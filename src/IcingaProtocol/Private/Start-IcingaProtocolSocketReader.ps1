<#
.SYNOPSIS
Starts a background loop that reads JSON-RPC framed messages from an established TCP/SSL connection and queues them for worker processing.

.DESCRIPTION
Start-IcingaProtocolSocketReader initializes and manages reading from a provided System.Net.Sockets.TcpClient. It validates and registers the TCP client in the module's global connection state, spawns a heartbeat sender thread, optionally sends an initial Hello when acting as a client, and then continuously reads from the associated SSL stream. Incoming data is assembled into framed JSON-RPC messages (using a length-prefixed framing scheme), complete messages are enqueued for worker processing, and partial messages are preserved between reads. The reader loop runs until the TCP connection becomes invalid or an unrecoverable read error occurs; on exit, the connection is closed and the reader thread is stopped.

.PARAMETER Client
| Name   | Type                         | Description                                                               | Default |
|--------|------------------------------|---------------------------------------------------------------------------|---------|
| Client | System.Net.Sockets.TcpClient | Established TCP connection to read from. Required; null causes early exit. | $null   |

.PARAMETER Endpoint
| Name     | Type          | Description                                                                     | Default |
|----------|---------------|---------------------------------------------------------------------------------|---------|
| Endpoint | System.String | Endpoint name used for SSL authentication with the IcingaProtocol certificate.  | $null   |

.PARAMETER IsClient
| Name     | Type                                             | Description                                                          | Default |
|----------|--------------------------------------------------|----------------------------------------------------------------------|---------|
| IsClient | System.Management.Automation.SwitchParameter     | When set, the reader sends an initial Hello after TLS handshake.     | $false  |

.OUTPUTS
None — Enqueues parsed JSON-RPC payloads for worker processing and updates global connection state.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolSocketReader' -Parameters @{ '-Client' = $client } -Start

Starts the socket reader for an accepted TcpClient in server role.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolSocketReader' -Parameters @{ '-Client' = $client; 'IsClient' = $true; 'Endpoint' = 'icinga-master' } -Start

Starts the socket reader for an outbound client connection and sends the initial Hello.

.NOTES
Updates global state under $Global:IcingaForWindows.Private.TCP (client, stream, LastWorkerId).
Uses a 4096-byte read buffer per iteration. Partial frames are accumulated and passed back
to Read-IcingaRPCMessage on subsequent reads. Heartbeat and writer threads are started via
New-Thread before the read loop begins.

#>
function Start-IcingaProtocolSocketReader()
{
    param (
        [System.Net.Sockets.TcpClient]$Client = $null,
        [string]$Endpoint                     = $null,
        [switch]$IsClient                     = $false
    );

    # Validate parameters
    if ($null -eq $Client) {
        Write-LoggingEntry -Message 'Please provide a valid TcpClient to read from' -Level 'Error';
        # Stop the current thread
        Stop-Thread -ThreadId (Get-ThreadId);
        return;
    }

    # Make sure we set the Icinga Protocol certificate for this thread instance
    $Global:IcingaForWindows.Private.TCP.Certificate = $Global:IcingaForWindows.Public.IcingaProtocol.Certificate;

    # Update the global TCP client and stream for reading
    if ((Update-TCPConnection -Client $Client -Endpoint $Endpoint -IsClient:$IsClient) -ne $Global:IcingaForWindows.Public.ReturnCodes.TlsHandshakeSuccessful.Code) {
        # Stop the current thread
        Stop-Thread -ThreadId (Get-ThreadId);
        return;
    }

    # First check if we have a valid connection
    if (-not (Test-TCPConnection)) {
        Write-LoggingEntry -Message 'A client is not connected which should not be present' -Level 'Error';
        # Stop the current thread
        Stop-Thread -ThreadId (Get-ThreadId);
        return;
    }

    # Start the heartbeat sender in a separate thread
    New-Thread -Command 'Start-IcingaProtocolHeartbeat' -Parameters @{
        '-TcpClient' = $Global:IcingaForWindows.Private.TCP.Client;
        '-SslStream' = $Global:IcingaForWindows.Private.TCP.Stream;
    } -Start;

    # Start the writer thread for this connection
    New-Thread -Command 'Start-IcingaProtocolSocketWriter' -Parameters @{
        '-TcpClient' = $Global:IcingaForWindows.Private.TCP.Client;
        '-SslStream' = $Global:IcingaForWindows.Private.TCP.Stream;
    } -Start -WaitForJobs;

    # If this is a client connection, send the initial Hello message
    if ($IsClient) {
        Send-IcingaProtocolHello;
    }

    # Create read buffer and variables
    $Global:IcingaForWindows.Private.TCP.LastWorkerId = -1;
    [int]$BufferSize                                  = 4096;
    [string]$JSONRPCMessage                           = '';

    # Start reading from the socket as long as the connection is valid
    while (Test-ThreadRunning -CheckTcpConnection) {
        try {
            $StartRead  = (Get-IcingaUnixTime -Milliseconds);
            # Read data from the SSL stream if available
            if ($Global:IcingaForWindows.Private.TCP.Stream.CanRead -and $Global:IcingaForWindows.Private.TCP.Client.GetStream().DataAvailable) {

                # Prepare read buffer and read data
                [byte[]]$bytes          = New-Object byte[] $BufferSize;
                $ReadBytes              = $Global:IcingaForWindows.Private.TCP.Stream.Read($bytes, 0, $BufferSize);
                # Prepare the actual read buffer and variables
                [byte[]]$RealBuffersize = New-Object byte[] $ReadBytes;
                [array]::Copy($bytes, 0, $RealBuffersize, 0, $ReadBytes);
                # Expand the JSONRPCMessage with the newly read data
                [string]$JSONRPCMessage += [System.Text.Encoding]::UTF8.GetString($RealBuffersize);

                # Now we the entire message and properly parse it
                $JSONRPCMessage = Read-IcingaRPCMessage -JSONRPCMessage $JSONRPCMessage;
                continue;
            }
        } catch {
            Write-LoggingEntry -Message "Error reading from SSL stream" -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; };
            break;
        }
    }
}

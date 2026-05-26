<#
.SYNOPSIS
Starts a recurring heartbeat sender over an established TCP/TLS connection to keep the remote endpoint alive and detect disconnects.

.DESCRIPTION
Start-IcingaProtocolHeartbeat validates and registers a provided System.Net.Sockets.TcpClient and System.Net.Security.SslStream for use by the Icinga protocol heartbeat subsystem, then enters a loop that periodically sends heartbeat messages until the TCP connection is lost. The function logs connection loss and other exceptions, closes the TCP connection when the client disconnects, and stops the current Icinga thread.

This function relies on helper functions from the IcingaForWindows module (for example: Set-TCPClientAndStream, Test-TCPConnection, Send-IcingaProtocolHeartbeat, Close-TCPConnection, Stop-Thread, Get-ThreadId and Write-LoggingEntry) to perform its work. It is intended to be used after a successful connection handshake and when you have an active SslStream wrapped around a TcpClient.

.PARAMETER TcpClient
| Name      | Type                         | Description                                                               | Default |
|-----------|------------------------------|---------------------------------------------------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Connected TCP client representing the remote endpoint. Required.          | $null   |

.PARAMETER SslStream
| Name      | Type                            | Description                                                              | Default |
|-----------|---------------------------------|--------------------------------------------------------------------------|---------|
| SslStream | System.Net.Security.SslStream   | SSL/TLS stream wrapping the network stream for secure communication. Required. | $null   |

.OUTPUTS
None — Sends heartbeat messages, writes log entries, closes the connection and stops
the current thread when the connection terminates.

.EXAMPLE
PS> Start-IcingaProtocolHeartbeat -TcpClient $tcp -SslStream $stream

Starts the heartbeat loop for an established TcpClient and its authenticated SslStream.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolHeartbeat' -Parameters @{ '-TcpClient' = $tcp; '-SslStream' = $stream } -Start

Starts the heartbeat in a dedicated background thread using the module thread helper.

.NOTES
The function returns immediately with an error log entry if either parameter is null.
Heartbeats are sent once per second while Test-ThreadRunning -CheckTcpConnection returns
true. MethodInvocationException during send is logged at Info level as a connection loss
event. After the loop exits, the TCP connection is closed and the current thread is stopped
via Stop-Thread.
#>
function Start-IcingaProtocolHeartbeat()
{
    param (
        [System.Net.Sockets.TcpClient]$TcpClient  = $null,
        [System.Net.Security.SslStream]$SslStream = $null
    );

    # Validate parameters
    if ($null -eq $TcpClient -or $null -eq $SslStream) {
        Write-LoggingEntry -Message 'Please provide a valid TcpClient and SslStream to send heartbeats' -Level 'Error';
        # Stop the current thread
        Stop-Thread -ThreadId (Get-ThreadId);
        return;
    }

    # Set the global TCP client and stream for heartbeat sending
    Set-TCPClientAndStream -TcpClient $TcpClient -SslStream $SslStream;

    # Get the remote address for logging
    [string]$RemoteAddress = $TcpClient.Client.RemoteEndPoint.Address.ToString();

    while (Test-ThreadRunning -CheckTcpConnection) {
        try {
            # Send a heartbeat message to keep the connection alive or check its status
            Send-IcingaProtocolHeartbeat;
        } catch [System.Management.Automation.MethodInvocationException] {
            # Handle connection lost during heartbeat sending
            Write-LoggingEntry -Message 'Connection to remote endpoint was lost while sending heartbeat' -Level 'Info' -Data @{ 'RemoteAddress' = $RemoteAddress };
        } catch {
            # Handle other exceptions
            Write-LoggingEntry -Message 'Exception caught while sending Heartbeat message' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; 'ExceptionType' = $_.Exception.GetType().FullName; };
        }
        # Wait before sending the next heartbeat
        Start-Sleep -Seconds 1;
    }
}

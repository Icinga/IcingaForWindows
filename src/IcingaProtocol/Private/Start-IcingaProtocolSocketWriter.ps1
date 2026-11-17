<#
.SYNOPSIS
Drains the per-endpoint writer queue and sends each message over the SSL stream.

.DESCRIPTION
Start-IcingaProtocolSocketWriter registers a BlockingCollection entry in
$Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue keyed by the remote
endpoint IP address and then enters a blocking loop that takes messages from that
queue and forwards them via Send-TCPMessage. The function validates TcpClient and
SslStream on entry and stops the current thread if either is null or the TCP
connection is no longer valid. On a disposed writer queue the current thread is
stopped and the function exits cleanly after the loop. On any other dequeue error
the exception is logged and the loop continues. The function is intended to run in
a dedicated background thread spawned
by Start-IcingaProtocolSocketReader.

.PARAMETER TcpClient
| Name      | Type                         | Description                                                             | Default |
|-----------|------------------------------|-------------------------------------------------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Connected TCP client whose remote endpoint identifies the writer queue. | $null   |

.PARAMETER SslStream
| Name      | Type                          | Description                                                      | Default |
|-----------|-------------------------------|------------------------------------------------------------------|---------|
| SslStream | System.Net.Security.SslStream | Authenticated SSL stream used by Send-TCPMessage to write bytes. | $null   |

.OUTPUTS
None -- Dequeues and sends messages; no pipeline output.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolSocketWriter' -Parameters @{ '-TcpClient' = $tcp; '-SslStream' = $stream } -Start -WaitForJobs

Starts the writer thread and waits until its queue entry is registered before continuing.

.NOTES
The writer queue entry for the endpoint is created inside this function using a
ConcurrentQueue-backed BlockingCollection. The WaitForJobs flag on New-Thread ensures the
queue slot exists before the first message is enqueued by other threads.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Start-IcingaProtocolSocketWriter()
{
    param (
        [System.Net.Sockets.TcpClient]$TcpClient  = $null,
        [System.Net.Security.SslStream]$SslStream = $null
    );

    # Validate parameters
    if ($null -eq $TcpClient) {
        Write-LoggingEntry -Message 'Please provide a valid TcpClient to write to' -Level 'Error';
        # Stop the current thread
        Stop-Thread -ThreadId (Get-ThreadId);
        return;
    }

    Set-TCPClientAndStream -TcpClient $TcpClient -SslStream $SslStream;

    # First check if we have a valid connection
    if (-not (Test-TCPConnection)) {
        Write-LoggingEntry -Message 'A client is not connected which should not be present' -Level 'Error';
        # Stop the current thread
        Stop-Thread -ThreadId (Get-ThreadId);
        return;
    }

    $Endpoint = $TcpClient.Client.RemoteEndPoint.Address.ToString();

    if ([string]::IsNullOrEmpty($Endpoint)) {
        Write-LoggingEntry -Message 'Failed to retrieve the remote endpoint address' -Level 'Error';
        # Stop the current thread
        Stop-Thread -ThreadId (Get-ThreadId);
        return;
    }

    if ($null -ne $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue.$Endpoint) {
        # Clear out any remaining messages in the queue
        $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue.$Endpoint.Dispose();
        $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue.$Endpoint = $null;
        [void]($Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue.PSObject.Properties.Remove($Endpoint));
    }

    $MyQueue = New-Object System.Collections.Concurrent.BlockingCollection[PSObject] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[PSObject]);

    $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue | Add-Member -MemberType NoteProperty `
        -Name $Endpoint `
        -Value $MyQueue `
        -Force;

    # Start reading from the socket as long as the connection is valid
    while (Test-ThreadRunning -CheckTcpConnection -NoSleep) {
        try {
            $TcpMessage = $null;
            if (-not $MyQueue.TryTake([ref]$TcpMessage, 10000)) {
                Set-ThreadProcessing;
                continue;
            }

            Set-ThreadProcessing;

            if ($null -eq $TcpMessage) {
                continue; # No message to process, loop again
            }

            $EncodedMessage = [System.Text.Encoding]::UTF8.GetString($TcpMessage.message);

            Write-LoggingEntry -Message 'Sending message to Icinga endpoint' -Level 'Debug' -Data @{ 'Endpoint' = $Endpoint; 'Message' = $EncodedMessage; };

            Send-TCPMessage -MsgObj $TcpMessage;
        } catch {
            # A disposed writer queue (replaced by a new writer instance for the same endpoint or
            # disposed during shutdown) makes TryTake throw an ObjectDisposedException, which
            # PowerShell wraps in a RuntimeException. The queue is gone permanently in that case,
            # so stop this thread and let the function run to its natural end instead of looping.
            if ($null -ne $_.Exception.InnerException -and $_.Exception.InnerException -is [System.ObjectDisposedException] -and $_.Exception.Message -like '*TryTake*') {
                Write-LoggingEntry -Message 'Writer queue disposed, stopping writer thread' -Level 'Info' -Data @{ 'Endpoint' = $Endpoint; };
                # Stop the current thread
                Stop-Thread -ThreadId (Get-ThreadId);
                break;
            }

            Write-LoggingEntry -Message 'Caught exception in Icinga Protocol Socket Writer' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; 'Endpoint' = $Endpoint; };
        } finally {
            $TcpMessage     = $null;
            $EncodedMessage = $null;
        }
    }

    if (-not [string]::IsNullOrEmpty($Endpoint) -and $null -ne $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue) {
        if ($null -ne $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue.$Endpoint) {
            # Only dispose and remove the queue if it is STILL our queue!
            # (Prevents a dying thread from deleting the queue of a newly established connection)
            if ($Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue.$Endpoint -eq $MyQueue) {
                try {
                    $MyQueue.Dispose();
                } catch {
                    $MyQueue = $null;
                }
                $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue.PSObject.Properties.Remove($Endpoint) | Out-Null;
            }
        }
    }
}

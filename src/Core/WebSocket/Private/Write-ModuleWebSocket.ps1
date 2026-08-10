<#
.SYNOPSIS
Dequeue messages and send them over the active WebSocket.

.DESCRIPTION
`Write-ModuleWebSocket` continuously reads messages from the named
WebSocket writer queue and sends them to the remote endpoint using the
active `ClientWebSocket`. The function retries queueing when the socket
is not connected and emits structured return values on errors.

.PARAMETER Name
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection to write to | |

.PARAMETER ClientWebSocket
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | Active client WebSocket instance | |

.PARAMETER CancellationTokenSource
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Token source used to cancel send operations | |

.OUTPUTS
System.Object — Emits structured `Write-FunctionReturnValue` values on send errors.

.EXAMPLE
PS> Write-ModuleWebSocket -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts
#>
function Write-ModuleWebSocket()
{
    param (
        [string]$Name                                                      = $null,
        [System.Net.WebSockets.ClientWebSocket]$ClientWebSocket            = $null,
        [System.Threading.CancellationTokenSource]$CancellationTokenSource = $null
    );

    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ((Update-ModuleWebSocketThread -Name $Name -ClientWebSocket $ClientWebSocket -CancellationTokenSource $CancellationTokenSource) -ne $GlobalVariable.Public.ReturnCodes.WebSocketUpdatedSuccessfully.Code) {
        return;
    }

    [string]$WebSocketName = $GlobalVariable.Private.WebSocket.Name;

     # If the WebSocket is not open, we don't need to proceed and close the thread
    while (Test-ThreadRunning -CheckWebSocket) {
        try {
            [string]$WebSocketMessage = $null;
            if (-not $GlobalVariable.Public.WebSocket.$WebSocketName.WriterWorker.TryTake([ref]$WebSocketMessage, 10000)) {
                Set-ThreadProcessing;
                continue;
            }
            Set-ThreadProcessing;

            # Just continue if the WebSocket is not connected, as the
            # Test-ThreadRunning will take care of stopping the thread
            # We just need to check here, as it could have taken longer to accept a message
            # and we wanted to send something, but it failed in the meantime
            if (-not (Test-ModuleWebSocket)) {
                # Re-add the message back to the queue for later processing
                $GlobalVariable.Public.WebSocket.$WebSocketName.WriterWorker.Add($WebSocketMessage) | Out-Null;
                continue;
            }

            # Prevent sending empty messages
            if ([string]::IsNullOrEmpty($WebSocketMessage)) {
                continue;
            }

            # This is just a test message to keep the write thread alive and can be ignored
            if ($WebSocketMessage -eq 'WebSocket::CoreTestWriteObject') {
                continue;
            }

            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($WebSocketMessage);

            [ArraySegment[byte]]$SocketMsg = $Bytes;

            $RequestProgress = $GlobalVariable.Private.WebSocket.ClientWebSocket.SendAsync(
                $SocketMsg,
                [System.Net.WebSockets.WebSocketMessageType]::Text,
                $TRUE,
                $GlobalVariable.Private.WebSocket.CancellationTokenSource.Token
            );

            While ($RequestProgress.IsCompleted -eq $FALSE) {
                Start-Sleep -Milliseconds 10;
            }

            # Clear our request progress which would otherwise cause a memory leak as in case we
            # cannot establish a connection to the remote server, this function is called frequently
            # and will then cause endless request progress states to be created
            $RequestProgress.Dispose();
            $RequestProgress = $null;
        } catch {
            Write-FunctionReturnValue -ReturnValue 'WebSocketWriteError' -Data @{ 'Name' = $WebSocketName; 'Exception' = $_.Exception } | Out-Null;
        }
    };
}

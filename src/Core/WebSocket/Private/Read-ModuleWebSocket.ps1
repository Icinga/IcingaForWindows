<#
.SYNOPSIS
Read messages from an open WebSocket and enqueue them for processing.

.DESCRIPTION
`Read-ModuleWebSocket` continuously reads messages from the active
`ClientWebSocket`, converts the received bytes into UTF8 strings and
pushes complete messages to the configured reader worker queue for the
connection name. It updates thread processing state and handles
exceptions by emitting structured module return values.

.PARAMETER Name
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection | |

.PARAMETER ClientWebSocket
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | The active client WebSocket instance | |

.PARAMETER CancellationTokenSource
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Token source used to cancel read operations | |

.OUTPUTS
System.Object — Emits structured `Write-FunctionReturnValue` values on errors;
otherwise received messages are placed into the named reader worker queue for
downstream processing.

.EXAMPLE
PS> Read-ModuleWebSocket -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts

.NOTES
This function is designed to run inside a dedicated worker thread spawned by
`Start-ModuleWebSocketHandler`. It stores connection references via
`Update-ModuleWebSocketThread` into `$Global:ModuleName.Private.WebSocket` and
reads from the `ClientWebSocket` in a blocking loop. Received messages are
placed in the `ReaderWorker` BlockingCollection under
`$Global:ModuleName.Public.WebSocket.<Name>`. The loop runs until
`Test-ThreadRunning -CheckWebSocket` returns `$false`.
#>
function Read-ModuleWebSocket()
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

    # If the WebSocket is not open, we don't need to proceed
    while (Test-ThreadRunning -CheckWebSocket) {
        try {
            $WebSocketBuffer    = [Net.WebSockets.WebSocket]::CreateClientBuffer(2048, 2048);
            $ResponseMsg        = '';
            [bool]$EndOfMessage = $false;

            # Loop this to ensure we receive the full message, as WebSocket messages can be fragmented and we need to wait until we received the full message before we can process it
            do {
                $RequestProgress = $GlobalVariable.Private.WebSocket.ClientWebSocket.ReceiveAsync(
                    $WebSocketBuffer,
                    $GlobalVariable.Private.WebSocket.CancellationTokenSource.Token
                );

                # Wait for the read to complete, also this waits for a message to be available
                While ((Test-ModuleWebSocket) -And $RequestProgress.IsCompleted -eq $FALSE) {
                    Start-Sleep -Milliseconds 10; 
                }

                # Set this thread as processing to avoid being killed by the thread manager, once we received a message
                Set-ThreadProcessing;

                $ResponseMsg += ([System.Text.Encoding]::UTF8.GetString($WebSocketBuffer, 0, $RequestProgress.Result.Count));
                [bool]$EndOfMessage = $RequestProgress.Result.EndOfMessage;
            } while (-not $EndOfMessage -and (Test-ModuleWebSocket));

            # Clear our request progress which would otherwise cause a memory leak as in case we
            # cannot establish a connection to the remote server, this function is called frequently
            # and will then cause endless request progress states to be created
            $RequestProgress.Dispose();
            $RequestProgress = $null;

            # Log the received message for debugging purposes
            Write-LoggingEntry -Message 'Received WebSocket message' -Data @{ 'Name' = $WebSocketName; 'Message' = $ResponseMsg; } -Severity 'Debug' | Out-Null;

            # Push the received message to the reader worker queue
            $GlobalVariable.Public.WebSocket.$WebSocketName.ReaderWorker.Add([string]($ResponseMsg)) | Out-Null;
        } catch {
            Write-FunctionReturnValue -ReturnValue 'WebSocketReadError' -Data @{ 'Name' = $WebSocketName; 'Exception' = $_.Exception } | Out-Null;
        }

        $WebSocketBuffer = $null;
        $ResponseMsg     = $null;
    }
}

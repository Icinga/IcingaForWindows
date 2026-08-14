<#
.SYNOPSIS
Worker loop: dequeue WebSocket messages and dispatch by type.

.DESCRIPTION
`Start-ModuleWebSocketReaderWorker` consumes messages from the named
WebSocket reader queue, converts them into message objects depending on the
WebSocket type (for example MyWebSocket), and augments them with
`Origin` metadata for downstream processing. The worker runs until the thread
manager requests shutdown.

.PARAMETER Name
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection to read from | |

.PARAMETER ClientWebSocket
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | Active client WebSocket instance | |

.PARAMETER CancellationTokenSource
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Cancellation token source used to cancel operations | |

.OUTPUTS
System.Object — Emits structured module return values on errors; otherwise
messages are prepared and enqueued for further processing.

.EXAMPLE
PS> Start-ModuleWebSocketReaderWorker -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts
#>
function Start-ModuleWebSocketReaderWorker()
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

    [string]$WebSocketName   = $GlobalVariable.Private.WebSocket.Name;
    [string]$WebSocketType   = $GlobalVariable.Public.WebSocket.Config.$WebSocketName.Type;
    # [string]$WebSocketConfig = $GlobalVariable.Public.WebSocket.Config.$WebSocketName.Config;

     # If the WebSocket is not open, we don't need to proceed and close the thread
    while (Test-ThreadRunning -CheckWebSocket) {
        try {
            [string]$WebSocketMessage = $null;
            if (-not $GlobalVariable.Public.WebSocket.$WebSocketName.ReaderWorker.TryTake([ref]$WebSocketMessage, 10000)) {
                Set-ThreadProcessing;
                continue;
            }
            Set-ThreadProcessing;

            # Just continue if the WebSocket is not connected, as the
            # Test-ThreadRunning will take care of stopping the thread
            # We just need to check here, as it could have taken longer to accept a message
            # and we wanted to send something, but it failed in the meantime
            if (-not (Test-ModuleWebSocket)) {
                continue;
            }

            # Prevent reading empty messages
            if ([string]::IsNullOrEmpty($WebSocketMessage)) {
                continue;
            }

            # This is just a test message to keep the write thread alive and can be ignored
            if ($WebSocketMessage -eq 'WebSocket::CoreTestWriteObject') {
                continue;
            }

            [PSCustomObject]$MessageObj = $null;

            # TODO: We should make this dynamic with a configuration instead of hardcoding
            switch ($WebSocketType) {
                <#'ExampleWebSocketType' {
                    $MessageObj = Invoke-ExampleWebSocket -Message $WebSocketMessage;
                    break;
                };#>
                default {
                    Write-LoggingEntry -Message 'Start-ModuleWebSocketReaderWorker: Unknown WebSocket type, cannot process incoming message' -Level 'Warning' -Data @{ 'WebSocketType' = $WebSocketType; 'Name' = $WebSocketName; };
                    break;
                };
            };

            # If for some reason the message object is null, we just continue
            if ($null -eq $MessageObj) {
                continue;
            }

            # If we have a valid message object, we can add metadata about the origin to make it easier to process later on
            $MessageObj | Add-Member -MemberType NoteProperty -Name 'Origin' -Value (
                [PSCustomObject]@{
                    'Source' = 'WebSocket';
                    'Name'   = $WebSocketName;
                    'Type'   = $WebSocketType;
                }
            ) -Force;

            # TODO: We should make this dynamic with a configuration instead of hardcoding
            # Add-ExampleDataToWorker -Message $MessageObj;
        } catch {
            Write-FunctionReturnValue -ReturnValue 'WebSocketWriteError' -Data @{ 'Name' = $WebSocketName; 'Exception' = $_.Exception } | Out-Null;
        }
    };
}

<#
.SYNOPSIS
Close and dispose the active WebSocket connection.

.DESCRIPTION
`Disconnect-ModuleWebSocket` attempts a graceful close of the active
`ClientWebSocket` then disposes runtime resources. It returns structured
module results for success, not-connected, and various error conditions.

.OUTPUTS
System.Object — Structured `Write-FunctionReturnValue` values describing the outcome.

.EXAMPLE
PS> Disconnect-ModuleWebSocket

.NOTES
This function is safe to call even when no connection exists. It ensures cleanup
of any lingering `ClientWebSocket` and `CancellationTokenSource` objects to
avoid memory leaks. The function accesses runtime state via
`Get-GlobalRuntimeVariable`.
#>
function Disconnect-ModuleWebSocket()
{
    # First try to close the WebSocket connection gracefully
    try {
        $GlobalVariable = Get-GlobalRuntimeVariable;

        if (Test-ModuleWebSocket) {
            $CancelTokenSource = $GlobalVariable.Private.WebSocket.CancellationTokenSource;
            $CancelTokenSource.Cancel();

            $CloseProgress = $GlobalVariable.Private.WebSocket.ClientWebSocket.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                'Closing WebSocket connection',
                [System.Threading.CancellationToken]::None
            );

            # Wait until we closed the connection
            While ($CloseProgress.IsCompleted -eq $FALSE) {
                Start-Sleep -Milliseconds 10;
            }

            # Clear our close progress to avoid memory leaks
            $CloseProgress.Dispose();
            $CloseProgress = $null;
            $GlobalVariable.Private.WebSocket.ClientWebSocket.Dispose();
            $GlobalVariable.Private.WebSocket.ClientWebSocket         = $null;
            $GlobalVariable.Private.WebSocket.CancellationTokenSource.Dispose();
            $GlobalVariable.Private.WebSocket.CancellationTokenSource = $null;

            return (Write-FunctionReturnValue -ReturnValue 'WebSocketDisconnectedSuccessfully' -Data @{ 'Name' = $GlobalVariable.Private.WebSocket.Name; } );
        }

        return (Write-FunctionReturnValue -ReturnValue 'WebSocketNotConnected' -Data @{ 'Name' = $GlobalVariable.Private.WebSocket.Name; } );
    } catch {
        Write-FunctionReturnValue -ReturnValue 'WebSocketDisconnectError' -Data @{ 'Exception' = $_.Exception; 'Name' = $GlobalVariable.Private.WebSocket.Name; } | Out-Null;
    }

    # Ensure all resources are cleaned up
    try {
        if ($null -ne $GlobalVariable.Private.WebSocket.ClientWebSocket) {
            $GlobalVariable.Private.WebSocket.ClientWebSocket.Dispose();
            $GlobalVariable.Private.WebSocket.ClientWebSocket         = $null;
        }

        if ($null -ne $GlobalVariable.Private.WebSocket.CancellationTokenSource) {
            $GlobalVariable.Private.WebSocket.CancellationTokenSource.Dispose();
            $GlobalVariable.Private.WebSocket.CancellationTokenSource = $null;
        }

        return (Write-FunctionReturnValue -ReturnValue 'WebSocketDisposedSuccessfully' -Data @{ 'Exception' = $_.Exception; 'Name' = $GlobalVariable.Private.WebSocket.Name; });
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketDisposeError' -Data @{ 'Exception' = $_.Exception; 'Name' = $GlobalVariable.Private.WebSocket.Name; });
    }
}

<#
.SYNOPSIS
Update the global WebSocket thread state for the current runtime.

.DESCRIPTION
`Update-ModuleWebSocketThread` stores the active WebSocket thread values
(`Name`, `ClientWebSocket`, `CancellationTokenSource`) in
`$Global:ModuleName.Private.WebSocket` so other WebSocket helper threads can
access the current connection reference.

.PARAMETER Name
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection | |

.PARAMETER ClientWebSocket
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | Active client WebSocket instance | |

.PARAMETER CancellationTokenSource
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Cancellation token source used to cancel reads/writes | |

.OUTPUTS
System.Object — Returns structured `Write-FunctionReturnValue` status codes indicating success or validation failures.

.EXAMPLE
PS> Update-ModuleWebSocketThread -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts
#>
function Update-ModuleWebSocketThread()
{
    param (
        [string]$Name                                                      = $null,
        [System.Net.WebSockets.ClientWebSocket]$ClientWebSocket            = $null,
        [System.Threading.CancellationTokenSource]$CancellationTokenSource = $null
    );

    if ([string]::IsNullOrEmpty($Name)) {
        return (Write-FunctionReturnValue -ReturnValue 'UpdateWebSocketNameEmpty');
    }

    if ($null -eq $ClientWebSocket) {
        return (Write-FunctionReturnValue -ReturnValue 'UpdateWebSocketClientEmpty' -Data @{ 'Name' = $Name; } );
    }

    if ($null -eq $CancellationTokenSource) {
        return (Write-FunctionReturnValue -ReturnValue 'UpdateWebSocketCancellationTokenSourceEmpty' -Data @{ 'Name' = $Name; } );
    }

    $GlobalVariable                                           = Get-GlobalRuntimeVariable;
    $GlobalVariable.Private.WebSocket.Name                    = $Name;
    $GlobalVariable.Private.WebSocket.ClientWebSocket         = $ClientWebSocket;
    $GlobalVariable.Private.WebSocket.CancellationTokenSource = $CancellationTokenSource;

    return (Write-FunctionReturnValue -ReturnValue 'WebSocketUpdatedSuccessfully' -Data @{ 'Name' = $Name; } );
}

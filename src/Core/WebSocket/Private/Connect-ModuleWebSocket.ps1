<#
.SYNOPSIS
Establish a new ClientWebSocket connection and register it in runtime state.

.DESCRIPTION
`Connect-ModuleWebSocket` connects to a remote WebSocket URI using
`System.Net.WebSockets.ClientWebSocket`, initializes cancellation token
sources and stores the resulting objects in the private runtime state for
use by reader/writer workers. It validates parameters and returns structured
module return values.

.PARAMETER Name
| Name | Type         | Description                          | Default |
|------|--------------|--------------------------------------|---------|
| Name | System.String| Logical name for the WebSocket entry.|         |

.PARAMETER Address
| Name    | Type         | Description                               | Default |
|---------|--------------|-------------------------------------------|---------|
| Address | System.String| WebSocket URI to connect to.              |         |

.OUTPUTS
System.Object — Emits `Write-FunctionReturnValue` results describing success or failure.

.EXAMPLE
PS> Connect-ModuleWebSocket -Name 'MyWebSocket' -Address 'wss://example.com'

.NOTES
Any existing connection is cleaned up via `Disconnect-ModuleWebSocket` before a
new one is established. The resulting `ClientWebSocket` and
`CancellationTokenSource` are stored in `$Global:ModuleName.Private.WebSocket`
and must be accessed via `Get-GlobalRuntimeVariable` from worker threads.
#>
function Connect-ModuleWebSocket()
{
    param (
        [string]$Name    = '',
        [string]$Address = ''
    );

    if ([string]::IsNullOrEmpty($Name)) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketNameEmpty');
    }

    if ([string]::IsNullOrEmpty($Address)) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketAddressEmpty');
    }

    # First test if we are already connected
    if (Test-ModuleWebSocket) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketAlreadyOpened' -Data @{ 'Name' = $Name; 'Address' = $Address });
    }

    Write-LoggingEntry -Message 'Trying to establish WebSocket connection' -Data @{ 'Name' = $Name; 'Address' = $Address; } -Severity 'debug' | Out-Null;

    # Ensure we always dispose or disconnect any existing WebSocket connection
    # Just ensures proper cleanup
    Disconnect-ModuleWebSocket | Out-Null;

    $GlobalVariable    = Get-GlobalRuntimeVariable;
    # [IcingaIgnoreDisposeCheck]
    $WebSocketClient   = New-Object System.Net.WebSockets.ClientWebSocket;
    # [IcingaIgnoreDisposeCheck]
    $CancelTokenSource = New-Object System.Threading.CancellationTokenSource;
    $RequestProgress   = $WebSocketClient.ConnectAsync($Address, $CancelTokenSource.Token);

    # Wait until we received a response
    While ($RequestProgress.IsCompleted -eq $FALSE) {
        Start-Sleep -Milliseconds 10;
    }

    # Clear our request progress which would otherwise cause a memory leak as in case we
    # cannot establish a connection to the remote server, this function is called frequently
    # and will then cause endless request progress states to be created
    $RequestProgress.Dispose();
    $RequestProgress = $null;

    $GlobalVariable.Private.WebSocket.Name                    = $Name;
    $GlobalVariable.Private.WebSocket.ClientWebSocket         = $WebSocketClient;
    $GlobalVariable.Private.WebSocket.CancellationTokenSource = $CancelTokenSource;

    return (Write-FunctionReturnValue -ReturnValue 'WebSocketCreatedSuccessfully' -Data @{ 'Name' = $Name; 'Address' = $Address });
}

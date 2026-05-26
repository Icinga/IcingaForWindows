<#
.SYNOPSIS
Return the WebSocket configuration object for the current thread.

.DESCRIPTION
`Get-ModuleCurrentWebSocketConfig` determines which WebSocket instance is
assigned to the calling thread (via `$Global:ModuleName.Private.WebSocket.Name`) and
returns the corresponding configuration object stored in
`$Global:ModuleName.Public.WebSocket.Config`. If no name or config is found the
function returns `$null`.

.OUTPUTS
System.Management.Automation.PSCustomObject — Returns the WebSocket configuration
object for the current thread, or `$null` when no configuration is available.

.EXAMPLE
PS> Get-ModuleCurrentWebSocketConfig

.NOTES
Relies on global state populated by WebSocket management functions under
`Core\WebSocket`. Typical consumers are reader and handler threads that need
access to the current connection credentials and settings. The thread-local
WebSocket name is read from `$Global:ModuleName.Private.WebSocket.Name` via
`Get-GlobalRuntimeVariable`.
#>
function Get-ModuleCurrentWebSocketConfig()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;
    # First get the name of the WebSocket assigned for the thread this function is called from
    [string]$Name   = $GlobalVariable.Private.WebSocket.Name;

    # If there is no WebSocket name, return null
    if ([string]::IsNullOrEmpty($Name)) {
        return $null;
    }

    # If there is no config for this WebSocket, return null
    if ($null -eq $GlobalVariable.Public.WebSocket.Config.$Name) {
        return $null;
    }

    # Now get the config object for this WebSocket from the global config
    [PSCustomObject]$WebSocketConfig = $GlobalVariable.Public.WebSocket.Config.$Name.Config;

    return $WebSocketConfig;
}

<#
.SYNOPSIS
Remove a persisted WebSocket configuration file.

.DESCRIPTION
`Remove-ModuleWebSocketConfig` removes the persisted pointer file for a
named WebSocket configuration from the module config directory. It does
not modify in-memory runtime structures.

.PARAMETER Name
| Name | Type          | Description                                    | Default |
|------|---------------|------------------------------------------------|---------|
| Name | System.String | Logical name of the WebSocket config to remove |         |

.OUTPUTS
System.Object -- Emits a structured return value when no name is provided; otherwise it removes the file and returns quietly.

.EXAMPLE
PS> Remove-ModuleWebSocketConfig -Name 'MyWebSocket'

.NOTES
Removes the JSON configuration file from the `WebSocket` subfolder inside
`Get-ModuleConfigDirectory` via `Remove-SecureItem`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Remove-ModuleWebSocketConfig()
{
    param (
        [string]$Name = ''
    );

    # Ensure we specify a name for the role
    if ([string]::IsNullOrEmpty($Name)) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketConfigNoNameProvided');
    };

    # Remove invalid filename characters from the role name for file saving
    [string]$SafeName      = Remove-ModuleAmbitiousCharacters -InputString $Name -RemoveSpaces;
    [string]$WebSocketFile = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath ([string]::Format('WebSocket\{0}.json', $SafeName.ToLower()));

    # Remove the access role file
    Remove-SecureItem -Path $WebSocketFile | Out-Null;
}

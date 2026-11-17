<#
.SYNOPSIS
Remove a persisted WebSocket configuration file.

.DESCRIPTION
`Remove-IcingaWebSocketConfig` is the public wrapper for
`Remove-ModuleWebSocketConfig`. It removes the persisted pointer file for a
named WebSocket configuration from the Icinga config directory. The function
does not modify in-memory runtime structures; a running WebSocket environment
must be restarted separately to reflect the removal.

.PARAMETER Name
| Name | Type          | Description                                    | Default |
|------|---------------|------------------------------------------------|---------|
| Name | System.String | Logical name of the WebSocket config to remove |         |

.OUTPUTS
System.Object -- Emits a structured return value when no name is provided;
otherwise removes the file and returns quietly.

.EXAMPLE
PS> Remove-IcingaWebSocketConfig -Name 'MyWebSocket'

.NOTES
Only the persisted pointer file on disk is removed. The in-memory configuration
in `$Global:Icinga.Public.WebSocket.Config` is not modified. No special
permissions beyond write access to the Icinga config directory are required.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Remove-IcingaWebSocketConfig()
{
    param (
        [string]$Name = ''
    );

    Remove-ModuleWebSocketConfig -Name $Name;
}

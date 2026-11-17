<#
.SYNOPSIS
Register and persist a WebSocket configuration.

.DESCRIPTION
`Add-IcingaWebSocketConfig` is the public wrapper for `Add-ModuleWebSocketConfig`.
It validates a WebSocket configuration payload, stores it in the runtime
configuration (`$Global:Icinga.Public.WebSocket.Config`), and persists a pointer
file under the Icinga config directory. The function reads the referenced
type-specific config via `Read-ModuleConfigFile` and only writes a path pointer
to disk.

.PARAMETER Name
| Name | Type          | Description                           | Default |
|------|---------------|---------------------------------------|---------|
| Name | System.String | Logical name for the WebSocket config |         |

.PARAMETER Address
| Name    | Type          | Description                      | Default |
|---------|---------------|----------------------------------|---------|
| Address | System.String | Remote WebSocket URI (wss://...) |         |

.PARAMETER Config
| Name   | Type          | Description                                      | Default |
|--------|---------------|--------------------------------------------------|---------|
| Config | System.String | Path or pointer to the type-specific config file |         |

.PARAMETER Type
| Name | Type          | Description                           | Default |
|------|---------------|---------------------------------------|---------|
| Type | System.String | Logical type for the WebSocket config |         |

.PARAMETER Force
| Name  | Type                                         | Description                                     | Default |
|-------|----------------------------------------------|-------------------------------------------------|---------|
| Force | System.Management.Automation.SwitchParameter | Overwrite an existing config with the same name | $false  |

.OUTPUTS
System.Object -- Returns a structured Icinga return indicating success or the
validation failure.

.EXAMPLE
PS> Add-IcingaWebSocketConfig -Name 'MyWebSocket' -Address 'wss://mywebsocket.example.com:443' -Config 'configs\mywebsocket.json' -Type MyWebSocket

.NOTES
The persisted file under the Icinga config directory contains only the path
pointer to the type-specific config, not the full in-memory object. Requires
read access to the type-specific configuration file referenced by `Config`.
Configuration is stored in `$Global:Icinga.Public.WebSocket.Config`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Add-IcingaWebSocketConfig()
{
    param (
        [string]$Name    = $null,
        [string]$Address = $null,
        [string]$Config  = $null,
        [string]$Type    = $null,
        [switch]$Force   = $false
    );

    return (
        Add-ModuleWebSocketConfig -Name $Name -Address $Address -Config $Config -Type $Type -Force:$Force
    );
}

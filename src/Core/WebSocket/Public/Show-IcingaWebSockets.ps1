<#
.SYNOPSIS
Display the currently configured WebSocket endpoints.

.DESCRIPTION
`Show-IcingaWebSockets` is the public wrapper for `Show-ModuleWebSockets`. It
reads all WebSocket configurations from `$Global:Icinga.Public.WebSocket.Config`
and emits them as a formatted output message via `Write-LoggingEntry` at the
`Output` level. The function is intended for interactive inspection during
runtime and produces no return value.

.OUTPUTS
None -- Writes the WebSocket configurations as a formatted output entry via
`Write-LoggingEntry`.

.EXAMPLE
PS> Show-IcingaWebSockets

.NOTES
No parameters are required. The output is written through `Write-LoggingEntry`
and is not returned to the pipeline. Requires the WebSocket environment to have
been initialized via `Start-ModuleWebSocketDaemon` for meaningful output.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Show-IcingaWebSockets()
{
    Show-ModuleWebSockets;
}

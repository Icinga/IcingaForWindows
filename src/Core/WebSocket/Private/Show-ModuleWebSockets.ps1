<#
.SYNOPSIS
Display the currently configured WebSocket endpoints.

.DESCRIPTION
`Show-ModuleWebSockets` reads all WebSocket configurations from
`$Global:IcingaForWindows.Public.WebSocket.Config` via `Get-GlobalRuntimeVariable` and
emits them as a formatted output message using `Write-LoggingEntry` at the
`Output` level. The function is intended for interactive inspection during
runtime and produces no return value.

.OUTPUTS
None -- Writes the WebSocket configurations as a formatted output entry via
`Write-LoggingEntry`.

.EXAMPLE
PS> Show-ModuleWebSockets

.NOTES
Internal implementation behind the public `Show-IcingaWebSockets` cmdlet.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Show-ModuleWebSockets()
{
    Write-LoggingEntry -Message "`r`n=== $(Get-ModuleProjectName) WebSockets ===" -Level 'Output' -Data @{ 'WebSockets' = (Get-GlobalRuntimeVariable).Public.WebSocket.Config };
}

<#
.SYNOPSIS
Check whether the current WebSocket client is connected and open.

.DESCRIPTION
`Test-ModuleWebSocket` verifies that a `ClientWebSocket` exists in
`$Global:IcingaForWindows.Private.WebSocket` via `Get-GlobalRuntimeVariable` and
that its `State` equals `Open`. Returns a boolean value indicating whether the
WebSocket is connected.

.OUTPUTS
System.Boolean -- $true when the WebSocket connection is active and open; $false otherwise.

.EXAMPLE
PS> if (Test-ModuleWebSocket) { Write-LoggingEntry -Message 'WebSocket connected' -Level 'Output' }

.NOTES
Reads thread-local `Private.WebSocket.ClientWebSocket` state for the active
WebSocket worker runspace.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Test-ModuleWebSocket()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($null -eq $GlobalVariable.Private.WebSocket.ClientWebSocket) {
        return $FALSE;
    }

    if ($GlobalVariable.Private.WebSocket.ClientWebSocket.State -ne 'Open') {
        return $FALSE;
    }

    return $TRUE;
}

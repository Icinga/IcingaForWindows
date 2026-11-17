<#
.SYNOPSIS
Stop and release the TCP listener socket

.DESCRIPTION
`Close-TCPSocket` stops the active `TcpListener` (if any), logs the action
and clears the listener reference in the global runtime variable.

.OUTPUTS
None -- Stops the listener and clears its reference in the global state.

.EXAMPLE
PS> Close-TCPSocket

.NOTES
Requires privileges sufficient to stop the listener; exceptions are logged.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Close-TCPSocket()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($null -eq $GlobalVariable.Private.TCP.Listener) {
        return;
    }

    Write-LoggingEntry -Message 'Closing TCP socket' -Level 'Debug' -Data @{ 'LocalEndpoint' = $GlobalVariable.Private.TCP.Listener.LocalEndpoint };

    try {
        $GlobalVariable.Private.TCP.Listener.Stop();
    } catch {
        Write-LoggingEntry -Message 'Error closing TCP socket' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message };
    }

    $GlobalVariable.Private.TCP.Listener = $null;
}

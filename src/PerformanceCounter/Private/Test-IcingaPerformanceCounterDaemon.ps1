<#
.SYNOPSIS
Determine whether the performance counter daemon is currently alive

.DESCRIPTION
`Test-IcingaPerformanceCounterDaemon` checks the heartbeat timestamp the daemon refreshes
on every loop cycle. If the heartbeat is recent the daemon is considered alive and callers
route their reads through the request/response queue; otherwise `Get-IcingaPerformanceCounter`
falls back to a synchronous inline read. Using the heartbeat keeps the check decoupled from
the thread registry.

.OUTPUTS
System.Boolean -- $true when the daemon heartbeat is recent, otherwise $false.

.EXAMPLE
PS> if (Test-IcingaPerformanceCounterDaemon) { 'daemon is serving requests' }

.NOTES
The heartbeat lives at `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Heartbeat`.
A heartbeat older than five seconds is treated as not alive.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Test-IcingaPerformanceCounterDaemon()
{
    $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;

    if ($null -eq $Store) {
        return $false;
    }

    if ($null -eq $Store.Heartbeat) {
        return $false;
    }

    if (((Get-Date) - $Store.Heartbeat).TotalSeconds -gt 5) {
        return $false;
    }

    return $true;
}

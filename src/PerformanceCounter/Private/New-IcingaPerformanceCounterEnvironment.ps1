<#
.SYNOPSIS
Initialize the performance counter manager, cache and warm counter set

.DESCRIPTION
`New-IcingaPerformanceCounterEnvironment` prepares the performance-counter subsystem for
the daemon. It creates the central manager instance the first time it runs (the class type
is available because the kernel has been dot-sourced by then), loads the persisted cache,
runs component discovery to register statically declared counters, and reconciles the
manager so every registered counter is warmed in a single batch. It also stamps the initial
heartbeat and refresh timestamps.

This function is expected to run inside the performance-counter daemon runspace, before the
daemon enters its processing loop, so the manager is created and used on a single thread.

.OUTPUTS
None -- Populates `(Get-GlobalRuntimeVariable).Public.PerformanceCounter`.

.EXAMPLE
PS> New-IcingaPerformanceCounterEnvironment

.NOTES
All shared state is read through `Get-GlobalRuntimeVariable`. The manager is stored on the
`Manager` slot of the global store and is only ever touched by the daemon thread.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-IcingaPerformanceCounterEnvironment()
{
    $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;

    if ($null -eq $Store) {
        return;
    }

    # Create the central manager once the class type is available (post kernel load).
    # The class is looked up by name at runtime on purpose: the compiled kernel is shared
    # between runspaces, and on Windows PowerShell 5.1 a [IcingaPerformanceCounter] literal
    # in it yields the main runspace's class type inside the daemon runspace. Every manager
    # method then runs through the main runspace and stalls while the main thread waits for
    # the daemon's response. The runtime lookup returns this runspace's own class type.
    if ($null -eq $Store.Manager) {
        $Store.Manager                    = ('IcingaPerformanceCounter' -as [type])::new();
        $Store.Manager.WarmupMilliseconds = $Store.Config.WarmupMilliseconds;
    }

    # Seed the registry from the persisted cache and from component declarations.
    Read-IcingaPerformanceCounterCache;
    Register-IcingaPerformanceCounterFromComponents;

    # Warm up everything currently registered in a single batch.
    [string[]]$Registered = @($Store.Registered.Keys);

    if ($Registered.Count -gt 0) {
        $Store.Manager.Reconcile($Registered);
    }

    $Store.Heartbeat   = (Get-Date);
    $Store.LastRefresh = (Get-Date);

    Write-LoggingEntry -Message 'Performance counter environment initialized' -Level 'Info' -Data @{
        'RegisteredCounters' = $Registered.Count;
    };
}

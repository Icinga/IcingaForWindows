<#
.SYNOPSIS
Declare and keep-alive a set of performance counters for a component

.DESCRIPTION
`New-IcingaPerformanceCounter` registers the given counter paths in the global
performance-counter store so the background daemon initializes, warms and keeps them
available. Calling it refreshes each counter's last-seen timestamp, which both prevents
eviction of actively-used counters and drives the self-maintaining cache file.

Components declare the counters they need by calling this function with a literal list.
At module start the discovery step statically scans the compiled kernel for these calls
and seeds the registry from the extracted counter paths, so a declared counter is warm
before it is ever requested. The function only writes to the thread-safe registry
dictionary, so it is safe to call from any thread.

.PARAMETER Counter
| Name    | Type         | Description                                             | Default |
|---------|--------------|---------------------------------------------------------|---------|
| Counter | System.Array | One or more counter paths to register, e.g. '\Cat\Ctr'. | @()     |

.OUTPUTS
None -- Registers the counter paths in the global store.

.EXAMPLE
PS> New-IcingaPerformanceCounter -Counter @('\Processor(*)\% Processor Time', '\Memory\Available Bytes')

Declares two counters so the daemon keeps them warm and the discovery step can find them.

.NOTES
The counters are stored under `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered`.
This function does not return counter values -- use `Get-IcingaPerformanceCounter` to read them.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-IcingaPerformanceCounter()
{
    param (
        [array]$Counter = @()
    );

    if ($null -eq $Counter -or $Counter.Count -eq 0) {
        return;
    }

    $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;

    if ($null -eq $Store) {
        return;
    }

    [datetime]$Now = (Get-Date);

    foreach ($Path in $Counter) {
        if (-not [string]::IsNullOrEmpty($Path)) {
            $Store.Registered[$Path] = $Now;
        }
    }
}

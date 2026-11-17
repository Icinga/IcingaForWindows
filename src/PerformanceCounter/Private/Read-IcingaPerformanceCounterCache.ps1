<#
.SYNOPSIS
Load the registered performance counters from the cache file

.DESCRIPTION
`Read-IcingaPerformanceCounterCache` reads the persisted counter cache written by
`Write-IcingaPerformanceCounterCache` and merges its entries into the global registry.
It runs during performance-counter environment initialization so counters learned in
previous runs are warmed immediately at startup. A missing, empty or corrupt cache file
is ignored silently so a bad cache never blocks the daemon.

.OUTPUTS
None -- Populates `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered`.

.EXAMPLE
PS> Read-IcingaPerformanceCounterCache

.NOTES
`ConvertFrom-Json` returns a PSCustomObject on both Windows PowerShell 5.1 and
PowerShell 7 (the `-AsHashtable` switch is deliberately not used because it is PowerShell
6+ only). Entries are read through the object's properties for cross-version compatibility.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Read-IcingaPerformanceCounterCache()
{
    $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;

    if ($null -eq $Store) {
        return;
    }

    [string]$CacheFile = Join-Path -Path (Get-ModuleCacheDirectory) -ChildPath 'PerformanceCounter.json';

    if (-not (Test-Path -Path $CacheFile)) {
        return;
    }

    [string]$Content = Get-Content -Path $CacheFile -Raw -Encoding UTF8;

    if ([string]::IsNullOrEmpty($Content)) {
        return;
    }

    $Parsed = $null;

    try {
        $Parsed = ConvertFrom-Json -InputObject $Content;
    } catch {
        # A corrupt cache file must never block startup; discard it.
        return;
    }

    if ($null -eq $Parsed) {
        return;
    }

    foreach ($Property in $Parsed.PSObject.Properties) {
        [datetime]$Timestamp  = (Get-Date);
        [datetime]$ParsedTime = [datetime]::MinValue;

        if ([datetime]::TryParse([string]$Property.Value, [ref]$ParsedTime)) {
            $Timestamp = $ParsedTime;
        }

        $Store.Registered[$Property.Name] = $Timestamp;
    }
}

<#
.SYNOPSIS
Persist the registered performance counters to the cache file

.DESCRIPTION
`Write-IcingaPerformanceCounterCache` serializes the registered counter paths and their
last-seen timestamps to a JSON file in the module cache directory. The daemon calls this
each refresh cycle so the warm counter set survives restarts and self-maintains — new
counters are added and stale ones drop out over time. The file is written atomically by
writing to a temporary file and renaming it into place.

.OUTPUTS
None — Writes the cache file to disk.

.EXAMPLE
PS> Write-IcingaPerformanceCounterCache

.NOTES
The cache file is `PerformanceCounter.json` under `Get-ModuleCacheDirectory`. Timestamps
are stored in ISO 8601 round-trip format so they parse identically on Windows PowerShell
5.1 and PowerShell 7.
#>
function Write-IcingaPerformanceCounterCache()
{
    $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;

    if ($null -eq $Store) {
        return;
    }

    [string]$CacheDir = Get-ModuleCacheDirectory;

    if (-not (Test-Path -Path $CacheDir)) {
        New-Item -Path $CacheDir -ItemType Directory -Force | Out-Null;
    }

    [string]$CacheFile = Join-Path -Path $CacheDir -ChildPath 'PerformanceCounter.json';
    [string]$TempFile  = Join-Path -Path $CacheDir -ChildPath 'PerformanceCounter.json.tmp';

    [hashtable]$Data = @{ };

    foreach ($Key in @($Store.Registered.Keys)) {
        $Timestamp = $Store.Registered[$Key];

        if ($null -ne $Timestamp) {
            $Data[$Key] = $Timestamp.ToString('o');
        }
    }

    [string]$Json = ConvertTo-Json -InputObject $Data -Depth 5;

    Set-Content -Path $TempFile -Value $Json -Encoding UTF8;
    Move-Item -Path $TempFile -Destination $CacheFile -Force;
}

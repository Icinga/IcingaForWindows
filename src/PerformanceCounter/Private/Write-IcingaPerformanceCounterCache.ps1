<#
.SYNOPSIS
Persist the registered performance counters to the cache file

.DESCRIPTION
`Write-IcingaPerformanceCounterCache` serializes the registered counter paths and their
last-seen timestamps to a JSON file in the module cache directory using UTF-8 without BOM.
The daemon calls this each refresh cycle so the warm counter set survives restarts and
self-maintains -- new counters are added and stale ones drop out over time. The file is
written atomically via a temporary file and guarded with try/catch so transient file locks
or permission issues never interrupt the daemon.

.OUTPUTS
None -- Writes the cache file to disk.

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

    [string]$CacheDir  = Get-ModuleCacheDirectory;
    [string]$CacheFile = Join-Path -Path $CacheDir -ChildPath 'PerformanceCounter.json';
    [string]$TempFile  = Join-Path -Path $CacheDir -ChildPath ('PerformanceCounter.{0}.tmp' -f [System.Guid]::NewGuid().ToString('N'));
    [hashtable]$Data   = @{ };

    foreach ($Key in @($Store.Registered.Keys)) {
        $Timestamp = $Store.Registered[$Key];

        if ($null -ne $Timestamp) {
            $Data[$Key] = $Timestamp.ToString('o');
        }
    }

    try {
        if (-not (Test-Path -Path $CacheDir)) {
            New-Item -Path $CacheDir -ItemType Directory -Force -ErrorAction Stop | Out-Null;
        }

        # Write UTF-8 without BOM to a unique temporary file first, then atomically replace the cache file
        [string]$Json = ConvertTo-ModuleJson -InputObject $Data;
        [System.IO.File]::WriteAllText($TempFile, $Json, (New-Object System.Text.UTF8Encoding($false)));
        Move-Item -Path $TempFile -Destination $CacheFile -Force -ErrorAction Stop;
    } catch {
        if (Test-Path -Path $TempFile) {
            try {
                Remove-Item -Path $TempFile -Force -ErrorAction Stop;
            } catch {
                [void]$_;
            }
        }

        Write-LoggingEntry -Message 'Failed to persist PerformanceCounter cache file' -Level 'Warning' -Data @{
            'CacheFile'        = $CacheFile;
            'ExceptionMessage' = $_.Exception.Message;
        };
    }
}

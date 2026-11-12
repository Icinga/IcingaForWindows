<#
.SYNOPSIS
Refresh, reconcile, evict and persist the performance counter state

.DESCRIPTION
`Update-IcingaPerformanceCounterState` is the periodic maintenance step run by the
performance-counter daemon. On every call it refreshes the daemon heartbeat. When the
configured refresh interval has elapsed it additionally evicts counters that have not been
requested for longer than the eviction window, reconciles the manager against the current
registration set (adding new instances and disposing vanished ones such as a removed disk),
takes a fresh sample of every counter to keep rate values current, and persists the cache
file.

Extracting this maintenance out of the daemon loop keeps the loop body small and lets the
throttling logic live in one place.

.PARAMETER Store
| Name  | Type          | Description                                                                          | Default |
|-------|---------------|--------------------------------------------------------------------------------------|---------|
| Store | System.Object | The performance-counter store to operate on. Resolved from the runtime when omitted. | $null   |

.OUTPUTS
None -- Mutates the global performance-counter store and writes the cache file.

.EXAMPLE
PS> Update-IcingaPerformanceCounterState

.NOTES
Reads configuration (`RefreshIntervalMs`, `EvictionMinutes`) from the store's Config object.
Heartbeat is always refreshed so liveness detection stays responsive even under load. The daemon
passes its cached store reference to avoid re-resolving it through Get-GlobalRuntimeVariable each cycle.
#>
function Update-IcingaPerformanceCounterState()
{
    param (
        $Store = $null
    );

    if ($null -eq $Store) {
        $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;
    }

    if ($null -eq $Store) {
        return;
    }

    # Always refresh the heartbeat so callers can detect the daemon is alive.
    $Store.Heartbeat = (Get-Date);
    $Manager         = $Store.Manager;

    if ($null -eq $Manager) {
        return;
    }

    # Throttle the heavier maintenance to the configured refresh interval.
    if ($null -ne $Store.LastRefresh -and ((Get-Date) - $Store.LastRefresh).TotalMilliseconds -lt $Store.Config.RefreshIntervalMs) {
        return;
    }

    # Evict counters that have not been requested within the eviction window.
    [datetime]$Threshold = (Get-Date).AddMinutes(-1 * $Store.Config.EvictionMinutes);

    foreach ($Key in @($Store.Registered.Keys)) {
        $LastSeen = $Store.Registered[$Key];

        if ($null -ne $LastSeen -and $LastSeen -lt $Threshold) {
            # TValue is a value type (datetime), so the out-ref must be a typed variable;
            # [ref]$null only binds for reference-type dictionary values.
            [datetime]$Removed = [datetime]::MinValue;
            $Store.Registered.TryRemove($Key, [ref]$Removed) | Out-Null;
        }
    }

    [string[]]$Registered = @($Store.Registered.Keys);

    $Manager.Reconcile($Registered);
    $Manager.Sample();

    Write-IcingaPerformanceCounterCache;

    $Store.LastRefresh    = (Get-Date);
}

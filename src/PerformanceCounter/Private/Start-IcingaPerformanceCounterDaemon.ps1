<#
.SYNOPSIS
Background daemon that serves performance counter requests and maintains the registry

.DESCRIPTION
`Start-IcingaPerformanceCounterDaemon` initializes the performance-counter environment and
then runs the request/refresh loop while `Test-ThreadRunning` is true. Each cycle it blocks
briefly on the request queue; when a request arrives it resolves the requested counters
through the central manager and pushes the result into the caller's pending response queue,
keyed by the request id. When idle (and on a throttled interval) it runs the maintenance
step which refreshes the heartbeat, reconciles transient instances, evicts unused counters
and persists the cache.

Because every performance counter handle is created, sampled and disposed here on this one
thread, callers never touch the non-thread-safe counter objects directly -- they exchange
data through the thread-safe queues only.

.OUTPUTS
None -- Operates for side effects (serves requests and maintains counters).

.EXAMPLE
PS> Start-IcingaPerformanceCounterDaemon

.NOTES
Must run inside a dedicated background runspace created by `New-Thread`. All shared state is
accessed through `Get-GlobalRuntimeVariable` because the runspace receives only a snapshot of
the runtime at startup. The daemon exits cleanly when `Test-ThreadRunning` returns $false.
#>
function Start-IcingaPerformanceCounterDaemon()
{
    New-IcingaPerformanceCounterEnvironment;

    # Resolve the shared runtime references once. Set-ThreadData wires the shared Public space into
    # this runspace before the daemon starts and the store/manager references never change again, so
    # there is no reason to call Get-GlobalRuntimeVariable on every loop iteration.
    $Store   = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;
    $Manager = $Store.Manager;

    while (Test-ThreadRunning) {
        $Request  = $null;
        $Response = $null;

        # This is a WaitForJobs thread, so its state must be refreshed on every cycle,
        # whether a request is processed or the thread is idle waiting on the queue.
        # Skipping it on idle cycles trips the ThreadWaitForJobMisconfiguration warning
        # (mirrors the Set-ThreadProcessing call in Start-LoggingDaemon's timeout branch).
        Set-ThreadProcessing;

        if ($Store.RequestQueue.TryTake([ref]$Request, 500)) {
            if ($null -ne $Manager -and $null -ne $Request) {
                $Response = $Manager.Resolve([string[]]$Request.Counter);
            }

            if ($null -ne $Request -and $Store.PendingRequests.ContainsKey($Request.RequestId)) {
                $Store.PendingRequests[$Request.RequestId].Add($Response);
            }
        }

        # Periodic maintenance: heartbeat, refresh, reconcile, eviction and cache persistence.
        Update-IcingaPerformanceCounterState -Store $Store;

        $Request  = $null;
        $Response = $null;
    }
}

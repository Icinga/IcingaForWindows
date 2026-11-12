<#
.SYNOPSIS
Read one or more Windows performance counters and return their current values

.DESCRIPTION
`Get-IcingaPerformanceCounter` returns the current values of the requested counter paths. By default
the result is a hashtable keyed by the requested path: a concrete path maps to a flat result
hashtable with the keys value, sample, help, type and error; a wildcard path (instance '*') maps to a
nested hashtable keyed by each live instance path.

With `-StructureByInstance` the result is reshaped for easier plugin consumption: counters with an
instance are keyed instance-first (`$out[Instance][Category][Counter]`), counters without an instance
are keyed category-first (`$out[Category][Counter]`), and the leaf is always the uniform value
hashtable.

When the performance-counter daemon is running the read is dispatched through a request/pull queue:
the function generates a request id, registers a single-slot response queue, enqueues the request and
blocks on the response for up to the given timeout. All counter access happens on the daemon thread,
so there are no races on the underlying counter handles. When no daemon is running the function uses a
persistent per-runspace manager kept in module scope, so repeated reads stay warm and only the first
read of a new counter pays the warm-up sleep.

Requesting a counter also refreshes its last-seen timestamp in the registry, keeping actively used
counters warm and out of the eviction path.

.PARAMETER Counter
| Name    | Type         | Description                                                  | Default |
|---------|--------------|--------------------------------------------------------------|---------|
| Counter | System.Array | One or more counter paths to read, e.g. '\Processor(*)\...'. | @()     |

.PARAMETER TimeoutMs
| Name      | Type         | Description                                                    | Default |
|-----------|--------------|----------------------------------------------------------------|---------|
| TimeoutMs | System.Int32 | Milliseconds to wait for the daemon response before giving up. | 5000    |

.PARAMETER StructureByInstance
| Name                | Type                                         | Description                                                                          | Default |
|---------------------|----------------------------------------------|--------------------------------------------------------------------------------------|---------|
| StructureByInstance | System.Management.Automation.SwitchParameter | Reshape the result to instance/category/counter (category/counter when no instance). | $false  |

.OUTPUTS
System.Collections.Hashtable -- By default keyed by requested path (flat for concrete paths, nested for
wildcard paths). With `-StructureByInstance`, keyed by instance then category then counter, or by
category then counter for counters without an instance. Returns an empty hashtable when no counter is
requested, or $null when the daemon request times out.

.EXAMPLE
PS> Get-IcingaPerformanceCounter -Counter '\Processor(_Total)\% Processor Time'

Reads a single counter and returns its value hashtable.

.EXAMPLE
PS> $cpu = Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time' -StructureByInstance
PS> $cpu.'0'.'Processor'.'% Processor Time'.value

Reads every processor instance and addresses one core by instance, category and counter name.

.EXAMPLE
PS> $mem = Get-IcingaPerformanceCounter -Counter '\Memory\Pages/sec' -StructureByInstance
PS> $mem.'Memory'.'Pages/sec'.value

A counter without an instance is keyed category-first.

.NOTES
The request/response transport lives under `(Get-GlobalRuntimeVariable).Public.PerformanceCounter`.
Timeouts are logged through `Write-LoggingEntry` at Warning level. No external services are used.
#>
function Get-IcingaPerformanceCounter()
{
    param (
        [array]$Counter              = @(),
        [int]$TimeoutMs              = 5000,
        [switch]$StructureByInstance = $false
    );

    if ($null -eq $Counter -or $Counter.Count -eq 0) {
        return @{ };
    }

    $Store  = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;
    $Result = $null;

    if ($null -eq $Store) {
        # The environment is not initialized at all; do a fully transient read.
        $Result = ('IcingaPerformanceCounter' -as [type])::ResolveOnce([string[]]$Counter, 250);
    } else {
        # Keep the requested counters alive in the registry and cache.
        [datetime]$Now = (Get-Date);

        foreach ($Path in $Counter) {
            if (-not [string]::IsNullOrEmpty($Path)) {
                $Store.Registered[$Path] = $Now;
            }
        }

        if (Test-IcingaPerformanceCounterDaemon) {
            # Daemon is alive: dispatch through the request/response queue.
            [string]$RequestId                 = (New-Guid).ToString();
            $ResponseQueue                     = [System.Collections.Concurrent.BlockingCollection[PSObject]]::new(1);
            $Store.PendingRequests[$RequestId] = $ResponseQueue;

            try {
                $Store.RequestQueue.Add(
                    [PSCustomObject]@{
                        'RequestId' = $RequestId;
                        'Counter'   = [string[]]$Counter;
                    }
                );

                $Response = $null;

                if ($ResponseQueue.TryTake([ref]$Response, $TimeoutMs)) {
                    $Result = $Response;
                } else {
                    Write-LoggingEntry -Message 'Get-IcingaPerformanceCounter: Request timed out' -Level 'Warning' -Data @{
                        'RequestId' = $RequestId;
                        'Counter'   = $Counter;
                        'TimeoutMs' = $TimeoutMs;
                    };

                    return $null;
                }
            } finally {
                [System.Collections.Concurrent.BlockingCollection[PSObject]]$RemovedQueue = $null;
                [void]$Store.PendingRequests.TryRemove($RequestId, [ref]$RemovedQueue);
                $ResponseQueue.Dispose();
            }
        } else {
            # Inline fallback: no live daemon. Keep a persistent per-runspace manager in module scope
            # so counters stay warm across calls and only the first read of a new counter pays the
            # warm-up sleep. A runspace runs one pipeline at a time and each runspace has its own
            # module scope, so this manager is never accessed concurrently and needs no lock. Living
            # in module scope (rather than the global store) also means it works without rebuilding
            # the global runtime state.
            if ($null -eq $script:IcingaPerformanceCounterInlineManager) {
                # Looked up by name so a thread runspace gets its own class type instead of the
                # main runspace's one (see New-IcingaPerformanceCounterEnvironment).
                $script:IcingaPerformanceCounterInlineManager = ('IcingaPerformanceCounter' -as [type])::new();
            }

            $script:IcingaPerformanceCounterInlineManager.WarmupMilliseconds = $Store.Config.WarmupMilliseconds;
            $Result                                                          = $script:IcingaPerformanceCounterInlineManager.Resolve([string[]]$Counter);
        }
    }

    if ($StructureByInstance -and $null -ne $Result) {
        return (ConvertTo-IcingaPerformanceCounterInstanceStructure -Result $Result -Counter $Counter);
    }

    return $Result;
}

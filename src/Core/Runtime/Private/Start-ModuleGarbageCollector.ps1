<#
.SYNOPSIS
Background garbage collector loop used by the runtime subsystem.

.DESCRIPTION
Periodically forces a full .NET garbage collection and clears the `$Error` buffer
while the runtime thread is running. Intended to run as a background helper thread.

.EXAMPLE
PS> Start-ModuleGarbageCollector

.OUTPUTS
None — Periodically runs garbage collection and clears the error buffer in the background.

.NOTES
This helper should be run in a dedicated thread and relies on `Test-ThreadRunning`.
#>
function Start-ModuleGarbageCollector()
{
    while (Test-ThreadRunning) {
        # Force the full collection of memory being used
        [System.GC]::GetTotalMemory('forcefullcollection') | Out-Null;
        # Collect all generations of objects inside our memory and force the flushing of objects
        [System.GC]::Collect([System.GC]::MaxGeneration, [System.GCCollectionMode]::Forced) | Out-Null;
        # Collect the remaining memory for a before/after delta
        [System.GC]::GetTotalMemory('forcefullcollection') | Out-Null;
        # Clear the error buffer to avoid memory leaks
        $Error.Clear();
        Start-Sleep -Seconds 30;
    }
}

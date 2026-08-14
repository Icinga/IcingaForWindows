<#
.SYNOPSIS
Evaluate and normalize the runtime state of a thread.

.DESCRIPTION
`Get-ThreadState` inspects a thread's stored state and returns a normalized
status such as 'RUNNING', 'IDLE', 'BLOCKED', or the raw stored state when
unmodified. It uses the thread's `LastSeen` timestamp and `KeepAlive` flag to
differentiate between active and idle conditions.

.PARAMETER ThreadId
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ThreadId | System.String | The thread id to evaluate. Defaults to current thread. | (Get-ThreadId) |

.OUTPUTS
System.String — Normalisierter Thread-State (z.B. RUNNING, IDLE, BLOCKED).

.EXAMPLE
PS> Get-ThreadState -ThreadId $tid

.NOTES
Relies on configuration values such as `(Get-GlobalRuntimeVariable).Public.Threading.IdleTime`.
#>
function Get-ThreadState()
{
    param (
        [string]$ThreadId = (Get-ThreadId)
    );

    # Load the current thread
    $ThreadState = (Get-GlobalRuntimeVariable).Public.Threading.Threads.$ThreadId.State;
    $KeepAlive   = (Get-GlobalRuntimeVariable).Public.Threading.Threads.$ThreadId.KeepAlive;
    switch ($ThreadState) {
        'RUNNING'{
            # We just need to make a difference between RUNNING, as the thread could be IDLE but still RUNNING
            # This happens if a thread is waiting for connections or worker queues

            # Check last seen timestamp to determine if the thread is doing something or IDLE
            $LastSeenInSeconds = Get-ThreadLastSeen -ThreadId $ThreadId;

            if ($null -ne $LastSeenInSeconds -And $LastSeenInSeconds -gt (Get-GlobalRuntimeVariable).Public.Threading.IdleTime) {
                if (-not $KeepAlive) {
                    return 'IDLE';
                }
                return 'BLOCKED';
            }

            return 'RUNNING'
        };
        default {
            return $ThreadState;
        };
    };

    # Shouldn't happen anyway
    return $ThreadState;
}

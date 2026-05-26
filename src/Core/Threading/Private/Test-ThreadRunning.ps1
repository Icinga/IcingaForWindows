<#
.SYNOPSIS
Core loop gate to determine whether a thread should continue running.

.DESCRIPTION
`Test-ThreadRunning` is invoked by thread loops to decide if the thread
should continue executing. It updates heartbeats, refreshes logging ids,
checks the thread state and optionally validates TCP/WebSocket connectivity.
It also enforces lightweight sleeps to reduce CPU usage.

.PARAMETER CheckTcpConnection
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CheckTcpConnection | System.SwitchParameter | When set test the global TCP connection status | $false |

.PARAMETER CheckWebSocket
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CheckWebSocket | System.SwitchParameter | When set test the WebSocket connectivity | $false |

.PARAMETER NoSleep
| Name | Type | Description | Default |
|------|------|-------------|---------|
| NoSleep | System.SwitchParameter | When set skip the default short sleep at loop start | $false |

.OUTPUTS
System.Boolean — $true when the thread should continue, $false otherwise.

.EXAMPLE
while (Test-ThreadRunning) { Do-Work }

.NOTES
This function performs multiple side effects (timestamp updates, logging id rotation)
and is central to thread lifecycle management.
#>
function Test-ThreadRunning()
{
    param (
        [switch]$CheckTcpConnection = $false,
        [switch]$CheckWebSocket     = $false,
        [switch]$NoSleep             = $false
    );

    # At first, before we do anything, lets sleep for 100 milliseconds to keep the entire CPU from spiking
    # This is done for every cycle of a thread to ensure we don't overload the CPU with constant checks
    if (-not $NoSleep) {
        Start-Sleep -Milliseconds 100;
    }
    # Clear the entire error buffer for each cycle to keep memory consumption low
    # By this point, everything was already handled, so we don't need old errors anymore
    $Error.Clear();
    # Read the ID of the current thread
    $ThreadId       = Get-ThreadId;
    [bool]$RetValue = $true;
    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Update the logging ID for this thread to ensure logs are properly tagged an traceable
    Update-LoggingThreadLoggingId;

    # Now lets check if we should keep running or not. Basically our state should be RUNNING, other states would be
    # FROZEN, TERMINATED, ZOMBIE, SHUTDOWN
    # If we are TERMINATED, we should already have reached the ending point, which means we should be fine
    # If we are in state ZOMBIE, we should return false as this state only applies if we are meant to be KeepAlive
    # Shutdown simply means we are in the process of stopping, so we should also return false
    $ThreadState = $GlobalVariable.Public.Threading.Threads.$ThreadId.State;
    switch ($ThreadState) {
        'RUNNING' {
            # If we are a thread that is required to wait for jobs, the first state we reach is RUNNING after
            # The thread is created. This means, we will set us immediately to WAITING to ensure proper state tracking
            # If we are a worker thread that does actual work, but waits for a queue or similar, we should be changed
            # to PROCESSING when actual work is done. Basically wait for jobs threads should always be in WAITING state when idle
            if ($GlobalVariable.Public.Threading.Threads.$ThreadId.WaitForJobs) {
                $GlobalVariable.Public.Threading.Threads.$ThreadId.State = 'WAITING';
            }

            # Update the last seen timestamp to now
            $GlobalVariable.Public.Threading.Threads.$ThreadId.LastSeen = (Get-Date);
            $RetValue = $true;
            break;
        };
        'ALIVE' {
            # If we are in ALIVE mode, we simply update the last seen timestamp to now
            # This is basically a misconfiguration scenario, as ALIVE threads are configured with WaitForJobs,
            # but the state is never updated to Processing with Set-ThreadProcessing after taking a job
            $GlobalVariable.Public.Threading.Threads.$ThreadId.LastSeen = (Get-Date);
            $RetValue = $true;
            break;
        };
        'PROCESSING' {
            # If we are in PROCESSING mode, we simply update the last seen timestamp to now
            $GlobalVariable.Public.Threading.Threads.$ThreadId.LastSeen = (Get-Date);
            # We are actually part of a processing thread, which means we always have to have for work to do
            # To ensure we don't restart threads every time, we have to move the thread to a different state now
            # to ensure the housekeeper does not mark us as frozen, because we are actually waiting for work
            $GlobalVariable.Public.Threading.Threads.$ThreadId.State    = 'WAITING';
            $RetValue = $true;
            break;
        };
        'WAITING' {
            # If we are still WAITING on the next loop iteration, this basically means we are configured differently
            # in keep alive scenarios without a worker queue or similar. We should then change the state to ALIVE
            # which should handle the same procedure as PROCESSING threads, but are meant to be kept alive
            $GlobalVariable.Public.Threading.Threads.$ThreadId.LastSeen = (Get-Date);
            $GlobalVariable.Public.Threading.Threads.$ThreadId.State    = 'ALIVE';

            Write-FunctionReturnValue `
                -ReturnValue 'ThreadWaitForJobMisconfiguration' `
                -Data @{ 'ThreadId' = $ThreadId; 'ThreadName' = $GlobalVariable.Public.Threading.Threads.$ThreadId.Name } | Out-Null;

            $RetValue = $true;
            break;
        };
        'SHUTDOWN' {
             # If our thread does close, we should also make sure all Tcp connections are closed properly
            Close-TCPConnection;
            # In case we provide a Tcp-Socket, make sure it is closed properly
            Close-TCPSocket;
            # Ensure we also disconnect any WebSocket connections properly
            Disconnect-ModuleWebSocket | Out-Null;
            # If we are shutting down, we should not continue running and stop this thread
            Stop-Thread -ThreadId $ThreadId;
            $RetValue = $false;
            break;
        };
        'FROZEN' {
            # If we are frozen, we should not continue running
            # Reason is, that we are already in a bad state and might cause more harm if we keep running
            # as the housekeeper might have already proceeded to mark us as ZOMBIE and restart us
            $RetValue = $false;
            break;
        };
        'TERMINATED' {
            # If we are terminated, we should not continue running
            $RetValue = $false;
            break;
        };
        'ZOMBIE' {
            # If we are a zombie, we should not continue running. If for some reason we went back to work, set us to DEAD instead
            # This will ensure the housekeeper will remove us properly and not try to restart us again
            $GlobalVariable.Public.Threading.Threads.$ThreadId.State = 'DEAD';
            $RetValue = $false;
            break;
        };
        default {
            # Unknown state, log an error and stop the thread. Shouldn't happen anyway
            Write-LoggingEntry -Message 'Test-ThreadRunning: Detected unknown thread state, stopping thread' -Level 'Error' -Data @{ 'ThreadState' = $ThreadState };
            $RetValue = $false;
            break;
        };
    }

    if ($CheckTcpConnection) {
        # Additionally check if the TCP connection is still valid
        if (-not (Test-TCPConnection)) {
            # If our thread does close, we should also make sure all Tcp connections are cleaned up properly
            Close-TCPConnection;
            # In case we provide a Tcp-Socket, make sure it is closed properly
            Close-TCPSocket;
            # Ensure we stop this thread, as no active connection exists anymore
            Stop-Thread -ThreadId $ThreadId;
            Write-LoggingEntry -Message 'Test-ThreadRunning: Detected invalid TCP connection, stopping thread {0}' -Level 'Info' -Data @{ 'ThreadId' = $ThreadId };
            $RetValue = $false;
        }
    }

    if ($CheckWebSocket) {
        # Additionally check if the WebSocket connection is still valid
        if (-not (Test-ModuleWebSocket)) {
            # If our thread does close, we should also make sure all WebSocket connections are cleaned up properly
            Disconnect-ModuleWebSocket | Out-Null;
            # Ensure we stop this thread, as no active connection exists anymore
            # This only applies for read and write threads for WebSockets, as the main umbrella head will restart them properly
            # again in case they are gone
            Stop-Thread -ThreadId $ThreadId;
            Write-LoggingEntry -Message 'Test-ThreadRunning: Detected invalid WebSocket connection, stopping thread {0}' -Level 'Debug' -Data @{ 'ThreadId' = $ThreadId; 'Name' = $GlobalVariable.Private.WebSocket.Name; };
            $RetValue = $false;
        }
    }

    # Return the final decision
    return $RetValue;
}

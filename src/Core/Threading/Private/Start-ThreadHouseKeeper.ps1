<#
.SYNOPSIS
Periodic housekeeper that monitors and manages thread lifecycle.

.DESCRIPTION
`Start-ThreadHouseKeeper` runs a loop that inspects all registered threads,
marks unresponsive threads as `FROZEN`, cleans up terminated or dead threads,
and attempts restarts for keep-alive threads. It sleeps between cycles to
reduce resource usage.

.OUTPUTS
None — Performs side-effect operations on the global thread registry and logs actions.

.EXAMPLE
PS> Start-ThreadHouseKeeper

.NOTES
This function is intended to run as a background supervisory thread.
#>
function Start-ThreadHouseKeeper()
{
    while (Test-ThreadRunning) {
        try {
            # First fetch all current available threads
            $GlobalVariable      = Get-GlobalRuntimeVariable;
            [array]$ThreadIdList = $GlobalVariable.Public.Threading.Threads.PSobject.Properties.Name;

            foreach ($threadId in $ThreadIdList) {
                # Check if the thread has naturally completed its execution (e.g. function reached the end).
                # If so, mark it as TERMINATED so the housekeeper can dispose the runspace and free the memory.
                $ThreadHandle = $GlobalVariable.Public.Threading.Threads.$threadId.Handle;
                if ($null -ne $ThreadHandle -and $ThreadHandle.IsCompleted) {
                    $GlobalVariable.Public.Threading.Threads.$threadId.State = 'TERMINATED';
                }

                switch ($GlobalVariable.Public.Threading.Threads.$threadId.State) {
                    'RUNNING' {
                        # RUNNING, ALIVE and PROCESSING threads are similar in monitoring
                        Set-ThreadFrozen -ThreadId $threadId;
                        break;
                    };
                    'ALIVE' {
                        # RUNNING, ALIVE and PROCESSING threads are similar in monitoring
                        # ALIVE is basically a configuration error which should never happen anyways
                        # It is already logged as warning at Test-ThreadRunning, so we just monitor it here
                        Set-ThreadFrozen -ThreadId $threadId;
                        break;
                    };
                    'PROCESSING' {
                        # RUNNING, ALIVE and PROCESSING threads are similar in monitoring
                        Set-ThreadFrozen -ThreadId $threadId;
                        break;
                    };
                    'TERMINATED' {
                        # Handling of terminated threads
                        Write-LoggingEntry -Message 'Housekeeper: Cleaning up terminated thread' -Level 'Info' -Data @{ 'ThreadId' = $threadId };
                        # Stop the thread shell if not already stopped
                        $GlobalVariable.Public.Threading.Threads.$threadId.Shell.Stop();
                        # Dispose the shell to free resources
                        $GlobalVariable.Public.Threading.Threads.$threadId.Shell.Dispose();
                        # Clear the shell and handle references
                        $GlobalVariable.Public.Threading.Threads.$threadId.Shell  = $null;
                        $GlobalVariable.Public.Threading.Threads.$threadId.Handle = $null;

                        # Finally remove the thread from the global thread list
                        $GlobalVariable.Public.Threading.Threads.PSObject.Properties.Remove($threadId) | Out-Null;
                        break;
                    };
                    'DEAD' {
                        # Handling of dead threads (should not happen normally)
                        Write-LoggingEntry -Message 'Housekeeper: Cleaning up dead thread' -Level 'Info' -Data @{ 'ThreadId' = $threadId };
                        # Just remove the thread from the global thread list as already handled
                        # DEAD threads will appear after a ZOMBIE thread tried to continue working, after it was already restarted
                        $GlobalVariable.Public.Threading.Threads.PSObject.Properties.Remove($threadId) | Out-Null;
                        break;
                    };
                    'ZOMBIE' {
                        # If a thread has been in ZOMBIE state for more than 30 minutes (1800 seconds),
                        # remove it from the global thread list without stopping or disposing the shell
                        # to avoid hanging the housekeeper thread.
                        $ZombieTimestamp = $GlobalVariable.Public.Threading.Threads.$threadId.ZombieTimestamp;
                        if ($null -ne $ZombieTimestamp -and ((Get-Date) - $ZombieTimestamp).TotalSeconds -gt 1800) {
                            Write-LoggingEntry -Message 'Housekeeper: Cleaning up abandoned ZOMBIE thread after 30 minute timeout' -Level 'Info' -Data @{ 'ThreadId' = $threadId };
                            $GlobalVariable.Public.Threading.Threads.PSObject.Properties.Remove($threadId) | Out-Null;
                        }
                        break;
                    };
                    'FROZEN' {
                        # If a thread is frozen, we cannot stop it because PowerShell does not support that
                        # Instead we log a warning and leave it be for now in a ZOMBIE state, but try to restart
                        # it in case the thread logic supports that
                        Write-LoggingEntry -Message 'Housekeeper: Detected frozen thread, attempting to restart' -Level 'Warning' -Data @{ 'ThreadId' = $threadId };
                        # Set the thread state to ZOMBIE to indicate it is no longer active
                        $GlobalVariable.Public.Threading.Threads.$threadId.State           = 'ZOMBIE';
                        $GlobalVariable.Public.Threading.Threads.$threadId.ZombieTimestamp = (Get-Date);
                        # null the existing shell and handle to ensure we do not keep references
                        # Do NOT try to stop or dispose the shell as it is frozen and will also freeze this housekeeper thread
                        $GlobalVariable.Public.Threading.Threads.$threadId.Shell  = $null;
                        $GlobalVariable.Public.Threading.Threads.$threadId.Handle = $null;

                        [string]$ParentThread = $GlobalVariable.Public.Threading.Threads.$threadId.ParentThread;
                        [string]$ThreadName   = $null;

                        # If our parent thread is null or empty, we set it to MAIN for proper thread hierarchy tracking
                        if ([string]::IsNullOrEmpty($ParentThread)) {
                            $ParentThread = 'MAIN';
                            $ThreadName   = $GlobalVariable.Public.Threading.Threads.$threadId.Name;
                        }

                        if ($GlobalVariable.Public.Threading.Threads.$threadId.KeepAlive) {
                            # Try to restart the thread if it is marked as KeepAlive
                            Write-LoggingEntry -Message 'Housekeeper: Restarting frozen thread' -Level 'Info' -Data @{ 'ThreadId' = $threadId };
                            New-Thread `
                                -Command $GlobalVariable.Public.Threading.Threads.$threadId.Command `
                                -Parameters $GlobalVariable.Public.Threading.Threads.$threadId.Parameters `
                                -ParentThread $ParentThread `
                                -OverrideName $ThreadName `
                                -Start `
                                -KeepAlive;
                        }
                        break;
                    };
                }
            }
        } catch {
            # Log any exceptions that occur during the housekeeping process
            Write-LoggingEntry -Message 'Housekeeper: Caught exception during housekeeping: {0}' -Level 'Error' -Data @{ 'Exception' = $_.Exception };
        } finally {
            $GlobalVariable  = $null;
            $ThreadIdList    = $null;
            $ParentThread    = $null;
            $ZombieTimestamp = $null;
            $ThreadHandle    = $null;
        }

        # Call this function every 10 seconds to minimize performance impact
        Start-Sleep -Seconds 10;
    }
}

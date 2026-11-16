<#
.SYNOPSIS
Terminate a timed-out external binary process and all of its descendant processes

.DESCRIPTION
Stop-IcingaProtocolProcessTree ensures that a timed-out external binary check
cannot leave orphaned child processes holding stdout/stderr handles open or
consuming host resources:
- On Windows, kills the root process first while holding its SafeProcessHandle
  open (preventing OS PID reuse), performs up to three Win32_Process
  ParentProcessId breadth-first sweeps to terminate any newly spawned
  descendants, waits up to 2000ms per handle, and disposes all descendant
  Process handles.
- On Linux and macOS, walks child PIDs via 'pgrep -P', kills the root process
  tree (using Process.Kill($true) on PowerShell 7+), terminates every discovered
  descendant handle, waits for exit, and disposes all descendant handles.

.PARAMETER Process
| Name    | Type                       | Description                                         | Default |
|---------|----------------------------|-----------------------------------------------------|---------|
| Process | System.Diagnostics.Process | Live root Process object whose handle stays open.   | $null   |

.PARAMETER RootProcessId
| Name          | Type         | Description                                     | Default |
|---------------|--------------|-------------------------------------------------|---------|
| RootProcessId | System.Int32 | OS process identifier of the root binary check. | 0       |

.OUTPUTS
None -- Terminates the process tree and waits briefly for OS rundown.

.EXAMPLE
PS> Stop-IcingaProtocolProcessTree -Process $proc -RootProcessId $proc.Id

Kills the root process and all descendant processes spawned by it.

.NOTES
Caller remains responsible for disposing the root Process instance after stream
drain completes.
#>
function Stop-IcingaProtocolProcessTree()
{
    param (
        [System.Diagnostics.Process]$Process = $null,
        [int]$RootProcessId                  = 0
    );

    if ($null -eq $Process) {
        return;
    }

    if ($env:OS -eq 'Windows_NT') {
        <#
        Windows Process-Tree Termination Strategy:
        - On Windows PowerShell 5.1 (.NET Framework), Process.Kill() only terminates the root process
          (e.g. cmd.exe) and leaves child processes (e.g. ping.exe) alive holding inherited stdout/stderr
          pipes and Win32 current-directory locks on WorkingDirectory.
        - Even when the root process has already exited (for example a batch script that spawned a
          background child via 'start /b'), Windows never reparents children to PID 1, and keeping
          $Process undisposed keeps its SafeProcessHandle open so the kernel cannot recycle $RootProcessId.
        - We kill the root process first to stop new child spawns immediately, then perform up to 3
          Win32_Process ParentProcessId BFS passes to open handles and terminate every child/grandchild,
          and finally call WaitForExit(2000) on every handle so kernel file/pipe rundown completes
          before returning to the caller.
        #>
        [array]$DescendantHandles      = @();
        [hashtable]$KnownTreePids      = @{ };
        $KnownTreePids[$RootProcessId] = $true;

        try {
            # 1. Kill root process first while keeping $Process open so Windows cannot reuse RootProcessId
            try {
                if (-not $Process.HasExited) {
                    if ($PSVersionTable.PSVersion.Major -ge 6) {
                        try {
                            $Process.Kill($true);
                        } catch {
                            $Process.Kill();
                        }
                    } else {
                        $Process.Kill();
                    }
                }
            } catch {
                [void]$_;
            }

            # 2. Run up to 3 Win32_Process snapshots to catch any child/grandchild spawned right as root died
            for ($scanPass = 0; $scanPass -lt 3; $scanPass++) {
                [bool]$CimLookupFailed       = $false;
                [hashtable]$ChildrenByParent = @{ };

                try {
                    [array]$AllProcs = @(Get-CimInstance -ClassName 'Win32_Process' -Property 'ProcessId', 'ParentProcessId' -ErrorAction Stop);
                    foreach ($ProcRow in $AllProcs) {
                        [int]$RowPid  = [int]$ProcRow.ProcessId;
                        [int]$RowPpid = [int]$ProcRow.ParentProcessId;
                        if ($RowPid -gt 0 -and $RowPid -ne $RowPpid) {
                            if (-not $ChildrenByParent.ContainsKey($RowPpid)) {
                                $ChildrenByParent[$RowPpid] = New-Object System.Collections.ArrayList;
                            }
                            [void]$ChildrenByParent[$RowPpid].Add($RowPid);
                        }
                    }
                } catch {
                    $CimLookupFailed  = $true;
                    $ChildrenByParent = @{ };
                }

                if ($CimLookupFailed) {
                    break;
                }

                # Walk all descendants reachable from $RootProcessId (or previously discovered descendants)
                $VisitQueue           = New-Object System.Collections.Queue;
                [hashtable]$PassSeen  = @{ };
                [int]$LiveFoundInPass = 0;

                foreach ($SeedPidObj in @($KnownTreePids.Keys)) {
                    [int]$SeedPid       = [int]$SeedPidObj;
                    $PassSeen[$SeedPid] = $true;
                    $VisitQueue.Enqueue($SeedPid);
                }

                while ($VisitQueue.Count -gt 0) {
                    [int]$CurrPid = [int]$VisitQueue.Dequeue();
                    if ($ChildrenByParent.ContainsKey($CurrPid)) {
                        foreach ($ChildPidObj in $ChildrenByParent[$CurrPid]) {
                            [int]$NextPid = [int]$ChildPidObj;
                            if (-not $PassSeen.ContainsKey($NextPid)) {
                                $PassSeen[$NextPid] = $true;
                                $VisitQueue.Enqueue($NextPid);

                                if (-not $KnownTreePids.ContainsKey($NextPid)) {
                                    $KnownTreePids[$NextPid] = $true;
                                    try {
                                        # Keep each child handle open so we can WaitForExit after killing
                                        $ChildHandle        = [System.Diagnostics.Process]::GetProcessById($NextPid);
                                        $DescendantHandles += $ChildHandle;
                                        if (-not $ChildHandle.HasExited) {
                                            $LiveFoundInPass++;
                                            $ChildHandle.Kill();
                                        }
                                    } catch {
                                        [void]$_;
                                    }
                                }
                            }
                        }
                    }
                }

                # Stop scanning as soon as no live descendants remain
                if ($LiveFoundInPass -eq 0) {
                    break;
                }
            }

            # 3. Wait for kernel handle rundown (ObKillProcess) on both root and every descendant
            #    so working-directory and stdout/stderr pipe handles are guaranteed closed
            try {
                [void]$Process.WaitForExit(2000);
            } catch {
                [void]$_;
            }

            foreach ($DescHandle in $DescendantHandles) {
                if ($null -ne $DescHandle) {
                    try {
                        [void]$DescHandle.WaitForExit(2000);
                    } catch {
                        [void]$_;
                    }
                }
            }
        } finally {
            foreach ($DescHandle in $DescendantHandles) {
                if ($null -ne $DescHandle) {
                    $DescHandle.Dispose();
                }
            }
        }

        return;
    }

    # Unix / macOS fallback: enumerate descendant PIDs via 'pgrep -P' before calling Process.Kill($true)
    # so children are captured before POSIX reparents orphans to PID 1
    [array]$UnixDescendantHandles = @();

    try {
        [string]$PgrepPath = '/usr/bin/pgrep';
        if (-not [System.IO.File]::Exists($PgrepPath)) {
            $PgrepPath = 'pgrep';
        }

        $UnixQueue                = New-Object System.Collections.Queue;
        [hashtable]$UnixSeen      = @{ };
        $UnixSeen[$RootProcessId] = $true;
        $UnixQueue.Enqueue($RootProcessId);

        while ($UnixQueue.Count -gt 0) {
            [int]$ParentUnixPid = [int]$UnixQueue.Dequeue();
            $PgrepProcess       = New-Object System.Diagnostics.Process;

            try {
                $PgrepInfo                        = New-Object System.Diagnostics.ProcessStartInfo;
                $PgrepInfo.FileName               = $PgrepPath;
                $PgrepInfo.Arguments              = ('-P {0}' -f $ParentUnixPid);
                $PgrepInfo.UseShellExecute        = $false;
                $PgrepInfo.RedirectStandardOutput = $true;
                $PgrepInfo.RedirectStandardError  = $true;
                $PgrepInfo.CreateNoWindow         = $true;
                $PgrepProcess.StartInfo           = $PgrepInfo;
                [void]$PgrepProcess.Start();
                [string]$PgrepOut                 = $PgrepProcess.StandardOutput.ReadToEnd();
                [void]$PgrepProcess.WaitForExit(1000);

                if (-not [string]::IsNullOrWhiteSpace($PgrepOut)) {
                    foreach ($PidToken in ($PgrepOut -split '\s+')) {
                        [int]$ParsedUnixChild = 0;
                        if ([int]::TryParse($PidToken, [ref]$ParsedUnixChild) -and $ParsedUnixChild -gt 0 -and -not $UnixSeen.ContainsKey($ParsedUnixChild)) {
                            $UnixSeen[$ParsedUnixChild] = $true;
                            $UnixQueue.Enqueue($ParsedUnixChild);
                            try {
                                $UnixChildHandle        = [System.Diagnostics.Process]::GetProcessById($ParsedUnixChild);
                                $UnixDescendantHandles += $UnixChildHandle;
                            } catch {
                                [void]$_;
                            }
                        }
                    }
                }
            } catch {
                [void]$_;
            } finally {
                $PgrepProcess.Dispose();
            }
        }

        try {
            if (-not $Process.HasExited) {
                if ($PSVersionTable.PSVersion.Major -ge 6) {
                    $Process.Kill($true);
                } else {
                    $Process.Kill();
                }
            }
        } catch {
            [void]$_;
        }

        foreach ($UnixDescHandle in $UnixDescendantHandles) {
            if ($null -ne $UnixDescHandle) {
                try {
                    if (-not $UnixDescHandle.HasExited) {
                        $UnixDescHandle.Kill();
                    }
                } catch {
                    [void]$_;
                }
            }
        }

        try {
            [void]$Process.WaitForExit(2000);
        } catch {
            [void]$_;
        }

        foreach ($UnixDescHandle in $UnixDescendantHandles) {
            if ($null -ne $UnixDescHandle) {
                try {
                    [void]$UnixDescHandle.WaitForExit(2000);
                } catch {
                    [void]$_;
                }
            }
        }
    } finally {
        foreach ($UnixDescHandle in $UnixDescendantHandles) {
            if ($null -ne $UnixDescHandle) {
                $UnixDescHandle.Dispose();
            }
        }
    }
}

<#
.SYNOPSIS
Execute an approved external binary or batch check process with timeout control

.DESCRIPTION
Invoke-IcingaProtocolBinaryProcess runs an approved executable (.exe, .com, .cmd
or .bat) inside Get-ModuleBinaryDirectory via System.Diagnostics.Process with
UseShellExecute = $false:
1. Validates .cmd/.bat arguments against cmd.exe command, redirection and
   '%VAR%' expansion metacharacters before spawning a child process.
2. Escapes CLI tokens via Format-ModuleCommandLineArguments.
3. Captures StandardOutput and StandardError asynchronously (falling back to
   StandardError when StandardOutput is blank).
4. Enforces TimeoutMs across both process exit and output stream closure,
   terminating the entire process tree via Stop-IcingaProtocolProcessTree when
   exceeded.
5. Splits output and performance data via Split-IcingaBinaryPluginOutput.

.PARAMETER BinaryPath
| Name       | Type          | Description                                            | Default |
|------------|---------------|--------------------------------------------------------|---------|
| BinaryPath | System.String | Full canonical path to the approved binary executable. | ''      |

.PARAMETER CommandName
| Name        | Type          | Description                                          | Default |
|-------------|---------------|------------------------------------------------------|---------|
| CommandName | System.String | Display file name of the binary for status messages. | ''      |

.PARAMETER BinaryArguments
| Name            | Type            | Description                                         | Default |
|-----------------|-----------------|-----------------------------------------------------|---------|
| BinaryArguments | System.String[] | Ordered CLI argument tokens to pass to the process. | @()     |

.PARAMETER TimeoutMs
| Name      | Type         | Description                                                  | Default |
|-----------|--------------|--------------------------------------------------------------|---------|
| TimeoutMs | System.Int32 | Maximum execution window in milliseconds before termination. | 60000   |

.PARAMETER DefaultCommandLine
| Name               | Type          | Description                                              | Default |
|--------------------|---------------|----------------------------------------------------------|---------|
| DefaultCommandLine | System.String | Rendered command line reported in CheckResult telemetry. | ''      |

.OUTPUTS
System.Collections.Hashtable -- Hashtable containing ExitCode, Output,
PerformanceData and CommandLine.

.EXAMPLE
PS> Invoke-IcingaProtocolBinaryProcess -BinaryPath 'C:\ProgramData\IcingaForWindows\Binaries\check_load.exe' -CommandName 'check_load.exe' -BinaryArguments @('-w', '80%') -TimeoutMs 60000

Executes check_load.exe with a 60s timeout and splits its Nagios output.

.NOTES
Always disposes the root Process handle in finally.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaProtocolBinaryProcess()
{
    param (
        [string]$BinaryPath         = '',
        [string]$CommandName        = '',
        [string[]]$BinaryArguments  = @(),
        [int]$TimeoutMs             = 60000,
        [string]$DefaultCommandLine = ''
    );

    # 1. Guard Windows batch scripts (.cmd / .bat) against cmd.exe command/redirection/expansion metacharacters.
    #    Standalone percent thresholds such as '80%' remain allowed, while paired '%VAR%' tokens and '&|<>^"!' are blocked.
    [bool]$IsBatchScript = ($BinaryPath.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase) -or $BinaryPath.EndsWith('.bat', [System.StringComparison]::OrdinalIgnoreCase));

    if ($IsBatchScript -and $null -ne $BinaryArguments) {
        foreach ($BatchCandidate in $BinaryArguments) {
            [string]$BatchText = [string]$BatchCandidate;
            if ($BatchText -match '[&|<>^\r\n"!]|%[^%]*%') {
                return @{
                    'ExitCode'        = 3;
                    'Output'          = ('[UNKNOWN] Argument for batch script "{0}" contains forbidden cmd.exe metacharacters' -f $CommandName);
                    'PerformanceData' = @();
                    'CommandLine'     = $DefaultCommandLine;
                };
            }
        }
    }

    [int]$ExitCode                    = 3;
    [string]$CheckOutput              = '';
    [array]$CheckPerfData             = @();

    # 2. Configure Win32 ProcessStartInfo with canonical full path (UseShellExecute = $false avoids $env:PATH & shell injection)
    $StartInfo                        = New-Object System.Diagnostics.ProcessStartInfo;
    $StartInfo.FileName               = $BinaryPath;
    $StartInfo.Arguments              = Format-ModuleCommandLineArguments -Arguments $BinaryArguments;
    $StartInfo.WorkingDirectory       = [System.IO.Path]::GetDirectoryName($BinaryPath);
    $StartInfo.UseShellExecute        = $false;
    $StartInfo.RedirectStandardOutput = $true;
    $StartInfo.RedirectStandardError  = $true;
    $StartInfo.CreateNoWindow         = $true;

    $Process                          = New-Object System.Diagnostics.Process;

    try {
        $ProcWatch          = [System.Diagnostics.Stopwatch]::StartNew();
        $Process.StartInfo  = $StartInfo;
        [void]$Process.Start();

        # Start async stream reads immediately before WaitForExit so >4 KB stdout/stderr output never deadlocks OS pipe buffers
        [int]$RootPid       = $Process.Id;
        [bool]$TimedOut     = $false;
        [string]$TimeoutMsg = '';
        $StdoutTask         = $Process.StandardOutput.ReadToEndAsync();
        $StderrTask         = $Process.StandardError.ReadToEndAsync();

        # 3. Enforce check_timeout on both the root process exit and full closure of inherited stdout/stderr pipes
        if (-not $Process.WaitForExit($TimeoutMs)) {
            $TimedOut   = $true;
            $TimeoutMsg = ('[UNKNOWN] External binary check "{0}" timed out after {1}s' -f $CommandName, [System.Math]::Round(($TimeoutMs / 1000.0), 2));
        } else {
            $ProcWatch.Stop();
            [int]$RemainingMs  = [System.Math]::Max(100, ($TimeoutMs - [int]$ProcWatch.ElapsedMilliseconds));
            [bool]$StreamsDone = [System.Threading.Tasks.Task]::WaitAll(@( $StdoutTask, $StderrTask ), $RemainingMs);

            if (-not $StreamsDone) {
                $TimedOut   = $true;
                $TimeoutMsg = ('[UNKNOWN] External binary check "{0}" timed out after {1}s while waiting for output streams to close' -f $CommandName, [System.Math]::Round(($TimeoutMs / 1000.0), 2));
            }
        }

        if ($TimedOut) {
            # Terminate root and all orphaned descendant processes holding pipes or working-directory locks
            Stop-IcingaProtocolProcessTree -Process $Process -RootProcessId $RootPid;

            try {
                [void][System.Threading.Tasks.Task]::WaitAll(@( $StdoutTask, $StderrTask ), 500);
            } catch {
                [void]$_;
            }

            $ExitCode    = 3;
            $CheckOutput = $TimeoutMsg;
        } else {
            # 4. Collect stdout (falling back to stderr when stdout is blank) and split Nagios/Icinga '|' perfdata
            [string]$StdoutText = '';
            [string]$StderrText = '';

            if ($StdoutTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $StdoutText = [string]$StdoutTask.Result;
            }
            if ($StderrTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                $StderrText = [string]$StderrTask.Result;
            }

            [string]$Effective = $StdoutText;
            if ([string]::IsNullOrWhiteSpace($Effective) -and -not [string]::IsNullOrWhiteSpace($StderrText)) {
                $Effective = $StderrText;
            }

            [hashtable]$SplitBinary = Split-IcingaBinaryPluginOutput -RawOutput $Effective;
            $CheckOutput            = [string]$SplitBinary['Output'];
            $CheckPerfData          = @($SplitBinary['PerformanceData']);
            $ExitCode               = [int]$Process.ExitCode;
        }
    } catch {
        $ExitCode    = 3;
        $CheckOutput = ('[UNKNOWN] External binary check "{0}" failed to execute: {1}' -f $CommandName, $_.Exception.Message);
    } finally {
        $Process.Dispose();
    }

    return @{
        'ExitCode'        = [int]$ExitCode;
        'Output'          = [string]$CheckOutput;
        'PerformanceData' = [array]$CheckPerfData;
        'CommandLine'     = $DefaultCommandLine;
    };
}

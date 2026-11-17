<#
.SYNOPSIS
Check the state, exit code, missed runs and run times of Windows scheduled tasks

.DESCRIPTION
Reads scheduled tasks through Get-IcingaScheduledTask and builds an IcingaPlugin
container named 'Scheduled Tasks' grouped by task path. Each task becomes a child
package containing checks for its State, Missed Runs, Last Task Result, Last Run
Time and Next Run Time. State is compared against the allowed State list (when
provided) using CheckNotIn, raising CRITICAL when the task is not in any of the
expected states. Missed Runs is evaluated against WarningMissedRuns and
CriticalMissedRuns using the Icinga range grammar. Last Task Result treats
Windows Scheduler informational codes 267009 (0x41301, SCHED_S_TASK_RUNNING,
while the task State is Running) and 267011 (0x41303, SCHED_S_TASK_HAS_NOT_RUN)
as OK by default, and raises CRITICAL on any other non-zero exit code unless
IgnoreLastRunTime (aliased to IgnoreLastResult and IgnoreExitCode) is set or the
code is listed in IgnoreExitCodes (decimal, unsigned and 32-bit masked hex
representations such as '0x80070005' or '0x41301' are all accepted). Last Run
Time and Next Run Time measure the offset in seconds between the current time
and the timestamp (Last Run Time counts up since the last execution, Next Run
Time counts down until the next scheduled execution, and 0s is rendered as
'Never' when unset) and are evaluated against their respective duration
thresholds.

Explicit task names in TaskName (without wildcards) that do not exist on the host
are reported with the state chosen by OverrideNotFound (UNKNOWN by default). When
no task matches the filter at all, the plugin returns UNKNOWN, or OK when
MitigateUnknown (aliased to IgnoreEmptyChecks) is set.

Performance data uses the labels '<path_taskname>::ifw_scheduledtask::state',
'::missedruns', '::lasttaskresult', '::lastruntime' and '::nextruntime'.

.PARAMETER TaskName
| Name     | Type         | Description                                                      | Default |
|----------|--------------|------------------------------------------------------------------|---------|
| TaskName | System.Array | Task names to check (wildcards allowed; plain names must exist). | @()     |

.PARAMETER ExcludeTaskName
| Name            | Type         | Description                                               | Default |
|-----------------|--------------|-----------------------------------------------------------|---------|
| ExcludeTaskName | System.Array | Task names to exclude from the check (wildcards allowed). | @()     |

.PARAMETER TaskPath
| Name     | Type         | Description                                                         | Default |
|----------|--------------|---------------------------------------------------------------------|---------|
| TaskPath | System.Array | Task folder paths to include (wildcards allowed, e.g. '\Icinga\*'). | @()     |

.PARAMETER ExcludeTaskPath
| Name            | Type         | Description                                       | Default |
|-----------------|--------------|---------------------------------------------------|---------|
| ExcludeTaskPath | System.Array | Task folder paths to exclude (wildcards allowed). | @()     |

.PARAMETER State
| Name  | Type                        | Description                                                                | Default |
|-------|-----------------------------|----------------------------------------------------------------------------|---------|
| State | IcingaScheduledTaskStatus[] | Allowed task states ('Unknown', 'Disabled', 'Queued', 'Ready', 'Running'). | @()     |

.PARAMETER IgnoreExitCodes
| Name            | Type         | Description                                                            | Default |
|-----------------|--------------|------------------------------------------------------------------------|---------|
| IgnoreExitCodes | System.Array | Non-zero task exit codes to treat as OK (decimal or hex, e.g. 267009). | @()     |

.PARAMETER WarningMissedRuns
| Name              | Type          | Description                                      | Default |
|-------------------|---------------|--------------------------------------------------|---------|
| WarningMissedRuns | System.String | Warning threshold for the number of missed runs. |         |

.PARAMETER CriticalMissedRuns
| Name               | Type          | Description                                       | Default |
|--------------------|---------------|---------------------------------------------------|---------|
| CriticalMissedRuns | System.String | Critical threshold for the number of missed runs. |         |

.PARAMETER WarningLastRunTime
| Name               | Type          | Description                                                       | Default |
|--------------------|---------------|-------------------------------------------------------------------|---------|
| WarningLastRunTime | System.String | Warning threshold for the age of the last run (e.g. '1d', '12h'). |         |

.PARAMETER CriticalLastRunTime
| Name                | Type          | Description                                                        | Default |
|---------------------|---------------|--------------------------------------------------------------------|---------|
| CriticalLastRunTime | System.String | Critical threshold for the age of the last run (e.g. '2d', '24h'). |         |

.PARAMETER WarningNextRunTime
| Name               | Type          | Description                                                     | Default |
|--------------------|---------------|-----------------------------------------------------------------|---------|
| WarningNextRunTime | System.String | Warning threshold for the next run offset (e.g. '10m', '-1h:'). |         |

.PARAMETER CriticalNextRunTime
| Name                | Type          | Description                                                      | Default |
|---------------------|---------------|------------------------------------------------------------------|---------|
| CriticalNextRunTime | System.String | Critical threshold for the next run offset (e.g. '30m', '-2h:'). |         |

.PARAMETER IgnoreLastRunTime
| Name              | Type                                         | Description                                      | Default |
|-------------------|----------------------------------------------|--------------------------------------------------|---------|
| IgnoreLastRunTime | System.Management.Automation.SwitchParameter | Do not alert on non-zero Last Task Result codes. | False   |

.PARAMETER MitigateUnknown
| Name            | Type                                         | Description                                                   | Default |
|-----------------|----------------------------------------------|---------------------------------------------------------------|---------|
| MitigateUnknown | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no task matches the filter. | False   |

.PARAMETER OverrideNotFound
| Name             | Type          | Description                                                                | Default |
|------------------|---------------|----------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State for missing required tasks ('Ok', 'Warning', 'Critical', 'Unknown'). | Unknown |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                         | Default |
|-----------|--------------|-------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config. | 0       |

.PARAMETER NoPerfData
| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

.OUTPUTS
System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

.EXAMPLE
PS> Invoke-IcingaCheckScheduledTask -TaskName 'AutomaticBackup', 'Windows Backup Monitor' -State 'Ready'

Checks that both backup tasks exist and are in the Ready state.

.EXAMPLE
PS> Invoke-IcingaCheckScheduledTask -TaskPath '\Icinga\*' -State 'Ready', 'Running' -WarningLastRunTime '1d' -Verbosity 2

Checks all tasks under \Icinga\ for Ready or Running state and warns if a task has not run within the last day.

.NOTES
Windows-only. Queries tasks through Get-IcingaScheduledTask. The integer exit code
is the return value; an Icinga command wrapper is expected to exit with it.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaCheckScheduledTask()
{
    param (
        [array]$TaskName                    = @(),
        [array]$ExcludeTaskName             = @(),
        [array]$TaskPath                    = @(),
        [array]$ExcludeTaskPath             = @(),
        [IcingaScheduledTaskStatus[]]$State = @(),
        [array]$IgnoreExitCodes             = @(),
        [string]$WarningMissedRuns          = '',
        [string]$CriticalMissedRuns         = '',
        [string]$WarningLastRunTime         = '',
        [string]$CriticalLastRunTime        = '',
        [string]$WarningNextRunTime         = '',
        [string]$CriticalNextRunTime        = '',
        [Alias('IgnoreLastResult', 'IgnoreExitCode')]
        [switch]$IgnoreLastRunTime          = $false,
        [Alias('IgnoreEmptyChecks')]
        [switch]$MitigateUnknown            = $false,
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotFound           = 'Unknown',
        [int]$Verbosity                     = 0,
        [switch]$NoPerfData                 = $false
    );

    $CheckPackage            = New-IcingaPlugin 'Scheduled Tasks';
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    $Data                    = Get-IcingaScheduledTask -TaskName $TaskName -ExcludeTaskName $ExcludeTaskName -TaskPath $TaskPath -ExcludeTaskPath $ExcludeTaskPath;

    if (Test-IcingaError -InputObject $Data) {
        return $CheckPackage.SetError($Data).Compile();
    }

    foreach ($PathKey in (ConvertTo-IcingaSortedArray -InputObject @($Data.Tasks.Keys))) {
        $PathPackage = New-IcingaPlugin $PathKey;

        foreach ($Task in $Data.Tasks[$PathKey]) {
            $TaskPackage         = New-IcingaPlugin $Task.TaskName;
            [string]$MetricIndex = ([string]::Format('{0}{1}', $Task.TaskPath, $Task.TaskName)).Trim('\').Replace('\', '_');

            $TaskState           = (New-IcingaPlugin 'State' $Task.State).
                Translate().
                MetricIndex($MetricIndex).
                MetricLabel('state');

            if ($State.Count -ne 0) {
                $TaskState.Critical($State).CheckNotIn().Commit();
            }

            $TaskMissedRuns = (New-IcingaPlugin 'Missed Runs' $Task.MissedRuns).
                MetricIndex($MetricIndex).
                MetricLabel('missedruns');

            if ('' -ne $WarningMissedRuns -or '' -ne $CriticalMissedRuns) {
                $TaskMissedRuns.Warning($WarningMissedRuns).Critical($CriticalMissedRuns).CheckRange().Commit();
            }

            $TaskLastResult        = (New-IcingaPlugin 'Last Task Result' $Task.LastTaskResult).
                MetricIndex($MetricIndex).
                MetricLabel('lasttaskresult');

            [bool]$ExitCodeIgnored = [bool]$IgnoreLastRunTime;

            # Windows Task Scheduler reports non-zero status codes that do not represent failed runs:
            # - 267011 (0x00041303, SCHED_S_TASK_HAS_NOT_RUN): newly created task that has never executed yet
            # - 267009 (0x00041301, SCHED_S_TASK_RUNNING): task is actively running right now
            if (-not $ExitCodeIgnored) {
                if ($Task.LastTaskResult -eq 267011) {
                    $ExitCodeIgnored = $true;
                } elseif ($Task.LastTaskResult -eq 267009 -and $Task.State -eq [IcingaScheduledTaskStatus]::Running) {
                    $ExitCodeIgnored = $true;
                }
            }

            if (-not $ExitCodeIgnored -and $Task.LastTaskResult -ne 0) {
                # Mask to unsigned 32-bit before hex formatting so negative HRESULTs stored in [int64]
                # (e.g. -2147024891) format as '0x80070005' instead of 64-bit '0xFFFFFFFF80070005'
                [int64]$MaskedResult  = ([int64]$Task.LastTaskResult -band 0xFFFFFFFFL);
                [string]$ExitDecimal  = [string]$Task.LastTaskResult;
                [string]$ExitUnsigned = [string]$MaskedResult;
                [string]$ExitHex      = [string]::Format('{0:X}', $MaskedResult);
                [string]$ExitHex0x    = [string]::Format('0x{0:X}', $MaskedResult);
                [string]$ExitHex8     = [string]::Format('{0:X8}', $MaskedResult);
                [string]$ExitHex80x   = [string]::Format('0x{0:X8}', $MaskedResult);

                foreach ($IgnoredCode in $IgnoreExitCodes) {
                    if ($null -eq $IgnoredCode) {
                        continue;
                    }

                    [string]$CodeText = ([string]$IgnoredCode).Trim();
                    if ('' -eq $CodeText) {
                        continue;
                    }

                    [bool]$MatchesDec = ($CodeText -ieq $ExitDecimal -or $CodeText -ieq $ExitUnsigned);
                    [bool]$MatchesHex = ($CodeText -ieq $ExitHex -or $CodeText -ieq $ExitHex0x -or $CodeText -ieq $ExitHex8 -or $CodeText -ieq $ExitHex80x);

                    if ($MatchesDec -or $MatchesHex) {
                        $ExitCodeIgnored = $true;
                        break;
                    }
                }
            }

            if ($Task.LastTaskResult -ne 0 -and -not $ExitCodeIgnored) {
                $TaskLastResult.SetCritical([string]::Format('Task exited with code {0}', $Task.LastTaskResult), $true).Commit();
            }

            [string]$LastRunDateText = $Task.LastRunTime;
            if ([string]::IsNullOrEmpty($LastRunDateText)) {
                $LastRunDateText = 'Never';
            }

            $TaskLastRunTime = (New-IcingaPlugin ([string]::Format('Last Run Time [{0}]', $LastRunDateText)) $Task.LastRunOffset 's').
                Translate(@{ 0 = 'Never' }).
                MetricIndex($MetricIndex).
                MetricLabel('lastruntime');

            if ('' -ne $WarningLastRunTime -or '' -ne $CriticalLastRunTime) {
                $TaskLastRunTime.Warning($WarningLastRunTime).Critical($CriticalLastRunTime).CheckRange().Commit();
            }

            [string]$NextRunDateText = $Task.NextRunTime;
            if ([string]::IsNullOrEmpty($NextRunDateText)) {
                $NextRunDateText = 'Never';
            }

            $TaskNextRunTime = (New-IcingaPlugin ([string]::Format('Next Run Time [{0}]', $NextRunDateText)) $Task.NextRunOffset 's').
                Translate(@{ 0 = 'Never' }).
                MetricIndex($MetricIndex).
                MetricLabel('nextruntime');

            if ('' -ne $WarningNextRunTime -or '' -ne $CriticalNextRunTime) {
                $TaskNextRunTime.Warning($WarningNextRunTime).Critical($CriticalNextRunTime).CheckRange().Commit();
            }

            $TaskPackage.
                AddCheck($TaskState).
                AddCheck($TaskMissedRuns).
                AddCheck($TaskLastResult).
                AddCheck($TaskLastRunTime).
                AddCheck($TaskNextRunTime).
                Commit();

            $PathPackage.AddCheck($TaskPackage).Commit();
        }

        if ($PathPackage.HasChecks()) {
            $CheckPackage.AddCheck($PathPackage).Commit();
        }
    }

    [array]$RequiredTasks = @();

    foreach ($Filter in $TaskName) {
        if ($null -ne $Filter -and [string]::IsNullOrEmpty([string]$Filter) -eq $false -and [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters([string]$Filter) -eq $false) {
            $RequiredTasks += [string]$Filter;
        }
    }

    $CheckPackage.AddMissingChecks($RequiredTasks, $Data.TaskNames, '{0}', 'Task not found', $OverrideNotFound).Commit();

    if ($CheckPackage.HasChecks() -eq $false) {
        if ($MitigateUnknown) {
            return $CheckPackage.SetOk('No scheduled task matches the given filter', $true).Compile();
        }

        return $CheckPackage.SetError('No scheduled task matches the given filter').Compile();
    }

    return $CheckPackage.Compile();
}

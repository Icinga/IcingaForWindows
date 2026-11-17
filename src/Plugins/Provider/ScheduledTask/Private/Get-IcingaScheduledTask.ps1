<#
.SYNOPSIS
Collect Windows scheduled tasks and their runtime metadata

.DESCRIPTION
Get-IcingaScheduledTask is the data source for Invoke-IcingaCheckScheduledTask.
It queries all scheduled tasks via Get-ScheduledTask, filters them by TaskPath,
ExcludeTaskPath, TaskName and ExcludeTaskName (wildcards supported), and enriches
each matching task with runtime information from Get-ScheduledTaskInfo (last run
time, next run time, last task result and number of missed runs).

Run timestamps are returned both as formatted invariant strings
('yyyy/MM/dd HH:mm:ss', or '' when never run / not scheduled) and as offsets in
seconds relative to the current time (LastRunOffset counts up from the last run,
NextRunOffset counts down to the next scheduled run, 0 when unset). Tasks are
grouped by TaskPath and sorted by TaskName.

.PARAMETER TaskName
| Name     | Type         | Description                                                  | Default |
|----------|--------------|--------------------------------------------------------------|---------|
| TaskName | System.Array | Only collect tasks matching these names (wildcards allowed). | @()     |

.PARAMETER ExcludeTaskName
| Name            | Type         | Description                                          | Default |
|-----------------|--------------|------------------------------------------------------|---------|
| ExcludeTaskName | System.Array | Skip tasks matching these names (wildcards allowed). | @()     |

.PARAMETER TaskPath
| Name     | Type         | Description                                                  | Default |
|----------|--------------|--------------------------------------------------------------|---------|
| TaskPath | System.Array | Only collect tasks matching these paths (wildcards allowed). | @()     |

.PARAMETER ExcludeTaskPath
| Name            | Type         | Description                                          | Default |
|-----------------|--------------|------------------------------------------------------|---------|
| ExcludeTaskPath | System.Array | Skip tasks matching these paths (wildcards allowed). | @()     |

.OUTPUTS
System.Collections.Hashtable -- Hashtable with keys Tasks (hashtable keyed by
TaskPath containing arrays of task hashtables) and TaskNames (array of known task
names after path and exclude filtering), or an IcingaError when querying failed.

.EXAMPLE
PS> Get-IcingaScheduledTask -TaskPath '\Icinga\*'

Returns all scheduled tasks under the \Icinga\ task path hierarchy.

.NOTES
Windows-only. Relies on Get-ScheduledTask and Get-ScheduledTaskInfo from the
ScheduledTasks module.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-IcingaScheduledTask()
{
    param (
        [array]$TaskName        = @(),
        [array]$ExcludeTaskName = @(),
        [array]$TaskPath        = @(),
        [array]$ExcludeTaskPath = @()
    );

    if ($null -eq (Get-Command -Name 'Get-ScheduledTask' -ErrorAction SilentlyContinue)) {
        [hashtable]$ErrorData = @{ 'Command' = 'Get-ScheduledTask'; };
        return (Write-FunctionReturnValue -ReturnValue 'ScheduledTaskQueryFailed' -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new('ScheduledTaskQueryFailed', 'The ScheduledTasks cmdlet Get-ScheduledTask is not available on this system', $ErrorData)));
    }

    [array]$RawTasks = @();

    try {
        $RawTasks = @(Get-ScheduledTask -TaskName '*' -ErrorAction Stop);
    } catch {
        [string]$ErrorMessage = $_.Exception.Message;
        [hashtable]$ErrorData = @{ 'Error' = $ErrorMessage; };
        return (Write-FunctionReturnValue -ReturnValue 'ScheduledTaskQueryFailed' -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new('ScheduledTaskQueryFailed', ('Failed to query scheduled tasks: {0}' -f $ErrorMessage), $ErrorData)));
    }

    [hashtable]$GroupedTasks = @{ };
    [hashtable]$KnownNames   = @{ };
    $StatusMap               = 'IcingaScheduledTaskStatusMap' -as [type];
    [datetime]$Now           = [datetime]::Now;

    foreach ($Task in (ConvertTo-IcingaSortedArray -InputObject $RawTasks -Property 'TaskName')) {
        if ($null -eq $Task) {
            continue;
        }

        [string]$Name = [string]$Task.TaskName;
        [string]$Path = [string]$Task.TaskPath;

        if ([string]::IsNullOrEmpty($Name) -or [string]::IsNullOrEmpty($Path)) {
            continue;
        }

        if ((Test-IcingaArrayFilter -InputObject $Path -Include $TaskPath -Exclude $ExcludeTaskPath) -eq $false) {
            continue;
        }

        if ((Test-IcingaArrayFilter -InputObject $Name -Exclude $ExcludeTaskName) -eq $false) {
            continue;
        }

        $KnownNames[$Name] = $true;

        if ((Test-IcingaArrayFilter -InputObject $Name -Include $TaskName) -eq $false) {
            continue;
        }

        $TaskInfo = $null;
        try {
            $TaskInfo = Get-ScheduledTaskInfo -TaskName $Name -TaskPath $Path -ErrorAction SilentlyContinue;
        } catch {
            $TaskInfo = $null;
        }

        [string]$LastRunTime   = '';
        [double]$LastRunOffset = 0;
        [string]$NextRunTime   = '';
        [double]$NextRunOffset = 0;
        [int]$MissedRuns       = 0;
        [int64]$LastTaskResult = 0;

        if ($null -ne $TaskInfo) {
            if ($null -ne $TaskInfo.NumberOfMissedRuns) {
                $MissedRuns = [int]$TaskInfo.NumberOfMissedRuns;
            }

            if ($null -ne $TaskInfo.LastTaskResult) {
                $LastTaskResult = [int64]$TaskInfo.LastTaskResult;
            }

            if ($null -ne $TaskInfo.LastRunTime) {
                [datetime]$ParsedLast = [datetime]::MinValue;
                if ($TaskInfo.LastRunTime -is [datetime]) {
                    $ParsedLast = [datetime]$TaskInfo.LastRunTime;
                } else {
                    [void][datetime]::TryParse([string]$TaskInfo.LastRunTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedLast);
                }

                # Windows Task Scheduler reports 1999-11-30 00:00:00 with result 267011
                # (SCHED_S_TASK_HAS_NOT_RUN) when a task has never been executed.
                [bool]$NeverRunSentinel = ($ParsedLast.Year -eq 1999 -and $ParsedLast.Month -eq 11 -and $ParsedLast.Day -eq 30 -and $LastTaskResult -eq 267011);

                if ($ParsedLast.Year -gt 1970 -and -not $NeverRunSentinel) {
                    $LastRunTime   = $ParsedLast.ToString('yyyy/MM/dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture);
                    $LastRunOffset = [System.Math]::Round(($Now - $ParsedLast).TotalSeconds, 0);
                }
            }

            if ($null -ne $TaskInfo.NextRunTime) {
                [datetime]$ParsedNext = [datetime]::MinValue;
                if ($TaskInfo.NextRunTime -is [datetime]) {
                    $ParsedNext = [datetime]$TaskInfo.NextRunTime;
                } else {
                    [void][datetime]::TryParse([string]$TaskInfo.NextRunTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedNext);
                }

                if ($ParsedNext.Year -gt 1970) {
                    $NextRunTime   = $ParsedNext.ToString('yyyy/MM/dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture);
                    $NextRunOffset = [System.Math]::Round(($ParsedNext - $Now).TotalSeconds, 0);
                }
            }
        }

        [hashtable]$TaskEntry = @{
            'TaskName'       = $Name;
            'TaskPath'       = $Path;
            'State'          = $StatusMap::Resolve($Task.State);
            'LastRunTime'    = $LastRunTime;
            'LastRunOffset'  = $LastRunOffset;
            'NextRunTime'    = $NextRunTime;
            'NextRunOffset'  = $NextRunOffset;
            'MissedRuns'     = $MissedRuns;
            'LastTaskResult' = $LastTaskResult;
        };

        if ($GroupedTasks.ContainsKey($Path) -eq $false) {
            $GroupedTasks[$Path] = @($TaskEntry);
        } else {
            $GroupedTasks[$Path] += $TaskEntry;
        }
    }

    [hashtable]$Result = @{
        'Tasks'     = $GroupedTasks;
        'TaskNames' = @($KnownNames.Keys);
    };

    return (Write-FunctionReturnValue -ReturnValue 'ScheduledTaskInformationCollected' -Data @{ 'Count' = $GroupedTasks.Count; } -OverrideReturn $Result);
}

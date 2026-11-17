<#
.SYNOPSIS
Check the CPU, memory, page file and thread usage of processes against thresholds

.DESCRIPTION
Reads every process once through Get-IcingaProcessInformation and builds a single
IcingaPlugin container named 'Process Overview'. Every process name becomes a
package with one package per process ('<name> [<pid>]') and a '<name> Summary'
package holding the sums of all processes with that name. Each of them checks the
page file usage, the memory usage (private working set), the CPU usage and the
thread count; the summary also checks the process count.

The thresholds without 'Total' apply to every single process, the 'Total'
thresholds to the summary. Memory thresholds accept sizes ('500MB') and
percentages of the installed memory ('5%'). The page file usage is the commit
charge of the process; its percentages relate to the commit limit (installed
memory plus page files), because a commit charge can exceed the page file size. The CPU
usage is in percent of the whole machine (all logical processors), so '80' or
'80%' means 80 percent of the machine like in the task manager. All thresholds
accept the full Icinga range grammar.

Process and ExcludeProcess select the processes by name without '.exe'
(wildcards allowed). Every entry of Process that matches no running process is
reported with the state chosen with OverrideNotFound (UNKNOWN by default). Without
Process every process is checked; for a plain process count of the whole system
this is more output than needed.

Performance data is written for the summary only, with the labels
'<name>::ifw_process::cpu', '::memory', '::pagefile', '::threads' and '::count'.

.PARAMETER PageFileWarning
| Name            | Type          | Description                                                | Default |
|-----------------|---------------|------------------------------------------------------------|---------|
| PageFileWarning | System.String | Warning threshold for the page file usage of each process. |         |

.PARAMETER PageFileCritical
| Name             | Type          | Description                                                 | Default |
|------------------|---------------|-------------------------------------------------------------|---------|
| PageFileCritical | System.String | Critical threshold for the page file usage of each process. |         |

.PARAMETER MemoryWarning
| Name          | Type          | Description                                             | Default |
|---------------|---------------|---------------------------------------------------------|---------|
| MemoryWarning | System.String | Warning threshold for the memory usage of each process. |         |

.PARAMETER MemoryCritical
| Name           | Type          | Description                                              | Default |
|----------------|---------------|----------------------------------------------------------|---------|
| MemoryCritical | System.String | Critical threshold for the memory usage of each process. |         |

.PARAMETER CPUWarning
| Name       | Type          | Description                                          | Default |
|------------|---------------|------------------------------------------------------|---------|
| CPUWarning | System.String | Warning threshold for the CPU usage of each process. |         |

.PARAMETER CPUCritical
| Name        | Type          | Description                                           | Default |
|-------------|---------------|-------------------------------------------------------|---------|
| CPUCritical | System.String | Critical threshold for the CPU usage of each process. |         |

.PARAMETER ThreadCountWarning
| Name               | Type          | Description                                             | Default |
|--------------------|---------------|---------------------------------------------------------|---------|
| ThreadCountWarning | System.String | Warning threshold for the thread count of each process. |         |

.PARAMETER ThreadCountCritical
| Name                | Type          | Description                                              | Default |
|---------------------|---------------|----------------------------------------------------------|---------|
| ThreadCountCritical | System.String | Critical threshold for the thread count of each process. |         |

.PARAMETER TotalPageFileWarning
| Name                 | Type          | Description                                                           | Default |
|----------------------|---------------|-----------------------------------------------------------------------|---------|
| TotalPageFileWarning | System.String | Warning threshold for the page file usage of all processes of a name. |         |

.PARAMETER TotalPageFileCritical
| Name                  | Type          | Description                                                            | Default |
|-----------------------|---------------|------------------------------------------------------------------------|---------|
| TotalPageFileCritical | System.String | Critical threshold for the page file usage of all processes of a name. |         |

.PARAMETER TotalMemoryWarning
| Name               | Type          | Description                                                        | Default |
|--------------------|---------------|--------------------------------------------------------------------|---------|
| TotalMemoryWarning | System.String | Warning threshold for the memory usage of all processes of a name. |         |

.PARAMETER TotalMemoryCritical
| Name                | Type          | Description                                                         | Default |
|---------------------|---------------|---------------------------------------------------------------------|---------|
| TotalMemoryCritical | System.String | Critical threshold for the memory usage of all processes of a name. |         |

.PARAMETER TotalCPUWarning
| Name            | Type          | Description                                                     | Default |
|-----------------|---------------|-----------------------------------------------------------------|---------|
| TotalCPUWarning | System.String | Warning threshold for the CPU usage of all processes of a name. |         |

.PARAMETER TotalCPUCritical
| Name             | Type          | Description                                                      | Default |
|------------------|---------------|------------------------------------------------------------------|---------|
| TotalCPUCritical | System.String | Critical threshold for the CPU usage of all processes of a name. |         |

.PARAMETER TotalThreadCountWarning
| Name                    | Type          | Description                                                        | Default |
|-------------------------|---------------|--------------------------------------------------------------------|---------|
| TotalThreadCountWarning | System.String | Warning threshold for the thread count of all processes of a name. |         |

.PARAMETER TotalThreadCountCritical
| Name                     | Type          | Description                                                         | Default |
|--------------------------|---------------|---------------------------------------------------------------------|---------|
| TotalThreadCountCritical | System.String | Critical threshold for the thread count of all processes of a name. |         |

.PARAMETER TotalProcessCountWarning
| Name                     | Type          | Description                                              | Default |
|--------------------------|---------------|----------------------------------------------------------|---------|
| TotalProcessCountWarning | System.String | Warning threshold for the number of processes of a name. |         |

.PARAMETER TotalProcessCountCritical
| Name                      | Type          | Description                                               | Default |
|---------------------------|---------------|-----------------------------------------------------------|---------|
| TotalProcessCountCritical | System.String | Critical threshold for the number of processes of a name. |         |

.PARAMETER Process
| Name    | Type         | Description                                                                 | Default |
|---------|--------------|-----------------------------------------------------------------------------|---------|
| Process | System.Array | Process names without '.exe' to check, wildcards allowed. Empty checks all. | @()     |

.PARAMETER ExcludeProcess
| Name           | Type         | Description                               | Default |
|----------------|--------------|-------------------------------------------|---------|
| ExcludeProcess | System.Array | Process names to skip, wildcards allowed. | @()     |

.PARAMETER OverrideNotFound
| Name             | Type          | Description                                                                  | Default |
|------------------|---------------|------------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State for a Process entry without a match: Ok, Warning, Critical or Unknown. | Unknown |

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
PS> Invoke-IcingaCheckProcess -Process 'powershell' -Verbosity 2

Lists every PowerShell process and the summary of all of them.

.EXAMPLE
PS> Invoke-IcingaCheckProcess -Process 'sqlservr' -CPUWarning '80' -TotalMemoryCritical '90%' -TotalProcessCountCritical '1:'

Warns when one SQL Server process uses more than 80 percent of the machine, and
goes critical when all of them use more than 90 percent of the memory or none runs.

.NOTES
Windows-only. Reads the '\Process(*)' performance counters ('Performance Monitor
Users'), '\Memory\Commit Limit' and the Win32_ComputerSystem CIM class through
Get-IcingaProcessInformation. The integer exit code is the return value; an Icinga
command wrapper is expected to exit with it.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaCheckProcess()
{
    param (
        [string]$PageFileWarning           = '',
        [string]$PageFileCritical          = '',
        [string]$MemoryWarning             = '',
        [string]$MemoryCritical            = '',
        [string]$CPUWarning                = '',
        [string]$CPUCritical               = '',
        [string]$ThreadCountWarning        = '',
        [string]$ThreadCountCritical       = '',
        [string]$TotalPageFileWarning      = '',
        [string]$TotalPageFileCritical     = '',
        [string]$TotalMemoryWarning        = '',
        [string]$TotalMemoryCritical       = '',
        [string]$TotalCPUWarning           = '',
        [string]$TotalCPUCritical          = '',
        [string]$TotalThreadCountWarning   = '',
        [string]$TotalThreadCountCritical  = '',
        [string]$TotalProcessCountWarning  = '',
        [string]$TotalProcessCountCritical = '',
        [array]$Process                    = @(),
        [array]$ExcludeProcess             = @(),
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotFound          = 'Unknown',
        [int]$Verbosity                    = 0,
        [switch]$NoPerfData                = $false
    );

    $CheckPackage            = New-IcingaPlugin 'Process Overview';
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    $Data                    = Get-IcingaProcessInformation -Include $Process -Exclude $ExcludeProcess;

    if (Test-IcingaError -InputObject $Data) {
        return $CheckPackage.SetError($Data).Compile();
    }

    foreach ($Name in (ConvertTo-IcingaSortedArray -InputObject @($Data.Processes.Keys))) {
        $Entry           = $Data.Processes[$Name];
        $ProcessPackage  = New-IcingaPlugin $Name;
        [array]$Packages = @();

        # Every package with its metrics: name, value, unit, base value, warning,
        # critical and perfdata label. Single processes write no performance data.
        foreach ($Id in (ConvertTo-IcingaSortedArray -InputObject @($Entry.Instances.Keys))) {
            $Instance  = $Entry.Instances[$Id];
            $Packages += ,@(
                (New-IcingaPlugin ([string]::Format('{0} [{1}]', $Name, $Id))),
                @(
                    @('Page File Usage', $Instance.PageFile, 'B', $Data.CommitLimit, $PageFileWarning, $PageFileCritical, ''),
                    @('Memory Usage', $Instance.Memory, 'B', $Data.MemoryTotal, $MemoryWarning, $MemoryCritical, ''),
                    @('CPU Usage', $Instance.Cpu, '%', 100, $CPUWarning, $CPUCritical, ''),
                    @('Thread Count', $Instance.Threads, '', 0, $ThreadCountWarning, $ThreadCountCritical, '')
                )
            );
        }

        $Total     = $Entry.Total;
        $Packages += ,@(
            (New-IcingaPlugin ([string]::Format('{0} Summary', $Name))),
            @(
                @('Page File Usage', $Total.PageFile, 'B', $Data.CommitLimit, $TotalPageFileWarning, $TotalPageFileCritical, 'pagefile'),
                @('Memory Usage', $Total.Memory, 'B', $Data.MemoryTotal, $TotalMemoryWarning, $TotalMemoryCritical, 'memory'),
                @('CPU Usage', $Total.Cpu, '%', 100, $TotalCPUWarning, $TotalCPUCritical, 'cpu'),
                @('Thread Count', $Total.Threads, '', 0, $TotalThreadCountWarning, $TotalThreadCountCritical, 'threads'),
                @('Process Count', $Total.Count, '', 0, $TotalProcessCountWarning, $TotalProcessCountCritical, 'count')
            )
        );

        foreach ($Package in $Packages) {
            foreach ($Metric in $Package[1]) {
                $Check = (New-IcingaPlugin $Metric[0] $Metric[1] $Metric[2]).
                    SetNoPerfData([string]::IsNullOrEmpty($Metric[6])).
                    MetricIndex($Name).
                    MetricLabel($Metric[6]).
                    Warning($Metric[4]).
                    Critical($Metric[5]);

                # Counts have no size to calculate percentages from.
                if ([double]$Metric[3] -gt 0) {
                    $Check.BaseValue($Metric[3]).Minimum('0').Maximum([string]$Metric[3]).Commit();
                }

                # Perfdata label: <name>::ifw_process::<metric> (template auto-derived from the command).
                $Package[0].AddCheck($Check.CheckRange()).Commit();
            }

            $ProcessPackage.AddCheck($Package[0]).Commit();
        }

        $CheckPackage.AddCheck($ProcessPackage).Commit();
    }

    # Wildcard entries are reported as well: a pattern without any match means the
    # expected process is not running.
    $CheckPackage.AddMissingChecks($Process, @($Data.Processes.Keys), '{0}', 'Process not found', $OverrideNotFound).Commit();

    if ($CheckPackage.HasChecks() -eq $false) {
        return $CheckPackage.SetError('No process matches the given filter').Compile();
    }

    return $CheckPackage.Compile();
}

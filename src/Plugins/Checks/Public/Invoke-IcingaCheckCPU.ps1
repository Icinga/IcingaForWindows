<#
.SYNOPSIS
Check the processor load per core, per NUMA node and in total against thresholds

.DESCRIPTION
Reads the '\Processor Information(*)\% Processor Time' performance counter and
builds a single IcingaPlugin container named 'CPU Load'. Windows reports one
instance per logical processor as '<node>,<index>', where the first number is the
NUMA node and the second the index within that node. Every NUMA node becomes a
'NUMA Node #<node>' container holding a check per core plus its 'Node Total', and
the average of all cores becomes the 'Overall Load' check. The cores are numbered
across all nodes ('Core #0' to 'Core #<n-1>'), so the second node of a host with
eight cores per node starts at 'Core #8'. Every check is evaluated immediately
against the warning and critical thresholds, so the plugin reports
CRITICAL/WARNING as soon as any core, node or the total breaches its threshold
(the default 'all must be OK' aggregation).

NodeFilter (aliased to SocketFilter for legacy compatibility) narrows evaluation
to matching NUMA node IDs while preserving hardware core numbering. Core selects
'*' (all cores, node totals and Overall Load), '_Total' / 'Total' (only Overall
Load), or a specific core number/wildcard pattern. OverallOnly collects all NUMA
node and core checks and performance data, while applying Warning and Critical
thresholds exclusively to 'Overall Load'.

'Node Total' and 'Overall Load' are the averages of the core values read in the
same request. Windows' own '<node>,_Total' and '_Total' instances are not used,
because they are sampled in a slightly different window and would not match the
cores shown next to them.

The counter is declared through New-IcingaPerformanceCounter, so the
performance-counter daemon keeps it warm. Without a running daemon the first
read in a new process pays the counter warm-up. A failed read is reported as
UNKNOWN with the counter error, for the whole plugin or for the single core; the
averages then use the cores that could be read.

Compile() renders the nested plugin output, collects the performance data and
returns the Icinga exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN). On the
main thread the output is written to the console; inside a background daemon it
is stored in the thread-local runtime state for the REST API instead.

This plugin is Windows-only because it relies on the Windows performance counters.

.PARAMETER Warning
| Name    | Type          | Description                                                       | Default |
|---------|---------------|-------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold in percent, using the Icinga threshold grammar. |         |

.PARAMETER Critical
| Name     | Type          | Description                                                        | Default |
|----------|---------------|--------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold in percent, using the Icinga threshold grammar. |         |

.PARAMETER Core
| Name | Type          | Description                                                                   | Default |
|------|---------------|-------------------------------------------------------------------------------|---------|
| Core | System.String | Core selector: '*' for all cores + totals, '_Total'/'Total' or a core number. | *       |

.PARAMETER NodeFilter
| Name       | Type         | Description                                                            | Default |
|------------|--------------|------------------------------------------------------------------------|---------|
| NodeFilter | System.Array | NUMA node IDs to include (wildcards allowed; aliased to SocketFilter). | @()     |

.PARAMETER OverallOnly
| Name        | Type                                         | Description                                                                  | Default |
|-------------|----------------------------------------------|------------------------------------------------------------------------------|---------|
| OverallOnly | System.Management.Automation.SwitchParameter | Collect all cores/nodes, but evaluate Warning/Critical only on Overall Load. | False   |

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
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90

Warns at 80% and goes critical at 90% load for any core, NUMA node or the total.

.EXAMPLE
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90 -OverallOnly

Collects performance data for all cores and NUMA nodes, alerting only when
Overall Load breaches 80% or 90%.

.EXAMPLE
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90 -Core '_Total'

Evaluates and emits performance data exclusively for Overall Load.

.NOTES
Windows-only. Reads the '\Processor Information(*)\% Processor Time' performance
counter; the user needs read access to the performance counters ('Performance
Monitor Users'). Perfdata labels are '<node>_<core>::ifw_cpu::load' with the core
numbered across all nodes, '<node>_total::ifw_cpu::load' and
'totalload::ifw_cpu::load'. The integer exit code is the return value; an Icinga
command wrapper is expected to exit with it.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaCheckCPU()
{
    param (
        [string]$Warning     = '',
        [string]$Critical    = '',
        [string]$Core        = '*',
        [Alias('SocketFilter')]
        [array]$NodeFilter   = @(),
        [switch]$OverallOnly = $false,
        [int]$Verbosity      = 0,
        [switch]$NoPerfData  = $false
    );

    [string]$CounterPath     = '\Processor Information(*)\% Processor Time';

    # Literal declaration, so the counter discovery at module start finds and warms it.
    New-IcingaPerformanceCounter -Counter @('\Processor Information(*)\% Processor Time');

    $CheckPackage            = New-IcingaPlugin 'CPU Load';
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    $Counters                = Get-IcingaPerformanceCounter -Counter $CounterPath -StructureByInstance;

    [array]$Nodes            = @();
    [hashtable]$NodeCores    = @{ };

    if ($null -ne $Counters) {
        # Natural order puts the nodes and the cores of every node in numeric order.
        foreach ($Instance in (ConvertTo-IcingaSortedArray -InputObject @($Counters.Keys))) {
            [string[]]$Parts = ([string]$Instance).Split(',');

            # Skips '_Total' and '<node>,_Total'; the totals are averaged from the cores.
            if ($Parts.Count -ne 2 -or $Parts[1] -eq '_Total') {
                continue;
            }

            if ($NodeCores.ContainsKey($Parts[0]) -eq $false) {
                $NodeCores[$Parts[0]] = @();
                $Nodes += $Parts[0];
            }

            $NodeCores[$Parts[0]] += $Instance;
        }
    }

    if ($Nodes.Count -eq 0) {
        return $CheckPackage.SetError('Failed to read the performance counter {0}: no processor instance available', $CounterPath).Compile();
    }

    # Normalize -Core so '*' selects all cores + Overall Load, '_Total' / 'Total' selects only Overall Load,
    # and '0' or 'Core #0' selects matching logical core numbers.
    [string]$NormalizedCore = '*';
    if (-not [string]::IsNullOrWhiteSpace($Core)) {
        $NormalizedCore = $Core.Trim().Replace('_', '');
    }

    [bool]$IsAllCores        = ($NormalizedCore -eq '*');
    [bool]$IsTotalOnly       = ($NormalizedCore -ieq 'Total');
    [string]$SpecificPattern = ($NormalizedCore -replace '(?i)^core\s*#?', '').Trim();

    # The node and overall averages need every core value, so all checks are collected
    # first and created afterwards in output order.
    [array]$Entries          = @();
    [int]$CoreNumber         = 0;
    [double]$OverallSum      = 0;
    [int]$OverallCount       = 0;
    [int]$MatchedNodes       = 0;
    [int]$MatchedCores       = 0;

    foreach ($Node in $Nodes) {
        # Advance CoreNumber across skipped NUMA nodes so logical hardware core IDs stay globally aligned
        if ((Test-IcingaArrayFilter -InputObject $Node -Include $NodeFilter) -eq $false) {
            $CoreNumber += $NodeCores[$Node].Count;
            continue;
        }

        $MatchedNodes++;
        $NodePackage        = $null;
        [double]$NodeSum    = 0;
        [int]$NodeCount     = 0;
        [array]$NodeEntries = @();

        # Skip creating per-node containers when only Overall Load ('_Total' / 'Total') was requested
        if (-not $IsTotalOnly) {
            $NodePackage = New-IcingaPlugin ([string]::Format('NUMA Node #{0}', $Node));
        }

        foreach ($Instance in $NodeCores[$Node]) {
            [int]$CurrentCoreIndex = $CoreNumber;
            $CoreNumber            = $CoreNumber + 1;

            [bool]$CoreSelected    = ($IsAllCores -or $IsTotalOnly);
            if (-not $CoreSelected) {
                $CoreSelected = [bool](Test-IcingaArrayFilter -InputObject ([string]$CurrentCoreIndex) -Include @( $SpecificPattern ));
            }

            if (-not $CoreSelected) {
                continue;
            }

            $MatchedCores++;
            $Value = Get-IcingaPerformanceCounterValue -InputObject $Counters[$Instance]['Processor Information']['% Processor Time'];
            $Entry = @{
                'Parent'    = $NodePackage;
                'Name'      = [string]::Format('Core #{0}', $CurrentCoreIndex);
                'Index'     = [string]::Format('{0}_{1}', $Node, $CurrentCoreIndex);
                'Value'     = $null;
                'Error'     = $null;
                'IsOverall' = $false;
            };

            if ($null -eq $Value -or $Value -is [string]) {
                $Entry['Error'] = [string]$Value;
            } else {
                $Entry['Value'] = [double]$Value;
                $NodeSum       += [double]$Value;
                $NodeCount     += 1;
            }

            if (-not $IsTotalOnly) {
                $NodeEntries += $Entry;
            }
        }

        if ($IsAllCores) {
            $NodeTotal = @{
                'Parent'    = $NodePackage;
                'Name'      = 'Node Total';
                'Index'     = [string]::Format('{0}_total', $Node);
                'Value'     = $null;
                'Error'     = 'no core of this NUMA node could be read';
                'IsOverall' = $false;
            };

            if ($NodeCount -ne 0) {
                $NodeTotal['Value'] = $NodeSum / $NodeCount;
                $NodeTotal['Error'] = $null;
            }

            $NodeEntries += $NodeTotal;
        }

        if ($null -ne $NodePackage -and $NodeEntries.Count -gt 0) {
            $CheckPackage.AddCheck($NodePackage).Commit();
            $Entries += $NodeEntries;
        }

        $OverallSum   += $NodeSum;
        $OverallCount += $NodeCount;
    }

    if ($MatchedNodes -eq 0) {
        return $CheckPackage.SetError('No NUMA node matches the given filter').Compile();
    }

    if (-not $IsAllCores -and -not $IsTotalOnly -and $MatchedCores -eq 0) {
        return $CheckPackage.SetError('No processor core matches the given filter "{0}"', $Core).Compile();
    }

    if ($IsAllCores -or $IsTotalOnly) {
        $OverallLoad = @{
            'Parent'    = $CheckPackage;
            'Name'      = 'Overall Load';
            'Index'     = 'totalload';
            'Value'     = $null;
            'Error'     = 'no processor core could be read';
            'IsOverall' = $true;
        };

        if ($OverallCount -ne 0) {
            $OverallLoad['Value'] = $OverallSum / $OverallCount;
            $OverallLoad['Error'] = $null;
        }

        $Entries += $OverallLoad;
    }

    foreach ($Entry in $Entries) {
        if ($null -eq $Entry['Value']) {
            $Entry['Parent'].AddCheck(
                (New-IcingaPlugin $Entry['Name']).SetError('Failed to read the performance counter: {0}', $Entry['Error'])
            ).Commit();
            continue;
        }

        [string]$EntryWarn = $Warning;
        [string]$EntryCrit = $Critical;

        # When -OverallOnly is set alongside -Core '*', keep individual core and node metrics for
        # performance data, but apply Warning/Critical thresholds exclusively to 'Overall Load'.
        if ($OverallOnly -and $IsAllCores -and -not [bool]$Entry['IsOverall']) {
            $EntryWarn = '';
            $EntryCrit = '';
        }

        $Entry['Parent'].AddCheck(
            (New-IcingaPlugin $Entry['Name'] ([System.Math]::Round([double]$Entry['Value'], 2)) '%').
                MetricIndex($Entry['Index']).
                MetricLabel('load').
                Warning($EntryWarn).
                Critical($EntryCrit).
                Minimum('0').
                Maximum('100').
                CheckRange()
        ).Commit();
    }

    return $CheckPackage.Compile();
}

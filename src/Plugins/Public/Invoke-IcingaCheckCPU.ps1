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
| Name    | Type          | Description                                                        | Default |
|---------|---------------|--------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold in percent, using the Icinga threshold grammar.  |         |

.PARAMETER Critical
| Name     | Type          | Description                                                         | Default |
|----------|---------------|---------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold in percent, using the Icinga threshold grammar.  |         |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                 | Default |
|-----------|--------------|-----------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config. | 0 |

.PARAMETER NoPerfData
| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

.OUTPUTS
System.Int32 — The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

.EXAMPLE
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90

Warns at 80% and goes critical at 90% load for any core, NUMA node or the total.

.EXAMPLE
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90 -Verbosity 2

Shows every NUMA node and core in the output, not only the ones that breach a
threshold.

.NOTES
Windows-only. Reads the '\Processor Information(*)\% Processor Time' performance
counter; the user needs read access to the performance counters ('Performance
Monitor Users'). Perfdata labels are '<node>_<core>::ifw_cpu::load' with the core
numbered across all nodes, '<node>_total::ifw_cpu::load' and
'totalload::ifw_cpu::load'. The integer exit code is the return value; an Icinga
command wrapper is expected to exit with it.
#>
function Invoke-IcingaCheckCPU()
{
    param (
        [string]$Warning     = '',
        [string]$Critical    = '',
        [int]$Verbosity      = 0,
        [switch]$NoPerfData  = $false
    );

    [string]$CounterPath = '\Processor Information(*)\% Processor Time';

    # Literal declaration, so the counter discovery at module start finds and warms it.
    New-IcingaPerformanceCounter -Counter @('\Processor Information(*)\% Processor Time');

    $CheckPackage         = New-IcingaPlugin 'CPU Load';
    $CheckPackage.Verbose = $Verbosity;

    $Counters = Get-IcingaPerformanceCounter -Counter $CounterPath -StructureByInstance;

    [array]$Nodes         = @();
    [hashtable]$NodeCores = @{ };

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
                $Nodes               += $Parts[0];
            }

            $NodeCores[$Parts[0]] += $Instance;
        }
    }

    if ($Nodes.Count -eq 0) {
        return $CheckPackage.SetError('Failed to read the performance counter {0}: no processor instance available', $CounterPath).Compile();
    }

    # The node and overall averages need every core value, so all checks are collected
    # first and created afterwards in output order.
    [array]$Entries     = @();
    [int]$CoreNumber    = 0;
    [double]$OverallSum = 0;
    [int]$OverallCount  = 0;

    foreach ($Node in $Nodes) {
        $NodePackage = New-IcingaPlugin ([string]::Format('NUMA Node #{0}', $Node));
        $CheckPackage.AddCheck($NodePackage).Commit();

        [double]$NodeSum = 0;
        [int]$NodeCount  = 0;

        foreach ($Instance in $NodeCores[$Node]) {
            $Value = Get-IcingaPerformanceCounterValue -InputObject $Counters[$Instance]['Processor Information']['% Processor Time'];
            $Entry = @{
                'Parent' = $NodePackage;
                'Name'   = [string]::Format('Core #{0}', $CoreNumber);
                'Index'  = [string]::Format('{0}_{1}', $Node, $CoreNumber);
                'Value'  = $null;
                'Error'  = $null;
            };

            $CoreNumber += 1;

            if ($null -eq $Value -or $Value -is [string]) {
                $Entry['Error'] = [string]$Value;
            } else {
                $Entry['Value'] = [double]$Value;
                $NodeSum       += [double]$Value;
                $NodeCount     += 1;
            }

            $Entries += $Entry;
        }

        $NodeTotal = @{
            'Parent' = $NodePackage;
            'Name'   = 'Node Total';
            'Index'  = [string]::Format('{0}_total', $Node);
            'Value'  = $null;
            'Error'  = 'no core of this NUMA node could be read';
        };

        if ($NodeCount -ne 0) {
            $NodeTotal['Value'] = $NodeSum / $NodeCount;
            $NodeTotal['Error'] = $null;
        }

        $Entries      += $NodeTotal;
        $OverallSum   += $NodeSum;
        $OverallCount += $NodeCount;
    }

    $OverallLoad = @{
        'Parent' = $CheckPackage;
        'Name'   = 'Overall Load';
        'Index'  = 'totalload';
        'Value'  = $null;
        'Error'  = 'no processor core could be read';
    };

    if ($OverallCount -ne 0) {
        $OverallLoad['Value'] = $OverallSum / $OverallCount;
        $OverallLoad['Error'] = $null;
    }

    $Entries += $OverallLoad;

    foreach ($Entry in $Entries) {
        if ($null -eq $Entry['Value']) {
            $Entry['Parent'].AddCheck(
                (New-IcingaPlugin $Entry['Name']).SetError('Failed to read the performance counter: {0}', $Entry['Error'])
            ).Commit();
            continue;
        }

        $Check            = New-IcingaPlugin $Entry['Name'] ([System.Math]::Round([double]$Entry['Value'], 2)) '%';
        $Check.NoPerfData = $NoPerfData;

        $Entry['Parent'].AddCheck(
            $Check.
                MetricIndex($Entry['Index']).
                MetricLabel('load').
                Warning($Warning).
                Critical($Critical).
                Minimum('0').
                Maximum('100').
                CheckRange()
        ).Commit();
    }

    return $CheckPackage.Compile();
}

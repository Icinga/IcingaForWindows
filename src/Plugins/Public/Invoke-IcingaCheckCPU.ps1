<#
.SYNOPSIS
Check the processor load per core and in total against thresholds

.DESCRIPTION
Queries the current processor load from the Win32_PerfFormattedData_PerfOS_Processor
performance class (one instance per logical core plus the '_Total' average) and
builds a single IcingaPlugin container named 'CPU Load'. Every core and the total
become a child check that is evaluated immediately against the supplied warning and
critical thresholds, so the container reports CRITICAL/WARNING as soon as any core
or the total breaches its threshold (the default 'all must be OK' aggregation).

Compile() renders the nested plugin output, collects the per-core performance data
and returns the Icinga exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN). On the
main thread the output is written to the console; inside a background daemon it is
stored in the thread-local runtime state for the REST API instead.

This plugin is Windows-only because it relies on the Windows performance counters.

.PARAMETER Warning
| Name    | Type          | Description                                                        | Default |
|---------|---------------|--------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold in percent, using the Icinga threshold grammar.  |         |

.PARAMETER Critical
| Name     | Type          | Description                                                        | Default |
|----------|---------------|-------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold in percent, using the Icinga threshold grammar. |        |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                 | Default |
|-----------|--------------|-----------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config. | 0 |

.PARAMETER NoPerfData
| Name       | Type          | Description                                  | Default |
|------------|---------------|----------------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False |

.OUTPUTS
System.Int32 — The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

.EXAMPLE
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90

Warns at 80% and goes critical at 90% load for any core or the total.

.EXAMPLE
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90 -Verbosity 2

Shows every core in the output, not only the ones that breach a threshold.

.NOTES
Windows-only. Reads the Win32_PerfFormattedData_PerfOS_Processor CIM class. The
integer exit code is the return value; an Icinga command wrapper is expected to
exit with it.
#>
function Invoke-IcingaCheckCPU()
{
    param (
        [string]$Warning     = '',
        [string]$Critical    = '',
        [int]$Verbosity      = 0,
        [switch]$NoPerfData  = $false
    );

    $CheckPackage         = [IcingaPlugin]::new('CPU Load');
    $CheckPackage.Verbose = $Verbosity;

    try {
        $Processors = Get-CimInstance -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -ErrorAction Stop;
    } catch {
        $CheckPackage.SetUnknown([string]::Format('Failed to query processor performance data: {0}', $_.Exception.Message), $true).Commit();
        return $CheckPackage.Compile();
    }

    # Order the cores numerically and append the '_Total' average last.
    $Sorted = $Processors | Sort-Object -Property {
        if ($_.Name -eq '_Total') {
            return [int]::MaxValue;
        }

        return [int]$_.Name;
    };

    foreach ($Processor in $Sorted) {
        if ($Processor.Name -eq '_Total') {
            [string]$CoreName = 'CPU Total';
        } else {
            [string]$CoreName = [string]::Format('Core #{0}', $Processor.Name);
        }

        $Core            = [IcingaPlugin]::new($CoreName, [double]$Processor.PercentProcessorTime, '%');
        $Core.NoPerfData = $NoPerfData;

        # Perfdata label: <core>::ifw_cpu::load (template auto-derived from the command).
        $CheckPackage.AddCheck(
            $Core.MetricIndex($Processor.Name).MetricLabel('load').Warning($Warning).Critical($Critical).Minimum('0').Maximum('100').CheckRange()
        ).Commit();
    }

    return $CheckPackage.Compile();
}

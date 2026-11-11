<#
.SYNOPSIS
Check any Windows performance counter against thresholds

.DESCRIPTION
Reads every given performance counter in one request and builds a single
IcingaPlugin container named 'Performance Counter'. Every requested counter
becomes a package named after its path, holding one check per instance: a
wildcard path such as '\Processor(*)\% Processor Time' is expanded to every live
instance, a concrete path such as '\Memory\Available Bytes' yields one check. All
checks are evaluated immediately against the same warning and critical
thresholds, using the full Icinga range grammar.

Every value gets its unit from the counter type and name, so it is rendered and
compared through the unit conversion. Percent counters (name starting with '%'
or a percent counter type) use '%'. Timer counters such as 'Avg. Disk sec/Read',
'System Up Time' or 'Elapsed Time' are durations in seconds and render as '4ms'
or '1d 2h 3m 4s'; their thresholds accept durations ('30m', '1d:'). Counters with
'Bytes' in the name are sizes in bytes, 'KBytes' and 'MBytes' counters are scaled
to bytes as well; they render as '8.93GiB' and their thresholds accept sizes
('500MB'). Rates such as 'Pages/sec' and plain counts keep a plain number.

IncludeCounter and ExcludeCounter filter the instance paths (wildcards allowed,
for example '*_Total*'). An instance that cannot be read is skipped; when no
instance of a counter can be read, or a concrete counter fails, the counter is
reported as UNKNOWN with the first counter error. With IgnoreEmptyChecks the
plugin reports OK instead of UNKNOWN when the filters leave no counter at all.

Counters that are requested repeatedly are kept warm by the performance-counter
daemon. Without a running daemon the first read of a counter in a new process
pays the counter warm-up.

Performance data uses the label '<category>::ifw_perfcounter::<counter><instance>'
with '%' spelled out as 'percent', for example
'processor::ifw_perfcounter::percentprocessortime2' for core 2 or
'memory::ifw_perfcounter::availablebytes' for a counter without an instance.

.PARAMETER PerfCounter
| Name        | Type         | Description                                                   | Default |
|-------------|--------------|---------------------------------------------------------------|---------|
| PerfCounter | System.Array | Counter paths to check, e.g. '\Processor(*)\% Processor Time'.| @()     |

.PARAMETER Warning
| Name    | Type          | Description                                                           | Default |
|---------|---------------|-----------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold in the counter's unit, e.g. '80', '500MB' or '30m'. |         |

.PARAMETER Critical
| Name     | Type          | Description                                                         | Default |
|----------|---------------|---------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold in the counter's unit, e.g. '90', '1GB' or '1h'. |         |

.PARAMETER IncludeCounter
| Name           | Type         | Description                                        | Default |
|----------------|--------------|----------------------------------------------------|---------|
| IncludeCounter | System.Array | Only check instance paths matching these patterns. | @()     |

.PARAMETER ExcludeCounter
| Name           | Type         | Description                                  | Default |
|----------------|--------------|----------------------------------------------|---------|
| ExcludeCounter | System.Array | Skip instance paths matching these patterns. | @()     |

.PARAMETER IgnoreEmptyChecks
| Name              | Type                                         | Description                                                    | Default |
|-------------------|----------------------------------------------|----------------------------------------------------------------|---------|
| IgnoreEmptyChecks | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no counter remains to check. | False   |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

.PARAMETER NoPerfData
| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

.OUTPUTS
System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

.EXAMPLE
PS> Invoke-IcingaCheckPerfCounter -PerfCounter '\Processor(*)\% Processor Time' -Warning 80 -Critical 90 -ExcludeCounter '*_Total*'

Checks the load of every processor instance except the total.

.EXAMPLE
PS> Invoke-IcingaCheckPerfCounter -PerfCounter '\Memory\Pages/sec', '\System\Processor Queue Length' -Critical 10 -Verbosity 2

Checks two concrete counters against the same critical threshold.

.NOTES
Windows-only. Reads the Windows performance counters; the user needs read access
to them ('Performance Monitor Users'). The integer exit code is the return value;
an Icinga command wrapper is expected to exit with it.
#>
function Invoke-IcingaCheckPerfCounter()
{
    param (
        [array]$PerfCounter        = @(),
        [string]$Warning           = '',
        [string]$Critical          = '',
        [array]$IncludeCounter     = @(),
        [array]$ExcludeCounter     = @(),
        [switch]$IgnoreEmptyChecks = $false,
        [int]$Verbosity            = 0,
        [switch]$NoPerfData        = $false
    );

    $CheckPackage            = New-IcingaPlugin 'Performance Counter';
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    [array]$Requested        = @();

    foreach ($CounterPath in $PerfCounter) {
        if ([string]::IsNullOrEmpty([string]$CounterPath) -eq $false) {
            $Requested += [string]$CounterPath;
        }
    }

    if ($Requested.Count -eq 0) {
        return $CheckPackage.SetError('No performance counter was provided').Compile();
    }

    # Counter types whose value is a percentage or a duration in seconds. Some
    # percent counters report an unnamed type, so the '%' name prefix counts as well.
    [array]$PercentTypes = @(
        'Timer100Ns', 'Timer100NsInverse', 'CounterTimer', 'CounterTimerInverse',
        'CounterMultiTimer', 'CounterMultiTimerInverse', 'CounterMultiTimer100Ns',
        'CounterMultiTimer100NsInverse', 'RawFraction', 'SampleFraction'
    );
    [array]$TimeTypes    = @( 'AverageTimer32', 'ElapsedTime' );

    $Counters            = Get-IcingaPerformanceCounter -Counter $Requested;

    if ($null -eq $Counters) {
        return $CheckPackage.SetError('Failed to read the performance counters {0}', ($Requested -join ', ')).Compile();
    }

    $CounterType = 'IcingaPerformanceCounter' -as [type];

    foreach ($CounterPath in $Requested) {
        $CounterPackage = New-IcingaPlugin $CounterPath;
        $Parsed         = $CounterType::ParsePath($CounterPath);

        if ($Parsed.Valid -eq $false) {
            $CheckPackage.AddCheck(
                $CounterPackage.SetError('Invalid performance counter path, expected \Category\Counter or \Category(Instance)\Counter')
            ).Commit();
            continue;
        }

        # A wildcard result is keyed by every expanded instance path, a concrete
        # request is the counter result itself.
        [hashtable]$Instances = @{ };

        if ($Parsed.Instance -eq '*') {
            if ($Counters[$CounterPath] -is [hashtable]) {
                $Instances = $Counters[$CounterPath];
            }
        } else {
            $Instances[$CounterPath] = $Counters[$CounterPath];
        }

        [bool]$Filtered     = $false;
        [string]$FirstError = '';

        foreach ($InstancePath in (ConvertTo-IcingaSortedArray -InputObject @($Instances.Keys))) {
            if ((Test-IcingaArrayFilter -InputObject $InstancePath -Include $IncludeCounter -Exclude $ExcludeCounter) -eq $false) {
                $Filtered = $true;
                continue;
            }

            $Value = Get-IcingaPerformanceCounterValue -InputObject $Instances[$InstancePath];

            if ($null -eq $Value -or $Value -is [string]) {
                if ([string]::IsNullOrEmpty($FirstError)) {
                    $FirstError = [string]$Value;
                }
                continue;
            }

            # The label names the counter and the instance ('percentprocessortime2'), so
            # several counters of one category never share a label. '%' is spelled out
            # because the label sanitizing would drop it.
            $Instance      = $CounterType::ParsePath($InstancePath);
            [string]$Label = $Instance.Counter.Replace('%', 'percent') + $Instance.Instance;
            [string]$Type  = [string]$Instances[$InstancePath]['type'];
            [string]$Unit  = '';
            [double]$Scale = 1;

            if ($Instance.Counter.StartsWith('%') -or $PercentTypes -contains $Type) {
                $Unit = '%';
            } elseif ($TimeTypes -contains $Type -or $Instance.Counter -match '(?i)\bsec/') {
                $Unit = 's';
            } elseif ($Instance.Counter -match '(?i)(KBytes|Kilobytes)') {
                $Unit  = 'B';
                $Scale = 1KB;
            } elseif ($Instance.Counter -match '(?i)(MBytes|Megabytes)') {
                $Unit  = 'B';
                $Scale = 1MB;
            } elseif ($Instance.Counter -match '(?i)Bytes') {
                $Unit = 'B';
            }

            [double]$Measured = [double]$Value * $Scale;

            # Bytes are indivisible (a byte rate is rounded to whole bytes as well), an
            # elapsed time such as the uptime needs no sub-second part and percentages
            # keep two decimals like the other plugins. Timer averages keep their precision.
            if ($Unit -eq 'B' -or $Type -eq 'ElapsedTime') {
                $Measured = [System.Math]::Round($Measured, 0);
            } elseif ($Unit -eq '%') {
                $Measured = [System.Math]::Round($Measured, 2);
            }

            # Perfdata label: <category>::ifw_perfcounter::<counter><instance> (template auto-derived from the command).
            $CounterPackage.AddCheck(
                (New-IcingaPlugin $InstancePath $Measured $Unit).
                    MetricIndex($Instance.Category).
                    MetricLabel($Label).
                    Warning($Warning).
                    Critical($Critical).
                    CheckRange()
            ).Commit();
        }

        if ($CounterPackage.HasChecks() -eq $false) {
            # Instances that were filtered out on purpose are no failure.
            if ($Filtered -and [string]::IsNullOrEmpty($FirstError)) {
                continue;
            }

            if ([string]::IsNullOrEmpty($FirstError)) {
                $FirstError = 'no instance of this counter exists';
            }

            $CounterPackage.SetError('Failed to read the performance counter: {0}', $FirstError).Commit();
        }

        $CheckPackage.AddCheck($CounterPackage).Commit();
    }

    if ($CheckPackage.HasChecks() -eq $false) {
        if ($IgnoreEmptyChecks) {
            return $CheckPackage.SetOk('No performance counter matches the given filter', $true).Compile();
        }

        return $CheckPackage.SetError('No performance counter matches the given filter').Compile();
    }

    return $CheckPackage.Compile();
}

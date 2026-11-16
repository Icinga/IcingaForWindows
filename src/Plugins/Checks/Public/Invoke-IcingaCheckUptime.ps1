<#
.SYNOPSIS
Check the time since the last system start against thresholds

.DESCRIPTION
Reads the '\System\System Up Time' performance counter and builds a single
IcingaPlugin container named 'System Uptime: <uptime>' with the check 'System
Uptime' (whole seconds since the last start, shown as a duration such as
'1d 2h 3m 4s') and the informational 'Last Boot' entry with the start time. The
check is evaluated immediately against the warning and critical thresholds, which
accept durations with an Icinga time unit and the full Icinga range grammar:
'1d:' raises an alert while the system runs shorter than one day (a recent
reboot), '30d' while it runs longer than 30 days.

The counter is declared through New-IcingaPerformanceCounter, so the
performance-counter daemon keeps it warm. A failed read is reported as UNKNOWN
with the counter error.

Performance data uses the label 'windows::ifw_uptime::uptime' in seconds.

.PARAMETER Warning
| Name    | Type          | Description                                              | Default |
|---------|---------------|----------------------------------------------------------|---------|
| Warning | System.String | Warning threshold as duration or range, e.g. '1d:'.      |         |

.PARAMETER Critical
| Name     | Type          | Description                                              | Default |
|----------|---------------|----------------------------------------------------------|---------|
| Critical | System.String | Critical threshold as duration or range, e.g. '30m:'.    |         |

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
PS> Invoke-IcingaCheckUptime -Warning '1d:' -Critical '30m:'

Warns during the first day after a reboot and goes critical during the first 30 minutes.

.EXAMPLE
PS> Invoke-IcingaCheckUptime -Warning '60d' -Verbosity 2

Warns when the system has not been restarted for more than 60 days.

.NOTES
Windows-only. Reads the '\System\System Up Time' performance counter; the user
needs read access to the performance counters ('Performance Monitor Users'). The
integer exit code is the return value; an Icinga command wrapper is expected to
exit with it.
#>
function Invoke-IcingaCheckUptime()
{
    param (
        [string]$Warning    = '',
        [string]$Critical   = '',
        [int]$Verbosity     = 0,
        [switch]$NoPerfData = $false
    );

    [string]$CounterPath     = '\System\System Up Time';

    # Literal declaration, so the counter discovery at module start finds and warms it.
    New-IcingaPerformanceCounter -Counter @('\System\System Up Time');

    $CheckPackage            = New-IcingaPlugin 'System Uptime';
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    $Counters                = Get-IcingaPerformanceCounter -Counter $CounterPath -StructureByInstance;
    $Value                   = $null;

    if ($null -ne $Counters -and $null -ne $Counters['System']) {
        $Value = Get-IcingaPerformanceCounterValue -InputObject $Counters['System']['System Up Time'];
    }

    if ($null -eq $Value -or $Value -is [string]) {
        return $CheckPackage.SetError('Failed to read the performance counter {0}: {1}', $CounterPath, $Value).Compile();
    }

    [uint64]$Uptime    = [System.Math]::Round([double]$Value, 0);
    $CheckPackage.Name = [string]::Format('System Uptime: {0}', ('IcingaUnit' -as [type])::new([string]$Uptime, 's', '', $false).OutputString);

    $CheckPackage.AddCheck(
        (New-IcingaPlugin 'System Uptime' $Uptime 's').
            MetricIndex('windows').
            MetricLabel('uptime').
            Warning($Warning).
            Critical($Critical).
            CheckRange()
    ).AddCheck(
        (New-IcingaPlugin 'Last Boot').
            SetNoPerfData($true).
            SetNotice([datetime]::Now.AddSeconds(-1 * [double]$Uptime).ToString('yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture))
    ).Commit();

    return $CheckPackage.Compile();
}

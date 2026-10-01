<#
.SYNOPSIS
Check the state of Windows services against an expected status

.DESCRIPTION
Queries every service from the Win32_Service CIM class once and builds a single
IcingaPlugin container named 'Services'. Each selected service becomes a child
check comparing its current state with the expected status; a mismatch raises the
state chosen with OverrideNotOk (CRITICAL by default).

When no service is given, every service with the 'Automatic' start mode is
checked: it is expected to be running, except when it is stopped with exit code
0, which means it ended on purpose and is reported OK. When services are given
by name or display name (wildcards allowed), they are compared against Status,
optionally narrowed down by their startup type. Every given name without a
wildcard that matches no service on the system is reported with the state chosen
with OverrideNotFound (UNKNOWN by default).

Performance data contains the numeric state of each explicitly selected service
('<service>::ifw_service::state', 1 Stopped to 7 Paused) and per-state counters
of all checked services ('summary::ifw_service::<state>' and '::count').

This plugin is Windows-only because it relies on the Win32_Service CIM class.

.PARAMETER Service
| Name    | Type           | Description                                                              | Default |
|---------|----------------|--------------------------------------------------------------------------|---------|
| Service | System.Array   | Service names or display names to check, wildcards allowed. Empty checks all automatic services. | @() |

.PARAMETER Exclude
| Name    | Type         | Description                                                   | Default |
|---------|--------------|---------------------------------------------------------------|---------|
| Exclude | System.Array | Service names or display names to skip, wildcards allowed.    | @()     |

.PARAMETER Status
| Name   | Type          | Description                                                                                       | Default |
|--------|---------------|---------------------------------------------------------------------------------------------------|---------|
| Status | System.String | Expected status of the given services: Stopped, StartPending, StopPending, Running, ContinuePending, PausePending or Paused. | Running |

.PARAMETER FilterStartupType
| Name              | Type         | Description                                                                                         | Default |
|-------------------|--------------|-----------------------------------------------------------------------------------------------------|---------|
| FilterStartupType | System.Array | Only check given services with one of these startup types: Boot, System, Automatic, Manual, Disabled, Unknown. | @() |

.PARAMETER MitigateUnknown
| Name            | Type                                         | Description                                                  | Default |
|-----------------|----------------------------------------------|--------------------------------------------------------------|---------|
| MitigateUnknown | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no service matches at all. | False   |

.PARAMETER OverrideNotOk
| Name          | Type          | Description                                                                   | Default  |
|---------------|---------------|-------------------------------------------------------------------------------|----------|
| OverrideNotOk | System.String | State for a service not in the expected status: Ok, Warning, Critical, Unknown. | Critical |

.PARAMETER OverrideNotFound
| Name             | Type          | Description                                                        | Default |
|------------------|---------------|--------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State for a given service that does not exist: Ok, Warning, Critical, Unknown. | Unknown |

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
PS> Invoke-IcingaCheckService

Checks that every automatic service is running or ended with exit code 0.

.EXAMPLE
PS> Invoke-IcingaCheckService -Service 'Spooler', 'W32Time' -OverrideNotOk 'Warning'

Warns when the print spooler or the time service is not running.

.EXAMPLE
PS> Invoke-IcingaCheckService -Service 'Windows Update*' -Exclude 'wuauserv' -Status 'Stopped' -Verbosity 2

Expects every service whose display name starts with 'Windows Update', except
wuauserv, to be stopped and lists all of them in the output.

.NOTES
Windows-only. Reads the Win32_Service CIM class. The integer exit code is the
return value; an Icinga command wrapper is expected to exit with it.
#>
function Invoke-IcingaCheckService()
{
    param (
        [array]$Service           = @(),
        [array]$Exclude           = @(),
        [ValidateSet('Stopped', 'StartPending', 'StopPending', 'Running', 'ContinuePending', 'PausePending', 'Paused')]
        [string]$Status           = 'Running',
        [ValidateSet('Boot', 'System', 'Automatic', 'Manual', 'Disabled', 'Unknown')]
        [array]$FilterStartupType = @(),
        [switch]$MitigateUnknown  = $false,
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotOk    = 'Critical',
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotFound = 'Unknown',
        [int]$Verbosity           = 0,
        [switch]$NoPerfData       = $false
    );

    # Codes match the System.ServiceProcess.ServiceControllerStatus values used by
    # the previous plugin generation, so existing state graphs stay comparable.
    [hashtable]$ServiceStates = @{
        'Stopped'         = @{ 'Code' = 1; 'Summary' = 'stopped'; };
        'StartPending'    = @{ 'Code' = 2; 'Summary' = 'pendingstarted'; };
        'StopPending'     = @{ 'Code' = 3; 'Summary' = 'pendingstopped'; };
        'Running'         = @{ 'Code' = 4; 'Summary' = 'running'; };
        'ContinuePending' = @{ 'Code' = 5; 'Summary' = 'pendingcontinued'; };
        'PausePending'    = @{ 'Code' = 6; 'Summary' = 'pendingpaused'; };
        'Paused'          = @{ 'Code' = 7; 'Summary' = 'paused'; };
    };

    [hashtable]$StartupTypes = @{
        'Boot'     = 'Boot';
        'System'   = 'System';
        'Auto'     = 'Automatic';
        'Manual'   = 'Manual';
        'Disabled' = 'Disabled';
    };

    $CheckPackage         = [IcingaPlugin]::new('Services');
    $CheckPackage.Verbose = $Verbosity;

    try {
        [array]$AllServices = Get-CimInstance -ClassName 'Win32_Service' -Property 'Name', 'DisplayName', 'State', 'StartMode', 'ExitCode' -ErrorAction Stop;
    } catch {
        $CheckPackage.SetUnknown([string]::Format('Failed to query the Windows services: {0}', $_.Exception.Message), $true).Commit();
        return $CheckPackage.Compile();
    }

    $SummaryCount = [ordered]@{
        'stopped'          = 0;
        'pendingstarted'   = 0;
        'pendingstopped'   = 0;
        'running'          = 0;
        'pendingcontinued' = 0;
        'pendingpaused'    = 0;
        'paused'           = 0;
    };

    $MetricPackage          = [IcingaPlugin]::new('Service Metrics');
    $MetricPackage.IsHidden = $true;
    [bool]$AutoMode         = ($Service.Count -eq 0);
    [int]$ServiceCount      = 0;
    [int]$CheckCount        = 0;

    foreach ($ServiceEntry in ($AllServices | Sort-Object -Property 'Name')) {
        [string]$ServiceName = $ServiceEntry.Name;
        [string]$DisplayName = $ServiceEntry.DisplayName;
        [string]$StateName   = ([string]$ServiceEntry.State).Replace(' ', '');
        [string]$StartupType = 'Unknown';

        if ($StartupTypes.ContainsKey([string]$ServiceEntry.StartMode)) {
            $StartupType = $StartupTypes[[string]$ServiceEntry.StartMode];
        }

        if (@($Exclude | Where-Object { $ServiceName -like $_ -or $DisplayName -like $_ }).Count -ne 0) {
            continue;
        }

        if ($AutoMode) {
            if ($StartupType -ne 'Automatic') {
                continue;
            }

            [string]$Expected = 'Running';

            # A stopped automatic service with exit code 0 ended on purpose (for
            # example a trigger-start service) and is not a failure.
            if ($StateName -ne 'Running' -and $ServiceEntry.ExitCode -eq 0) {
                $Expected = $StateName;
            }
        } else {
            if (@($Service | Where-Object { $ServiceName -like $_ -or $DisplayName -like $_ }).Count -eq 0) {
                continue;
            }

            if ($FilterStartupType.Count -ne 0 -and $FilterStartupType -notcontains $StartupType) {
                continue;
            }

            [string]$Expected = $Status;
        }

        $ServiceCheck = [IcingaPlugin]::new([string]::Format('Service "{0} ({1})"', $DisplayName, $ServiceName), $StateName);

        if ($OverrideNotOk -eq 'Warning') {
            $ServiceCheck.Warning($Expected).CheckNotEqual().Commit();
        } else {
            $ServiceCheck.Critical($Expected).CheckNotEqual().Commit();
        }

        # An empty message keeps the comparison text; the lock stops the critical
        # comparison result from escalating the overridden state again.
        if ($StateName -ne $Expected) {
            if ($OverrideNotOk -eq 'Ok') {
                $ServiceCheck.SetOk('', $true).Commit();
            } elseif ($OverrideNotOk -eq 'Unknown') {
                $ServiceCheck.SetUnknown('', $true).Commit();
            }
        }

        $CheckPackage.AddCheck($ServiceCheck).Commit();
        $CheckCount++;
        $ServiceCount++;

        if (-not $ServiceStates.ContainsKey($StateName)) {
            continue;
        }

        $SummaryCount[$ServiceStates[$StateName].Summary] += 1;

        if ($AutoMode -or $NoPerfData) {
            continue;
        }

        $MetricPackage.AddCheck(
            [IcingaPlugin]::new($ServiceName, $ServiceStates[$StateName].Code).MetricIndex($ServiceName).MetricLabel('state').CheckRange()
        ).Commit();
    }

    foreach ($Filter in $Service) {
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters([string]$Filter)) {
            continue;
        }

        if (@($AllServices | Where-Object { $_.Name -eq $Filter -or $_.DisplayName -eq $Filter }).Count -ne 0) {
            continue;
        }

        $NotFound = [IcingaPlugin]::new([string]$Filter, 'Service not found');

        switch ($OverrideNotFound) {
            'Ok' {
                $NotFound.SetOk('Service not found', $true).Commit();
                break;
            }
            'Warning' {
                $NotFound.SetWarning('Service not found', $true).Commit();
                break;
            }
            'Critical' {
                $NotFound.SetCritical('Service not found', $true).Commit();
                break;
            }
            default {
                $NotFound.SetUnknown('Service not found', $true).Commit();
                break;
            }
        }

        $CheckPackage.AddCheck($NotFound).Commit();
        $CheckCount++;
    }

    # The container line only shows its own message while it has no children, so
    # the hidden metric package is attached only when there are real checks.
    if ($CheckCount -eq 0) {
        if ($MitigateUnknown) {
            $CheckPackage.SetOk('No service matches the given filter', $true).Commit();
        } else {
            $CheckPackage.SetUnknown('No service matches the given filter', $true).Commit();
        }

        return $CheckPackage.Compile();
    }

    if (-not $NoPerfData) {
        foreach ($SummaryLabel in $SummaryCount.Keys) {
            $MetricPackage.AddCheck(
                [IcingaPlugin]::new($SummaryLabel, $SummaryCount[$SummaryLabel]).MetricIndex('summary').MetricLabel($SummaryLabel).CheckRange()
            ).Commit();
        }

        $MetricPackage.AddCheck(
            [IcingaPlugin]::new('count', $ServiceCount).MetricIndex('summary').MetricLabel('count').CheckRange()
        ).Commit();

        $CheckPackage.AddCheck($MetricPackage).Commit();
    }

    return $CheckPackage.Compile();
}

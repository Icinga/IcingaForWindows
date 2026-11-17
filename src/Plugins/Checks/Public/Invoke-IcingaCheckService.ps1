<#
.SYNOPSIS
Check the state of Windows services against one or more expected statuses

.DESCRIPTION
Queries every service from the Win32_Service CIM class once and builds a single
IcingaPlugin container named 'Services'. Each selected service becomes a child
check comparing its current state with the expected Status list; a mismatch
raises the state chosen with OverrideNotOk (CRITICAL by default).

When no service is given, every service with the 'Automatic' start mode is
checked: it is expected to be running, except when it is stopped with exit code
0, which means it ended on purpose and is reported OK. When services are given
by name or display name (wildcards allowed), they are compared against Status
(supporting both single statuses and multi-status lists), optionally narrowed
down by their startup type. Every given name without a wildcard that matches no
service on the system is reported with the state chosen with OverrideNotFound
(UNKNOWN by default).

Service states and startup types are resolved through the IcingaServiceStatus
and IcingaServiceStartupType data types. Performance data contains the numeric
state of each explicitly selected service ('<service>::ifw_service::state', 0
Unknown, 1 Stopped to 7 Paused) and per-state counters of all checked services
('summary::ifw_service::<state>' and '::count').

This plugin is Windows-only because it relies on the Win32_Service CIM class.

.PARAMETER Service
| Name    | Type         | Description                                                                                      | Default |
|---------|--------------|--------------------------------------------------------------------------------------------------|---------|
| Service | System.Array | Service names or display names to check, wildcards allowed. Empty checks all automatic services. | @()     |

.PARAMETER Exclude
| Name    | Type         | Description                                                | Default |
|---------|--------------|------------------------------------------------------------|---------|
| Exclude | System.Array | Service names or display names to skip, wildcards allowed. | @()     |

.PARAMETER Status
| Name   | Type                  | Description                                                                                                                             | Default    |
|--------|-----------------------|-----------------------------------------------------------------------------------------------------------------------------------------|------------|
| Status | IcingaServiceStatus[] | Expected status(es) of the given services: Stopped, StartPending, StopPending, Running, ContinuePending, PausePending, Paused, Unknown. | @(Running) |

.PARAMETER FilterStartupType
| Name              | Type                       | Description                                                                                                    | Default |
|-------------------|----------------------------|----------------------------------------------------------------------------------------------------------------|---------|
| FilterStartupType | IcingaServiceStartupType[] | Only check given services with one of these startup types: Boot, System, Automatic, Manual, Disabled, Unknown. | @()     |

.PARAMETER MitigateUnknown
| Name            | Type                                         | Description                                                  | Default |
|-----------------|----------------------------------------------|--------------------------------------------------------------|---------|
| MitigateUnknown | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no service matches at all. | False   |

.PARAMETER OverrideNotOk
| Name          | Type          | Description                                                                     | Default  |
|---------------|---------------|---------------------------------------------------------------------------------|----------|
| OverrideNotOk | System.String | State for a service not in the expected status: Ok, Warning, Critical, Unknown. | Critical |

.PARAMETER OverrideNotFound
| Name             | Type          | Description                                                                    | Default |
|------------------|---------------|--------------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State for a given service that does not exist: Ok, Warning, Critical, Unknown. | Unknown |

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
Windows-only. Reads the Win32_Service CIM class through
Get-IcingaWindowsInformation; a failed query is reported as UNKNOWN with its
reason. The integer exit code is the return value; an Icinga command wrapper is
expected to exit with it.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaCheckService()
{
    param (
        [array]$Service                                = @(),
        [array]$Exclude                                = @(),
        [IcingaServiceStatus[]]$Status                 = @( [IcingaServiceStatus]::Running ),
        [IcingaServiceStartupType[]]$FilterStartupType = @(),
        [Alias('IgnoreEmptyChecks')]
        [switch]$MitigateUnknown                       = $false,
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotOk                         = 'Critical',
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotFound                      = 'Unknown',
        [int]$Verbosity                                = 0,
        [switch]$NoPerfData                            = $false
    );

    # Fall back to @(Running) when an unpopulated Icinga array variable passes @() for -Status
    [IcingaServiceStatus[]]$EffectiveStatus = $Status;
    if ($null -eq $EffectiveStatus -or $EffectiveStatus.Count -eq 0) {
        $EffectiveStatus = @( [IcingaServiceStatus]::Running );
    }

    [hashtable]$SummaryLabels = @{
        ([IcingaServiceStatus]::Stopped)         = 'stopped';
        ([IcingaServiceStatus]::StartPending)    = 'pendingstarted';
        ([IcingaServiceStatus]::StopPending)     = 'pendingstopped';
        ([IcingaServiceStatus]::Running)         = 'running';
        ([IcingaServiceStatus]::ContinuePending) = 'pendingcontinued';
        ([IcingaServiceStatus]::PausePending)    = 'pendingpaused';
        ([IcingaServiceStatus]::Paused)          = 'paused';
    };

    $CheckPackage             = New-IcingaPlugin 'Services';
    $CheckPackage.Verbose     = $Verbosity;
    $CheckPackage.NoPerfData  = $NoPerfData;

    $AllServices              = Get-IcingaWindowsInformation -ClassName 'Win32_Service' -Property 'Name', 'DisplayName', 'State', 'StartMode', 'ExitCode';

    if (Test-IcingaError -InputObject $AllServices) {
        return $CheckPackage.SetError($AllServices).Compile();
    }

    [hashtable]$KnownServices = @{ };

    foreach ($ServiceEntry in $AllServices) {
        $KnownServices[[string]$ServiceEntry.Name]        = $true;
        $KnownServices[[string]$ServiceEntry.DisplayName] = $true;
    }

    $SummaryCount      = [ordered]@{
        'stopped'          = 0;
        'pendingstarted'   = 0;
        'pendingstopped'   = 0;
        'running'          = 0;
        'pendingcontinued' = 0;
        'pendingpaused'    = 0;
        'paused'           = 0;
    };

    $MetricPackage     = (New-IcingaPlugin 'Service Metrics').SetHidden();
    [bool]$AutoMode    = ($Service.Count -eq 0);
    [int]$ServiceCount = 0;
    $StatusMap         = 'IcingaServiceStatusMap' -as [type];
    $StartupTypeMap    = 'IcingaServiceStartupTypeMap' -as [type];

    foreach ($ServiceEntry in (ConvertTo-IcingaSortedArray -InputObject $AllServices -Property 'Name')) {
        [string]$ServiceName                     = $ServiceEntry.Name;
        [string]$DisplayName                     = $ServiceEntry.DisplayName;
        [IcingaServiceStatus]$State              = $StatusMap::Resolve($ServiceEntry.State);
        [IcingaServiceStartupType]$StartupType   = $StartupTypeMap::Resolve($ServiceEntry.StartMode);
        [IcingaServiceStatus[]]$ExpectedStatuses = $EffectiveStatus;

        if ((Test-IcingaArrayFilter -InputObject $ServiceName -Exclude $Exclude) -eq $false -or (Test-IcingaArrayFilter -InputObject $DisplayName -Exclude $Exclude) -eq $false) {
            continue;
        }

        if ($AutoMode) {
            if ($StartupType -ne [IcingaServiceStartupType]::Automatic) {
                continue;
            }

            $ExpectedStatuses = @( [IcingaServiceStatus]::Running );

            # A stopped automatic service with exit code 0 ended on purpose (for
            # example a trigger-start service) and is not a failure.
            if ($State -ne [IcingaServiceStatus]::Running -and $ServiceEntry.ExitCode -eq 0) {
                $ExpectedStatuses = @( $State );
            }
        } else {
            if ((Test-IcingaArrayFilter -InputObject $ServiceName -Include $Service) -eq $false -and (Test-IcingaArrayFilter -InputObject $DisplayName -Include $Service) -eq $false) {
                continue;
            }

            if ($FilterStartupType.Count -ne 0 -and $FilterStartupType -notcontains $StartupType) {
                continue;
            }
        }

        $ServiceCheck          = (New-IcingaPlugin ([string]::Format('Service "{0} ({1})"', $DisplayName, $ServiceName)) $State).
            MetricIndex($ServiceName).
            MetricLabel('state').
            SetNoPerfData($AutoMode);

        # Compare against a single expected status via CheckNotEqual or against multiple allowed statuses via CheckNotIn
        [bool]$IsStateMismatch = $false;

        if ($ExpectedStatuses.Count -le 1) {
            [IcingaServiceStatus]$SingleExpected = $ExpectedStatuses[0];
            $ServiceCheck.Critical([string]$SingleExpected).CheckNotEqual().Commit();
            $IsStateMismatch                     = ($State -ne $SingleExpected);
        } else {
            [array]$ExpectedNames = @();
            foreach ($ExpectedStatus in $ExpectedStatuses) {
                $ExpectedNames += [string]$ExpectedStatus;
            }
            $ServiceCheck.Critical($ExpectedNames).CheckNotIn().Commit();
            $IsStateMismatch = ($ExpectedStatuses -notcontains $State);
        }

        # An empty message keeps the comparison text; the lock stops the critical
        # comparison result from escalating the overridden state again.
        if ($IsStateMismatch -and $OverrideNotOk -ne 'Critical') {
            $ServiceCheck.SetState($OverrideNotOk, '', $true).Commit();
        }

        $CheckPackage.AddCheck($ServiceCheck).Commit();
        $ServiceCount++;

        if ($SummaryLabels.ContainsKey($State)) {
            $SummaryCount[$SummaryLabels[$State]] += 1;
        }
    }

    # Wildcard arguments select services instead of naming one, so only plain
    # names can be missing.
    [array]$RequiredServices = @();

    foreach ($Filter in $Service) {
        if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters([string]$Filter) -eq $false) {
            $RequiredServices += [string]$Filter;
        }
    }

    $CheckPackage.AddMissingChecks($RequiredServices, @($KnownServices.Keys), '{0}', 'Service not found', $OverrideNotFound).Commit();

    if ($CheckPackage.HasChecks() -eq $false) {
        if ($MitigateUnknown) {
            return $CheckPackage.SetOk('No service matches the given filter', $true).Compile();
        }

        return $CheckPackage.SetError('No service matches the given filter').Compile();
    }

    foreach ($SummaryLabel in $SummaryCount.Keys) {
        $MetricPackage.AddCheck(
            (New-IcingaPlugin $SummaryLabel $SummaryCount[$SummaryLabel]).MetricIndex('summary').MetricLabel($SummaryLabel)
        ).Commit();
    }

    $MetricPackage.AddCheck(
        (New-IcingaPlugin 'count' $ServiceCount).MetricIndex('summary').MetricLabel('count')
    ).Commit();

    $CheckPackage.AddCheck($MetricPackage).Commit();

    return $CheckPackage.Compile();
}

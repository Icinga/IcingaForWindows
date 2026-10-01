$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckService' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        function New-TestService()
        {
            param (
                [string]$Name        = '',
                [string]$DisplayName = '',
                [string]$State       = 'Running',
                [string]$StartMode   = 'Auto',
                [int]$ExitCode       = 0
            );

            return [PSCustomObject]@{
                'Name'        = $Name;
                'DisplayName' = $DisplayName;
                'State'       = $State;
                'StartMode'   = $StartMode;
                'ExitCode'    = $ExitCode;
            };
        }

        # Runs the plugin inside the module scope with Get-CimInstance shadowed by a
        # function, so the check works on the given service objects instead of CIM.
        function Invoke-TestServiceCheck()
        {
            param (
                [array]$StubData      = @(),
                [hashtable]$Arguments = @{ },
                [switch]$Fail         = $false
            );

            return (& $script:IcingaModule {
                param ($StubData, $Arguments, $Fail);

                function Get-CimInstance()
                {
                    [CmdletBinding()]
                    param (
                        [string]$ClassName  = '',
                        [string]$Filter     = '',
                        [string[]]$Property = @()
                    );

                    if ($Fail) {
                        throw 'Access is denied';
                    }

                    return $StubData;
                }

                Invoke-IcingaCheckService @Arguments;
            } $StubData $Arguments $Fail);
        }

        $script:Spooler = New-TestService -Name 'Spooler' -DisplayName 'Print Spooler';
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    Context 'Explicit services' {
        It 'reports a running service as OK with state and summary perfdata' {
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Spooler'; 'Verbosity' = 2; } | Should -Be 0;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output          | Should -Match ([regex]::Escape('[OK] Service "Print Spooler (Spooler)": ''Running'' is ok'));
            $Result.PerformanceData | Should -Contain 'spooler::ifw_service::state=4;;;;';
            $Result.PerformanceData | Should -Contain 'summary::ifw_service::running=1;;;;';
            $Result.PerformanceData | Should -Contain 'summary::ifw_service::count=1;;;;';
        }

        It 'reports a stopped service as CRITICAL by default' {
            $Stopped = New-TestService -Name 'Spooler' -DisplayName 'Print Spooler' -State 'Stopped';

            Invoke-TestServiceCheck -StubData @($Stopped) -Arguments @{ 'Service' = 'Spooler'; } | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[CRITICAL] Service "Print Spooler (Spooler)": ''Stopped'' does not equal pattern ''Running'''));
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'spooler::ifw_service::state=1;;;;';
        }

        It 'applies OverrideNotOk to a service in the wrong state' {
            $Stopped = New-TestService -Name 'Spooler' -DisplayName 'Print Spooler' -State 'Stopped';

            Invoke-TestServiceCheck -StubData @($Stopped) -Arguments @{ 'Service' = 'Spooler'; 'OverrideNotOk' = 'Warning'; } | Should -Be 1;
            Invoke-TestServiceCheck -StubData @($Stopped) -Arguments @{ 'Service' = 'Spooler'; 'OverrideNotOk' = 'Unknown'; } | Should -Be 3;
            Invoke-TestServiceCheck -StubData @($Stopped) -Arguments @{ 'Service' = 'Spooler'; 'OverrideNotOk' = 'Ok'; }      | Should -Be 0;
        }

        It 'compares against the expected Status' {
            $Stopped = New-TestService -Name 'Spooler' -DisplayName 'Print Spooler' -State 'Stopped';

            Invoke-TestServiceCheck -StubData @($Stopped) -Arguments @{ 'Service' = 'Spooler'; 'Status' = 'Stopped'; } | Should -Be 0;
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Spooler'; 'Status' = 'Stopped'; } | Should -Be 2;
        }

        It 'maps pending states to their status code and summary counter' {
            $Pending = New-TestService -Name 'Spooler' -DisplayName 'Print Spooler' -State 'Start Pending';

            Invoke-TestServiceCheck -StubData @($Pending) -Arguments @{ 'Service' = 'Spooler'; } | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'spooler::ifw_service::state=2;;;;';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'summary::ifw_service::pendingstarted=1;;;;';
        }

        It 'reports a service in the Unknown state with state code 0' {
            $Unknown = New-TestService -Name 'Spooler' -DisplayName 'Print Spooler' -State 'Unknown';

            Invoke-TestServiceCheck -StubData @($Unknown) -Arguments @{ 'Service' = 'Spooler'; } | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'spooler::ifw_service::state=0;;;;';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'summary::ifw_service::count=1;;;;';
        }

        It 'rejects a Status that is no IcingaServiceStatus' {
            { Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Spooler'; 'Status' = 'Sleeping'; } } | Should -Throw;
        }

        It 'selects services by wildcard and honours Exclude' {
            $Services = @(
                (New-TestService -Name 'WinRM' -DisplayName 'Windows Remote Management'),
                (New-TestService -Name 'WinDefend' -DisplayName 'Microsoft Defender Antivirus Service'),
                $script:Spooler
            );

            Invoke-TestServiceCheck -StubData $Services -Arguments @{ 'Service' = 'Win*'; 'Exclude' = 'WinDefend'; } | Should -Be 0;

            [array]$StateMetrics = @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Where-Object { $_ -like '*::state=*' });
            $StateMetrics | Should -Be @('winrm::ifw_service::state=4;;;;');
        }

        It 'matches services by display name' {
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Print Spooler'; 'Verbosity' = 2; } | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Not -Match 'Service not found';
        }

        It 'only checks services with a matching startup type' {
            $Services = @(
                (New-TestService -Name 'Manual1' -DisplayName 'Manual One' -State 'Stopped' -StartMode 'Manual'),
                (New-TestService -Name 'Auto1' -DisplayName 'Auto One' -State 'Running' -StartMode 'Auto')
            );

            Invoke-TestServiceCheck -StubData $Services -Arguments @{ 'Service' = '*'; 'Status' = 'Stopped'; 'FilterStartupType' = 'Manual'; } | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'summary::ifw_service::count=1;;;;';
        }
    }

    Context 'Missing services' {
        It 'reports a service that does not exist as UNKNOWN' {
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Spooler', 'DoesNotExist'; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[UNKNOWN] DoesNotExist: Service not found'));
        }

        It 'applies OverrideNotFound to a service that does not exist' {
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'DoesNotExist'; 'OverrideNotFound' = 'Critical'; } | Should -Be 2;
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'DoesNotExist'; 'OverrideNotFound' = 'Ok'; }       | Should -Be 0;
        }

        It 'returns UNKNOWN when a wildcard matches nothing, OK with MitigateUnknown' {
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Nope*'; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Services: No service matches the given filter';

            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Nope*'; 'MitigateUnknown' = $true; } | Should -Be 0;
        }
    }

    Context 'Automatic services' {
        It 'checks only automatic services and accepts a clean exit' {
            $Services = @(
                (New-TestService -Name 'AutoRunning' -DisplayName 'Auto Running'),
                (New-TestService -Name 'AutoDone' -DisplayName 'Auto Done' -State 'Stopped' -ExitCode 0),
                (New-TestService -Name 'AutoFailed' -DisplayName 'Auto Failed' -State 'Stopped' -ExitCode 1067),
                (New-TestService -Name 'ManualStopped' -DisplayName 'Manual Stopped' -State 'Stopped' -StartMode 'Manual' -ExitCode 1)
            );

            Invoke-TestServiceCheck -StubData $Services | Should -Be 2;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output          | Should -Match '^\[CRITICAL\] Services: 1 Critical 2 Ok';
            $Result.Output          | Should -Match ([regex]::Escape('Service "Auto Failed (AutoFailed)"'));
            $Result.Output          | Should -Not -Match 'ManualStopped';
            $Result.PerformanceData | Should -Contain 'summary::ifw_service::count=3;;;;';
            $Result.PerformanceData | Should -Contain 'summary::ifw_service::stopped=2;;;;';
            @($Result.PerformanceData | Where-Object { $_ -like '*::state=*' }).Count | Should -Be 0;
        }
    }

    Context 'Errors and perfdata switches' {
        It 'suppresses all performance data with NoPerfData' {
            Invoke-TestServiceCheck -StubData @($script:Spooler) -Arguments @{ 'Service' = 'Spooler'; 'NoPerfData' = $true; } | Should -Be 0;
            @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
        }

        It 'returns UNKNOWN when the service query fails' {
            Invoke-TestServiceCheck -Fail -Arguments @{ 'Service' = 'Spooler'; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match 'Failed to query the Windows services: Access is denied';
        }
    }
}

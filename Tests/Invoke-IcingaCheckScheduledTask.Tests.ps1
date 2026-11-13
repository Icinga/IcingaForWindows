$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckScheduledTask' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        function Invoke-TestScheduledTaskCheck()
        {
            param (
                [array]$Tasks         = @(),
                [hashtable]$Infos     = @{ },
                [hashtable]$Arguments = @{ },
                [switch]$Fail         = $false
            );

            return (& $script:IcingaModule {
                param ($Tasks, $Infos, $Arguments, $Fail);

                function Get-ScheduledTask()
                {
                    param (
                        [string]$TaskName    = '*',
                        [string]$ErrorAction = 'Continue'
                    );

                    if ($Fail) {
                        throw 'Access is denied';
                    }

                    return $Tasks;
                }

                function Get-ScheduledTaskInfo()
                {
                    param (
                        [string]$TaskName    = '',
                        [string]$TaskPath    = '',
                        [string]$ErrorAction = 'Continue'
                    );

                    [string]$Key = '{0}{1}' -f $TaskPath, $TaskName;
                    if ($Infos.ContainsKey($Key)) {
                        return $Infos[$Key];
                    }

                    return $null;
                }

                return (Invoke-IcingaCheckScheduledTask @Arguments);
            } $Tasks $Infos $Arguments $Fail);
        }

        $script:DefaultTask = [PSCustomObject]@{
            'TaskName' = 'Renew Certificate';
            'TaskPath' = '\Icinga\Icinga for Windows\';
            'State'    = 'Ready';
        };
        $script:DefaultInfo = @{
            '\Icinga\Icinga for Windows\Renew Certificate' = [PSCustomObject]@{
                'LastRunTime'        = [datetime]::Now.AddHours(-1);
                'NextRunTime'        = [datetime]::Now.AddHours(2);
                'NumberOfMissedRuns' = 0;
                'LastTaskResult'     = 0;
            };
        };
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    Context 'State checks and multi-value State arrays' {
        It 'returns OK when task state matches a single or multi-value State list and emits perfdata' {
            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $script:DefaultInfo -Arguments @{ 'State' = @('Ready', 'Running'); 'Verbosity' = 2; } | Should -Be 0;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output          | Should -Match ([regex]::Escape("[OK] State: 'Ready' is ok"));
            $Result.PerformanceData | Should -Contain 'icinga_icingaforwindows_renewcertificate::ifw_scheduledtask::state=3;;;;';
            $Result.PerformanceData | Should -Contain 'icinga_icingaforwindows_renewcertificate::ifw_scheduledtask::missedruns=0;;;;';
            $Result.PerformanceData | Should -Contain 'icinga_icingaforwindows_renewcertificate::ifw_scheduledtask::lasttaskresult=0;;;;';
        }

        It 'returns CRITICAL when task state does not match the required State list' {
            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $script:DefaultInfo -Arguments @{ 'State' = @('Disabled'); 'Verbosity' = 2; } | Should -Be 2;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output | Should -Match ([regex]::Escape("[CRITICAL] State: 'Ready' does not equal pattern 'Disabled'"));
        }
    }

    Context 'Exit codes, Missed Runs and Run Time thresholds' {
        It 'raises CRITICAL on a non-zero LastTaskResult unless ignored via IgnoreLastRunTime or IgnoreExitCodes' {
            $FailedInfo = @{
                '\Icinga\Icinga for Windows\Renew Certificate' = [PSCustomObject]@{
                    'LastRunTime'        = [datetime]::Now.AddHours(-1);
                    'NextRunTime'        = $null;
                    'NumberOfMissedRuns' = 0;
                    'LastTaskResult'     = 267009;
                };
            };

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $FailedInfo | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match 'Task exited with code 267009';

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $FailedInfo -Arguments @{ 'IgnoreLastRunTime' = $true; } | Should -Be 0;

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $FailedInfo -Arguments @{ 'IgnoreExitCodes' = @('0x41301'); } | Should -Be 0;
        }

        It 'evaluates WarningMissedRuns and WarningLastRunTime thresholds' {
            $Info = @{
                '\Icinga\Icinga for Windows\Renew Certificate' = [PSCustomObject]@{
                    'LastRunTime'        = [datetime]::Now.AddHours(-5);
                    'NextRunTime'        = $null;
                    'NumberOfMissedRuns' = 3;
                    'LastTaskResult'     = 0;
                };
            };

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $Info -Arguments @{ 'WarningMissedRuns' = '2'; } | Should -Be 1;

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $Info -Arguments @{ 'CriticalLastRunTime' = '2h'; } | Should -Be 2;
        }

        It 'renders unset run times as [Never]: Never with 0s perfdata' {
            $NeverInfo = @{
                '\Icinga\Icinga for Windows\Renew Certificate' = [PSCustomObject]@{
                    'LastRunTime'        = $null;
                    'NextRunTime'        = $null;
                    'NumberOfMissedRuns' = 0;
                    'LastTaskResult'     = 0;
                };
            };

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $NeverInfo -Arguments @{ 'Verbosity' = 3; } | Should -Be 0;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output          | Should -Match ([regex]::Escape('[INFO] Last Run Time [Never]: Never'));
            $Result.Output          | Should -Match ([regex]::Escape('[INFO] Next Run Time [Never]: Never'));
            $Result.PerformanceData | Should -Contain 'icinga_icingaforwindows_renewcertificate::ifw_scheduledtask::lastruntime=0s;;;;';
            $Result.PerformanceData | Should -Contain 'icinga_icingaforwindows_renewcertificate::ifw_scheduledtask::nextruntime=0s;;;;';
        }
    }

    Context 'Missing tasks and empty filter handling' {
        It 'reports a missing required task with OverrideNotFound (UNKNOWN by default)' {
            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $script:DefaultInfo -Arguments @{ 'TaskName' = @('Renew Certificate', 'MissingTask'); } | Should -Be 3;

            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[UNKNOWN] MissingTask: Task not found'));

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $script:DefaultInfo -Arguments @{ 'TaskName' = @('MissingTask'); 'OverrideNotFound' = 'Critical'; } | Should -Be 2;
        }

        It 'returns UNKNOWN when no task matches a wildcard filter, or OK with MitigateUnknown' {
            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $script:DefaultInfo -Arguments @{ 'TaskPath' = '\DoesNotExist\*'; } | Should -Be 3;

            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Scheduled Tasks: No scheduled task matches the given filter';

            Invoke-TestScheduledTaskCheck -Tasks @($script:DefaultTask) -Infos $script:DefaultInfo -Arguments @{ 'TaskPath' = '\DoesNotExist\*'; 'MitigateUnknown' = $true; } | Should -Be 0;
        }

        It 'returns UNKNOWN when querying scheduled tasks fails' {
            Invoke-TestScheduledTaskCheck -Fail | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match '^\[UNKNOWN\] Scheduled Tasks: Failed to query scheduled tasks: Access is denied';
        }
    }
}

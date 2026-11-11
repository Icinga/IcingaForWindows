$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

function Invoke-TestGetScheduledTask()
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

        return (Get-IcingaScheduledTask @Arguments);
    } $Tasks $Infos $Arguments $Fail);
}

Describe 'Get-IcingaScheduledTask' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    Context 'Task collection and filtering' {
        It 'groups tasks by TaskPath and resolves runtime info' {
            [datetime]$Past   = [datetime]::Now.AddHours(-2);
            [datetime]$Future = [datetime]::Now.AddHours(1);

            $Tasks            = @(
                [PSCustomObject]@{ 'TaskName' = 'Renew Certificate'; 'TaskPath' = '\Icinga\'; 'State' = 'Ready' },
                [PSCustomObject]@{ 'TaskName' = 'Backup'; 'TaskPath' = '\Microsoft\'; 'State' = 'Disabled' }
            );
            $Infos            = @{
                '\Icinga\Renew Certificate' = [PSCustomObject]@{
                    'LastRunTime'        = $Past;
                    'NextRunTime'        = $Future;
                    'NumberOfMissedRuns' = 1;
                    'LastTaskResult'     = 0;
                };
                '\Microsoft\Backup' = [PSCustomObject]@{
                    'LastRunTime'        = [datetime]::new(1999, 11, 30, 0, 0, 0);
                    'NextRunTime'        = $null;
                    'NumberOfMissedRuns' = 0;
                    'LastTaskResult'     = 267011;
                };
            };

            $Result           = Invoke-TestGetScheduledTask -Tasks $Tasks -Infos $Infos;
            $Result.Tasks.Count                        | Should -Be 2;
            $Result.Tasks['\Icinga\'][0].TaskName      | Should -Be 'Renew Certificate';
            [string]$Result.Tasks['\Icinga\'][0].State | Should -Be 'Ready';
            $Result.Tasks['\Icinga\'][0].MissedRuns    | Should -Be 1;
            $Result.Tasks['\Icinga\'][0].LastRunOffset | Should -BeGreaterThan 7000;
            $Result.Tasks['\Icinga\'][0].NextRunOffset | Should -BeGreaterThan 3000;

            # 1999-11-30 with 267011 (SCHED_S_TASK_HAS_NOT_RUN) is treated as never run.
            $Result.Tasks['\Microsoft\'][0].LastRunTime   | Should -Be '';
            $Result.Tasks['\Microsoft\'][0].LastRunOffset | Should -Be 0;
            $Result.Tasks['\Microsoft\'][0].NextRunTime   | Should -Be '';
            $Result.Tasks['\Microsoft\'][0].NextRunOffset | Should -Be 0;
        }

        It 'filters by TaskName, ExcludeTaskName, TaskPath and ExcludeTaskPath' {
            $Tasks  = @(
                [PSCustomObject]@{ 'TaskName' = 'TaskA'; 'TaskPath' = '\Icinga\'; 'State' = 'Ready' },
                [PSCustomObject]@{ 'TaskName' = 'TaskB'; 'TaskPath' = '\Icinga\'; 'State' = 'Ready' },
                [PSCustomObject]@{ 'TaskName' = 'TaskC'; 'TaskPath' = '\Other\'; 'State' = 'Ready' }
            );

            $Result = Invoke-TestGetScheduledTask -Tasks $Tasks -Arguments @{
                'TaskPath'        = '\Icinga\*';
                'ExcludeTaskName' = 'TaskB';
            };

            $Result.Tasks.Count                   | Should -Be 1;
            $Result.Tasks['\Icinga\'].Count       | Should -Be 1;
            $Result.Tasks['\Icinga\'][0].TaskName | Should -Be 'TaskA';
            $Result.TaskNames                     | Should -Be @('TaskA');
        }

        It 'returns an IcingaError when Get-ScheduledTask fails' {
            $Result = Invoke-TestGetScheduledTask -Fail;
            (Test-IcingaError -InputObject $Result) | Should -BeTrue;
        }
    }
}

$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckUptime' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Builds the -StructureByInstance result of '\System\System Up Time'. A string
        # value becomes the counter error.
        function New-TestUptimeCounter()
        {
            param (
                $Value = [decimal]0
            );

            $Leaf = @{ 'value' = [decimal]0; 'sample' = $null; 'help' = ''; 'type' = ''; 'error' = $null; };

            if ($Value -is [string]) {
                $Leaf['error'] = $Value;
            } else {
                $Leaf['value'] = [decimal]$Value;
            }

            return @{ 'System' = @{ 'System Up Time' = $Leaf; }; };
        }

        # Runs the plugin inside the module scope with the performance counter
        # functions shadowed, so the check works on the given counter value.
        function Invoke-TestUptimeCheck()
        {
            param (
                $StubData             = $null,
                [hashtable]$Arguments = @{ }
            );

            return (& $script:IcingaModule {
                param ($StubData, $Arguments);

                function New-IcingaPerformanceCounter()
                {
                    param (
                        [array]$Counter = @()
                    );
                }

                function Get-IcingaPerformanceCounter()
                {
                    param (
                        [array]$Counter              = @(),
                        [int]$TimeoutMs              = 5000,
                        [switch]$StructureByInstance = $false
                    );

                    return $StubData;
                }

                Invoke-IcingaCheckUptime @Arguments;
            } $StubData $Arguments);
        }
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'shows the uptime as duration and writes it in whole seconds' {
        Invoke-TestUptimeCheck -StubData (New-TestUptimeCounter -Value 93784.4) -Arguments @{ 'Warning' = '1d:'; 'Verbosity' = 2; } | Should -Be 0;

        $Result       = $Global:IcingaForWindows.Private.Icinga.CheckResult;
        [array]$Lines = $Result.Output -split "`n";
        $Lines[0] | Should -Be '[OK] System Uptime: 1d 2h 3m 4s: 1 Ok';
        $Lines[1] | Should -Be '\_ [OK] System Uptime: 1d 2h 3m 4s is ok';
        $Lines[2] | Should -Match '^\\_ \[INFO\] Last Boot: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$';
        $Result.PerformanceData | Should -Be @('windows::ifw_uptime::uptime=93784s;86400:;;;');
    }

    It 'raises the state after a recent restart' {
        Invoke-TestUptimeCheck -StubData (New-TestUptimeCounter -Value 3600) -Arguments @{ 'Warning' = '1d:'; 'Critical' = '30m:'; } | Should -Be 1;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[WARNING] System Uptime: 1h is lower than threshold 1d'));
    }

    It 'raises the state when the system runs longer than allowed' {
        Invoke-TestUptimeCheck -StubData (New-TestUptimeCounter -Value 5184000) -Arguments @{ 'Critical' = '30d'; } | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[CRITICAL] System Uptime: 2M is greater than threshold 30d'));
    }

    It 'reports a failed counter read as UNKNOWN' {
        Invoke-TestUptimeCheck -StubData (New-TestUptimeCounter -Value 'Counter not initialized') | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] System Uptime: Failed to read the performance counter \System\System Up Time: Counter not initialized';

        Invoke-TestUptimeCheck -StubData $null | Should -Be 3;
    }

    It 'suppresses the performance data with NoPerfData' {
        Invoke-TestUptimeCheck -StubData (New-TestUptimeCounter -Value 3600) -Arguments @{ 'NoPerfData' = $true; } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
    }
}

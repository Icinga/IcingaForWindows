$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckCPU' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Runs the plugin inside the module scope with Get-CimInstance shadowed by a
        # function, so the check works on the given processor objects instead of CIM.
        function Invoke-TestCpuCheck()
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
                        [string]$ClassName = ''
                    );

                    if ($Fail) {
                        throw 'Performance counters are disabled';
                    }

                    return $StubData;
                }

                Invoke-IcingaCheckCPU @Arguments;
            } $StubData $Arguments $Fail);
        }

        $script:Processors = @(
            [PSCustomObject]@{ 'Name' = '_Total'; 'PercentProcessorTime' = 50; },
            [PSCustomObject]@{ 'Name' = '1'; 'PercentProcessorTime' = 95; },
            [PSCustomObject]@{ 'Name' = '0'; 'PercentProcessorTime' = 5; }
        );
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'orders the cores numerically with the total last in the perfdata' {
        Invoke-TestCpuCheck -StubData $script:Processors -Arguments @{ 'Warning' = '80'; 'Critical' = '90'; } | Out-Null;

        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
            '0::ifw_cpu::load=5%;80;90;0;100',
            '1::ifw_cpu::load=95%;80;90;0;100',
            '_total::ifw_cpu::load=50%;80;90;0;100'
        );
    }

    It 'raises CRITICAL when a single core breaches the critical threshold' {
        Invoke-TestCpuCheck -StubData $script:Processors -Arguments @{ 'Warning' = '80'; 'Critical' = '90'; } | Should -Be 2;

        $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
        $Result.Output | Should -Match '^\[CRITICAL\] CPU Load: 1 Critical 2 Ok';
        $Result.Output | Should -Match ([regex]::Escape('[CRITICAL] Core #1: 95% is greater than threshold 90%'));
    }

    It 'returns OK when every core is below the thresholds' {
        Invoke-TestCpuCheck -StubData $script:Processors -Arguments @{ 'Warning' = '96'; 'Critical' = '98'; } | Should -Be 0;
    }

    It 'suppresses the performance data with NoPerfData' {
        Invoke-TestCpuCheck -StubData $script:Processors -Arguments @{ 'NoPerfData' = $true; } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
    }

    It 'returns UNKNOWN when the processor query fails' {
        Invoke-TestCpuCheck -Fail | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match 'Failed to query processor performance data: Performance counters are disabled';
    }
}

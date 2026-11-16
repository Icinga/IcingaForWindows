$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckCPU' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Builds the -StructureByInstance result of Get-IcingaPerformanceCounter for
        # '\Processor Information(*)\% Processor Time'. A string value becomes the
        # counter error of that instance.
        function New-TestCpuCounter()
        {
            param (
                [hashtable]$Instances = @{ }
            );

            [hashtable]$Result = @{ };

            foreach ($Instance in $Instances.Keys) {
                $Leaf = @{ 'value' = [decimal]0; 'sample' = $null; 'help' = ''; 'type' = ''; 'error' = $null; };

                if ($Instances[$Instance] -is [string]) {
                    $Leaf['error'] = $Instances[$Instance];
                } else {
                    $Leaf['value'] = [decimal]$Instances[$Instance];
                }

                $Result[$Instance] = @{ 'Processor Information' = @{ '% Processor Time' = $Leaf; }; };
            }

            return $Result;
        }

        # Runs the plugin inside the module scope with the performance counter
        # functions shadowed, so the check works on the given counter values.
        function Invoke-TestCpuCheck()
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

                Invoke-IcingaCheckCPU @Arguments;
            } $StubData $Arguments);
        }

        # Windows' own totals carry wrong values on purpose: the plugin must average the
        # cores instead of reading these instances.
        $script:TwoNodes = New-TestCpuCounter -Instances @{
            '0,1'      = 95;
            '0,0'      = 5;
            '0,_Total' = 77;
            '1,0'      = 10;
            '1,_Total' = 99;
            '_Total'   = 1;
        };
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'writes the perfdata per core, per NUMA node and in total in natural order' {
        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Warning' = '80'; 'Critical' = '90'; } | Out-Null;

        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
            '0_0::ifw_cpu::load=5%;80;90;0;100',
            '0_1::ifw_cpu::load=95%;80;90;0;100',
            '0_total::ifw_cpu::load=50%;80;90;0;100',
            '1_2::ifw_cpu::load=10%;80;90;0;100',
            '1_total::ifw_cpu::load=10%;80;90;0;100',
            'totalload::ifw_cpu::load=36.67%;80;90;0;100'
        );
    }

    It 'groups the cores into one container per NUMA node and numbers them across all nodes' {
        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Verbosity' = 2; } | Should -Be 0;

        [array]$Lines = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output -split "`n";
        $Lines[0] | Should -Be '[OK] CPU Load: 6 Ok';
        $Lines[1] | Should -Be '\_ [OK] NUMA Node #0';
        $Lines[2] | Should -Match '^   \\_ \[OK\] Core #0: ';
        $Lines[4] | Should -Match '^   \\_ \[OK\] Node Total: ';
        $Lines[5] | Should -Be '\_ [OK] NUMA Node #1';
        $Lines[6] | Should -Be '   \_ [OK] Core #2: 10% is ok';
        $Lines[8] | Should -Match '^\\_ \[OK\] Overall Load: ';
    }

    It 'reports the same node total and overall load on a single NUMA node' {
        $Counters    = New-TestCpuCounter -Instances @{ '0,0' = 13.18; '0,1' = 9.67; '0,2' = 6.52; '0,3' = 1.13; '0,_Total' = 7.44; '_Total' = 7.57; };

        Invoke-TestCpuCheck -StubData $Counters | Should -Be 0;

        [array]$Perf = $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData;
        $Perf[4] | Should -Be '0_total::ifw_cpu::load=7.62%;;;0;100';
        $Perf[5] | Should -Be 'totalload::ifw_cpu::load=7.62%;;;0;100';
    }

    It 'raises CRITICAL when a single core breaches the critical threshold' {
        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Warning' = '80'; 'Critical' = '90'; } | Should -Be 2;

        $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
        $Result.Output | Should -Match '^\[CRITICAL\] CPU Load: 1 Critical 5 Ok';
        $Result.Output | Should -Match ([regex]::Escape('[CRITICAL] Core #1: 95% is greater than threshold 90%'));
    }

    It 'reports a core whose counter failed as UNKNOWN and averages the readable cores' {
        $Counters = New-TestCpuCounter -Instances @{ '0,0' = 5; '0,1' = 'Counter not initialized'; '0,_Total' = 50; '_Total' = 50; };

        Invoke-TestCpuCheck -StubData $Counters -Arguments @{ 'Warning' = '80'; } | Should -Be 3;

        $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
        $Result.Output          | Should -Match ([regex]::Escape('[UNKNOWN] Core #1: Failed to read the performance counter: Counter not initialized'));
        $Result.PerformanceData | Should -Contain '0_total::ifw_cpu::load=5%;80;;0;100';
        $Result.PerformanceData | Should -Contain 'totalload::ifw_cpu::load=5%;80;;0;100';
    }

    It 'reports the node total as UNKNOWN when no core of the node could be read' {
        $Counters = New-TestCpuCounter -Instances @{ '0,0' = 5; '1,0' = 'Counter not initialized'; };

        Invoke-TestCpuCheck -StubData $Counters -Arguments @{ 'Verbosity' = 2; } | Should -Be 3;

        $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
        $Result.Output          | Should -Match ([regex]::Escape('[UNKNOWN] Node Total: Failed to read the performance counter: no core of this NUMA node could be read'));
        $Result.PerformanceData | Should -Contain 'totalload::ifw_cpu::load=5%;;;0;100';
    }

    It 'returns UNKNOWN when no processor instance could be read' {
        Invoke-TestCpuCheck -StubData $null | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] CPU Load: Failed to read the performance counter \Processor Information(*)\% Processor Time: no processor instance available';

        Invoke-TestCpuCheck -StubData @{ } | Should -Be 3;
        Invoke-TestCpuCheck -StubData (New-TestCpuCounter -Instances @{ '_Total' = 5; '0,_Total' = 5; }) | Should -Be 3;
    }

    It 'suppresses the performance data with NoPerfData' {
        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'NoPerfData' = $true; } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
    }

    It 'evaluates thresholds exclusively on Overall Load when OverallOnly is enabled while keeping all core perfdata' {
        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Warning' = '80'; 'Critical' = '90'; 'OverallOnly' = $true; } | Should -Be 0;

        $OkResult = $Global:IcingaForWindows.Private.Icinga.CheckResult;
        $OkResult.PerformanceData | Should -Be @(
            '0_0::ifw_cpu::load=5%;;;0;100',
            '0_1::ifw_cpu::load=95%;;;0;100',
            '0_total::ifw_cpu::load=50%;;;0;100',
            '1_2::ifw_cpu::load=10%;;;0;100',
            '1_total::ifw_cpu::load=10%;;;0;100',
            'totalload::ifw_cpu::load=36.67%;80;90;0;100'
        );

        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Warning' = '20'; 'Critical' = '30'; 'OverallOnly' = $true; } | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[CRITICAL] Overall Load: 36.67% is greater than threshold 30%'));
    }

    It 'supports Core "_Total", "Total" and specific core numbers as well as NodeFilter / SocketFilter' {
        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Core' = '_Total'; 'Warning' = '80'; 'Critical' = '90'; } | Should -Be 0;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @( 'totalload::ifw_cpu::load=36.67%;80;90;0;100' );

        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Core' = '1'; 'Warning' = '80'; 'Critical' = '90'; } | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @( '0_1::ifw_cpu::load=95%;80;90;0;100' );

        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Core' = '1'; 'OverallOnly' = $true; 'Warning' = '80'; 'Critical' = '90'; } | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @( '0_1::ifw_cpu::load=95%;80;90;0;100' );

        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'SocketFilter' = @( '1' ); 'Warning' = '80'; 'Critical' = '90'; } | Should -Be 0;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
            '1_2::ifw_cpu::load=10%;80;90;0;100',
            '1_total::ifw_cpu::load=10%;80;90;0;100',
            'totalload::ifw_cpu::load=10%;80;90;0;100'
        );

        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'Core' = '99'; }           | Should -Be 3;
        Invoke-TestCpuCheck -StubData $script:TwoNodes -Arguments @{ 'NodeFilter' = @( '9' ); } | Should -Be 3;
    }
}

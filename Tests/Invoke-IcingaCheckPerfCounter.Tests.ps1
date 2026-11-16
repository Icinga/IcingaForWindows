$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckPerfCounter' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Builds one counter result in the shape of Get-IcingaPerformanceCounter. A
        # string value becomes the counter error.
        function New-TestLeaf()
        {
            param (
                $Value        = [decimal]0,
                [string]$Type = ''
            );

            $Leaf = @{ 'value' = [decimal]0; 'sample' = $null; 'help' = ''; 'type' = $Type; 'error' = $null; };

            if ($Value -is [string]) {
                $Leaf['error'] = $Value;
            } else {
                $Leaf['value'] = [decimal]$Value;
            }

            return $Leaf;
        }

        # Runs the plugin inside the module scope with Get-IcingaPerformanceCounter
        # shadowed, so the check works on the given counter results.
        function Invoke-TestPerfCounterCheck()
        {
            param (
                $StubData             = $null,
                [hashtable]$Arguments = @{ }
            );

            return (& $script:IcingaModule {
                param ($StubData, $Arguments);

                function Get-IcingaPerformanceCounter()
                {
                    param (
                        [array]$Counter              = @(),
                        [int]$TimeoutMs              = 5000,
                        [switch]$StructureByInstance = $false
                    );

                    return $StubData;
                }

                Invoke-IcingaCheckPerfCounter @Arguments;
            } $StubData $Arguments);
        }

        $script:Counters = @{
            '\Processor(*)\% Processor Time' = @{
                '\Processor(1)\% Processor Time'      = (New-TestLeaf -Value 95 -Type 'Timer100NsInverse');
                '\Processor(0)\% Processor Time'      = (New-TestLeaf -Value 10 -Type 'Timer100NsInverse');
                '\Processor(_Total)\% Processor Time' = (New-TestLeaf -Value 52.5 -Type 'Timer100NsInverse');
            };
            '\Memory\Available Bytes' = (New-TestLeaf -Value 50 -Type 'NumberOfItems64');
            '\Nope\Nothing'           = (New-TestLeaf -Value "Category 'Nope' does not exist.");
            '\Disk(*)\Reads'          = @{ };
            '\Broken(*)\Value'        = @{
                '\Broken(a)\Value' = (New-TestLeaf -Value 'Counter not initialized');
                '\Broken(b)\Value' = (New-TestLeaf -Value 'Instance vanished');
            };
        };
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'writes one metric per instance with the category as index' {
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('\Processor(*)\% Processor Time', '\Memory\Available Bytes'); 'Warning' = '80'; 'Critical' = '90'; } | Should -Be 2;

        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
            'processor::ifw_perfcounter::percentprocessortime0=10%;80;90;;',
            'processor::ifw_perfcounter::percentprocessortime1=95%;80;90;;',
            'processor::ifw_perfcounter::percentprocessortime_total=52.5%;80;90;;',
            'memory::ifw_perfcounter::availablebytes=50B;80;90;;'
        );
    }

    It 'groups the instances into one package per requested counter' {
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('\Processor(*)\% Processor Time', '\Memory\Available Bytes'); 'Critical' = '90'; 'Verbosity' = 2; } | Should -Be 2;

        [array]$Lines = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output -split "`n";
        $Lines[0] | Should -Be '[CRITICAL] Performance Counter: 1 Critical 3 Ok [CRITICAL] \Processor(1)\% Processor Time';
        $Lines[1] | Should -Be '\_ [CRITICAL] \Processor(*)\% Processor Time';
        $Lines[3] | Should -Be '   \_ [CRITICAL] \Processor(1)\% Processor Time: 95% is greater than threshold 90%';
        $Lines[5] | Should -Be '\_ [OK] \Memory\Available Bytes';
    }

    It 'filters the instances with ExcludeCounter and IncludeCounter' {
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('\Processor(*)\% Processor Time'); 'ExcludeCounter' = @('*_Total*'); } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 2;

        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('\Processor(*)\% Processor Time'); 'IncludeCounter' = @('*(0)*'); } | Should -Be 0;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @('processor::ifw_perfcounter::percentprocessortime0=10%;;;;');
    }

    It 'derives the unit of every value from the counter type and name' {
        $Units = @{
            '\Memory\Available MBytes'                 = (New-TestLeaf -Value 2 -Type 'NumberOfItems64');
            '\PhysicalDisk(_Total)\Avg. Disk sec/Read' = (New-TestLeaf -Value 0.004 -Type 'AverageTimer32');
            '\System\System Up Time'                   = (New-TestLeaf -Value 93784.33 -Type 'ElapsedTime');
            '\Memory\Pages/sec'                        = (New-TestLeaf -Value 12.5 -Type 'RateOfCountsPerSecond32');
            '\PhysicalDisk(_Total)\% Disk Time'        = (New-TestLeaf -Value 7.456789 -Type '542573824');
            '\PhysicalDisk(_Total)\Disk Bytes/sec'     = (New-TestLeaf -Value 1048576.4 -Type 'RateOfCountsPerSecond64');
        };

        Invoke-TestPerfCounterCheck -StubData $Units -Arguments @{ 'PerfCounter' = @($Units.Keys); 'Verbosity' = 2; } | Should -Be 0;

        $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
        $Result.Output | Should -Match ([regex]::Escape('\Memory\Available MBytes: 2MiB is ok'));
        $Result.Output | Should -Match ([regex]::Escape('\Avg. Disk sec/Read: 4ms is ok'));
        $Result.Output | Should -Match ([regex]::Escape('\System\System Up Time: 1d 2h 3m 4s is ok'));
        $Result.Output | Should -Match ([regex]::Escape('\Memory\Pages/sec: 12.5 is ok'));
        $Result.Output | Should -Match ([regex]::Escape('\% Disk Time: 7.46% is ok'));
        $Result.Output | Should -Match ([regex]::Escape('\Disk Bytes/sec: 1MiB is ok'));
        $Result.PerformanceData | Should -Contain 'memory::ifw_perfcounter::availablembytes=2097152B;;;;';
        $Result.PerformanceData | Should -Contain 'system::ifw_perfcounter::systemuptime=93784s;;;;';
        $Result.PerformanceData | Should -Contain 'memory::ifw_perfcounter::pagessec=12.5;;;;';

        # Three counters of the same category and instance keep distinct labels.
        $Result.PerformanceData | Should -Contain 'physicaldisk::ifw_perfcounter::avgdisksecread_total=0.004s;;;;';
        $Result.PerformanceData | Should -Contain 'physicaldisk::ifw_perfcounter::percentdisktime_total=7.46%;;;;';
        $Result.PerformanceData | Should -Contain 'physicaldisk::ifw_perfcounter::diskbytessec_total=1048576B;;;;';
    }

    It 'compares sizes and durations against thresholds with units' {
        $Units = @{
            '\Memory\Available MBytes' = (New-TestLeaf -Value 2 -Type 'NumberOfItems64');
            '\System\System Up Time'   = (New-TestLeaf -Value 93784 -Type 'ElapsedTime');
        };

        Invoke-TestPerfCounterCheck -StubData $Units -Arguments @{ 'PerfCounter' = @('\Memory\Available MBytes'); 'Warning' = '1MB'; } | Should -Be 1;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('2MiB is greater than threshold 1MB'));

        Invoke-TestPerfCounterCheck -StubData $Units -Arguments @{ 'PerfCounter' = @('\System\System Up Time'); 'Critical' = '1d'; } | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('1d 2h 3m 4s is greater than threshold 1d'));
    }

    It 'reports a failed concrete counter as UNKNOWN with its error' {
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('\Memory\Available Bytes', '\Nope\Nothing'); } | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape("[UNKNOWN] \Nope\Nothing: Failed to read the performance counter: Category 'Nope' does not exist."));
    }

    It 'reports a wildcard counter without readable instances as UNKNOWN with the first error' {
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('\Disk(*)\Reads', '\Broken(*)\Value'); } | Should -Be 3;

        $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
        $Output | Should -Match ([regex]::Escape('[UNKNOWN] \Disk(*)\Reads: Failed to read the performance counter: no instance of this counter exists'));
        $Output | Should -Match ([regex]::Escape('[UNKNOWN] \Broken(*)\Value: Failed to read the performance counter: Counter not initialized'));
    }

    It 'reports an empty result as UNKNOWN, or OK with IgnoreEmptyChecks' {
        [hashtable]$Arguments           = @{ 'PerfCounter' = @('\Processor(*)\% Processor Time'); 'IncludeCounter' = @('*(9)*'); };

        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments $Arguments | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Performance Counter: No performance counter matches the given filter';

        $Arguments['IgnoreEmptyChecks'] = $true;
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments $Arguments | Should -Be 0;

        $Arguments.Remove('IgnoreEmptyChecks');
        $Arguments['MitigateUnknown']   = $true;
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments $Arguments | Should -Be 0;
    }

    It 'rejects a missing or invalid counter path and a timed out read' {
        Invoke-TestPerfCounterCheck -StubData $script:Counters | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Performance Counter: No performance counter was provided';

        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('Memory'); } | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[UNKNOWN] Memory: Invalid performance counter path'));

        Invoke-TestPerfCounterCheck -StubData $null -Arguments @{ 'PerfCounter' = @('\Memory\Available Bytes'); } | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Performance Counter: Failed to read the performance counters \Memory\Available Bytes';
    }

    It 'suppresses the performance data with NoPerfData' {
        Invoke-TestPerfCounterCheck -StubData $script:Counters -Arguments @{ 'PerfCounter' = @('\Memory\Available Bytes'); 'NoPerfData' = $true; } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
    }
}

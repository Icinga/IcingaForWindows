$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Get-IcingaProcessInformation' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        # Builds the -StructureByInstance result of the process counters. Every
        # process is @(instance, id, cpu, memory, pagefile, threads); a string id
        # becomes the counter error of an instance that ended between the reads.
        function New-TestProcessCounter()
        {
            param (
                [array]$Processes = @(
                    @('powershell', 100, 50, 104857600, 52428800, 10),
                    @('powershell#1', 200, 30, 209715200, 62914560, 20),
                    @('svchost', 300, 8, 10485760, 5242880, 5),
                    @('_Total', 0, 400, 1073741824, 1073741824, 900),
                    @('Idle', 0, 300, 8192, 0, 8),
                    @('gone', 'The instance "gone" does not exist in the category "Process"', 0, 0, 0, 0)
                )
            );

            [hashtable]$Result = @{ };

            foreach ($Process in $Processes) {
                [hashtable]$Values = @{ };
                [array]$Counters   = @(
                    @('ID Process', $Process[1]),
                    @('% Processor Time', $Process[2]),
                    @('Working Set - Private', $Process[3]),
                    @('Page File Bytes', $Process[4]),
                    @('Thread Count', $Process[5])
                );

                foreach ($Counter in $Counters) {
                    $Leaf = @{ 'value' = [decimal]0; 'sample' = $null; 'help' = ''; 'type' = ''; 'error' = $null; };

                    if ($Counter[1] -is [string]) {
                        $Leaf['error'] = $Counter[1];
                    } else {
                        $Leaf['value'] = [decimal]$Counter[1];
                    }

                    $Values[$Counter[0]] = $Leaf;
                }

                $Result[$Process[0]] = @{ 'Process' = $Values; };
            }

            return $Result;
        }

        # Runs the provider inside the module scope with the CIM and performance counter
        # functions shadowed. 16GiB installed memory, 4 logical processors, 20GiB commit limit.
        function Invoke-TestProcessInformation()
        {
            param (
                $Counters             = (New-TestProcessCounter),
                $CommitLimit          = [decimal]21474836480,
                [hashtable]$Arguments = @{ },
                [string]$FailClass    = ''
            );

            return (& $script:IcingaModule {
                param ($Counters, $CommitLimit, $Arguments, $FailClass);

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

                    if ($StructureByInstance) {
                        return $Counters;
                    }

                    $Leaf = @{ 'value' = [decimal]0; 'sample' = $null; 'help' = ''; 'type' = ''; 'error' = $null; };

                    if ($CommitLimit -is [string]) {
                        $Leaf['error'] = $CommitLimit;
                    } else {
                        $Leaf['value'] = [decimal]$CommitLimit;
                    }

                    return @{ '\Memory\Commit Limit' = $Leaf; };
                }

                function Get-IcingaWindowsInformation()
                {
                    param (
                        [string]$ClassName = '',
                        [string]$Namespace = 'root/cimv2',
                        [string]$Filter    = '',
                        [array]$Property   = @()
                    );

                    if ($ClassName -eq $FailClass) {
                        return [IcingaError]::new('WindowsInformationAccessDenied', 'Simulated failure of ' + $ClassName, @{ });
                    }

                    return ,@([PSCustomObject]@{ 'TotalPhysicalMemory' = [uint64]17179869184; 'NumberOfLogicalProcessors' = [uint32]4; });
                }

                Get-IcingaProcessInformation @Arguments;
            } $Counters $CommitLimit $Arguments $FailClass);
        }
    }

    It 'groups the processes by name and keys every process by its id' {
        $Data = Invoke-TestProcessInformation;

        @($Data.Processes.Keys | Sort-Object)                          | Should -Be @('powershell', 'svchost');
        @($Data.Processes['powershell'].Instances.Keys | Sort-Object)  | Should -Be @('100', '200');
        $Data.Processes['powershell'].Instances['200'].Memory          | Should -Be 209715200;
        $Data.Processes['powershell'].Instances['200'].PageFile        | Should -Be 62914560;
        $Data.Processes['powershell'].Instances['200'].Threads         | Should -Be 20;
    }

    It 'divides the CPU usage by the number of logical processors' {
        $Data = Invoke-TestProcessInformation;

        $Data.Processes['powershell'].Instances['100'].Cpu | Should -Be 12.5;
        $Data.Processes['powershell'].Instances['200'].Cpu | Should -Be 7.5;
        $Data.Processes['svchost'].Instances['300'].Cpu    | Should -Be 2;
        $Data.LogicalProcessors                            | Should -Be 4;
    }

    It 'sums every process of a name' {
        $Total = (Invoke-TestProcessInformation).Processes['powershell'].Total;

        $Total.Cpu      | Should -Be 20;
        $Total.Memory   | Should -Be 314572800;
        $Total.PageFile | Should -Be 115343360;
        $Total.Threads  | Should -Be 30;
        $Total.Count    | Should -Be 2;
    }

    It 'leaves out _Total, Idle and processes that ended between the reads' {
        $Data = Invoke-TestProcessInformation;

        $Data.Processes.ContainsKey('_Total') | Should -BeFalse;
        $Data.Processes.ContainsKey('Idle')   | Should -BeFalse;
        $Data.Processes.ContainsKey('gone')   | Should -BeFalse;
    }

    It 'returns the installed memory and the commit limit' {
        $Data = Invoke-TestProcessInformation;

        $Data.MemoryTotal | Should -Be 17179869184;
        $Data.CommitLimit | Should -Be 21474836480;
    }

    It 'filters the processes by name' {
        @((Invoke-TestProcessInformation -Arguments @{ 'Include' = @('power*'); }).Processes.Keys) | Should -Be @('powershell');
        @((Invoke-TestProcessInformation -Arguments @{ 'Exclude' = @('POWERSHELL'); }).Processes.Keys) | Should -Be @('svchost');
    }

    It 'returns the IcingaError of a failed CIM query' {
        $Data = Invoke-TestProcessInformation -FailClass 'Win32_ComputerSystem';

        (Test-IcingaError -InputObject $Data) | Should -BeTrue;
        $Data.Message                         | Should -Be 'Simulated failure of Win32_ComputerSystem';
    }

    It 'returns an IcingaError when the counters cannot be read' {
        $Data = Invoke-TestProcessInformation -Counters $null;
        (Test-IcingaError -InputObject $Data) | Should -BeTrue;
        $Data.ReturnCode                      | Should -Be 'ProcessCounterReadFailed';

        $Data = Invoke-TestProcessInformation -Counters @{ };
        (Test-IcingaError -InputObject $Data) | Should -BeTrue;

        $Data = Invoke-TestProcessInformation -CommitLimit 'Counter not initialized';
        (Test-IcingaError -InputObject $Data) | Should -BeTrue;
        $Data.Message                         | Should -Match 'Commit Limit';
    }
}

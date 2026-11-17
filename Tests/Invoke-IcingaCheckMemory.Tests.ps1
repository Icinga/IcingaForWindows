<#
.SYNOPSIS
Pester unit test suite for Invoke-IcingaCheckMemory in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for Invoke-IcingaCheckMemory
as part of the Icinga for Windows automated Pester test suite.

.NOTES
Executed via build/Invoke-ModuleTests.ps1 using Pester 5.0+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckMemory' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Builds the -StructureByInstance result of the two memory counters. A string
        # value becomes the counter error.
        function New-TestMemoryCounter()
        {
            param (
                $Available = [decimal]4294967296,
                $PagesSec  = [decimal]12.5
            );

            [hashtable]$Memory = @{ };

            foreach ($Counter in @(@('Available Bytes', $Available), @('Pages/sec', $PagesSec))) {
                $Leaf = @{ 'value' = [decimal]0; 'sample' = $null; 'help' = ''; 'type' = ''; 'error' = $null; };

                if ($Counter[1] -is [string]) {
                    $Leaf['error'] = $Counter[1];
                } else {
                    $Leaf['value'] = [decimal]$Counter[1];
                }

                $Memory[$Counter[0]] = $Leaf;
            }

            return @{ 'Memory' = $Memory; };
        }

        # 16GiB installed, two page files of 2048MB (512MB used) and 1024MB (1000MB used).
        function New-TestCimData()
        {
            param (
                [bool]$AutomaticManagedPagefile = $true,
                [array]$PageFileSettings        = @()
            );

            return @{
                'Win32_ComputerSystem' = @([PSCustomObject]@{ 'TotalPhysicalMemory' = [uint64]17179869184; 'AutomaticManagedPagefile' = $AutomaticManagedPagefile; });
                'Win32_PageFileUsage'  = @(
                    [PSCustomObject]@{ 'Name' = 'D:\pagefile.sys'; 'AllocatedBaseSize' = [uint32]1024; 'CurrentUsage' = [uint32]1000; },
                    [PSCustomObject]@{ 'Name' = 'C:\pagefile.sys'; 'AllocatedBaseSize' = [uint32]2048; 'CurrentUsage' = [uint32]512; }
                );
                'Win32_PageFileSetting' = $PageFileSettings;
            };
        }

        # Runs the plugin inside the module scope with the CIM and performance counter
        # functions shadowed, so the check works on the given data.
        function Invoke-TestMemoryCheck()
        {
            param (
                [hashtable]$CimData   = (New-TestCimData),
                $Counters             = (New-TestMemoryCounter),
                [hashtable]$Arguments = @{ },
                [string]$FailClass    = ''
            );

            return (& $script:IcingaModule {
                param ($CimData, $Counters, $Arguments, $FailClass);

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

                    return $Counters;
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

                    return ,@($CimData[$ClassName]);
                }

                Invoke-IcingaCheckMemory @Arguments;
            } $CimData $Counters $Arguments $FailClass);
        }
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'writes the used memory, the paging rate and every page file as perfdata' {
        Invoke-TestMemoryCheck -Arguments @{ 'Warning' = '80%'; 'Critical' = '90%'; } | Should -Be 0;

        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
            'memory::ifw_memory::used=12884901888B;13743895347;15461882266;0;17179869184',
            'memory::ifw_memory::pagessec=12.5;;;;',
            'cpagefilesys::ifw_pagefile::used=536870912B;;;0;2147483648',
            'dpagefilesys::ifw_pagefile::used=1048576000B;;;0;1073741824'
        );
    }

    It 'renders the used memory with its share of the installed memory' {
        Invoke-TestMemoryCheck -Arguments @{ 'Warning' = '70%'; } | Should -Be 1;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[WARNING] Used Memory: 12GiB (75%) is greater than threshold 11.2GiB (70%)'));
    }

    It 'checks the page files and the paging rate against their own thresholds' {
        Invoke-TestMemoryCheck -Arguments @{ 'PageFileWarning' = '90%'; 'MemoryPagesSecCritical' = '10'; 'Verbosity' = 2; } | Should -Be 2;

        $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
        $Output | Should -Match ([regex]::Escape('[CRITICAL] Memory pages/sec: 12.5 is greater than threshold 10'));
        $Output | Should -Match ([regex]::Escape('[OK] C:\pagefile.sys: 512MiB (25%) is ok'));
        $Output | Should -Match ([regex]::Escape('[WARNING] D:\pagefile.sys: 1000MiB (97.66%) is greater than threshold 921.6MiB (90%)'));
    }

    It 'measures a page file with a configured maximum against that maximum' {
        $CimData = New-TestCimData -AutomaticManagedPagefile $false -PageFileSettings @(
            [PSCustomObject]@{ 'Name' = 'C:\pagefile.sys'; 'MaximumSize' = [uint32]4096; },
            [PSCustomObject]@{ 'Name' = 'D:\pagefile.sys'; 'MaximumSize' = [uint32]0; }
        );

        Invoke-TestMemoryCheck -CimData $CimData | Should -Be 0;

        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'cpagefilesys::ifw_pagefile::used=536870912B;;;0;4294967296';
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'dpagefilesys::ifw_pagefile::used=1048576000B;;;0;1073741824';
    }

    It 'filters the page files and leaves the package out when none remains' {
        Invoke-TestMemoryCheck -Arguments @{ 'ExcludePageFile' = @('D:*'); 'Verbosity' = 2; } | Should -Be 0;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Not -Match 'D:\\pagefile';

        Invoke-TestMemoryCheck -Arguments @{ 'IncludePageFile' = @('X:*'); 'Verbosity' = 2; } | Should -Be 0;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Not -Match 'PageFile Usage';
    }

    It 'reports a failed CIM query as UNKNOWN with its reason' {
        Invoke-TestMemoryCheck -FailClass 'Win32_ComputerSystem' | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Memory Usage: Simulated failure of Win32_ComputerSystem';

        Invoke-TestMemoryCheck -FailClass 'Win32_PageFileUsage' | Should -Be 3;
    }

    It 'keeps the page files on their allocated size when the settings cannot be read' {
        Invoke-TestMemoryCheck -CimData (New-TestCimData -AutomaticManagedPagefile $false) -FailClass 'Win32_PageFileSetting' | Should -Be 0;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Contain 'cpagefilesys::ifw_pagefile::used=536870912B;;;0;2147483648';
    }

    It 'reports unreadable performance counters as UNKNOWN' {
        Invoke-TestMemoryCheck -Counters $null | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Memory Usage: Failed to read the performance counters of the category Memory';

        Invoke-TestMemoryCheck -Counters (New-TestMemoryCounter -Available 'Counter not initialized') | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[UNKNOWN] Used Memory: Failed to read the performance counter \Memory\Available Bytes: Counter not initialized'));
    }

    It 'suppresses the performance data with NoPerfData' {
        Invoke-TestMemoryCheck -Arguments @{ 'NoPerfData' = $true; } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
    }

    It 'guards empty Win32_ComputerSystem results and skips 0-byte pagefiles cleanly' {
        [hashtable]$EmptyComp    = @{
            'Win32_ComputerSystem' = @();
            'Win32_PageFileUsage'  = @();
        };
        Invoke-TestMemoryCheck -CimData $EmptyComp | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match 'Failed to read installed physical memory';

        [hashtable]$ZeroPageData = @{
            'Win32_ComputerSystem' = @([PSCustomObject]@{ 'TotalPhysicalMemory' = [uint64]17179869184; 'AutomaticManagedPagefile' = $true; });
            'Win32_PageFileUsage'  = @(
                [PSCustomObject]@{ 'Name' = 'C:\pagefile.sys'; 'AllocatedBaseSize' = [uint32]0; 'CurrentUsage' = [uint32]0; }
            );
        };
        Invoke-TestMemoryCheck -CimData $ZeroPageData -Arguments @{ 'PageFileWarning' = '80%'; 'PageFileCritical' = '90%'; } | Should -Be 0;
    }
}

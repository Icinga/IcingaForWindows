<#
.SYNOPSIS
Pester unit test suite for Invoke-IcingaCheckProcess in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for Invoke-IcingaCheckProcess
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

Describe 'Invoke-IcingaCheckProcess' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Two PowerShell processes on a host with 16GiB memory and a 4GiB commit limit.
        function New-TestProcessData()
        {
            param (
                [uint64]$CommitLimit = 4294967296
            );

            return @{
                'MemoryTotal'       = [uint64]17179869184;
                'CommitLimit'       = $CommitLimit;
                'LogicalProcessors' = 4;
                'Processes'         = @{
                    'powershell' = @{
                        'Name'      = 'powershell';
                        'Instances' = @{
                            '200' = @{ 'Id' = 200; 'Cpu' = [double]7.5; 'Memory' = [uint64]209715200; 'PageFile' = [uint64]62914560; 'Threads' = 20; };
                            '100' = @{ 'Id' = 100; 'Cpu' = [double]12.5; 'Memory' = [uint64]104857600; 'PageFile' = [uint64]52428800; 'Threads' = 10; };
                        };
                        'Total'     = @{ 'Cpu' = [double]20; 'Memory' = [uint64]314572800; 'PageFile' = [uint64]115343360; 'Threads' = 30; 'Count' = 2; };
                    };
                };
            };
        }

        # Runs the plugin inside the module scope with the provider shadowed.
        function Invoke-TestProcessCheck()
        {
            param (
                $Data                 = (New-TestProcessData),
                [hashtable]$Arguments = @{ }
            );

            return (& $script:IcingaModule {
                param ($Data, $Arguments);

                function Get-IcingaProcessInformation()
                {
                    param (
                        [array]$Include = @(),
                        [array]$Exclude = @()
                    );

                    if ($Data -is [string]) {
                        return [IcingaError]::new('ProcessCounterReadFailed', $Data, @{ });
                    }

                    return $Data;
                }

                Invoke-IcingaCheckProcess @Arguments;
            } $Data $Arguments);
        }
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'checks every process and the summary of every name' {
        Invoke-TestProcessCheck -Arguments @{ 'Verbosity' = 2; } | Should -Be 0;

        $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
        $Output | Should -Match ([regex]::Escape('[OK] Process Overview: 13 Ok'));
        $Output | Should -Match ([regex]::Escape('\_ [OK] powershell [100]'));
        $Output | Should -Match ([regex]::Escape('\_ [OK] CPU Usage: 12.5% is ok'));
        $Output | Should -Match ([regex]::Escape('\_ [OK] Page File Usage: 50MiB is ok'));
        $Output | Should -Match ([regex]::Escape('\_ [OK] powershell Summary'));
        $Output | Should -Match ([regex]::Escape('\_ [OK] Process Count: 2 is ok'));
    }

    It 'lists the single processes in the order of their ids' {
        Invoke-TestProcessCheck -Arguments @{ 'Verbosity' = 2; } | Should -Be 0;

        $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
        $Output.IndexOf('powershell [100]') | Should -BeLessThan $Output.IndexOf('powershell [200]');
    }

    It 'writes performance data for the summary only' {
        Invoke-TestProcessCheck | Should -Be 0;

        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
            'powershell::ifw_process::pagefile=115343360B;;;0;4294967296',
            'powershell::ifw_process::memory=314572800B;;;0;17179869184',
            'powershell::ifw_process::cpu=20%;;;0;100',
            'powershell::ifw_process::threads=30;;;;',
            'powershell::ifw_process::count=2;;;;'
        );
    }

    It 'applies the single thresholds to every process and the total thresholds to the summary' {
        Invoke-TestProcessCheck -Arguments @{ 'CPUWarning' = '10'; 'TotalMemoryCritical' = '1%'; 'TotalProcessCountCritical' = '3:'; } | Should -Be 2;

        $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
        $Output | Should -Match ([regex]::Escape('\_ [WARNING] powershell [100]'));
        $Output | Should -Match ([regex]::Escape('[WARNING] CPU Usage: 12.5% is greater than threshold 10%'));
        $Output | Should -Match ([regex]::Escape('[CRITICAL] Memory Usage: 300MiB (1.83%) is greater than threshold 163.84MiB (1%)'));
        $Output | Should -Match ([regex]::Escape('[CRITICAL] Process Count: 2 is lower than threshold 3'));
        $Output | Should -Not -Match ([regex]::Escape('powershell [200]'));
    }

    It 'measures the page file usage against the commit limit' {
        Invoke-TestProcessCheck -Arguments @{ 'TotalPageFileWarning' = '2%'; } | Should -Be 1;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[WARNING] Page File Usage: 110MiB (2.69%) is greater than threshold 81.92MiB (2%)'));
    }

    It 'reports every requested process without a match with the OverrideNotFound state' {
        Invoke-TestProcessCheck -Arguments @{ 'Process' = @('powershell', 'notepad', 'note*'); } | Should -Be 3;

        $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
        $Output | Should -Match ([regex]::Escape('[UNKNOWN] notepad: Process not found'));
        $Output | Should -Match ([regex]::Escape('[UNKNOWN] note*: Process not found'));
        $Output | Should -Not -Match ([regex]::Escape('powershell: Process not found'));

        Invoke-TestProcessCheck -Arguments @{ 'Process' = @('notepad'); 'OverrideNotFound' = 'Critical'; } | Should -Be 2;
        Invoke-TestProcessCheck -Arguments @{ 'Process' = @('notepad'); 'OverrideNotFound' = 'Ok'; } | Should -Be 0;
    }

    It 'reports a provider error as UNKNOWN with its reason' {
        Invoke-TestProcessCheck -Data 'Simulated counter failure' | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Process Overview: Simulated counter failure';
    }

    It 'reports UNKNOWN when no process matches' {
        $Data              = New-TestProcessData;
        $Data['Processes'] = @{ };

        Invoke-TestProcessCheck -Data $Data | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Process Overview: No process matches the given filter';
    }

    It 'suppresses the performance data with NoPerfData' {
        Invoke-TestProcessCheck -Arguments @{ 'NoPerfData' = $true; } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
    }
}

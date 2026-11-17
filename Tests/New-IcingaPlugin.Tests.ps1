<#
.SYNOPSIS
Pester unit test suite for New-IcingaPlugin in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for New-IcingaPlugin
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

Describe 'New-IcingaPlugin' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        # Daemon mode keeps Compile from writing to the console; the result is still
        # stored in Private.Icinga.CheckResult.
        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        function Invoke-TestNewPlugin()
        {
            return (& $script:IcingaModule {
                New-IcingaPlugin @args;
            } @args);
        }
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'creates an instance of the IcingaPlugin type loaded by the current runspace' {
        $PluginType = & $script:IcingaModule { 'IcingaPlugin' -as [type] };
        $Plugin     = Invoke-TestNewPlugin 'Disks';

        ($Plugin.GetType() -eq $PluginType) | Should -BeTrue;
    }

    It 'creates a container from a name only' {
        $Plugin = & $script:IcingaModule { New-IcingaPlugin -Name 'Disks' };

        $Plugin.Name  | Should -Be 'Disks';
        $Plugin.Value | Should -BeNullOrEmpty;
        $Plugin.Unit  | Should -Be '';
    }

    It 'creates a check from a name and a value' {
        $Plugin = & $script:IcingaModule { New-IcingaPlugin -Name 'Load' -Value 95 };

        $Plugin.Value | Should -Be 95;
        $Plugin.Unit  | Should -Be '';
    }

    It 'passes the unit to the check' {
        $Plugin = & $script:IcingaModule { New-IcingaPlugin -Name 'Load' -Value 95 -Unit '%' };

        $Plugin.Value | Should -Be 95;
        $Plugin.Unit  | Should -Be '%';
    }

    It 'binds name, value and unit by position' {
        $Plugin = Invoke-TestNewPlugin 'C:' 55 '%';

        $Plugin.Name  | Should -Be 'C:';
        $Plugin.Value | Should -Be 55;
        $Plugin.Unit  | Should -Be '%';
    }

    It 'returns a node whose fluent chain evaluates and compiles the check' {
        $ExitCode = (Invoke-TestNewPlugin 'Load' 95 '%').Warning('80').Critical('90').CheckRange().Compile();

        $ExitCode | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.ToString() | Should -Match '^\[CRITICAL\] Load';
    }

    It 'aggregates the checks added to a container' {
        $CheckPackage = Invoke-TestNewPlugin 'Disks';
        $CheckPackage.AddCheck((Invoke-TestNewPlugin 'C:' 55 '%').Warning('80').CheckRange()).Commit();
        $CheckPackage.AddCheck((Invoke-TestNewPlugin 'D:' 85 '%').Warning('80').CheckRange()).Commit();

        $CheckPackage.Compile() | Should -Be 1;
    }

    It 'is publicly exported for external SDK plugins outside module scope' {
        $ExportedCmd  = Get-Command -Name 'New-IcingaPlugin' -Module 'IcingaForWindows' -ErrorAction Stop;
        $SdkContainer = New-IcingaPlugin 'Custom SDK Package';
        $SdkLeaf      = (New-IcingaPlugin 'Queue Depth' 12).MetricIndex('queue0').MetricName('customsdk').Warning('10').Critical('20').CheckRange();
        $SdkContainer.AddCheck($SdkLeaf).Commit();

        [int]$SdkExit = $SdkContainer.Compile();

        $ExportedCmd.Name                                                        | Should -Be 'New-IcingaPlugin';
        $SdkExit                                                                 | Should -Be 1;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output               | Should -Match '^\[WARNING\] Custom SDK Package';
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0]   | Should -Be 'queue0::ifw_customsdk::queuedepth=12;10;20;;';
    }
}

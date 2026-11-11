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
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'creates an instance of the IcingaPlugin type loaded by the current runspace' {
        $PluginType = & $script:IcingaModule { 'IcingaPlugin' -as [type] };
        $Plugin     = New-IcingaPlugin 'Disks';

        ($Plugin.GetType() -eq $PluginType) | Should -BeTrue;
    }

    It 'creates a container from a name only' {
        $Plugin = New-IcingaPlugin -Name 'Disks';

        $Plugin.Name  | Should -Be 'Disks';
        $Plugin.Value | Should -BeNullOrEmpty;
        $Plugin.Unit  | Should -Be '';
    }

    It 'creates a check from a name and a value' {
        $Plugin = New-IcingaPlugin -Name 'Load' -Value 95;

        $Plugin.Value | Should -Be 95;
        $Plugin.Unit  | Should -Be '';
    }

    It 'passes the unit to the check' {
        $Plugin = New-IcingaPlugin -Name 'Load' -Value 95 -Unit '%';

        $Plugin.Value | Should -Be 95;
        $Plugin.Unit  | Should -Be '%';
    }

    It 'binds name, value and unit by position' {
        $Plugin = New-IcingaPlugin 'C:' 55 '%';

        $Plugin.Name  | Should -Be 'C:';
        $Plugin.Value | Should -Be 55;
        $Plugin.Unit  | Should -Be '%';
    }

    It 'returns a node whose fluent chain evaluates and compiles the check' {
        $ExitCode = (New-IcingaPlugin 'Load' 95 '%').Warning('80').Critical('90').CheckRange().Compile();

        $ExitCode | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.ToString() | Should -Match '^\[CRITICAL\] Load';
    }

    It 'aggregates the checks added to a container' {
        $CheckPackage = New-IcingaPlugin 'Disks';
        $CheckPackage.AddCheck((New-IcingaPlugin 'C:' 55 '%').Warning('80').CheckRange()).Commit();
        $CheckPackage.AddCheck((New-IcingaPlugin 'D:' 85 '%').Warning('80').CheckRange()).Commit();

        $CheckPackage.Compile() | Should -Be 1;
    }
}

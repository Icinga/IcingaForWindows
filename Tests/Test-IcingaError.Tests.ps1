$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Test-IcingaError' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    It 'returns $true for an IcingaError' {
        $IcingaError = & $script:IcingaModule { ('IcingaError' -as [type])::new('Failed to query Win32_Service') };

        Test-IcingaError -InputObject $IcingaError | Should -BeTrue;
    }

    It 'returns $false for <Case>' -TestCases @(
        @{ 'Case' = '$null';          'Value' = $null; },
        @{ 'Case' = 'a string';       'Value' = 'Failed to query'; },
        @{ 'Case' = 'a number';       'Value' = 3; },
        @{ 'Case' = 'a hashtable';    'Value' = @{ 'Message' = 'Failed'; }; },
        @{ 'Case' = 'an empty array'; 'Value' = @(); },
        @{ 'Case' = 'an array';       'Value' = @('a', 'b'); }
    ) {
        Test-IcingaError -InputObject $Value | Should -BeFalse;
    }

    It 'returns $false for an array that contains an IcingaError' {
        $IcingaError = & $script:IcingaModule { ('IcingaError' -as [type])::new('Failed') };

        Test-IcingaError -InputObject @($IcingaError, 'b') | Should -BeFalse;
    }
}

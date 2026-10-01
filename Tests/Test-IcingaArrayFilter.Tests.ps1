$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Test-IcingaArrayFilter' {
    Context 'Single values' {
        It 'passes every value without filters' {
            Test-IcingaArrayFilter -InputObject 'Spooler' | Should -BeTrue;
        }

        It 'requires an include match when an include list is given' {
            Test-IcingaArrayFilter -InputObject 'Spooler' -Include 'Spo*'       | Should -BeTrue;
            Test-IcingaArrayFilter -InputObject 'Spooler' -Include 'WinRM', 'W*' | Should -BeFalse;
        }

        It 'matches case-insensitively with ? and [] wildcards' {
            Test-IcingaArrayFilter -InputObject 'SPOOLER' -Include 'spo?ler' | Should -BeTrue;
            Test-IcingaArrayFilter -InputObject 'D' -Include '[c-e]'         | Should -BeTrue;
        }

        It 'lets an exclude match win over an include match' {
            Test-IcingaArrayFilter -InputObject 'Spooler' -Include '*' -Exclude 'Spooler' | Should -BeFalse;
            Test-IcingaArrayFilter -InputObject 'WinRM' -Exclude 'Spooler'                | Should -BeTrue;
        }

        It 'compares non-string values by their string form' {
            Test-IcingaArrayFilter -InputObject 4 -Include '4' | Should -BeTrue;
        }

        It 'never passes $null' {
            Test-IcingaArrayFilter -InputObject $null | Should -BeFalse;
        }

        It 'treats an invalid wildcard pattern as no match instead of throwing' {
            Test-IcingaArrayFilter -InputObject 'abc' -Include '[abc' | Should -BeFalse;
            Test-IcingaArrayFilter -InputObject 'abc' -Exclude '[abc' | Should -BeTrue;
        }
    }

    Context 'Arrays' {
        It 'returns the passing elements as an array' {
            $Result = Test-IcingaArrayFilter -InputObject @('C', 'D', 'E') -Exclude 'D';
            ($Result -is [array]) | Should -BeTrue;
            $Result               | Should -Be @('C', 'E');
        }

        It 'returns an array for a single passing element and an empty array for none' {
            $Single = Test-IcingaArrayFilter -InputObject @('C', 'D') -Include 'C';
            ($Single -is [array]) | Should -BeTrue;
            $Single.Count         | Should -Be 1;

            $None = Test-IcingaArrayFilter -InputObject @('C', 'D') -Include 'Q';
            ($None -is [array]) | Should -BeTrue;
            $None.Count         | Should -Be 0;
        }
    }
}

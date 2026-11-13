$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'IcingaError' {
    BeforeAll {
        # The class lives in the dot-sourced kernel and is only visible inside the
        # script module scope.
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    Context 'Construction' {
        It 'keeps a plain message verbatim, including braces' {
            $Error1 = & $script:IcingaModule { [IcingaError]::new('Volume \\?\Volume{1234}\ is offline') };
            $Error1.Message    | Should -Be 'Volume \\?\Volume{1234}\ is offline';
            $Error1.ReturnCode | Should -Be '';
            $Error1.Data.Count | Should -Be 0;
        }

        It 'formats a message with its arguments' {
            $Error1 = & $script:IcingaModule { [IcingaError]::new('Failed to query {0}: {1}', @('Win32_Service', 'Access denied')) };
            $Error1.Message | Should -Be 'Failed to query Win32_Service: Access denied';
        }

        It 'stores return code and data' {
            $Error1 = & $script:IcingaModule { [IcingaError]::new('WindowsInformationClassUnknown', 'The class Foo is unknown', @{ 'ClassName' = 'Foo'; }) };
            $Error1.ReturnCode        | Should -Be 'WindowsInformationClassUnknown';
            $Error1.Message           | Should -Be 'The class Foo is unknown';
            $Error1.Data['ClassName'] | Should -Be 'Foo';
        }

        It 'stores an empty hashtable for $null data' {
            $Error1 = & $script:IcingaModule { [IcingaError]::new('Key', 'Message', $null) };
            ($Error1.Data -is [hashtable]) | Should -BeTrue;
            $Error1.Data.Count             | Should -Be 0;
        }

        It 'renders as its message' {
            $Text = & $script:IcingaModule { [string]([IcingaError]::new('boom')) };
            $Text | Should -Be 'boom';
        }
    }

    Context 'FormatMessage' {
        It 'returns the message unchanged without arguments' {
            (& $script:IcingaModule { [IcingaError]::FormatMessage('Value {x}', @()) }) | Should -Be 'Value {x}';
            (& $script:IcingaModule { [IcingaError]::FormatMessage('Value {x}', $null) }) | Should -Be 'Value {x}';
        }

        It 'appends the arguments instead of throwing on an invalid format string' {
            (& $script:IcingaModule { [IcingaError]::FormatMessage('Value {x}', @('a', 'b')) }) | Should -Be 'Value {x} (a, b)';
        }
    }
}

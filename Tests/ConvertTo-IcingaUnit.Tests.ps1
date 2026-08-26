$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'ConvertTo-IcingaUnit' {
    Context 'Input parsing' {
        It 'Parses a combined value and unit string' {
            $result = ConvertTo-IcingaUnit -InputValue '1024B';
            $result.InputValue | Should -Be 1024;
            $result.InputUnit  | Should -Be 'B';
        }

        It 'Parses a plain number together with -InputUnit' {
            $result = ConvertTo-IcingaUnit -InputValue '1024' -InputUnit 'B';
            $result.InputUnit    | Should -Be 'B';
            $result.OutputString | Should -Be '1KiB';
        }

        It 'Prefers a unit suffix on the value over -InputUnit' {
            $result = ConvertTo-IcingaUnit -InputValue '1024B' -InputUnit 's';
            $result.InputUnit | Should -Be 'B';
        }
    }

    Context 'Data size auto best-fit (binary ladder)' {
        It 'Keeps a sub-KiB value in bytes so it never rounds to zero' {
            $result = ConvertTo-IcingaUnit -InputValue '1000B';
            $result.OutputUnit   | Should -Be 'B';
            $result.OutputString | Should -Be '1000B';
        }

        It 'Promotes exactly 1024 bytes to 1KiB' {
            (ConvertTo-IcingaUnit -InputValue '1024B').OutputString | Should -Be '1KiB';
        }

        It 'Promotes to MiB and rounds to two decimals' {
            (ConvertTo-IcingaUnit -InputValue '1048576B').OutputString | Should -Be '1MiB';
            (ConvertTo-IcingaUnit -InputValue '1500000B').OutputString | Should -Be '1.43MiB';
        }
    }

    Context 'Explicit target unit' {
        It 'Converts into the requested unit even when the result is small' {
            $result = ConvertTo-IcingaUnit -InputValue '1000B' -TargetUnit 'GiB';
            $result.OutputUnit | Should -Be 'GiB';
        }

        It 'Converts bits into bytes within the same family' {
            (ConvertTo-IcingaUnit -InputValue '16' -InputUnit 'bit' -TargetUnit 'B').OutputString | Should -Be '2B';
        }
    }

    Context 'Data unit matching is case-insensitive' {
        It 'Accepts lower-case data units and normalizes to the canonical form' {
            $result = ConvertTo-IcingaUnit -InputValue '1000b' -TargetUnit 'gib';
            $result.InputUnit  | Should -Be 'B';
            $result.OutputUnit | Should -Be 'GiB';
        }
    }

    Context 'Time is always decomposed' {
        It 'Decomposes into every non-zero unit (compact)' {
            $result = ConvertTo-IcingaUnit -InputValue '8600' -InputUnit 's';
            $result.OutputValue  | Should -Be 2;
            $result.OutputUnit   | Should -Be 'h';
            $result.OutputString | Should -Be '2h 23m 20s';
        }

        It 'Renders a single unit without stray parts' {
            (ConvertTo-IcingaUnit -InputValue '3600' -InputUnit 's').OutputString | Should -Be '1h';
        }

        It 'Decomposes down to days' {
            (ConvertTo-IcingaUnit -InputValue '90061' -InputUnit 's').OutputString | Should -Be '1d 1h 1m 1s';
        }

        It 'Handles sub-second units' {
            (ConvertTo-IcingaUnit -InputValue '1500' -InputUnit 'ms').OutputString | Should -Be '1s 500ms';
            (ConvertTo-IcingaUnit -InputValue '500' -InputUnit 'ms').OutputString  | Should -Be '500ms';
        }
    }

    Context 'Time unit matching is case-sensitive (minute vs month)' {
        It 'Treats lower-case m as minute' {
            $result = ConvertTo-IcingaUnit -InputValue '1' -InputUnit 'm';
            $result.OutputUnit   | Should -Be 'm';
            $result.OutputString | Should -Be '1m';
        }

        It 'Treats upper-case M as month' {
            $result = ConvertTo-IcingaUnit -InputValue '1' -InputUnit 'M';
            $result.OutputUnit   | Should -Be 'M';
            $result.OutputString | Should -Be '1M';
        }
    }

    Context 'Human readable output' {
        It 'Uses long, pluralized English names for time' {
            (ConvertTo-IcingaUnit -InputValue '8600' -InputUnit 's' -AsHumanReadable).OutputString | Should -Be '2 Hours 23 Minutes 20 Seconds';
        }

        It 'Uses the singular form for a value of one' {
            (ConvertTo-IcingaUnit -InputValue '3600' -InputUnit 's' -AsHumanReadable).OutputString | Should -Be '1 Hour';
            (ConvertTo-IcingaUnit -InputValue '1' -InputUnit 'B' -AsHumanReadable).OutputString     | Should -Be '1 Byte';
        }

        It 'Renders data sizes as a single long-named value' {
            (ConvertTo-IcingaUnit -InputValue '1500000B' -AsHumanReadable).OutputString | Should -Be '1.43 Mebibytes';
        }
    }

    Context 'Exposes the normalized base value and family' {
        It 'Reports the unrounded base value in bytes for data units' {
            $result = ConvertTo-IcingaUnit -InputValue '10GB';
            $result.BaseValue | Should -Be 10000000000;
            $result.Family    | Should -Be 'Data';
        }

        It 'Reports the base value in seconds for time units' {
            $result = ConvertTo-IcingaUnit -InputValue '500' -InputUnit 'ms';
            $result.BaseValue | Should -Be 0.5;
            $result.Family    | Should -Be 'Time';
        }

        It 'Keeps sub-10ms precision in the base value (no 2-decimal rounding)' {
            (ConvertTo-IcingaUnit -InputValue '1' -InputUnit 'ms').BaseValue | Should -Be 0.001;
        }
    }

    Context 'Failure paths return $null' {
        # icinga-powershell-framework #503: a label containing a unit substring
        # must never be parsed as a unit value (e.g. 'Serverms-001' -> -1ms).
        It 'Rejects label-like strings instead of parsing a hidden unit' {
            ConvertTo-IcingaUnit -InputValue 'Serverms-001' | Should -BeNullOrEmpty;
            ConvertTo-IcingaUnit -InputValue 'Server-001'   | Should -BeNullOrEmpty;
        }

        # icinga-powershell-framework #816: colon/range/non-numeric strings must
        # fail cleanly, not throw a raw Decimal cast exception.
        It 'Rejects colon and range strings without a cast exception' {
            ConvertTo-IcingaUnit -InputValue 'testb:testc' | Should -BeNullOrEmpty;
            ConvertTo-IcingaUnit -InputValue '20:40'       | Should -BeNullOrEmpty;
        }

        It 'Rejects a bare or empty value with no number' {
            ConvertTo-IcingaUnit -InputValue 'ms' | Should -BeNullOrEmpty;
            ConvertTo-IcingaUnit -InputValue ''   | Should -BeNullOrEmpty;
            ConvertTo-IcingaUnit -InputValue '   '| Should -BeNullOrEmpty;
        }

        It 'Rejects a value without any unit' {
            ConvertTo-IcingaUnit -InputValue '1000' | Should -BeNullOrEmpty;
        }

        It 'Rejects an unknown unit' {
            ConvertTo-IcingaUnit -InputValue '1000Foo' | Should -BeNullOrEmpty;
        }

        It 'Rejects a target unit from a different family' {
            ConvertTo-IcingaUnit -InputValue '10' -InputUnit 's' -TargetUnit 'GiB' | Should -BeNullOrEmpty;
        }
    }
}

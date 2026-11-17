<#
.SYNOPSIS
Pester unit test suite for IcingaThresholds in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for IcingaThresholds
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

Describe 'IcingaThresholds' {
    BeforeAll {
        # IcingaThresholds is defined in the dot-sourced kernel inside the module's
        # script module, so the type is not visible to the test scope. Grab that
        # module and construct instances in its scope; the returned instances can
        # then be used directly (method and property access need no type binding).
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        function script:New-Threshold()
        {
            param (
                [string]$Warning,
                [string]$Critical,
                [string]$BaseValue
            );

            if ($PSBoundParameters.ContainsKey('BaseValue')) {
                return (& $script:IcingaModule { param($w, $c, $b) [IcingaThresholds]::new($w, $c, $b) } $Warning $Critical $BaseValue);
            }

            return (& $script:IcingaModule { param($w, $c) [IcingaThresholds]::new($w, $c) } $Warning $Critical);
        }
    }

    Context 'Round-trips the threshold strings 1:1' {
        It 'Preserves warning and critical verbatim' {
            $t = New-Threshold '10:20' '~:5';
            $t.Warning  | Should -Be '10:20';
            $t.Critical | Should -Be '~:5';
        }

        It 'Preserves the inverted, percent and pattern notation verbatim' {
            (New-Threshold '@10:20' '').Warning      | Should -Be '@10:20';
            (New-Threshold '90%' '' '1000').Warning  | Should -Be '90%';
            (New-Threshold '^warn' '^err').Critical  | Should -Be '^err';
        }
    }

    Context 'CheckRange (Icinga range grammar)' {
        It 'Treats a single value as 0 .. X' {
            $t = New-Threshold '10' '';
            $t.CheckRange(5).StatusCode  | Should -Be 0;
            $t.CheckRange(15).StatusCode | Should -Be 1;
        }

        It 'Combines warning and critical with critical taking precedence' {
            $t = New-Threshold '10:20' '5:30';
            $t.CheckRange(15).StatusCode | Should -Be 0;
            $t.CheckRange(8).StatusCode  | Should -Be 1;
            $t.CheckRange(3).StatusCode  | Should -Be 2;
        }

        It 'Returns OK and an output message when no threshold is set' {
            $r = (New-Threshold '' '').CheckRange(999);
            $r.StatusCode | Should -Be 0;
            $r.Output     | Should -Not -BeNullOrEmpty;
        }

        It 'Handles greater-guard, less-guard and inverted ranges' {
            (New-Threshold '10:' '').CheckRange(5).StatusCode     | Should -Be 1;
            (New-Threshold '~:10' '').CheckRange(11).StatusCode   | Should -Be 1;
            (New-Threshold '@10:20' '').CheckRange(15).StatusCode | Should -Be 1;
            (New-Threshold '@10:20' '').CheckRange(25).StatusCode | Should -Be 0;
        }

        It 'Normalizes unit values and range bounds' {
            $t = New-Threshold '100MB' '200MB';
            $t.CheckRange('50MB').StatusCode  | Should -Be 0;
            $t.CheckRange('150MB').StatusCode | Should -Be 1;
            $t.CheckRange('250MB').StatusCode | Should -Be 2;
        }

        It 'Resolves percent range bounds against the base value' {
            $t = New-Threshold '80%' '90%' '1000';
            $t.CheckRange(700).StatusCode | Should -Be 0;
            $t.CheckRange(850).StatusCode | Should -Be 1;
            $t.CheckRange(950).StatusCode | Should -Be 2;
        }
    }

    Context 'Numeric comparisons' {
        It 'CheckGreater alerts above the thresholds and fills the result fields' {
            $t = New-Threshold '80' '90';
            $t.CheckGreater(50).StatusCode | Should -Be 0;
            $t.CheckGreater(85).StatusCode | Should -Be 1;

            $r = $t.CheckGreater(95);
            $r.StatusCode    | Should -Be 2;
            $r.InputValue    | Should -Be 95;
            $r.WarningValue  | Should -Be 80;
            $r.CriticalValue | Should -Be 90;
            $r.Output        | Should -Match 'greater than';
        }

        It 'CheckGreaterEqual differs from CheckGreater at the boundary' {
            (New-Threshold '80' '90').CheckGreater(90).StatusCode      | Should -Be 1;
            (New-Threshold '80' '90').CheckGreaterEqual(90).StatusCode | Should -Be 2;
        }

        It 'CheckLower and CheckLowerEqual alert below the thresholds' {
            $t = New-Threshold '20' '10';
            $t.CheckLower(25).StatusCode      | Should -Be 0;
            $t.CheckLower(15).StatusCode      | Should -Be 1;
            $t.CheckLower(5).StatusCode       | Should -Be 2;
            $t.CheckLowerEqual(10).StatusCode | Should -Be 2;
        }

        It 'Skips an unset threshold' {
            $t = New-Threshold '' '90';
            $t.CheckGreater(50).StatusCode | Should -Be 0;
            $t.CheckGreater(95).StatusCode | Should -Be 2;
            (New-Threshold '' '').CheckGreater(999).StatusCode | Should -Be 0;
        }
    }

    Context 'Units and percent in numeric comparisons' {
        It 'Normalizes unit strings on values and thresholds' {
            $r = (New-Threshold '10GB' '20GB').CheckGreater('15GB');
            $r.StatusCode   | Should -Be 1;
            $r.InputValue   | Should -Be '15000000000B'; # input carries the base unit
            $r.WarningValue | Should -Be 10000000000;    # threshold resolved, no unit
        }

        It 'Resolves percent thresholds against the base value' {
            $t = New-Threshold '80%' '90%' '1000';
            $t.CheckGreaterEqual(850).StatusCode | Should -Be 1;
            $t.CheckGreaterEqual(950).StatusCode | Should -Be 2;
        }

        It 'Exposes the resolved base as Maximum' {
            (New-Threshold '80%' '90%' '1TB').Maximum | Should -Be 1000000000000;
        }
    }

    Context 'CheckMax comparison' {
        It 'Alerts at or above the max-relative thresholds' {
            $t = New-Threshold '80%' '90%' '1000';
            $t.CheckMax(500).StatusCode | Should -Be 0;
            $t.CheckMax(850).StatusCode | Should -Be 1;
            $t.CheckMax(950).StatusCode | Should -Be 2;
        }

        It 'Returns UNKNOWN when no base value is set' {
            $r = (New-Threshold '80%' '90%').CheckMax(950);
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Match 'base value';
        }

        It 'Accepts a unit-string value against a unit-string base' {
            $t = New-Threshold '80%' '90%' '1TB';
            $t.CheckMax('500GB').StatusCode | Should -Be 0;
            $t.CheckMax('850GB').StatusCode | Should -Be 1;
            $t.CheckMax('950GB').StatusCode | Should -Be 2;
        }
    }

    Context 'String comparisons (regex and wildcard)' {
        It 'CheckMatch uses regular expressions with critical precedence' {
            $t = New-Threshold '^warn' '^err';
            $t.CheckMatch('all clear').StatusCode | Should -Be 0;
            $t.CheckMatch('warning').StatusCode   | Should -Be 1;
            $t.CheckMatch('error now').StatusCode | Should -Be 2;
        }

        It 'CheckNotMatch alerts when the pattern does not match' {
            $t = New-Threshold '' '^healthy';
            $t.CheckNotMatch('degraded').StatusCode     | Should -Be 2;
            $t.CheckNotMatch('healthy node').StatusCode | Should -Be 0;
        }

        It 'CheckLike and CheckNotLike use wildcard patterns' {
            $t = New-Threshold '*warn*' '*error*';
            $t.CheckLike('all good').StatusCode    | Should -Be 0;
            $t.CheckLike('a warning').StatusCode   | Should -Be 1;
            $t.CheckLike('fatal error').StatusCode | Should -Be 2;

            $n = New-Threshold '' '*ok*';
            $n.CheckNotLike('failure').StatusCode | Should -Be 2;
            $n.CheckNotLike('all ok').StatusCode  | Should -Be 0;
        }

        It 'Reports UNKNOWN for an invalid regular expression' {
            $r = (New-Threshold '' '[').CheckMatch('x');
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Match 'pattern';
        }

        It 'Names the invalid regex threshold in a clean UNKNOWN message (no raw parser text)' {
            # A wildcard-looking pattern is an invalid regex ('*' quantifies nothing).
            $both = (New-Threshold '*or*' '*ha*').CheckMatch('foo');
            $both.StatusCode | Should -Be 3;
            $both.Output     | Should -Be "The critical pattern '*ha*' is not a valid regular expression";

            # Critical is valid, so the invalid warning is the one reported.
            $warn = (New-Threshold '*or*' 'ok').CheckMatch('foo');
            $warn.StatusCode | Should -Be 3;
            $warn.Output     | Should -Be "The warning pattern '*or*' is not a valid regular expression";

            # CheckNotMatch validates its patterns the same way.
            (New-Threshold '' '*ha*').CheckNotMatch('foo').Output | Should -Be "The critical pattern '*ha*' is not a valid regular expression";
        }

        It 'Returns UNKNOWN for a null value across the string operators' {
            (New-Threshold '^a' '^b').CheckNotMatch($null).StatusCode | Should -Be 3;
            (New-Threshold '*a*' '*b*').CheckLike($null).StatusCode     | Should -Be 3;
            (New-Threshold '*a*' '*b*').CheckNotLike($null).StatusCode  | Should -Be 3;
        }
    }

    Context 'String equality (CheckEqual / CheckNotEqual)' {
        It 'CheckEqual matches an exact string with critical precedence' {
            $t = New-Threshold 'foo' 'bar';
            $t.CheckEqual('baz').StatusCode | Should -Be 0;
            $t.CheckEqual('foo').StatusCode | Should -Be 1;
            $t.CheckEqual('bar').StatusCode | Should -Be 2;
        }

        It 'CheckEqual compares case-insensitively and literally (not as a pattern)' {
            (New-Threshold '' 'FOO').CheckEqual('foo').StatusCode  | Should -Be 2;
            (New-Threshold '' 'f.o').CheckEqual('foo').StatusCode  | Should -Be 0;
        }

        It 'CheckNotEqual alerts when the value differs from the critical threshold' {
            $t = New-Threshold '' 'online';
            $t.CheckNotEqual('online').StatusCode  | Should -Be 0;
            $t.CheckNotEqual('offline').StatusCode | Should -Be 2;
        }

        It 'CheckNotEqual honors the warning threshold' {
            $t = New-Threshold 'expected' '';
            $t.CheckNotEqual('expected').StatusCode | Should -Be 0;
            $t.CheckNotEqual('surprise').StatusCode | Should -Be 1;
        }

        It 'Returns UNKNOWN for a null value' {
            (New-Threshold 'foo' 'bar').CheckEqual($null).StatusCode    | Should -Be 3;
            (New-Threshold 'foo' 'bar').CheckNotEqual($null).StatusCode | Should -Be 3;
        }

        It 'Describes the equality comparison in the Output' {
            (New-Threshold '' 'crit').CheckEqual('crit').Output     | Should -Match "equals pattern 'crit'";
            (New-Threshold '' 'crit').CheckNotEqual('other').Output | Should -Match "does not equal pattern 'crit'";
        }
    }

    Context 'UNKNOWN / error paths surface a friendly Output (never throw)' {
        It 'Reports an invalid range' {
            $r = (New-Threshold '10:xx' '').CheckRange(5);
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Not -BeNullOrEmpty;
        }

        It 'Reports a lower bound greater than the upper bound' {
            (New-Threshold '20:10' '').CheckRange(5).StatusCode | Should -Be 3;
        }

        It 'Reports an invalid base value' {
            $r = (New-Threshold '90%' '' 'abc').CheckGreater(5);
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Match 'base value';
        }

        It 'Reports a percent threshold used without a base value' {
            $r = (New-Threshold '90%' '').CheckGreater(5);
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Match 'base value';
        }

        It 'Reports an unresolvable or null measured value' {
            (New-Threshold '10' '20').CheckGreater('abc').StatusCode  | Should -Be 3;
            (New-Threshold '10' '20').CheckGreater($null).StatusCode  | Should -Be 3;
            (New-Threshold '^a' '^b').CheckMatch($null).StatusCode  | Should -Be 3;
        }
    }

    Context 'CheckRange output is direction-aware' {
        It 'Names the crossed bound and the direction' {
            (New-Threshold '20:' '').CheckRange(19).Output   | Should -Be '19 is lower than threshold 20';
            (New-Threshold '~:20' '').CheckRange(25).Output  | Should -Be '25 is greater than threshold 20';
            (New-Threshold '10:20' '').CheckRange(5).Output  | Should -Be '5 is lower than threshold 10';
            (New-Threshold '10:20' '').CheckRange(25).Output | Should -Be '25 is greater than threshold 20';
        }

        It 'Describes an inverted range as within' {
            (New-Threshold '@10:20' '').CheckRange(15).Output | Should -Be '15 is within range 10 to 20';
        }
    }

    Context 'Rejects an unreachable warning or OK state (contradictory thresholds)' {
        It 'CheckRange: warning subsumed by critical -> UNKNOWN [WARNING] with translated message' {
            $r = (New-Threshold '10:' '15:').CheckRange(19);
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Be "Check can never reach [WARNING]-State if warning is '< 10' and critical is '< 15'";
        }

        It 'CheckRange: no value can be OK -> UNKNOWN [OK] with translated message' {
            $r = (New-Threshold '~:10' '20:').CheckRange(50);
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Be "Check can never reach [OK]-State if warning is '> 10' and critical is '< 20'";

            (New-Threshold '10' '30:').CheckRange(50).StatusCode | Should -Be 3;
            (New-Threshold '10' '30:').CheckRange(20).StatusCode | Should -Be 3;
        }

        It 'CheckRange: sound orderings still evaluate' {
            (New-Threshold '10:' '5:').CheckRange(7).StatusCode     | Should -Be 1;
            (New-Threshold '10:' '5:').CheckRange(19).StatusCode    | Should -Be 0;
            (New-Threshold '~:10' '~:20').CheckRange(15).StatusCode | Should -Be 1;
        }

        It 'CheckRange: detects masking for inverted and open-ended ranges' {
            (New-Threshold '@10:20' '@5:30').CheckRange(15).StatusCode | Should -Be 3;
            (New-Threshold '~:20' '~:10').CheckRange(50).StatusCode    | Should -Be 3;
        }

        It 'Numeric: unreachable warning is UNKNOWN with translated message' {
            $r = (New-Threshold '90' '80').CheckGreater(200);
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Be "Check can never reach [WARNING]-State if warning is '> 90' and critical is '> 80'";

            (New-Threshold '10' '20').CheckLower(1).StatusCode          | Should -Be 3;
            (New-Threshold '90%' '80%' '1000').CheckMax(999).StatusCode | Should -Be 3;
        }

        It 'Numeric: sound orderings still evaluate' {
            (New-Threshold '80' '90').CheckGreater(85).StatusCode | Should -Be 1;
            (New-Threshold '20' '10').CheckLower(15).StatusCode   | Should -Be 1;
        }

        It 'String wildcards: warning subsumed by critical -> UNKNOWN [WARNING] with message' {
            $r = (New-Threshold '*fo*' '*f*').CheckLike('foo');
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Be "Check can never reach [WARNING]-State if warning is 'is like *fo*' and critical is 'is like *f*'";
        }

        It 'String wildcards: NotLike masks in the opposite direction' {
            (New-Threshold '*f*' '*fo*').CheckNotLike('zzz').StatusCode | Should -Be 3;
        }

        It 'String regex: warning subsumed by critical -> UNKNOWN [WARNING] with message' {
            $r = (New-Threshold 'fo' 'f').CheckMatch('foo');
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Be "Check can never reach [WARNING]-State if warning is 'matches fo' and critical is 'matches f'";
        }

        It 'String regex: NotMatch masks in the opposite direction' {
            (New-Threshold 'f' 'fo').CheckNotMatch('x').StatusCode | Should -Be 3;
        }

        It 'Identical patterns always mask (equality and regex, case-insensitive)' {
            (New-Threshold 'foo' 'foo').CheckEqual('foo').StatusCode     | Should -Be 3;
            (New-Threshold 'FOO' 'foo').CheckEqual('foo').StatusCode     | Should -Be 3;
            (New-Threshold '^err' '^err').CheckMatch('error').StatusCode | Should -Be 3;
        }

        It 'String comparisons: sound patterns still evaluate' {
            (New-Threshold '.*' 'error').CheckMatch('error').StatusCode          | Should -Be 2;
            (New-Threshold '*f*' '*fo*').CheckLike('foo').StatusCode             | Should -Be 2;
            (New-Threshold '*warn*' '*error*').CheckLike('a warning').StatusCode | Should -Be 1;
            (New-Threshold 'foo' 'bar').CheckEqual('foo').StatusCode             | Should -Be 1;

            # Regex literal masking is direction-aware and declines when a metacharacter
            # makes the pattern more than a plain literal, so a sound pair still evaluates.
            (New-Threshold 'f' 'fo').CheckMatch('foo').StatusCode      | Should -Be 2;
            (New-Threshold 'err' 'crit').CheckMatch('error').StatusCode | Should -Be 1;
            (New-Threshold 'f.o' 'f').CheckMatch('foo').StatusCode     | Should -Be 2;
        }

        It 'String masking never fires when a threshold is unset' {
            (New-Threshold '*f*' '').CheckLike('foo').StatusCode | Should -Be 1;
            (New-Threshold '' '*f*').CheckLike('foo').StatusCode | Should -Be 2;
        }
    }

    Context 'ToAlertString translates a range to its alert condition' {
        It 'Renders each range form' {
            (& $script:IcingaModule { [IcingaThresholdRange]::new('10:', 0, $false).ToAlertString() })    | Should -Be '< 10';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('~:10', 0, $false).ToAlertString() })   | Should -Be '> 10';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('10:20', 0, $false).ToAlertString() })  | Should -Be '< 10 or > 20';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('@10:20', 0, $false).ToAlertString() }) | Should -Be '>= 10 and <= 20';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('10', 0, $false).ToAlertString() })     | Should -Be '< 0 or > 10';
        }
    }

    Context 'ToBaseThresholdString resolves bounds to numbers (no units)' {
        It 'Renders each range form' {
            (& $script:IcingaModule { [IcingaThresholdRange]::new('10MB', 0, $false).ToBaseThresholdString() })       | Should -Be '10000000';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('15MB:', 0, $false).ToBaseThresholdString() })      | Should -Be '15000000:';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('@10MB:20MB', 0, $false).ToBaseThresholdString() }) | Should -Be '@10000000:20000000';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('~:10MB', 0, $false).ToBaseThresholdString() })     | Should -Be '~:10000000';
            (& $script:IcingaModule { [IcingaThresholdRange]::new('90%', 1000, $true).ToBaseThresholdString() })      | Should -Be '900';
        }
    }

    Context 'Result fields: InputValue carries the base unit, thresholds are resolved (no unit)' {
        It 'CheckRange fields on a sound pair' {
            $r = (New-Threshold '100MB' '200MB').CheckRange('150MB');
            $r.StatusCode    | Should -Be 1;
            $r.InputValue    | Should -Be '150000000B';
            $r.WarningValue  | Should -Be '100000000';
            $r.CriticalValue | Should -Be '200000000';
        }

        It 'Input carries the base unit and resolved thresholds; the [OK]-State is unreachable' {
            $r = (New-Threshold '10MB' '15MB:').CheckRange('19MB');
            $r.StatusCode    | Should -Be 3;
            $r.InputValue    | Should -Be '19000000B';
            $r.WarningValue  | Should -Be '10000000';
            $r.CriticalValue | Should -Be '15000000:';
            $r.Output        | Should -Be "Check can never reach [OK]-State if warning is '< 0 or > 10MB' and critical is '< 15MB'";
        }

        It 'Time example: input carries the base unit, best-unit output' {
            $r = (New-Threshold '86400s' '92000s').CheckRange('6h');
            $r.StatusCode    | Should -Be 0;
            $r.InputValue    | Should -Be '21600s';
            $r.WarningValue  | Should -Be 86400;
            $r.CriticalValue | Should -Be 92000;
            $r.Output        | Should -Be '6h is ok';
        }

        It 'Numeric percent thresholds resolve against the base' {
            $r = (New-Threshold '80%' '90%' '1000').CheckGreaterEqual(950);
            $r.StatusCode    | Should -Be 2;
            $r.InputValue    | Should -Be 950;
            $r.WarningValue  | Should -Be 800;
            $r.CriticalValue | Should -Be 900;
        }
    }

    Context 'Data-family result fields render as whole bytes' {
        It 'Fractional GiB and percent yield integer byte fields' {
            $r = (New-Threshold '20%' '30%' '254.55GiB').CheckRange('38.64GiB');
            $r.StatusCode    | Should -Be 0;
            $r.InputValue    | Should -Be '41489384079B';
            $r.WarningValue  | Should -Be 54664196260;
            $r.CriticalValue | Should -Be 81996294390;
            $r.BaseValue     | Should -Be 273320981299;
            $r.Output        | Should -Be '38.64GiB (15.18%) is ok';
        }

        It 'Rounds an absolute fractional-GiB range bound to whole bytes' {
            (New-Threshold '254.55GiB:' '').CheckRange('100GiB').WarningValue | Should -Be '273320981299:';
        }

        It 'Byte fields of the numeric comparisons are whole bytes too' {
            $r = (New-Threshold '10%' '20%' '254.55GiB').CheckGreater('50GiB');
            $r.WarningValue  | Should -Be 27332098130;
            $r.CriticalValue | Should -Be 54664196260;
        }

        It 'Keeps sub-second Time values fractional (only bytes are indivisible)' {
            $r = (New-Threshold '1.5s' '2.5s').CheckRange('2s');
            $r.InputValue    | Should -Be '2s';
            $r.WarningValue  | Should -Be 1.5;
            $r.CriticalValue | Should -Be 2.5;
        }

        It 'Rounds byte bounds in the unreachable-state message, but not Time' {
            $b = (New-Threshold '30%' '20%' '254.55GiB').CheckRange('38.64GiB');
            $b.StatusCode | Should -Be 3;
            $b.Output     | Should -Be "Check can never reach [WARNING]-State if warning is '< 0 or > 81996294390' and critical is '< 0 or > 54664196260'";

            $t = (New-Threshold '2.5s' '1.5s').CheckRange('2s');
            $t.StatusCode | Should -Be 3;
            $t.Output     | Should -Be "Check can never reach [WARNING]-State if warning is '< 0 or > 2.5s' and critical is '< 0 or > 1.5s'";
        }
    }

    Context 'Output messages are descriptive' {
        It 'Describes the numeric comparison and the triggering threshold' {
            (New-Threshold '20' '10').CheckLower(5).Output    | Should -Be '5 is lower than threshold 10';
            (New-Threshold '80' '90').CheckGreater(85).Output | Should -Be '85 is greater than threshold 80';
        }

        It 'Describes the pattern comparison and the triggering pattern' {
            (New-Threshold '^warn' '^err').CheckMatch('error now').Output | Should -Match "matches pattern '\^err'";
            (New-Threshold '' '*ok*').CheckNotLike('failure').Output        | Should -Match "is not like pattern '\*ok\*'";
        }
    }

    Context 'Percent thresholds show the number and the percent in the Output' {
        It 'Percent example: value and threshold carry both number and percent' {
            $c = (New-Threshold '10%' '20%' '200').CheckRange('100');
            $c.StatusCode    | Should -Be 2;
            $c.InputValue    | Should -Be '100';   # fields unchanged
            $c.WarningValue  | Should -Be '20';
            $c.CriticalValue | Should -Be '40';
            $c.Output        | Should -Be '100 (50%) is greater than threshold 40 (20%)';
        }

        It 'Shows the value percent in the OK message too' {
            (New-Threshold '10%' '20%' '200').CheckRange('15').Output | Should -Be '15 (7.5%) is ok';
        }

        It 'Names the crossed percent bound with its token (lower/greater)' {
            (New-Threshold '10%' '20%' '200').CheckRange('30').Output  | Should -Be '30 (15%) is greater than threshold 20 (10%)';
            (New-Threshold '10%:' '' '200').CheckRange('10').Output    | Should -Be '10 (5%) is lower than threshold 20 (10%)';
        }

        It 'Applies to the numeric comparison methods (CheckMax)' {
            $r = (New-Threshold '80%' '90%' '1000').CheckMax('950');
            $r.StatusCode | Should -Be 2;
            $r.Output     | Should -Be '950 (95%) is greater than or equal to threshold 900 (90%)';
            (New-Threshold '80%' '90%' '1000').CheckMax(500).Output | Should -Be '500 (50%) is ok';
        }

        It 'Absolute thresholds are unaffected (no percent in the Output)' {
            (New-Threshold '80' '90').CheckGreater(85).Output              | Should -Be '85 is greater than threshold 80';
            (New-Threshold '100MB' '200MB').CheckRange('150MB').Output | Should -Be '150MB is greater than threshold 100MB';
        }
    }

    Context 'BaseValue result field mirrors the base value' {
        It 'Exposes the resolved base as BaseValue when a base value is set' {
            $r = (New-Threshold '10%' '20%' '200').CheckRange('100');
            $r.BaseValue     | Should -Be 200;
            $r.WarningValue  | Should -Be 20;
            $r.CriticalValue | Should -Be 40;
        }

        It 'Carries the base without a unit for a unit-string base' {
            (New-Threshold '80%' '90%' '1TB').CheckMax('950GB').BaseValue | Should -Be 1000000000000;
        }

        It 'Leaves BaseValue null when no base value is set' {
            (New-Threshold '80' '90').CheckGreater(85).BaseValue               | Should -BeNullOrEmpty;
            (New-Threshold '100MB' '200MB').CheckRange('150MB').BaseValue | Should -BeNullOrEmpty;
        }

        It 'Leaves BaseValue null when the base value is invalid' {
            (New-Threshold '90%' '' 'abc').CheckGreater(5).BaseValue | Should -BeNullOrEmpty;
        }
    }

    Context 'A value greater than the BaseValue is rejected as UNKNOWN' {
        It 'CheckRange: value above the base value is UNKNOWN (plain base)' {
            $r = (New-Threshold '10%' '20%' '200').CheckRange('10GB');
            $r.StatusCode | Should -Be 3;
            $r.InputValue | Should -Be '10000000000B';
            $r.BaseValue  | Should -Be 200;
            $r.Output     | Should -Be "The value '10GB' (10000000000B) cannot be greater than the BaseValue 200";
        }

        It 'Formats the base value in its own unit with its base-unit form in parentheses' {
            (New-Threshold '10%' '20%' '100GB').CheckRange('1000GB').Output |
                Should -Be "The value '1000GB' (1000000000000B) cannot be greater than the BaseValue 100GB (100000000000B)";
        }

        It 'Renders both value and base value with unit and resolved form (MB/MB)' {
            (New-Threshold '10%' '20%' '999MB').CheckRange('1000MB').Output |
                Should -Be "The value '1000MB' (1000000000B) cannot be greater than the BaseValue 999MB (999000000B)";
        }

        It 'Omits the parenthetical when the value carries no unit' {
            (New-Threshold '10%' '20%' '999B').CheckRange('1000').Output |
                Should -Be "The value '1000' cannot be greater than the BaseValue 999B";
        }

        It 'Applies regardless of the threshold kind (absolute thresholds too)' {
            $r = (New-Threshold '10B' '20MB' '999B').CheckRange('1000');
            $r.StatusCode | Should -Be 3;
            $r.Output     | Should -Be "The value '1000' cannot be greater than the BaseValue 999B";
        }

        It 'Numeric comparisons reject a value above the base value' {
            (New-Threshold '80%' '90%' '1000').CheckMax(2000).StatusCode | Should -Be 3;
        }

        It 'A value equal to the base value (100%) is still allowed' {
            (New-Threshold '10%' '20%' '200').CheckRange('200').StatusCode | Should -Be 2;
        }

        It 'A value below the base value still evaluates normally' {
            (New-Threshold '10B' '20MB' '999B').CheckRange('500').StatusCode | Should -Be 1;
        }

        It 'Without a base value there is no upper-bound guard' {
            (New-Threshold '100MB' '200MB').CheckRange('10GB').StatusCode | Should -Be 2;
        }
    }

    Context 'Performance' {
        # Budgets are per-iteration and generous to absorb CI variance while still
        # catching a gross regression. Construction runs in the module scope (where
        # the type resolves); evaluation runs on a prebuilt instance in test scope.
        It 'Constructs a threshold pair within a reasonable time budget' {
            $Iterations = 5000;
            $Elapsed    = Measure-Command {
                & $script:IcingaModule {
                    param($Count)
                    for ($i = 0; $i -lt $Count; $i++) {
                        [void][IcingaThresholds]::new('10:20', '5:30');
                    }
                } $Iterations;
            };

            ($Elapsed.TotalMilliseconds / $Iterations) | Should -BeLessThan 2;
        }

        It 'Evaluates values on a prebuilt threshold within a reasonable time budget' {
            # Each call re-resolves both thresholds and allocates a result object;
            # the budget is generous for CI variance and only guards gross regressions.
            $Thresholds = New-Threshold '80' '90';
            $Iterations = 5000;
            $Elapsed    = Measure-Command {
                for ($i = 0; $i -lt $Iterations; $i++) {
                    [void]$Thresholds.CheckGreater($i);
                }
            };

            ($Elapsed.TotalMilliseconds / $Iterations) | Should -BeLessThan 5;
        }
    }
}

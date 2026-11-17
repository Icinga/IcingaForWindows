<#
.SYNOPSIS
Pester unit test suite for ConvertFrom-ModuleBoolean in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for ConvertFrom-ModuleBoolean
as part of the Icinga for Windows automated Pester test suite.

.NOTES
Executed via build/Invoke-ModuleTests.ps1 using Pester 5.0+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
$ModulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'ConvertFrom-ModuleBoolean' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        function Invoke-TestBoolConversion()
        {
            param (
                [object]$InputValue = $null
            );

            return (& $script:IcingaModule {
                param ($Val);
                return (ConvertFrom-ModuleBoolean -Value $Val);
            } $InputValue);
        }
    }

    Context 'Native booleans, switches and null' {
        It 'preserves native booleans and evaluates $null to $false' {
            (Invoke-TestBoolConversion -InputValue $true)  | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue $false) | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue $null)  | Should -BeFalse;
        }

        It 'converts SwitchParameter values accurately' {
            [switch]$PresentSwitch = $true;
            [switch]$AbsentSwitch  = $false;

            (Invoke-TestBoolConversion -InputValue $PresentSwitch) | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue $AbsentSwitch)  | Should -BeFalse;
        }
    }

    Context 'Numeric and string representations' {
        It 'maps numeric 1 and truthy strings case-insensitively to $true' {
            (Invoke-TestBoolConversion -InputValue 1)        | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue 1.0)      | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue 'true')   | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue 'TRUE')   | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue '1')      | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue 'yes')    | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue 'YES')    | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue '$true')  | Should -BeTrue;
        }

        It 'maps numeric 0, empty strings and falsy strings to $false without PowerShell string-truthiness bugs' {
            (Invoke-TestBoolConversion -InputValue 0)        | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue 0.0)      | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue 'false')  | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue 'False')  | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue '0')      | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue 'no')     | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue '$false') | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue '')       | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue '   ')    | Should -BeFalse;
        }

        It 'returns $false and logs StringToBoolConversionInvalidValue on unrecognized values' {
            (Invoke-TestBoolConversion -InputValue 'not-a-bool') | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue 42)           | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue -1)           | Should -BeFalse;
            (Invoke-TestBoolConversion -InputValue ([byte]1))    | Should -BeTrue;
            (Invoke-TestBoolConversion -InputValue ([int64]0))   | Should -BeFalse;
        }
    }
}

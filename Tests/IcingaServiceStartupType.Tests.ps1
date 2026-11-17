<#
.SYNOPSIS
Pester unit test suite for IcingaServiceStartupType in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for IcingaServiceStartupType
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

Describe 'IcingaServiceStartupType' {
    BeforeAll {
        # The data types live in the dot-sourced kernel and are only visible inside
        # the script module scope.
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    Context 'Enum values' {
        It 'keeps the ServiceStartMode codes' {
            $Codes = & $script:IcingaModule {
                return @(
                    [int][IcingaServiceStartupType]::Boot,
                    [int][IcingaServiceStartupType]::System,
                    [int][IcingaServiceStartupType]::Automatic,
                    [int][IcingaServiceStartupType]::Manual,
                    [int][IcingaServiceStartupType]::Disabled,
                    [int][IcingaServiceStartupType]::Unknown
                );
            };
            $Codes | Should -Be @(0, 1, 2, 3, 4, 5);
        }

        It 'converts an array of names as a parameter type' {
            $Converted = & $script:IcingaModule {
                function Test-IcingaServiceStartupTypeParameter()
                {
                    param (
                        [IcingaServiceStartupType[]]$StartupType = @()
                    );

                    return ($StartupType -join ',');
                }

                return (Test-IcingaServiceStartupTypeParameter -StartupType 'automatic', 'Disabled');
            };
            $Converted | Should -Be 'Automatic,Disabled';
        }
    }

    Context 'IcingaServiceStartupTypeMap' {
        It 'resolves the Win32_Service start modes' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaServiceStartupTypeMap]::Resolve('Boot'),
                    [string][IcingaServiceStartupTypeMap]::Resolve('System'),
                    [string][IcingaServiceStartupTypeMap]::Resolve('Auto'),
                    [string][IcingaServiceStartupTypeMap]::Resolve('Manual'),
                    [string][IcingaServiceStartupTypeMap]::Resolve('Disabled')
                );
            };
            $Resolved | Should -Be @('Boot', 'System', 'Automatic', 'Manual', 'Disabled');
        }

        It 'resolves names in any casing and numeric codes' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaServiceStartupTypeMap]::Resolve('automatic'),
                    [string][IcingaServiceStartupTypeMap]::Resolve(3)
                );
            };
            $Resolved | Should -Be @('Automatic', 'Manual');
        }

        It 'resolves unmappable values to Unknown' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaServiceStartupTypeMap]::Resolve($null),
                    [string][IcingaServiceStartupTypeMap]::Resolve(''),
                    [string][IcingaServiceStartupTypeMap]::Resolve('Delayed'),
                    [string][IcingaServiceStartupTypeMap]::Resolve(42)
                );
            };
            $Resolved | Should -Be @('Unknown', 'Unknown', 'Unknown', 'Unknown');
        }
    }
}

<#
.SYNOPSIS
Pester unit test suite for IcingaScheduledTaskStatus in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for IcingaScheduledTaskStatus
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

Describe 'IcingaScheduledTaskStatus' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    Context 'Enum values' {
        It 'keeps the Task Scheduler state codes used by the state perfdata' {
            $Codes = & $script:IcingaModule {
                return @(
                    [int][IcingaScheduledTaskStatus]::Unknown,
                    [int][IcingaScheduledTaskStatus]::Disabled,
                    [int][IcingaScheduledTaskStatus]::Queued,
                    [int][IcingaScheduledTaskStatus]::Ready,
                    [int][IcingaScheduledTaskStatus]::Running
                );
            };
            $Codes | Should -Be @(0, 1, 2, 3, 4);
        }

        It 'converts names in any casing and codes as a parameter type' {
            $Converted = & $script:IcingaModule {
                function Test-IcingaScheduledTaskStatusParameter()
                {
                    param (
                        [IcingaScheduledTaskStatus]$State = 'Ready'
                    );

                    return [string]$State;
                }

                return @(
                    (Test-IcingaScheduledTaskStatusParameter),
                    (Test-IcingaScheduledTaskStatusParameter -State 'disabled'),
                    (Test-IcingaScheduledTaskStatusParameter -State 4)
                );
            };
            $Converted | Should -Be @('Ready', 'Disabled', 'Running');
        }

        It 'rejects an unknown name as a parameter value' {
            {
                & $script:IcingaModule {
                    function Test-IcingaScheduledTaskStatusParameter()
                    {
                        param (
                            [IcingaScheduledTaskStatus]$State = 'Ready'
                        );

                        return $State;
                    }

                    Test-IcingaScheduledTaskStatusParameter -State 'Sleeping';
                };
            } | Should -Throw;
        }
    }

    Context 'IcingaScheduledTaskStatusMap' {
        It 'resolves names in any casing and numeric codes' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaScheduledTaskStatusMap]::Resolve('Ready'),
                    [string][IcingaScheduledTaskStatusMap]::Resolve('running'),
                    [string][IcingaScheduledTaskStatusMap]::Resolve(1),
                    [string][IcingaScheduledTaskStatusMap]::Resolve('2')
                );
            };
            $Resolved | Should -Be @('Ready', 'Running', 'Disabled', 'Queued');
        }

        It 'resolves unmappable values to Unknown' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaScheduledTaskStatusMap]::Resolve($null),
                    [string][IcingaScheduledTaskStatusMap]::Resolve(''),
                    [string][IcingaScheduledTaskStatusMap]::Resolve('InvalidState'),
                    [string][IcingaScheduledTaskStatusMap]::Resolve(99)
                );
            };
            $Resolved | Should -Be @('Unknown', 'Unknown', 'Unknown', 'Unknown');
        }
    }
}

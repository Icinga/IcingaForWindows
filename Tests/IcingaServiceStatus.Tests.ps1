$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'IcingaServiceStatus' {
    BeforeAll {
        # The data types live in the dot-sourced kernel and are only visible inside
        # the script module scope.
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    Context 'Enum values' {
        It 'keeps the ServiceControllerStatus codes used by the state perfdata' {
            $Codes = & $script:IcingaModule {
                return @(
                    [int][IcingaServiceStatus]::Unknown,
                    [int][IcingaServiceStatus]::Stopped,
                    [int][IcingaServiceStatus]::StartPending,
                    [int][IcingaServiceStatus]::StopPending,
                    [int][IcingaServiceStatus]::Running,
                    [int][IcingaServiceStatus]::ContinuePending,
                    [int][IcingaServiceStatus]::PausePending,
                    [int][IcingaServiceStatus]::Paused
                );
            };
            $Codes | Should -Be @(0, 1, 2, 3, 4, 5, 6, 7);
        }

        It 'converts names in any casing and codes as a parameter type' {
            $Converted = & $script:IcingaModule {
                function Test-IcingaServiceStatusParameter()
                {
                    param (
                        [IcingaServiceStatus]$Status = 'Running'
                    );

                    return [string]$Status;
                }

                return @(
                    (Test-IcingaServiceStatusParameter),
                    (Test-IcingaServiceStatusParameter -Status 'stoppending'),
                    (Test-IcingaServiceStatusParameter -Status 7)
                );
            };
            $Converted | Should -Be @('Running', 'StopPending', 'Paused');
        }

        It 'rejects an unknown name as a parameter value' {
            {
                & $script:IcingaModule {
                    function Test-IcingaServiceStatusParameter()
                    {
                        param (
                            [IcingaServiceStatus]$Status = 'Running'
                        );

                        return $Status;
                    }

                    Test-IcingaServiceStatusParameter -Status 'Sleeping';
                };
            } | Should -Throw;
        }
    }

    Context 'IcingaServiceStatusMap' {
        It 'resolves Win32_Service states with blanks' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaServiceStatusMap]::Resolve('Running'),
                    [string][IcingaServiceStatusMap]::Resolve('Start Pending'),
                    [string][IcingaServiceStatusMap]::Resolve('Continue Pending'),
                    [string][IcingaServiceStatusMap]::Resolve('Unknown')
                );
            };
            $Resolved | Should -Be @('Running', 'StartPending', 'ContinuePending', 'Unknown');
        }

        It 'resolves names in any casing and numeric codes' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaServiceStatusMap]::Resolve('paused'),
                    [string][IcingaServiceStatusMap]::Resolve(1),
                    [string][IcingaServiceStatusMap]::Resolve('4')
                );
            };
            $Resolved | Should -Be @('Paused', 'Stopped', 'Running');
        }

        It 'resolves unmappable values to Unknown' {
            $Resolved = & $script:IcingaModule {
                return @(
                    [string][IcingaServiceStatusMap]::Resolve($null),
                    [string][IcingaServiceStatusMap]::Resolve(''),
                    [string][IcingaServiceStatusMap]::Resolve('Sleeping'),
                    [string][IcingaServiceStatusMap]::Resolve(99)
                );
            };
            $Resolved | Should -Be @('Unknown', 'Unknown', 'Unknown', 'Unknown');
        }
    }
}

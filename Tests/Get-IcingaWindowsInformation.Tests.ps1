<#
.SYNOPSIS
Pester unit test suite for Get-IcingaWindowsInformation in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for Get-IcingaWindowsInformation
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

Describe 'Get-IcingaWindowsInformation' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        # Runs the query inside the module scope with Get-CimInstance shadowed by a
        # function. The result is wrapped in a hashtable so its type survives the
        # pipeline, and IcingaError is only resolvable inside the module scope.
        function Invoke-TestWindowsInformation()
        {
            param (
                [hashtable]$Arguments = @{ },
                [array]$StubData      = @(),
                [string]$FailCode     = '',
                [switch]$EchoArguments
            );

            return (& $script:IcingaModule {
                param ($Arguments, $StubData, $FailCode, $EchoArguments);

                class FakeCimException : System.Exception
                {
                    [string]$NativeErrorCode = '';

                    FakeCimException([string]$Message, [string]$Code) : base($Message)
                    {
                        $this.NativeErrorCode = $Code;
                    }
                }

                function Get-CimInstance()
                {
                    [CmdletBinding()]
                    param (
                        [string]$ClassName  = '',
                        [string]$Namespace  = '',
                        [string]$Filter     = '',
                        [string[]]$Property = @()
                    );

                    if (-not [string]::IsNullOrEmpty($FailCode)) {
                        throw [FakeCimException]::new('Simulated CIM failure', $FailCode);
                    }

                    if ($EchoArguments) {
                        return [PSCustomObject]@{
                            'Bound'     = @($PSBoundParameters.Keys);
                            'ClassName' = $ClassName;
                            'Namespace' = $Namespace;
                            'Filter'    = $Filter;
                            'Property'  = $Property;
                        };
                    }

                    return $StubData;
                }

                $Value = Get-IcingaWindowsInformation @Arguments;

                return @{
                    'Value'   = $Value;
                    'IsArray' = ($Value -is [array]);
                    'IsError' = ($Value -is [IcingaError]);
                };
            } $Arguments $StubData $FailCode $EchoArguments);
        }

        # Runs an OperationOption query inside the module scope with New-CimSession
        # shadowed by a fake session. The fake records every QueryInstances call and
        # its disposal; Get-CimInstance throws, so the session path is proven.
        function Invoke-TestWindowsInformationSession()
        {
            param (
                [hashtable]$Arguments = @{ },
                [array]$StubData      = @(),
                [string]$FailCode     = ''
            );

            return (& $script:IcingaModule {
                param ($Arguments, $StubData, $FailCode);

                class FakeCimException : System.Exception
                {
                    [string]$NativeErrorCode = '';

                    FakeCimException([string]$Message, [string]$Code) : base($Message)
                    {
                        $this.NativeErrorCode = $Code;
                    }
                }

                $FakeSession = [PSCustomObject]@{
                    'Calls'    = [System.Collections.ArrayList]::new();
                    'Disposed' = $false;
                    'StubData' = $StubData;
                    'FailCode' = $FailCode;
                };

                $FakeSession | Add-Member -MemberType ScriptMethod -Name 'QueryInstances' -Value {
                    param ($Namespace, $Dialect, $Query, $Options);

                    [void]$this.Calls.Add(@{ 'Namespace' = $Namespace; 'Dialect' = $Dialect; 'Query' = $Query; 'Options' = $Options; });

                    if (-not [string]::IsNullOrEmpty($this.FailCode)) {
                        throw [FakeCimException]::new('Simulated session failure', $this.FailCode);
                    }

                    return $this.StubData;
                };

                $FakeSession | Add-Member -MemberType ScriptMethod -Name 'Dispose' -Value {
                    $this.Disposed = $true;
                };

                function New-CimSession()
                {
                    [CmdletBinding()]
                    param ();

                    return $FakeSession;
                }

                function Get-CimInstance()
                {
                    throw 'Get-CimInstance must not be used when OperationOption is given';
                }

                $Value = Get-IcingaWindowsInformation @Arguments;

                return @{
                    'Value'   = $Value;
                    'IsArray' = ($Value -is [array]);
                    'IsError' = ($Value -is [IcingaError]);
                    'Session' = $FakeSession;
                };
            } $Arguments $StubData $FailCode);
        }
    }

    Context 'Successful queries' {
        It 'returns the instances as an array, even a single one' {
            $Result = Invoke-TestWindowsInformation -Arguments @{ 'ClassName' = 'Win32_Service'; } -StubData @([PSCustomObject]@{ 'Name' = 'Spooler'; });
            $Result.IsArray          | Should -BeTrue;
            $Result.Value.Count      | Should -Be 1;
            $Result.Value[0].Name    | Should -Be 'Spooler';
        }

        It 'returns an empty array when nothing matches' {
            $Result = Invoke-TestWindowsInformation -Arguments @{ 'ClassName' = 'Win32_Service'; };
            $Result.IsArray     | Should -BeTrue;
            $Result.Value.Count | Should -Be 0;
        }

        It 'uses root/cimv2 and passes filter and properties only when given' {
            $Plain = Invoke-TestWindowsInformation -Arguments @{ 'ClassName' = 'Win32_Volume'; } -EchoArguments;
            $Plain.Value[0].Namespace | Should -Be 'root/cimv2';
            $Plain.Value[0].Bound     | Should -Not -Contain 'Filter';
            $Plain.Value[0].Bound     | Should -Not -Contain 'Property';

            $Full  = Invoke-TestWindowsInformation -Arguments @{ 'ClassName' = 'MSFT_Disk'; 'Namespace' = 'root/Microsoft/Windows/Storage'; 'Filter' = 'Number = 0'; 'Property' = @('Number', 'Size'); } -EchoArguments;
            $Full.Value[0].Namespace | Should -Be 'root/Microsoft/Windows/Storage';
            $Full.Value[0].Filter    | Should -Be 'Number = 0';
            $Full.Value[0].Property  | Should -Be @('Number', 'Size');
        }
    }

    Context 'Failed queries' {
        It 'maps the CIM error <Code> to <ReturnCode>' -ForEach @(
            @{ 'Code' = 'InvalidClass'; 'ReturnCode' = 'WindowsInformationClassUnknown'; },
            @{ 'Code' = 'InvalidNamespace'; 'ReturnCode' = 'WindowsInformationNamespaceInvalid'; },
            @{ 'Code' = 'AccessDenied'; 'ReturnCode' = 'WindowsInformationAccessDenied'; },
            @{ 'Code' = 'InvalidQuery'; 'ReturnCode' = 'WindowsInformationInvalidQuery'; },
            @{ 'Code' = 'NoSuchProperty'; 'ReturnCode' = 'WindowsInformationInvalidQuery'; },
            @{ 'Code' = 'Failed'; 'ReturnCode' = 'WindowsInformationQueryFailed'; }
        ) {
            $Result = Invoke-TestWindowsInformation -Arguments @{ 'ClassName' = 'Win32_Foo'; 'Namespace' = 'root/test'; } -FailCode $Code;
            $Result.IsError          | Should -BeTrue;
            $Result.Value.ReturnCode | Should -Be $ReturnCode;
        }

        It 'names class, namespace and reason in the error message and data' {
            $Result = Invoke-TestWindowsInformation -Arguments @{ 'ClassName' = 'MPIO_DISK_INFO'; 'Namespace' = 'root/wmi'; } -FailCode 'InvalidClass';
            $Result.Value.Message           | Should -Be 'The requested CIM class does not exist on this system: Class "MPIO_DISK_INFO", Namespace "root/wmi": Simulated CIM failure';
            $Result.Value.Data['ClassName'] | Should -Be 'MPIO_DISK_INFO';
            $Result.Value.Data['Namespace'] | Should -Be 'root/wmi';
        }

        It 'returns an IcingaError instead of throwing for a missing class name' {
            $Result = Invoke-TestWindowsInformation -Arguments @{ };
            $Result.IsError          | Should -BeTrue;
            $Result.Value.ReturnCode | Should -Be 'WindowsInformationClassNameMissing';
            $Result.Value.Message    | Should -Be 'No CIM class name was provided for the query';
        }
    }

    Context 'Queries with OperationOption' {
        It 'runs a WQL query through a CimSession with the custom options and disposes the session' {
            $Result = Invoke-TestWindowsInformationSession -Arguments @{ 'ClassName' = 'MSFT_NetFirewallProfile'; 'Namespace' = 'root/StandardCimv2'; 'OperationOption' = @{ 'PolicyStore' = 'ActiveStore'; }; } -StubData @([PSCustomObject]@{ 'Name' = 'Domain'; 'Enabled' = 1; });

            $Result.IsArray       | Should -BeTrue;
            $Result.Value.Count   | Should -Be 1;
            $Result.Value[0].Name | Should -Be 'Domain';

            $Result.Session.Calls.Count           | Should -Be 1;
            $Result.Session.Calls[0]['Namespace'] | Should -Be 'root/StandardCimv2';
            $Result.Session.Calls[0]['Dialect']   | Should -Be 'WQL';
            $Result.Session.Calls[0]['Query']     | Should -Be 'SELECT * FROM MSFT_NetFirewallProfile';
            $Result.Session.Calls[0]['Options']   | Should -BeOfType ([Microsoft.Management.Infrastructure.Options.CimOperationOptions]);
            $Result.Session.Disposed              | Should -BeTrue;
        }

        It 'builds the WQL select list and WHERE clause from Property and Filter' {
            $Result = Invoke-TestWindowsInformationSession -Arguments @{ 'ClassName' = 'MSFT_NetFirewallProfile'; 'Namespace' = 'root/StandardCimv2'; 'Property' = @('Name', 'Enabled'); 'Filter' = "Name = 'Domain'"; 'OperationOption' = @{ 'PolicyStore' = 'RSOP'; }; };

            $Result.Session.Calls[0]['Query'] | Should -Be "SELECT Name, Enabled FROM MSFT_NetFirewallProfile WHERE Name = 'Domain'";
            $Result.IsArray                   | Should -BeTrue;
            $Result.Value.Count               | Should -Be 0;
        }

        It 'unwraps the CIM error of a session call to <ReturnCode> and still disposes the session' -ForEach @(
            @{ 'Code' = 'InvalidClass'; 'ReturnCode' = 'WindowsInformationClassUnknown'; },
            @{ 'Code' = 'AccessDenied'; 'ReturnCode' = 'WindowsInformationAccessDenied'; },
            @{ 'Code' = 'Failed'; 'ReturnCode' = 'WindowsInformationQueryFailed'; }
        ) {
            $Result = Invoke-TestWindowsInformationSession -Arguments @{ 'ClassName' = 'MSFT_Foo'; 'Namespace' = 'root/StandardCimv2'; 'OperationOption' = @{ 'PolicyStore' = 'ActiveStore'; }; } -FailCode $Code;

            $Result.IsError                       | Should -BeTrue;
            $Result.Value.ReturnCode              | Should -Be $ReturnCode;
            $Result.Value.Message                 | Should -Match 'Class "MSFT_Foo", Namespace "root/StandardCimv2": Simulated session failure$';
            $Result.Value.Data['OperationOption'] | Should -Not -BeNullOrEmpty;
            $Result.Session.Disposed              | Should -BeTrue;
        }
    }
}

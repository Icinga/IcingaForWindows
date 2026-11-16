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
}

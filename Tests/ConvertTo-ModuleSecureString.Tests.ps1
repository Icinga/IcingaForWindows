$ModulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'ConvertTo-ModuleSecureString and Get-IcingaUnixTime' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        function ConvertFrom-TestSecureString()
        {
            param (
                [System.Security.SecureString]$Secure = $null
            );

            if ($null -eq $Secure) {
                return $null;
            }

            [System.IntPtr]$Ptr = [System.IntPtr]::Zero;
            try {
                $Ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Secure);
                return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($Ptr);
            } finally {
                if ($Ptr -ne [System.IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($Ptr);
                }
            }
        }
    }

    Context 'ConvertTo-ModuleSecureString' {
        It 'returns $null when InputObject is $null' {
            $Result = & $script:IcingaModule { ConvertTo-ModuleSecureString -InputObject $null };
            $Result | Should -BeNullOrEmpty;
        }

        It 'returns an empty read-only SecureString without throwing on empty string input' {
            $Result = & $script:IcingaModule { ConvertTo-ModuleSecureString -InputObject '' };
            ($Result -is [System.Security.SecureString])   | Should -BeTrue;
            $Result.IsReadOnly()                           | Should -BeTrue;
            $Result.Length                                 | Should -Be 0;
            (ConvertFrom-TestSecureString -Secure $Result) | Should -Be '';
            $Result.Dispose();
        }

        It 'converts plain-text strings and scalar inputs into a read-only SecureString' {
            $Result    = & $script:IcingaModule { ConvertTo-ModuleSecureString -InputObject 'S3cr3t!Pass#2026' };
            $NumResult = & $script:IcingaModule { ConvertTo-ModuleSecureString -InputObject 98765 };
            try {
                ($Result -is [System.Security.SecureString])      | Should -BeTrue;
                $Result.IsReadOnly()                              | Should -BeTrue;
                (ConvertFrom-TestSecureString -Secure $Result)    | Should -Be 'S3cr3t!Pass#2026';
                (ConvertFrom-TestSecureString -Secure $NumResult) | Should -Be '98765';
            } finally {
                $Result.Dispose();
                $NumResult.Dispose();
            }
        }

        It 'returns an existing SecureString instance unchanged' {
            $Existing = & $script:IcingaModule { ConvertTo-ModuleSecureString -InputObject 'AlreadySecure' };
            try {
                $Returned = & $script:IcingaModule {
                    param ($Sec);
                    return (ConvertTo-ModuleSecureString -InputObject $Sec);
                } $Existing;

                [object]::ReferenceEquals($Existing, $Returned) | Should -BeTrue;
            } finally {
                $Existing.Dispose();
            }
        }

        It 'emits SecureStringConversionFailed via Write-FunctionReturnValue and returns $null without throwing on oversized input' {
            [string]$OversizedSecret = ('S' * 65537);
            [hashtable]$FailureData  = & $script:IcingaModule {
                param ($BigInput);

                $script:CapturedCodeKeys = @();
                $RealReturnCmd           = Get-Command -Name 'Write-FunctionReturnValue' -CommandType Function;

                function Write-FunctionReturnValue()
                {
                    param (
                        [string]$ReturnValue   = $null,
                        [hashtable]$Data       = @{ },
                        $OverrideReturn        = 'Core::IgnoreOverride',
                        [switch]$AutomationRun = $false
                    );

                    $script:CapturedCodeKeys += $ReturnValue;
                    return (& $RealReturnCmd -ReturnValue $ReturnValue -Data $Data -OverrideReturn $OverrideReturn -AutomationRun:$AutomationRun);
                }

                $Converted = ConvertTo-ModuleSecureString -InputObject $BigInput;

                function Invoke-IcingaCheckMockOversizedSecret()
                {
                    param (
                        [securestring]$Password = $null
                    );

                    return 0;
                }

                $CheckRes = Invoke-IcingaProtocolCheckCommand -Params @{
                    'command' = 'Invoke-IcingaCheckMockOversizedSecret';
                    'macros'  = @{
                        'ifw_api_command'   = 'Invoke-IcingaCheckMockOversizedSecret';
                        'ifw_api_arguments' = @{
                            'Password' = @{ 'value' = $BigInput; };
                        };
                    };
                };

                return @{
                    'Converted'     = $Converted;
                    'CapturedKeys'  = $script:CapturedCodeKeys;
                    'CheckExitCode' = $CheckRes['ExitCode'];
                    'CheckOutput'   = $CheckRes['Output'];
                    'CommandLine'   = $CheckRes['CommandLine'];
                };
            } $OversizedSecret;

            $FailureData['Converted']     | Should -BeNullOrEmpty;
            $FailureData['CapturedKeys']  | Should -Contain 'SecureStringConversionFailed';
            $FailureData['CapturedKeys']  | Should -Contain 'IcingaProtocolMacroMappingFailed';
            $FailureData['CheckExitCode'] | Should -Be 3;
            $FailureData['CheckOutput']   | Should -Match '\[UNKNOWN\]';
            $FailureData['CommandLine']   | Should -Not -Match 'SSSSSS';
        }
    }

    Context 'Get-IcingaUnixTime' {
        It 'returns UTC Unix seconds without local timezone drift' {
            [int]$Expected = [int][System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds();
            $Actual        = Get-IcingaUnixTime;

            ($Actual -is [int])                    | Should -BeTrue;
            [System.Math]::Abs($Actual - $Expected) | Should -BeLessOrEqual 2;
        }

        It 'returns fractional UTC Unix seconds as Double when -Milliseconds is set' {
            [double]$Expected = [double]([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0);
            $Actual           = Get-IcingaUnixTime -Milliseconds;

            ($Actual -is [double])                  | Should -BeTrue;
            [System.Math]::Abs($Actual - $Expected) | Should -BeLessOrEqual 2.0;
        }
    }
}

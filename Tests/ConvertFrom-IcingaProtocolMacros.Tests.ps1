<#
.SYNOPSIS
Pester unit test suite for ConvertFrom-IcingaProtocolMacros in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for ConvertFrom-IcingaProtocolMacros
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

Describe 'ConvertFrom-IcingaProtocolMacros' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        function Invoke-TestMacroParser()
        {
            param (
                [string]$CommandName = 'Invoke-IcingaCheckDirectory',
                [object]$Macros      = $null,
                [string]$BinaryPath  = ''
            );

            return (& $script:IcingaModule {
                param ($CmdName, $MacrosArg, $BinPathArg);

                if (-not [string]::IsNullOrEmpty($BinPathArg)) {
                    [hashtable]$BinResolved = @{
                        'Status'      = 'Ok';
                        'Kind'        = 'Binary';
                        'CommandName' = [System.IO.Path]::GetFileName($BinPathArg);
                        'BinaryPath'  = $BinPathArg;
                        'Parameters'  = $null;
                    };
                    return (ConvertFrom-IcingaProtocolMacros -ResolvedCommand $BinResolved -Macros $MacrosArg);
                }

                $CmdInfo               = Get-Command -Name $CmdName -CommandType Function, Cmdlet -ErrorAction Stop | Select-Object -First 1;
                [hashtable]$PsResolved = @{
                    'Status'      = 'Ok';
                    'Kind'        = 'PowerShell';
                    'CommandName' = [string]$CmdInfo.Name;
                    'BinaryPath'  = '';
                    'Parameters'  = $CmdInfo.Parameters;
                };
                return (ConvertFrom-IcingaProtocolMacros -ResolvedCommand $PsResolved -Macros $MacrosArg);
            } $CommandName $Macros $BinaryPath);
        }
    }

    Context 'Mode A -- Active ifw-api template (PowerShell checks)' {
        It 'maps real Icinga 2 ifw_api_arguments payloads and skips unset optional macros' {
            [hashtable]$Macros = @{
                'ifw_api_command'                                   = 'Invoke-IcingaCheckDirectory';
                'IcingaPowerShellBase_String_ExecutionPolicy'       = 'ByPass';
                'IcingaCheckDirectory_String_Path'                  = 'C:\Users\cstein';
                'IcingaCheckDirectory_Array_FileNames'              = @( '*.gitconfig' );
                'IcingaCheckDirectory_String_Critical'              = '0';
                'IcingaCheckDirectory_Switchparameter_ShowFileList' = $true;
                'IcingaCheckDirectory_Switchparameter_Recurse'      = 'False';
                'IcingaCheckDirectory_String_OverrideNotFound'      = '';
                'IcingaCheckDirectory_Int32_Verbosity'              = '';
                'ifw_api_arguments'                                 = @{
                    '-Path'              = @{ 'value' = '$IcingaCheckDirectory_String_Path$'; };
                    '-FileNames'         = @{ 'value' = '$IcingaCheckDirectory_Array_FileNames$'; };
                    '-Critical'          = @{ 'value' = '$IcingaCheckDirectory_String_Critical$'; };
                    '-ShowFileList'      = @{ 'set_if' = '$IcingaCheckDirectory_Switchparameter_ShowFileList$'; };
                    '-Recurse'           = @{ 'set_if' = '$IcingaCheckDirectory_Switchparameter_Recurse$'; };
                    '-OverrideNotFound'  = @{ 'value' = '$IcingaCheckDirectory_String_OverrideNotFound$'; };
                    '-Verbosity'         = @{ 'value' = '$IcingaCheckDirectory_Int32_Verbosity$'; };
                    '-ThresholdInterval' = @{ 'value' = '$IcingaCheckDirectory_String_ThresholdInterval$'; };
                };
            };

            [hashtable]$Parsed = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $Macros;

            $Parsed['Status']                                              | Should -Be 'Ok';
            $Parsed['PowerShellArguments']['Path']                         | Should -Be 'C:\Users\cstein';
            $Parsed['PowerShellArguments']['FileNames']                    | Should -Be @( '*.gitconfig' );
            $Parsed['PowerShellArguments']['Critical']                     | Should -Be '0';
            $Parsed['PowerShellArguments']['ShowFileList']                 | Should -BeTrue;
            $Parsed['PowerShellArguments'].ContainsKey('Recurse')          | Should -BeFalse;
            $Parsed['PowerShellArguments'].ContainsKey('OverrideNotFound') | Should -BeFalse;
            $Parsed['PowerShellArguments'].ContainsKey('Verbosity')        | Should -BeFalse;
            $Parsed['CommandLine']                                         | Should -Be "Invoke-IcingaCheckDirectory -Critical '0' -FileNames @('*.gitconfig') -Path 'C:\Users\cstein' -ShowFileList";
        }

        It 'supports Dictionary[string, object] from Windows PowerShell 5.1 and PSCustomObject payloads' {
            $Ps51Macros                                     = New-Object 'System.Collections.Generic.Dictionary[string, object]';
            $Ps51Args                                       = New-Object 'System.Collections.Generic.Dictionary[string, object]';
            $Ps51PathSpec                                   = New-Object 'System.Collections.Generic.Dictionary[string, object]';
            $Ps51PathSpec['value']                          = '$ICINGACHECKDIRECTORY_STRING_PATH$';
            $Ps51Args['-Path']                              = $Ps51PathSpec;
            $Ps51Macros['ifw_api_command']                  = 'Invoke-IcingaCheckDirectory';
            $Ps51Macros['icingacheckdirectory_string_path'] = $null;
            $Ps51Macros['IcingaCheckDirectory_String_Path'] = 'D:\Logs';
            $Ps51Macros['ifw_api_arguments']                = $Ps51Args;

            [hashtable]$Parsed                              = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $Ps51Macros;

            $PsObjMacros                                    = [PSCustomObject]@{
                'ifw_api_command'   = 'Invoke-IcingaCheckDirectory';
                'target_path'       = 'E:\Data';
                'ifw_api_arguments' = [PSCustomObject]@{
                    '-Path'         = [PSCustomObject]@{ 'value' = '$target_path$'; };
                    '-ShowFileList' = [PSCustomObject]@{ 'value' = $null; };
                    '-Critical'     = [PSCustomObject]@{ 'value' = $null; };
                };
            };

            [hashtable]$ObjParsed                           = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $PsObjMacros;

            $Parsed['Status']                                           | Should -Be 'Ok';
            $Parsed['PowerShellArguments']['Path']                      | Should -Be 'D:\Logs';

            $ObjParsed['Status']                                        | Should -Be 'Ok';
            $ObjParsed['PowerShellArguments']['Path']                   | Should -Be 'E:\Data';
            $ObjParsed['PowerShellArguments']['ShowFileList']           | Should -BeTrue;
            $ObjParsed['PowerShellArguments'].ContainsKey('Critical')   | Should -BeFalse;
        }

        It 'skips empty string "", empty [] and empty {} on unknown parameters in ifw_api_arguments and raises IWKB001001 on non-empty values' {
            [hashtable]$EmptyUnknown     = @{
                'ifw_api_command'   = 'Invoke-IcingaCheckDirectory';
                'Path'              = 'C:\Temp';
                'ObsoleteEmpty'     = '';
                'ObsoleteList'      = @();
                'ObsoleteDict'      = @{ };
                'EmptyFileNames'    = @();
                'ifw_api_arguments' = @{
                    '-Path'              = @{ 'value' = '$Path$'; };
                    '-FileNames'         = @{ 'value' = '$EmptyFileNames$'; };
                    '-ThresholdInterval' = @{ 'value' = '$ObsoleteEmpty$'; };
                    '-LegacyArrayParam'  = @{ 'value' = '$ObsoleteList$'; };
                    '-LegacyMapParam'    = @{ 'value' = '$ObsoleteDict$'; };
                    '-NullRemovedParam'  = @{ 'value' = $null; };
                };
            };

            [hashtable]$PopulatedUnknown = @{
                'ifw_api_command'   = 'Invoke-IcingaCheckDirectory';
                'ObsoleteValue'     = '10s';
                'ifw_api_arguments' = @{
                    '-ThresholdInterval' = @{ 'value' = '$ObsoleteValue$'; };
                };
            };

            [hashtable]$PopulatedListUnk = @{
                'ifw_api_command'   = 'Invoke-IcingaCheckDirectory';
                'ObsoleteArr'       = @( '10s' );
                'ifw_api_arguments' = @{
                    '-ThresholdInterval' = @{ 'value' = '$ObsoleteArr$'; };
                };
            };

            [hashtable]$EmptyRes         = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $EmptyUnknown;
            [hashtable]$PopRes           = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $PopulatedUnknown;
            [hashtable]$PopListRes       = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $PopulatedListUnk;

            $EmptyRes['Status']                                        | Should -Be 'Ok';
            $EmptyRes['PowerShellArguments']['Path']                   | Should -Be 'C:\Temp';
            $EmptyRes['PowerShellArguments'].ContainsKey('FileNames')  | Should -BeFalse;

            $PopRes['Status']                                          | Should -Be 'UnknownParameter';
            $PopRes['KnowledgeBaseId']                                 | Should -Be 'IWKB001001';
            $PopRes['Message']                                         | Should -Match 'ThresholdInterval';
            $PopRes['Message']                                         | Should -Match 'IWKB001001';

            $PopListRes['Status']                                      | Should -Be 'UnknownParameter';
            $PopListRes['KnowledgeBaseId']                             | Should -Be 'IWKB001001';
        }

        It 'handles Windows dollar-sign paths, escaped $$ literals, single-pass substitution and empty array macros' {
            [hashtable]$DollarMacros = @{
                'ifw_api_command'   = 'Invoke-IcingaCheckDirectory';
                'address'           = '10.0.0.5';
                'first'             = 'keep$second$literal';
                'second'            = 'REPLACED';
                'empty_files'       = '';
                'ifw_api_arguments' = @{
                    '-Path'              = @{ 'value' = '\\$address$\C$\MSSQL$SQLEXPRESS'; };
                    '-ChangeTimeEqual'   = @{ 'value' = '\\$address$\D$$'; };
                    '-CreationTimeEqual' = @{ 'value' = '$first$/$second$'; };
                    '-FileNames'         = @{ 'value' = '$empty_files$'; };
                };
            };

            [hashtable]$DollarParsed = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $DollarMacros;

            $DollarParsed['Status']                                       | Should -Be 'Ok';
            $DollarParsed['PowerShellArguments']['Path']                  | Should -Be '\\10.0.0.5\C$\MSSQL$SQLEXPRESS';
            $DollarParsed['PowerShellArguments']['ChangeTimeEqual']       | Should -Be '\\10.0.0.5\D$';
            $DollarParsed['PowerShellArguments']['CreationTimeEqual']     | Should -Be 'keep$second$literal/REPLACED';
            $DollarParsed['PowerShellArguments'].ContainsKey('FileNames') | Should -BeFalse;

            [hashtable]$SvcParsed    = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckService' -Macros @{
                'ifw_api_command'   = 'Invoke-IcingaCheckService';
                'FilterStartupType' = '';
            };

            $SvcParsed['Status']                                               | Should -Be 'Ok';
            $SvcParsed['PowerShellArguments'].ContainsKey('FilterStartupType') | Should -BeFalse;
        }

        It 'resolves parameter aliases and formats uint32, single and uint64 numeric types unquoted in CommandLine' {
            [hashtable]$AliasRes = & $script:IcingaModule {
                function Invoke-IcingaCheckMockAliasNumeric()
                {
                    param (
                        [Alias('PortNum')]
                        [uint32]$Port    = 443,
                        [single]$Ratio   = 0.5,
                        [uint64[]]$Sizes = @()
                    );

                    return 0;
                }

                $CmdInfo         = Get-Command -Name 'Invoke-IcingaCheckMockAliasNumeric' -CommandType Function;
                [hashtable]$Info = @{
                    'Status'      = 'Ok';
                    'Kind'        = 'PowerShell';
                    'CommandName' = 'Invoke-IcingaCheckMockAliasNumeric';
                    'BinaryPath'  = '';
                    'Parameters'  = $CmdInfo.Parameters;
                };
                [hashtable]$RawMacros = @{
                    'ifw_api_command'   = 'Invoke-IcingaCheckMockAliasNumeric';
                    'p'                 = '8443';
                    'r'                 = '1.25';
                    's'                 = @( '1024', '2048' );
                    'ifw_api_arguments' = @{
                        '-PortNum' = @{ 'value' = '$p$'; };
                        '-Ratio'   = @{ 'value' = '$r$'; };
                        '-Sizes'   = @{ 'value' = '$s$'; };
                    };
                };

                return (ConvertFrom-IcingaProtocolMacros -ResolvedCommand $Info -Macros $RawMacros);
            };

            $AliasRes['Status']                        | Should -Be 'Ok';
            $AliasRes['PowerShellArguments']['Port']   | Should -Be ([uint32]8443);
            $AliasRes['PowerShellArguments']['Ratio']  | Should -Be ([single]1.25);
            $AliasRes['CommandLine']                   | Should -Be 'Invoke-IcingaCheckMockAliasNumeric -Port 8443 -Ratio 1.25 -Sizes @(1024, 2048)';
        }
    }

    Context 'Mode B -- Fallback without ifw-api (PowerShell checks)' {
        It 'maps IcingaCheck[Name]_[Type]_[Param], direct names and ignores empty "" macro keys without IWKB001000' {
            $Macros                                                      = New-Object 'System.Collections.Generic.Dictionary[string, object]';
            $Macros['']                                                  = '$';
            $Macros['   ']                                               = '$';
            $Macros['ifw_api_command']                                   = 'Invoke-IcingaCheckDirectory';
            $Macros['IcingaPowerShellBase_String_ExecutionPolicy']       = 'ByPass';
            $Macros['IcingaCheckDirectory_String_Path']                  = 'C:\Users\cstein';
            $Macros['IcingaCheckDirectory_Array_FileNames']              = '*.gitconfig';
            $Macros['IcingaCheckDirectory_Switchparameter_ShowFileList'] = 'True';
            $Macros['Verbosity']                                         = '2';

            [hashtable]$Parsed                                           = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $Macros;

            $Parsed['Status']                              | Should -Be 'Ok';
            $Parsed['PowerShellArguments']['Path']         | Should -Be 'C:\Users\cstein';
            $Parsed['PowerShellArguments']['FileNames']    | Should -Be @( '*.gitconfig' );
            $Parsed['PowerShellArguments']['ShowFileList'] | Should -BeTrue;
            $Parsed['PowerShellArguments']['Verbosity']    | Should -Be 2;
        }

        It 'returns MappingFailed with exact error message and IWKB001000 on unmapped custom variables' {
            [hashtable]$Macros = @{
                'ifw_api_command' = 'Invoke-IcingaCheckDirectory';
                'Path'            = 'C:\Temp';
                'foo_bar'         = 'unexpected';
            };

            [hashtable]$Parsed = Invoke-TestMacroParser -CommandName 'Invoke-IcingaCheckDirectory' -Macros $Macros;

            $Parsed['Status']          | Should -Be 'MappingFailed';
            $Parsed['KnowledgeBaseId'] | Should -Be 'IWKB001000';
            $Parsed['Message']         | Should -Match 'Unable to map Custom-Variables to Icinga for Windows Check';
            $Parsed['Message']         | Should -Match 'foo_bar';
            $Parsed['Message']         | Should -Match 'IWKB001000';
        }
    }

    Context 'SecureString conversion and CommandLine masking' {
        It 'converts plain-text secrets to SecureString and masks them in CommandLine' {
            [hashtable]$Parsed = & $script:IcingaModule {
                function Invoke-IcingaCheckMockAuth()
                {
                    param (
                        [string]$Username        = '',
                        [securestring]$ApiSecret = $null
                    );

                    return 0;
                }

                $CmdInfo              = Get-Command -Name 'Invoke-IcingaCheckMockAuth' -CommandType Function;
                [hashtable]$Info      = @{
                    'Status'      = 'Ok';
                    'Kind'        = 'PowerShell';
                    'CommandName' = 'Invoke-IcingaCheckMockAuth';
                    'BinaryPath'  = '';
                    'Parameters'  = $CmdInfo.Parameters;
                };
                [hashtable]$RawMacros = @{
                    'ifw_api_command' = 'Invoke-IcingaCheckMockAuth';
                    'Username'        = 'icinga';
                    'ApiSecret'       = 'TopSecretValue!';
                };

                return (ConvertFrom-IcingaProtocolMacros -ResolvedCommand $Info -Macros $RawMacros);
            };

            try {
                $Parsed['Status']                                                                 | Should -Be 'Ok';
                ($Parsed['PowerShellArguments']['ApiSecret'] -is [System.Security.SecureString]) | Should -BeTrue;
                $Parsed['AllocatedSecureStrings'].Count                                           | Should -Be 1;
                $Parsed['CommandLine']                                                            | Should -Match ([regex]::Escape("-ApiSecret '********'"));
                $Parsed['CommandLine']                                                            | Should -Not -Match 'TopSecretValue';
            } finally {
                foreach ($Sec in $Parsed['AllocatedSecureStrings']) {
                    $Sec.Dispose();
                }
            }
        }
    }

    Context 'Binary argument mapping (ifw-api and Fallback)' {
        It 'builds ordered CLI arguments with serialized "value": null, skip_key, repeat_key and float order' {
            [hashtable]$Macros     = @{
                'ifw_api_command'   = 'check_http.exe';
                'address'           = '127.0.0.1';
                'port'              = 8080;
                'headers'           = @( 'X-Test: 1', 'X-Env: prod' );
                'tags'              = @( 'web', 'edge' );
                'pos_items'         = @( 'posA', 'posB' );
                'ssl_enabled'       = $true;
                'ifw_api_arguments' = @{
                    '-4'          = @{ 'order' = -1; 'value' = $null; 'set_if' = $null; 'skip_key' = $false; 'description' = 'IPv4 only'; };
                    'ignored_pos' = @{ 'order' = 0; 'value' = $null; 'skip_key' = $true; };
                    'endpoint'    = @{ 'value' = 'http://$address$:$port$/health'; 'skip_key' = $true; 'order' = '1.0'; };
                    '-H'          = @{ 'value' = '$headers$'; 'repeat_key' = $true; 'order' = 2; };
                    '--tags'      = @{ 'value' = '$tags$'; 'repeat_key' = $false; 'order' = '2.5'; };
                    'extra_pos'   = @{ 'value' = '$pos_items$'; 'skip_key' = $true; 'order' = 3; };
                    '--ssl'       = @{ 'set_if' = '$ssl_enabled$'; 'order' = 4; };
                };
            };

            [string]$HttpCheckPath = & $script:IcingaModule { Join-Path -Path (Get-ModuleBinaryDirectory) -ChildPath 'check_http.exe' };
            [hashtable]$Parsed     = Invoke-TestMacroParser -BinaryPath $HttpCheckPath -Macros $Macros;

            $Parsed['Status']          | Should -Be 'Ok';
            $Parsed['BinaryArguments'] | Should -Be @( '-4', 'http://127.0.0.1:8080/health', '-H', 'X-Test: 1', '-H', 'X-Env: prod', '--tags', 'web', 'edge', 'posA', 'posB', '--ssl' );
            $Parsed['CommandLine']     | Should -Match 'check_http\.exe';
            $Parsed['CommandLine']     | Should -Match '"X-Test: 1"';
        }

        It 'preserves case-distinct CLI flags (-p vs -P and -c vs -C) in both ifw-api and Fallback modes' {
            $CaseApiArgs                           = New-Object 'System.Collections.Generic.Dictionary[string, object]';
            $CaseApiArgs['-p']                     = @{ 'value' = '8080'; 'order' = 1; };
            $CaseApiArgs['-P']                     = @{ 'value' = 'payload=ok'; 'order' = 2; };
            $CaseApiArgs['-c']                     = @{ 'value' = '5'; 'order' = 3; };
            $CaseApiArgs['-C']                     = @{ 'value' = '30,14'; 'order' = 4; };

            $CaseApiMacros                         = New-Object 'System.Collections.Generic.Dictionary[string, object]';
            $CaseApiMacros['ifw_api_command']      = 'check_http.exe';
            $CaseApiMacros['ifw_api_arguments']    = $CaseApiArgs;

            $CaseFallbackMacros                    = New-Object 'System.Collections.Generic.Dictionary[string, object]';
            $CaseFallbackMacros['']                = '$';
            $CaseFallbackMacros['ifw_api_command'] = 'check_http.exe';
            $CaseFallbackMacros['-p']              = '8080';
            $CaseFallbackMacros['-P']              = 'payload=ok';
            $CaseFallbackMacros['-c']              = '5';
            $CaseFallbackMacros['-C']              = '30,14';

            [string]$HttpBin                       = & $script:IcingaModule { Join-Path -Path (Get-ModuleBinaryDirectory) -ChildPath 'check_http.exe' };
            [hashtable]$ApiRes                     = Invoke-TestMacroParser -BinaryPath $HttpBin -Macros $CaseApiMacros;
            [hashtable]$FallRes                    = Invoke-TestMacroParser -BinaryPath $HttpBin -Macros $CaseFallbackMacros;

            $ApiRes['Status']           | Should -Be 'Ok';
            $ApiRes['BinaryArguments']  | Should -Be @( '-p', '8080', '-P', 'payload=ok', '-c', '5', '-C', '30,14' );

            $FallRes['Status']          | Should -Be 'Ok';
            $FallRes['BinaryArguments'] | Should -Be @( '-p', '8080', '-P', 'payload=ok', '-c', '5', '-C', '30,14' );
        }

        It 'allows zero or flag-prefixed custom variables for binaries in Fallback mode and rejects unprefixed ones with IWKB001002' {
            [string]$BinPath   = & $script:IcingaModule { Join-Path -Path (Get-ModuleBinaryDirectory) -ChildPath 'check_load.exe' };
            [hashtable]$Empty  = Invoke-TestMacroParser -BinaryPath $BinPath -Macros @{ 'ifw_api_command' = 'check_load.exe'; };
            [hashtable]$Flags  = Invoke-TestMacroParser -BinaryPath $BinPath -Macros @{ 'ifw_api_command' = 'check_load.exe'; '-w' = '80%'; '/v' = $true; };
            [hashtable]$BadVar = Invoke-TestMacroParser -BinaryPath $BinPath -Macros @{ 'ifw_api_command' = 'check_load.exe'; 'load_win_warn' = '80%'; };

            $Empty['Status']                | Should -Be 'Ok';
            $Empty['BinaryArguments'].Count | Should -Be 0;

            $Flags['Status']                | Should -Be 'Ok';
            $Flags['BinaryArguments']       | Should -Contain '-w';
            $Flags['BinaryArguments']       | Should -Contain '80%';
            $Flags['BinaryArguments']       | Should -Contain '/v';

            $BadVar['Status']               | Should -Be 'BinaryMappingFailed';
            $BadVar['KnowledgeBaseId']      | Should -Be 'IWKB001002';
            $BadVar['Message']              | Should -Match 'IWKB001002';
        }
    }
}

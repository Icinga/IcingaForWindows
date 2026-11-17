<#
.SYNOPSIS
Pester unit test suite for Invoke-IcingaProtocolCheckCommand in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for Invoke-IcingaProtocolCheckCommand
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

Describe 'Invoke-IcingaProtocolCheckCommand and Split-IcingaBinaryPluginOutput' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    BeforeEach {
        $script:TestBinDir  = Join-Path -Path $TestDrive -ChildPath ('Bin_' + [System.Guid]::NewGuid().ToString('N'));
        $script:TestDataDir = Join-Path -Path $TestDrive -ChildPath ('Data_' + [System.Guid]::NewGuid().ToString('N'));
        New-Item -Path $script:TestBinDir -ItemType Directory -Force | Out-Null;
        New-Item -Path $script:TestDataDir -ItemType Directory -Force | Out-Null;
    }

    Context 'Split-IcingaBinaryPluginOutput' {
        It 'splits single-line, multi-line, quoted, scoped and doubled-quote performance data accurately' {
            [string]$Sample   = "DISK WARNING - free space low | 'C:\ Free Space'=12GB;20;10;0;100 check_disk::'E:\ Free Space'=18GB;20;10;0;100 'Label''s Space'=10% inode=44%`nDetail line 1`nDetail line 2 | `"D:\ Free Space`"=80GB;20;10;0;100`nextra_metric=5s";

            [hashtable]$Split = & $script:IcingaModule {
                param ($Raw);
                return (Split-IcingaBinaryPluginOutput -RawOutput $Raw);
            } $Sample;

            $Split['Output']                | Should -Be "DISK WARNING - free space low`nDetail line 1`nDetail line 2";
            $Split['PerformanceData'].Count | Should -Be 6;
            $Split['PerformanceData'][0]    | Should -Be "'C:\ Free Space'=12GB;20;10;0;100";
            $Split['PerformanceData'][1]    | Should -Be "check_disk::'E:\ Free Space'=18GB;20;10;0;100";
            $Split['PerformanceData'][2]    | Should -Be "'Label''s Space'=10%";
            $Split['PerformanceData'][3]    | Should -Be 'inode=44%';
            $Split['PerformanceData'][4]    | Should -Be '"D:\ Free Space"=80GB;20;10;0;100';
            $Split['PerformanceData'][5]    | Should -Be 'extra_metric=5s';
        }
    }

    Context 'End-to-end PowerShell plugin execution and SecureString disposal' {
        It 'executes Invoke-IcingaCheckDirectory via shorthand and returns compiled output and perfdata' {
            Set-Content -Path (Join-Path -Path $script:TestDataDir -ChildPath 'a.gitconfig') -Value 'test' -Encoding UTF8;
            Set-Content -Path (Join-Path -Path $script:TestDataDir -ChildPath 'b.gitconfig') -Value 'test' -Encoding UTF8;

            [hashtable]$Params     = @{
                'command' = 'Invoke-IcingaCheckDirectory';
                'macros'  = @{
                    'ifw_api_command'   = 'directory';
                    'Path'              = $script:TestDataDir;
                    'FileNames'         = @( '*.gitconfig' );
                    'Critical'          = '1';
                    'ShowFileList'      = $true;
                    'ifw_api_arguments' = @{
                        '-Path'         = @{ 'value' = '$Path$'; };
                        '-FileNames'    = @{ 'value' = '$FileNames$'; };
                        '-Critical'     = @{ 'value' = '$Critical$'; };
                        '-ShowFileList' = @{ 'set_if' = '$ShowFileList$'; };
                    };
                };
            };

            [hashtable]$ExecResult = & $script:IcingaModule {
                param ($RpcParams, $BinDir);
                function Get-ModuleBinaryDirectory()
                {
                    return $BinDir;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $RpcParams);
            } $Params $script:TestBinDir;

            $ExecResult['ExitCode']              | Should -Be 2;
            $ExecResult['Output']                | Should -Match '\[CRITICAL\]';
            $ExecResult['PerformanceData'].Count | Should -BeGreaterThan 0;
            $ExecResult['CommandLine']           | Should -Match '^Invoke-IcingaCheckDirectory ';
        }

        It 'converts plain-text SecureString arguments, masks CommandLine and disposes the SecureString after execution' {
            [hashtable]$Outcome = & $script:IcingaModule {
                param ($BinDir);

                function Get-ModuleBinaryDirectory()
                {
                    return $BinDir;
                }

                $script:CapturedSecureRef = $null;
                $script:CapturedPlainText = '';

                function Invoke-IcingaCheckSecretProbe()
                {
                    param (
                        [securestring]$Token = $null
                    );

                    $script:CapturedSecureRef = $Token;
                    [System.IntPtr]$Ptr       = [System.IntPtr]::Zero;
                    try {
                        $Ptr                      = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($Token);
                        $script:CapturedPlainText = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($Ptr);
                    } finally {
                        if ($Ptr -ne [System.IntPtr]::Zero) {
                            [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($Ptr);
                        }
                    }

                    $Pkg = New-IcingaPlugin 'Secret Probe';
                    $Pkg.AddCheck((New-IcingaPlugin 'Auth' 1).CheckRange()) | Out-Null;
                    return $Pkg.Compile();
                }

                [hashtable]$RpcParams = @{
                    'command' = 'Invoke-IcingaCheckSecretProbe';
                    'macros'  = @{
                        'ifw_api_command' = 'Invoke-IcingaCheckSecretProbe';
                        'Token'           = 'SuperSecretToken99!';
                    };
                };

                [hashtable]$Res       = Invoke-IcingaProtocolCheckCommand -Params $RpcParams;
                [bool]$WasDisposed    = $false;

                try {
                    [void][System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($script:CapturedSecureRef);
                } catch [System.ObjectDisposedException] {
                    $WasDisposed = $true;
                }

                return @{
                    'Result'      = $Res;
                    'Decrypted'   = $script:CapturedPlainText;
                    'WasDisposed' = $WasDisposed;
                };
            } $script:TestBinDir;

            $Outcome['Decrypted']             | Should -Be 'SuperSecretToken99!';
            $Outcome['WasDisposed']           | Should -BeTrue;
            $Outcome['Result']['ExitCode']    | Should -Be 0;
            $Outcome['Result']['CommandLine'] | Should -Match ([regex]::Escape("-Token '********'"));
            $Outcome['Result']['CommandLine'] | Should -Not -Match 'SuperSecretToken99!';
        }

        It 'catches unhandled exceptions from faulty PowerShell checks and returns UNKNOWN (3)' {
            [hashtable]$CrashRes = & $script:IcingaModule {
                param ($BinDir);

                function Get-ModuleBinaryDirectory()
                {
                    return $BinDir;
                }

                function Invoke-IcingaCheckBoom()
                {
                    throw 'Simulated plugin crash';
                }

                return (Invoke-IcingaProtocolCheckCommand -Params @{
                    'command' = 'Invoke-IcingaCheckBoom';
                    'macros'  = @{ 'ifw_api_command' = 'Invoke-IcingaCheckBoom'; };
                });
            } $script:TestBinDir;

            $CrashRes['ExitCode'] | Should -Be 3;
            $CrashRes['Output']   | Should -Match '\[UNKNOWN\]';
            $CrashRes['Output']   | Should -Match 'Simulated plugin crash';
        }
    }

    Context 'End-to-end External Script and Native Process execution in Binaries' {
        It 'executes .ps1 scripts inside Binaries, splits perfdata and normalizes out-of-range exit codes to 3' {
            [string]$ScriptPath          = Join-Path -Path $script:TestBinDir -ChildPath 'check_custom.ps1';
            [string]$ScriptBody          = @(
                'param([int]$ExitWith = 0, [string]$Label = "disk")',
                'Write-Output ("CUSTOM STATE | ''" + $Label + "''=75%;80;90;0;100")',
                'exit $ExitWith'
            ) -join "`n";
            Set-Content -Path $ScriptPath -Value $ScriptBody -Encoding UTF8;

            [hashtable]$WarnParams       = @{
                'command' = 'check_custom';
                'macros'  = @{
                    'ifw_api_command'   = 'check_custom.ps1';
                    'exit_code'         = 1;
                    'metric_label'      = 'C:\ Data';
                    'ifw_api_arguments' = @{
                        '-ExitWith' = @{ 'value' = '$exit_code$'; 'order' = 1; };
                        '-Label'    = @{ 'value' = '$metric_label$'; 'order' = 2; };
                    };
                };
            };

            [hashtable]$OutOfRangeParams = @{
                'command' = 'check_custom';
                'macros'  = @{
                    'ifw_api_command' = 'check_custom.ps1';
                    '-ExitWith'       = 255;
                };
            };

            [hashtable]$WarnRes          = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $WarnParams $script:TestBinDir;

            [hashtable]$OutRes           = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $OutOfRangeParams $script:TestBinDir;

            $WarnRes['ExitCode']        | Should -Be 1;
            $WarnRes['Output']          | Should -Be 'CUSTOM STATE';
            $WarnRes['PerformanceData'] | Should -Be @( "'C:\ Data'=75%;80;90;0;100" );

            $OutRes['ExitCode']         | Should -Be 3;
        }

        It 'binds array, boolean and SecureString parameters on external .ps1 scripts and masks secrets in CommandLine' {
            [string]$AdvScriptPath     = Join-Path -Path $script:TestBinDir -ChildPath 'check_typed.ps1';
            [string]$AdvScriptBody     = @(
                'param([string[]]$Targets = @(), [bool]$UseSsl = $true, [switch]$ForceCheck = $false, [securestring]$Secret = $null, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @())',
                '$hasSec = ($null -ne $Secret -and $Secret.Length -gt 0)',
                'Write-Output ("Targets=" + ($Targets -join ",") + " Ssl=" + $UseSsl + " Force=" + [bool]$ForceCheck + " Rest=" + $Rest.Count + " Secret=" + $hasSec + " | count=" + $Targets.Count)',
                'exit 0'
            ) -join "`n";
            Set-Content -Path $AdvScriptPath -Value $AdvScriptBody -Encoding UTF8;

            [hashtable]$AdvParams      = @{
                'command' = 'check_typed';
                'macros'  = @{
                    'ifw_api_command'   = 'check_typed.ps1';
                    'targets'           = @( 'node1', 'node2' );
                    'ssl_flag'          = 'False';
                    'force_flag'        = 'False';
                    'api_key'           = ' MySecret123 ';
                    'ifw_api_arguments' = @{
                        '-Targets'    = @{ 'value' = '$targets$'; 'order' = 1; };
                        '-UseSsl'     = @{ 'value' = '$ssl_flag$'; 'order' = 2; };
                        '-ForceCheck' = @{ 'value' = '$force_flag$'; 'order' = 3; };
                        '-Secret'     = @{ 'value' = '$api_key$'; 'order' = 4; };
                    };
                };
            };

            [hashtable]$EmptyArrParams = @{
                'command' = 'check_typed';
                'macros'  = @{
                    'ifw_api_command'   = 'check_typed.ps1';
                    'ifw_api_arguments' = @{
                        '-Targets' = @{ 'order' = 1; 'value' = $null; };
                        '-UseSsl'  = @{ 'value' = 'False'; 'order' = 2; };
                    };
                };
            };

            [hashtable]$TrailingParams = @{
                'command' = 'check_typed';
                'macros'  = @{
                    'ifw_api_command'   = 'check_typed.ps1';
                    'ifw_api_arguments' = @{
                        '-UseSsl' = @{ 'order' = 1; 'value' = $null; };
                    };
                };
            };

            [hashtable]$MidFlagParams  = @{
                'command' = 'check_typed';
                'macros'  = @{
                    'ifw_api_command'   = 'check_typed.ps1';
                    'ifw_api_arguments' = @{
                        '-UseSsl'     = @{ 'order' = 1; 'value' = $null; };
                        '-ForceCheck' = @{ 'order' = 2; 'value' = $null; };
                    };
                };
            };

            [hashtable]$ColonSecParams = @{
                'command' = 'check_typed';
                'macros'  = @{
                    'ifw_api_command'        = 'check_typed.ps1';
                    '-Secret:ColonSecret99!' = $true;
                    '-UseSsl:False'          = $true;
                    '-ForceCheck:True'       = $true;
                };
            };

            [hashtable]$PosSecParams   = @{
                'command' = 'check_typed';
                'macros'  = @{
                    'ifw_api_command'   = 'check_typed.ps1';
                    'ifw_api_arguments' = @{
                        'targets_pos' = @{ 'order' = 1; 'skip_key' = $true; 'value' = 'nodePos'; };
                        'ssl_pos'     = @{ 'order' = 2; 'skip_key' = $true; 'value' = 'False'; };
                        'sec_pos'     = @{ 'order' = 3; 'skip_key' = $true; 'value' = 'PosSecret77!'; };
                    };
                };
            };

            [hashtable]$AdvRes         = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $AdvParams $script:TestBinDir;

            [hashtable]$EmptyArrRes    = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $EmptyArrParams $script:TestBinDir;

            [hashtable]$TrailingRes    = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $TrailingParams $script:TestBinDir;

            [hashtable]$MidFlagRes     = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $MidFlagParams $script:TestBinDir;

            [hashtable]$ColonSecRes    = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $ColonSecParams $script:TestBinDir;

            [hashtable]$PosSecRes      = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $PosSecParams $script:TestBinDir;

            $AdvRes['ExitCode']             | Should -Be 0;
            $AdvRes['Output']               | Should -Be 'Targets=node1,node2 Ssl=False Force=False Rest=0 Secret=True';
            $AdvRes['PerformanceData']      | Should -Be @( 'count=2' );
            $AdvRes['CommandLine']          | Should -Match '\*{8}';
            $AdvRes['CommandLine']          | Should -Not -Match 'MySecret123';

            $EmptyArrRes['ExitCode']        | Should -Be 0;
            $EmptyArrRes['Output']          | Should -Be 'Targets= Ssl=False Force=False Rest=0 Secret=False';
            $EmptyArrRes['PerformanceData'] | Should -Be @( 'count=0' );

            $TrailingRes['ExitCode']        | Should -Be 3;
            $TrailingRes['Output']          | Should -Match '\[UNKNOWN\]';

            $MidFlagRes['ExitCode']         | Should -Be 3;
            $MidFlagRes['Output']           | Should -Match '\[UNKNOWN\]';

            $ColonSecRes['ExitCode']        | Should -Be 0;
            $ColonSecRes['Output']          | Should -Be 'Targets= Ssl=False Force=True Rest=0 Secret=True';
            $ColonSecRes['CommandLine']     | Should -Match ([regex]::Escape('-Secret:********'));
            $ColonSecRes['CommandLine']     | Should -Not -Match 'ColonSecret99!';

            $PosSecRes['ExitCode']          | Should -Be 0;
            $PosSecRes['Output']            | Should -Be 'Targets=nodePos Ssl=False Force=False Rest=0 Secret=True';
            $PosSecRes['CommandLine']       | Should -Match '\*{8}';
            $PosSecRes['CommandLine']       | Should -Not -Match 'PosSecret77!';
        }

        It 'supports external .ps1 scripts in Binaries that build results with New-IcingaPlugin' {
            [string]$PluginScriptPath   = Join-Path -Path $script:TestBinDir -ChildPath 'check_ifw_plugin.ps1';
            [string]$PluginScriptBody   = @(
                'param([int]$Val = 85)',
                '$global:LASTEXITCODE = 0',
                '$Pkg = New-IcingaPlugin ''External Script Package''',
                '$Chk = New-IcingaPlugin ''Load'' $Val ''%''',
                '[void]$Chk.Warning(''80'').Critical(''90'').CheckRange()',
                '[void]$Pkg.AddCheck($Chk)',
                '[void]$Pkg.Compile()'
            ) -join "`n";
            Set-Content -Path $PluginScriptPath -Value $PluginScriptBody -Encoding UTF8;

            [hashtable]$PluginScriptRes = & $script:IcingaModule {
                param ($B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params @{
                    'command' = 'check_ifw_plugin';
                    'macros'  = @{
                        'ifw_api_command'   = 'check_ifw_plugin.ps1';
                        'ifw_api_arguments' = @{
                            '-Val' = @{ 'value' = '85'; 'order' = 1; };
                        };
                    };
                });
            } $script:TestBinDir;

            $PluginScriptRes['ExitCode']              | Should -Be 1;
            $PluginScriptRes['Output']                | Should -Match '\[WARNING\]';
            $PluginScriptRes['Output']                | Should -Match 'External Script Package';
            $PluginScriptRes['PerformanceData'].Count | Should -BeGreaterThan 0;
        }

        It 'enforces check_timeout and kills descendant processes when a binary hangs or spawns a background pipe holder' {
            [bool]$IsWindowsHost = ($env:OS -eq 'Windows_NT');
            [string]$HangFile    = '';
            [string]$BgPipeFile  = '';

            if ($IsWindowsHost) {
                $HangFile   = Join-Path -Path $script:TestBinDir -ChildPath 'check_hang.cmd';
                Set-Content -Path $HangFile -Value "@echo off`r`nping -n 15 127.0.0.1 >nul`r`nexit /b 0`r`n" -Encoding ASCII;

                $BgPipeFile = Join-Path -Path $script:TestBinDir -ChildPath 'check_bgpipe.cmd';
                Set-Content -Path $BgPipeFile -Value "@echo off`r`necho OK ^| m=1`r`nstart `"`" /b ping -n 15 127.0.0.1`r`nexit /b 0`r`n" -Encoding ASCII;
            } else {
                $HangFile   = Join-Path -Path $script:TestBinDir -ChildPath 'check_hang';
                [System.IO.File]::WriteAllText($HangFile, "#!/bin/sh`nsleep 10`nexit 0`n", (New-Object System.Text.UTF8Encoding $false));
                & /bin/chmod +x $HangFile;

                $BgPipeFile = Join-Path -Path $script:TestBinDir -ChildPath 'check_bgpipe';
                [System.IO.File]::WriteAllText($BgPipeFile, "#!/bin/sh`necho `"OK | m=1`"`nsleep 10 &`nexit 0`n", (New-Object System.Text.UTF8Encoding $false));
                & /bin/chmod +x $BgPipeFile;
            }

            $Timer                = [System.Diagnostics.Stopwatch]::StartNew();
            [hashtable]$HangRes   = & $script:IcingaModule {
                param ($B, $CmdName);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params @{
                    'command'       = 'hang-test';
                    'check_timeout' = 0.5;
                    'macros'        = @{ 'ifw_api_command' = $CmdName; };
                });
            } $script:TestBinDir ([System.IO.Path]::GetFileName($HangFile));
            $Timer.Stop();

            $HangRes['ExitCode']        | Should -Be 3;
            $HangRes['Output']          | Should -Match 'timed out';
            $Timer.Elapsed.TotalSeconds | Should -BeLessThan 5.0;

            $BgTimer              = [System.Diagnostics.Stopwatch]::StartNew();
            [hashtable]$BgPipeRes = & $script:IcingaModule {
                param ($B, $CmdName);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params @{
                    'command'       = 'bgpipe-test';
                    'check_timeout' = 0.5;
                    'macros'        = @{ 'ifw_api_command' = $CmdName; };
                });
            } $script:TestBinDir ([System.IO.Path]::GetFileName($BgPipeFile));
            $BgTimer.Stop();

            $BgPipeRes['ExitCode']        | Should -Be 3;
            $BgPipeRes['Output']          | Should -Match 'timed out';
            $BgTimer.Elapsed.TotalSeconds | Should -BeLessThan 5.0;
        }

        It 'executes native OS processes by full path, falls back to stderr when stdout is empty, and guards .cmd/.bat metacharacters' {
            [bool]$IsWindowsHost = ($env:OS -eq 'Windows_NT');
            [string]$NativeFile  = '';
            [string]$StderrFile  = '';
            [string]$BatchFile   = Join-Path -Path $script:TestBinDir -ChildPath 'check_meta.cmd';

            if ($IsWindowsHost) {
                $NativeFile      = Join-Path -Path $script:TestBinDir -ChildPath 'check_native.cmd';
                [string]$CmdBody = "@echo off`r`necho NATIVE CRITICAL %~1 %~2 ^| 'load avg'=2.50;1.50;2.00;0;`r`nexit /b 2`r`n";
                Set-Content -Path $NativeFile -Value $CmdBody -Encoding ASCII;

                $StderrFile      = Join-Path -Path $script:TestBinDir -ChildPath 'check_stderr.cmd';
                [string]$ErrBody = "@echo off`r`necho STDERR WARNING ^| err_count=1 >&2`r`nexit /b 1`r`n";
                Set-Content -Path $StderrFile -Value $ErrBody -Encoding ASCII;

                Set-Content -Path $BatchFile -Value "@echo off`r`necho THRESH %~1 %~2 %~3 %~4`r`nexit /b 0`r`n" -Encoding ASCII;
            } else {
                $NativeFile      = Join-Path -Path $script:TestBinDir -ChildPath 'check_native';
                [string]$ShBody  = "#!/bin/sh`necho `"NATIVE CRITICAL `$1 `$2 | 'load avg'=2.50;1.50;2.00;0;`"`nexit 2`n";
                [System.IO.File]::WriteAllText($NativeFile, $ShBody, (New-Object System.Text.UTF8Encoding $false));
                & /bin/chmod +x $NativeFile;

                $StderrFile      = Join-Path -Path $script:TestBinDir -ChildPath 'check_stderr';
                [string]$ErrBody = "#!/bin/sh`necho `"STDERR WARNING | err_count=1`" >&2`nexit 1`n";
                [System.IO.File]::WriteAllText($StderrFile, $ErrBody, (New-Object System.Text.UTF8Encoding $false));
                & /bin/chmod +x $StderrFile;

                [System.IO.File]::WriteAllText($BatchFile, "#!/bin/sh`necho `"THRESH `$1 `$2 `$3 `$4`"`nexit 0`n", (New-Object System.Text.UTF8Encoding $false));
                & /bin/chmod +x $BatchFile;
            }

            [hashtable]$NativeParams     = @{
                'command'       = 'ifw-native';
                'check_timeout' = 10;
                'macros'        = @{
                    'ifw_api_command'   = [System.IO.Path]::GetFileName($NativeFile);
                    'msg'               = 'hello world';
                    'ifw_api_arguments' = @{
                        '-m' = @{ 'value' = '$msg$'; 'order' = 1; };
                    };
                };
            };

            [hashtable]$StderrParams     = @{
                'command'       = 'ifw-stderr';
                'check_timeout' = 99999999;
                'macros'        = @{
                    'ifw_api_command' = [System.IO.Path]::GetFileName($StderrFile);
                };
            };

            [hashtable]$InjectedBatch    = @{
                'command' = 'ifw-batch-inject';
                'macros'  = @{
                    'ifw_api_command'   = 'check_meta.cmd';
                    'ifw_api_arguments' = @{
                        '-w' = @{ 'value' = '80%&whoami'; 'order' = 1; };
                    };
                };
            };

            [hashtable]$EnvExpandBatch   = @{
                'command' = 'ifw-batch-env';
                'macros'  = @{
                    'ifw_api_command'   = 'check_meta.cmd';
                    'ifw_api_arguments' = @{
                        '-w' = @{ 'value' = '%TEMP%'; 'order' = 1; };
                    };
                };
            };

            [hashtable]$SpaceSubstBatch  = @{
                'command' = 'ifw-batch-subst';
                'macros'  = @{
                    'ifw_api_command'   = 'check_meta.cmd';
                    'ifw_api_arguments' = @{
                        '-w' = @{ 'value' = '%COMSPEC: =%'; 'order' = 1; };
                    };
                };
            };

            [hashtable]$SafePercentBatch = @{
                'command' = 'ifw-batch-safe';
                'macros'  = @{
                    'ifw_api_command'   = 'check_meta.cmd';
                    'ifw_api_arguments' = @{
                        '-w' = @{ 'value' = '80%'; 'order' = 1; };
                        '-c' = @{ 'value' = '90%'; 'order' = 2; };
                    };
                };
            };

            [hashtable]$NativeRes        = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $NativeParams $script:TestBinDir;

            [hashtable]$StderrRes        = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $StderrParams $script:TestBinDir;

            [hashtable]$InjectedRes      = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $InjectedBatch $script:TestBinDir;

            [hashtable]$EnvExpandRes     = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $EnvExpandBatch $script:TestBinDir;

            [hashtable]$SpaceSubstRes    = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $SpaceSubstBatch $script:TestBinDir;

            [hashtable]$SafePercentRes   = & $script:IcingaModule {
                param ($P, $B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params $P);
            } $SafePercentBatch $script:TestBinDir;

            $NativeRes['ExitCode']        | Should -Be 2;
            $NativeRes['Output']          | Should -Be 'NATIVE CRITICAL -m hello world';
            $NativeRes['PerformanceData'] | Should -Be @( "'load avg'=2.50;1.50;2.00;0;" );
            $NativeRes['CommandLine']     | Should -Match '"hello world"';

            $StderrRes['ExitCode']        | Should -Be 1;
            $StderrRes['Output']          | Should -Be 'STDERR WARNING';
            $StderrRes['PerformanceData'] | Should -Be @( 'err_count=1' );

            $InjectedRes['ExitCode']      | Should -Be 3;
            $InjectedRes['Output']        | Should -Match 'metacharacters';

            $EnvExpandRes['ExitCode']     | Should -Be 3;
            $EnvExpandRes['Output']       | Should -Match 'metacharacters';

            $SpaceSubstRes['ExitCode']    | Should -Be 3;
            $SpaceSubstRes['Output']      | Should -Match 'metacharacters';

            $SafePercentRes['ExitCode']   | Should -Be 0;
            $SafePercentRes['Output']     | Should -Be 'THRESH -w 80% -c 90%';
        }
    }

    Context 'UNKNOWN error handling with IWKB001000..IWKB001003' {
        It 'returns ExitCode 3 and IWKB001003 for unmodified ITL load-windows without ifw_api_command' {
            [hashtable]$Res = & $script:IcingaModule {
                param ($B);
                function Get-ModuleBinaryDirectory()
                {
                    return $B;
                }
                return (Invoke-IcingaProtocolCheckCommand -Params @{ 'command' = 'load-windows'; 'macros' = @{ }; });
            } $script:TestBinDir;

            $Res['ExitCode'] | Should -Be 3;
            $Res['Output']   | Should -Match 'IWKB001003';
            $Res['Output']   | Should -Match 'load-windows';
        }
    }

    Context 'Start-IcingaProtocolWorker ExecuteCommand dispatch and timing' {
        It 'measures execution_start/execution_end and dispatches CheckResult via Send-IcingaProtocolCheckResult' {
            Set-Content -Path (Join-Path -Path $script:TestDataDir -ChildPath 'item.log') -Value 'ok' -Encoding UTF8;

            [hashtable]$Dispatched = & $script:IcingaModule {
                param ($DataDir, $BinDir);

                $GlobalVar              = Get-GlobalRuntimeVariable;
                $PrevQueue              = $GlobalVar.Public.IcingaProtocol.WorkerQueue;
                $PrevHost               = $GlobalVar.Public.IcingaProtocol.Config.Hostname;
                $script:WorkerLoopCalls = 0;
                $script:SentCheckResult = $null;

                function Get-ModuleBinaryDirectory()
                {
                    return $BinDir;
                }

                function Test-ThreadRunning()
                {
                    param (
                        [switch]$NoSleep = $false
                    );

                    $script:WorkerLoopCalls++;
                    return ($script:WorkerLoopCalls -le 1);
                }

                function Set-ThreadProcessing()
                {
                }

                function Set-TCPClientAndStream()
                {
                    param (
                        $TcpClient = $null,
                        $SslStream = $null
                    );
                }

                function Send-IcingaProtocolCheckResult()
                {
                    param (
                        [hashtable]$CheckResult = @{ }
                    );

                    $script:SentCheckResult = $CheckResult;
                }

                try {
                    $QueueList = New-Object System.Collections.ArrayList;
                    $Queue     = New-Object 'System.Collections.Concurrent.BlockingCollection[PSObject]' -ArgumentList (New-Object 'System.Collections.Concurrent.ConcurrentQueue[PSObject]');
                    [void]$QueueList.Add($Queue);

                    $GlobalVar.Public.IcingaProtocol.WorkerQueue     = $QueueList;
                    $GlobalVar.Public.IcingaProtocol.Config.Hostname = 'win-agent-01.local';

                    $Queue.Add([PSCustomObject]@{
                        'Message' = @{
                            'method' = 'event::ExecuteCommand';
                            'params' = @{
                                'host'    = 'win-agent-01.local';
                                'service' = 'Logs Check';
                                'command' = 'Invoke-IcingaCheckDirectory';
                                'macros'  = @{
                                    'ifw_api_command' = 'Invoke-IcingaCheckDirectory';
                                    'Path'            = $DataDir;
                                    'FileNames'       = @( '*.log' );
                                };
                            };
                        };
                        'Client' = $null;
                        'Stream' = $null;
                    });

                    Start-IcingaProtocolWorker -WorkerId 0;
                    return $script:SentCheckResult;
                } finally {
                    $GlobalVar.Public.IcingaProtocol.WorkerQueue     = $PrevQueue;
                    $GlobalVar.Public.IcingaProtocol.Config.Hostname = $PrevHost;
                }
            } $script:TestDataDir $script:TestBinDir;

            $Dispatched                                                                    | Should -Not -BeNullOrEmpty;
            $Dispatched['host']                                                            | Should -Be 'win-agent-01.local';
            $Dispatched['service']                                                         | Should -Be 'Logs Check';
            $Dispatched['cr']['check_source']                                              | Should -Be 'win-agent-01.local';
            $Dispatched['cr']['exit_status']                                               | Should -Be 0;
            $Dispatched['cr']['state']                                                     | Should -Be 0;
            $Dispatched['cr']['type']                                                      | Should -Be 'CheckResult';
            $Dispatched['cr']['command']                                                   | Should -Match '^Invoke-IcingaCheckDirectory ';
            ($Dispatched['cr']['execution_end'] -ge $Dispatched['cr']['execution_start'])  | Should -BeTrue;
        }

        It 'omits the service key for Icinga 2 Host checks and falls back check_source to host when Config.Hostname is unset' {
            Set-Content -Path (Join-Path -Path $script:TestDataDir -ChildPath 'host.log') -Value 'ok' -Encoding UTF8;

            [hashtable]$HostDispatched = & $script:IcingaModule {
                param ($DataDir, $BinDir);

                $GlobalVar              = Get-GlobalRuntimeVariable;
                $PrevQueue              = $GlobalVar.Public.IcingaProtocol.WorkerQueue;
                $PrevHost               = $GlobalVar.Public.IcingaProtocol.Config.Hostname;
                $script:HostLoopCalls   = 0;
                $script:HostSentResult  = $null;

                function Get-ModuleBinaryDirectory()
                {
                    return $BinDir;
                }

                function Test-ThreadRunning()
                {
                    param (
                        [switch]$NoSleep = $false
                    );

                    $script:HostLoopCalls++;
                    return ($script:HostLoopCalls -le 1);
                }

                function Set-ThreadProcessing()
                {
                }

                function Set-TCPClientAndStream()
                {
                    param (
                        $TcpClient = $null,
                        $SslStream = $null
                    );
                }

                function Send-IcingaProtocolCheckResult()
                {
                    param (
                        [hashtable]$CheckResult = @{ }
                    );

                    $script:HostSentResult = $CheckResult;
                }

                try {
                    $QueueList = New-Object System.Collections.ArrayList;
                    $Queue     = New-Object 'System.Collections.Concurrent.BlockingCollection[PSObject]' -ArgumentList (New-Object 'System.Collections.Concurrent.ConcurrentQueue[PSObject]');
                    [void]$QueueList.Add($Queue);

                    $GlobalVar.Public.IcingaProtocol.WorkerQueue     = $QueueList;
                    $GlobalVar.Public.IcingaProtocol.Config.Hostname = '';

                    $Queue.Add([PSCustomObject]@{
                        'Message' = @{
                            'method' = 'event::ExecuteCommand';
                            'params' = @{
                                'host'    = 'win-hostcheck.local';
                                'command' = 'Invoke-IcingaCheckDirectory';
                                'macros'  = @{
                                    'ifw_api_command' = 'Invoke-IcingaCheckDirectory';
                                    'Path'            = $DataDir;
                                    'FileNames'       = @( '*.log' );
                                };
                            };
                        };
                        'Client' = $null;
                        'Stream' = $null;
                    });

                    Start-IcingaProtocolWorker -WorkerId 0;
                    return $script:HostSentResult;
                } finally {
                    $GlobalVar.Public.IcingaProtocol.WorkerQueue     = $PrevQueue;
                    $GlobalVar.Public.IcingaProtocol.Config.Hostname = $PrevHost;
                }
            } $script:TestDataDir $script:TestBinDir;

            $HostDispatched                          | Should -Not -BeNullOrEmpty;
            $HostDispatched['host']                  | Should -Be 'win-hostcheck.local';
            $HostDispatched.ContainsKey('service')   | Should -BeFalse;
            $HostDispatched['cr']['check_source']    | Should -Be 'win-hostcheck.local';
            $HostDispatched['cr']['exit_status']     | Should -Be 0;
        }

        It 'dispatches ExecuteCommand payloads deserialized as Dictionary[string, object] on Windows PowerShell 5.1' {
            Set-Content -Path (Join-Path -Path $script:TestDataDir -ChildPath 'ps51.log') -Value 'ok' -Encoding UTF8;

            [hashtable]$Ps51Dispatched = & $script:IcingaModule {
                param ($DataDir, $BinDir);

                $GlobalVar              = Get-GlobalRuntimeVariable;
                $PrevQueue              = $GlobalVar.Public.IcingaProtocol.WorkerQueue;
                $PrevHost               = $GlobalVar.Public.IcingaProtocol.Config.Hostname;
                $script:Ps51LoopCalls   = 0;
                $script:Ps51SentResult  = $null;

                function Get-ModuleBinaryDirectory()
                {
                    return $BinDir;
                }

                function Test-ThreadRunning()
                {
                    param (
                        [switch]$NoSleep = $false
                    );

                    $script:Ps51LoopCalls++;
                    return ($script:Ps51LoopCalls -le 1);
                }

                function Set-ThreadProcessing()
                {
                }

                function Set-TCPClientAndStream()
                {
                    param (
                        $TcpClient = $null,
                        $SslStream = $null
                    );
                }

                function Send-IcingaProtocolCheckResult()
                {
                    param (
                        [hashtable]$CheckResult = @{ }
                    );

                    $script:Ps51SentResult = $CheckResult;
                }

                try {
                    $QueueList = New-Object System.Collections.ArrayList;
                    $Queue     = New-Object 'System.Collections.Concurrent.BlockingCollection[PSObject]' -ArgumentList (New-Object 'System.Collections.Concurrent.ConcurrentQueue[PSObject]');
                    [void]$QueueList.Add($Queue);

                    $GlobalVar.Public.IcingaProtocol.WorkerQueue     = $QueueList;
                    $GlobalVar.Public.IcingaProtocol.Config.Hostname = 'win-ps51-agent.local';

                    $MsgDict                       = New-Object 'System.Collections.Generic.Dictionary[string, object]';
                    $ParamsDict                    = New-Object 'System.Collections.Generic.Dictionary[string, object]';
                    $MacrosDict                    = New-Object 'System.Collections.Generic.Dictionary[string, object]';
                    $MacrosDict['ifw_api_command'] = 'Invoke-IcingaCheckDirectory';
                    $MacrosDict['Path']            = $DataDir;
                    $MacrosDict['FileNames']       = [object[]]@( '*.log' );
                    $ParamsDict['host']            = 'win-ps51-agent.local';
                    $ParamsDict['service']         = 'PS51 Logs Check';
                    $ParamsDict['command']         = 'Invoke-IcingaCheckDirectory';
                    $ParamsDict['macros']          = $MacrosDict;
                    $MsgDict['method']             = 'event::ExecuteCommand';
                    $MsgDict['params']             = $ParamsDict;

                    $Queue.Add([PSCustomObject]@{
                        'Message' = $MsgDict;
                        'Client'  = $null;
                        'Stream'  = $null;
                    });

                    Start-IcingaProtocolWorker -WorkerId 0;
                    return $script:Ps51SentResult;
                } finally {
                    $GlobalVar.Public.IcingaProtocol.WorkerQueue     = $PrevQueue;
                    $GlobalVar.Public.IcingaProtocol.Config.Hostname = $PrevHost;
                }
            } $script:TestDataDir $script:TestBinDir;

            $Ps51Dispatched                       | Should -Not -BeNullOrEmpty;
            $Ps51Dispatched['host']               | Should -Be 'win-ps51-agent.local';
            $Ps51Dispatched['service']            | Should -Be 'PS51 Logs Check';
            $Ps51Dispatched['cr']['check_source'] | Should -Be 'win-ps51-agent.local';
            $Ps51Dispatched['cr']['exit_status']  | Should -Be 0;
        }
    }
}

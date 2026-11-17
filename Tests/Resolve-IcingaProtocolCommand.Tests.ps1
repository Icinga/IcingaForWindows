<#
.SYNOPSIS
Pester unit test suite for Resolve-IcingaProtocolCommand in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for Resolve-IcingaProtocolCommand
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

Describe 'Resolve-IcingaProtocolCommand' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        function Invoke-TestCommandResolution()
        {
            param (
                [object]$Macros       = $null,
                [string]$CheckCommand = '',
                [string]$BinaryDir    = ''
            );

            return (& $script:IcingaModule {
                param ($MacrosArg, $CheckCmdArg, $BinDirArg);

                function Get-ModuleBinaryDirectory()
                {
                    return $BinDirArg;
                }

                return (Resolve-IcingaProtocolCommand -Macros $MacrosArg -CheckCommand $CheckCmdArg);
            } $Macros $CheckCommand $BinaryDir);
        }
    }

    BeforeEach {
        $script:TestBinDir = Join-Path -Path $TestDrive -ChildPath ('Binaries_' + [System.Guid]::NewGuid().ToString('N'));
        New-Item -Path $script:TestBinDir -ItemType Directory -Force | Out-Null;
    }

    Context 'Mandatory ifw_api_command enforcement (IWKB001003)' {
        It 'returns CommandMissing with IWKB001003 when macros are empty (unmodified ITL load-windows)' {
            [hashtable]$Result = Invoke-TestCommandResolution -Macros @{ } -CheckCommand 'load-windows' -BinaryDir $script:TestBinDir;

            $Result['Status']          | Should -Be 'CommandMissing';
            $Result['KnowledgeBaseId'] | Should -Be 'IWKB001003';
            $Result['ReturnCodeKey']   | Should -Be 'IcingaProtocolCommandMissing';
            $Result['Message']         | Should -Match 'load-windows';
            $Result['Message']         | Should -Match 'IWKB001003';
        }

        It 'returns CommandMissing when Macros is $null or ifw_api_command is whitespace' {
            [hashtable]$NullResult  = Invoke-TestCommandResolution -Macros $null -BinaryDir $script:TestBinDir;
            [hashtable]$BlankResult = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = '   '; } -BinaryDir $script:TestBinDir;

            $NullResult['Status']  | Should -Be 'CommandMissing';
            $BlankResult['Status'] | Should -Be 'CommandMissing';
        }
    }

    Context 'PowerShell check plugin resolution and shorthand expansion' {
        It 'resolves an explicit Invoke-IcingaCheck* function with parameter metadata' {
            [hashtable]$Result = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheckDirectory'; } -BinaryDir $script:TestBinDir;

            $Result['Status']                         | Should -Be 'Ok';
            $Result['Kind']                           | Should -Be 'PowerShell';
            $Result['CommandName']                    | Should -Be 'Invoke-IcingaCheckDirectory';
            $Result['Parameters'].ContainsKey('Path') | Should -BeTrue;
        }

        It 'expands shorthand names from Hashtable and PSCustomObject macros when no binary exists in Binaries' {
            [hashtable]$CpuResult = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'cpu'; } -BinaryDir $script:TestBinDir;
            [hashtable]$DirResult = Invoke-TestCommandResolution -Macros ([PSCustomObject]@{ 'ifw_api_command' = 'IcingaCheckDirectory'; }) -BinaryDir $script:TestBinDir;

            $CpuResult['Status']      | Should -Be 'Ok';
            $CpuResult['Kind']        | Should -Be 'PowerShell';
            $CpuResult['CommandName'] | Should -Be 'Invoke-IcingaCheckCPU';

            $DirResult['Status']      | Should -Be 'Ok';
            $DirResult['Kind']        | Should -Be 'PowerShell';
            $DirResult['CommandName'] | Should -Be 'Invoke-IcingaCheckDirectory';
        }

        It 'rejects non-check PowerShell cmdlets and wildcard patterns with IWKB001003' {
            [hashtable]$RemoveResult = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'Remove-Item'; } -BinaryDir $script:TestBinDir;
            [hashtable]$ProcResult   = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'Get-Process'; } -BinaryDir $script:TestBinDir;
            [hashtable]$WildResult   = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheck*'; } -BinaryDir $script:TestBinDir;

            $RemoveResult['Status']          | Should -Be 'CommandNotFound';
            $RemoveResult['KnowledgeBaseId'] | Should -Be 'IWKB001003';
            $ProcResult['Status']            | Should -Be 'CommandNotFound';
            $WildResult['Status']            | Should -Be 'CommandNotFound';
        }
    }

    Context 'Strict full-path Binary lookup and Path-Traversal rejection' {
        It 'resolves binaries inside Get-ModuleBinaryDirectory with explicit or probed extensions' {
            [string]$ExeFile     = Join-Path -Path $script:TestBinDir -ChildPath 'check_load.exe';
            [string]$CmdFile     = Join-Path -Path $script:TestBinDir -ChildPath 'check_load.cmd';
            [string]$DottedFile  = Join-Path -Path $script:TestBinDir -ChildPath 'check_app_v1.2.exe';
            Set-Content -Path $ExeFile -Value 'stub' -Encoding UTF8;
            Set-Content -Path $CmdFile -Value 'stub' -Encoding UTF8;
            Set-Content -Path $DottedFile -Value 'stub' -Encoding UTF8;

            [hashtable]$Explicit = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'check_load.cmd'; } -BinaryDir $script:TestBinDir;
            [hashtable]$Probed   = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'check_load'; } -BinaryDir $script:TestBinDir;
            [hashtable]$Dotted   = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'check_app_v1.2'; } -BinaryDir $script:TestBinDir;

            $Explicit['Status']     | Should -Be 'Ok';
            $Explicit['Kind']       | Should -Be 'Binary';
            $Explicit['BinaryPath'] | Should -Be ([System.IO.Path]::GetFullPath($CmdFile));

            $Probed['Status']       | Should -Be 'Ok';
            $Probed['Kind']         | Should -Be 'Binary';
            $Probed['CommandName']  | Should -Be 'check_load.exe';
            $Probed['BinaryPath']   | Should -Be ([System.IO.Path]::GetFullPath($ExeFile));

            $Dotted['Status']       | Should -Be 'Ok';
            $Dotted['Kind']         | Should -Be 'Binary';
            $Dotted['CommandName']  | Should -Be 'check_app_v1.2.exe';
            $Dotted['BinaryPath']   | Should -Be ([System.IO.Path]::GetFullPath($DottedFile));
        }

        It 'gives files inside Get-ModuleBinaryDirectory precedence over shorthand expansion' {
            [string]$CustomCpuScript = Join-Path -Path $script:TestBinDir -ChildPath 'cpu.ps1';
            Set-Content -Path $CustomCpuScript -Value 'exit 0' -Encoding UTF8;

            [hashtable]$Result       = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'cpu'; } -BinaryDir $script:TestBinDir;

            $Result['Status']      | Should -Be 'Ok';
            $Result['Kind']        | Should -Be 'Binary';
            $Result['CommandName'] | Should -Be 'cpu.ps1';
            $Result['BinaryPath']  | Should -Be ([System.IO.Path]::GetFullPath($CustomCpuScript));
        }

        It 'rejects path traversal, sibling-prefix tricks and system paths outside Binaries with IWKB001003' {
            [string]$SiblingDir   = $script:TestBinDir + 'Evil';
            New-Item -Path $SiblingDir -ItemType Directory -Force | Out-Null;
            [string]$SiblingFile  = Join-Path -Path $SiblingDir -ChildPath 'evil.exe';
            Set-Content -Path $SiblingFile -Value 'stub' -Encoding UTF8;

            [hashtable]$Traversal = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = '..\evil.exe'; } -BinaryDir $script:TestBinDir;
            [hashtable]$Sibling   = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = $SiblingFile; } -BinaryDir $script:TestBinDir;
            [hashtable]$WinSys    = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'C:\Windows\System32\cmd.exe'; } -BinaryDir $script:TestBinDir;
            [hashtable]$UnixSys   = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = '/bin/sh'; } -BinaryDir $script:TestBinDir;
            [hashtable]$UncPath   = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = '\\attacker\share\tool.exe'; } -BinaryDir $script:TestBinDir;

            $Traversal['Status']          | Should -Be 'BinaryPathRejected';
            $Traversal['KnowledgeBaseId'] | Should -Be 'IWKB001003';
            $Sibling['Status']            | Should -Be 'BinaryPathRejected';
            $WinSys['Status']             | Should -Be 'BinaryPathRejected';
            $UnixSys['Status']            | Should -Be 'BinaryPathRejected';
            $UncPath['Status']            | Should -Be 'BinaryPathRejected';
        }

        It 'rejects NTFS Alternate Data Stream colons, drive-relative colons and ASCII control characters' {
            [string]$ValidBin       = Join-Path -Path $script:TestBinDir -ChildPath 'check_load.exe';
            Set-Content -Path $ValidBin -Value 'stub' -Encoding UTF8;

            [hashtable]$AdsRel      = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'check_load.exe:stream'; } -BinaryDir $script:TestBinDir;
            [hashtable]$AdsFull     = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = ($ValidBin + ':stream'); } -BinaryDir $script:TestBinDir;
            [hashtable]$DriveRel    = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'C:evil.exe'; } -BinaryDir $script:TestBinDir;
            [hashtable]$CtrlNewline = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = "check_load.exe`nwhoami"; } -BinaryDir $script:TestBinDir;
            [hashtable]$CtrlNull    = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = ("check_load.exe" + [char]0 + '.txt'); } -BinaryDir $script:TestBinDir;
            [hashtable]$PathWild    = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = '..\*.exe'; } -BinaryDir $script:TestBinDir;
            [hashtable]$PipeInvalid = Invoke-TestCommandResolution -Macros @{ 'ifw_api_command' = 'check_load|evil.exe'; } -BinaryDir $script:TestBinDir;

            $AdsRel['Status']          | Should -Be 'BinaryPathRejected';
            $AdsRel['KnowledgeBaseId'] | Should -Be 'IWKB001003';
            $AdsFull['Status']         | Should -Be 'BinaryPathRejected';
            $DriveRel['Status']        | Should -Be 'BinaryPathRejected';
            $CtrlNewline['Status']     | Should -Be 'BinaryPathRejected';
            $CtrlNull['Status']        | Should -Be 'BinaryPathRejected';
            $PathWild['Status']        | Should -Be 'BinaryPathRejected';
            $PipeInvalid['Status']     | Should -Be 'BinaryPathRejected';
        }
    }

    Context 'Binary directory environment and secure child enumeration' {
        It 'resolves Get-ModuleBinaryDirectory and creates Config and Binaries via New-ModuleConfigEnvironment' {
            [string]$MockProgramData = Join-Path -Path $TestDrive -ChildPath ('ProgData_' + [System.Guid]::NewGuid().ToString('N'));
            New-Item -Path $MockProgramData -ItemType Directory -Force | Out-Null;

            [hashtable]$EnvOutcome   = & $script:IcingaModule {
                param ($TempProgData);

                [string]$PrevProgramData = $env:ProgramData;
                try {
                    $env:ProgramData   = $TempProgData;
                    [string]$BinDir    = Get-ModuleBinaryDirectory;
                    [string]$CfgDir    = Get-ModuleConfigDirectory;
                    $FirstCode         = New-ModuleConfigEnvironment;
                    $SecondCode        = New-ModuleConfigEnvironment;

                    return @{
                        'BinDir'     = $BinDir;
                        'CfgDir'     = $CfgDir;
                        'BinExists'  = (Test-Path -Path $BinDir -PathType Container);
                        'CfgExists'  = (Test-Path -Path $CfgDir -PathType Container);
                        'FirstCode'  = $FirstCode;
                        'SecondCode' = $SecondCode;
                    };
                } finally {
                    $env:ProgramData = $PrevProgramData;
                }
            } $MockProgramData;

            [string]$ExpectedBin     = Join-Path -Path $MockProgramData -ChildPath (Join-Path -Path 'IcingaForWindows' -ChildPath 'Binaries');
            $EnvOutcome['BinDir']                  | Should -Be $ExpectedBin;
            $EnvOutcome['BinExists']               | Should -BeTrue;
            $EnvOutcome['CfgExists']               | Should -BeTrue;
            ($EnvOutcome['FirstCode'] -is [int])   | Should -BeTrue;
            $EnvOutcome['FirstCode']               | Should -Be 0;
            $EnvOutcome['SecondCode']              | Should -Be 0;
        }

        It 'allows Get-SecureChildItem inside Get-ModuleBinaryDirectory and rejects unapproved paths once' {
            [string]$MockProgramData = Join-Path -Path $TestDrive -ChildPath ('SecProg_' + [System.Guid]::NewGuid().ToString('N'));
            [string]$OutsideDir      = Join-Path -Path $TestDrive -ChildPath ('Outside_' + [System.Guid]::NewGuid().ToString('N'));
            New-Item -Path $MockProgramData -ItemType Directory -Force | Out-Null;
            New-Item -Path $OutsideDir -ItemType Directory -Force | Out-Null;
            Set-Content -Path (Join-Path -Path $OutsideDir -ChildPath 'secret.txt') -Value 'nope' -Encoding UTF8;

            [hashtable]$SecOutcome   = & $script:IcingaModule {
                param ($TempProgData, $UnapprovedPath);

                [string]$PrevProgramData = $env:ProgramData;
                try {
                    $env:ProgramData      = $TempProgData;
                    [void](New-ModuleConfigEnvironment);
                    [string]$BinDir       = Get-ModuleBinaryDirectory;
                    Set-Content -Path (Join-Path -Path $BinDir -ChildPath 'check_demo.exe') -Value 'bin' -Encoding UTF8;

                    $ApprovedItems        = @(Get-SecureChildItem -Path $BinDir -File);
                    $script:ApproveChecks = 0;
                    $RealApproveCmd       = Get-Command -Name 'Test-SecureApprovedPath' -CommandType Function;

                    function Test-SecureApprovedPath()
                    {
                        param (
                            [string]$Path        = '',
                            [array]$ApprovedPath = @()
                        );

                        $script:ApproveChecks++;
                        return (& $RealApproveCmd -Path $Path -ApprovedPath $ApprovedPath);
                    }

                    $DeniedResult = Get-SecureChildItem -Path $UnapprovedPath -File;

                    return @{
                        'ApprovedCount' = $ApprovedItems.Count;
                        'ApprovedName'  = [string]$ApprovedItems[0].Name;
                        'DeniedResult'  = $DeniedResult;
                        'ApproveChecks' = $script:ApproveChecks;
                    };
                } finally {
                    $env:ProgramData = $PrevProgramData;
                }
            } $MockProgramData $OutsideDir;

            $SecOutcome['ApprovedCount'] | Should -Be 1;
            $SecOutcome['ApprovedName']  | Should -Be 'check_demo.exe';
            $SecOutcome['DeniedResult']  | Should -BeNullOrEmpty;
            $SecOutcome['ApproveChecks'] | Should -Be 1;
        }
    }
}

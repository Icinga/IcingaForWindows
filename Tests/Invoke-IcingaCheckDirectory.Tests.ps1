<#
.SYNOPSIS
Pester unit test suite for Invoke-IcingaCheckDirectory in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for Invoke-IcingaCheckDirectory
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

Describe 'Invoke-IcingaCheckDirectory' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Builds a result in the shape of Get-IcingaDirectoryInformation.
        function New-TestDirectoryData()
        {
            param (
                [int]$FileCount     = 0,
                [int]$FolderCount   = 0,
                [long]$TotalSize    = 0,
                [long]$SmallestFile = 0,
                [long]$LargestFile  = 0,
                [array]$FileList    = @()
            );

            [double]$Average = 0;

            if ($FileCount -ne 0) {
                $Average = [System.Math]::Round($TotalSize / $FileCount, 2);
            }

            return @{
                'Path'         = 'C:\Backup';
                'Exists'       = $true;
                'FileCount'    = $FileCount;
                'FolderCount'  = $FolderCount;
                'TotalCount'   = $FileCount + $FolderCount;
                'TotalSize'    = $TotalSize;
                'LargestFile'  = $LargestFile;
                'SmallestFile' = $SmallestFile;
                'AverageSize'  = $Average;
                'FileList'     = $FileList;
            };
        }

        # Runs the plugin inside the module scope with Get-IcingaDirectoryInformation
        # shadowed by a function, which records the arguments it was called with.
        function Invoke-TestDirectoryCheck()
        {
            param (
                $StubData             = $null,
                [hashtable]$Arguments = @{ },
                [switch]$Fail         = $false
            );

            return (& $script:IcingaModule {
                param ($StubData, $Arguments, $Fail);

                function Get-IcingaDirectoryInformation()
                {
                    param (
                        [string]$Path                = '',
                        [array]$FileNames            = @( '*' ),
                        [switch]$Recurse             = $false,
                        [string]$ChangeTimeEqual     = '',
                        [string]$ChangeYoungerThan   = '',
                        [string]$ChangeOlderThan     = '',
                        [string]$CreationTimeEqual   = '',
                        [string]$CreationYoungerThan = '',
                        [string]$CreationOlderThan   = '',
                        [string]$AccessYoungerThan   = '',
                        [string]$AccessOlderThan     = '',
                        [string]$FileSizeGreaterThan = '',
                        [string]$FileSizeSmallerThan = '',
                        [switch]$IncludeFileList     = $false,
                        [switch]$IgnoreMissingPath   = $false
                    );

                    $Global:IcingaTestDirectoryCall = $PSBoundParameters;

                    if ($Fail) {
                        return [IcingaError]::new('DirectoryAccessDenied', 'Access to the directory "C:\Backup" was denied', @{ });
                    }

                    return $StubData;
                }

                Invoke-IcingaCheckDirectory @Arguments;
            } $StubData $Arguments $Fail);
        }

        # 3 files of 1KiB, 2KiB and 3KiB, one folder.
        $script:Backup = New-TestDirectoryData -FileCount 3 -FolderCount 1 -TotalSize 6144 -SmallestFile 1024 -LargestFile 3072;
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
        Remove-Variable -Name 'IcingaTestDirectoryCall' -Scope Global -ErrorAction Ignore;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    It 'writes one metric per statistic with the path as index' {
        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'Warning' = '5'; 'Critical' = '10'; } | Should -Be 0;

        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
            'cbackup::ifw_directory::files=3;5;10;;',
            'cbackup::ifw_directory::folders=1;;;;',
            'cbackup::ifw_directory::totalsize=6144B;;;;',
            'cbackup::ifw_directory::smallestfile=1024B;;;;',
            'cbackup::ifw_directory::largestfile=3072B;;;;',
            'cbackup::ifw_directory::averagefile=2048B;;;;'
        );
    }

    It 'lists every statistic and the informational file found entry' {
        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'Verbosity' = 2; } | Should -Be 0;

        [array]$Lines = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output -split "`n";
        $Lines[0] | Should -Be '[OK] Directory Check: "C:\Backup": 6 Ok';
        $Lines[1] | Should -Be '\_ [OK] File Count: 3 is ok';
        $Lines[3] | Should -Be '\_ [OK] Total Size: 6KiB is ok';
        $Lines[6] | Should -Be '\_ [OK] Average File Size: 2KiB is ok';
        $Lines[7] | Should -Be '\_ [INFO] File Found: Yes';
    }

    It 'raises the state when the file count or a size breaches its threshold' {
        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'Critical' = '2'; 'WarningTotalSize' = '5KiB'; } | Should -Be 2;

        $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
        $Output | Should -Match ([regex]::Escape('[CRITICAL] Directory Check: "C:\Backup": 1 Critical 1 Warning 4 Ok'));
        $Output | Should -Match ([regex]::Escape('[CRITICAL] File Count: 3 is greater than threshold 2'));
        $Output | Should -Match ([regex]::Escape('[WARNING] Total Size: 6KiB is greater than threshold 5KiB'));
    }

    It 'adds the folders to the file count with CountFolderAsFile' {
        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'Critical' = '3'; 'CountFolderAsFile' = $true; } | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'cbackup::ifw_directory::files=4;;3;;';
    }

    It 'passes the filters to the provider and treats a missing path as empty only with OverrideNotFound' {
        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'Recurse' = $true; 'FileNames' = @('*.bak'); 'ChangeOlderThan' = '1d'; 'FileSizeGreaterThan' = '1MB'; } | Out-Null;

        $Global:IcingaTestDirectoryCall['Recurse']             | Should -BeTrue;
        $Global:IcingaTestDirectoryCall['FileNames']           | Should -Be @('*.bak');
        $Global:IcingaTestDirectoryCall['ChangeOlderThan']     | Should -Be '1d';
        $Global:IcingaTestDirectoryCall['FileSizeGreaterThan'] | Should -Be '1MB';
        $Global:IcingaTestDirectoryCall['IgnoreMissingPath']   | Should -BeFalse;
        $Global:IcingaTestDirectoryCall['IncludeFileList']     | Should -BeFalse;

        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'OverrideNotFound' = 'Critical'; } | Out-Null;
        $Global:IcingaTestDirectoryCall['IgnoreMissingPath'] | Should -BeTrue;
    }

    It 'reports the OverrideNotFound state when nothing matches' {
        $Empty = New-TestDirectoryData;

        Invoke-TestDirectoryCheck -StubData $Empty -Arguments @{ 'Path' = 'C:\Backup'; 'OverrideNotFound' = 'Critical'; } | Should -Be 2;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be "[CRITICAL] Directory Check: `"C:\Backup`": 1 Critical 6 Ok [CRITICAL] File Found`n\_ [CRITICAL] File Found: No";

        Invoke-TestDirectoryCheck -StubData $Empty -Arguments @{ 'Path' = 'C:\Backup'; 'OverrideNotFound' = 'Warning'; } | Should -Be 1;
        Invoke-TestDirectoryCheck -StubData $Empty -Arguments @{ 'Path' = 'C:\Backup'; 'OverrideNotFound' = 'Ok'; } | Should -Be 0;
        Invoke-TestDirectoryCheck -StubData $Empty -Arguments @{ 'Path' = 'C:\Backup'; } | Should -Be 0;
    }

    It 'reports OK for found files even with OverrideNotFound' {
        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'OverrideNotFound' = 'Critical'; 'Verbosity' = 2; } | Should -Be 0;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[OK] File Found: Yes'));
    }

    It 'reports a provider failure as UNKNOWN with its reason' {
        Invoke-TestDirectoryCheck -Fail -Arguments @{ 'Path' = 'C:\Backup'; } | Should -Be 3;
        $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Directory Check: "C:\Backup": Access to the directory "C:\Backup" was denied';
    }

    It 'lists the files sorted by path with ShowFileList without counting them' {
        [string]$ListRoot = Join-Path -Path $TestDrive -ChildPath 'list';
        New-Item -Path (Join-Path -Path $ListRoot -ChildPath 'folder') -ItemType Directory -Force | Out-Null;
        [System.IO.File]::WriteAllBytes((Join-Path -Path $ListRoot -ChildPath 'b.bak'), [byte[]]::new(2048));
        [System.IO.File]::WriteAllBytes((Join-Path -Path $ListRoot -ChildPath 'a.bak'), [byte[]]::new(1024));

        [array]$Entries   = @(
            [System.IO.FileInfo]::new((Join-Path -Path $ListRoot -ChildPath 'b.bak')),
            [System.IO.DirectoryInfo]::new((Join-Path -Path $ListRoot -ChildPath 'folder')),
            [System.IO.FileInfo]::new((Join-Path -Path $ListRoot -ChildPath 'a.bak'))
        );
        $Data             = New-TestDirectoryData -FileCount 2 -FolderCount 1 -TotalSize 3072 -SmallestFile 1024 -LargestFile 2048 -FileList $Entries;

        Invoke-TestDirectoryCheck -StubData $Data -Arguments @{ 'Path' = 'C:\Backup'; 'ShowFileList' = $true; } | Should -Be 0;

        $Global:IcingaTestDirectoryCall['IncludeFileList'] | Should -BeTrue;

        [array]$Lines = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output -split "`n";
        $Lines[0]  | Should -Be '[OK] Directory Check: "C:\Backup": 6 Ok';
        $Lines[8]  | Should -Be '\_ [INFO] File List';
        $Lines[9]  | Should -Be ([string]::Format('   \_ [INFO] {0}: 1KiB', (Join-Path -Path $ListRoot -ChildPath 'a.bak')));
        $Lines[10] | Should -Be ([string]::Format('   \_ [INFO] {0}: 2KiB', (Join-Path -Path $ListRoot -ChildPath 'b.bak')));
        $Lines[11] | Should -Be ([string]::Format('   \_ [INFO] {0}: Folder', (Join-Path -Path $ListRoot -ChildPath 'folder')));
    }

    It 'suppresses the performance data with NoPerfData' {
        Invoke-TestDirectoryCheck -StubData $script:Backup -Arguments @{ 'Path' = 'C:\Backup'; 'NoPerfData' = $true; } | Should -Be 0;
        @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
    }
}

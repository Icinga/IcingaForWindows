$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Get-IcingaDirectoryInformation' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        # Writes a file of the given size and sets its time stamps.
        function New-TestFile()
        {
            param (
                [string]$Path         = '',
                [int]$Size            = 0,
                [datetime]$LastWrite  = [datetime]::Now,
                [datetime]$Creation   = [datetime]::Now,
                [datetime]$LastAccess = [datetime]::Now,
                [switch]$Hidden       = $false
            );

            [System.IO.File]::WriteAllBytes($Path, [byte[]]::new($Size));
            [System.IO.File]::SetCreationTime($Path, $Creation);
            [System.IO.File]::SetLastWriteTime($Path, $LastWrite);
            [System.IO.File]::SetLastAccessTime($Path, $LastAccess);

            if ($Hidden) {
                [System.IO.File]::SetAttributes($Path, [System.IO.FileAttributes]::Hidden);
            }
        }

        # Calls the provider inside the module scope, where IcingaError is visible.
        function Invoke-TestDirectory()
        {
            param (
                [hashtable]$Arguments = @{ }
            );

            return (& $script:IcingaModule {
                param ($Arguments);

                Get-IcingaDirectoryInformation @Arguments;
            } $Arguments);
        }

        # Layout (sizes in bytes, ages relative to now):
        #   a.log 100 (written at noon 10 days ago), b.log 2000 (1h), c.txt 50 (40d,
        #   created 40d ago, last access 40d ago), hidden.log 10 (hidden),
        #   sub\ (written 3d ago) with d.log 5000 (2d) and deep\e.log 1 (now),
        #   hidden\ (hidden folder) with f.log 7.
        [datetime]$Now         = [datetime]::Now;
        $script:Root           = Join-Path -Path $TestDrive -ChildPath 'scan';
        [string]$Sub           = Join-Path -Path $script:Root -ChildPath 'sub';
        [string]$Deep          = Join-Path -Path $Sub -ChildPath 'deep';
        [string]$Secret        = Join-Path -Path $script:Root -ChildPath 'hidden';

        New-Item -Path $Deep -ItemType Directory -Force | Out-Null;
        New-Item -Path $Secret -ItemType Directory -Force | Out-Null;

        New-TestFile -Path (Join-Path -Path $script:Root -ChildPath 'a.log') -Size 100 -LastWrite $Now.AddDays(-10).Date.AddHours(12);
        New-TestFile -Path (Join-Path -Path $script:Root -ChildPath 'b.log') -Size 2000 -LastWrite $Now.AddHours(-1);
        New-TestFile -Path (Join-Path -Path $script:Root -ChildPath 'c.txt') -Size 50 -LastWrite $Now.AddDays(-40) -Creation $Now.AddDays(-40) -LastAccess $Now.AddDays(-40);
        New-TestFile -Path (Join-Path -Path $script:Root -ChildPath 'hidden.log') -Size 10 -Hidden;
        New-TestFile -Path (Join-Path -Path $Sub -ChildPath 'd.log') -Size 5000 -LastWrite $Now.AddDays(-2);
        New-TestFile -Path (Join-Path -Path $Deep -ChildPath 'e.log') -Size 1;
        New-TestFile -Path (Join-Path -Path $Secret -ChildPath 'f.log') -Size 7;

        [System.IO.Directory]::SetLastWriteTime($Sub, $Now.AddDays(-3));
        [System.IO.Directory]::SetLastWriteTime($Deep, $Now.AddDays(-3));
        $SecretInfo            = [System.IO.DirectoryInfo]::new($Secret);
        $SecretInfo.Attributes = $SecretInfo.Attributes -bor [System.IO.FileAttributes]::Hidden;
    }

    It 'collects the statistics of the top level and skips hidden entries' {
        $Result = Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; };

        $Result.Exists       | Should -BeTrue;
        $Result.FileCount    | Should -Be 3;
        $Result.FolderCount  | Should -Be 1;
        $Result.TotalCount   | Should -Be 4;
        $Result.TotalSize    | Should -Be 2150;
        $Result.SmallestFile | Should -Be 50;
        $Result.LargestFile  | Should -Be 2000;
        $Result.AverageSize  | Should -Be 716.67;
        @($Result.FileList).Count | Should -Be 0;
    }

    It 'descends into every subdirectory with Recurse, but not into hidden ones' {
        $Result = Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'Recurse' = $true; };

        $Result.FileCount    | Should -Be 5;
        $Result.FolderCount  | Should -Be 2;
        $Result.TotalSize    | Should -Be 7151;
        $Result.SmallestFile | Should -Be 1;
        $Result.LargestFile  | Should -Be 5000;
    }

    It 'matches the file names case-insensitively and still scans non-matching folders' {
        $Result = Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'Recurse' = $true; 'FileNames' = @('*.LOG'); };

        $Result.FileCount   | Should -Be 4;
        $Result.FolderCount | Should -Be 0;
    }

    It 'keeps entries matching any of several name patterns' {
        $Result = Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'FileNames' = @('a.*', '*.txt'); };

        $Result.FileCount | Should -Be 2;
    }

    It 'filters by the last write time' {
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'ChangeOlderThan' = '5d'; }).FileCount     | Should -Be 2;
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'ChangeOlderThan' = '5d'; }).FolderCount   | Should -Be 0;
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'ChangeYoungerThan' = '1d'; }).FileCount   | Should -Be 1;
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'ChangeYoungerThan' = '4d'; }).FolderCount | Should -Be 1;
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'ChangeTimeEqual' = '10d'; }).FileCount    | Should -Be 1;
    }

    It 'filters by the creation and the last access time' {
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'CreationOlderThan' = '20d'; }).FileCount   | Should -Be 1;
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'CreationYoungerThan' = '20d'; }).FileCount | Should -Be 2;
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'AccessOlderThan' = '20d'; }).FileCount     | Should -Be 1;
    }

    It 'filters files by size, accepts plain numbers as bytes and never keeps folders' {
        $Larger = Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'Recurse' = $true; 'FileSizeGreaterThan' = '1KB'; };
        $Larger.FileCount   | Should -Be 2;
        $Larger.FolderCount | Should -Be 0;

        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'FileSizeSmallerThan' = '100'; }).FileCount | Should -Be 1;
    }

    It 'combines every given filter with AND' {
        $Result = Invoke-TestDirectory -Arguments @{
            'Path'                = $script:Root;
            'Recurse'             = $true;
            'FileNames'           = @('*.log');
            'ChangeYoungerThan'   = '3d';
            'FileSizeGreaterThan' = '1KB';
        };

        $Result.FileCount | Should -Be 2;
        $Result.TotalSize | Should -Be 7000;
    }

    It 'returns the kept entries with IncludeFileList' {
        $Result       = Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'IncludeFileList' = $true; };

        [array]$Names = @($Result.FileList | ForEach-Object { $_.Name } | Sort-Object);
        $Names | Should -Be @('a.log', 'b.log', 'c.txt', 'sub');
    }

    It 'resolves a relative path against the current location' {
        $Result = & $script:IcingaModule {
            param ($Root);

            Push-Location -Path $Root;
            try {
                Get-IcingaDirectoryInformation -Path 'sub';
            } finally {
                Pop-Location;
            }
        } $script:Root;

        $Result.FileCount   | Should -Be 1;
        $Result.FolderCount | Should -Be 1;
    }

    It 'rejects an invalid filter value with DirectoryFilterInvalid' {
        $Result = Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'ChangeOlderThan' = '20MB'; };
        $Result.GetType().Name | Should -Be 'IcingaError';
        $Result.ReturnCode     | Should -Be 'DirectoryFilterInvalid';
        $Result.Message        | Should -Be 'The value "20MB" of -ChangeOlderThan is not a valid duration such as 20d, 12h or 30m';

        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'FileSizeGreaterThan' = 'abc'; }).ReturnCode | Should -Be 'DirectoryFilterInvalid';
        (Invoke-TestDirectory -Arguments @{ 'Path' = $script:Root; 'FileNames' = @( '[unclosed' ); }).ReturnCode | Should -Be 'DirectoryFilterInvalid';
    }

    It 'reports a missing path, or an empty result with IgnoreMissingPath' {
        [string]$Missing = Join-Path -Path $TestDrive -ChildPath 'missing';

        $Result          = Invoke-TestDirectory -Arguments @{ 'Path' = $Missing; };
        $Result.ReturnCode | Should -Be 'DirectoryPathNotFound';
        $Result.Message    | Should -Be ([string]::Format('The directory "{0}" does not exist on this system', $Missing));

        $Empty = Invoke-TestDirectory -Arguments @{ 'Path' = $Missing; 'IgnoreMissingPath' = $true; };
        $Empty.Exists    | Should -BeFalse;
        $Empty.FileCount | Should -Be 0;

        (Invoke-TestDirectory -Arguments @{ 'Path' = ''; }).ReturnCode | Should -Be 'DirectoryPathMissing';
    }

    It 'reports a directory that cannot be listed with DirectoryAccessDenied' {
        [string]$Locked = Join-Path -Path $TestDrive -ChildPath 'locked';
        New-Item -Path $Locked -ItemType Directory -Force | Out-Null;

        $Rule           = New-Object System.Security.AccessControl.FileSystemAccessRule(
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
            [System.Security.AccessControl.FileSystemRights]::ListDirectory,
            [System.Security.AccessControl.AccessControlType]::Deny
        );
        $Acl            = Get-Acl -Path $Locked;
        $Acl.AddAccessRule($Rule);
        Set-Acl -Path $Locked -AclObject $Acl;

        try {
            $Result = Invoke-TestDirectory -Arguments @{ 'Path' = $Locked; };
            $Result.ReturnCode | Should -Be 'DirectoryAccessDenied';
            $Result.Message    | Should -Be ([string]::Format('Access to the directory "{0}" was denied', $Locked));
        } finally {
            $Acl = Get-Acl -Path $Locked;
            [void]$Acl.RemoveAccessRule($Rule);
            Set-Acl -Path $Locked -AclObject $Acl;
        }
    }

    It 'scans 5000 files with filters in one pass within the time budget' {
        [string]$Large = Join-Path -Path $TestDrive -ChildPath 'large';
        New-Item -Path $Large -ItemType Directory -Force | Out-Null;

        for ($i = 0; $i -lt 5000; $i++) {
            [System.IO.File]::WriteAllBytes((Join-Path -Path $Large -ChildPath ([string]::Format('file{0}.log', $i))), [byte[]]::new($i % 10));
        }

        $Watch  = [System.Diagnostics.Stopwatch]::StartNew();
        $Result = Invoke-TestDirectory -Arguments @{ 'Path' = $Large; 'FileNames' = @('*.log'); 'ChangeYoungerThan' = '1h'; 'FileSizeGreaterThan' = '4'; };
        $Watch.Stop();

        $Result.FileCount | Should -Be 2500;
        $Watch.ElapsedMilliseconds | Should -BeLessThan 5000;
    }
}

$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckPartitionSpace' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Builds a volume entry in the shape of Get-IcingaDiskInformation -Entrypoint 'Volume'.
        function New-TestVolume()
        {
            param (
                [string]$Name        = '',
                [string]$DriveLetter = '',
                [string]$Label       = '',
                $Capacity            = $null,
                $FreeSpace           = $null
            );

            $UsedSpace = $null;

            if ($null -ne $Capacity -and $null -ne $FreeSpace) {
                $UsedSpace = [uint64]$Capacity - [uint64]$FreeSpace;
            }

            return @{
                'DeviceId'    = $Name;
                'Name'        = $Name;
                'DriveLetter' = $DriveLetter;
                'Label'       = $Label;
                'FileSystem'  = 'NTFS';
                'Size'        = $Capacity;
                'FreeSpace'   = $FreeSpace;
                'UsedSpace'   = $UsedSpace;
            };
        }

        # Runs the plugin inside the module scope with Get-IcingaDiskInformation
        # shadowed by a function, so the check works on the given volume entries.
        function Invoke-TestPartitionCheck()
        {
            param (
                [array]$StubData      = @(),
                [hashtable]$Arguments = @{ },
                [switch]$Fail         = $false
            );

            return (& $script:IcingaModule {
                param ($StubData, $Arguments, $Fail);

                function Get-IcingaDiskInformation()
                {
                    param (
                        [string]$Entrypoint = 'PhysicalDisk'
                    );

                    if ($Fail) {
                        return [IcingaError]::new('Simulated volume failure');
                    }

                    [hashtable]$Volumes = @{ };

                    foreach ($Volume in $StubData) {
                        $Volumes[$Volume.DeviceId] = $Volume;
                    }

                    return $Volumes;
                }

                Invoke-IcingaCheckPartitionSpace @Arguments;
            } $StubData $Arguments $Fail);
        }

        # 512GB volume with 442.692GB used (86.46%).
        $script:DriveC = New-TestVolume -Name 'C:\' -DriveLetter 'C:' -Label 'System' -Capacity ([uint64]512000000000) -FreeSpace ([uint64]69308000000);
        # 100GB volume with 10GB used (10%).
        $script:DriveD = New-TestVolume -Name 'D:\' -DriveLetter 'D:' -Label 'Data' -Capacity ([uint64]100000000000) -FreeSpace ([uint64]90000000000);
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    Context 'Used space' {
        It 'evaluates the used space against percent thresholds' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC, $script:DriveD) -Arguments @{ 'Warning' = '80%'; 'Critical' = '90%'; } | Should -Be 1;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output | Should -Match '^\[WARNING\] Used Partition Space: 1 Warning 1 Ok';
            $Result.Output | Should -Match ([regex]::Escape('[WARNING] Partition C: 412.29GiB (86.46%) is greater than threshold 381.47GiB (80%)'));
        }

        It 'writes the used space and resolved thresholds in bytes into the perfdata' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC, $script:DriveD) -Arguments @{ 'Warning' = '80%'; 'Critical' = '90%'; } | Out-Null;

            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
                'c::ifw_partitionspace::used=442692000000B;409600000000;460800000000;0;512000000000',
                'd::ifw_partitionspace::used=10000000000B;80000000000;90000000000;0;100000000000'
            );
        }

        It 'accepts absolute size thresholds' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC) -Arguments @{ 'Warning' = '400GB'; 'Critical' = '450GB'; 'Verbosity' = 2; } | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('Partition C: 412.29GiB is greater than threshold 400GB'));
        }
    }

    Context 'Free space' {
        It 'evaluates the free space against a percent range with CheckFreeSpace' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC) -Arguments @{ 'CheckFreeSpace' = $true; 'Warning' = '15%:'; 'Critical' = '5%:'; } | Should -Be 1;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output          | Should -Match '^\[WARNING\] Free Partition Space';
            $Result.Output          | Should -Match ([regex]::Escape('Partition C: 64.55GiB (13.54%) is lower than threshold 71.53GiB (15%)'));
            $Result.PerformanceData | Should -Be @('c::ifw_partitionspace::free=69308000000B;76800000000:;25600000000:;0;512000000000');
        }
    }

    Context 'Partition selection' {
        It 'only checks included partitions, ignoring the drive letter colon' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC, $script:DriveD) -Arguments @{ 'Include' = 'D:'; 'Warning' = '80%'; } | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @('d::ifw_partitionspace::used=10000000000B;80000000000;;0;100000000000');
        }

        It 'skips excluded partitions' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC, $script:DriveD) -Arguments @{ 'Exclude' = 'C:\'; 'Warning' = '80%'; } | Should -Be 0;
            @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 1;
        }

        It 'names a volume without drive letter after its label, or its path without a label' {
            $Labeled   = New-TestVolume -Name '\\?\Volume{1}\' -Label 'Recovery' -Capacity ([uint64]1000000000) -FreeSpace ([uint64]500000000);
            $Unlabeled = New-TestVolume -Name '\\?\Volume{2}\' -Capacity ([uint64]1000000000) -FreeSpace ([uint64]500000000);

            Invoke-TestPartitionCheck -StubData @($Labeled, $Unlabeled) -Arguments @{ 'Verbosity' = 2; } | Should -Be 0;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output          | Should -Match ([regex]::Escape('[OK] Partition Recovery: '));
            $Result.Output          | Should -Match ([regex]::Escape('[OK] Partition \\?\Volume{2}\: '));
            $Result.PerformanceData | Should -Contain 'recovery::ifw_partitionspace::used=500000000B;;;0;1000000000';
            $Result.PerformanceData | Should -Contain 'volume2::ifw_partitionspace::used=500000000B;;;0;1000000000';
        }

        It 'reports a missing required partition as CRITICAL' {
            Invoke-TestPartitionCheck -StubData @($script:DriveD) -Arguments @{ 'RequiredPartition' = 'D:', 'E:'; } | Should -Be 2;

            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.Output | Should -Match ([regex]::Escape('[CRITICAL] Partition E: Mandatory partition not found on host'));
            $Result.Output | Should -Not -Match 'Partition D: Mandatory';
        }

        It 'returns UNKNOWN when no partition matches, OK with IgnoreEmptyChecks' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC) -Arguments @{ 'Include' = 'Q'; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Used Partition Space: No partition matches the given filter';

            Invoke-TestPartitionCheck -StubData @($script:DriveC) -Arguments @{ 'Include' = 'Q'; 'IgnoreEmptyChecks' = $true; } | Should -Be 0;
        }
    }

    Context 'Missing size data and errors' {
        It 'reports a volume without size as UNKNOWN, OK with SkipUnknown' {
            $NoSize = New-TestVolume -Name 'F:\' -DriveLetter 'F:';

            Invoke-TestPartitionCheck -StubData @($NoSize) -Arguments @{ 'Warning' = '80%'; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[UNKNOWN] Partition F: No partition size available'));

            Invoke-TestPartitionCheck -StubData @($NoSize) -Arguments @{ 'Warning' = '80%'; 'SkipUnknown' = $true; } | Should -Be 0;
        }

        It 'suppresses the performance data with NoPerfData' {
            Invoke-TestPartitionCheck -StubData @($script:DriveC) -Arguments @{ 'Warning' = '80%'; 'NoPerfData' = $true; } | Should -Be 1;
            @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
        }

        It 'returns UNKNOWN when the volume query fails' {
            Invoke-TestPartitionCheck -Fail | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Used Partition Space: Simulated volume failure';
        }
    }
}

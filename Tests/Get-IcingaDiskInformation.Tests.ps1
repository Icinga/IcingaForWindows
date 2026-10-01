$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Get-IcingaDiskInformation' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        # Runs the provider inside the module scope with Get-IcingaWindowsInformation
        # shadowed by a function that serves the stub instances per class, or an
        # IcingaError for every class listed in FailingClasses.
        function Invoke-TestDiskInformation()
        {
            param (
                [string]$Entrypoint    = 'PhysicalDisk',
                [hashtable]$StubData   = @{ },
                [array]$FailingClasses = @()
            );

            return (& $script:IcingaModule {
                param ($Entrypoint, $StubData, $FailingClasses);

                function Get-IcingaWindowsInformation()
                {
                    param (
                        [string]$ClassName = '',
                        [string]$Namespace = '',
                        [string]$Filter    = '',
                        [array]$Property   = @()
                    );

                    if ($FailingClasses -contains $ClassName) {
                        return [IcingaError]::new('WindowsInformationClassUnknown', [string]::Format('Simulated failure of {0}', $ClassName), @{ });
                    }

                    if ($StubData.ContainsKey($ClassName)) {
                        return ,@($StubData[$ClassName]);
                    }

                    return ,@();
                }

                $Value = Get-IcingaDiskInformation -Entrypoint $Entrypoint;

                return @{
                    'Value'   = $Value;
                    'IsError' = ($Value -is [IcingaError]);
                };
            } $Entrypoint $StubData $FailingClasses);
        }

        $script:StubData = @{
            'Win32_Volume'      = @(
                [PSCustomObject]@{ 'DeviceID' = '\\?\Volume{c}\'; 'Name' = 'C:\'; 'DriveLetter' = 'C:'; 'Label' = 'System'; 'FileSystem' = 'NTFS'; 'Capacity' = [uint64]500000000000; 'FreeSpace' = [uint64]100000000000; },
                [PSCustomObject]@{ 'DeviceID' = '\\?\Volume{r}\'; 'Name' = '\\?\Volume{r}\'; 'DriveLetter' = $null; 'Label' = 'Recovery'; 'FileSystem' = 'NTFS'; 'Capacity' = [uint64]1000000000; 'FreeSpace' = [uint64]100000000; },
                [PSCustomObject]@{ 'DeviceID' = '\\?\Volume{x}\'; 'Name' = '\\?\Volume{x}\'; 'DriveLetter' = $null; 'Label' = $null; 'FileSystem' = 'RAW'; 'Capacity' = $null; 'FreeSpace' = $null; }
            );
            'MSFT_Partition'    = @(
                [PSCustomObject]@{ 'DiskNumber' = [uint32]0; 'PartitionNumber' = [uint32]1; 'DriveLetter' = [char]0; 'AccessPaths' = @('\\?\Volume{e}\'); 'Size' = [uint64]200000000; 'Offset' = [uint64]1048576; 'GptType' = '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}'; 'MbrType' = $null; 'IsBoot' = $false; 'IsSystem' = $true; 'IsActive' = $false; 'IsHidden' = $true; },
                [PSCustomObject]@{ 'DiskNumber' = [uint32]0; 'PartitionNumber' = [uint32]3; 'DriveLetter' = [char]'C'; 'AccessPaths' = @('C:\', '\\?\Volume{c}\'); 'Size' = [uint64]500000000000; 'Offset' = [uint64]227540992; 'GptType' = '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}'; 'MbrType' = $null; 'IsBoot' = $true; 'IsSystem' = $false; 'IsActive' = $false; 'IsHidden' = $false; },
                [PSCustomObject]@{ 'DiskNumber' = [uint32]0; 'PartitionNumber' = [uint32]4; 'DriveLetter' = [char]0; 'AccessPaths' = @('\\?\Volume{r}\'); 'Size' = [uint64]1000000000; 'Offset' = [uint64]500300000000; 'GptType' = '{de94bba4-06d1-4d40-a16a-bfd50179d6ac}'; 'MbrType' = $null; 'IsBoot' = $false; 'IsSystem' = $false; 'IsActive' = $false; 'IsHidden' = $true; },
                [PSCustomObject]@{ 'DiskNumber' = [uint32]1; 'PartitionNumber' = [uint32]1; 'DriveLetter' = [char]'E'; 'AccessPaths' = @('E:\'); 'Size' = [uint64]100000000000; 'Offset' = [uint64]1048576; 'GptType' = $null; 'MbrType' = [uint16]7; 'IsBoot' = $false; 'IsSystem' = $false; 'IsActive' = $true; 'IsHidden' = $false; }
            );
            'MSFT_Disk'         = @(
                [PSCustomObject]@{ 'Number' = [uint32]0; 'FriendlyName' = 'NVMe Disk'; 'Model' = 'NVMe Disk'; 'Manufacturer' = 'Vendor'; 'SerialNumber' = 'SERIAL0 '; 'UniqueId' = 'eui.0000'; 'Size' = [uint64]512000000000; 'BusType' = [uint16]17; 'HealthStatus' = [uint16]0; 'OperationalStatus' = @([uint16]53264); 'IsOffline' = $false; 'OfflineReason' = [uint16]0; 'IsReadOnly' = $false; 'IsBoot' = $true; 'IsSystem' = $true; 'IsClustered' = $false; 'PartitionStyle' = [uint16]2; 'Location' = 'PCI Slot 8'; },
                [PSCustomObject]@{ 'Number' = [uint32]1; 'FriendlyName' = 'SAN LUN'; 'Model' = 'LUN'; 'Manufacturer' = 'SAN'; 'SerialNumber' = 'SAN-SERIAL'; 'UniqueId' = '600A0B80'; 'Size' = [uint64]100000000000; 'BusType' = [uint16]6; 'HealthStatus' = [uint16]0; 'OperationalStatus' = @([uint16]53264); 'IsOffline' = $false; 'OfflineReason' = [uint16]0; 'IsReadOnly' = $true; 'IsBoot' = $false; 'IsSystem' = $false; 'IsClustered' = $true; 'PartitionStyle' = [uint16]1; 'Location' = 'Fibre Channel'; }
            );
            'MSFT_PhysicalDisk' = @(
                [PSCustomObject]@{ 'DeviceId' = '0'; 'MediaType' = [uint16]4; 'SpindleSpeed' = [uint32]0; }
            );
            'MPIO_DISK_INFO'    = @(
                [PSCustomObject]@{ 'InstanceName' = 'ROOT\MPIO\0000_0'; 'DriveInfo' = @([PSCustomObject]@{ 'Name' = 'MPIO Disk1'; 'NumberPaths' = [uint32]4; 'SerialNumber' = '600A0B80'; }); }
            );
        };
    }

    Context 'Volume entrypoint' {
        It 'returns every volume keyed by its volume path with sizes in bytes' {
            $Volumes = (Invoke-TestDiskInformation -Entrypoint 'Volume' -StubData $script:StubData).Value;
            $Volumes.Count                          | Should -Be 3;
            $Volumes['\\?\Volume{c}\'].Name         | Should -Be 'C:\';
            $Volumes['\\?\Volume{c}\'].DriveLetter  | Should -Be 'C:';
            $Volumes['\\?\Volume{c}\'].Size         | Should -Be 500000000000;
            $Volumes['\\?\Volume{c}\'].FreeSpace    | Should -Be 100000000000;
            $Volumes['\\?\Volume{c}\'].UsedSpace    | Should -Be 400000000000;
            $Volumes['\\?\Volume{r}\'].Label        | Should -Be 'Recovery';
        }

        It 'links each volume to its disk and partition through the access paths' {
            $Volumes = (Invoke-TestDiskInformation -Entrypoint 'Volume' -StubData $script:StubData).Value;
            $Volumes['\\?\Volume{c}\'].DiskNumber      | Should -Be 0;
            $Volumes['\\?\Volume{c}\'].PartitionNumber | Should -Be 3;
            $Volumes['\\?\Volume{c}\'].PartitionId     | Should -Be 'Disk #0, Partition #3';
            $Volumes['\\?\Volume{x}\'].DiskNumber      | Should -BeNullOrEmpty;
        }

        It 'reports unknown sizes as $null' {
            $Volume = (Invoke-TestDiskInformation -Entrypoint 'Volume' -StubData $script:StubData).Value['\\?\Volume{x}\'];
            $Volume.Size      | Should -BeNullOrEmpty;
            $Volume.UsedSpace | Should -BeNullOrEmpty;
        }

        It 'still returns the volumes when the partition data is unavailable' {
            $Result = Invoke-TestDiskInformation -Entrypoint 'Volume' -StubData $script:StubData -FailingClasses 'MSFT_Partition';
            $Result.IsError                                | Should -BeFalse;
            $Result.Value['\\?\Volume{c}\'].Size           | Should -Be 500000000000;
            $Result.Value['\\?\Volume{c}\'].DiskNumber     | Should -BeNullOrEmpty;
        }

        It 'returns the IcingaError when the volumes cannot be read' {
            $Result = Invoke-TestDiskInformation -Entrypoint 'Volume' -StubData $script:StubData -FailingClasses 'Win32_Volume';
            $Result.IsError       | Should -BeTrue;
            $Result.Value.Message | Should -Be 'Simulated failure of Win32_Volume';
        }
    }

    Context 'Partition entrypoint' {
        It 'returns every partition with drive letter and linked volume' {
            $Partitions = (Invoke-TestDiskInformation -Entrypoint 'Partition' -StubData $script:StubData).Value;
            $Partitions.Count                                       | Should -Be 4;
            $Partitions['Disk #0, Partition #3'].DriveLetter        | Should -Be 'C:';
            $Partitions['Disk #0, Partition #3'].VolumeId           | Should -Be '\\?\Volume{c}\';
            $Partitions['Disk #0, Partition #3'].Volume.Name        | Should -Be 'C:\';
            $Partitions['Disk #0, Partition #3'].IsBoot             | Should -BeTrue;
            $Partitions['Disk #0, Partition #1'].DriveLetter        | Should -Be '';
            $Partitions['Disk #0, Partition #1'].Volume             | Should -BeNullOrEmpty;
            $Partitions['Disk #1, Partition #1'].MbrType            | Should -Be 7;
        }

        It 'returns the IcingaError when the partitions cannot be read' {
            (Invoke-TestDiskInformation -Entrypoint 'Partition' -StubData $script:StubData -FailingClasses 'MSFT_Partition').IsError | Should -BeTrue;
        }
    }

    Context 'PhysicalDisk entrypoint' {
        It 'returns every disk keyed by its number with media type and status' {
            $Disks = (Invoke-TestDiskInformation -StubData $script:StubData).Value;
            $Disks.Count                       | Should -Be 2;
            $Disks['0'].FriendlyName           | Should -Be 'NVMe Disk';
            $Disks['0'].SerialNumber           | Should -Be 'SERIAL0';
            $Disks['0'].MediaType              | Should -Be 4;
            $Disks['0'].BusType                | Should -Be 17;
            $Disks['0'].OperationalStatus      | Should -Be @(53264);
            $Disks['0'].IsBoot                 | Should -BeTrue;
            $Disks['1'].IsReadOnly             | Should -BeTrue;
            $Disks['1'].MediaType              | Should -BeNullOrEmpty;
        }

        It 'attaches partitions, volumes and drive letters to their disk' {
            $Disks = (Invoke-TestDiskInformation -StubData $script:StubData).Value;
            @($Disks['0'].Partitions.Keys | Sort-Object) | Should -Be @('1', '3', '4');
            $Disks['0'].DriveLetters                     | Should -Be @('C:');
            @($Disks['0'].Volumes | ForEach-Object { $_.Name }) | Should -Be @('C:\', '\\?\Volume{r}\');
            $Disks['1'].DriveLetters                     | Should -Be @('E:');
        }

        It 'matches the MPIO information by unique id' {
            $Disks = (Invoke-TestDiskInformation -StubData $script:StubData).Value;
            $Disks['1'].MPIO.Name         | Should -Be 'MPIO Disk1';
            $Disks['1'].MPIO.NumberPaths  | Should -Be 4;
            $Disks['1'].MPIO.InstanceName | Should -Be 'ROOT\MPIO\0000_0';
            $Disks['0'].MPIO              | Should -BeNullOrEmpty;
        }

        It 'leaves MPIO and media type empty when their classes are unavailable' {
            $Result = Invoke-TestDiskInformation -StubData $script:StubData -FailingClasses 'MPIO_DISK_INFO', 'MSFT_PhysicalDisk';
            $Result.IsError                 | Should -BeFalse;
            $Result.Value['1'].MPIO         | Should -BeNullOrEmpty;
            $Result.Value['0'].MediaType    | Should -BeNullOrEmpty;
        }

        It 'returns the IcingaError when the disks cannot be read' {
            (Invoke-TestDiskInformation -StubData $script:StubData -FailingClasses 'MSFT_Disk').IsError | Should -BeTrue;
        }
    }
}

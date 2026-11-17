<#
.SYNOPSIS
Collect correlated physical disk, partition, volume and MPIO data in one call

.DESCRIPTION
Get-IcingaDiskInformation is the single data source for disk related plugins. It
reads every involved CIM class exactly once and correlates the results in
memory, instead of issuing one query per disk or volume, so the whole storage
picture is available in well below a second. The Entrypoint selects the view
that is returned and limits the queries to the classes that view needs:

Volume returns the local disk volumes (Win32_Volume, DriveType 3) keyed by their
volume path ('\\?\Volume{GUID}\'), each with size, free and used space and the
disk and partition it lives on. Partition returns every partition
(MSFT_Partition) keyed by 'Disk #<disk>, Partition #<partition>', each with its
volume. PhysicalDisk returns every disk known to the operating system
(MSFT_Disk) keyed by its disk number, enriched with the media type
(MSFT_PhysicalDisk), its partitions, volumes and drive letters and, on hosts
with the MPIO feature, its multipath information (MPIO_DISK_INFO).

All queries go through Get-IcingaWindowsInformation. When the main class of the
requested view cannot be read, the IcingaError of that query is returned instead
of the data; failures of enriching classes (for example MPIO on hosts without the
feature) only leave the related fields empty. Every exit goes through
Write-FunctionReturnValue with its own return code (DiskInformationCollected,
DiskInformationVolumeQueryFailed, DiskInformationPartitionQueryFailed,
DiskInformationDiskQueryFailed), so the log shows where the collection stopped.

.PARAMETER Entrypoint
| Name       | Type          | Description                                              | Default      |
|------------|---------------|----------------------------------------------------------|--------------|
| Entrypoint | System.String | View to return: 'PhysicalDisk', 'Partition' or 'Volume'. | PhysicalDisk |

.PARAMETER SkipPartitionMapping
| Name                 | Type                                         | Description                                                      | Default |
|----------------------|----------------------------------------------|------------------------------------------------------------------|---------|
| SkipPartitionMapping | System.Management.Automation.SwitchParameter | Skip querying MSFT_Partition when Entrypoint is set to 'Volume'. | $false  |

.OUTPUTS
System.Collections.Hashtable -- The entries of the requested view, or an
IcingaError when its main class could not be read. Entry fields per view:

Volume: DeviceId, Name, DriveLetter ('C:' or ''), Label, FileSystem, Size,
FreeSpace, UsedSpace (bytes, $null when unknown), DiskNumber, PartitionNumber,
PartitionId.

Partition: Id, DiskNumber, PartitionNumber, DriveLetter, Size, Offset,
GptType, MbrType, IsBoot, IsSystem, IsActive, IsHidden, AccessPaths, VolumeId,
Volume (the volume entry or $null).

PhysicalDisk: Number, FriendlyName, Model, Manufacturer, SerialNumber, UniqueId,
Size, BusType, MediaType, SpindleSpeed, HealthStatus, OperationalStatus,
IsOffline, OfflineReason, IsReadOnly, IsBoot, IsSystem, IsClustered,
PartitionStyle, Location, Partitions (partition entries keyed by partition
number), Volumes (volume entries), DriveLetters, MPIO (Name, InstanceName,
NumberPaths, or $null). Status values are the raw numeric codes of the
MSFT_Disk / MSFT_PhysicalDisk classes.

.EXAMPLE
PS> (Get-IcingaDiskInformation -Entrypoint 'Volume').Values | Select-Object Name, Size, FreeSpace

Lists the size and free space of every local volume.

.EXAMPLE
PS> $Disks = Get-IcingaDiskInformation
PS> $Disks['0'].DriveLetters

Returns the drive letters of disk 0.

.NOTES
Windows-only. Reads root/cimv2 (Win32_Volume), root/Microsoft/Windows/Storage
(MSFT_Disk, MSFT_PhysicalDisk, MSFT_Partition) and root/wmi (MPIO_DISK_INFO).
Standard users can read all of them. Spanned volumes are linked to the first
partition reporting them.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-IcingaDiskInformation()
{
    param (
        [ValidateSet('PhysicalDisk', 'Partition', 'Volume')]
        [string]$Entrypoint           = 'PhysicalDisk',
        [switch]$SkipPartitionMapping = $false
    );

    [string]$StorageNamespace = 'root/Microsoft/Windows/Storage';

    $Volumes                  = Get-IcingaWindowsInformation -ClassName 'Win32_Volume' -Filter 'DriveType = 3' -Property 'DeviceID', 'Name', 'DriveLetter', 'Label', 'FileSystem', 'Capacity', 'FreeSpace';

    if (Test-IcingaError -InputObject $Volumes) {
        if ($Entrypoint -eq 'Volume') {
            return (Write-FunctionReturnValue -ReturnValue 'DiskInformationVolumeQueryFailed' -Data @{ 'Entrypoint' = $Entrypoint; 'Error' = $Volumes.Message; } -OverrideReturn $Volumes);
        }

        $Volumes = @();
    }

    [hashtable]$VolumeData = @{ };

    foreach ($Volume in $Volumes) {
        $Size      = $null;
        $FreeSpace = $null;
        $UsedSpace = $null;

        if ($null -ne $Volume.Capacity) {
            $Size = [uint64]$Volume.Capacity;
        }

        if ($null -ne $Volume.FreeSpace) {
            $FreeSpace = [uint64]$Volume.FreeSpace;
        }

        if ($null -ne $Size -and $null -ne $FreeSpace -and $FreeSpace -le $Size) {
            $UsedSpace = $Size - $FreeSpace;
        }

        $VolumeData[[string]$Volume.DeviceID] = @{
            'DeviceId'        = [string]$Volume.DeviceID;
            'Name'            = [string]$Volume.Name;
            'DriveLetter'     = [string]$Volume.DriveLetter;
            'Label'           = [string]$Volume.Label;
            'FileSystem'      = [string]$Volume.FileSystem;
            'Size'            = $Size;
            'FreeSpace'       = $FreeSpace;
            'UsedSpace'       = $UsedSpace;
            'DiskNumber'      = $null;
            'PartitionNumber' = $null;
            'PartitionId'     = $null;
        };
    }

    # Callers that only need Win32_Volume capacity/freespace metrics (such as Invoke-IcingaCheckPartitionSpace)
    # can skip MSFT_Partition so non-admin accounts without root/Microsoft/Windows/Storage rights do not log errors
    if ($Entrypoint -eq 'Volume' -and $SkipPartitionMapping) {
        return (Write-FunctionReturnValue -ReturnValue 'DiskInformationCollected' -Data @{ 'Entrypoint' = $Entrypoint; 'Count' = $VolumeData.Count; } -OverrideReturn $VolumeData);
    }

    $Partitions = Get-IcingaWindowsInformation -ClassName 'MSFT_Partition' -Namespace $StorageNamespace -Property 'DiskNumber', 'PartitionNumber', 'DriveLetter', 'AccessPaths', 'Size', 'Offset', 'GptType', 'MbrType', 'IsBoot', 'IsSystem', 'IsActive', 'IsHidden';

    if (Test-IcingaError -InputObject $Partitions) {
        if ($Entrypoint -ne 'Volume') {
            return (Write-FunctionReturnValue -ReturnValue 'DiskInformationPartitionQueryFailed' -Data @{ 'Entrypoint' = $Entrypoint; 'Error' = $Partitions.Message; } -OverrideReturn $Partitions);
        }

        # The volume view stays usable without the disk mapping.
        $Partitions = @();
    }

    [hashtable]$PartitionData = @{ };

    foreach ($Partition in $Partitions) {
        [string]$PartitionId = [string]::Format('Disk #{0}, Partition #{1}', $Partition.DiskNumber, $Partition.PartitionNumber);
        [string]$DriveLetter = '';

        # MSFT_Partition reports a partition without drive letter as the NUL character.
        if ($null -ne $Partition.DriveLetter -and [int][char]$Partition.DriveLetter -ne 0) {
            $DriveLetter = [string]::Format('{0}:', $Partition.DriveLetter);
        }

        $Entry = @{
            'Id'              = $PartitionId;
            'DiskNumber'      = [int]$Partition.DiskNumber;
            'PartitionNumber' = [int]$Partition.PartitionNumber;
            'DriveLetter'     = $DriveLetter;
            'Size'            = [uint64]$Partition.Size;
            'Offset'          = [uint64]$Partition.Offset;
            'GptType'         = [string]$Partition.GptType;
            'MbrType'         = $Partition.MbrType;
            'IsBoot'          = [bool]$Partition.IsBoot;
            'IsSystem'        = [bool]$Partition.IsSystem;
            'IsActive'        = [bool]$Partition.IsActive;
            'IsHidden'        = [bool]$Partition.IsHidden;
            'AccessPaths'     = @($Partition.AccessPaths);
            'VolumeId'        = $null;
            'Volume'          = $null;
        };

        foreach ($AccessPath in $Entry.AccessPaths) {
            if ($VolumeData.ContainsKey([string]$AccessPath) -eq $false) {
                continue;
            }

            $LinkedVolume   = $VolumeData[[string]$AccessPath];

            $Entry.VolumeId = $LinkedVolume.DeviceId;
            $Entry.Volume   = $LinkedVolume;

            if ($null -eq $LinkedVolume.PartitionId) {
                $LinkedVolume.DiskNumber      = $Entry.DiskNumber;
                $LinkedVolume.PartitionNumber = $Entry.PartitionNumber;
                $LinkedVolume.PartitionId     = $PartitionId;
            }

            break;
        }

        $PartitionData[$PartitionId] = $Entry;
    }

    if ($Entrypoint -eq 'Volume') {
        return (Write-FunctionReturnValue -ReturnValue 'DiskInformationCollected' -Data @{ 'Entrypoint' = $Entrypoint; 'Count' = $VolumeData.Count; } -OverrideReturn $VolumeData);
    }

    if ($Entrypoint -eq 'Partition') {
        return (Write-FunctionReturnValue -ReturnValue 'DiskInformationCollected' -Data @{ 'Entrypoint' = $Entrypoint; 'Count' = $PartitionData.Count; } -OverrideReturn $PartitionData);
    }

    $Disks = Get-IcingaWindowsInformation -ClassName 'MSFT_Disk' -Namespace $StorageNamespace -Property 'Number', 'FriendlyName', 'Model', 'Manufacturer', 'SerialNumber', 'UniqueId', 'Size', 'BusType', 'HealthStatus', 'OperationalStatus', 'IsOffline', 'OfflineReason', 'IsReadOnly', 'IsBoot', 'IsSystem', 'IsClustered', 'PartitionStyle', 'Location';

    if (Test-IcingaError -InputObject $Disks) {
        return (Write-FunctionReturnValue -ReturnValue 'DiskInformationDiskQueryFailed' -Data @{ 'Entrypoint' = $Entrypoint; 'Error' = $Disks.Message; } -OverrideReturn $Disks);
    }

    [hashtable]$PhysicalDiskData = @{ };
    $PhysicalDisks               = Get-IcingaWindowsInformation -ClassName 'MSFT_PhysicalDisk' -Namespace $StorageNamespace -Property 'DeviceId', 'MediaType', 'SpindleSpeed';

    if ((Test-IcingaError -InputObject $PhysicalDisks) -eq $false) {
        foreach ($PhysicalDisk in $PhysicalDisks) {
            $PhysicalDiskData[[string]$PhysicalDisk.DeviceId] = $PhysicalDisk;
        }
    }

    [hashtable]$MpioData = @{ };
    $MpioDisks           = Get-IcingaWindowsInformation -ClassName 'MPIO_DISK_INFO' -Namespace 'root/wmi';

    if ((Test-IcingaError -InputObject $MpioDisks) -eq $false) {
        foreach ($MpioDisk in $MpioDisks) {
            foreach ($Drive in $MpioDisk.DriveInfo) {
                if ([string]::IsNullOrEmpty([string]$Drive.SerialNumber)) {
                    continue;
                }

                $MpioData[([string]$Drive.SerialNumber).Trim()] = @{
                    'Name'         = [string]$Drive.Name;
                    'InstanceName' = [string]$MpioDisk.InstanceName;
                    'NumberPaths'  = [int]$Drive.NumberPaths;
                };
            }
        }
    }

    [hashtable]$DiskData = @{ };

    foreach ($Disk in $Disks) {
        [string]$DiskNumber   = [string]$Disk.Number;
        [string]$SerialNumber = ([string]$Disk.SerialNumber).Trim();
        [string]$UniqueId     = [string]$Disk.UniqueId;
        $PhysicalDisk         = $PhysicalDiskData[$DiskNumber];
        $Mpio                 = $null;

        if ($MpioData.ContainsKey($UniqueId)) {
            $Mpio = $MpioData[$UniqueId];
        } elseif ([string]::IsNullOrEmpty($SerialNumber) -eq $false -and $MpioData.ContainsKey($SerialNumber)) {
            $Mpio = $MpioData[$SerialNumber];
        }

        $Entry = @{
            'Number'            = [int]$Disk.Number;
            'FriendlyName'      = [string]$Disk.FriendlyName;
            'Model'             = [string]$Disk.Model;
            'Manufacturer'      = [string]$Disk.Manufacturer;
            'SerialNumber'      = $SerialNumber;
            'UniqueId'          = $UniqueId;
            'Size'              = [uint64]$Disk.Size;
            'BusType'           = $Disk.BusType;
            'MediaType'         = $null;
            'SpindleSpeed'      = $null;
            'HealthStatus'      = $Disk.HealthStatus;
            'OperationalStatus' = @($Disk.OperationalStatus);
            'IsOffline'         = [bool]$Disk.IsOffline;
            'OfflineReason'     = $Disk.OfflineReason;
            'IsReadOnly'        = [bool]$Disk.IsReadOnly;
            'IsBoot'            = [bool]$Disk.IsBoot;
            'IsSystem'          = [bool]$Disk.IsSystem;
            'IsClustered'       = [bool]$Disk.IsClustered;
            'PartitionStyle'    = $Disk.PartitionStyle;
            'Location'          = [string]$Disk.Location;
            'Partitions'        = @{ };
            'Volumes'           = @();
            'DriveLetters'      = @();
            'MPIO'              = $Mpio;
        };

        if ($null -ne $PhysicalDisk) {
            $Entry.MediaType    = $PhysicalDisk.MediaType;
            $Entry.SpindleSpeed = $PhysicalDisk.SpindleSpeed;
        }

        $DiskData[$DiskNumber] = $Entry;
    }

    foreach ($Partition in $PartitionData.Values) {
        [string]$DiskNumber = [string]$Partition.DiskNumber;

        if ($DiskData.ContainsKey($DiskNumber) -eq $false) {
            continue;
        }

        $Entry = $DiskData[$DiskNumber];
        $Entry.Partitions[[string]$Partition.PartitionNumber] = $Partition;

        if ([string]::IsNullOrEmpty($Partition.DriveLetter) -eq $false) {
            $Entry.DriveLetters += $Partition.DriveLetter;
        }

        if ($null -ne $Partition.Volume) {
            $Entry.Volumes += $Partition.Volume;
        }
    }

    foreach ($Entry in $DiskData.Values) {
        $Entry.DriveLetters = ConvertTo-IcingaSortedArray -InputObject $Entry.DriveLetters;
        $Entry.Volumes      = ConvertTo-IcingaSortedArray -InputObject $Entry.Volumes -Property 'Name';
    }

    return (Write-FunctionReturnValue -ReturnValue 'DiskInformationCollected' -Data @{ 'Entrypoint' = $Entrypoint; 'Count' = $DiskData.Count; } -OverrideReturn $DiskData);
}

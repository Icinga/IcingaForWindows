# Icinga.Plugins.Provider.Disk

*Auto-generated from `src/Plugins/Provider/Disk/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [Get-IcingaDiskInformation](#get-icingadiskinformation)

---

### Get-IcingaDiskInformation

*Private function*

**Synopsis:** Collect correlated physical disk, partition, volume and MPIO data in one call

#### Description

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

#### Parameters

**`$Entrypoint`**

| Name       | Type          | Description                                              | Default      |
|------------|---------------|----------------------------------------------------------|--------------|
| Entrypoint | System.String | View to return: 'PhysicalDisk', 'Partition' or 'Volume'. | PhysicalDisk |

**`$SkipPartitionMapping`**

| Name                 | Type                                         | Description                                                      | Default |
|----------------------|----------------------------------------------|------------------------------------------------------------------|---------|
| SkipPartitionMapping | System.Management.Automation.SwitchParameter | Skip querying MSFT_Partition when Entrypoint is set to 'Volume'. | $false  |

#### Outputs

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

#### Examples

```powershell
PS> (Get-IcingaDiskInformation -Entrypoint 'Volume').Values | Select-Object Name, Size, FreeSpace

Lists the size and free space of every local volume.
```

```powershell
PS> $Disks = Get-IcingaDiskInformation
PS> $Disks['0'].DriveLetters

Returns the drive letters of disk 0.
```

#### Notes

Windows-only. Reads root/cimv2 (Win32_Volume), root/Microsoft/Windows/Storage
(MSFT_Disk, MSFT_PhysicalDisk, MSFT_Partition) and root/wmi (MPIO_DISK_INFO).
Standard users can read all of them. Spanned volumes are linked to the first
partition reporting them.

*Source: [src/Plugins/Provider/Disk/Private/Get-IcingaDiskInformation.ps1](../src/Plugins/Provider/Disk/Private/Get-IcingaDiskInformation.ps1)*


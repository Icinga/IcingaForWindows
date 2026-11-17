# Icinga.Plugins.Provider.FileSystem

*Auto-generated from `src/Plugins/Provider/FileSystem/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [Get-IcingaDirectoryInformation](#get-icingadirectoryinformation)

---

### Get-IcingaDirectoryInformation

*Private function*

**Synopsis:** Collect file and folder statistics of a directory in a single pass

#### Description

Get-IcingaDirectoryInformation is the data source of the directory plugin. It
reads the directory exactly once and evaluates every entry while it is read: the
name filter, the time and size filters and the statistics (counts, total,
smallest, largest and average size) are all handled in the same loop, without a
pipeline, without script blocks and without a second lookup per entry.

All filter values are converted once before the scan. Time filters accept a
duration with an Icinga time unit ('20d', '12h', '30m', a plain number counts as
seconds) and compare against the moment of the call: ChangeOlderThan '20d' keeps
entries last written more than 20 days ago, ChangeYoungerThan keeps the ones
written within the last 20 days and ChangeTimeEqual keeps the ones written on
the calendar day 20 days ago. The Creation* and Access* filters do the same for
the creation and last access time. Size filters accept a size ('20MB', '1.5GiB',
a plain number counts as bytes) and only ever match files. Every given filter must
match (they are combined with AND).

FileNames are wildcard patterns matched case-insensitively against the entry
name; an entry is kept when any pattern matches. With Recurse the scan descends
into every subdirectory, whether its name matches or not. Hidden and system
entries are skipped like Get-ChildItem without -Force does, and reparse points
(junctions, symbolic links) are counted but never followed, so the scan cannot
loop.

Every exit goes through Write-FunctionReturnValue with its own return code
(DirectoryInformationCollected, DirectoryPathMissing, DirectoryPathNotFound,
DirectoryAccessDenied, DirectoryFilterInvalid, DirectoryReadFailed). A failure
returns an IcingaError that names the directory or filter, so a plugin can stop
with one check. A directory that cannot be read, including a subdirectory during
a recursive scan, ends the scan with DirectoryAccessDenied or DirectoryReadFailed.

#### Parameters

**`$Path`**

| Name | Type          | Description                                    | Default |
|------|---------------|------------------------------------------------|---------|
| Path | System.String | Directory to scan, e.g. 'C:\ProgramData\Logs'. |         |

**`$FileNames`**

| Name      | Type         | Description                                          | Default |
|-----------|--------------|------------------------------------------------------|---------|
| FileNames | System.Array | Wildcard patterns for the entry names, e.g. '*.log'. | @('*')  |

**`$Recurse`**

| Name    | Type                                         | Description                      | Default |
|---------|----------------------------------------------|----------------------------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Scan every subdirectory as well. | False   |

**`$ChangeTimeEqual`**

| Name            | Type          | Description                                                    | Default |
|-----------------|---------------|----------------------------------------------------------------|---------|
| ChangeTimeEqual | System.String | Keep entries last written on the day this long ago, e.g. '1d'. |         |

**`$ChangeYoungerThan`**

| Name              | Type          | Description                                                | Default |
|-------------------|---------------|------------------------------------------------------------|---------|
| ChangeYoungerThan | System.String | Keep entries last written within this duration, e.g. '5d'. |         |

**`$ChangeOlderThan`**

| Name            | Type          | Description                                                 | Default |
|-----------------|---------------|-------------------------------------------------------------|---------|
| ChangeOlderThan | System.String | Keep entries last written longer ago than this, e.g. '10d'. |         |

**`$CreationTimeEqual`**

| Name              | Type          | Description                                               | Default |
|-------------------|---------------|-----------------------------------------------------------|---------|
| CreationTimeEqual | System.String | Keep entries created on the day this long ago, e.g. '1d'. |         |

**`$CreationYoungerThan`**

| Name                | Type          | Description                                           | Default |
|---------------------|---------------|-------------------------------------------------------|---------|
| CreationYoungerThan | System.String | Keep entries created within this duration, e.g. '5d'. |         |

**`$CreationOlderThan`**

| Name              | Type          | Description                                            | Default |
|-------------------|---------------|--------------------------------------------------------|---------|
| CreationOlderThan | System.String | Keep entries created longer ago than this, e.g. '10d'. |         |

**`$AccessYoungerThan`**

| Name              | Type          | Description                                                 | Default |
|-------------------|---------------|-------------------------------------------------------------|---------|
| AccessYoungerThan | System.String | Keep entries last accessed within this duration, e.g. '5d'. |         |

**`$AccessOlderThan`**

| Name            | Type          | Description                                                  | Default |
|-----------------|---------------|--------------------------------------------------------------|---------|
| AccessOlderThan | System.String | Keep entries last accessed longer ago than this, e.g. '10d'. |         |

**`$FileSizeGreaterThan`**

| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeGreaterThan | System.String | Keep files larger than this size, e.g. '20MB'. |         |

**`$FileSizeSmallerThan`**

| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeSmallerThan | System.String | Keep files smaller than this size, e.g. '5MB'. |         |

**`$IncludeFileList`**

| Name            | Type                                         | Description                               | Default |
|-----------------|----------------------------------------------|-------------------------------------------|---------|
| IncludeFileList | System.Management.Automation.SwitchParameter | Also return every kept entry in FileList. | False   |

**`$IgnoreMissingPath`**

| Name              | Type                                         | Description                                                    | Default |
|-------------------|----------------------------------------------|----------------------------------------------------------------|---------|
| IgnoreMissingPath | System.Management.Automation.SwitchParameter | Return an empty result instead of an error for a missing path. | False   |

#### Outputs

System.Collections.Hashtable -- Path, Exists, FileCount, FolderCount, TotalCount,
TotalSize, LargestFile, SmallestFile and AverageSize (sizes in bytes, the smallest
file is 0 when no file was kept) and FileList (the kept System.IO.FileSystemInfo
entries, empty unless IncludeFileList is set). Returns an IcingaError on failure.

#### Examples

```powershell
PS> Get-IcingaDirectoryInformation -Path 'C:\Backup' -FileNames '*.bak' -ChangeYoungerThan '1d'

Counts the backup files written within the last day.
```

```powershell
PS> Get-IcingaDirectoryInformation -Path 'D:\Logs' -Recurse -FileSizeGreaterThan '100MB' -IncludeFileList

Returns every log file larger than 100MB below D:\Logs together with the statistics.
```

#### Notes

Reads the file system through System.IO.DirectoryInfo; the user needs list
permission on every scanned directory. Relative paths are resolved against the
current PowerShell file system location. No external services are used.

*Source: [src/Plugins/Provider/FileSystem/Private/Get-IcingaDirectoryInformation.ps1](../src/Plugins/Provider/FileSystem/Private/Get-IcingaDirectoryInformation.ps1)*


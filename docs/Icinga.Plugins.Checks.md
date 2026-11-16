# Icinga.Plugins.Checks

*Auto-generated from `src/Plugins/Checks/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Invoke-IcingaCheckCPU](#invoke-icingacheckcpu)
- [Invoke-IcingaCheckDirectory](#invoke-icingacheckdirectory)
- [Invoke-IcingaCheckMemory](#invoke-icingacheckmemory)
- [Invoke-IcingaCheckPartitionSpace](#invoke-icingacheckpartitionspace)
- [Invoke-IcingaCheckPerfCounter](#invoke-icingacheckperfcounter)
- [Invoke-IcingaCheckProcess](#invoke-icingacheckprocess)
- [Invoke-IcingaCheckScheduledTask](#invoke-icingacheckscheduledtask)
- [Invoke-IcingaCheckService](#invoke-icingacheckservice)
- [Invoke-IcingaCheckUptime](#invoke-icingacheckuptime)

---

### Invoke-IcingaCheckCPU

*Public function*

**Synopsis:** Check the processor load per core, per NUMA node and in total against thresholds

#### Description

Reads the '\Processor Information(*)\% Processor Time' performance counter and
builds a single IcingaPlugin container named 'CPU Load'. Windows reports one
instance per logical processor as '<node>,<index>', where the first number is the
NUMA node and the second the index within that node. Every NUMA node becomes a
'NUMA Node #<node>' container holding a check per core plus its 'Node Total', and
the average of all cores becomes the 'Overall Load' check. The cores are numbered
across all nodes ('Core #0' to 'Core #<n-1>'), so the second node of a host with
eight cores per node starts at 'Core #8'. Every check is evaluated immediately
against the warning and critical thresholds, so the plugin reports
CRITICAL/WARNING as soon as any core, node or the total breaches its threshold
(the default 'all must be OK' aggregation).

NodeFilter (aliased to SocketFilter for legacy compatibility) narrows evaluation
to matching NUMA node IDs while preserving hardware core numbering. Core selects
'*' (all cores, node totals and Overall Load), '_Total' / 'Total' (only Overall
Load), or a specific core number/wildcard pattern. OverallOnly collects all NUMA
node and core checks and performance data, while applying Warning and Critical
thresholds exclusively to 'Overall Load'.

'Node Total' and 'Overall Load' are the averages of the core values read in the
same request. Windows' own '<node>,_Total' and '_Total' instances are not used,
because they are sampled in a slightly different window and would not match the
cores shown next to them.

The counter is declared through New-IcingaPerformanceCounter, so the
performance-counter daemon keeps it warm. Without a running daemon the first
read in a new process pays the counter warm-up. A failed read is reported as
UNKNOWN with the counter error, for the whole plugin or for the single core; the
averages then use the cores that could be read.

Compile() renders the nested plugin output, collects the performance data and
returns the Icinga exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN). On the
main thread the output is written to the console; inside a background daemon it
is stored in the thread-local runtime state for the REST API instead.

This plugin is Windows-only because it relies on the Windows performance counters.

#### Parameters

**`$Warning`**

| Name    | Type          | Description                                                        | Default |
|---------|---------------|--------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold in percent, using the Icinga threshold grammar.  |         |

**`$Critical`**

| Name     | Type          | Description                                                         | Default |
|----------|---------------|---------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold in percent, using the Icinga threshold grammar.  |         |

**`$Core`**

| Name | Type          | Description                                                                   | Default |
|------|---------------|-------------------------------------------------------------------------------|---------|
| Core | System.String | Core selector: '*' for all cores + totals, '_Total'/'Total' or a core number. | *       |

**`$NodeFilter`**

| Name       | Type         | Description                                                               | Default |
|------------|--------------|---------------------------------------------------------------------------|---------|
| NodeFilter | System.Array | NUMA node IDs to include (wildcards allowed; aliased to SocketFilter).    | @()     |

**`$OverallOnly`**

| Name        | Type                                         | Description                                                                  | Default |
|-------------|----------------------------------------------|------------------------------------------------------------------------------|---------|
| OverallOnly | System.Management.Automation.SwitchParameter | Collect all cores/nodes, but evaluate Warning/Critical only on Overall Load. | False   |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90

Warns at 80% and goes critical at 90% load for any core, NUMA node or the total.
```

```powershell
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90 -OverallOnly

Collects performance data for all cores and NUMA nodes, alerting only when
Overall Load breaches 80% or 90%.
```

```powershell
PS> Invoke-IcingaCheckCPU -Warning 80 -Critical 90 -Core '_Total'

Evaluates and emits performance data exclusively for Overall Load.
```

#### Notes

Windows-only. Reads the '\Processor Information(*)\% Processor Time' performance
counter; the user needs read access to the performance counters ('Performance
Monitor Users'). Perfdata labels are '<node>_<core>::ifw_cpu::load' with the core
numbered across all nodes, '<node>_total::ifw_cpu::load' and
'totalload::ifw_cpu::load'. The integer exit code is the return value; an Icinga
command wrapper is expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckCPU.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckCPU.ps1)*

---

### Invoke-IcingaCheckDirectory

*Public function*

**Synopsis:** Check the number and the sizes of the files in a directory against thresholds

#### Description

Reads the directory through Get-IcingaDirectoryInformation, which scans it once
and applies every name, time and size filter while reading, and builds a single
IcingaPlugin container named 'Directory Check: "<Path>"'. It holds the checks
'File Count', 'Folder Count', 'Total Size', 'Smallest File Size', 'Largest File
Size' and 'Average File Size' of the entries matching the filters, each evaluated
immediately against its own warning and critical thresholds, plus the
informational 'File Found' check.

Warning and Critical apply to the file count (with CountFolderAsFile the matching
folders are counted as well); the size thresholds accept sizes ('2GiB', '500MB')
and the full Icinga range grammar. Without OverrideNotFound a missing directory
is reported as UNKNOWN and 'File Found' only informs whether anything matched.
With OverrideNotFound a missing directory counts as an empty one and 'File Found'
takes the given state when nothing matches, so a missing backup file can be
reported as CRITICAL.

ShowFileList adds an informational 'File List' package with every matching entry
and its size; it raises the verbosity to at least 2 so the list is part of the
output. The list entries are not counted in the summary header.

Performance data uses the label '<path>::ifw_directory::<metric>' with the
metrics files, folders, totalsize, smallestfile, largestfile and averagefile,
sizes in bytes. A directory that cannot be read or an invalid filter value is
reported as UNKNOWN with its reason.

#### Parameters

**`$Path`**

| Name | Type          | Description                                     | Default |
|------|---------------|-------------------------------------------------|---------|
| Path | System.String | Directory to check, e.g. 'C:\ProgramData\Logs'. |         |

**`$FileNames`**

| Name      | Type         | Description                                          | Default |
|-----------|--------------|------------------------------------------------------|---------|
| FileNames | System.Array | Wildcard patterns for the entry names, e.g. '*.log'. | @('*')  |

**`$Recurse`**

| Name    | Type                                         | Description                       | Default |
|---------|----------------------------------------------|-----------------------------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Check every subdirectory as well. | False   |

**`$Warning`**

| Name    | Type          | Description                                         | Default |
|---------|---------------|-----------------------------------------------------|---------|
| Warning | System.String | Warning threshold for the number of matching files. |         |

**`$Critical`**

| Name     | Type          | Description                                          | Default |
|----------|---------------|------------------------------------------------------|---------|
| Critical | System.String | Critical threshold for the number of matching files. |         |

**`$WarningTotalSize`**

| Name             | Type          | Description                                        | Default |
|------------------|---------------|----------------------------------------------------|---------|
| WarningTotalSize | System.String | Warning threshold for the total size, e.g. '2GiB'. |         |

**`$CriticalTotalSize`**

| Name              | Type          | Description                                         | Default |
|-------------------|---------------|-----------------------------------------------------|---------|
| CriticalTotalSize | System.String | Critical threshold for the total size, e.g. '4GiB'. |         |

**`$WarningSmallestFile`**

| Name                | Type          | Description                                   | Default |
|---------------------|---------------|-----------------------------------------------|---------|
| WarningSmallestFile | System.String | Warning threshold for the smallest file size. |         |

**`$CriticalSmallestFile`**

| Name                 | Type          | Description                                    | Default |
|----------------------|---------------|------------------------------------------------|---------|
| CriticalSmallestFile | System.String | Critical threshold for the smallest file size. |         |

**`$WarningLargestFile`**

| Name               | Type          | Description                                  | Default |
|--------------------|---------------|----------------------------------------------|---------|
| WarningLargestFile | System.String | Warning threshold for the largest file size. |         |

**`$CriticalLargestFile`**

| Name                | Type          | Description                                   | Default |
|---------------------|---------------|-----------------------------------------------|---------|
| CriticalLargestFile | System.String | Critical threshold for the largest file size. |         |

**`$WarningAverageFile`**

| Name               | Type          | Description                                  | Default |
|--------------------|---------------|----------------------------------------------|---------|
| WarningAverageFile | System.String | Warning threshold for the average file size. |         |

**`$CriticalAverageFile`**

| Name                | Type          | Description                                   | Default |
|---------------------|---------------|-----------------------------------------------|---------|
| CriticalAverageFile | System.String | Critical threshold for the average file size. |         |

**`$CountFolderAsFile`**

| Name              | Type                                         | Description                                 | Default |
|-------------------|----------------------------------------------|---------------------------------------------|---------|
| CountFolderAsFile | System.Management.Automation.SwitchParameter | Add the matching folders to the file count. | False   |

**`$ShowFileList`**

| Name         | Type                                         | Description                                                | Default |
|--------------|----------------------------------------------|------------------------------------------------------------|---------|
| ShowFileList | System.Management.Automation.SwitchParameter | List every matching entry; can make the output very large. | False   |

**`$ChangeTimeEqual`**

| Name            | Type          | Description                                                    | Default |
|-----------------|---------------|----------------------------------------------------------------|---------|
| ChangeTimeEqual | System.String | Only entries last written on the day this long ago, e.g. '1d'. |         |

**`$ChangeYoungerThan`**

| Name              | Type          | Description                                                | Default |
|-------------------|---------------|------------------------------------------------------------|---------|
| ChangeYoungerThan | System.String | Only entries last written within this duration, e.g. '5d'. |         |

**`$ChangeOlderThan`**

| Name            | Type          | Description                                                 | Default |
|-----------------|---------------|-------------------------------------------------------------|---------|
| ChangeOlderThan | System.String | Only entries last written longer ago than this, e.g. '10d'. |         |

**`$CreationTimeEqual`**

| Name              | Type          | Description                                               | Default |
|-------------------|---------------|-----------------------------------------------------------|---------|
| CreationTimeEqual | System.String | Only entries created on the day this long ago, e.g. '1d'. |         |

**`$CreationOlderThan`**

| Name              | Type          | Description                                            | Default |
|-------------------|---------------|--------------------------------------------------------|---------|
| CreationOlderThan | System.String | Only entries created longer ago than this, e.g. '10d'. |         |

**`$CreationYoungerThan`**

| Name                | Type          | Description                                           | Default |
|---------------------|---------------|-------------------------------------------------------|---------|
| CreationYoungerThan | System.String | Only entries created within this duration, e.g. '5d'. |         |

**`$AccessYoungerThan`**

| Name              | Type          | Description                                                 | Default |
|-------------------|---------------|-------------------------------------------------------------|---------|
| AccessYoungerThan | System.String | Only entries last accessed within this duration, e.g. '5d'. |         |

**`$AccessOlderThan`**

| Name            | Type          | Description                                                  | Default |
|-----------------|---------------|--------------------------------------------------------------|---------|
| AccessOlderThan | System.String | Only entries last accessed longer ago than this, e.g. '10d'. |         |

**`$FileSizeGreaterThan`**

| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeGreaterThan | System.String | Only files larger than this size, e.g. '20MB'. |         |

**`$FileSizeSmallerThan`**

| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeSmallerThan | System.String | Only files smaller than this size, e.g. '5MB'. |         |

**`$OverrideNotFound`**

| Name             | Type          | Description                                                                                 | Default |
|------------------|---------------|---------------------------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State when nothing matches: Ok, Warning, Critical, Unknown; a missing path counts as empty. |         |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckDirectory -Path 'C:\Users\Icinga\Downloads' -Warning 20 -Critical 30

Warns when the directory holds more than 20 and goes critical with more than 30 files.
```

```powershell
PS> Invoke-IcingaCheckDirectory -Path 'D:\Logs' -Recurse -FileNames '*.log' -ChangeOlderThan '30d' -Critical 0

Goes critical as soon as any log file below D:\Logs is older than 30 days.
```

```powershell
PS> Invoke-IcingaCheckDirectory -Path 'C:\Backup' -FileNames '*.bak' -ChangeYoungerThan '1d' -OverrideNotFound 'Critical'

Goes critical when no backup file was written within the last day.
```

#### Notes

Windows-only. Reads the file system through Get-IcingaDirectoryInformation; the
user needs list permission on every checked directory. The integer exit code is
the return value; an Icinga command wrapper is expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckDirectory.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckDirectory.ps1)*

---

### Invoke-IcingaCheckMemory

*Public function*

**Synopsis:** Check the used physical memory, the memory paging rate and the page files against thresholds

#### Description

Builds a single IcingaPlugin container named 'Memory Usage' with the checks
'Used Memory' (installed physical memory minus the available memory, in bytes),
'Memory pages/sec' (hard page faults per second) and a 'PageFile Usage' package
with one check per page file (current usage in bytes). Every check is evaluated
immediately against its own warning and critical thresholds. The memory and page
file thresholds accept percentages of the respective size ('80%'), absolute sizes
('4GiB', '500MB') and the full Icinga range grammar.

The available memory and the paging rate are read in one request from the
'\Memory\Available Bytes' and '\Memory\Pages/sec' performance counters, which the
performance-counter daemon keeps warm. The installed memory comes from
Win32_ComputerSystem and the page files from Win32_PageFileUsage. A page file
with a configured maximum size (Win32_PageFileSetting, only read when Windows does
not manage the page files automatically) is measured against that maximum,
otherwise against its currently allocated size. IncludePageFile and
ExcludePageFile filter the page files by name (wildcards allowed); the package is
left out when no page file remains.

Performance data uses the labels 'memory::ifw_memory::used',
'memory::ifw_memory::pagessec' and '<pagefile>::ifw_pagefile::used' (for example
'cpagefilesys::ifw_pagefile::used'). A failed query or counter read is reported
as UNKNOWN with its reason.

#### Parameters

**`$Warning`**

| Name    | Type          | Description                                                         | Default |
|---------|---------------|---------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold for the used memory, e.g. '80%' or '12GiB'.       |         |

**`$Critical`**

| Name     | Type          | Description                                                         | Default |
|----------|---------------|---------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold for the used memory, e.g. '90%' or '14GiB'.      |         |

**`$PageFileWarning`**

| Name            | Type          | Description                                                  | Default |
|-----------------|---------------|--------------------------------------------------------------|---------|
| PageFileWarning | System.String | Warning threshold for every page file, e.g. '80%' or '2GiB'. |         |

**`$PageFileCritical`**

| Name             | Type          | Description                                                   | Default |
|------------------|---------------|---------------------------------------------------------------|---------|
| PageFileCritical | System.String | Critical threshold for every page file, e.g. '90%' or '3GiB'. |         |

**`$MemoryPagesSecWarning`**

| Name                  | Type          | Description                                   | Default |
|-----------------------|---------------|-----------------------------------------------|---------|
| MemoryPagesSecWarning | System.String | Warning threshold for the memory pages/sec.   |         |

**`$MemoryPagesSecCritical`**

| Name                   | Type          | Description                                   | Default |
|------------------------|---------------|-----------------------------------------------|---------|
| MemoryPagesSecCritical | System.String | Critical threshold for the memory pages/sec.  |         |

**`$IncludePageFile`**

| Name            | Type         | Description                                              | Default |
|-----------------|--------------|----------------------------------------------------------|---------|
| IncludePageFile | System.Array | Only check page files matching these names (wildcards).  | @()     |

**`$ExcludePageFile`**

| Name            | Type         | Description                                          | Default |
|-----------------|--------------|------------------------------------------------------|---------|
| ExcludePageFile | System.Array | Skip page files matching these names (wildcards).    | @()     |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckMemory -Warning '80%' -Critical '90%'

Warns at 80% and goes critical at 90% used physical memory.
```

```powershell
PS> Invoke-IcingaCheckMemory -Warning '12GiB' -Critical '14GiB' -PageFileWarning '75%' -Verbosity 2

Uses absolute memory thresholds, checks the page files against 75% and lists every check.
```

#### Notes

Windows-only. Reads the '\Memory\Available Bytes' and '\Memory\Pages/sec'
performance counters ('Performance Monitor Users') and the Win32_ComputerSystem,
Win32_PageFileUsage and Win32_PageFileSetting CIM classes. The integer exit code
is the return value; an Icinga command wrapper is expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckMemory.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckMemory.ps1)*

---

### Invoke-IcingaCheckPartitionSpace

*Public function*

**Synopsis:** Check the used or free space of the local partitions against thresholds

#### Description

Reads every local disk volume through Get-IcingaDiskInformation (Volume
entrypoint) and builds a single IcingaPlugin container named 'Used Partition
Space' (or 'Free Partition
Space' with CheckFreeSpace). Every volume becomes a child check whose value is
the used (or free) space in bytes, evaluated immediately against the warning and
critical thresholds with the volume size as base value. Thresholds therefore
accept percentages ('80%'), absolute sizes ('400GB', '1.5TiB') and the full Icinga
range grammar ('10%:' raises an alert below 10 percent).

Volumes with a drive letter are named after the letter ('C'), volumes without
one after their label, or their volume path when they have no label. Include,
Exclude and RequiredPartition match that name (wildcards allowed; 'C', 'C:' and
'C:\' all select drive C). Every RequiredPartition that does not exist on the
host is reported CRITICAL.

Performance data uses the label '<partition>::ifw_partitionspace::used' (or
'::free') in bytes, with the resolved thresholds in bytes and the volume size as
maximum.

A failed volume query is reported as UNKNOWN with its reason. This plugin is
Windows-only because it relies on the Win32_Volume CIM class.

#### Parameters

**`$Warning`**

| Name    | Type          | Description                                                                   | Default |
|---------|---------------|-------------------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold as percentage, size or Icinga range, e.g. '80%' or '400GB'. |         |

**`$Critical`**

| Name     | Type          | Description                                                                    | Default |
|----------|---------------|--------------------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold as percentage, size or Icinga range, e.g. '90%' or '450GB'. |         |

**`$Include`**

| Name    | Type         | Description                                                         | Default |
|---------|--------------|---------------------------------------------------------------------|---------|
| Include | System.Array | Only check partitions matching these letters or labels (wildcards). | @()     |

**`$Exclude`**

| Name    | Type         | Description                                                   | Default |
|---------|--------------|---------------------------------------------------------------|---------|
| Exclude | System.Array | Skip partitions matching these letters or labels (wildcards). | @()     |

**`$RequiredPartition`**

| Name              | Type         | Description                                                     | Default |
|-------------------|--------------|-----------------------------------------------------------------|---------|
| RequiredPartition | System.Array | Partitions that must exist; a missing one is reported CRITICAL. | @()     |

**`$CheckFreeSpace`**

| Name           | Type                                         | Description                                  | Default |
|----------------|----------------------------------------------|----------------------------------------------|---------|
| CheckFreeSpace | System.Management.Automation.SwitchParameter | Evaluate the free instead of the used space. | False   |

**`$IgnoreEmptyChecks`**

| Name              | Type                                         | Description                                                    | Default |
|-------------------|----------------------------------------------|----------------------------------------------------------------|---------|
| IgnoreEmptyChecks | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no partition matches at all. | False   |

**`$SkipUnknown`**

| Name        | Type                                         | Description                                                  | Default |
|-------------|----------------------------------------------|--------------------------------------------------------------|---------|
| SkipUnknown | System.Management.Automation.SwitchParameter | Report OK instead of UNKNOWN for a volume without size data. | False   |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckPartitionSpace -Warning '80%' -Critical '90%'

Warns at 80% and goes critical at 90% used space on any local partition.
```

```powershell
PS> Invoke-IcingaCheckPartitionSpace -CheckFreeSpace -Warning '50GB:' -Critical '10%:' -Include 'C', 'D'

Warns when less than 50GB and goes critical when less than 10% are free on C: or D:.
```

```powershell
PS> Invoke-IcingaCheckPartitionSpace -Warning '80%' -Critical '90%' -RequiredPartition 'E:' -Verbosity 2

Also reports CRITICAL when E: is missing and lists every partition in the output.
```

#### Notes

Windows-only. Reads Win32_Volume and MSFT_Partition through
Get-IcingaDiskInformation. The integer exit code is the
return value; an Icinga command wrapper is expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckPartitionSpace.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckPartitionSpace.ps1)*

---

### Invoke-IcingaCheckPerfCounter

*Public function*

**Synopsis:** Check any Windows performance counter against thresholds

#### Description

Reads every given performance counter in one request and builds a single
IcingaPlugin container named 'Performance Counter'. Every requested counter
becomes a package named after its path, holding one check per instance: a
wildcard path such as '\Processor(*)\% Processor Time' is expanded to every live
instance, a concrete path such as '\Memory\Available Bytes' yields one check. All
checks are evaluated immediately against the same warning and critical
thresholds, using the full Icinga range grammar.

Every value gets its unit from the counter type and name, so it is rendered and
compared through the unit conversion. Percent counters (name starting with '%'
or a percent counter type) use '%'. Timer counters such as 'Avg. Disk sec/Read',
'System Up Time' or 'Elapsed Time' are durations in seconds and render as '4ms'
or '1d 2h 3m 4s'; their thresholds accept durations ('30m', '1d:'). Counters with
'Bytes' in the name are sizes in bytes, 'KBytes' and 'MBytes' counters are scaled
to bytes as well; they render as '8.93GiB' and their thresholds accept sizes
('500MB'). Rates such as 'Pages/sec' and plain counts keep a plain number.

IncludeCounter and ExcludeCounter filter the instance paths (wildcards allowed,
for example '*_Total*'). An instance that cannot be read is skipped; when no
instance of a counter can be read, or a concrete counter fails, the counter is
reported as UNKNOWN with the first counter error. With IgnoreEmptyChecks the
plugin reports OK instead of UNKNOWN when the filters leave no counter at all.

Counters that are requested repeatedly are kept warm by the performance-counter
daemon. Without a running daemon the first read of a counter in a new process
pays the counter warm-up.

Performance data uses the label '<category>::ifw_perfcounter::<counter><instance>'
with '%' spelled out as 'percent', for example
'processor::ifw_perfcounter::percentprocessortime2' for core 2 or
'memory::ifw_perfcounter::availablebytes' for a counter without an instance.

#### Parameters

**`$PerfCounter`**

| Name        | Type         | Description                                                   | Default |
|-------------|--------------|---------------------------------------------------------------|---------|
| PerfCounter | System.Array | Counter paths to check, e.g. '\Processor(*)\% Processor Time'.| @()     |

**`$Warning`**

| Name    | Type          | Description                                                           | Default |
|---------|---------------|-----------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold in the counter's unit, e.g. '80', '500MB' or '30m'. |         |

**`$Critical`**

| Name     | Type          | Description                                                         | Default |
|----------|---------------|---------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold in the counter's unit, e.g. '90', '1GB' or '1h'. |         |

**`$IncludeCounter`**

| Name           | Type         | Description                                        | Default |
|----------------|--------------|----------------------------------------------------|---------|
| IncludeCounter | System.Array | Only check instance paths matching these patterns. | @()     |

**`$ExcludeCounter`**

| Name           | Type         | Description                                  | Default |
|----------------|--------------|----------------------------------------------|---------|
| ExcludeCounter | System.Array | Skip instance paths matching these patterns. | @()     |

**`$IgnoreEmptyChecks`**

| Name              | Type                                         | Description                                                    | Default |
|-------------------|----------------------------------------------|----------------------------------------------------------------|---------|
| IgnoreEmptyChecks | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no counter remains to check. | False   |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckPerfCounter -PerfCounter '\Processor(*)\% Processor Time' -Warning 80 -Critical 90 -ExcludeCounter '*_Total*'

Checks the load of every processor instance except the total.
```

```powershell
PS> Invoke-IcingaCheckPerfCounter -PerfCounter '\Memory\Pages/sec', '\System\Processor Queue Length' -Critical 10 -Verbosity 2

Checks two concrete counters against the same critical threshold.
```

#### Notes

Windows-only. Reads the Windows performance counters; the user needs read access
to them ('Performance Monitor Users'). The integer exit code is the return value;
an Icinga command wrapper is expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckPerfCounter.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckPerfCounter.ps1)*

---

### Invoke-IcingaCheckProcess

*Public function*

**Synopsis:** Check the CPU, memory, page file and thread usage of processes against thresholds

#### Description

Reads every process once through Get-IcingaProcessInformation and builds a single
IcingaPlugin container named 'Process Overview'. Every process name becomes a
package with one package per process ('<name> [<pid>]') and a '<name> Summary'
package holding the sums of all processes with that name. Each of them checks the
page file usage, the memory usage (private working set), the CPU usage and the
thread count; the summary also checks the process count.

The thresholds without 'Total' apply to every single process, the 'Total'
thresholds to the summary. Memory thresholds accept sizes ('500MB') and
percentages of the installed memory ('5%'). The page file usage is the commit
charge of the process; its percentages relate to the commit limit (installed
memory plus page files), because a commit charge can exceed the page file size. The CPU
usage is in percent of the whole machine (all logical processors), so '80' or
'80%' means 80 percent of the machine like in the task manager. All thresholds
accept the full Icinga range grammar.

Process and ExcludeProcess select the processes by name without '.exe'
(wildcards allowed). Every entry of Process that matches no running process is
reported with the state chosen with OverrideNotFound (UNKNOWN by default). Without
Process every process is checked; for a plain process count of the whole system
this is more output than needed.

Performance data is written for the summary only, with the labels
'<name>::ifw_process::cpu', '::memory', '::pagefile', '::threads' and '::count'.

#### Parameters

**`$PageFileWarning`**

| Name            | Type          | Description                                                     | Default |
|-----------------|---------------|-----------------------------------------------------------------|---------|
| PageFileWarning | System.String | Warning threshold for the page file usage of each process.      |         |

**`$PageFileCritical`**

| Name             | Type          | Description                                                     | Default |
|------------------|---------------|-----------------------------------------------------------------|---------|
| PageFileCritical | System.String | Critical threshold for the page file usage of each process.     |         |

**`$MemoryWarning`**

| Name          | Type          | Description                                                 | Default |
|---------------|---------------|-------------------------------------------------------------|---------|
| MemoryWarning | System.String | Warning threshold for the memory usage of each process.     |         |

**`$MemoryCritical`**

| Name           | Type          | Description                                                 | Default |
|----------------|---------------|-------------------------------------------------------------|---------|
| MemoryCritical | System.String | Critical threshold for the memory usage of each process.    |         |

**`$CPUWarning`**

| Name       | Type          | Description                                              | Default |
|------------|---------------|----------------------------------------------------------|---------|
| CPUWarning | System.String | Warning threshold for the CPU usage of each process.     |         |

**`$CPUCritical`**

| Name        | Type          | Description                                              | Default |
|-------------|---------------|----------------------------------------------------------|---------|
| CPUCritical | System.String | Critical threshold for the CPU usage of each process.    |         |

**`$ThreadCountWarning`**

| Name               | Type          | Description                                                | Default |
|--------------------|---------------|------------------------------------------------------------|---------|
| ThreadCountWarning | System.String | Warning threshold for the thread count of each process.    |         |

**`$ThreadCountCritical`**

| Name                | Type          | Description                                                | Default |
|---------------------|---------------|------------------------------------------------------------|---------|
| ThreadCountCritical | System.String | Critical threshold for the thread count of each process.   |         |

**`$TotalPageFileWarning`**

| Name                 | Type          | Description                                                           | Default |
|----------------------|---------------|-----------------------------------------------------------------------|---------|
| TotalPageFileWarning | System.String | Warning threshold for the page file usage of all processes of a name. |         |

**`$TotalPageFileCritical`**

| Name                  | Type          | Description                                                            | Default |
|-----------------------|---------------|------------------------------------------------------------------------|---------|
| TotalPageFileCritical | System.String | Critical threshold for the page file usage of all processes of a name. |         |

**`$TotalMemoryWarning`**

| Name               | Type          | Description                                                        | Default |
|--------------------|---------------|--------------------------------------------------------------------|---------|
| TotalMemoryWarning | System.String | Warning threshold for the memory usage of all processes of a name. |         |

**`$TotalMemoryCritical`**

| Name                | Type          | Description                                                         | Default |
|---------------------|---------------|---------------------------------------------------------------------|---------|
| TotalMemoryCritical | System.String | Critical threshold for the memory usage of all processes of a name. |         |

**`$TotalCPUWarning`**

| Name            | Type          | Description                                                     | Default |
|-----------------|---------------|-----------------------------------------------------------------|---------|
| TotalCPUWarning | System.String | Warning threshold for the CPU usage of all processes of a name. |         |

**`$TotalCPUCritical`**

| Name             | Type          | Description                                                      | Default |
|------------------|---------------|------------------------------------------------------------------|---------|
| TotalCPUCritical | System.String | Critical threshold for the CPU usage of all processes of a name. |         |

**`$TotalThreadCountWarning`**

| Name                    | Type          | Description                                                       | Default |
|-------------------------|---------------|-------------------------------------------------------------------|---------|
| TotalThreadCountWarning | System.String | Warning threshold for the thread count of all processes of a name.|         |

**`$TotalThreadCountCritical`**

| Name                     | Type          | Description                                                        | Default |
|--------------------------|---------------|--------------------------------------------------------------------|---------|
| TotalThreadCountCritical | System.String | Critical threshold for the thread count of all processes of a name.|         |

**`$TotalProcessCountWarning`**

| Name                     | Type          | Description                                              | Default |
|--------------------------|---------------|----------------------------------------------------------|---------|
| TotalProcessCountWarning | System.String | Warning threshold for the number of processes of a name. |         |

**`$TotalProcessCountCritical`**

| Name                      | Type          | Description                                               | Default |
|---------------------------|---------------|-----------------------------------------------------------|---------|
| TotalProcessCountCritical | System.String | Critical threshold for the number of processes of a name. |         |

**`$Process`**

| Name    | Type         | Description                                                                 | Default |
|---------|--------------|-----------------------------------------------------------------------------|---------|
| Process | System.Array | Process names without '.exe' to check, wildcards allowed. Empty checks all. | @()     |

**`$ExcludeProcess`**

| Name           | Type         | Description                               | Default |
|----------------|--------------|-------------------------------------------|---------|
| ExcludeProcess | System.Array | Process names to skip, wildcards allowed. | @()     |

**`$OverrideNotFound`**

| Name             | Type          | Description                                                                   | Default |
|------------------|---------------|-------------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State for a Process entry without a match: Ok, Warning, Critical or Unknown.  | Unknown |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckProcess -Process 'powershell' -Verbosity 2

Lists every PowerShell process and the summary of all of them.
```

```powershell
PS> Invoke-IcingaCheckProcess -Process 'sqlservr' -CPUWarning '80' -TotalMemoryCritical '90%' -TotalProcessCountCritical '1:'

Warns when one SQL Server process uses more than 80 percent of the machine, and
goes critical when all of them use more than 90 percent of the memory or none runs.
```

#### Notes

Windows-only. Reads the '\Process(*)' performance counters ('Performance Monitor
Users'), '\Memory\Commit Limit' and the Win32_ComputerSystem CIM class through
Get-IcingaProcessInformation. The integer exit code is the return value; an Icinga
command wrapper is expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckProcess.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckProcess.ps1)*

---

### Invoke-IcingaCheckScheduledTask

*Public function*

**Synopsis:** Check the state, exit code, missed runs and run times of Windows scheduled tasks

#### Description

Reads scheduled tasks through Get-IcingaScheduledTask and builds an IcingaPlugin
container named 'Scheduled Tasks' grouped by task path. Each task becomes a child
package containing checks for its State, Missed Runs, Last Task Result, Last Run
Time and Next Run Time. State is compared against the allowed State list (when
provided) using CheckNotIn, raising CRITICAL when the task is not in any of the
expected states. Missed Runs is evaluated against WarningMissedRuns and
CriticalMissedRuns using the Icinga range grammar. Last Task Result treats
Windows Scheduler informational codes 267009 (0x41301, SCHED_S_TASK_RUNNING,
while the task State is Running) and 267011 (0x41303, SCHED_S_TASK_HAS_NOT_RUN)
as OK by default, and raises CRITICAL on any other non-zero exit code unless
IgnoreLastRunTime (aliased to IgnoreLastResult and IgnoreExitCode) is set or the
code is listed in IgnoreExitCodes (decimal, unsigned and 32-bit masked hex
representations such as '0x80070005' or '0x41301' are all accepted). Last Run
Time and Next Run Time measure the offset in seconds between the current time
and the timestamp (Last Run Time counts up since the last execution, Next Run
Time counts down until the next scheduled execution, and 0s is rendered as
'Never' when unset) and are evaluated against their respective duration
thresholds.

Explicit task names in TaskName (without wildcards) that do not exist on the host
are reported with the state chosen by OverrideNotFound (UNKNOWN by default). When
no task matches the filter at all, the plugin returns UNKNOWN, or OK when
MitigateUnknown (aliased to IgnoreEmptyChecks) is set.

Performance data uses the labels '<path_taskname>::ifw_scheduledtask::state',
'::missedruns', '::lasttaskresult', '::lastruntime' and '::nextruntime'.

#### Parameters

**`$TaskName`**

| Name     | Type         | Description                                                                   | Default |
|----------|--------------|-------------------------------------------------------------------------------|---------|
| TaskName | System.Array | Task names to check (wildcards allowed; plain names must exist).              | @()     |

**`$ExcludeTaskName`**

| Name            | Type         | Description                                                            | Default |
|-----------------|--------------|------------------------------------------------------------------------|---------|
| ExcludeTaskName | System.Array | Task names to exclude from the check (wildcards allowed).              | @()     |

**`$TaskPath`**

| Name     | Type         | Description                                                                   | Default |
|----------|--------------|-------------------------------------------------------------------------------|---------|
| TaskPath | System.Array | Task folder paths to include (wildcards allowed, e.g. '\Icinga\*').           | @()     |

**`$ExcludeTaskPath`**

| Name            | Type         | Description                                                            | Default |
|-----------------|--------------|------------------------------------------------------------------------|---------|
| ExcludeTaskPath | System.Array | Task folder paths to exclude (wildcards allowed).                      | @()     |

**`$State`**

| Name  | Type                        | Description                                                                | Default |
|-------|-----------------------------|----------------------------------------------------------------------------|---------|
| State | IcingaScheduledTaskStatus[] | Allowed task states ('Unknown', 'Disabled', 'Queued', 'Ready', 'Running'). | @()     |

**`$IgnoreExitCodes`**

| Name            | Type         | Description                                                            | Default |
|-----------------|--------------|------------------------------------------------------------------------|---------|
| IgnoreExitCodes | System.Array | Non-zero task exit codes to treat as OK (decimal or hex, e.g. 267009). | @()     |

**`$WarningMissedRuns`**

| Name              | Type          | Description                                                         | Default |
|-------------------|---------------|---------------------------------------------------------------------|---------|
| WarningMissedRuns | System.String | Warning threshold for the number of missed runs.                    |         |

**`$CriticalMissedRuns`**

| Name               | Type          | Description                                                        | Default |
|--------------------|---------------|--------------------------------------------------------------------|---------|
| CriticalMissedRuns | System.String | Critical threshold for the number of missed runs.                  |         |

**`$WarningLastRunTime`**

| Name               | Type          | Description                                                        | Default |
|--------------------|---------------|--------------------------------------------------------------------|---------|
| WarningLastRunTime | System.String | Warning threshold for the age of the last run (e.g. '1d', '12h').  |         |

**`$CriticalLastRunTime`**

| Name                | Type          | Description                                                       | Default |
|---------------------|---------------|-------------------------------------------------------------------|---------|
| CriticalLastRunTime | System.String | Critical threshold for the age of the last run (e.g. '2d', '24h').|         |

**`$WarningNextRunTime`**

| Name               | Type          | Description                                                        | Default |
|--------------------|---------------|--------------------------------------------------------------------|---------|
| WarningNextRunTime | System.String | Warning threshold for the next run offset (e.g. '10m', '-1h:').    |         |

**`$CriticalNextRunTime`**

| Name                | Type          | Description                                                       | Default |
|---------------------|---------------|-------------------------------------------------------------------|---------|
| CriticalNextRunTime | System.String | Critical threshold for the next run offset (e.g. '30m', '-2h:').  |         |

**`$IgnoreLastRunTime`**

| Name              | Type                                         | Description                                        | Default |
|-------------------|----------------------------------------------|----------------------------------------------------|---------|
| IgnoreLastRunTime | System.Management.Automation.SwitchParameter | Do not alert on non-zero Last Task Result codes.   | False   |

**`$MitigateUnknown`**

| Name            | Type                                         | Description                                                  | Default |
|-----------------|----------------------------------------------|--------------------------------------------------------------|---------|
| MitigateUnknown | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no task matches the filter.| False   |

**`$OverrideNotFound`**

| Name             | Type          | Description                                                               | Default |
|------------------|---------------|---------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State for missing required tasks ('Ok', 'Warning', 'Critical', 'Unknown').| Unknown |

**`$Verbosity`**

| Name      | Type         | Description                                                                         | Default |
|-----------|--------------|-------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config. | 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckScheduledTask -TaskName 'AutomaticBackup', 'Windows Backup Monitor' -State 'Ready'

Checks that both backup tasks exist and are in the Ready state.
```

```powershell
PS> Invoke-IcingaCheckScheduledTask -TaskPath '\Icinga\*' -State 'Ready', 'Running' -WarningLastRunTime '1d' -Verbosity 2

Checks all tasks under \Icinga\ for Ready or Running state and warns if a task has not run within the last day.
```

#### Notes

Windows-only. Queries tasks through Get-IcingaScheduledTask. The integer exit code
is the return value; an Icinga command wrapper is expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckScheduledTask.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckScheduledTask.ps1)*

---

### Invoke-IcingaCheckService

*Public function*

**Synopsis:** Check the state of Windows services against one or more expected statuses

#### Description

Queries every service from the Win32_Service CIM class once and builds a single
IcingaPlugin container named 'Services'. Each selected service becomes a child
check comparing its current state with the expected Status list; a mismatch
raises the state chosen with OverrideNotOk (CRITICAL by default).

When no service is given, every service with the 'Automatic' start mode is
checked: it is expected to be running, except when it is stopped with exit code
0, which means it ended on purpose and is reported OK. When services are given
by name or display name (wildcards allowed), they are compared against Status
(supporting both single statuses and multi-status lists), optionally narrowed
down by their startup type. Every given name without a wildcard that matches no
service on the system is reported with the state chosen with OverrideNotFound
(UNKNOWN by default).

Service states and startup types are resolved through the IcingaServiceStatus
and IcingaServiceStartupType data types. Performance data contains the numeric
state of each explicitly selected service ('<service>::ifw_service::state', 0
Unknown, 1 Stopped to 7 Paused) and per-state counters of all checked services
('summary::ifw_service::<state>' and '::count').

This plugin is Windows-only because it relies on the Win32_Service CIM class.

#### Parameters

**`$Service`**

| Name    | Type         | Description                                                                                      | Default |
|---------|--------------|--------------------------------------------------------------------------------------------------|---------|
| Service | System.Array | Service names or display names to check, wildcards allowed. Empty checks all automatic services. | @()     |

**`$Exclude`**

| Name    | Type         | Description                                                | Default |
|---------|--------------|------------------------------------------------------------|---------|
| Exclude | System.Array | Service names or display names to skip, wildcards allowed. | @()     |

**`$Status`**

| Name   | Type                  | Description                                                                                                                            | Default    |
|--------|-----------------------|----------------------------------------------------------------------------------------------------------------------------------------|------------|
| Status | IcingaServiceStatus[] | Expected status(es) of the given services: Stopped, StartPending, StopPending, Running, ContinuePending, PausePending, Paused, Unknown.| @(Running) |

**`$FilterStartupType`**

| Name              | Type                       | Description                                                                                                    | Default |
|-------------------|----------------------------|----------------------------------------------------------------------------------------------------------------|---------|
| FilterStartupType | IcingaServiceStartupType[] | Only check given services with one of these startup types: Boot, System, Automatic, Manual, Disabled, Unknown. | @()     |

**`$MitigateUnknown`**

| Name            | Type                                         | Description                                                  | Default |
|-----------------|----------------------------------------------|--------------------------------------------------------------|---------|
| MitigateUnknown | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no service matches at all. | False   |

**`$OverrideNotOk`**

| Name          | Type          | Description                                                                     | Default  |
|---------------|---------------|---------------------------------------------------------------------------------|----------|
| OverrideNotOk | System.String | State for a service not in the expected status: Ok, Warning, Critical, Unknown. | Critical |

**`$OverrideNotFound`**

| Name             | Type          | Description                                                                    | Default |
|------------------|---------------|--------------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State for a given service that does not exist: Ok, Warning, Critical, Unknown. | Unknown |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckService

Checks that every automatic service is running or ended with exit code 0.
```

```powershell
PS> Invoke-IcingaCheckService -Service 'Spooler', 'W32Time' -OverrideNotOk 'Warning'

Warns when the print spooler or the time service is not running.
```

```powershell
PS> Invoke-IcingaCheckService -Service 'Windows Update*' -Exclude 'wuauserv' -Status 'Stopped' -Verbosity 2

Expects every service whose display name starts with 'Windows Update', except
wuauserv, to be stopped and lists all of them in the output.
```

#### Notes

Windows-only. Reads the Win32_Service CIM class through
Get-IcingaWindowsInformation; a failed query is reported as UNKNOWN with its
reason. The integer exit code is the return value; an Icinga command wrapper is
expected to exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckService.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckService.ps1)*

---

### Invoke-IcingaCheckUptime

*Public function*

**Synopsis:** Check the time since the last system start against thresholds

#### Description

Reads the '\System\System Up Time' performance counter and builds a single
IcingaPlugin container named 'System Uptime: <uptime>' with the check 'System
Uptime' (whole seconds since the last start, shown as a duration such as
'1d 2h 3m 4s') and the informational 'Last Boot' entry with the start time. The
check is evaluated immediately against the warning and critical thresholds, which
accept durations with an Icinga time unit and the full Icinga range grammar:
'1d:' raises an alert while the system runs shorter than one day (a recent
reboot), '30d' while it runs longer than 30 days.

The counter is declared through New-IcingaPerformanceCounter, so the
performance-counter daemon keeps it warm. A failed read is reported as UNKNOWN
with the counter error.

Performance data uses the label 'windows::ifw_uptime::uptime' in seconds.

#### Parameters

**`$Warning`**

| Name    | Type          | Description                                              | Default |
|---------|---------------|----------------------------------------------------------|---------|
| Warning | System.String | Warning threshold as duration or range, e.g. '1d:'.      |         |

**`$Critical`**

| Name     | Type          | Description                                              | Default |
|----------|---------------|----------------------------------------------------------|---------|
| Critical | System.String | Critical threshold as duration or range, e.g. '30m:'.    |         |

**`$Verbosity`**

| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

**`$NoPerfData`**

| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

#### Outputs

System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

#### Examples

```powershell
PS> Invoke-IcingaCheckUptime -Warning '1d:' -Critical '30m:'

Warns during the first day after a reboot and goes critical during the first 30 minutes.
```

```powershell
PS> Invoke-IcingaCheckUptime -Warning '60d' -Verbosity 2

Warns when the system has not been restarted for more than 60 days.
```

#### Notes

Windows-only. Reads the '\System\System Up Time' performance counter; the user
needs read access to the performance counters ('Performance Monitor Users'). The
integer exit code is the return value; an Icinga command wrapper is expected to
exit with it.

*Source: [src/Plugins/Checks/Public/Invoke-IcingaCheckUptime.ps1](../../src/Plugins/Checks/Public/Invoke-IcingaCheckUptime.ps1)*


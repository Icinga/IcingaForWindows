# Icinga.Plugins.Provider.Process

*Auto-generated from `src/Plugins/Provider/Process/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [Get-IcingaProcessInformation](#get-icingaprocessinformation)

---

### Get-IcingaProcessInformation

*Private function*

**Synopsis:** Collect the CPU, memory, page file and thread usage of every running process

#### Description

Get-IcingaProcessInformation is the data source of the process plugins. It reads
the counters 'ID Process', '% Processor Time', 'Working Set - Private',
'Page File Bytes' and 'Thread Count' of every process in one request from the
'\Process(*)' performance counter category, which the performance-counter daemon
keeps warm through a single category snapshot. The installed memory and the number
of logical processors come from Win32_ComputerSystem, the commit limit from the
'\Memory\Commit Limit' counter.

The page file usage of a process is its commit charge ('Page File Bytes'): the
private memory the system guarantees to back with the page files. It can exceed the
size of the page files, so it is measured against the commit limit (installed
memory plus page files), which no commit charge can exceed.

Processes are grouped by name. Windows names the counter instances of several
processes with the same name 'name', 'name#1', 'name#2' and so on; the suffix is
removed and every process is keyed by its process id. The '_Total' and 'Idle'
instances (process id 0) are left out. Include and Exclude filter the process
names (wildcards allowed, without '.exe').

The CPU usage of the counter is relative to one logical processor and is divided
by the number of logical processors, so 100 means the whole machine like in the
task manager. Win32_ComputerSystem is used for that number because
[Environment]::ProcessorCount only covers one processor group on Windows
PowerShell 5.1.

#### Parameters

**`$Include`**

| Name    | Type         | Description                                              | Default |
|---------|--------------|----------------------------------------------------------|---------|
| Include | System.Array | Only collect processes matching these names (wildcards). | @()     |

**`$Exclude`**

| Name    | Type         | Description                                      | Default |
|---------|--------------|--------------------------------------------------|---------|
| Exclude | System.Array | Skip processes matching these names (wildcards). | @()     |

#### Outputs

System.Collections.Hashtable -- Keys Processes, MemoryTotal, CommitLimit and
LogicalProcessors, or an IcingaError when the data could not be read. Processes is
keyed by process name; every entry holds Name, Instances (keyed by process id, each
with Id, Cpu, Memory, PageFile and Threads) and Total (Cpu, Memory, PageFile,
Threads and Count). Cpu is in percent of the machine, Memory (private working set),
PageFile and the totals are in bytes.

#### Examples

```powershell
PS> (Get-IcingaProcessInformation -Include 'powershell').Processes['powershell'].Total

Returns the summed usage of all PowerShell processes.
```

#### Notes

Windows-only. Reads the '\Process(*)' performance counters ('Performance Monitor
Users'), '\Memory\Commit Limit' and the Win32_ComputerSystem CIM class. Without a
running daemon the first call in a runspace waits for the counter warm-up.

*Source: [src/Plugins/Provider/Process/Private/Get-IcingaProcessInformation.ps1](../src/Plugins/Provider/Process/Private/Get-IcingaProcessInformation.ps1)*


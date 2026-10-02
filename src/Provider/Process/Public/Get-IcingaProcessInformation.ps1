<#
.SYNOPSIS
Collect the CPU, memory, page file and thread usage of every running process

.DESCRIPTION
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

.PARAMETER Include
| Name    | Type         | Description                                              | Default |
|---------|--------------|----------------------------------------------------------|---------|
| Include | System.Array | Only collect processes matching these names (wildcards). | @()     |

.PARAMETER Exclude
| Name    | Type         | Description                                         | Default |
|---------|--------------|-----------------------------------------------------|---------|
| Exclude | System.Array | Skip processes matching these names (wildcards).    | @()     |

.OUTPUTS
System.Collections.Hashtable — Keys Processes, MemoryTotal, CommitLimit and
LogicalProcessors, or an IcingaError when the data could not be read. Processes is
keyed by process name; every entry holds Name, Instances (keyed by process id, each
with Id, Cpu, Memory, PageFile and Threads) and Total (Cpu, Memory, PageFile,
Threads and Count). Cpu is in percent of the machine, Memory (private working set),
PageFile and the totals are in bytes.

.EXAMPLE
PS> (Get-IcingaProcessInformation -Include 'powershell').Processes['powershell'].Total

Returns the summed usage of all PowerShell processes.

.NOTES
Windows-only. Reads the '\Process(*)' performance counters ('Performance Monitor
Users'), '\Memory\Commit Limit' and the Win32_ComputerSystem CIM class. Without a
running daemon the first call in a runspace waits for the counter warm-up.
#>
function Get-IcingaProcessInformation()
{
    param (
        [array]$Include = @(),
        [array]$Exclude = @()
    );

    # Literal declaration, so the counter discovery at module start finds and warms them.
    New-IcingaPerformanceCounter -Counter @('\Process(*)\ID Process', '\Process(*)\% Processor Time', '\Process(*)\Working Set - Private', '\Process(*)\Page File Bytes', '\Process(*)\Thread Count', '\Memory\Commit Limit');

    $ComputerSystem = Get-IcingaWindowsInformation -ClassName 'Win32_ComputerSystem' -Property 'TotalPhysicalMemory', 'NumberOfLogicalProcessors';

    if (Test-IcingaError -InputObject $ComputerSystem) {
        return $ComputerSystem;
    }

    $Counters = Get-IcingaPerformanceCounter -Counter @('\Process(*)\ID Process', '\Process(*)\% Processor Time', '\Process(*)\Working Set - Private', '\Process(*)\Page File Bytes', '\Process(*)\Thread Count') -StructureByInstance;

    if ($null -eq $Counters -or $Counters.Count -eq 0) {
        [hashtable]$ErrorData = @{ 'Counter' = '\Process(*)'; };
        return (Write-FunctionReturnValue -ReturnValue 'ProcessCounterReadFailed' -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new('ProcessCounterReadFailed', 'The performance counters of the category Process could not be read', $ErrorData)));
    }

    # Read on its own, so a process named like the category cannot collide with it in
    # the structured result.
    $Memory      = Get-IcingaPerformanceCounter -Counter '\Memory\Commit Limit';
    $CommitLimit = $null;

    if ($null -ne $Memory) {
        $CommitLimit = Get-IcingaPerformanceCounterValue -InputObject $Memory['\Memory\Commit Limit'];
    }

    if ($null -eq $CommitLimit -or $CommitLimit -is [string]) {
        [hashtable]$ErrorData = @{ 'Counter' = '\Memory\Commit Limit'; 'Error' = [string]$CommitLimit; };
        return (Write-FunctionReturnValue -ReturnValue 'ProcessCounterReadFailed' -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new('ProcessCounterReadFailed', 'The performance counter \Memory\Commit Limit could not be read', $ErrorData)));
    }

    [double]$Processors   = [System.Math]::Max([double]1, [double]$ComputerSystem[0].NumberOfLogicalProcessors);
    [hashtable]$Processes = @{ };

    foreach ($InstanceName in $Counters.Keys) {
        $Values = $Counters[$InstanceName]['Process'];

        if ($null -eq $Values) {
            continue;
        }

        # An instance that ended between the snapshots has no readable id.
        $Id = Get-IcingaPerformanceCounterValue -InputObject $Values['ID Process'];

        if ($null -eq $Id -or $Id -is [string] -or [int]$Id -eq 0) {
            continue;
        }

        # Windows replaces a '#' in a process name, so only the duplicate suffix uses it.
        [string]$Name = $InstanceName;
        [int]$Suffix  = $Name.LastIndexOf('#');

        if ($Suffix -gt 0) {
            $Name = $Name.Substring(0, $Suffix);
        }

        if ((Test-IcingaArrayFilter -InputObject $Name -Include $Include -Exclude $Exclude) -eq $false) {
            continue;
        }

        [double]$Cpu      = 0;
        [uint64]$Memory   = 0;
        [uint64]$PageFile = 0;
        [int]$Threads     = 0;

        $Value = Get-IcingaPerformanceCounterValue -InputObject $Values['% Processor Time'];
        if ($null -ne $Value -and $Value -isnot [string]) {
            $Cpu = [double]$Value / $Processors;
        }

        $Value = Get-IcingaPerformanceCounterValue -InputObject $Values['Working Set - Private'];
        if ($null -ne $Value -and $Value -isnot [string]) {
            $Memory = [uint64]$Value;
        }

        $Value = Get-IcingaPerformanceCounterValue -InputObject $Values['Page File Bytes'];
        if ($null -ne $Value -and $Value -isnot [string]) {
            $PageFile = [uint64]$Value;
        }

        $Value = Get-IcingaPerformanceCounterValue -InputObject $Values['Thread Count'];
        if ($null -ne $Value -and $Value -isnot [string]) {
            $Threads = [int]$Value;
        }

        if ($Processes.ContainsKey($Name) -eq $false) {
            $Processes[$Name] = @{
                'Name'      = $Name;
                'Instances' = @{ };
                'Total'     = @{
                    'Cpu'      = [double]0;
                    'Memory'   = [uint64]0;
                    'PageFile' = [uint64]0;
                    'Threads'  = 0;
                    'Count'    = 0;
                };
            };
        }

        $Entry = $Processes[$Name];

        $Entry['Instances'][[string][int]$Id] = @{
            'Id'       = [int]$Id;
            'Cpu'      = [System.Math]::Round($Cpu, 2);
            'Memory'   = $Memory;
            'PageFile' = $PageFile;
            'Threads'  = $Threads;
        };

        $Entry['Total']['Cpu']      += $Cpu;
        $Entry['Total']['Memory']   += $Memory;
        $Entry['Total']['PageFile'] += $PageFile;
        $Entry['Total']['Threads']  += $Threads;
        $Entry['Total']['Count']    += 1;
    }

    # The totals are summed unrounded and rounded once, so they match the processes.
    foreach ($Entry in $Processes.Values) {
        $Entry['Total']['Cpu'] = [System.Math]::Round([double]$Entry['Total']['Cpu'], 2);
    }

    [hashtable]$Result = @{
        'Processes'         = $Processes;
        'MemoryTotal'       = [uint64]$ComputerSystem[0].TotalPhysicalMemory;
        'CommitLimit'       = [uint64]$CommitLimit;
        'LogicalProcessors' = [int]$Processors;
    };

    return (Write-FunctionReturnValue -ReturnValue 'ProcessInformationCollected' -Data @{ 'Count' = $Processes.Count; } -OverrideReturn $Result);
}

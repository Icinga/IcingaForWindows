# Performance Counter Usability and Developer Guide

This guide explains how to discover, query, pre-declare, and process Windows Performance Counters in Icinga for Windows, both interactively on the command line and inside data providers or check plugins.

For internal class specifications, daemon architecture, and runspace isolation details, see [`01-Technical-Architecture-and-Reference.md`](01-Technical-Architecture-and-Reference.md).

---

## 1. Quick Start: Interactive Discovery and Inspection

Icinga for Windows provides four public cmdlets for working with performance counters:

| Cmdlet | Purpose |
| :--- | :--- |
| `Show-IcingaPerformanceCounter` | Browse available categories, counter paths within a category, or live instances for a wildcard counter. |
| `Test-IcingaPerformanceCounterCategory` | Check whether a performance counter category exists on the local machine without throwing exceptions. |
| `Get-IcingaPerformanceCounter` | Read live values for one or more concrete or wildcard performance counter paths. |
| `Show-IcingaPerformanceCounterDetails` | Inspect live values for all currently registered counters (or a filtered subset). |

### Step 1: Browse Categories (`Show-IcingaPerformanceCounter`)
List all performance counter categories on the system, or filter them using a wildcard pattern (`-Filter`):

```powershell
# List all available categories on the machine
Show-IcingaPerformanceCounter

# Filter categories by wildcard
Show-IcingaPerformanceCounter -Filter '*Disk*'
```

Example output:
```text
LogicalDisk
PhysicalDisk
```

### Step 2: List Counters Inside a Category (`-Category`)
Pass `-Category` to inspect all counter paths exposed by that category. Multi-instance categories automatically emit wildcard paths (`\Category(*)\Counter`), while single-instance categories emit direct paths (`\Category\Counter`):

```powershell
# Multi-instance category (emits '\Processor(*)\...')
Show-IcingaPerformanceCounter -Category 'Processor'

# Single-instance category (emits '\Memory\...')
Show-IcingaPerformanceCounter -Category 'Memory'
```

### Step 3: List Live Instances for a Wildcard Path (`-Counter`)
Pass a wildcard path to `-Counter` to see the exact per-instance counter paths that currently exist on the system:

```powershell
Show-IcingaPerformanceCounter -Counter '\PhysicalDisk(*)\Disk Reads/sec'
```

Example output:
```text
\PhysicalDisk(0 C:)\Disk Reads/sec
\PhysicalDisk(_Total)\Disk Reads/sec
```

### Step 4: Inspect Registered Counters (`Show-IcingaPerformanceCounterDetails`)
To see the live values of all counters currently registered in the Icinga for Windows store (or a specific subset):

```powershell
# Dump all registered counters
Show-IcingaPerformanceCounterDetails

# Dump all registered counters reshaped by instance/category
Show-IcingaPerformanceCounterDetails -StructureByInstance
```

---

## 2. Supported Counter Path Formats

`Get-IcingaPerformanceCounter` and `Test-IcingaPerformanceCounterCategory` accept standard Windows Performance Counter paths in the following formats:

| Format | Example | Description |
| :--- | :--- | :--- |
| **Single-Instance Path** | `\Memory\Available Bytes` | Reads a counter from a category that has no instances. |
| **Concrete Instance Path** | `\Processor(_Total)\% Processor Time` | Reads a specific named instance (`_Total`, `0`, `0 C:`, etc.). |
| **Wildcard Instance Path** | `\Processor(*)\% Processor Time` | Reads all live instances of the category in a single category snapshot. |
| **Local Host Prefixed Path** | `\\.\Memory\Available Bytes`<br>`\\localhost\Memory\Available Bytes`<br>`\\127.0.0.1\Memory\Available Bytes`<br>`\\::1\Memory\Available Bytes`<br>`\\MY-SERVER\Memory\Available Bytes` | Local machine prefixes (`.`, `localhost`, `127.0.0.1`, `::1`, or `[System.Environment]::MachineName`, case-insensitive) are automatically accepted and normalized internally so they share the same underlying counter handle as machine-less paths. |

> [!NOTE]
> Remote machine paths (such as `\\other-server\Memory\Available Bytes`) are intentionally rejected (`Valid = $false`) and return `'Counter not initialized'` in the counter result's `error` field.

---

## 3. Understanding Result Shapes

### 3.1 The Uniform Leaf Value Hashtable
Every individual counter read—whether concrete or expanded from a wildcard, and regardless of whether `-StructureByInstance` is used—produces a uniform **5-key leaf hashtable**:

| Key | Type | Description |
| :--- | :--- | :--- |
| `value` | `System.Decimal` | The calculated counter value rounded to at most 6 decimal places (`0` if an error occurred). |
| `sample` | `System.Diagnostics.CounterSample` | The raw `.NET` `CounterSample` struct (`RawValue`, `BaseValue`, `TimeStamp`, `CounterType`, etc.), or `$null` on error. |
| `help` | `System.String` | Localized description text (`CounterHelp`) for this counter from the Windows counter library, or `$null` on error. |
| `type` | `System.String` | String name of the `System.Diagnostics.PerformanceCounterType` (for example `'Timer100Ns'`, `'NumberOfItems64'`, `'RateOfCountsPerSecond64'`), or `$null` on error. |
| `error` | `System.String` | `$null` when the read succeeded, or a descriptive error message when the counter/category/instance could not be read. |

---

### 3.2 Default Output Shape (Keyed by Requested Path)
Without `-StructureByInstance`, `Get-IcingaPerformanceCounter` returns a hashtable keyed by the exact path string you requested:

- **Concrete path** -> maps directly to the 5-key leaf hashtable.
- **Wildcard path (`*`)** -> maps to a nested hashtable keyed by each expanded concrete instance path (`\Category(Instance)\Counter`), where each value is the 5-key leaf hashtable.

```powershell
$Result = Get-IcingaPerformanceCounter -Counter @(
    '\Memory\Available Bytes',
    '\Processor(*)\% Processor Time'
);

# 1. Concrete counter access:
$Result['\Memory\Available Bytes'].value
$Result['\Memory\Available Bytes'].error

# 2. Wildcard counter access (nested under the wildcard path):
$Result['\Processor(*)\% Processor Time']['\Processor(_Total)\% Processor Time'].value
$Result['\Processor(*)\% Processor Time']['\Processor(0)\% Processor Time'].value
```

---

### 3.3 Instance-Structured Output (`-StructureByInstance`)
When writing providers or plugins that combine multiple counters (for example reading both `% Processor Time` and `% Idle Time` across all CPU cores, or reading multiple `Memory` counters), `-StructureByInstance` reshapes the output into a clean hierarchy:

- **Counters WITH an instance** (concrete or wildcard) are grouped **Instance -> Category -> Counter**:
  ```powershell
  $Result[Instance][Category][Counter]
  ```
- **Counters WITHOUT an instance** (single-instance categories) are grouped **Category -> Counter**:
  ```powershell
  $Result[Category][Counter]
  ```

#### Example: Single-Instance Category (`Memory`) with `-StructureByInstance`
```powershell
$Mem = Get-IcingaPerformanceCounter -Counter @(
    '\Memory\Available Bytes',
    '\Memory\Pages/sec'
) -StructureByInstance;

# Keyed by: $Mem[Category][Counter]
$AvailableBytes = $Mem['Memory']['Available Bytes'].value;
$PagesPerSec    = $Mem['Memory']['Pages/sec'].value;
```

#### Example: Multi-Instance Category (`Processor(*)`) with `-StructureByInstance`
```powershell
$Cpu = Get-IcingaPerformanceCounter -Counter @(
    '\Processor(*)\% Processor Time',
    '\Processor(*)\% User Time'
) -StructureByInstance;

# Keyed by: $Cpu[Instance][Category][Counter]
$TotalLoad = $Cpu['_Total']['Processor']['% Processor Time'].value;
$Core0Load = $Cpu['0']['Processor']['% Processor Time'].value;
$Core0User = $Cpu['0']['Processor']['% User Time'].value;

# Iterate over all discovered CPU instances:
foreach ($InstanceName in $Cpu.Keys) {
    $Load = $Cpu[$InstanceName]['Processor']['% Processor Time'].value;
    Write-Host "Instance ${InstanceName}: ${Load}%";
}
```

> [!IMPORTANT]
> **Avoid chaining `.Values` on multi-counter hashtables!**
> In interactive one-liners you might see `(Get-IcingaPerformanceCounter -Counter '\Memory\Available Bytes' -StructureByInstance).Values.'Available Bytes'.value`. While `.Values` works when only a single category is in the hashtable, `$Mem['Memory']['Available Bytes'].value` is strongly recommended in scripts and providers because it explicitly addresses the category key and never breaks when additional categories or instances are present.

---

## 4. Pre-Declaring Counters for Zero-Latency Reads

### Why Pre-Declare Counters?
Windows rate counters (such as `\Processor(_Total)\% Processor Time` or `\PhysicalDisk(*)\Disk Reads/sec`) compute rates between two consecutive samples separated by `WarmupMilliseconds` (`250 ms`).

If a counter is requested for the very first time during a check execution, the first call has to prime the counter and sleep `250 ms`. By declaring your component's counters via `New-IcingaPerformanceCounter`, Icinga for Windows automatically discovers them at startup by parsing the AST of `lib\IcingaForWindows.Kernel.ps1` and warms all of them in a single shared batch when the daemon starts.

### How to Declare Counters (`New-IcingaPerformanceCounter`)
Create a registration function in your provider or component (or call `New-IcingaPerformanceCounter` inside your provider initialization) passing a **literal array of strings** to `-Counter`:

```powershell
function Register-IcingaProviderCpuPerformanceCounter()
{
    New-IcingaPerformanceCounter -Counter @(
        '\Processor(*)\% Processor Time',
        '\Processor(*)\% Interrupt Time',
        '\Processor(*)\% Privileged Time',
        '\Processor(*)\% User Time'
    );
}
```

### Static AST Discovery Rules (Dos and Don'ts)
During `New-IcingaPerformanceCounterEnvironment`, `Register-IcingaPerformanceCounterFromComponents` parses `lib\IcingaForWindows.Kernel.ps1` using the PowerShell language parser **without executing any functions**. It looks for `New-IcingaPerformanceCounter` command ASTs and extracts every `StringConstantExpressionAst` inside the `-Counter` argument.

```powershell
# GOOD: Literal string array attached to -Counter (discovered statically at startup)
New-IcingaPerformanceCounter -Counter @(
    '\Memory\Available Bytes',
    '\Memory\Committed Bytes'
);

# GOOD: Single literal string (discovered statically at startup)
New-IcingaPerformanceCounter -Counter '\System\Processor Queue Length';

# NOT DISCOVERED AT STARTUP: Variables or dynamic expressions
# (Will still register at runtime when the function executes, but cannot be extracted statically by the AST scanner)
$MyCounters = @('\Memory\Available Bytes');
New-IcingaPerformanceCounter -Counter $MyCounters;
```

> [!TIP]
> After adding or modifying `New-IcingaPerformanceCounter` calls in `src\`, run `Build-ModuleProject` (or `build\Build-ModuleProject.ps1`) to regenerate `lib\IcingaForWindows.Kernel.ps1` so the static AST scanner sees your changes.

---

## 5. Safe Value Extraction and Error Handling

### 5.1 Checking Category Existence (`Test-IcingaPerformanceCounterCategory`)
Before querying counters that belong to optional Windows Server roles, features, or third-party applications (such as Hyper-V, IIS, Exchange, or SQL Server), use `Test-IcingaPerformanceCounterCategory` to verify that the category is installed on the host:

```powershell
# Pass a plain category name:
if (-not (Test-IcingaPerformanceCounterCategory -Category 'Hyper-V Virtual Machine Health Summary')) {
    # Role is not installed or category is unavailable
    return;
}

# Or pass a full counter path directly (local host prefixes and wildcards are supported):
if (Test-IcingaPerformanceCounterCategory -Category '\Processor(*)\% Processor Time') {
    # Category 'Processor' exists
}
```

### 5.2 Extracting Values vs. Errors (`Get-IcingaPerformanceCounterValue`)
When a counter read fails (for example because a counter name is misspelled or an instance disappeared), the leaf hashtable always has `value = 0` and a non-empty `error` string.

If you only read `.value` without checking `.error`, a broken or missing counter can silently look like a `0` measurement!

Use the private helper `Get-IcingaPerformanceCounterValue` (or check `.error` explicitly) to ensure errors are never masked by a default `0`:

- If `error` is non-empty, `Get-IcingaPerformanceCounterValue` returns the **error message (`[string]`)**.
- If `error` is `$null` or empty, `Get-IcingaPerformanceCounterValue` returns the **numeric value (`[decimal]`)**.
- If `$InputObject` is `$null` or not a `[hashtable]`, it returns `$null`.

```powershell
$Counters = Get-IcingaPerformanceCounter -Counter '\Memory\Available Bytes' -StructureByInstance;
$Leaf     = $Counters['Memory']['Available Bytes'];

$ValueOrError = Get-IcingaPerformanceCounterValue -InputObject $Leaf;

if ($null -eq $ValueOrError) {
    Write-Warning 'Counter request timed out or returned no data.';
} elseif ($ValueOrError -is [string]) {
    Write-Warning "Failed to read counter: $ValueOrError";
} else {
    # $ValueOrError is a [decimal] ready for threshold comparison
    Write-Host "Available Memory: $ValueOrError bytes";
}
```

---

## 6. Practical Provider and Plugin Recipes

### Recipe 1: Reading Single-Instance Counters (Memory Provider Pattern)
```powershell
function Get-MyMemoryMetrics()
{
    [array]$CounterPaths = @(
        '\Memory\Available Bytes',
        '\Memory\Committed Bytes',
        '\Memory\Pages/sec'
    );

    $Data = Get-IcingaPerformanceCounter -Counter $CounterPaths -StructureByInstance;

    if ($null -eq $Data -or -not $Data.ContainsKey('Memory')) {
        return @{
            'Error' = 'Failed to query Memory performance counters.';
        };
    }

    $Memory = $Data['Memory'];
    $Result = @{ };

    foreach ($CounterName in $Memory.Keys) {
        $Extracted = Get-IcingaPerformanceCounterValue -InputObject $Memory[$CounterName];

        if ($Extracted -is [string]) {
            Write-LoggingEntry -Message 'Memory counter read error' -Level 'Warning' -Data @{
                'Counter' = $CounterName;
                'Error'   = $Extracted;
            };
            $Result[$CounterName] = $null;
        } else {
            $Result[$CounterName] = $Extracted;
        }
    }

    return $Result;
}
```

### Recipe 2: Reading Multi-Instance Wildcard Counters (Per-Core CPU or Disk Metrics)
```powershell
function Get-MyDiskThroughput()
{
    [array]$CounterPaths = @(
        '\PhysicalDisk(*)\Disk Reads/sec',
        '\PhysicalDisk(*)\Disk Writes/sec'
    );

    $Data = Get-IcingaPerformanceCounter -Counter $CounterPaths -StructureByInstance;
    [hashtable]$Disks = @{ };

    if ($null -eq $Data) {
        return $Disks;
    }

    foreach ($Instance in $Data.Keys) {
        if (-not $Data[$Instance].ContainsKey('PhysicalDisk')) {
            continue;
        }

        $DiskCategory = $Data[$Instance]['PhysicalDisk'];
        $ReadsPerSec  = Get-IcingaPerformanceCounterValue -InputObject $DiskCategory['Disk Reads/sec'];
        $WritesPerSec = Get-IcingaPerformanceCounterValue -InputObject $DiskCategory['Disk Writes/sec'];

        $Disks[$Instance] = @{
            'ReadsPerSec'  = $ReadsPerSec;
            'WritesPerSec' = $WritesPerSec;
        };
    }

    return $Disks;
}
```

### Recipe 3: Guarding Optional Role Counters (`Test-IcingaPerformanceCounterCategory`)
```powershell
function Get-MyHyperVHealth()
{
    [string]$CategoryName = 'Hyper-V Virtual Machine Health Summary';

    if (-not (Test-IcingaPerformanceCounterCategory -Category $CategoryName)) {
        return @{
            'Supported' = $false;
            'Reason'    = ('Performance counter category "{0}" is not installed on this system.' -f $CategoryName);
        };
    }

    $Data = Get-IcingaPerformanceCounter -Counter @(
        '\Hyper-V Virtual Machine Health Summary\Health Ok',
        '\Hyper-V Virtual Machine Health Summary\Health Critical'
    ) -StructureByInstance;

    return @{
        'Supported'      = $true;
        'HealthOk'       = Get-IcingaPerformanceCounterValue -InputObject $Data[$CategoryName]['Health Ok'];
        'HealthCritical' = Get-IcingaPerformanceCounterValue -InputObject $Data[$CategoryName]['Health Critical'];
    };
}
```

---

## 7. Troubleshooting and FAQ

### Q1: Why does `Get-IcingaPerformanceCounter` return `value = 0` when I type an invalid counter name?
To guarantee a predictable schema for plugins, every counter leaf always contains the five keys `value`, `sample`, `help`, `type`, and `error`, with `value` initialized to `[decimal]0`. When a category, counter, or instance does not exist, the OS exception is captured into the `error` key rather than throwing a terminating exception that would abort an entire batch of counters. Always inspect `.error` or use `Get-IcingaPerformanceCounterValue`.

### Q2: Do I need the background daemon running to use `Get-IcingaPerformanceCounter`?
No.
- When the daemon is running (`Use-IcingaForWindows -RunBackgroundDaemons`), requests are served with zero warm-up sleep by the background daemon thread.
- When the daemon is **not** running (`Use-IcingaForWindows -NoNewShell` without `-RunBackgroundDaemons`), `Get-IcingaPerformanceCounter` automatically falls back to a persistent per-runspace manager (`$script:IcingaPerformanceCounterInlineManager`). The first call for a new counter sleeps `250 ms` (`WarmupMilliseconds`), and all subsequent calls in that shell session reuse the warm handles immediately.

### Q3: How long are unused counters kept in memory and in `PerformanceCounter.json`?
By default, any counter path that has not been requested via `Get-IcingaPerformanceCounter` or refreshed via `New-IcingaPerformanceCounter` for **60 minutes** (`$Store.Config.EvictionMinutes = 60`) is automatically evicted during the daemon's periodic maintenance pass (`Update-IcingaPerformanceCounterState`), its `.NET` handle is disposed, and `PerformanceCounter.json` is atomically rewritten without the stale entry.

### Q4: How are short-lived or renumbered process instances (`svchost#1`, `svchost#2`) handled in wildcard queries?
When querying `\Process(*)\% Processor Time`, Windows names duplicate process instances `name#1`, `name#2`, etc. If `svchost#1` exits, Windows shifts `svchost#2` into `svchost#1`. `IcingaPerformanceCounterCategory.FindPrevious` automatically compares the `'ID Process'` raw value between the `Previous` and `Current` category snapshots whenever `'ID Process'` is present in the category. If the process ID changed between snapshots, the previous sample is discarded for that instance so a rate is never calculated across two unrelated processes.

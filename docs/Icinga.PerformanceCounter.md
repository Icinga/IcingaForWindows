# Icinga.PerformanceCounter

*Auto-generated from `src/PerformanceCounter/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Get-IcingaPerformanceCounter](#get-icingaperformancecounter)
- [Show-IcingaPerformanceCounter](#show-icingaperformancecounter)
- [Show-IcingaPerformanceCounterDetails](#show-icingaperformancecounterdetails)
- [Test-IcingaPerformanceCounterCategory](#test-icingaperformancecountercategory)

## Private helpers

- [ConvertTo-IcingaPerformanceCounterInstanceStructure](#convertto-icingaperformancecounterinstancestructure)
- [Get-IcingaPerformanceCounterLiteral](#get-icingaperformancecounterliteral)
- [Get-IcingaPerformanceCounterValue](#get-icingaperformancecountervalue)
- [New-IcingaPerformanceCounter](#new-icingaperformancecounter)
- [New-IcingaPerformanceCounterEnvironment](#new-icingaperformancecounterenvironment)
- [Read-IcingaPerformanceCounterCache](#read-icingaperformancecountercache)
- [Register-IcingaDefaultPerformanceCounter](#register-icingadefaultperformancecounter)
- [Register-IcingaPerformanceCounterFromComponents](#register-icingaperformancecounterfromcomponents)
- [Start-IcingaPerformanceCounterDaemon](#start-icingaperformancecounterdaemon)
- [Test-IcingaPerformanceCounterDaemon](#test-icingaperformancecounterdaemon)
- [Update-IcingaPerformanceCounterState](#update-icingaperformancecounterstate)
- [Write-IcingaPerformanceCounterCache](#write-icingaperformancecountercache)

---

### Get-IcingaPerformanceCounter

*Public function*

**Synopsis:** Read one or more Windows performance counters and return their current values

#### Description

`Get-IcingaPerformanceCounter` returns the current values of the requested counter paths. By default
the result is a hashtable keyed by the requested path: a concrete path maps to a flat result
hashtable with the keys value, sample, help, type and error; a wildcard path (instance '*') maps to a
nested hashtable keyed by each live instance path.

With `-StructureByInstance` the result is reshaped for easier plugin consumption: counters with an
instance are keyed instance-first (`$out[Instance][Category][Counter]`), counters without an instance
are keyed category-first (`$out[Category][Counter]`), and the leaf is always the uniform value
hashtable.

When the performance-counter daemon is running the read is dispatched through a request/pull queue:
the function generates a request id, registers a single-slot response queue, enqueues the request and
blocks on the response for up to the given timeout. All counter access happens on the daemon thread,
so there are no races on the underlying counter handles. When no daemon is running the function uses a
persistent per-runspace manager kept in module scope, so repeated reads stay warm and only the first
read of a new counter pays the warm-up sleep.

Requesting a valid counter path also refreshes its last-seen timestamp in the registry, keeping
actively used counters warm and out of the eviction path.

#### Parameters

**`$Counter`**

| Name    | Type         | Description                                                  | Default |
|---------|--------------|--------------------------------------------------------------|---------|
| Counter | System.Array | One or more counter paths to read, e.g. '\Processor(*)\...'. | @()     |

**`$TimeoutMs`**

| Name      | Type         | Description                                                    | Default |
|-----------|--------------|----------------------------------------------------------------|---------|
| TimeoutMs | System.Int32 | Milliseconds to wait for the daemon response before giving up. | 5000    |

**`$StructureByInstance`**

| Name                | Type                                         | Description                                                                          | Default |
|---------------------|----------------------------------------------|--------------------------------------------------------------------------------------|---------|
| StructureByInstance | System.Management.Automation.SwitchParameter | Reshape the result to instance/category/counter (category/counter when no instance). | $false  |

#### Outputs

System.Collections.Hashtable -- By default keyed by requested path (flat for concrete paths, nested for
wildcard paths). With `-StructureByInstance`, keyed by instance then category then counter, or by
category then counter for counters without an instance. Returns an empty hashtable when no counter is
requested, or $null when the daemon request times out.

#### Examples

```powershell
PS> Get-IcingaPerformanceCounter -Counter '\Processor(_Total)\% Processor Time'

Reads a single counter and returns its value hashtable.
```

```powershell
PS> $cpu = Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time' -StructureByInstance
PS> $cpu.'0'.'Processor'.'% Processor Time'.value

Reads every processor instance and addresses one core by instance, category and counter name.
```

```powershell
PS> $mem = Get-IcingaPerformanceCounter -Counter '\Memory\Pages/sec' -StructureByInstance
PS> $mem.'Memory'.'Pages/sec'.value

A counter without an instance is keyed category-first.
```

#### Notes

The request/response transport lives under `(Get-GlobalRuntimeVariable).Public.PerformanceCounter`.
Timeouts are logged through `Write-LoggingEntry` at Warning level. No external services are used.

*Source: [src/PerformanceCounter/Public/Get-IcingaPerformanceCounter.ps1](../src/PerformanceCounter/Public/Get-IcingaPerformanceCounter.ps1)*

---

### Show-IcingaPerformanceCounter

*Public function*

**Synopsis:** Browse performance counter categories, counters and live instances

#### Description

`Show-IcingaPerformanceCounter` is a stateless introspection helper that queries Windows
performance counter metadata directly. It has three modes selected by the parameters passed:

- With no arguments it lists all counter categories, optionally filtered by `-Filter` using
  wildcard matching.
- With `-Category` it lists the counter paths inside that category, emitting '\Category(*)\Counter'
  for multi-instance categories and '\Category\Counter' for single-instance categories.
- With `-Counter` (a wildcard path) it lists the concrete counter paths for every live instance.

Because it only reads metadata it is safe to call from any thread and does not require the
daemon. Errors are logged and yield an empty result rather than throwing.

#### Parameters

**`$Category`**

| Name     | Type          | Description                             | Default |
|----------|---------------|-----------------------------------------|---------|
| Category | System.String | List the counters within this category. | $null   |

**`$Counter`**

| Name    | Type          | Description                                                  | Default |
|---------|---------------|--------------------------------------------------------------|---------|
| Counter | System.String | Wildcard counter path whose live instances should be listed. | $null   |

**`$Filter`**

| Name   | Type          | Description                                      | Default |
|--------|---------------|--------------------------------------------------|---------|
| Filter | System.String | Wildcard filter applied when listing categories. | $null   |

#### Outputs

System.Array -- Category names, counter paths, or instance paths depending on the mode.

#### Examples

```powershell
PS> Show-IcingaPerformanceCounter

Lists all performance counter categories.
```

```powershell
PS> Show-IcingaPerformanceCounter -Category 'Processor'

Lists the counter paths available in the Processor category.
```

```powershell
PS> Show-IcingaPerformanceCounter -Counter '\PhysicalDisk(*)\Disk Reads/sec'

Lists the concrete per-instance paths that currently exist for the wildcard counter.
```

#### Notes

Uses `System.Diagnostics.PerformanceCounterCategory` directly. No global state is read or
written, and no external services are used.

*Source: [src/PerformanceCounter/Public/Show-IcingaPerformanceCounter.ps1](../src/PerformanceCounter/Public/Show-IcingaPerformanceCounter.ps1)*

---

### Show-IcingaPerformanceCounterDetails

*Public function*

**Synopsis:** Show live values for the registered performance counters, or a filtered subset

#### Description

`Show-IcingaPerformanceCounterDetails` returns the current values of performance counters
through `Get-IcingaPerformanceCounter`. Called without arguments it dumps every counter
currently registered in the global store. Passing `-Counter` narrows the output to the given
paths. The result keeps the uniform shape: a hashtable keyed by counter path with flat value
hashtables for concrete paths and nested hashtables for wildcard paths.

#### Parameters

**`$Counter`**

| Name    | Type         | Description                                                 | Default |
|---------|--------------|-------------------------------------------------------------|---------|
| Counter | System.Array | Counter paths to show. Empty shows all registered counters. | @()     |

**`$StructureByInstance`**

| Name                | Type                                         | Description                                                                                 | Default |
|---------------------|----------------------------------------------|---------------------------------------------------------------------------------------------|---------|
| StructureByInstance | System.Management.Automation.SwitchParameter | Reshape the result to instance/category/counter, forwarded to Get-IcingaPerformanceCounter. | $false  |

#### Outputs

System.Collections.Hashtable -- Keyed by counter path; values as returned by
`Get-IcingaPerformanceCounter`. With `-StructureByInstance`, keyed by instance/category/counter.
Empty when nothing is registered and nothing is requested.

#### Examples

```powershell
PS> Show-IcingaPerformanceCounterDetails

Shows live values for every registered counter.
```

```powershell
PS> Show-IcingaPerformanceCounterDetails -Counter '\Processor(_Total)\% Processor Time'

Shows the live value for a single specified counter.
```

#### Notes

This is a thin convenience layer over `Get-IcingaPerformanceCounter`; the same daemon/inline
behavior and return shape apply. No external services are used.

*Source: [src/PerformanceCounter/Public/Show-IcingaPerformanceCounterDetails.ps1](../src/PerformanceCounter/Public/Show-IcingaPerformanceCounterDetails.ps1)*

---

### Test-IcingaPerformanceCounterCategory

*Public function*

**Synopsis:** Check whether a Windows performance counter category exists on the local system

#### Description

`Test-IcingaPerformanceCounterCategory` checks whether the given performance counter category
is present and accessible on the local system. It accepts either a plain category name
(such as 'Processor' or 'Memory') or a full counter path (such as
'\Processor(*)\% Processor Time' or '\\.\Processor(_Total)\% Processor Time').

Because it only queries category metadata and never throws, it is safe to call from any
thread or provider before reading optional role counters (such as Hyper-V, IIS or MSSQL).

#### Parameters

**`$Category`**

| Name     | Type          | Description                                               | Default |
|----------|---------------|-----------------------------------------------------------|---------|
| Category | System.String | The category name or counter path to check for existence. |         |

#### Outputs

System.Boolean -- $true when the category exists and is accessible on this system; $false otherwise.

#### Examples

```powershell
PS> Test-IcingaPerformanceCounterCategory -Category 'Processor'

Returns $true when the 'Processor' performance counter category exists on the system.
```

```powershell
PS> Test-IcingaPerformanceCounterCategory -Category '\Hyper-V Virtual Machine Health Summary(*)\Health Critical'

Extracts the category name from the counter path and returns $true when the category exists.
```

#### Notes

Delegates to `IcingaPerformanceCounter::CategoryExists`. Never throws and reads no global state.

*Source: [src/PerformanceCounter/Public/Test-IcingaPerformanceCounterCategory.ps1](../src/PerformanceCounter/Public/Test-IcingaPerformanceCounterCategory.ps1)*

---

### ConvertTo-IcingaPerformanceCounterInstanceStructure

*Private function*

**Synopsis:** Reshape a flat performance counter result into an instance/category/counter structure

#### Description

`ConvertTo-IcingaPerformanceCounterInstanceStructure` transforms the default result of
`Get-IcingaPerformanceCounter` (a hashtable keyed by the requested counter path) into a nested
structure that is easier to consume when writing plugins.

Counters that carry an instance are keyed instance-first, then category, then counter name:
`$out[Instance][Category][Counter]`. Counters without an instance are keyed category-first, then
counter name: `$out[Category][Counter]`. In both cases the leaf is the uniform value hashtable
(`value`, `sample`, `help`, `type`, `error`), so `$out['0']['Processor']['% Processor Time'].value`
and `$out['Memory']['Pages/sec'].value` both work. Wildcard requests are expanded so each live
instance becomes its own top-level key (for example CPU cores `0`, `1`, `_Total`).

The requested paths are re-parsed to decide the shape, so the transform never has to guess whether a
nested value is a value hashtable or an instance group.

#### Parameters

**`$Result`**

| Name   | Type                         | Description                                                  | Default |
|--------|------------------------------|--------------------------------------------------------------|---------|
| Result | System.Collections.Hashtable | The result returned by the manager, keyed by requested path. | @{ }    |

**`$Counter`**

| Name    | Type         | Description                                                        | Default |
|---------|--------------|--------------------------------------------------------------------|---------|
| Counter | System.Array | The originally requested counter paths, used to drive the reshape. | @()     |

#### Outputs

System.Collections.Hashtable -- Nested structure keyed by instance/category or category, with the
uniform value hashtable at the leaf.

#### Examples

```powershell
PS> ConvertTo-IcingaPerformanceCounterInstanceStructure -Result $raw -Counter '\Processor(*)\% Processor Time'
```

#### Notes

Called by `Get-IcingaPerformanceCounter` when `-StructureByInstance` is set. Pure transform; touches
no global state and reads no counters.

*Source: [src/PerformanceCounter/Private/ConvertTo-IcingaPerformanceCounterInstanceStructure.ps1](../src/PerformanceCounter/Private/ConvertTo-IcingaPerformanceCounterInstanceStructure.ps1)*

---

### Get-IcingaPerformanceCounterLiteral

*Private function*

**Synopsis:** Extract literal counter path strings from an AST argument node

#### Description

`Get-IcingaPerformanceCounterLiteral` walks an argument's abstract syntax tree and
collects the value of every string constant it contains. It is used by the startup
discovery step to read the literal counter list passed to a `New-IcingaPerformanceCounter`
call without executing any component code. Non-literal arguments (variables, expressions)
contribute no values, which is intentional -- only statically declarable counters are
discovered.

#### Parameters

**`$Argument`**

| Name     | Type                                      | Description                              | Default |
|----------|-------------------------------------------|------------------------------------------|---------|
| Argument | System.Management.Automation.Language.Ast | The AST node of the `-Counter` argument. | $null   |

#### Outputs

System.Array -- The literal string values found in the argument, or an empty array.

#### Examples

```powershell
PS> Get-IcingaPerformanceCounterLiteral -Argument $argumentAst
```

#### Notes

Called by `Register-IcingaPerformanceCounterFromComponents`. Returns an empty array when
the argument is null or contains no string literals.

*Source: [src/PerformanceCounter/Private/Get-IcingaPerformanceCounterLiteral.ps1](../src/PerformanceCounter/Private/Get-IcingaPerformanceCounterLiteral.ps1)*

---

### Get-IcingaPerformanceCounterValue

*Private function*

**Synopsis:** Return the value of a performance counter result, or its error when one is present

#### Description

`Get-IcingaPerformanceCounterValue` extracts the usable result from a single performance counter value
object (the leaf hashtable produced by `Get-IcingaPerformanceCounter`, containing the keys value,
sample, help, type and error). If the counter reported an error the error message is returned;
otherwise the numeric value is returned. This lets a plugin drill down to a single counter and get
back either a number to threshold against or the error text to surface, in one call.

Because the value is always numeric and the error is always a string, callers can tell the two apart
with a simple type check (`$result -is [string]` means an error was returned).

#### Parameters

**`$InputObject`**

| Name        | Type          | Description                                                           | Default |
|-------------|---------------|-----------------------------------------------------------------------|---------|
| InputObject | System.Object | A single counter value object (the leaf hashtable of a counter read). | $null   |

#### Outputs

System.Object -- The counter value (typically System.Decimal), or the error message (System.String)
when the counter reported one. Returns $null when the input is not a counter value object.

#### Examples

```powershell
PS> $data = Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time' -StructureByInstance
PS> Get-IcingaPerformanceCounterValue -InputObject $data.'0'.'Processor'.'% Processor Time'

Returns the processor load of core 0, or the error text if that counter could not be read.
```

#### Notes

Pure helper; reads no global state and touches no counters. Intended for use by plugins after they
have selected a single counter from a `Get-IcingaPerformanceCounter` result.

*Source: [src/PerformanceCounter/Private/Get-IcingaPerformanceCounterValue.ps1](../src/PerformanceCounter/Private/Get-IcingaPerformanceCounterValue.ps1)*

---

### New-IcingaPerformanceCounter

*Private function*

**Synopsis:** Declare and keep-alive a set of performance counters for a component

#### Description

`New-IcingaPerformanceCounter` registers the given counter paths in the global
performance-counter store so the background daemon initializes, warms and keeps them
available. Calling it refreshes each counter's last-seen timestamp, which both prevents
eviction of actively-used counters and drives the self-maintaining cache file.

Components declare the counters they need by calling this function with a literal list.
At module start the discovery step statically scans the compiled kernel for these calls
and seeds the registry from the extracted counter paths, so a declared counter is warm
before it is ever requested. The function only writes to the thread-safe registry
dictionary, so it is safe to call from any thread.

#### Parameters

**`$Counter`**

| Name    | Type         | Description                                             | Default |
|---------|--------------|---------------------------------------------------------|---------|
| Counter | System.Array | One or more counter paths to register, e.g. '\Cat\Ctr'. | @()     |

#### Outputs

None -- Registers the counter paths in the global store.

#### Examples

```powershell
PS> New-IcingaPerformanceCounter -Counter @('\Processor(*)\% Processor Time', '\Memory\Available Bytes')

Declares two counters so the daemon keeps them warm and the discovery step can find them.
```

#### Notes

The counters are stored under `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered`.
This function does not return counter values -- use `Get-IcingaPerformanceCounter` to read them.

*Source: [src/PerformanceCounter/Private/New-IcingaPerformanceCounter.ps1](../src/PerformanceCounter/Private/New-IcingaPerformanceCounter.ps1)*

---

### New-IcingaPerformanceCounterEnvironment

*Private function*

**Synopsis:** Initialize the performance counter manager, cache and warm counter set

#### Description

`New-IcingaPerformanceCounterEnvironment` prepares the performance-counter subsystem for
the daemon. It creates the central manager instance the first time it runs (the class type
is available because the kernel has been dot-sourced by then), loads the persisted cache,
runs component discovery to register statically declared counters, and reconciles the
manager so every registered counter is warmed in a single batch. It also stamps the initial
heartbeat and refresh timestamps.

This function is expected to run inside the performance-counter daemon runspace, before the
daemon enters its processing loop, so the manager is created and used on a single thread.

#### Outputs

None -- Populates `(Get-GlobalRuntimeVariable).Public.PerformanceCounter`.

#### Examples

```powershell
PS> New-IcingaPerformanceCounterEnvironment
```

#### Notes

All shared state is read through `Get-GlobalRuntimeVariable`. The manager is stored on the
`Manager` slot of the global store and is only ever touched by the daemon thread.

*Source: [src/PerformanceCounter/Private/New-IcingaPerformanceCounterEnvironment.ps1](../src/PerformanceCounter/Private/New-IcingaPerformanceCounterEnvironment.ps1)*

---

### Read-IcingaPerformanceCounterCache

*Private function*

**Synopsis:** Load the registered performance counters from the cache file

#### Description

`Read-IcingaPerformanceCounterCache` reads the persisted counter cache written by
`Write-IcingaPerformanceCounterCache` and merges its entries into the global registry.
It runs during performance-counter environment initialization so counters learned in
previous runs are warmed immediately at startup. A missing, empty or corrupt cache file
is ignored silently so a bad cache never blocks the daemon.

#### Outputs

None -- Populates `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered`.

#### Examples

```powershell
PS> Read-IcingaPerformanceCounterCache
```

#### Notes

`ConvertFrom-Json` returns a PSCustomObject on both Windows PowerShell 5.1 and
PowerShell 7 (the `-AsHashtable` switch is deliberately not used because it is PowerShell
6+ only). Entries are read through the object's properties for cross-version compatibility.

*Source: [src/PerformanceCounter/Private/Read-IcingaPerformanceCounterCache.ps1](../src/PerformanceCounter/Private/Read-IcingaPerformanceCounterCache.ps1)*

---

### Register-IcingaDefaultPerformanceCounter

*Private function*

**Synopsis:** Declare the default set of performance counters shipped with the module

#### Description

`Register-IcingaDefaultPerformanceCounter` declares a small, broadly-available set of
performance counters (processor, memory and physical disk) by calling
`New-IcingaPerformanceCounter`. It serves as the reference example of how a component
declares the counters it needs and gives the startup discovery step and the warm-up path a
concrete set to work with. Additional components declare their own counters the same way.

#### Outputs

None -- Registers the default counter paths in the global store.

#### Examples

```powershell
PS> Register-IcingaDefaultPerformanceCounter
```

#### Notes

The literal counter list here is what the discovery step reads from the compiled kernel. The
set is intentionally minimal and generic; it is an example, not a fixed contract.

*Source: [src/PerformanceCounter/Private/Register-IcingaDefaultPerformanceCounter.ps1](../src/PerformanceCounter/Private/Register-IcingaDefaultPerformanceCounter.ps1)*

---

### Register-IcingaPerformanceCounterFromComponents

*Private function*

**Synopsis:** Discover component-declared performance counters by scanning the compiled kernel

#### Description

`Register-IcingaPerformanceCounterFromComponents` parses the compiled module kernel
(`lib\IcingaForWindows.Kernel.ps1`, which contains every source file concatenated) and
finds all calls to `New-IcingaPerformanceCounter`. For each call it extracts the literal
counter paths passed to the `-Counter` parameter and registers them in the global store.
No component code is executed -- the declaration is read statically from the syntax tree.

This runs once during performance-counter environment initialization so that every
counter any component declares is warmed as soon as the daemon starts.

#### Outputs

None -- Populates `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered`.

#### Examples

```powershell
PS> Register-IcingaPerformanceCounterFromComponents
```

#### Notes

Only literal array/string arguments are discoverable. The kernel file is produced by
`Build-ModuleProject`; if it is missing the discovery step is skipped.

*Source: [src/PerformanceCounter/Private/Register-IcingaPerformanceCounterFromComponents.ps1](../src/PerformanceCounter/Private/Register-IcingaPerformanceCounterFromComponents.ps1)*

---

### Start-IcingaPerformanceCounterDaemon

*Private function*

**Synopsis:** Background daemon that serves performance counter requests and maintains the registry

#### Description

`Start-IcingaPerformanceCounterDaemon` initializes the performance-counter environment and
then runs the request/refresh loop while `Test-ThreadRunning` is true. Each cycle it blocks
briefly on the request queue; when a request arrives it resolves the requested counters
through the central manager and atomically claims the caller's pending response queue via
`TryRemove` before pushing the result, preventing disposal races when a caller times out.
When idle (and on a throttled interval) it runs the maintenance step which refreshes the
heartbeat, reconciles transient instances, evicts unused counters and persists the cache.

Because every performance counter handle is created, sampled and disposed here on this one
thread, callers never touch the non-thread-safe counter objects directly -- they exchange
data through the thread-safe queues only.

#### Outputs

None -- Operates for side effects (serves requests and maintains counters).

#### Examples

```powershell
PS> Start-IcingaPerformanceCounterDaemon
```

#### Notes

Must run inside a dedicated background runspace created by `New-Thread`. All shared state is
accessed through `Get-GlobalRuntimeVariable` because the runspace receives only a snapshot of
the runtime at startup. The daemon exits cleanly when `Test-ThreadRunning` returns $false.

*Source: [src/PerformanceCounter/Private/Start-IcingaPerformanceCounterDaemon.ps1](../src/PerformanceCounter/Private/Start-IcingaPerformanceCounterDaemon.ps1)*

---

### Test-IcingaPerformanceCounterDaemon

*Private function*

**Synopsis:** Determine whether the performance counter daemon is currently alive

#### Description

`Test-IcingaPerformanceCounterDaemon` checks the heartbeat timestamp the daemon refreshes
on every loop cycle. If the heartbeat is recent the daemon is considered alive and callers
route their reads through the request/response queue; otherwise `Get-IcingaPerformanceCounter`
falls back to a synchronous inline read. Using the heartbeat keeps the check decoupled from
the thread registry.

#### Outputs

System.Boolean -- $true when the daemon heartbeat is recent, otherwise $false.

#### Examples

```powershell
PS> if (Test-IcingaPerformanceCounterDaemon) { 'daemon is serving requests' }
```

#### Notes

The heartbeat lives at `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Heartbeat`.
A heartbeat older than five seconds is treated as not alive.

*Source: [src/PerformanceCounter/Private/Test-IcingaPerformanceCounterDaemon.ps1](../src/PerformanceCounter/Private/Test-IcingaPerformanceCounterDaemon.ps1)*

---

### Update-IcingaPerformanceCounterState

*Private function*

**Synopsis:** Refresh, reconcile, evict and persist the performance counter state

#### Description

`Update-IcingaPerformanceCounterState` is the periodic maintenance step run by the
performance-counter daemon. On every call it refreshes the daemon heartbeat. When the
configured refresh interval has elapsed it additionally evicts counters that have not been
requested for longer than the eviction window, reconciles the manager against the current
registration set (adding new instances and disposing vanished ones such as a removed disk),
takes a fresh sample of every counter to keep rate values current, and persists the cache
file.

Extracting this maintenance out of the daemon loop keeps the loop body small and lets the
throttling logic live in one place.

#### Parameters

**`$Store`**

| Name  | Type          | Description                                                                          | Default |
|-------|---------------|--------------------------------------------------------------------------------------|---------|
| Store | System.Object | The performance-counter store to operate on. Resolved from the runtime when omitted. | $null   |

#### Outputs

None -- Mutates the global performance-counter store and writes the cache file.

#### Examples

```powershell
PS> Update-IcingaPerformanceCounterState
```

#### Notes

Reads configuration (`RefreshIntervalMs`, `EvictionMinutes`) from the store's Config object.
Heartbeat is always refreshed so liveness detection stays responsive even under load. The daemon
passes its cached store reference to avoid re-resolving it through Get-GlobalRuntimeVariable each cycle.

*Source: [src/PerformanceCounter/Private/Update-IcingaPerformanceCounterState.ps1](../src/PerformanceCounter/Private/Update-IcingaPerformanceCounterState.ps1)*

---

### Write-IcingaPerformanceCounterCache

*Private function*

**Synopsis:** Persist the registered performance counters to the cache file

#### Description

`Write-IcingaPerformanceCounterCache` serializes the registered counter paths and their
last-seen timestamps to a JSON file in the module cache directory using UTF-8 without BOM.
The daemon calls this each refresh cycle so the warm counter set survives restarts and
self-maintains -- new counters are added and stale ones drop out over time. The file is
written atomically via a temporary file and guarded with try/catch so transient file locks
or permission issues never interrupt the daemon.

#### Outputs

None -- Writes the cache file to disk.

#### Examples

```powershell
PS> Write-IcingaPerformanceCounterCache
```

#### Notes

The cache file is `PerformanceCounter.json` under `Get-ModuleCacheDirectory`. Timestamps
are stored in ISO 8601 round-trip format so they parse identically on Windows PowerShell
5.1 and PowerShell 7.

*Source: [src/PerformanceCounter/Private/Write-IcingaPerformanceCounterCache.ps1](../src/PerformanceCounter/Private/Write-IcingaPerformanceCounterCache.ps1)*


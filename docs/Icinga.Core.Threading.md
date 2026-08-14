# Icinga.Core.Threading

*Auto-generated from `src/Core/Threading/`. Do not edit by hand — run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Set-ThreadData](#set-threaddata)
- [Show-IcingaThreads](#show-icingathreads)

## Private helpers

- [Get-ThreadCallStack](#get-threadcallstack)
- [Get-ThreadId](#get-threadid)
- [Get-ThreadLastSeen](#get-threadlastseen)
- [Get-ThreadState](#get-threadstate)
- [Get-ThreadTree](#get-threadtree)
- [New-Thread](#new-thread)
- [New-ThreadPool](#new-threadpool)
- [Set-ThreadFrozen](#set-threadfrozen)
- [Set-ThreadProcessing](#set-threadprocessing)
- [Show-Threads](#show-threads)
- [Start-ThreadHouseKeeper](#start-threadhousekeeper)
- [Stop-Thread](#stop-thread)
- [Test-ThreadRunning](#test-threadrunning)
- [Write-ThreadTree](#write-threadtree)

---

### Set-ThreadData

*Public function*

**Synopsis:** Initialize thread-local runtime state inside a new runspace.

#### Description

`Set-ThreadData` is invoked inside threads created by `New-Thread`. It sets up
the base environment, configures the public and protected runtime containers,
registers the thread id, validates the requested command and finally invokes it
with the supplied parameters.

#### Parameters

**`$PublicSpace`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| PublicSpace | System.Object | Shared public runtime object to attach to the thread | $null |

**`$AccessControl`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AccessControl | System.Object | Access control descriptor to attach to protected runtime area | $null |

**`$ThreadId`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ThreadId | System.String | The thread id assigned by the creator | $null |

**`$Command`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Command | System.String | The command/function name to execute in the thread | $null |

**`$Parameters`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Parameters | System.Hashtable | Named parameters to pass to `Command` | @{} |

#### Outputs

Varies. The invoked `Command` determines output; error conditions return structured cmdlet returns.

#### Examples

```powershell
PS> Set-ThreadData -PublicSpace $GlobalPublic -AccessControl $ac -ThreadId $tid -Command 'RunWorker' -Parameters @{ 'Queue' = $q }
```

#### Notes

Called exclusively by New-Thread; do not invoke directly. Calls New-ModuleBaseEnvironment to set
up the runspace and sets (Get-GlobalRuntimeVariable).Protected.IsBackgroundDaemon to $true so
that downstream functions know they are executing in a background context. Thread identity is
tracked via Update-LoggingThreadLoggingId for log correlation.

*Source: [src/Core/Threading/Public/Set-ThreadData.ps1](../../src/Core/Threading/Public/Set-ThreadData.ps1)*

---

### Show-IcingaThreads

*Public function*

**Synopsis:** Display the Icinga thread hierarchy.

#### Description

`Show-IcingaThreads` is a small public wrapper that renders the current
thread hierarchy for the Icinga application by delegating to `Show-Threads`.

#### Parameters

**`$AsObject`**

| Name     | Type                    | Description                                        | Default |
|----------|-------------------------|----------------------------------------------------|---------|
| AsObject | System.SwitchParameter  | Return the tree as PSObjects instead of rendering  | $false  |

#### Outputs

System.Array when `-AsObject` is set. Returns the root-level thread nodes
with a nested `Children` array representing the full hierarchy.

None otherwise. Writes a formatted thread tree to the logging system.

#### Examples

```powershell
PS> Show-IcingaThreads
```

```powershell
PS> $tree = Show-IcingaThreads -AsObject
PS> $tree | Select-Object Name, State, LastSeen
```

#### Notes

This wrapper calls `Show-Threads` and exists to provide a user-facing
command name for convenience.

*Source: [src/Core/Threading/Public/Show-IcingaThreads.ps1](../../src/Core/Threading/Public/Show-IcingaThreads.ps1)*

---

### Get-ThreadCallStack

*Private function*

**Synopsis:** Get a readable breadcrumb-style name for the current thread call stack.

#### Description

`Get-ThreadCallStack` inspects the PowerShell call stack to construct a compact,
human-readable thread name by joining function names with '`::`'. It normalizes
scriptblock entries and removes internal `Set-ThreadData` frames.

#### Outputs

System.String — A single-line thread name derived from the call stack.

#### Examples

```powershell
PS> Get-ThreadCallStack
```

#### Notes

Used for naming threads created with `New-Thread` to aid diagnostics and tracing.

*Source: [src/Core/Threading/Private/Get-ThreadCallStack.ps1](../../src/Core/Threading/Private/Get-ThreadCallStack.ps1)*

---

### Get-ThreadId

*Private function*

**Synopsis:** Return the current thread identifier used by our runtime.

#### Description

`Get-ThreadId` returns the thread id stored in the runtime private threading
container. It is a convenience helper to avoid repeating the global variable path.

#### Outputs

System.String — The current thread GUID string, or $null if not set.

#### Examples

```powershell
PS> Get-ThreadId
```

#### Notes

The value is read from `(Get-GlobalRuntimeVariable).Private.Threading.ThreadId`.

*Source: [src/Core/Threading/Private/Get-ThreadId.ps1](../../src/Core/Threading/Private/Get-ThreadId.ps1)*

---

### Get-ThreadLastSeen

*Private function*

**Synopsis:** Return seconds since the thread was last seen (heartbeat).

#### Description

`Get-ThreadLastSeen` reads a thread's `LastSeen` timestamp from the global
thread registry and returns the elapsed seconds (rounded) since that timestamp.
If the thread or timestamp is missing, `$null` is returned.

#### Parameters

**`$ThreadId`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ThreadId | System.String | The thread id to query. Defaults to current thread. | (Get-ThreadId) |

#### Outputs

System.Double — Seconds since the last heartbeat, or $null if the thread is unknown.

#### Examples

```powershell
PS> Get-ThreadLastSeen -ThreadId $tid
```

#### Notes

Used by health checks and thread state transitions in the housekeeper.

*Source: [src/Core/Threading/Private/Get-ThreadLastSeen.ps1](../../src/Core/Threading/Private/Get-ThreadLastSeen.ps1)*

---

### Get-ThreadState

*Private function*

**Synopsis:** Evaluate and normalize the runtime state of a thread.

#### Description

`Get-ThreadState` inspects a thread's stored state and returns a normalized
status such as 'RUNNING', 'IDLE', 'BLOCKED', or the raw stored state when
unmodified. It uses the thread's `LastSeen` timestamp and `KeepAlive` flag to
differentiate between active and idle conditions.

#### Parameters

**`$ThreadId`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ThreadId | System.String | The thread id to evaluate. Defaults to current thread. | (Get-ThreadId) |

#### Outputs

System.String — Normalisierter Thread-State (z.B. RUNNING, IDLE, BLOCKED).

#### Examples

```powershell
PS> Get-ThreadState -ThreadId $tid
```

#### Notes

Relies on configuration values such as `(Get-GlobalRuntimeVariable).Public.Threading.IdleTime`.

*Source: [src/Core/Threading/Private/Get-ThreadState.ps1](../../src/Core/Threading/Private/Get-ThreadState.ps1)*

---

### Get-ThreadTree

*Private function*

**Synopsis:** Build a hierarchical tree of all registered threads as PSObjects.

#### Description

`Get-ThreadTree` collects every thread from the global thread registry and
assembles it into a list of root-level tree nodes. Each node holds the
resolved thread state, last-seen age, parameters and a `Children` array that
contains the child nodes in the same format — forming a complete, self-contained
representation of the thread hierarchy without requiring further registry
lookups.

#### Outputs

System.Array. Sorted array of root-level thread nodes. Each node is a
PSObject with the following properties:

| Property   | Type             | Description                          |
|------------|------------------|--------------------------------------|
| Id         | System.String    | Unique thread GUID                   |
| Name       | System.String    | Display name of the thread           |
| Command    | System.String    | Entry-point command name             |
| State      | System.String    | Resolved state (RUNNING, IDLE, …)   |
| LastSeen   | System.Double    | Seconds since last heartbeat         |
| KeepAlive  | System.Boolean   | Whether the thread is kept alive     |
| Parameters | System.Hashtable | Parameters passed to the command     |
| ParentId   | System.String    | Parent thread GUID or $null          |
| Children   | System.Array     | Ordered child nodes (same structure) |

#### Examples

```powershell
PS> $tree = Get-ThreadTree
PS> $tree[0].Children
```

#### Notes

The function resolves state and last-seen values at call time via
`Get-ThreadState` and `Get-ThreadLastSeen`.

*Source: [src/Core/Threading/Private/Get-ThreadTree.ps1](../../src/Core/Threading/Private/Get-ThreadTree.ps1)*

---

### New-Thread

*Private function*

**Synopsis:** Create and (optionally) start a managed background PowerShell thread.

#### Description

`New-Thread` creates a PowerShell runspace with a thread-local environment,
registers the thread in the global threading registry and optionally starts it.
The function supports keep-alive semantics and parent/child relationships.

#### Parameters

**`$Command`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Command | System.String | The command (function) name to execute in the thread | |

**`$Parameters`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Parameters | System.Hashtable | Named parameters passed to the command | @{} |

**`$ParentThread`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ParentThread | System.String | Optional parent thread id (defaults to current thread) | $null |

**`$OverrideName`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| OverrideName | System.String | Optional explicit display name for the created thread | $null |

**`$Start`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Start | System.SwitchParameter | When set, start the thread immediately after creation | $false |

**`$KeepAlive`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| KeepAlive | System.SwitchParameter | When set, the housekeeper may restart the thread on failure | $false |

**`$WaitForJobs`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| WaitForJobs | System.SwitchParameter | When set the thread is expected to wait for queued jobs | $false |

#### Outputs

System.String. The newly created thread id.

#### Examples

```powershell
PS> New-Thread -Command 'Start-Worker' -Parameters @{ 'Queue' = $q } -Start
```

#### Notes

This helper uses `Set-ThreadData` in the created runspace to initialize thread-local state.

*Source: [src/Core/Threading/Private/New-Thread.ps1](../../src/Core/Threading/Private/New-Thread.ps1)*

---

### New-ThreadPool

*Private function*

**Synopsis:** Create or return a shared PowerShell runspace pool for threads.

#### Description

`New-ThreadPool` creates a `RunspacePool` with the given minimum and maximum
instances and caches it on the global runtime variable. If a pool already
exists, the cached instance is returned.

#### Parameters

**`$MinInstances`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| MinInstances | System.Int32 | Minimum number of runspaces in the pool | 1 |

**`$MaxInstances`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| MaxInstances | System.Int32 | Maximum number of runspaces in the pool | `(Get-GlobalRuntimeVariable).Public.Threading.MaxThreads` |

#### Outputs

System.Management.Automation.Runspaces.RunspacePool — The newly created or cached runspace pool.

#### Examples

```powershell
PS> New-ThreadPool -MinInstances 2 -MaxInstances 8
```

#### Notes

The function currently uses the default `InitialSessionState`. Future work may enable JEA.

*Source: [src/Core/Threading/Private/New-ThreadPool.ps1](../../src/Core/Threading/Private/New-ThreadPool.ps1)*

---

### Set-ThreadFrozen

*Private function*

**Synopsis:** Mark a thread as FROZEN if it appears unresponsive.

#### Description

`Set-ThreadFrozen` checks the last-seen timestamp for a given thread and, if
it exceeds the configured keep-alive threshold, sets the thread state to
`FROZEN` and emits a warning log entry.

#### Parameters

**`$ThreadId`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ThreadId | System.String | The thread id to inspect. Defaults to current thread. | (Get-ThreadId) |

#### Outputs

None — Updates the thread state in the global registry and emits a warning log entry when frozen.

#### Examples

```powershell
PS> Set-ThreadFrozen -ThreadId $tid
```

#### Notes

This helper is used by the housekeeper loop to detect and flag unresponsive threads.

*Source: [src/Core/Threading/Private/Set-ThreadFrozen.ps1](../../src/Core/Threading/Private/Set-ThreadFrozen.ps1)*

---

### Set-ThreadProcessing

*Private function*

**Synopsis:** Mark the current thread as processing and refresh its heartbeat.

#### Description

`Set-ThreadProcessing` updates the current thread's state to `PROCESSING`
and records the current timestamp in `LastSeen` to indicate activity.

#### Outputs

None — Modifies `(Get-GlobalRuntimeVariable).Public.Threading.Threads` for the current thread.

#### Examples

```powershell
PS> Set-ThreadProcessing
```

#### Notes

Typically called by worker loops when they start handling a job.

*Source: [src/Core/Threading/Private/Set-ThreadProcessing.ps1](../../src/Core/Threading/Private/Set-ThreadProcessing.ps1)*

---

### Show-Threads

*Private function*

**Synopsis:** Render or return the current thread hierarchy and status.

#### Description

`Show-Threads` builds a complete thread tree via `Get-ThreadTree` and either
returns the structured tree objects or renders them as a formatted hierarchy
string and emits it to the logging system — depending on the `-AsObject`
switch.

#### Parameters

**`$AsObject`**

| Name     | Type                    | Description                                        | Default |
|----------|-------------------------|----------------------------------------------------|---------|
| AsObject | System.SwitchParameter  | Return the tree as PSObjects instead of rendering  | $false  |

#### Outputs

System.Array when `-AsObject` is set. Returns the root-level thread nodes
produced by `Get-ThreadTree`, each with a `Children` array for the full
hierarchy.

None otherwise. Writes a formatted thread hierarchy string to the logging
queue.

#### Examples

```powershell
PS> Show-Threads
```

```powershell
PS> $tree = Show-Threads -AsObject
PS> $tree[0].Children
```

#### Notes

Relies on `Get-ThreadTree` to build the hierarchy and `Write-ThreadTree` to
render individual branches.

*Source: [src/Core/Threading/Private/Show-Threads.ps1](../../src/Core/Threading/Private/Show-Threads.ps1)*

---

### Start-ThreadHouseKeeper

*Private function*

**Synopsis:** Periodic housekeeper that monitors and manages thread lifecycle.

#### Description

`Start-ThreadHouseKeeper` runs a loop that inspects all registered threads,
marks unresponsive threads as `FROZEN`, cleans up terminated or dead threads,
and attempts restarts for keep-alive threads. It sleeps between cycles to
reduce resource usage.

#### Outputs

None — Performs side-effect operations on the global thread registry and logs actions.

#### Examples

```powershell
PS> Start-ThreadHouseKeeper
```

#### Notes

This function is intended to run as a background supervisory thread.

*Source: [src/Core/Threading/Private/Start-ThreadHouseKeeper.ps1](../../src/Core/Threading/Private/Start-ThreadHouseKeeper.ps1)*

---

### Stop-Thread

*Private function*

**Synopsis:** Request termination for a registered thread.

#### Description

`Stop-Thread` marks a thread's state as `TERMINATED` in the global thread
registry. It validates the provided thread id and returns structured results
using `Write-FunctionReturnValue` when errors occur.

#### Parameters

**`$ThreadId`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ThreadId | System.String | The id of the thread to stop | $null |

#### Outputs

System.Management.Automation.PSCustomObject — Strukturierter Rueckgabewert bei Fehler (via Write-FunctionReturnValue); None bei Erfolg.

#### Examples

```powershell
PS> Stop-Thread -ThreadId $tid
```

#### Notes

The actual runspace shutdown and cleanup is handled by the housekeeper loop.

*Source: [src/Core/Threading/Private/Stop-Thread.ps1](../../src/Core/Threading/Private/Stop-Thread.ps1)*

---

### Test-ThreadRunning

*Private function*

**Synopsis:** Core loop gate to determine whether a thread should continue running.

#### Description

`Test-ThreadRunning` is invoked by thread loops to decide if the thread
should continue executing. It updates heartbeats, refreshes logging ids,
checks the thread state and optionally validates TCP/WebSocket connectivity.
It also enforces lightweight sleeps to reduce CPU usage.

#### Parameters

**`$CheckTcpConnection`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| CheckTcpConnection | System.SwitchParameter | When set test the global TCP connection status | $false |

**`$CheckWebSocket`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| CheckWebSocket | System.SwitchParameter | When set test the WebSocket connectivity | $false |

**`$NoSleep`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| NoSleep | System.SwitchParameter | When set skip the default short sleep at loop start | $false |

#### Outputs

System.Boolean — $true when the thread should continue, $false otherwise.

#### Examples

```powershell
while (Test-ThreadRunning) { Do-Work }
```

#### Notes

This function performs multiple side effects (timestamp updates, logging id rotation)
and is central to thread lifecycle management.

*Source: [src/Core/Threading/Private/Test-ThreadRunning.ps1](../../src/Core/Threading/Private/Test-ThreadRunning.ps1)*

---

### Write-ThreadTree

*Private function*

**Synopsis:** Append a formatted tree entry for a thread node to a StringBuilder.

#### Description

`Write-ThreadTree` renders a single thread line (with name, id, state, age,
and parameters) into a supplied `System.Text.StringBuilder` and recursively
renders child nodes from the pre-built tree to produce the full hierarchical
view. The node is a PSObject as returned by `Get-ThreadTree`.

#### Parameters

**`$Node`**

| Name | Type          | Description                              | Default |
|------|---------------|------------------------------------------|---------|
| Node | PSObject      | Tree node as returned by `Get-ThreadTree` | $null   |

**`$StringBuilder`**

| Name          | Type                        | Description                     | Default |
|---------------|-----------------------------|---------------------------------|---------|
| StringBuilder | System.Text.StringBuilder   | The builder to append lines to  | $null   |

**`$Level`**

| Name  | Type          | Description                         | Default |
|-------|---------------|-------------------------------------|---------|
| Level | System.Int32  | Nesting level for indentation       | 0       |

#### Outputs

None. Appends formatted lines to the provided `StringBuilder` instance.

#### Examples

```powershell
$sb = [System.Text.StringBuilder]::new()
Get-ThreadTree | ForEach-Object { Write-ThreadTree -Node $_ -StringBuilder $sb }
```

#### Notes

This function does not return a value; it operates by side-effects on the
supplied builder. Child nodes are read directly from `$Node.Children` — no
additional registry lookups are performed.

*Source: [src/Core/Threading/Private/Write-ThreadTree.ps1](../../src/Core/Threading/Private/Write-ThreadTree.ps1)*



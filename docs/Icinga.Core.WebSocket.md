# Icinga.Core.WebSocket

*Auto-generated from `src/Core/WebSocket/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Add-IcingaWebSocketConfig](#add-icingawebsocketconfig)
- [Remove-IcingaWebSocketConfig](#remove-icingawebsocketconfig)
- [Show-IcingaWebSockets](#show-icingawebsockets)

## Private helpers

- [Add-ModuleWebSocketConfig](#add-modulewebsocketconfig)
- [Add-ModuleWebSocketMessageToQueue](#add-modulewebsocketmessagetoqueue)
- [Connect-ModuleWebSocket](#connect-modulewebsocket)
- [Disconnect-ModuleWebSocket](#disconnect-modulewebsocket)
- [Get-ModuleCurrentWebSocketConfig](#get-modulecurrentwebsocketconfig)
- [New-ModuleWebSocketEnvironment](#new-modulewebsocketenvironment)
- [Read-ModuleWebSocket](#read-modulewebsocket)
- [Read-ModuleWebSocketConfig](#read-modulewebsocketconfig)
- [Remove-ModuleWebSocketConfig](#remove-modulewebsocketconfig)
- [Show-ModuleWebSockets](#show-modulewebsockets)
- [Start-ModuleWebSocketDaemon](#start-modulewebsocketdaemon)
- [Start-ModuleWebSocketHandler](#start-modulewebsockethandler)
- [Start-ModuleWebSocketReaderWorker](#start-modulewebsocketreaderworker)
- [Test-ModuleWebSocket](#test-modulewebsocket)
- [Update-ModuleWebSocketThread](#update-modulewebsocketthread)
- [Write-ModuleWebSocket](#write-modulewebsocket)

---

### Add-IcingaWebSocketConfig

*Public function*

**Synopsis:** Register and persist a WebSocket configuration.

#### Description

`Add-IcingaWebSocketConfig` is the public wrapper for `Add-ModuleWebSocketConfig`.
It validates a WebSocket configuration payload, stores it in the runtime
configuration (`$Global:Icinga.Public.WebSocket.Config`), and persists a pointer
file under the Icinga config directory. The function reads the referenced
type-specific config via `Read-ModuleConfigFile` and only writes a path pointer
to disk.

#### Parameters

**`$Name`**

| Name | Type          | Description                            | Default |
|------|---------------|----------------------------------------|---------|
| Name | System.String | Logical name for the WebSocket config  |         |

**`$Address`**

| Name    | Type          | Description                        | Default |
|---------|---------------|------------------------------------|---------|
| Address | System.String | Remote WebSocket URI (wss://...)   |         |

**`$Config`**

| Name   | Type          | Description                                        | Default |
|--------|---------------|----------------------------------------------------|---------|
| Config | System.String | Path or pointer to the type-specific config file   |         |

**`$Type`**

| Name | Type          | Description                           | Default |
|------|---------------|---------------------------------------|---------|
| Type | System.String | Logical type for the WebSocket config |         |

**`$Force`**

| Name  | Type                    | Description                                    | Default |
|-------|-------------------------|------------------------------------------------|---------|
| Force | System.Management.Automation.SwitchParameter | Overwrite an existing config with the same name | $false |

#### Outputs

System.Object — Returns a structured Icinga return indicating success or the
validation failure.

#### Examples

```powershell
PS> Add-IcingaWebSocketConfig -Name 'MyWebSocket' -Address 'wss://mywebsocket.example.com:443' -Config 'configs\mywebsocket.json' -Type MyWebSocket
```

#### Notes

The persisted file under the Icinga config directory contains only the path
pointer to the type-specific config, not the full in-memory object. Requires
read access to the type-specific configuration file referenced by `Config`.
Configuration is stored in `$Global:Icinga.Public.WebSocket.Config`.

*Source: [src/Core/WebSocket/Public/Add-IcingaWebSocketConfig.ps1](../../src/Core/WebSocket/Public/Add-IcingaWebSocketConfig.ps1)*

---

### Remove-IcingaWebSocketConfig

*Public function*

**Synopsis:** Remove a persisted WebSocket configuration file.

#### Description

`Remove-IcingaWebSocketConfig` is the public wrapper for
`Remove-ModuleWebSocketConfig`. It removes the persisted pointer file for a
named WebSocket configuration from the Icinga config directory. The function
does not modify in-memory runtime structures; a running WebSocket environment
must be restarted separately to reflect the removal.

#### Parameters

**`$Name`**

| Name | Type          | Description                                    | Default |
|------|---------------|------------------------------------------------|---------|
| Name | System.String | Logical name of the WebSocket config to remove |         |

#### Outputs

System.Object — Emits a structured return value when no name is provided;
otherwise removes the file and returns quietly.

#### Examples

```powershell
PS> Remove-IcingaWebSocketConfig -Name 'MyWebSocket'
```

#### Notes

Only the persisted pointer file on disk is removed. The in-memory configuration
in `$Global:Icinga.Public.WebSocket.Config` is not modified. No special
permissions beyond write access to the Icinga config directory are required.

*Source: [src/Core/WebSocket/Public/Remove-IcingaWebSocketConfig.ps1](../../src/Core/WebSocket/Public/Remove-IcingaWebSocketConfig.ps1)*

---

### Show-IcingaWebSockets

*Public function*

**Synopsis:** Display the currently configured WebSocket endpoints.

#### Description

`Show-IcingaWebSockets` is the public wrapper for `Show-ModuleWebSockets`. It
reads all WebSocket configurations from `$Global:Icinga.Public.WebSocket.Config`
and emits them as a formatted output message via `Write-LoggingEntry` at the
`Output` level. The function is intended for interactive inspection during
runtime and produces no return value.

#### Outputs

None — Writes the WebSocket configurations as a formatted output entry via
`Write-LoggingEntry`.

#### Examples

```powershell
PS> Show-IcingaWebSockets
```

#### Notes

No parameters are required. The output is written through `Write-LoggingEntry`
and is not returned to the pipeline. Requires the WebSocket environment to have
been initialized via `Start-ModuleWebSocketDaemon` for meaningful output.

*Source: [src/Core/WebSocket/Public/Show-IcingaWebSockets.ps1](../../src/Core/WebSocket/Public/Show-IcingaWebSockets.ps1)*

---

### Add-ModuleWebSocketConfig

*Private function*

**Synopsis:** Register and persist a WebSocket configuration.

#### Description

`Add-ModuleWebSocketConfig` validates a WebSocket configuration payload,
stores it in the runtime configuration (`$Global:ModuleName.Public.WebSocket.Config`),
and persists a pointer file under the module config directory. The function
reads the referenced type-specific config via `Read-ModuleConfigFile` and
only writes a path pointer to disk.

#### Parameters

**`$Name`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name for the WebSocket config | |

**`$Address`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Address | System.String | Remote WebSocket URI (wss://...) | |

**`$Config`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Config | System.String | Path or pointer to the type-specific config | |

**`$Type`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Type | System.String | Logical type for the WebSocket config | |

**`$Force`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.SwitchParameter | Overwrite an existing config with the same name | false |

#### Outputs

System.Object — Returns a structured module return indicating success or the validation failure.

#### Examples

```powershell
PS> Add-ModuleWebSocketConfig -Name 'MyWebSocket' -Address 'wss://example.com' -Config 'configs\mywebsocket.json' -Type MyWebSocket
```

#### Notes

The persisted file under the config directory contains only the path pointer to
the type-specific config (not the full in-memory object). The configuration is
stored in `$Global:ModuleName.Public.WebSocket.Config` and accessed via
`Get-GlobalRuntimeVariable`.

*Source: [src/Core/WebSocket/Private/Add-ModuleWebSocketConfig.ps1](../../src/Core/WebSocket/Private/Add-ModuleWebSocketConfig.ps1)*

---

### Add-ModuleWebSocketMessageToQueue

*Private function*

**Synopsis:** Enqueue a message for a WebSocket writer worker.

#### Description

`Add-ModuleWebSocketMessageToQueue` places a message into the configured
WebSocket writer queue. It validates the WebSocket name (allowing an
override) and the message payload, logs the enqueue operation and returns a
structured module return on error conditions.

#### Parameters

**`$Message`**

| Name    | Type         | Description                        | Default |
|---------|--------------|------------------------------------|---------|
| Message | System.String| Message payload to enqueue.        |         |

**`$OverrideWebSocketName`**

| Name                  | Type         | Description                               | Default |
|-----------------------|--------------|-------------------------------------------|---------|
| OverrideWebSocketName  | System.String| Optional runtime websocket name override.|         |

#### Outputs

System.Object — Emits module structured return values on error; otherwise the
message is placed in the BlockingCollection and the function returns without
an explicit value.

#### Examples

```powershell
PS> Add-ModuleWebSocketMessageToQueue -Message $payload
```

#### Notes

The message is written directly to the `WriterWorker` BlockingCollection stored
in `$Global:ModuleName.Public.WebSocket.<Name>.WriterWorker`. This collection is
consumed by `Write-ModuleWebSocket` running in a separate worker thread. The
function must be called from within a worker context where
`Get-GlobalRuntimeVariable` provides a valid WebSocket name via
`Private.WebSocket.Name`.

*Source: [src/Core/WebSocket/Private/Add-ModuleWebSocketMessageToQueue.ps1](../../src/Core/WebSocket/Private/Add-ModuleWebSocketMessageToQueue.ps1)*

---

### Connect-ModuleWebSocket

*Private function*

**Synopsis:** Establish a new ClientWebSocket connection and register it in runtime state.

#### Description

`Connect-ModuleWebSocket` connects to a remote WebSocket URI using
`System.Net.WebSockets.ClientWebSocket`, initializes cancellation token
sources and stores the resulting objects in the private runtime state for
use by reader/writer workers. It validates parameters and returns structured
module return values.

#### Parameters

**`$Name`**

| Name | Type         | Description                          | Default |
|------|--------------|--------------------------------------|---------|
| Name | System.String| Logical name for the WebSocket entry.|         |

**`$Address`**

| Name    | Type         | Description                               | Default |
|---------|--------------|-------------------------------------------|---------|
| Address | System.String| WebSocket URI to connect to.              |         |

#### Outputs

System.Object — Emits `Write-FunctionReturnValue` results describing success or failure.

#### Examples

```powershell
PS> Connect-ModuleWebSocket -Name 'MyWebSocket' -Address 'wss://example.com'
```

#### Notes

Any existing connection is cleaned up via `Disconnect-ModuleWebSocket` before a
new one is established. The resulting `ClientWebSocket` and
`CancellationTokenSource` are stored in `$Global:ModuleName.Private.WebSocket`
and must be accessed via `Get-GlobalRuntimeVariable` from worker threads.

*Source: [src/Core/WebSocket/Private/Connect-ModuleWebSocket.ps1](../../src/Core/WebSocket/Private/Connect-ModuleWebSocket.ps1)*

---

### Disconnect-ModuleWebSocket

*Private function*

**Synopsis:** Close and dispose the active WebSocket connection.

#### Description

`Disconnect-ModuleWebSocket` attempts a graceful close of the active
`ClientWebSocket` then disposes runtime resources. It returns structured
module results for success, not-connected, and various error conditions.

#### Outputs

System.Object — Structured `Write-FunctionReturnValue` values describing the outcome.

#### Examples

```powershell
PS> Disconnect-ModuleWebSocket
```

#### Notes

This function is safe to call even when no connection exists. It ensures cleanup
of any lingering `ClientWebSocket` and `CancellationTokenSource` objects to
avoid memory leaks. The function accesses runtime state via
`Get-GlobalRuntimeVariable`.

*Source: [src/Core/WebSocket/Private/Disconnect-ModuleWebSocket.ps1](../../src/Core/WebSocket/Private/Disconnect-ModuleWebSocket.ps1)*

---

### Get-ModuleCurrentWebSocketConfig

*Private function*

**Synopsis:** Return the WebSocket configuration object for the current thread.

#### Description

`Get-ModuleCurrentWebSocketConfig` determines which WebSocket instance is
assigned to the calling thread (via `$Global:ModuleName.Private.WebSocket.Name`) and
returns the corresponding configuration object stored in
`$Global:ModuleName.Public.WebSocket.Config`. If no name or config is found the
function returns `$null`.

#### Outputs

System.Management.Automation.PSCustomObject — Returns the WebSocket configuration
object for the current thread, or `$null` when no configuration is available.

#### Examples

```powershell
PS> Get-ModuleCurrentWebSocketConfig
```

#### Notes

Relies on global state populated by WebSocket management functions under
`Core\WebSocket`. Typical consumers are reader and handler threads that need
access to the current connection credentials and settings. The thread-local
WebSocket name is read from `$Global:ModuleName.Private.WebSocket.Name` via
`Get-GlobalRuntimeVariable`.

*Source: [src/Core/WebSocket/Private/Get-ModuleCurrentWebSocketConfig.ps1](../../src/Core/WebSocket/Private/Get-ModuleCurrentWebSocketConfig.ps1)*

---

### New-ModuleWebSocketEnvironment

*Private function*

**Synopsis:** Initialize WebSocket runtime environments and start handler threads.

#### Description

`New-ModuleWebSocketEnvironment` loads WebSocket configuration files,
creates per-instance runtime containers (reader/writer queues) and starts
handler threads for each configured WebSocket instance. The function ensures
that the public runtime structure is populated for subsequent operations.

#### Outputs

System.Object — Returns a structured `Write-FunctionReturnValue` indicating
success or the absence of any configurations to initialize.

#### Examples

```powershell
PS> New-ModuleWebSocketEnvironment
```

#### Notes

Uses `Read-ModuleWebSocketConfig` to load persisted configurations and
`New-Thread` to spawn a `Start-ModuleWebSocketHandler` thread per instance.
Each instance receives its own `ReaderWorker` and `WriterWorker`
`BlockingCollection` stored in `$Global:ModuleName.Public.WebSocket`.

*Source: [src/Core/WebSocket/Private/New-ModuleWebSocketEnvironment.ps1](../../src/Core/WebSocket/Private/New-ModuleWebSocketEnvironment.ps1)*

---

### Read-ModuleWebSocket

*Private function*

**Synopsis:** Read messages from an open WebSocket and enqueue them for processing.

#### Description

`Read-ModuleWebSocket` continuously reads messages from the active
`ClientWebSocket`, converts the received bytes into UTF8 strings and
pushes complete messages to the configured reader worker queue for the
connection name. It updates thread processing state and handles
exceptions by emitting structured module return values.

#### Parameters

**`$Name`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection | |

**`$ClientWebSocket`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | The active client WebSocket instance | |

**`$CancellationTokenSource`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Token source used to cancel read operations | |

#### Outputs

System.Object — Emits structured `Write-FunctionReturnValue` values on errors;
otherwise received messages are placed into the named reader worker queue for
downstream processing.

#### Examples

```powershell
PS> Read-ModuleWebSocket -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts
```

#### Notes

This function is designed to run inside a dedicated worker thread spawned by
`Start-ModuleWebSocketHandler`. It stores connection references via
`Update-ModuleWebSocketThread` into `$Global:ModuleName.Private.WebSocket` and
reads from the `ClientWebSocket` in a blocking loop. Received messages are
placed in the `ReaderWorker` BlockingCollection under
`$Global:ModuleName.Public.WebSocket.<Name>`. The loop runs until
`Test-ThreadRunning -CheckWebSocket` returns `$false`.

*Source: [src/Core/WebSocket/Private/Read-ModuleWebSocket.ps1](../../src/Core/WebSocket/Private/Read-ModuleWebSocket.ps1)*

---

### Read-ModuleWebSocketConfig

*Private function*

**Synopsis:** Load WebSocket configuration files into the runtime config store.

#### Description

`Read-ModuleWebSocketConfig` scans the module configuration directory for
WebSocket JSON files, validates and parses each file, then loads the
referenced type-specific configuration using `Read-ModuleConfigFile`.
Parsed configurations are stored in `$Global:ModuleName.Public.WebSocket.Config`.

#### Outputs

System.Object — Emits structured `Write-FunctionReturnValue` values indicating
load results and returns the populated config object on success.

#### Examples

```powershell
PS> Read-ModuleWebSocketConfig
```

#### Notes

Each WebSocket configuration file must include a `Name` property and a `Config`
pointer referencing the type-specific configuration file. Parsed configurations
are stored in `$Global:ModuleName.Public.WebSocket.Config` and accessed via
`Get-GlobalRuntimeVariable`.

*Source: [src/Core/WebSocket/Private/Read-ModuleWebSocketConfig.ps1](../../src/Core/WebSocket/Private/Read-ModuleWebSocketConfig.ps1)*

---

### Remove-ModuleWebSocketConfig

*Private function*

**Synopsis:** Remove a persisted WebSocket configuration file.

#### Description

`Remove-ModuleWebSocketConfig` removes the persisted pointer file for a
named WebSocket configuration from the module config directory. It does
not modify in-memory runtime structures.

#### Parameters

**`$Name`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket config to remove | |

#### Outputs

System.Object — Emits a structured return value when no name is provided; otherwise it removes the file and returns quietly.

#### Examples

```powershell
PS> Remove-ModuleWebSocketConfig -Name 'MyWebSocket'
```

*Source: [src/Core/WebSocket/Private/Remove-ModuleWebSocketConfig.ps1](../../src/Core/WebSocket/Private/Remove-ModuleWebSocketConfig.ps1)*

---

### Show-ModuleWebSockets

*Private function*

**Synopsis:** Display the currently configured WebSocket endpoints.

#### Description

`Show-ModuleWebSockets` reads all WebSocket configurations from
`$Global:ModuleName.Public.WebSocket.Config` via `Get-GlobalRuntimeVariable` and
emits them as a formatted output message using `Write-LoggingEntry` at the
`Output` level. The function is intended for interactive inspection during
runtime and produces no return value.

#### Outputs

None — Writes the WebSocket configurations as a formatted output entry via
`Write-LoggingEntry`.

#### Examples

```powershell
PS> Show-ModuleWebSockets
```

*Source: [src/Core/WebSocket/Private/Show-ModuleWebSockets.ps1](../../src/Core/WebSocket/Private/Show-ModuleWebSockets.ps1)*

---

### Start-ModuleWebSocketDaemon

*Private function*

**Synopsis:** Start the WebSocket environment background thread.

#### Description

`Start-ModuleWebSocketDaemon` starts the WebSocket environment by creating a
background thread that initializes the WebSocket runtime (`New-ModuleWebSocketEnvironment`).
The function returns immediately after the management thread is started.

#### Outputs

None — Starts a background thread and returns immediately without a return value.

#### Examples

```powershell
PS> Start-ModuleWebSocketDaemon
```

#### Notes

This helper wraps `New-Thread` to ensure the WebSocket environment is
initialized on a separate thread. The background thread executes
`New-ModuleWebSocketEnvironment`, which loads all persisted WebSocket
configurations and spawns per-instance handler threads.

*Source: [src/Core/WebSocket/Private/Start-ModuleWebSocketDaemon.ps1](../../src/Core/WebSocket/Private/Start-ModuleWebSocketDaemon.ps1)*

---

### Start-ModuleWebSocketHandler

*Private function*

**Synopsis:** Manage a persistent WebSocket connection and spawn worker threads.

#### Description

`Start-ModuleWebSocketHandler` drives the lifecycle for a named WebSocket
connection. It attempts to establish the connection, performs any type-
specific authentication steps (for example MyWebSocket), and
spawns reader, writer and processing worker threads. The handler runs in a
loop and is responsible for reconnection and keep-alive handling.

#### Parameters

**`$Name`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Name of the WebSocket configuration to manage | |

#### Outputs

System.Object — Emits structured return codes for validation failures; otherwise
the function runs until the thread manager requests termination.

#### Examples

```powershell
PS> Start-ModuleWebSocketHandler -Name 'MySocket'
```

#### Notes

The function expects a corresponding configuration entry in
`$Global:ModuleName.Public.WebSocket.Config` for the provided `Name`. It runs
inside a dedicated thread spawned by `New-ModuleWebSocketEnvironment` and drives
connection, reconnection, keep-alive handling, as well as spawning of reader,
writer and processing worker threads.

*Source: [src/Core/WebSocket/Private/Start-ModuleWebSocketHandler.ps1](../../src/Core/WebSocket/Private/Start-ModuleWebSocketHandler.ps1)*

---

### Start-ModuleWebSocketReaderWorker

*Private function*

**Synopsis:** Worker loop: dequeue WebSocket messages and dispatch by type.

#### Description

`Start-ModuleWebSocketReaderWorker` consumes messages from the named
WebSocket reader queue, converts them into message objects depending on the
WebSocket type (for example MyWebSocket), and augments them with
`Origin` metadata for downstream processing. The worker runs until the thread
manager requests shutdown.

#### Parameters

**`$Name`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection to read from | |

**`$ClientWebSocket`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | Active client WebSocket instance | |

**`$CancellationTokenSource`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Cancellation token source used to cancel operations | |

#### Outputs

System.Object — Emits structured module return values on errors; otherwise
messages are prepared and enqueued for further processing.

#### Examples

```powershell
PS> Start-ModuleWebSocketReaderWorker -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts
```

*Source: [src/Core/WebSocket/Private/Start-ModuleWebSocketReaderWorker.ps1](../../src/Core/WebSocket/Private/Start-ModuleWebSocketReaderWorker.ps1)*

---

### Test-ModuleWebSocket

*Private function*

**Synopsis:** Check whether the current WebSocket client is connected and open.

#### Description

`Test-ModuleWebSocket` verifies that a `ClientWebSocket` exists in
`$Global:ModuleName.Private.WebSocket` and that its `State` equals `Open`.
Returns a boolean value indicating whether the WebSocket is connected.

#### Outputs

System.Boolean — $true when the WebSocket connection is active and open; $false otherwise.

#### Examples

```powershell
PS> if (Test-ModuleWebSocket) { Write-LoggingEntry -Message 'WebSocket connected' -Level 'Output' }
```

*Source: [src/Core/WebSocket/Private/Test-ModuleWebSocket.ps1](../../src/Core/WebSocket/Private/Test-ModuleWebSocket.ps1)*

---

### Update-ModuleWebSocketThread

*Private function*

**Synopsis:** Update the global WebSocket thread state for the current runtime.

#### Description

`Update-ModuleWebSocketThread` stores the active WebSocket thread values
(`Name`, `ClientWebSocket`, `CancellationTokenSource`) in
`$Global:ModuleName.Private.WebSocket` so other WebSocket helper threads can
access the current connection reference.

#### Parameters

**`$Name`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection | |

**`$ClientWebSocket`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | Active client WebSocket instance | |

**`$CancellationTokenSource`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Cancellation token source used to cancel reads/writes | |

#### Outputs

System.Object — Returns structured `Write-FunctionReturnValue` status codes indicating success or validation failures.

#### Examples

```powershell
PS> Update-ModuleWebSocketThread -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts
```

*Source: [src/Core/WebSocket/Private/Update-ModuleWebSocketThread.ps1](../../src/Core/WebSocket/Private/Update-ModuleWebSocketThread.ps1)*

---

### Write-ModuleWebSocket

*Private function*

**Synopsis:** Dequeue messages and send them over the active WebSocket.

#### Description

`Write-ModuleWebSocket` continuously reads messages from the named
WebSocket writer queue and sends them to the remote endpoint using the
active `ClientWebSocket`. The function retries queueing when the socket
is not connected and emits structured return values on errors.

#### Parameters

**`$Name`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name of the WebSocket connection to write to | |

**`$ClientWebSocket`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ClientWebSocket | System.Net.WebSockets.ClientWebSocket | Active client WebSocket instance | |

**`$CancellationTokenSource`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| CancellationTokenSource | System.Threading.CancellationTokenSource | Token source used to cancel send operations | |

#### Outputs

System.Object — Emits structured `Write-FunctionReturnValue` values on send errors.

#### Examples

```powershell
PS> Write-ModuleWebSocket -Name 'MyWebSocket' -ClientWebSocket $ws -CancellationTokenSource $cts
```

*Source: [src/Core/WebSocket/Private/Write-ModuleWebSocket.ps1](../../src/Core/WebSocket/Private/Write-ModuleWebSocket.ps1)*



# Icinga.Api

*Auto-generated from `src/Api/`. Do not edit by hand — run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Start-IcingaApi](#start-icingaapi)

## Private helpers

- [Add-IcingaApiCallToWorkerQueue](#add-icingaapicalltoworkerqueue)
- [New-IcingaApiEnvironment](#new-icingaapienvironment)
- [Start-IcingaApiListener](#start-icingaapilistener)

---

### Start-IcingaApi

*Public function*

**Synopsis:** Start the API subsystem by spawning the API environment background thread

#### Description

Start-IcingaApi is a convenience wrapper that spawns a background thread
running New-IcingaApiEnvironment. The background thread initializes the TLS
certificate, creates the worker queue, starts the configured number of API
worker threads and finally starts the TCP listener thread. Use this function
from interactive sessions or module startup to activate the full API stack.

#### Outputs

None — The API subsystem is activated as a side effect via background threads.

#### Examples

```powershell
PS> Start-IcingaApi

Spawns the API environment thread which brings up the listener and workers.
```

#### Notes

Delegates all initialization to New-IcingaApiEnvironment running inside a
New-Thread background thread. Requires IcingaForWindows.Public.Api.Config to
be populated before calling. No return value is emitted.

*Source: [src/Api/Public/Start-IcingaApi.ps1](../../src/Api/Public/Start-IcingaApi.ps1)*

---

### Add-IcingaApiCallToWorkerQueue

*Private function*

**Synopsis:** Add a TcpClient API call to the appropriate worker queue using a round-robin policy

#### Description

Assigns the provided System.Net.TcpClient to one of the API worker queues.
The function increments the global counter at IcingaForWindows.Private.TCP.LastWorkerId
and wraps it modulo IcingaForWindows.Public.Api.Config.WorkerCount. If the parameter
is $null the function returns a cmdlet-style object via Write-FunctionReturnValue and
does not enqueue the connection.

#### Parameters

**`$TcpClient`**

| Name      | Type                 | Description                                                  | Default |
|-----------|----------------------|--------------------------------------------------------------|---------|
| TcpClient | System.Net.TcpClient | The incoming API connection to queue (a TcpClient instance). | $null   |

#### Outputs

System.Object — Structured return object from Write-FunctionReturnValue on error; nothing on success.

#### Examples

```powershell
PS> Add-IcingaApiCallToWorkerQueue -TcpClient $client

Queues the provided TcpClient to the next worker according to the module's round-robin policy.
```

#### Notes

Relies on the global state entries IcingaForWindows.Private.TCP.LastWorkerId,
IcingaForWindows.Public.Api.Config.WorkerCount and IcingaForWindows.Public.Api.WorkerQueue.
Uses Write-FunctionReturnValue for standardized error return objects.

*Source: [src/Api/Private/Add-IcingaApiCallToWorkerQueue.ps1](../../src/Api/Private/Add-IcingaApiCallToWorkerQueue.ps1)*

---

### New-IcingaApiEnvironment

*Private function*

**Synopsis:** Initialize the API environment and default configuration for the API listener

#### Description

New-IcingaApiEnvironment prepares runtime globals used by the API subsystem.
It ensures default values for ListenAddress and ListenPort, loads the TLS
certificate from the configured path, initializes the worker queue list in
IcingaForWindows.Public.Api.WorkerQueue and spawns the configured number of
API worker threads via New-Thread. The listener thread is started last. This
function mutates global state and is intended to be invoked once during
process initialization inside a dedicated background thread.

#### Outputs

None — Performs initialization side effects only; returns nothing.

#### Examples

```powershell
PS> New-IcingaApiEnvironment

Creates the API environment and initializes all worker queues and threads.
```

#### Notes

Depends on the global config entries IcingaForWindows.Public.Api.Config
(ListenAddress, ListenPort, WorkerCount) and the certificate path derived
from $CertificateDirectory. Runs inside a background thread spawned by
Start-IcingaApi; do not call directly from the main thread.

*Source: [src/Api/Private/New-IcingaApiEnvironment.ps1](../../src/Api/Private/New-IcingaApiEnvironment.ps1)*

---

### Start-IcingaApiListener

*Private function*

**Synopsis:** Start the API TCP listener and accept incoming API client connections

#### Description

Start-IcingaApiListener opens a TCP socket using the configured
IcingaForWindows.Public.Api.Config.ListenAddress and ListenPort values.
For each accepted System.Net.Sockets.TcpClient it enqueues the client
for processing by the API workers using Add-IcingaApiCallToWorkerQueue.
The function runs in a tight loop guarded by Test-ThreadRunning and is
intended to run inside a dedicated long-lived background thread spawned
by New-IcingaApiEnvironment.

#### Outputs

None — Produces side effects (opens socket, enqueues clients, writes logs).

#### Examples

```powershell
PS> Start-IcingaApiListener

Starts the API listener on the configured address and port.
```

#### Notes

Reads listen address and port from IcingaForWindows.Public.Api.Config.
Uses Open-TCPSocket to bind and Close-TCPConnection to finalize individual
connections. Exceptions per connection are caught and logged; the listener
loop continues without aborting.

*Source: [src/Api/Private/Start-IcingaApiListener.ps1](../../src/Api/Private/Start-IcingaApiListener.ps1)*



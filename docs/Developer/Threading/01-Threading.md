# Icinga for Windows Threading

This section of the documentation will explain in detail, on how the internal threading architecture works for Icinga for Windows and how developers can use the feature for own, customized background threads.

## Architecture

Icinga for Windows is setting a **Global** variable (`$Global:IcingaForWindows`) after the start, to allow storing different configurations for the environment.

All thread related events are stored under the following path:

### Public Space

Everything put inside the `Public` space is shared and accessible by every single thread for Icinga for Windows.

```powershell
$Global:IcingaForWindows.Public.Threading;
```

### Private Spae

The `Private` space is not shared between threads and is only accessible by the thread itself. It is used to store the threads own id, make it unique for the entire solution.

```powershell
$Global:IcingaForWindows.Private.Threading;
```

### Configuration

The `Public` space will provide the following members:

|   Member   |      Type      |   Default  | Description |
|------------|----------------|------------|-------------|
| ThreadPool | RunSpacePool   | $null      | A thread pool which is created with `[RunSpaceFactory]::CreateRunSpacePool`, allowing up to 100 concurrent threads on the background. |
| Threads    | PSCustomObject | New-Object | A PSCustomObject (IcingaThreadObject) containing all started threads with their members |
| IdleTime   | int            | 30         | The time in seconds it takes before a thread is chaning its state from `RUNNING` to `IDLE` |
| KeepAlive  | int            | 180        | The time in seconds it takes before a thread which is started with `-KeepAlive` is being terminated and restarted if no response is detected |

The `Private` space will provide the following members:

|  Member  |  Type  | Default | Description |
|----------|--------|---------|-------------|
| ThreadId | string | $null   | The GUID as string of the current thread, identifying each thread in a unique way |

### IcingaThreadObject (PSCustomObject)

Each newly created thread is stored as member with the thread id in the `Public` threading space. Accessing a specific thread can for example be done like this:

```powershell
$Global:IcingaForWindows.Public.Threading.Threads.'1ce8780a-45e3-4eeb-94c7-ee1526d3c3c3';
```

Each thread object consist of the following members:

|    Member    |         Type          |   Default  | Description |
|--------------|-----------------------|------------|-------------|
| Name         | string                | -          | The name of the thread which will be displayed. If the thread is running on the main thread, it will display the entire call stack. If the thread is a child thread of a parent, it will only display the executed command |
| Shell        | PowerShell            | -          | The shell object being used to run the specified command in |
| Command      | string                | -          | The Icinga for Windows command to execute inside the thread |
| Parameters   | hashtable             | @{ }       | A hashtable with a key/value pair (argument and value) to start the commands assigned to the thread with different parameters |
| KeepAlive    | bool                  | false      | Tells Icinga for Windows if the thread should be monitored and started automatically in case it didn't respond after a certain time |
| WaitForJobs  | bool                  | false      | This flags determines if the thread is running in a simple loop, executing tasks or if it actively waiting for jobs to be assigned to do, like waiting for Tcp clients to connect on a Tcp listener thread |
| ParentThread | string                | -          | This determines if the thread is running directly from the base of the PowerShell tree or if a thread has created a child thread, like a heartbeat thread for the parents Tcp connection. This value references the `Guid` of the parent thread, is `$null` if started from the main thread or contains `MAIN` once the housekeeper is restarting the thread in case of `KeepAlive` is set and didn't response on time |
| LastSeen     | DateTime              | `Get-Date` | The current timestamp the last time the thread completed an entire run successfully |
| Handle       | PowerShellAsyncResult | -          | An asynchron object which stores the PowerShell session for the executed command of the thread |
| State        | string                | STOPPED    | The current status of the thread |

#### Thread States

|    State   |      Status      | Description |
| -----------| -----------------|-------------|
| RUNNING    | Healthy          | The thread is running and working without any issues |
| ALIVE      | Misconfiguration | Indicates a misconfiguration of your setup. This occurs if a thread is started with the flag `-WaitForJobs` but once a job is taken, the thread status is not set properly to `PROCESSING` with `Set-ThreadProcessing` |
| PROCESSING | Healthy          | Indicates that a thread configured with `-WaitForJobs` is actively processing a work item |
| WAITING    | Healthy          | Indicates that the thread is configured with `-WaitForJobs` and is currently waiting for workload to be assigned |
| IDLE       | Healthy          | Indicates that the thread is not using `-KeepAlive` or `-WaitForJobs` and has not been able to complete a loop run yet `IdleItem = 30s` |
| BLOCKED    | Warning          | Indicates that the thread is using `-KeepAlive` and is in a state on which it didn't complete a loop `IdleItem = 30s` |
| FROZEN     | Error            | Indicates that the thread is using the `-KeepAlive` flag and has not completed a loop within the given time. The internal housekeeper job will flag the thread as `ZOMBIE` in the next step and start another instance `KeepAlive = 180s` |
| ZOMBIE     | Error            | Indicates that the thread did not complete a run within the given `KeepAlive = 180s` time. PowerShell RunSpaces cannot escape a blocking loop and cannot be stopped, therefore those threads remain as ZOMBIES until the Icinga for Windows service is restarted |
| DEAD       | Error            | Indicates that a previous as ZOMBIE marked thread did respond again. Once the thread enters this state, it will be properly cleaned and removed from the memory stack |
| TERMINATED | Healthy          | Indicates that the thread stopped itself, because a required Tcp connection for example was no longer present and the thread for that reason is no longer required |
| SHUTDOWN   | Healthy          | Allows for a graceful shutdown of the thread, ending itself once the next loop cycle is complete. Will not work if the thread is blocked for some reason |

## Working with Threads

Besides the detailed, above description the actual usage of Icinga for Windows threading is very simple. There are only a few rulesets which need to be followed, in order to make the entire system work.

### Creating new Threads

To create a new thread, all you need to do is uring the function

```powershell
New-Thread
```

|   Argument   |    Type   | Default | Description |
|--------------|-----------|---------|-------------|
| Command      | string    | null    | The name of the command or script to invoke inside the new runspace. This must be a command reachable in the runspace's execution context (function, cmdlet or script name). |
| Parameters   | hashtable | null    | A hashtable of parameter name/value pairs to pass to the Command when the runspace is invoked. Keys should be parameter names (without leading dashes) and values their corresponding argument values. |
| ParentThread | string    | null    | Optional thread id of the parent thread. If omitted, the calling thread id is used. If the string 'MAIN' is provided, the parent is treated as the top-level root (no parent) for the thread tree display. **You should never use this, Icinga for Windows will take care of that!** |
| OverrideName | string    | null    | Optional human-readable name to override the automatically generated thread name. Intended for supervisory or housekeeper threads where a stable, recognizable name is desired. **You should never use this, Icinga for Windows will take care of that** |
| Start        | switch    | false   | When specified, the function will begin asynchronous invocation of the runspace and mark the thread state as RUNNING. When not specified, the thread is created, registered and left in STOPPED state for later start. |
| KeepAlive    | switch    | false   | Marks the thread for monitoring by keep-alive/supervisory logic. The thread object records its configuration so that a supervisor can restart it if it terminates unexpectedly. |
| WaitForJobs  | switch    | false   | Indicates that the thread will be running background jobs and that the supervisory logic should wait for those jobs to complete before considering the thread fully stopped. |

#### Example 1

Create a new thread for the Cmdlet `Start-ThreadHouseKeeper` and start it immediately after the creation. No monitoring with `-KeepAlive` required:

```powershell
New-Thread -Command 'Start-ThreadHouseKeeper' -Start;
```

#### Example 2

Start a new thread to create a Tcp listener. In this case, monitor the thread to ensure it is responsive by using `-KeepAlive`. As Tcp listeners use `TcpAcceptClient`, the thread becomes blocking while waiting for a client to connect. Therefore we will have to use `-WaitForJobs` to push the thread into the `WAITING` state. Also, we start the thread immediately:

```powershell
New-Thread -Command 'Start-IcingaProtocolListener' -KeepAlive -WaitForJobs -Start;
```

#### Example 3

Create a new thread that will continuously loop through the code without having to wait for any job being assigned. We just want to make sure the thread keeps being responsive. To enable the monitoring, we use `-KeepAlive`:

```powershell
New-Thread -Command 'Start-IcingaProtocolConnector' -KeepAlive -Start;
```

#### Example 4

Create a new thread and pass some arguments, ensuring our worker knows exactly which id it belongs to:

```powershell
New-Thread -Command 'Start-IcingaProtocolWorker' -Parameters @{ 'WorkerId' = 1 } -KeepAlive -WaitForJobs -Start;
```

### Using Thread loops

The Icinga for Windows threading is designed to work as continuously looping background tasks, reporting back certain elements to the `Public` space if required.

They are **NOT** designed as one-time shot events. You may use them in that way, but the proper execution is to keep them looping until `TERMINATED` or `SHUTDOWN`.

#### General Usage

Icinga for Windows will handle most of the work to keep on track with the thread status. To create a loop, you simply have to use the command `Test-ThreadRunning`:

```powershell
while (Test-ThreadRunning) {
    # Your code
}
```

This call will update the `LastSeen` flags and adjust the `State` of the thread with every single cycle.

If you are relying on Tcp connections within your thread, you can run the Cmdlet with the following flag:

```powershell
while (Test-ThreadRunning -CheckTcpConnection) {
    # Your code
}
```

This will ensure, once a Tcp client disconnects from your system, the thread will look on the connection and terminate itself during the process.

The threading mechanism will always close possible Tcp connections and Tcp sockets, once a given thread is ended.

The flag `-CheckTcpConnection` relies on the internal `TcpClient` and `SslStream` on the `Private` space of the thread.

To make this work, you will have to call `Update-TCPConnection` with at least the `-Client` object.

```powershell
Update-TCPConnection -Client $Client;

while (Test-ThreadRunning -CheckTcpConnection) {
    # Your code
}
```

#### Using WaitForJobs

If your thread is waiting for work load being assigned and is blocked otherwise, because it is waiting for `AcceptTcpClient` for example, you have to make sure you use `Set-ThreadProcessing` once the blocking event returns and object for the thread to work at:

```powershell
while (Test-ThreadRunning) {
    $Client = $Global:IcingaForWindows.Private.TCP.Listener.AcceptTcpClient();
    Set-ThreadProcessing;

    # Rest of your code
}
```

If you are missing `IcingaThreadProcessing`, Icinga for Windows will flag the thread as `ALIVE` and report a `Warning` within the Icinga for Windows Evenlog with id `837` and the following message:

```text
The thread (dedb8fbb-5309-4173-bee8-847db488cf62, Start-IcingaProtocolListener) is marked as WaitForJobs, but you did not use "Set-ThreadProcessing" after a job was taken to update the thread state accordingly.;
```

## Current Thread Status

You can display the current status of your Icinga for Windows threads by using the command `Show-IcingaThreads`. This command will print the current active threads for the local PowerShell session, but also query the Icinga for Windows API at the same time, to receive the status of all active threads within the daemon.

```powershell
icinga> Show-IcingaThreads;

=== ICINGA THREAD HIERARCHY ===
 Main::Use-IcingaForWindows::Start-ThreadHouseKeeper [0f70198e-ca8d-485c-bb3c-92ee985e3797] RUNNING [7.64s]

 Main::Use-IcingaForWindows::Write-IcingaConsole [399f09f7-23da-42db-912d-9d14a1ec0b91] RUNNING [2.66s]

 Main::Start-IcingaAPIListener::New-IcingaProtocolEnvironment [890e5f75-1250-472c-b3be-fcbc949731e0] RUNNING [14.38s]
    └──  Start-IcingaProtocolWorker [846002de-3d49-4b87-a204-31b13598f2b5] WAITING [13.42s] [KEEPALIVE] | Params: @{ -WorkerId 0 }
    └──  Start-IcingaProtocolWorker [bae68d93-ef99-463e-9633-8b5b7dcf5f58] WAITING [12.88s] [KEEPALIVE] | Params: @{ -WorkerId 1 }
    └──  Start-IcingaProtocolWorker [8226f42b-fdfe-48c6-9e07-a75e55c4a036] WAITING [12.37s] [KEEPALIVE] | Params: @{ -WorkerId 2 }
    └──  Start-IcingaProtocolWorker [50c88200-88d8-47ac-93c4-5abc0120ea1c] WAITING [11.82s] [KEEPALIVE] | Params: @{ -WorkerId 3 }
    └──  Start-IcingaProtocolWorker [09304ac1-658b-4298-9629-4d612ac8a6c8] WAITING [11.31s] [KEEPALIVE] | Params: @{ -WorkerId 4 }
    └──  Start-IcingaProtocolListener [67277dfb-cf80-4407-8f24-f19ebe22132f] WAITING [10.76s] [KEEPALIVE]
    └──  Start-IcingaProtocolConnector [cc9b19a9-4c4c-405e-9117-05172ea463c9] RUNNING [4.08s] [KEEPALIVE]
        └──  Start-IcingaProtocolSocketReader [e4d09537-203e-4e9c-87dd-32c2272d3d82] TERMINATED [3.95s]  | Params: @{ -Endpoint icingaa.localdomain; -IsClient True; -Client System.Net.Sockets.TcpClient }
        └──  Start-IcingaProtocolSocketReader [d7bca3cd-a750-4aa7-99c4-47b70e33ce12] TERMINATED [3.21s]  | Params: @{ -Endpoint icingab.localdomain; -IsClient True; -Client System.Net.Sockets.TcpClient }

Total Threads: 12
==================
```

Lets break down that we see:

```powershell
Start-IcingaProtocolWorker [bae68d93-ef99-463e-9633-8b5b7dcf5f58] WAITING [12.88s] [KEEPALIVE] | Params: @{ -WorkerId 1 }
```

This view displays the call stack for each thread. If started with `Main::`, it means the initial thread was called from the very root of Icinga for Windows. Child threads are always added with `└──  ` below the main thread and only displaying the executed command, to keep the UI as simple as possible. Otherwise the call stack is displayed.

Behind the first `[]` we will find the Guid of this thread, for possible directly accessing it and gathering additional information.

Followed by that is the `State` of the thread, like in this case `WAITING`, because we configured it with `-WaitForJobs`.

The second `[]` indicates the time in seconds, for the last time the thread successfully completed a loop run. If you have several worker threads for example, you can determine based on this if all of your workers have distributed the load evenly.

Behind the third `[]` we see the `KEEPALIVE`, which indicates that we used `-KeepAlive` to monitor if the thread is still responsive. This output is missing if we did not use the flag.

Last but not least we have a `|`, which is only present if we passed any arguments to our `New-Thread` call. If we did, all arguments are listed there for reference.

# Icinga for Windows - Code Quality & Linting

This section of the documentation explains the internal Code Quality and Linting checks that are enforced during the build process of Icinga for Windows. 

## Memory Leak Prevention

As background threads and daemons in Icinga for Windows usually run in endless loops, they are highly prone to memory leaks if local variables are not reset properly or unmanaged resources are not disposed. 

The Icinga for Windows build process includes an **AST (Abstract Syntax Tree) Linter** (`Test-ModuleDaemonMemoryLeak.ps1`) which enforces two strict memory constraints on all scripts and modules:

### 1. Local Variables in Endless Loops
Any variable assigned inside a `Test-ThreadRunning` loop **MUST** be explicitly set to `$null` (e.g., inside a `finally` block or at the end of the loop execution). Native value types (like `bool`, `int`, `switch`) are automatically exempted from this check, as they cannot hold a `$null` value.

### 2. IDisposable Objects
Any object that implements `IDisposable` and manages unmanaged resources (e.g., `TcpClient`, `PerformanceCounter`, `X509Certificate2`, `ClientWebSocket`) **MUST** have its `.Dispose()` method called anywhere within the same file if it was instantiated using `New-Object` or `[Type]::new()`.

## Opting out of the Dispose Check

There are valid architectural reasons to intentionally not dispose an object (for example, if a background thread creates a `TcpClient` and pushes it into a global worker queue where another thread takes over ownership). 

In these specific cases, you must explicitly tell the Linter to ignore the missing `.Dispose()` call.

To do so, place the exact comment `# [IcingaIgnoreDisposeCheck]` on the line **directly above** the variable assignment:

```powershell
# [IcingaIgnoreDisposeCheck]
$EventLog = New-Object System.Diagnostics.EventLog;
```

Alternatively, you can place `# [IcingaIgnoreDisposeCheck] $VariableName` anywhere in the same file to globally suppress checks for that specific variable name.

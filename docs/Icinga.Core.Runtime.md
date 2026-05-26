# Icinga.Core.Runtime

*Auto-generated from `src/Core/Runtime/`. Do not edit by hand — run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Exit-Icinga](#exit-icinga)
- [Use-IcingaForWindows](#use-icingaforwindows)

## Private helpers

- [Start-ModuleGarbageCollector](#start-modulegarbagecollector)

---

### Exit-Icinga

*Public function*

**Synopsis:** Forcibly terminate the current PowerShell process used by Icinga

#### Description

`Exit-Icinga` stops the current PowerShell process immediately to avoid the
shell freezing due to background threads that do not terminate on a normal
exit. It forcibly kills the process identified by $PID.

#### Outputs

None — The process is terminated immediately; no value is returned.

#### Examples

```powershell
PS> Exit-Icinga
```

#### Notes

Implementation uses Stop-Process -Force -Id $PID. Intended for scenarios where
a graceful shutdown cannot be achieved. Use with caution: cleanup routines and
background jobs will not complete and state may be lost or inconsistent.

*Source: [src/Core/Runtime/Public/Exit-Icinga.ps1](../../src/Core/Runtime/Public/Exit-Icinga.ps1)*

---

### Use-IcingaForWindows

*Public function*

**Synopsis:** Initialize the IcingaForWindows runtime environment in the current session

#### Description

`Use-IcingaForWindows` performs the necessary startup tasks for the Icinga
PowerShell module. When called without `-NoNewShell` it spawns a new
PowerShell process (preferring pwsh over powershell.exe) and re-invokes
itself with `-NoNewShell` in that child process. When called with
`-NoNewShell` it initializes the base environment, applies the log level,
loads configuration and access control, and starts the standard background
daemon threads (logging, garbage collector, housekeeper, REST API, WebSocket
and Icinga agent). The function is idempotent; repeated calls while already
initialized return immediately.

#### Parameters

**`$LogLevel`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| LogLevel | System.String | Minimum log level for the session. Accepted values: Debug, Audit, Info, Success, Warning, Error, Fatal. | Warning |

**`$NoBackgroundDaemons`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| NoBackgroundDaemons | System.Management.Automation.SwitchParameter | Reserved for future use; currently has no effect on daemon startup. | $false |

**`$NoNewShell`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| NoNewShell | System.Management.Automation.SwitchParameter | When set, initialize directly in the current shell instead of spawning a new process. | $false |

#### Outputs

None — Side effects only: starts background threads and configures global runtime state.

#### Examples

```powershell
PS> Use-IcingaForWindows
```

#### Notes

Depends on New-ModuleBaseEnvironment, New-ModuleConfigEnvironment,
Read-ModuleAccessControl and the daemon functions being available in scope.
The alias `ifw` maps to this function. When running without `-NoNewShell`
the function blocks until the spawned child process exits.

*Source: [src/Core/Runtime/Public/Use-Icinga.ps1](../../src/Core/Runtime/Public/Use-Icinga.ps1)*

---

### Start-ModuleGarbageCollector

*Private function*

**Synopsis:** Background garbage collector loop used by the runtime subsystem.

#### Description

Periodically forces a full .NET garbage collection and clears the `$Error` buffer
while the runtime thread is running. Intended to run as a background helper thread.

#### Outputs

None — Periodically runs garbage collection and clears the error buffer in the background.

#### Examples

```powershell
PS> Start-ModuleGarbageCollector
```

#### Notes

This helper should be run in a dedicated thread and relies on `Test-ThreadRunning`.

*Source: [src/Core/Runtime/Private/Start-ModuleGarbageCollector.ps1](../../src/Core/Runtime/Private/Start-ModuleGarbageCollector.ps1)*



# Icinga.Core.Runtime

*Auto-generated from `src/Core/Runtime/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Exit-Icinga](#exit-icinga)

## Private helpers

- [Start-ModuleGarbageCollector](#start-modulegarbagecollector)

---

### Exit-Icinga

*Public function*

**Synopsis:** Forcibly terminate the current PowerShell process used by Icinga

#### Description

`Exit-Icinga` stops the current PowerShell process immediately to avoid the
shell freezing due to background threads that do not terminate on a normal
exit.

#### Parameters

**`$ExitCode`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ExitCode | System.Int32 | Process exit code to return | 0 |

#### Outputs

None — The process is terminated immediately; no value is returned.

#### Examples

```powershell
PS> Exit-Icinga
```

#### Notes

Uses `[System.Environment]::Exit($ExitCode)` to ensure the process exits cleanly with the desired exit code.

*Source: [src/Core/Runtime/Public/Exit-Icinga.ps1](../../src/Core/Runtime/Public/Exit-Icinga.ps1)*

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



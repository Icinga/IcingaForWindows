# Icinga.Core.Runtime

*Auto-generated from `src/Core/Runtime/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Exit-Icinga](#exit-icinga)
- [Install-IcingaForWindows](#install-icingaforwindows)

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

| Name     | Type         | Description                 | Default |
|----------|--------------|-----------------------------|---------|
| ExitCode | System.Int32 | Process exit code to return | 0       |

#### Outputs

None -- The process is terminated immediately; no value is returned.

#### Examples

```powershell
PS> Exit-Icinga
```

#### Notes

Uses `[System.Environment]::Exit($ExitCode)` to ensure the process exits cleanly with the desired exit code.

*Source: [src/Core/Runtime/Public/Exit-Icinga.ps1](../src/Core/Runtime/Public/Exit-Icinga.ps1)*

---

### Install-IcingaForWindows

*Public function*

**Synopsis:** Perform the base installation of Icinga for Windows on the local host

#### Description

Install-IcingaForWindows trims -Hostname, initializes the internal return-code
table via Set-InternalExitCodes, creates the base Config and Binaries
directories under ProgramData (New-ModuleConfigEnvironment), registers all
IcingaForWindows::<Area> Windows Event Log sources with a 100 MiB maximum log
size (Register-LoggingWindowsEventLog), and generates an initial 4096-bit RSA
self-signed TLS certificate via New-IcingaProtocolCertificate.

The -Hostname value becomes the certificate Common Name (CN) and must match the
exact Endpoint and Host Object Name configured for this node in Icinga 2. The
-Hostname parameter is intentionally non-mandatory so automated callers receive
a standardized numeric return value (7000 InstallerHostnameMissing) via
Write-FunctionReturnValue instead of an interactive PowerShell parameter prompt
when -Hostname is omitted, empty, or whitespace.

#### Parameters

**`$Hostname`**

| Name     | Type          | Description                                                                      | Default |
|----------|---------------|----------------------------------------------------------------------------------|---------|
| Hostname | System.String | Node Object Name (certificate Common Name) used to generate the TLS certificate. | $null   |

#### Outputs

System.Int32 -- Standardized return code from Write-FunctionReturnValue (7001 on
success, 7000 when -Hostname is missing or whitespace, or the certificate error
code such as 50009 on failure).

#### Examples

```powershell
PS> Install-IcingaForWindows -Hostname 'win-srv01.example.com'

Initializes the Icinga for Windows directories, registers Windows Event Log
sources, and generates a self-signed TLS certificate for 'win-srv01.example.com'
in Cert:\CurrentUser\My (or locally under Certificates on Linux/macOS).
```

#### Notes

Requires administrative privileges on Windows to register Windows Event Log
sources and configure the 100 MiB log size under the IcingaForWindows log. On
Windows, the node TLS certificate is stored in Cert:\CurrentUser\My of the
executing user account.

*Source: [src/Core/Runtime/Public/Install-IcingaForWindows.ps1](../src/Core/Runtime/Public/Install-IcingaForWindows.ps1)*

---

### Start-ModuleGarbageCollector

*Private function*

**Synopsis:** Background garbage collector loop used by the runtime subsystem.

#### Description

Periodically forces a full .NET garbage collection and clears the `$Error` buffer
while the runtime thread is running. Intended to run as a background helper thread.

#### Outputs

None -- Periodically runs garbage collection and clears the error buffer in the background.

#### Examples

```powershell
PS> Start-ModuleGarbageCollector
```

#### Notes

This helper should be run in a dedicated thread and relies on `Test-ThreadRunning`.

*Source: [src/Core/Runtime/Private/Start-ModuleGarbageCollector.ps1](../src/Core/Runtime/Private/Start-ModuleGarbageCollector.ps1)*


# Implementation Walkthrough -- Base `Install-IcingaForWindows` Entrypoint & Event Log Wiring (`install-icinga-for-windows`)

## 1. Executive Summary

This branch (`feature/install-icinga-for-windows`) introduces the public `Install-IcingaForWindows` cmdlet as the foundational installation entrypoint for **Icinga for Windows**, completes the end-to-end Windows Event Log source registration and `-Area` logging pipeline, and documents the complete TLS cluster installation workflow:

1. **Public `Install-IcingaForWindows` (`src/Core/Runtime/Public/Install-IcingaForWindows.ps1`):** Validates `-Hostname` programmatically via `Write-FunctionReturnValue` (`InstallerHostnameMissing` `7000` when null, empty, or whitespace -- without triggering an interactive PowerShell `Mandatory` prompt), trims `-Hostname`, initializes `Public.ReturnCodes` via `Set-InternalExitCodes`, provisions the `Config` and `Binaries` directories, registers Windows Event Log sources (`100 MiB`), generates the initial self-signed node TLS certificate (`New-IcingaProtocolCertificate -CommonName $Hostname`), and emits `InstallerCompleted` (`7001`).
2. **Dynamic `-Area` Binding & Fallback (`src/Core/Logging/Private/Write-LoggingEntry.ps1`):** Declares `[string]$Area = $null` so `Write-FunctionReturnValue`'s `-Area $codeEntry.Area` binds explicitly rather than relying on caller scope leakage, invokes `Set-InternalExitCodes` unconditionally at function entry, trims non-blank values, and falls back (`# TODO`) to the generic `EventLogGenericLog` area (`'Logging'`) with a flat `'Logging'` guard whenever `-Area` is omitted or blank.
3. **In-Process Cross-Edition Event Log Registration & Daemon Cleanup (`Register-LoggingWindowsEventLog.ps1`, `Start-LoggingDaemon.ps1`, `New-IcingaProtocolCertificate.ps1`):** Guards non-Windows execution in `Register-LoggingWindowsEventLog`, seeds `IcingaForWindows::Logging`, deduplicates `IcingaForWindows::<Area>` source names case-insensitively, checks `[System.Diagnostics.EventLog]::SourceExists` before calling `[System.Diagnostics.EventLog]::CreateEventSource` directly in-process across both Windows PowerShell 5.1 and PowerShell 7+ (avoiding WinPSCompat `New-EventLog` remoting and deserialized `RemoteException` false warnings on already-existing sources), disposes `EventLogConfiguration` handles, hardens `Start-LoggingDaemon` with Windows Event Log guards, `0..65535` `EventId` bounds, `31839`-character truncation, and `try / finally` loop cleanup, and ensures `Get-ModuleCertificateDirectory` exists before writing `.pfx` files on non-Windows hosts.
4. **Step-by-Step Installation & TLS Documentation (`docs/General/Installation.md`, `README.md`):** Documents base installation, Icinga 2 CA import (`Import-IcingaCertAuthority`), `New-IcingaProtocolEnvironment` + `New-IcingaTlsCertConfig` configuration (explicitly separating optional `(... -DryRun).Output` diff previews from saving `Connection.json` with return code `50019`), Icinga 2 **Object Name** matching, single-quoted `'$fqdn'` / `'$hostname'` placeholders, and certificate signing (`pki::UpdateCertificate` and `-SignedCert`).

---

## 2. Under-the-Hood Deep Dive

### 2.1 Non-Interactive Parameter Validation & Standardized Return Codes
Marking `-Hostname` with `[Parameter(Mandatory = $true)]` would cause unattended automation or remote orchestration scripts to hang waiting for console input whenever `-Hostname` is omitted. Instead, `Install-IcingaForWindows` declares `[string]$Hostname = $null` and checks `[string]::IsNullOrWhiteSpace($Hostname)`, immediately returning `Write-FunctionReturnValue -ReturnValue 'InstallerHostnameMissing'` (`7000`) and enqueueing a structured `Error` log entry under `Area = 'Installer'`.

### 2.2 Explicit `-Area` Parameter & `EventLogGenericLog` Fallback
`Write-FunctionReturnValue` (`src/Core/ErrorHandling/Private/Write-FunctionReturnValue.ps1`, line 73) invokes:
```powershell
Write-LoggingEntry -Message $codeEntry.Message -Level $codeEntry.Severity -EventId $codeEntry.Code -Area $codeEntry['Area'] -Data $Data;
```
Previously, `Write-FunctionReturnValue` used dot-property access (`$codeEntry.Area`, which threw `PropertyNotFoundException` under `Set-StrictMode -Version Latest` on the eight `Set-InternalExitCodes` entries without an `'Area'` key, including `ConfigMissing` during initial `Install-IcingaForWindows` provisioning), while `Write-LoggingEntry` had no `$Area` parameter in `param ()` and constructed `'Area' = $codeEntry.Area` via dynamic scope lookup. Indexing `$codeEntry['Area']` in `Write-FunctionReturnValue`, calling `Set-InternalExitCodes` unconditionally at the start of `Write-LoggingEntry`, declaring `[string]$Area = $null`, and resolving blank values through `Public.ReturnCodes['EventLogGenericLog']['Area']` (with a flat `'Logging'` fallback) guarantees every queued log object carries a registered `IcingaForWindows::<Area>` Event Log source name cleanly under `Set-StrictMode -Version Latest`.

### 2.3 Windows PowerShell 5.1 vs. PowerShell 7 Event Log Source Registration
Immediately after `Import-Module IcingaForWindows`, `(Get-GlobalRuntimeVariable).Public.ReturnCodes` is `$null` until `Set-InternalExitCodes` runs, so `Install-IcingaForWindows` calls `Set-InternalExitCodes` explicitly before invoking `New-ModuleConfigEnvironment` and `Register-LoggingWindowsEventLog`. In addition, on Windows in PowerShell 7, `Get-Command -Name 'New-EventLog'` resolves to an implicit `WinPSCompatSession` proxy function (`CommandType: Function`); calling `New-EventLog -ErrorAction Stop` when an Event Log source already exists throws a deserialized `RemoteException` across the remoting boundary (which does not match `-is [System.InvalidOperationException]`), causing false `Warning` entries on subsequent runs. `Register-LoggingWindowsEventLog` therefore:
1. Returns early when `(Get-GlobalRuntimeVariable).Protected.OSType -ne 'Windows'`.
2. Seeds `IcingaForWindows::Logging` and enumerates `(Get-GlobalRuntimeVariable).Public.ReturnCodes`, deduplicating trimmed `IcingaForWindows::<Area>` source names case-insensitively (`-notcontains`).
3. Checks `if (-not [System.Diagnostics.EventLog]::SourceExists($entry))` and invokes `[System.Diagnostics.EventLog]::CreateEventSource($entry, $ModuleName)` directly in-process on both Windows PowerShell 5.1 and PowerShell 7+. Inside `catch`, `SourceExists($entry)` is re-checked so only genuine concurrent source creation is treated as registered while `SecurityException`, `ArgumentException` (such as 8-character log-name collisions), and `InvalidOperationException` failures populate `FailedSources` and emit a `Warning`.
4. Safely queries `Get-WinEvent -ListLog 'IcingaForWindows'`, applies the `104857600` byte (`100 MiB`) maximum log size when needed, and deterministically disposes the `EventLogConfiguration` (`IDisposable`) handle inside `finally`.

---

## 3. Runtime Flow

1. Caller imports `IcingaForWindows` once in the session (`Import-Module IcingaForWindows -Force -Global`) and runs `Install-IcingaForWindows -Hostname 'win-srv01.example.com'`.
2. If `-Hostname` is `$null`, `''`, or whitespace, `Install-IcingaForWindows` logs and returns `7000` (`InstallerHostnameMissing`).
3. `Install-IcingaForWindows` trims `-Hostname` and invokes `Set-InternalExitCodes` so `Public.ReturnCodes` is populated.
4. `New-ModuleConfigEnvironment` ensures `$env:ProgramData\IcingaForWindows\Binaries` and `$env:ProgramData\IcingaForWindows\Config` exist.
5. `Register-LoggingWindowsEventLog` registers every missing `IcingaForWindows::<Area>` source under the `IcingaForWindows` Windows Event Log via `[System.Diagnostics.EventLog]` and configures the `100 MiB` log size.
6. `New-IcingaProtocolCertificate -CommonName $Hostname` generates a 4096-bit RSA self-signed certificate and stores it in `Cert:\CurrentUser\My` (`50011` on Windows) or `$env:ProgramData\IcingaForWindows\Certificates\<Hostname>.pfx` (`50010` on Linux/macOS).
7. If certificate creation returns a failure code, `Install-IcingaForWindows` returns that code directly; otherwise it emits and returns `7001` (`InstallerCompleted`).

---

## 4. Verification Results

| Gate / Suite | Command | Result |
|--------------|---------|--------|
| Module Build + Docs + Memory Leaks + Code Style | `.\build\Build-ModuleProject.ps1 -SkipTests -GenerateDocs -TestDaemonMemoryLeaks -TestCodeStyling` | **Passed** (`43` public functions exported, `0` leak/style violations) |
| Compiled `lib/` SPDX & Encoding Check | `.\build\Test-ModuleCodeStyling.ps1 -Path .\lib\IcingaForWindows.Classes.ps1, .\lib\IcingaForWindows.Kernel.ps1` | **Passed** (`0` violations) |
| Strict Documentation & SPDX Gate | `.\build\Build-ModuleDocs.ps1 -Strict $true` | **Passed** (`199` functions documented across `20` Markdown files, `0` violations) |
| Changelog & Roadmap Governance Gate | `.\build\Test-ModuleChangelog.ps1` | **Passed** (`True`) |
| `PSScriptAnalyzer` Static Analysis | `.\build\Invoke-ScriptAnalysis.ps1 -FailOn 'Warning'` | **Passed** (`0` build-breaking warnings/errors) |
| Installer & Event Log Pester Suite | `.\build\Invoke-ModuleTests.ps1 -Path .\Tests\Install-IcingaForWindows.Tests.ps1` | **Passed** (`18 / 18` tests) |
| Class Literal Isolation Suite | `.\build\Invoke-ModuleTests.ps1 -Path .\Tests\ClassLiteral.Tests.ps1` | **Passed** (`3 / 3` tests) |
| Full Repository Pester Suite (macOS) | `Invoke-Pester` across `36` cross-platform test files | **`476 / 476` cross-platform tests passed** (`3` Windows-only test files -- `Get-IcingaDirectoryInformation.Tests.ps1`, `Get-IcingaPerformanceCounter.Tests.ps1`, and `MemoryLeak.Tests.ps1` -- require Windows APIs) |

---

## 5. Practical Examples

```powershell
Import-Module IcingaForWindows -Force -Global;

# Missing -Hostname returns 7000 (InstallerHostnameMissing) without interactive prompt
Install-IcingaForWindows;

# Base host installation (creates directories, registers Windows Event Log, creates self-signed certificate -> 7001)
Install-IcingaForWindows -Hostname 'win-srv01.example.com';

# Optional preview: inspect unified diff against Connection.json (-DryRun does NOT write changes to disk)
(
    New-IcingaProtocolEnvironment `
        -Endpoints @(
            (New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665),
            (New-IcingaProtocolEndpoint -Name 'icinga-master02.example.com' -Address 'icinga-master02.example.com' -Port 5665)
        ) `
        -Zone 'master' `
        -Hostname '$fqdn' `
        -TlsCertConfig (
            New-IcingaTlsCertConfig `
                -CertCN '$fqdn' `
                -CertStore 'My' `
                -CertStoreLocation 'CurrentUser' `
                -CertIssuer @( 'Icinga CA', '$fqdn' )
        ) `
        -DryRun
).Output;

# Persist configuration: run WITHOUT -DryRun and WITHOUT .Output to write Connection.json (returns 50019)
New-IcingaProtocolEnvironment `
    -Endpoints @(
        (New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665),
        (New-IcingaProtocolEndpoint -Name 'icinga-master02.example.com' -Address 'icinga-master02.example.com' -Port 5665)
    ) `
    -Zone 'master' `
    -Hostname '$fqdn' `
    -TlsCertConfig (
        New-IcingaTlsCertConfig `
            -CertCN '$fqdn' `
            -CertStore 'My' `
            -CertStoreLocation 'CurrentUser' `
            -CertIssuer @( 'Icinga CA', '$fqdn' )
    );

# Inspect registered Windows Event Log on Windows
Get-WinEvent -ListLog 'IcingaForWindows';
```

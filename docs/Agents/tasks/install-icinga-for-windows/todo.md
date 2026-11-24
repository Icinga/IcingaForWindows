# Task Checklist -- `Install-IcingaForWindows` & Event Log Wiring (`install-icinga-for-windows`)

## Implementation Tasks

- [x] Create feature branch `feature/install-icinga-for-windows` from `main` without committing changes.
- [x] Draft and maintain `docs/Agents/tasks/install-icinga-for-windows/implementation_plan.md`.
- [x] Add `InstallerHostnameMissing` (`7000`) and `InstallerCompleted` (`7001`) under `Area = 'Installer'` in `src/Core/ErrorHandling/Private/Set-InternalExitCodes.ps1`.
- [x] Create public `src/Core/Runtime/Public/Install-IcingaForWindows.ps1` with `-Hostname` return-code validation and trimming, `Set-InternalExitCodes`, `New-ModuleConfigEnvironment`, `Register-LoggingWindowsEventLog`, and `New-IcingaProtocolCertificate`.
- [x] Update `src/Core/Logging/Private/Register-LoggingWindowsEventLog.ps1` with Windows OS guard, guaranteed `IcingaForWindows::Logging` fallback source, case-insensitive deduplication, in-process `[System.Diagnostics.EventLog]::SourceExists` + `CreateEventSource` registration with `SourceExists` race verification, `EventLogConfiguration.Dispose()` cleanup, permission/registration-failure `Warning` diagnostics, and `.NOTES` documentation of the `Set-InternalExitCodes` caller precondition.
- [x] Update `src/Core/ErrorHandling/Private/Write-FunctionReturnValue.ps1` (`-Area $codeEntry['Area']`) and `src/Core/Logging/Private/Write-LoggingEntry.ps1` to declare `[string]$Area = $null`, invoke `Set-InternalExitCodes` unconditionally at function entry, and fall back (`# TODO`) to `EventLogGenericLog` (`'Logging'`) with a flat `'Logging'` guard when `-Area` or `EventLogGenericLog['Area']` is missing or blank.
- [x] Harden `src/Core/Logging/Private/Start-LoggingDaemon.ps1` with `OSType -eq 'Windows'` Event Log guard, `0..65535` `EventId` validation, `31839`-character truncation, non-fatal `EventLog.WriteEntry` error handling, and `try / finally` loop variable cleanup (`$LogObject.Data = $null` before `$LogObject = $null`).
- [x] Update `src/IcingaProtocol/Public/New-IcingaProtocolCertificate.ps1` with whitespace `-CommonName` validation and trimming, `Get-GlobalRuntimeVariable` OS detection, transient self-signed `X509Certificate2` / `RSA` disposal, and `Get-ModuleCertificateDirectory` creation on non-Windows hosts before writing `.pfx` files, and align comment-based help across `New-IcingaProtocolCertificate.ps1`, `Import-IcingaCertAuthority.ps1`, and `New-IcingaProtocolEnvironment.ps1` (`Cert:\CurrentUser\My`, `Cert:\LocalMachine\Root`, numeric return codes `50009`-`50019`, and `-DryRun` `@{ ExitCode; Output }` diff hashtables).
- [x] Expand `README.md` Quick Start & Base Setup with `Install-IcingaForWindows`, `Import-IcingaCertAuthority`, anonymized `New-IcingaProtocolEnvironment` + `New-IcingaTlsCertConfig` examples explicitly separating `-DryRun` diff preview (`(... -DryRun).Output`) from saving (`50019`), and Icinga 2 Object Name / `'$fqdn'` / `'$hostname'` explanations.
- [x] Create the complete step-by-step installation guide `docs/General/Installation.md`.
- [x] Add Pester unit test suite `Tests/Install-IcingaForWindows.Tests.ps1` (`18` tests including cold-state `Public.ReturnCodes = $null`, `Set-StrictMode -Version Latest`, CA import, signed certificate merge, and `-DryRun` vs. `50019` persistence).
- [x] Update `docs/General/Changelog.md` and synchronize `docs/General/Roadmap.md` (keeping `FunctionsToExport = '*'` in `IcingaForWindows.psd1` for dynamic `lib/` component loading and tracking standalone logging console output optimization).
- [x] Regenerate `lib/` and `docs/Icinga.*.md` / `docs/index.md` and run all style, documentation, memory-leak, changelog, `PSScriptAnalyzer`, and Pester gates.
- [x] Complete `docs/Agents/tasks/install-icinga-for-windows/walkthrough.md`.

## Open Follow-Up Tasks (Deferred to Subsequent PRs)

- [ ] **Logging Console Output & Standalone Rendering Optimization:** Redesign direct console log rendering and formatting when `Start-LoggingDaemon` is inactive during standalone CLI / `Install-IcingaForWindows` / `New-IcingaProtocolEnvironment` executions (`docs/General/Roadmap.md`).
- [ ] **Subsystem `Area` Metadata Completion (`# TODO`):** Assign explicit subsystem `Area` metadata across the remaining eight entries in `src/Core/ErrorHandling/Private/Set-InternalExitCodes.ps1` (`ConfigPresent`, `ConfigMissing`, `CommandNotFound`, `FileLockException`, `FileNotFound`, `DirectoryArgumentEmpty`, `DirectoryNotFound`, `ServiceNotInstalled`) and direct `Write-LoggingEntry` callers (`docs/General/Roadmap.md`).
- [ ] **Extended Installer & Service Hosting Capabilities:** Extend `Install-IcingaForWindows` with Icinga 2 endpoint/zone/CA/ticket onboarding, REST API setup, Windows Firewall rules, and native Windows service registration (`docs/General/Roadmap.md`).

## Known Limitations & Technical Debt

- **Live Windows Event Log & Local Certificate Store Integration:** Local development and unit tests executed on macOS (`arm64`); live Windows Registry Event Log source creation (`[System.Diagnostics.EventLog]::SourceExists` / `CreateEventSource`, `Get-WinEvent -ListLog 'IcingaForWindows'`) and `Cert:\CurrentUser\My` storage in `New-IcingaProtocolCertificate` require verification on an elevated Windows PowerShell 5.1 / PowerShell 7 host (and in GitHub Actions `windows-latest` CI).
- **Standalone Setup Output Prior to Daemon Startup:** Before `Start-LoggingDaemon` is started via `Use-IcingaForWindows -RunBackgroundDaemons`, standalone cmdlets return numeric status codes (`7001`, `50019`, ...) and enqueue structured log entries into `$Global:IcingaForWindows.Public.Logging.Queue` rather than printing formatted log lines directly to the console.

## Next Steps

1. Validate live `Install-IcingaForWindows`, `Import-IcingaCertAuthority`, `New-IcingaProtocolEnvironment`, and `Use-IcingaForWindows` execution on Windows PowerShell 5.1 and PowerShell 7.5+ (`windows-latest` CI and elevated Windows Server host).
2. Implement the planned Logging Console Output & Standalone Rendering Optimization in a dedicated follow-up branch.

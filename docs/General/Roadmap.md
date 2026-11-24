# Icinga for Windows Roadmap

## Overview

This document outlines the architectural roadmap for **Icinga for Windows** (`v27.0.0` and beyond). It tracks completed core subsystems, monitoring plugins, developer SDK capabilities, and prioritized upcoming engineering work in a single repository-level overview.

## Milestones

**Icinga for Windows** is continuously developed on the [`main` branch](https://github.com/Icinga/IcingaForWindows). Every feature, bugfix, security hardening, and refactoring pull request is recorded ahead of release in the [Icinga for Windows Changelog](Changelog.md), and detailed per-branch engineering plans are maintained under [`docs/Agents/tasks/`](../Agents/tasks/).

## Completed Milestones & Subsystems

The table below summarizes the foundational subsystems and milestones already delivered on the `27.0.0` architecture:

| Status | Subsystem / Milestone | Summary & Delivered Capabilities |
| ------ | --------------------- | -------------------------------- |
| Completed | Core Runtime, Threading, Logging & Error Handling | Synchronized `$Global:IcingaForWindows` state (`Public`, `Private`, `Protected`), runspace thread pool (`New-Thread`, `Start-ThreadHouseKeeper`), structured logging queue (`Write-LoggingEntry`), internal return-code registry (`Set-InternalExitCodes`), and AST daemon memory-leak verification (`build/Test-ModuleDaemonMemoryLeak.ps1`) |
| Completed | TLS TCP Stack, REST API, WebSocket & Access Control | TLS 1.2+ socket listener/client helpers, multi-worker HTTP REST API (`Start-RestApiDaemon`), persistent WebSocket reader/writer workers (`Start-ModuleWebSocketDaemon`), approved-path filesystem wrappers (`src/Security/`), and role-based access control |
| Completed | Unit Conversion & Threshold Evaluation Engine | SI/IEC unit conversion (`IcingaUnit`, `ConvertTo-IcingaUnit`), natural sorting (`IcingaSortKey`, `ConvertTo-IcingaSortedArray`), wildcard array filtering (`Test-IcingaArrayFilter`), and full Icinga range/percentage threshold evaluation (`IcingaThresholds`) |
| Completed | Background Performance Counter Subsystem | Dedicated `IcingaPerformanceCounter` daemon (`Start-IcingaPerformanceCounterDaemon`), category-level bulk snapshots, static AST counter discovery at startup, automatic inline fallback, and atomic `PerformanceCounter.json` caching |
| Completed | Unified Plugin Framework & Public Plugin SDK | Fluent `IcingaPlugin` check/container class, `IcingaCheckResult`, `IcingaError`, `Test-IcingaError`, `O(1)` active check command tracking, and the public `New-IcingaPlugin` SDK cmdlet |
| Completed | Core Monitoring Plugins & Icinga 2 Execution Pipeline | Nine core monitoring plugins (`CPU`, `Directory`, `Memory`, `PartitionSpace`, `PerfCounter`, `Process`, `ScheduledTask`, `Service`, `Uptime`), native Icinga 2 `event::ExecuteCommand` dispatch, approved `Binaries` external process/script execution with Job Object / process-group timeout cleanup, and `IWKB001000`-`IWKB001003` Knowledgebase articles |
| Completed | Holistic Code-Styling, SPDX Licensing & Governance | Zero-exemption code-styling enforcement across 250+ PowerShell files (`build/Test-ModuleCodeStyling.ps1`), mandatory `.NOTES` + `GPL-3.0-or-later` SPDX headers across source/build/test/manifest/`lib/` artifacts, non-`main` PR changelog enforcement (`build/Test-ModuleChangelog.ps1`), unified AI agent ruleset (`docs/Agents/guidelines/01-Instruction.md`), and English `README.md` architecture documentation |
| Completed | Automated PR Changelog Linking & Pre-Merge CI Gate | Zero-credential Pull Request changelog auto-updater (`build/Update-ModuleChangelog.ps1` with `-SyncHistory` backfill), two-stage pre-merge `[#<PR>](.../pull/<PR>)` enforcement in `build/Test-ModuleChangelog.ps1`, and ephemeral `GITHUB_TOKEN` auto-linking in `.github/workflows/ci.yml` ([`docs/Agents/tasks/changelog-pr-linking/`](../Agents/tasks/changelog-pr-linking/)) |
| Completed | Base `Install-IcingaForWindows` Entrypoint & Event Log Wiring | Public `Install-IcingaForWindows` cmdlet (`InstallerHostnameMissing` `7000`, `InstallerCompleted` `7001`), automatic `IcingaForWindows::<Area>` Windows Event Log source registration (`Register-LoggingWindowsEventLog`), dynamic `-Area` binding with `EventLogGenericLog` fallback in `Write-LoggingEntry`, initial node certificate provisioning, and step-by-step installation documentation ([`Installation.md`](Installation.md) · [`install-icinga-for-windows`](../Agents/tasks/install-icinga-for-windows/implementation_plan.md)) |

## Issue Triage & Prioritization

Opened issues, architectural tasks, and feature requests are triaged and prioritized according to operational impact:

* **Crash / Security:** Unhandled daemon exceptions, runspace deadlocks, memory/handle leaks, and security boundary issues receive top priority (`Priority 1`).
* **Bug / Enhancement:** Functional improvements, protocol extensions, tooling automation, and plugin migrations are scheduled into prioritized milestones (`Priority 2` - `Priority 4`).

## Feature List & Planned Work

The following table lists upcoming engineering tasks, architectural enhancements, and planned modules for **Icinga for Windows**.

> Note: Whenever an implementation plan under `docs/Agents/tasks/<BranchSlug>/implementation_plan.md` is created or completed, this table must be updated in the same branch.

| Priority\* | Scenario | Status / Task Plan | Description / Notes |
| ---------- | -------- | ------------------ | ------------------- |
| 1 | REST API Execution, Path Boundary & TLS Certificate Fixes | Planned | Integrate shared `ConvertTo-ModuleParameterValue` and `Invoke-ModulePowerShellCommand` helpers in `Invoke-RestApiCommandExecutionField`, mask and dispose `[securestring]` parameters, migrate REST JSON calls to `ConvertFrom-ModuleJson` / `ConvertTo-ModuleJson`, enforce canonical trailing-separator checks in `Test-SecureApprovedPath`, and fix premature `X509Certificate2` disposal in `Get-TlsCertificate` |
| 1 | Icinga Protocol Netstring Framing & Socket Concurrency | Planned | Replace character-based `StringBuilder` netstring slicing with UTF-8 byte-accurate framing in `Start-IcingaProtocolSocketReader` and `Read-IcingaRPCMessage`, pre-initialize per-endpoint `WriterQueue` before spawning socket writer/heartbeat threads, synchronize `Connections`, and harden disconnected-client guards |
| 1 | Pre-Compiled Native C# Helpers | Planned | Compile C# P/Invoke helpers (such as `DeviceIoControl` volume/disk-extent readers) into signed assemblies under `lib/` during `build/Build-ModuleProject.ps1` so runtime code never invokes `Add-Type -TypeDefinition` dynamically |
| 1 | Windows Service Hosting & Installer Packaging | In Progress (`Install-IcingaForWindows` base delivered) | Extend `Install-IcingaForWindows` with Icinga 2 endpoint/zone/ticket onboarding, native Windows service wrapper, MSI / bootstrap upgrade workflows, automatic Windows Firewall rule management, and configurable Windows service recovery policies |
| 2 | Just Enough Administration (JEA) & Least Privilege | Planned | Automated JEA session configuration compiler, managed least-privilege service account handling, and background SYSTEM task offloading for privileged checks |
| 2 | Metrics over Time (MoT) Background Daemon | Planned | Background time-series metric ring-buffer daemon and `-ThresholdInterval` support across monitoring plugins without blocking check execution |
| 2 | Icinga 2 DSL & Icinga Director Configuration Generator | Planned | Automated generation of Icinga 2 CheckCommand definitions and Icinga Director JSON baskets directly from plugin comment-based help and parameter metadata |
| 2 | Remaining Core Windows Monitoring Plugins | Planned | Migrate and modernize remaining Windows host checks onto `New-IcingaPlugin` (EventLog, X.509 Certificates, Network Adapter / Ping / Port, Time Sync / NTP, Windows Updates, Logged-On Users, Firewall, SMB / UNC Shares) |
| 2 | Logging Console Output & Standalone Rendering Optimization | Planned | Redesign direct console log rendering when `Start-LoggingDaemon` is inactive during standalone CLI and installer invocations, and assign explicit subsystem `Area` metadata across remaining `Set-InternalExitCodes` entries and direct `Write-LoggingEntry` callers |
| 3 | Interactive Management Console & Web UI | Planned | Guided CLI / TUI and local Web UI workflows for configuring `IcingaProtocol` endpoints, TLS certificates, REST API access roles, and live check testing |
| 4 | Enterprise Application Monitoring Modules | Planned | Dedicated extension plugin modules built on the public `New-IcingaPlugin` SDK for Microsoft SQL Server (MSSQL), Hyper-V, Windows Failover Clustering, Active Directory, IIS, and Exchange Server |

Feature Notes:

\* Feature Priorities:

1. Mandatory
2. Beneficial
3. Optional
4. Requires Sponsoring

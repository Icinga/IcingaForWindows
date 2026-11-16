# Implementation Walkthrough — Shared Helpers, IcingaProtocol Decomposition, Plugin SDK & Parity (`plugins-cpu-service-partition`)

## 1. Executive Summary

Delivered the modular decomposition of the Icinga 2 `event::ExecuteCommand` pipeline (`src/Tools/Private/` + `src/IcingaProtocol/Private/`), promoted `New-IcingaPlugin` to a public Plugin SDK cmdlet (`src/Plugins/Lib/Public/New-IcingaPlugin.ps1`), reduced `IcingaPlugin` `Get-PSCallStack` overhead from `O(N)` per node to `O(1)` per check execution via `Private.Icinga.ActiveCheckCommand`, hardened `PerformanceCounter` daemon concurrency and cache writes, and brought all nine core monitoring plugins to full legacy parity and edge-case safety. Deferred `RestApi`, `Test-SecureApprovedPath`, `Get-TlsCertificate`, `IcingaForWindows.psd1` static export sync, and `IcingaProtocol` socket/netstring transport items were documented in persistent task folders (`docs/Agents/tasks/fix-restapi-and-security/` and `docs/Agents/tasks/fix-icingaprotocol-transport/`) without touching any deferred source files.

---

## 2. Under-the-Hood Deep Dive

### 2.1 Zero-Duplication Shared Module Helpers (`src/Tools/Private/`)
- **`Get-ModuleObjectValue`:** Uniform, null-safe lookup across `Hashtable`, Windows PowerShell 5.1 `Dictionary[string, object]`, `OrderedDictionary`, and `PSCustomObject` with exact-key `O(1)` lookup first (`Contains` / `ContainsKey`) and `OrdinalIgnoreCase` fallback, preserving empty and single-element arrays via unary comma return.
- **`ConvertTo-ModuleOrderedDictionary`:** Normalizes dictionary and `PSCustomObject` payloads into an ordinal `OrderedDictionary` (`-SkipEmptyKeys` supported).
- **`Format-ModuleCommandLineArguments`:** Pure Windows `CommandLineToArgvW` argument quoter for CLI command rendering and `ProcessStartInfo.Arguments`.
- **`Get-ModuleCommandParameterMap` & `ConvertTo-ModuleParameterValue`:** Centralizes PowerShell parameter metadata lookup (excluding `CommonParameters` / `ShouldProcess`), alias resolution, positional ordering, typed coercion (`[bool]`, `[switch]`, numeric, enum, arrays, blank-skip on `[ValidateSet]` / `[ValidatePattern]`), and `[securestring]` conversion/tracking.
- **`Invoke-ModulePowerShellCommand`:** Unified `&` execution helper supporting both native `Invoke-IcingaCheck*` functions (`Private.Icinga.CheckResult`) and external `.ps1` scripts (`-UseLastExitCode` + Nagios `|` fallback) while deterministically resetting `Private.Icinga.CheckResult` and `Private.Icinga.ActiveCheckCommand` in `finally`.

### 2.2 Modular IcingaProtocol Execution Pipeline (`src/IcingaProtocol/Private/`)
- Extracted `Expand-IcingaProtocolMacroValue`, `Invoke-IcingaProtocolExternalScript`, `Stop-IcingaProtocolProcessTree`, and `Invoke-IcingaProtocolBinaryProcess`, reducing `ConvertFrom-IcingaProtocolMacros.ps1` and `Invoke-IcingaProtocolCheckCommand.ps1` to clean, single-responsibility orchestrators with 100% identical external behavior.
- `ConvertFrom-IcingaProtocolMacros` now skips empty `IList` (`[]`) and empty `IDictionary`/`PSCustomObject` (`{}`) alongside `""` and `$null` on unknown `ifw_api_arguments` parameters (`IWKB001001`).
- `Add-IcingaRPCMessageToWorker` retains `.Replace('"":"$",', '').Replace(',"":"$"', '')` for Windows PowerShell 5.1 `JavaScriptSerializer` safety and guards `if ($null -eq $RPCMessage)` after `ConvertFrom-ModuleJson`.

### 2.3 Public `New-IcingaPlugin` SDK, `O(1)` CallStack Caching & Plugin Parity
- **SDK Visibility:** Moved `New-IcingaPlugin.ps1` from `src/Plugins/Lib/Private/` to `src/Plugins/Lib/Public/` (`42` exported public functions) while keeping `Get-Icinga*` providers private.
- **`O(1)` CallStack Caching (`IcingaPlugin`):** `DetectCheckCommand()` checks `$GlobalVariable.Private.Icinga.ActiveCheckCommand` first and walks `Get-PSCallStack` only once when the first node of an `Invoke-IcingaCheck*` plugin is constructed, caching the resolved command name for all subsequent child/metric nodes (leaving `ActiveCheckCommand` untouched when called standalone outside a check command). `Compile()` resets `$GlobalVariable.Private.Icinga.ActiveCheckCommand = $null` in `finally` (backed up by `Invoke-ModulePowerShellCommand` and `Start-IcingaProtocolWorker`).
- **`Invoke-IcingaCheckCPU`:** Added `-Core` (`'*'`, `'_Total'`/`'Total'`, or core pattern), `-OverallOnly` (evaluates `-Warning`/`-Critical` only on `Overall Load` when `Overall Load` is present while preserving threshold evaluation on explicit single-core selectors), and `[Alias('SocketFilter')] -NodeFilter`.
- **`Invoke-IcingaCheckScheduledTask`:** Treats `LastTaskResult = 267009` (`0x41301`, when task `State` is `Running`) and `267011` (`0x41303`, `SCHED_S_TASK_HAS_NOT_RUN`) as `OK` by default, masks 32-bit HRESULTs with `0xFFFFFFFFL` (`0x80070005`) for `-IgnoreExitCodes`, and adds `[Alias('IgnoreLastResult', 'IgnoreExitCode')]` on `-IgnoreLastRunTime`.
- **`Invoke-IcingaCheckService`:** Changed `-Status` to `[IcingaServiceStatus[]]$Status = @( [IcingaServiceStatus]::Running )`, supporting single string `'Running'`, multi-status arrays `@('Running', 'Paused')` via `.CheckNotIn()`, and empty `@()` fallback without bitwise-OR enum corruption.
- **Additional Plugin & Provider Hardening:** Mutual `-IgnoreEmptyChecks` <-> `-MitigateUnknown` aliases (while keeping `[ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]` on `OverrideNotFound`/`OverrideNotOk` for Icinga Director dropdown DataLists and PowerShell auto-completion); `[WildcardPattern]` pre-validation (`DirectoryFilterInvalid`) in `Get-IcingaDirectoryInformation` (`-FileNames`); empty `Win32_ComputerSystem` and 0-byte pagefile guards in `Invoke-IcingaCheckMemory`; `-SkipPartitionMapping` on `Get-IcingaDiskInformation` (used by `Invoke-IcingaCheckPartitionSpace` while preserving `Get-IcingaDiskInformation -Entrypoint 'Volume'` standalone contract) and folder mount-point slash + trailing `\` normalization in `Invoke-IcingaCheckPartitionSpace` (keeping `@('')` fail-closed); and `InvariantCulture` formatting in `Invoke-IcingaCheckUptime`.

### 2.4 `PerformanceCounter` Daemon & Cache Safety
- `Start-IcingaPerformanceCounterDaemon` wraps each iteration in `try / catch / finally` and claims caller response queues atomically via `PendingRequests.TryRemove` with inner `try / catch` around `TryAdd` (while timed-out callers synchronize any in-flight `TryAdd` before calling `Dispose()`), preventing `BlockingCollection` disposal races.
- `Get-IcingaPerformanceCounter` validates paths via `IcingaPerformanceCounter::ParsePath` before recording timestamps in `Store.Registered`.
- `Write-IcingaPerformanceCounterCache` writes BOM-less UTF-8 (`[System.Text.UTF8Encoding]::new($false)`) inside `try / catch` logging warnings on I/O locks instead of throwing.

---

## 3. Verification Results

- **Module Build & Daemon Memory Leak Analysis (`.\build\Build-ModuleProject.ps1 -SkipTests -TestDaemonMemoryLeaks`):**
  - Compiled `42` public functions, `156` private functions, and `10` classes into `lib/IcingaForWindows.Classes.ps1` and `lib/IcingaForWindows.Kernel.ps1` with **`0` daemon memory leaks**.
- **Strict API Documentation (`.\build\Build-ModuleDocs.ps1 -Strict $true`):**
  - Parsed `198` functions across `20` Markdown files with **`0` documentation violations** (untouched CRLF-only `docs/Icinga.Core.*.md` files reset cleanly).
- **Code Styling, Class-Literal & Static Analysis:**
  - `Tests/CodeStyling.Tests.ps1` (`.\build\Test-ModuleCodeStyling.ps1`): **`0` violations** across all `99` target paths/directories.
  - `Tests/ClassLiteral.Tests.ps1`: **`3 / 3` passed** (`0` PowerShell class literals in functions).
  - `Invoke-ScriptAnalyzer -Settings .\PSScriptAnalyzerSettings.psd1` across all `33` new/modified `.ps1`/`.psm1` files: **`0` Error or Warning findings**.
- **Pester Test Suite (`.\Tests`):**
  - **`484 / 501` passed** (`100%` of cross-platform tests across `37` test files, including `17` new test blocks; the remaining `17` are pre-existing Windows-only OS calls on macOS: `WindowsIdentity::GetCurrent`, `System.Diagnostics.PerformanceCounter`, and `New-SelfSignedCertificate`).

# Implementation Plan — Icinga Protocol Check-Command Execution, Shared Helpers & Core Plugins (`plugins-cpu-service-partition`)

## 1. Problem Statement & Objectives

This branch delivers a modular, zero-duplication command execution pipeline for `event::ExecuteCommand` RPC frames alongside the public `New-IcingaPlugin` SDK, `O(1)` call-stack caching in `IcingaPlugin`, hardened `PerformanceCounter` daemon concurrency, and legacy-compatible monitoring plugins (`Invoke-IcingaCheckCPU`, `Invoke-IcingaCheckDirectory`, `Invoke-IcingaCheckMemory`, `Invoke-IcingaCheckPartitionSpace`, `Invoke-IcingaCheckPerfCounter`, `Invoke-IcingaCheckProcess`, `Invoke-IcingaCheckScheduledTask`, `Invoke-IcingaCheckService`, `Invoke-IcingaCheckUptime`):

1. **Shared Module Helpers (`src/Tools/Private/` — Zero Duplication):**
   - `Get-ModuleObjectValue`: Null-safe, case-insensitive lookup across `Hashtable`, PS 5.1 `Dictionary[string, object]`, `OrderedDictionary`, and `PSCustomObject` without array unrolling.
   - `ConvertTo-ModuleOrderedDictionary`: Ordinal `OrderedDictionary` normalizer with optional `-SkipEmptyKeys`.
   - `Format-ModuleCommandLineArguments`: Windows `CommandLineToArgvW` argument token quoter.
   - `Get-ModuleCommandParameterMap` & `ConvertTo-ModuleParameterValue`: Shared PowerShell parameter introspection (filtering `CommonParameters` / `ShouldProcess`), type coercion (`[bool]`, `[switch]`, numeric, enum, arrays, `[ValidateSet]` / `[ValidatePattern]` blank-skip), and `[securestring]` conversion/tracking.
   - `Invoke-ModulePowerShellCommand`: Unified in-process `&` runner reading `Private.Icinga.CheckResult`, supporting `-UseLastExitCode` and Nagios `|` fallback for `.ps1` scripts, and resetting `CheckResult` + `ActiveCheckCommand` in `finally`.
2. **Modular IcingaProtocol Execution Pipeline (`src/IcingaProtocol/Private/`):**
   - `Expand-IcingaProtocolMacroValue`, `Invoke-IcingaProtocolExternalScript`, `Stop-IcingaProtocolProcessTree`, and `Invoke-IcingaProtocolBinaryProcess` decompose `ConvertFrom-IcingaProtocolMacros` and `Invoke-IcingaProtocolCheckCommand` into focused single-responsibility functions.
   - Skips unset, `$null`, `""`, empty `IList` (`[]`), and empty `IDictionary`/`PSCustomObject` (`{}`) placeholders on unknown `ifw_api_arguments` parameters (`IWKB001001`).
   - Preserves PS 5.1 empty-key `"": "$"` stripping and adds a `$null -eq $RPCMessage` guard in `Add-IcingaRPCMessageToWorker`.
3. **Plugin SDK, `IcingaPlugin` `O(1)` CallStack Caching, Plugin Parity & `PerformanceCounter` Daemon Safety:**
   - Promotes `New-IcingaPlugin` to `src/Plugins/Lib/Public/New-IcingaPlugin.ps1` as the public SDK factory for custom/external plugin repositories (keeping `Get-Icinga*` providers in `Private/`).
   - Caches `Get-PSCallStack` command detection in `$GlobalVariable.Private.Icinga.ActiveCheckCommand` (`O(1)` per check execution regardless of node count or creation order, cleared in `Compile()`, `Invoke-ModulePowerShellCommand`, and `Start-IcingaProtocolWorker`).
   - Full legacy parity on `Invoke-IcingaCheckCPU` (`-Core`, `-OverallOnly`, `-NodeFilter` with `[Alias('SocketFilter')]`), `Invoke-IcingaCheckScheduledTask` (`267009` on `Running` tasks & `267011` treated as `OK`, 32-bit `0xFFFFFFFFL` HRESULT hex masking for `-IgnoreExitCodes`, `[Alias('IgnoreLastResult', 'IgnoreExitCode')]`), and `Invoke-IcingaCheckService` (`[IcingaServiceStatus[]]$Status` multi-status array + single-string compatibility).
   - Mutual `-IgnoreEmptyChecks` <-> `-MitigateUnknown` aliases, `Get-IcingaDirectoryInformation` `[WildcardPattern]` validation, `Invoke-IcingaCheckMemory` empty-CIM & 0-byte pagefile guards, `Get-IcingaDiskInformation -SkipPartitionMapping` + `Invoke-IcingaCheckPartitionSpace` trailing `\` mount-point matching, and `InvariantCulture` formatting in `Invoke-IcingaCheckUptime`.
   - `PerformanceCounter` daemon loop `try / catch / finally` resilience, atomic `PendingRequests.TryRemove` timeout disposal protection, `ParsePath` check before `Registered` insertion, and BOM-less UTF-8 `try / catch` cache persistence.

---

## 2. Proposed File Changes

### Shared Tools & Runtime State
- **[MODIFY]** `IcingaForWindows.psm1` (`Get-ModuleBinaryDirectory` & `Private.Icinga.ActiveCheckCommand`)
- **[MODIFY]** `src/Classes/Icinga/IcingaPlugin.ps1` (`O(1)` `ActiveCheckCommand` caching & `Compile()` reset)
- **[NEW]** `src/Tools/Private/Get-ModuleObjectValue.ps1`
- **[NEW]** `src/Tools/Private/ConvertTo-ModuleOrderedDictionary.ps1`
- **[NEW]** `src/Tools/Private/Format-ModuleCommandLineArguments.ps1`
- **[NEW]** `src/Tools/Private/Get-ModuleCommandParameterMap.ps1`
- **[NEW]** `src/Tools/Private/ConvertTo-ModuleParameterValue.ps1`
- **[NEW]** `src/Tools/Private/Invoke-ModulePowerShellCommand.ps1`
- **[NEW]** `src/Tools/Private/ConvertTo-ModuleSecureString.ps1` & `ConvertFrom-ModuleBoolean.ps1`
- **[MODIFY]** `src/Tools/Public/Get-IcingaUnixTime.ps1`

### IcingaProtocol Execution Pipeline
- **[NEW]** `src/IcingaProtocol/Private/Resolve-IcingaProtocolCommand.ps1`
- **[NEW]** `src/IcingaProtocol/Private/Expand-IcingaProtocolMacroValue.ps1`
- **[NEW]** `src/IcingaProtocol/Private/ConvertFrom-IcingaProtocolMacros.ps1`
- **[NEW]** `src/IcingaProtocol/Private/Split-IcingaBinaryPluginOutput.ps1`
- **[NEW]** `src/IcingaProtocol/Private/Invoke-IcingaProtocolExternalScript.ps1`
- **[NEW]** `src/IcingaProtocol/Private/Stop-IcingaProtocolProcessTree.ps1`
- **[NEW]** `src/IcingaProtocol/Private/Invoke-IcingaProtocolBinaryProcess.ps1`
- **[NEW]** `src/IcingaProtocol/Private/Invoke-IcingaProtocolCheckCommand.ps1`
- **[MODIFY]** `src/IcingaProtocol/Private/Start-IcingaProtocolWorker.ps1` & `Add-IcingaRPCMessageToWorker.ps1`

### Plugins, Providers & PerformanceCounter
- **[MOVE]** `src/Plugins/Lib/Private/New-IcingaPlugin.ps1` -> `src/Plugins/Lib/Public/New-IcingaPlugin.ps1`
- **[MODIFY]** `src/Plugins/Provider/Disk/Private/Get-IcingaDiskInformation.ps1` & `src/Plugins/Provider/FileSystem/Private/Get-IcingaDirectoryInformation.ps1`
- **[MODIFY]** `src/Plugins/Checks/Public/Invoke-IcingaCheck{CPU,Memory,PartitionSpace,PerfCounter,ScheduledTask,Service,Uptime}.ps1`
- **[MODIFY]** `src/PerformanceCounter/Private/{Start-IcingaPerformanceCounterDaemon,Write-IcingaPerformanceCounterCache}.ps1` & `src/PerformanceCounter/Public/Get-IcingaPerformanceCounter.ps1`

### Deferred Follow-Up Branch Plans (Unmodified Source on This Branch)
- **[NEW]** `docs/Agents/tasks/fix-restapi-and-security/{implementation_plan,todo}.md`
- **[NEW]** `docs/Agents/tasks/fix-icingaprotocol-transport/{implementation_plan,todo}.md`

---

## 3. Verification Plan

1. Compile `lib/` with daemon memory-leak checks (`.\build\Build-ModuleProject.ps1 -SkipTests -TestDaemonMemoryLeaks`) and regenerate docs (`.\build\Build-ModuleDocs.ps1 -Strict $true`).
2. Validate code styling (`.\build\Test-ModuleCodeStyling.ps1`), class-literal rules (`Tests/ClassLiteral.Tests.ps1`), and `Invoke-ScriptAnalyzer` (`0` violations).
3. Run all Pester 6.1.0 unit test suites across helpers, protocol execution, plugins, providers, and `PerformanceCounter`.

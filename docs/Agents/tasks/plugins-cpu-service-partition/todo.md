# Task Checklist — `plugins-cpu-service-partition`

## Completed Tasks

- [x] **Shared Module Helpers (`src/Tools/Private/`)**
  - Created `Get-ModuleObjectValue.ps1`, `ConvertTo-ModuleOrderedDictionary.ps1`, `Format-ModuleCommandLineArguments.ps1`, `Get-ModuleCommandParameterMap.ps1`, `ConvertTo-ModuleParameterValue.ps1`, `Invoke-ModulePowerShellCommand.ps1`, `ConvertTo-ModuleSecureString.ps1`, and `ConvertFrom-ModuleBoolean.ps1`.
- [x] **Modular IcingaProtocol Execution Pipeline (`src/IcingaProtocol/Private/`)**
  - Created `Resolve-IcingaProtocolCommand.ps1`, `Expand-IcingaProtocolMacroValue.ps1`, `ConvertFrom-IcingaProtocolMacros.ps1`, `Split-IcingaBinaryPluginOutput.ps1`, `Invoke-IcingaProtocolExternalScript.ps1`, `Stop-IcingaProtocolProcessTree.ps1`, `Invoke-IcingaProtocolBinaryProcess.ps1`, and `Invoke-IcingaProtocolCheckCommand.ps1`.
  - Updated `Start-IcingaProtocolWorker.ps1` (`Get-ModuleObjectValue`, monotonic `Stopwatch` timing, `ActiveCheckCommand` reset in `finally`) and `Add-IcingaRPCMessageToWorker.ps1` (retained PS 5.1 empty-key `"": "$"` stripping + added `$null -eq $RPCMessage` guard).
  - Updated `ConvertFrom-IcingaProtocolMacros.ps1` to skip empty `IList` (`[]`) and empty `IDictionary`/`PSCustomObject` (`{}`) alongside `""` on unknown `ifw_api_arguments` parameters (`IWKB001001`).
- [x] **Plugin SDK, `O(1)` CallStack Caching & Core Plugin Parity**
  - Promoted `src/Plugins/Lib/Private/New-IcingaPlugin.ps1` -> `src/Plugins/Lib/Public/New-IcingaPlugin.ps1` (keeping `Get-Icinga*` providers in `Private/`).
  - Implemented `O(1)` `Get-PSCallStack` caching in `IcingaPlugin.ps1` via `$GlobalVariable.Private.Icinga.ActiveCheckCommand` with deterministic reset in `Compile()` `finally`, `Invoke-ModulePowerShellCommand`, and `Start-IcingaProtocolWorker`.
  - Added legacy parity to `Invoke-IcingaCheckCPU.ps1` (`-Core`, `-OverallOnly`, `[Alias('SocketFilter')] -NodeFilter`), `Invoke-IcingaCheckScheduledTask.ps1` (`267009` on `Running` tasks & `267011` as `OK`, `0xFFFFFFFFL` HRESULT hex masking, `[Alias('IgnoreLastResult', 'IgnoreExitCode')]`), and `Invoke-IcingaCheckService.ps1` (`[IcingaServiceStatus[]]$Status` multi-status array + single-string compatibility).
  - Hardened `Get-IcingaDirectoryInformation.ps1`, `Get-IcingaDiskInformation.ps1` (`-SkipPartitionMapping`), `Invoke-IcingaCheckMemory.ps1`, `Invoke-IcingaCheckPartitionSpace.ps1`, `Invoke-IcingaCheckPerfCounter.ps1`, and `Invoke-IcingaCheckUptime.ps1`.
- [x] **`PerformanceCounter` Daemon Concurrency & Cache Safety**
  - Wrapped `Start-IcingaPerformanceCounterDaemon.ps1` loop in `try / catch / finally` and coordinated `PendingRequests` handoff via atomic `TryRemove` + `ObjectDisposedException` safety.
  - Validated counter paths via `ParsePath` before adding to `Store.Registered` in `Get-IcingaPerformanceCounter.ps1`.
  - Guarded `Write-IcingaPerformanceCounterCache.ps1` with `try / catch` and BOM-less UTF-8 `[System.IO.File]::WriteAllText`.
- [x] **Documentation, Tests & Follow-Up Task Tracking**
  - Regenerated `docs/Icinga.*.md` (`198` functions, `0` violations) and updated `docs/Developer/Plugins/{02-IcingaPlugin-Reference,04-Custom-Plugin-Developer-Guide}.md` + `docs/Developer/IcingaProtocol/01-Check-and-Binary-Execution.md`.
  - Added `Tests/ModuleToolsHelpers.Tests.ps1` and expanded `15` existing Pester test suites; validated `0` violations in `Test-ModuleCodeStyling.ps1`, `Invoke-ScriptAnalyzer`, `ClassLiteral.Tests.ps1`, and `Test-ModuleDaemonMemoryLeak.ps1`.
  - Created persistent follow-up plans under `docs/Agents/tasks/fix-restapi-and-security/` and `docs/Agents/tasks/fix-icingaprotocol-transport/`.
- [x] **Live Windows PowerShell 5.1 Daemon & Icinga 2 End-to-End Verification**
  - Verified live daemon and check execution under Windows PowerShell 5.1 against Icinga 2 (`event::ExecuteCommand` checks running cleanly end-to-end).

---

## Follow-Up Branches After Merge to `main`

- [ ] **RestApi, Security & Manifest Follow-Up (`docs/Agents/tasks/fix-restapi-and-security/`):**
  Implement shared helper integration in `RestApi`, boundary normalization in `Test-SecureApprovedPath.ps1`, certificate disposal fix in `Get-TlsCertificate.ps1`, and optional static `FunctionsToExport` sync in `IcingaForWindows.psd1`.
- [ ] **IcingaProtocol Socket & Netstring Transport Follow-Up (`docs/Agents/tasks/fix-icingaprotocol-transport/`):**
  Implement UTF-8 byte-accurate netstring framing, `WriterQueue` startup synchronization, thread-safe `Connections` tracking, and cluster lifecycle handlers in a dedicated branch.

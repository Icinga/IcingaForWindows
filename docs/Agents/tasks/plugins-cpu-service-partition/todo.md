# Task Checklist — `plugins-cpu-service-partition`

## Completed Tasks

- [x] **Core Plugins & Providers Layout (Committed Earlier on Branch)**
  - Structured `src/Plugins/Checks/Public/` (`Invoke-IcingaCheckCPU`, `Invoke-IcingaCheckDirectory`, `Invoke-IcingaCheckMemory`, `Invoke-IcingaCheckPartitionSpace`, `Invoke-IcingaCheckPerfCounter`, `Invoke-IcingaCheckProcess`, `Invoke-IcingaCheckScheduledTask`, `Invoke-IcingaCheckService`, `Invoke-IcingaCheckUptime`), `src/Plugins/Lib/`, and `src/Plugins/Provider/`.
- [x] **Environment, Security & Type Conversion Helpers**
  - Added `Get-ModuleBinaryDirectory()` with full comment-based help in `IcingaForWindows.psm1`.
  - Updated `src/Config/Private/New-ModuleConfigEnvironment.ps1` to create the `Binaries` directory on startup and aligned `.DESCRIPTION`/`.OUTPUTS` (`System.Int32`).
  - Added `(Get-ModuleBinaryDirectory)` to `src/Security/Private/Get-SecureChildItem.ps1`, cached `$AccessCheck` to prevent duplicate `Test-SecureApprovedPath` evaluations, formatted `{0}` in debug logs, and aligned `.OUTPUTS`.
  - Fixed local timezone offset in `src/Tools/Public/Get-IcingaUnixTime.ps1` using `[System.DateTimeOffset]::UtcNow`.
  - Implemented `src/Tools/Private/ConvertTo-ModuleSecureString.ps1` (`AppendChar` + `MakeReadOnly`, `0` `PSScriptAnalyzer` errors, emitting `SecureStringConversionFailed` via `Write-FunctionReturnValue` and returning `$null` without throwing) and `src/Tools/Private/ConvertFrom-ModuleBoolean.ps1`.
  - Registered internal return codes `4004` (`SecureStringConversionFailed`) and `50020`–`50025` in `src/Core/ErrorHandling/Private/Set-InternalExitCodes.ps1` (aligned `50024` wording to non-empty value).
- [x] **IcingaProtocol Command Resolution, Macro Parser & Check Runner**
  - Implemented `src/IcingaProtocol/Private/Resolve-IcingaProtocolCommand.ps1` (mandatory `ifw_api_command`, control-character / cross-platform invalid character / drive-relative / NTFS ADS colon / pre-`GetFullPath` wildcard rejection, dotted base-name probing, shorthand expansion, strict `Binaries` boundary check without `$env:PATH`).
  - Implemented `src/IcingaProtocol/Private/ConvertFrom-IcingaProtocolMacros.ps1` (ordinal `OrderedDictionary` preserving `-p` vs `-P` with non-null case-insensitive fallback, empty `""` macro-key filtering, serialized `"value": null` flag handling, empty-string skip on unknown parameters for `IWKB001001`, typed value-array coercion, `SecureString` masking & exception cleanup, PS 5.1 `Dictionary` + PS 7 `Hashtable` + `PSCustomObject` support).
  - Implemented `src/IcingaProtocol/Private/Split-IcingaBinaryPluginOutput.ps1` (single/multi-line Nagios/Icinga `|` perfdata splitter supporting quoted, scoped `pkg::'Label'=val`, and doubled-quote labels).
  - Implemented `src/IcingaProtocol/Private/Invoke-IcingaProtocolCheckCommand.ps1` (in-process `&` execution without custom timeout for `Invoke-IcingaCheck*` and `.ps1` scripts in `Binaries` including `New-IcingaPlugin` support unaffected by inner `$LASTEXITCODE`, named/colon-bound/positional `[securestring]` `CommandLine` masking, and non-trailing valueless flag guards; `System.Diagnostics.Process` execution for `.exe`/`.cmd`/`.bat`/`.com` with `.cmd`/`.bat` metacharacter & `%...%` substitution protection, clamped `check_timeout`, and deterministic multi-pass kill-first descendant process-tree termination via `Win32_Process` on Windows and `Kill($true)` + `pgrep -P` on Unix).
  - Integrated monotonic `Stopwatch` timing, Host check support (`'service'` omitted when empty), `'check_source'` fallback, and dictionary-safe RPC access in `src/IcingaProtocol/Private/Start-IcingaProtocolWorker.ps1`.
- [x] **Knowledgebase (`IWKB001000`–`IWKB001003`) & Developer Documentation**
  - Created and aligned `docs/Developer/IcingaProtocol/01-Check-and-Binary-Execution.md`.
  - Created and aligned `docs/Knowledgebase/index.md` and `IWKB001000.md` through `IWKB001003.md`.
  - Regenerated API reference docs (`docs/Icinga.*.md`) with `0` documentation violations.
- [x] **Automated Unit & Static-Analysis Tests**
  - Added cross-platform `Join-Path` tests across `Tests/ConvertTo-ModuleSecureString.Tests.ps1`, `Tests/ConvertFrom-ModuleBoolean.Tests.ps1`, `Tests/Resolve-IcingaProtocolCommand.Tests.ps1`, `Tests/ConvertFrom-IcingaProtocolMacros.Tests.ps1`, and `Tests/Invoke-IcingaProtocolCheckCommand.Tests.ps1` (including Windows `check_bgpipe.cmd` without `>nul`).
  - Verified `0` violations across all `88` target files in `Tests/CodeStyling.Tests.ps1` (`build/Test-ModuleCodeStyling.ps1 -Path ...`), `Invoke-ScriptAnalyzer` (`PSScriptAnalyzerSettings.psd1`), `Tests/ClassLiteral.Tests.ps1`, and `build/Test-ModuleDaemonMemoryLeak.ps1`.

---

## Open Points & Known Limitations

- [ ] **Live Windows Agent End-to-End Verification against Icinga 2 Master / Director:**
  Unit and process-level tests run offline against mocked `Get-ModuleBinaryDirectory()` paths; live TLS JSON-RPC verification with an Icinga 2 master (`ifw-api` active/inactive and `check_load.exe` in `C:\ProgramData\IcingaForWindows\Binaries`) should be executed on a Windows test host.
- [ ] **Windows PowerShell 5.1 Native Runtime Pass:**
  Static checks (`ClassLiteral.Tests.ps1`, `Test-ModuleCodeStyling.ps1`, `Dictionary[string, object]` unit tests, empty-string `SecureString` guards) cover PS 5.1 constraints, and CI / Windows verification should confirm runtime execution under `powershell.exe` 5.1.
- [ ] **Remaining Monitoring Check Plugins (Future Branches):**
  Additional plugins from the legacy plugin catalog (network interfaces, certificates, event logs, updates, HTTP/ICMP checks) remain scheduled for subsequent feature branches.

---

## Next Steps

1. Stage and commit the `feature/plugins-cpu-service-partition` files cleanly (keeping `update-code-styling` files unstaged for the follow-up branch).
2. Run live Windows verification against an Icinga 2 master with both PowerShell checks and external binaries in `C:\ProgramData\IcingaForWindows\Binaries`.

# Icinga for Windows Changelog

**The latest release announcements are available on [https://icinga.com/blog/](https://icinga.com/blog/).**

Please review the [Architecture & Developer Documentation](../Developer/) and [Roadmap](Roadmap.md) for details on subsystem design and upcoming milestones.

Released closed milestones can be found on [GitHub](https://github.com/Icinga/IcingaForWindows/milestones?state=closed).

## 27.0.0 (Unreleased)

[Issues and PRs](https://github.com/Icinga/IcingaForWindows/milestones)

### Enhancements

* Enforces zero-exemption PowerShell code-styling compliance, mandatory `.NOTES` sections with Icinga GmbH `GPL-3.0-or-later` SPDX license headers across all source, build, bootstrap, manifest, test, and compiled `lib/` files, automated PR changelog validation (`build/Test-ModuleChangelog.ps1`), `docs/General/Changelog.md` and `docs/General/Roadmap.md` governance, and an updated English `README.md` with Mermaid architecture diagrams (`feature/update-code-styling`)
* Adds nine core monitoring plugins (`Invoke-IcingaCheckCPU`, `Invoke-IcingaCheckDirectory`, `Invoke-IcingaCheckMemory`, `Invoke-IcingaCheckPartitionSpace`, `Invoke-IcingaCheckPerfCounter`, `Invoke-IcingaCheckProcess`, `Invoke-IcingaCheckScheduledTask`, `Invoke-IcingaCheckService`, `Invoke-IcingaCheckUptime`), promotes `New-IcingaPlugin` to a public Plugin SDK cmdlet, and introduces the modular Icinga 2 `event::ExecuteCommand` PowerShell and external binary execution pipeline (`3f7fa6e`)
* Adds the unified `IcingaPlugin` fluent check and package evaluation framework along with `IcingaCheckResult`, `IcingaError`, and `Test-IcingaError` (`be19ae1`)
* Adds the background `IcingaPerformanceCounter` daemon, category snapshot reader, static AST counter discovery, and persistent counter cache (`7e576b1`)
* [#18](https://github.com/Icinga/IcingaForWindows/pull/18) Adds the `IcingaThresholds` evaluation engine supporting Icinga range syntax, units, and percentage thresholds
* [#17](https://github.com/Icinga/IcingaForWindows/pull/17) Adds `IcingaUnit` and `ConvertTo-IcingaUnit` for SI and IEC unit conversion
* [#16](https://github.com/Icinga/IcingaForWindows/pull/16) Enhances `IcingaProtocol` stability, certificate handling, automatic module loading in `Build-ModuleProject.ps1`, and REST API thread inspection endpoints
* [#14](https://github.com/Icinga/IcingaForWindows/pull/14) Adds AST-based daemon endless-loop and `IDisposable` memory-leak detection (`build/Test-ModuleDaemonMemoryLeak.ps1`)
* [#4](https://github.com/Icinga/IcingaForWindows/pull/4) Adds configuration content diffing (`Compare-IcingaTextContent`) and native automation support
* [#3](https://github.com/Icinga/IcingaForWindows/pull/3) Introduces the GitHub Actions CI pipeline for module compilation, strict API documentation generation, `PSScriptAnalyzer`, daemon memory-leak checks, and Pester unit testing
* [#1](https://github.com/Icinga/IcingaForWindows/pull/1) Introduces the synchronized `$Global:IcingaForWindows` runtime architecture, runspace thread pool, structured logging daemon, TLS TCP stack, REST API, WebSocket client layer, and role-based access control

### Bugfixes

* Fixes Windows PowerShell 5.1 `lib/IcingaForWindows.Kernel.ps1` parser errors and Mojibake when dot-sourcing BOM-less UTF-8 artifacts by enforcing strict 7-bit ASCII across all PowerShell source, build, test, and compiled `lib/` files, deterministic file sorting and SMB-safe reading in `build/Build-ModuleProject.ps1`, and UNC `ProviderPath` normalization across build and test scripts (`feature/update-code-styling`)
* Fixes infinite exception loop in `Start-IcingaProtocolSocketWriter` when `WriterQueue` is disposed while the writer thread is still active (`c678e4f`)
* [#15](https://github.com/Icinga/IcingaForWindows/pull/15) [#13](https://github.com/Icinga/IcingaForWindows/pull/13) [#10](https://github.com/Icinga/IcingaForWindows/pull/10) [#7](https://github.com/Icinga/IcingaForWindows/pull/7) [#6](https://github.com/Icinga/IcingaForWindows/pull/6) Fixes memory leaks, file locks, and garbage-collection pressure across logging, worker queues, and compiled module loading
* [#12](https://github.com/Icinga/IcingaForWindows/pull/12) [#9](https://github.com/Icinga/IcingaForWindows/pull/9) Fixes `Start-ThreadHouseKeeper` lifecycle handling so completed and unresponsive threads are cleanly recycled
* [#11](https://github.com/Icinga/IcingaForWindows/pull/11) Fixes TCP client connection status verification and ensures `Open-SSLStream` closes the socket when an endpoint handshake fails
* [#8](https://github.com/Icinga/IcingaForWindows/pull/8) Fixes potential freezes on file locks by bounding secure file read and write retries

### Security

* Restricts external check binary and `.ps1` script execution in `Resolve-IcingaProtocolCommand` and `Invoke-IcingaProtocolCheckCommand` strictly to the approved `Get-ModuleBinaryDirectory` path (`$env:ProgramData\IcingaForWindows\Binaries`), rejecting path traversal, Alternate Data Streams, and arbitrary PowerShell cmdlet invocation (`IWKB001003`)
* Masks `[securestring]` check arguments as `'********'` in debug telemetry, passes secrets in-memory to PowerShell check plugins, and deterministically disposes temporary `SecureString` instances after execution

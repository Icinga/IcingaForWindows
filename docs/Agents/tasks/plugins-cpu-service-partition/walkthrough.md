# Implementation Walkthrough — Icinga Protocol Check-Command & Binary Execution (`plugins-cpu-service-partition`)

## 1. Executive Summary

Implemented the end-to-end check-command and external binary execution pipeline for the native Icinga 2 JSON-RPC protocol (`event::ExecuteCommand`) alongside the new v2 `IWKB001000`–`IWKB001003` Knowledgebase and developer documentation. PowerShell check plugins (`Invoke-IcingaCheck*` and shorthands such as `"cpu"`) and isolated external binaries/scripts inside `C:\ProgramData\IcingaForWindows\Binaries` now execute deterministically across both Icinga 2 macro delivery modes (`ifw-api` active and fallback custom variables), with `SecureString` conversion/masking/disposal, UTC-accurate execution timing, Nagios/Icinga `|` perfdata splitting, and zero runspace class-literal leaks.

---

## 2. Under-the-Hood Deep Dive

### 2.1 Strict Command Resolution (`Resolve-IcingaProtocolCommand`)
- Reads `macros.ifw_api_command` exclusively; `params.command` is never guessed as an executable so unmodified ITL commands (such as `load-windows` sending an empty `macros` block) immediately return `[UNKNOWN]` (`3`) with `IWKB001003`.
- Rejects ASCII control characters (`0x00..0x1F`), drive-relative paths (`C:evil.exe`), and NTFS Alternate Data Stream colons (`check_load.exe:stream`). Normalizes candidate paths via `[System.IO.Path]::GetFullPath(...)` and enforces a strict trailing-separator boundary check against `Get-ModuleBinaryDirectory()` (`C:\ProgramData\IcingaForWindows\Binaries`), defeating parent traversal (`..\`), sibling-prefix tricks (`BinariesEvil\`), UNC paths, and drive-root escapes across Windows and Unix test environments.
- Never queries `$env:PATH` for binaries or scripts; probes `.exe`, `.cmd`, `.bat`, `.com`, and `.ps1` exclusively inside `Get-ModuleBinaryDirectory()` (including dotted base names such as `check_app_v1.2`).
- Expands extensionless shorthands (`"cpu"` -> `Invoke-IcingaCheckCPU`, `"IcingaCheckDirectory"` -> `Invoke-IcingaCheckDirectory`) only when no matching file exists in `Binaries`, while blocking wildcard characters and non-check cmdlets (`Remove-Item`, `Get-Process`).

### 2.2 Dual-Mode Macro Parsing & Type Coercion (`ConvertFrom-IcingaProtocolMacros`)
- Normalizes `IDictionary` and `PSCustomObject` inputs into an ordinal `OrderedDictionary` (`[System.StringComparer]::Ordinal`) paired with a case-insensitive fallback table, preserving case-distinct CLI flags (`-p` vs `-P`, `-c` vs `-C`) while guaranteeing identical behavior for Windows PowerShell 5.1 (`Dictionary[string, object]`) and PowerShell 7+ (`Hashtable`). Empty/whitespace macro keys (`""`) are skipped up front.
- **Mode A (`ifw-api` active):** Resolves single (`$Var$`) and single-pass embedded (`http://$address$:$port$`) macro references while preserving literal Windows `$` identifiers (`C$`, `MSSQL$SQLEXPRESS`) and unescaping Icinga 2 `$$` sequences; supports both omitted `value` and Icinga 2 serialized `"value": null` valueless flags on binaries and PowerShell `[switch]` parameters; evaluates `set_if` via `ConvertFrom-ModuleBoolean`; skips unset, `null`, and empty `""` optional template placeholders; validates non-empty PowerShell parameters against `(Get-Command).Parameters` (`IWKB001001` on unknown parameters); skips empty strings on array, numeric, enum, and `[ValidateSet]` parameters so plugin defaults remain intact; coerces typed numeric/boolean array elements; and orders binary flags by `InvariantCulture` float/integer `order` with `skip_key` and `repeat_key`.
- **Mode B (`ifw-api` inactive):** Ignores `ifw_api_*`, `IcingaPowerShellBase_*`, and empty `""` keys, maps PowerShell parameters by exact name/alias or `IcingaCheck<Name>_<Type>_<Param>` (`IWKB001000` on unmapped custom variables), and restricts binary fallback variables to `-`/`/` prefixed flags (`IWKB001002` otherwise).
- Converts `[securestring]` parameters via `ConvertTo-ModuleSecureString` (`AppendChar` + `MakeReadOnly`, handling empty strings safely on PS 5.1 without `ConvertTo-SecureString -AsPlainText` and emitting `SecureStringConversionFailed` via `Write-FunctionReturnValue` without throwing), masks secrets as `'********'` in `CommandLine` (`cr.command`), returns a structured `[UNKNOWN]` (`3`) result on conversion failure, and disposes allocated instances on both normal completion and unexpected coercion exceptions.

### 2.3 Isolated Execution, Descendant Tree Termination & Timing (`Invoke-IcingaProtocolCheckCommand` & `Start-IcingaProtocolWorker`)
- **PowerShell check plugins & external `.ps1` scripts in `Binaries`:** Run natively in-process via `&` (never dot-sourced) with `Protected.IsBackgroundDaemon = $true` and no custom timeout wrapper (relying on `Start-ThreadHouseKeeper`). External `.ps1` scripts introspect `ExternalScript` parameter metadata, coercing `[bool]`, `[switch]` (including explicit boolean tokens and `-Flag:$val` colon syntax), arrays (respecting adjacent flag boundaries such as `-Targets -UseSsl False`), numeric/enum/`[ValidateSet]` optional empty strings, and named, colon-bound (`-Secret:val`), or positional `[securestring]` parameters (masking secrets as `'********'` or `-Secret:********` in `CommandLine`), rejecting valueless non-switch flags with `[UNKNOWN]`, supporting `New-IcingaPlugin ... .Compile()` via `Private.Icinga.CheckResult` without stale `$LASTEXITCODE` interference, and disposing temporary `SecureString` instances in `finally`.
- **Native executables & batch scripts (`.exe`, `.cmd`, `.bat`, `.com`):** Execute via `System.Diagnostics.Process` with `UseShellExecute = $false`, full canonical path in `Binaries`, `CommandLineToArgvW` quoting, pre-launch `.cmd`/`.bat` `cmd.exe` metacharacter validation (`&`, `|`, `<`, `>`, `^`, `\r`, `\n`, `"`, `!`, and any paired `%...%` substitution token), asynchronous stdout/stderr reads (`stderr` fallback when `stdout` is blank), clamped `check_timeout` (`60s` default), deterministic descendant process-tree termination in both process-hang and background-pipe timeout branches (root-first kill while `$Process` handle remains open + multi-pass `Win32_Process` `ParentProcessId` BFS + immediate descendant kill + `.WaitForExit(2000)` + stream drain + `.Dispose()` on Windows; `pgrep -P` walk + `Process.Kill($true)` on Unix), exit-code normalization (`0..3`, otherwise `3`), and `Split-IcingaBinaryPluginOutput` perfdata extraction.
- **Worker result dispatch:** `Start-IcingaProtocolWorker` measures monotonic `Stopwatch` timing around `Invoke-IcingaProtocolCheckCommand`, omits `'service'` from `$CheckResultData` when `params.service` is empty (preserving Icinga 2 Host check results), falls back `'check_source'` to `$HostName` if `Config.Hostname` is unset, and nulls all loop reference variables in `finally`.

---

## 3. Runtime Flow

1. `Add-IcingaRPCMessageToWorker` deserializes the incoming JSON-RPC frame and enqueues it onto `WorkerQueue[$WorkerId]`.
2. `Start-IcingaProtocolWorker` dequeues the frame, enters `'event::ExecuteCommand'`, records `CheckStarted`, and starts `$Stopwatch`.
3. `Invoke-IcingaProtocolCheckCommand` resolves the target via `Resolve-IcingaProtocolCommand`, parses arguments via `ConvertFrom-IcingaProtocolMacros`, executes the PowerShell check or approved binary, disposes temporary secrets, and returns `@{ ExitCode; Output; PerformanceData; CommandLine }`.
4. `Start-IcingaProtocolWorker` stops `$Stopwatch`, computes `CheckFinished`, logs `ExecutionTime` at `Debug` level, and enqueues `event::CheckResult` via `Send-IcingaProtocolCheckResult`.

---

## 4. Verification Results

- **Module Build & Strict API Documentation (`Build-ModuleProject.ps1` & `Build-ModuleDocs.ps1`):**
  - Compiled `41` public functions, `147` private functions, and `10` classes into `lib/IcingaForWindows.Classes.ps1` and `lib/IcingaForWindows.Kernel.ps1`.
  - Documented `188` functions across `20` Markdown files with **`0` violations**.
- **Code Styling, ScriptAnalyzer & Daemon Memory Leak Checks:**
  - `Tests/CodeStyling.Tests.ps1` (`.\build\Test-ModuleCodeStyling.ps1 -Path <targets>`) across all `88` validated source, build, and test files: **`0` violations**.
  - `Invoke-ScriptAnalyzer -Settings .\PSScriptAnalyzerSettings.psd1` across `src/`, `build/`, and `IcingaForWindows.psm1`: **`0` Error or Warning findings**.
  - `.\build\Test-ModuleDaemonMemoryLeak.ps1`: **`0` daemon memory or `IDisposable` leaks**.
- **Pester Unit Test Execution (Pester 6.1.0 & Pester 4.10.1):**
  - Targeted protocol, converter, class-literal & styling suites (`7` files): **`54 / 54` passed (`0` failed)**.
  - Full repository suite under Pester 6.1.0 on macOS (`484` total tests): **`467` passed** (remaining `17` are pre-existing Windows-only `PerformanceCounter` / `New-SelfSignedCertificate` / `WindowsPrincipal` / `Get-CimInstance` OS calls on macOS).

---

## 5. Practical Examples

### Icinga 2 `CheckCommand` for an External Binary (`check_load.exe`)

```icinga2
object CheckCommand "ifw-check-load" {
    import "ifw-api"

    vars.ifw_api_command = "check_load.exe"

    arguments = {
        "-w" = {
            value = "$load_win_warn$"
            order = 1
        }
        "-c" = {
            value = "$load_win_crit$"
            order = 2
        }
    }
}
```

### Direct Local Invocation via `Invoke-IcingaProtocolCheckCommand`

```powershell
Import-Module .\IcingaForWindows.psd1 -Force;

& (Get-Module IcingaForWindows | Where-Object ModuleType -eq 'Script') {
    Invoke-IcingaProtocolCheckCommand -Params @{
        'command' = 'Invoke-IcingaCheckDirectory';
        'macros'  = @{
            'ifw_api_command' = 'directory';
            'Path'            = 'C:\ProgramData\IcingaForWindows';
            'ShowFileList'    = $true;
        };
    };
};
```

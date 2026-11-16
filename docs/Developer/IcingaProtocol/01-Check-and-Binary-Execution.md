# Icinga Protocol Check and Binary Execution

This guide explains how Icinga for Windows receives, validates, and executes monitoring checks delivered by Icinga 2 over the native JSON-RPC cluster protocol (`event::ExecuteCommand`), covering both native PowerShell check plugins (`Invoke-IcingaCheck*`) and external binaries or scripts located in the approved `Binaries` directory.

---

## 1. Architectural Background: How Icinga 2 Transmits Commands

Unlike legacy Icinga 2 Agent setups that synchronize local Icinga 2 DSL configuration files to the endpoint, Icinga for Windows operates directly as an Icinga 2 JSON-RPC endpoint without requiring local `.conf` check definitions on the Windows host.

When Icinga 2 schedules a check on an Icinga for Windows node, the payload sent inside `event::ExecuteCommand` depends on the `execute` method configured on the **CheckCommand** object on the Icinga 2 master/satellite:

1. **Standard ITL `plugin-check-command` (`methods_execute = PluginCheck`):**
   Icinga 2 assumes the remote agent already possesses the local `CheckCommand` definition (such as the ITL `load-windows` command) and therefore transmits **only** the Icinga `CheckCommand` object name (`"command": "load-windows"`) and custom variables explicitly referenced by remote macro list rules — often resulting in an **empty `"macros": {}` payload**.
2. **Icinga for Windows `ifw-api` CheckCommand Template (`methods_execute = IfwApiCheck`):**
   Importing `ifw-api` on the **CheckCommand** instructs Icinga 2 to serialize and transmit:
   - `macros.ifw_api_command`: The exact PowerShell check command or binary filename to execute on the Windows host.
   - `macros.ifw_api_arguments`: The structured argument dictionary (`value`, `set_if`, `order`, `skip_key`, `repeat_key`) derived from the `CheckCommand`'s `arguments` block.
   - All resolved host, service, and command macro values referenced by those arguments.

> **Important:** `ifw-api` is a **CheckCommand template**, not a Service template. Importing `ifw-api` on a `Service` object has no effect on `methods_execute`; it **must** be imported on the `CheckCommand` definition itself.

---

## 2. Command Resolution Rules & Security Boundaries

Every incoming `event::ExecuteCommand` request is resolved by `Resolve-IcingaProtocolCommand` using strict, deterministic rules:

1. **`macros.ifw_api_command` is mandatory:**
   Icinga for Windows never guesses an executable or cmdlet name from `params.command`. If `macros.ifw_api_command` is missing or empty (for example when using an unmodified ITL command such as `load-windows`), execution is rejected immediately with `[UNKNOWN]` and knowledge base reference **[IWKB001003](../../Knowledgebase/IWKB001003.md)**.
2. **Path traversal, NTFS ADS & boundary enforcement:**
   ASCII control characters (`0x00..0x1F`), invalid path characters, drive-relative colons (`C:evil.exe`), and NTFS Alternate Data Stream colons (`check_load.exe:stream`) are rejected immediately. Any value containing path separators (`\`, `/`), rooted drive prefixes, UNC prefixes, or `..` segments is normalized via `[System.IO.Path]::GetFullPath(...)` and verified against `Get-ModuleBinaryDirectory()` (`C:\ProgramData\IcingaForWindows\Binaries`). Any path outside that directory is rejected with **[IWKB001003](../../Knowledgebase/IWKB001003.md)**.
3. **Explicit PowerShell check plugins (`Invoke-IcingaCheck*`):**
   Names starting with `Invoke-IcingaCheck` (without wildcards or path separators) are resolved against loaded module functions and cmdlets via `(Get-Command).Parameters` metadata introspection (no slow `Get-Help` calls and no Windows PowerShell 5.1 ETS memory leaks). Arbitrary PowerShell cmdlets such as `Remove-Item`, `Get-Process`, or `Invoke-Expression` are never accepted.
4. **Approved external binaries and scripts (`Get-ModuleBinaryDirectory()`):**
   External executables and scripts are looked up **exclusively** inside `C:\ProgramData\IcingaForWindows\Binaries` using full canonical file paths (`[System.IO.File]::Exists(...)`). `$env:PATH` and system directories (`System32`) are **never** searched. When `ifw_api_command` is specified without a file extension (or with a non-executable dotted suffix such as `check_app_v1.2`), extensions are probed deterministically in the order `.exe`, `.cmd`, `.bat`, `.com`, `.ps1`.
5. **PowerShell shorthand names:**
   If no matching file exists inside `C:\ProgramData\IcingaForWindows\Binaries` and `ifw_api_command` has neither path separators nor a file extension, Icinga for Windows expands shorthand names automatically:
   - `"cpu"` -> `Invoke-IcingaCheckCPU`
   - `"directory"` -> `Invoke-IcingaCheckDirectory`
   - `"IcingaCheckService"` -> `Invoke-IcingaCheckService`

---

## 3. Configuring PowerShell Check Plugins

### 3.1 Recommended Mode: Active `ifw-api` Template

When using the Icinga for Windows Director Basket or DSL CheckCommand definitions, each `CheckCommand` imports `PowerShell Base` and `ifw-api`:

```icinga2
object CheckCommand "Invoke-IcingaCheckDirectory" {
    import "PowerShell Base"
    import "ifw-api"

    vars.ifw_api_command = "Invoke-IcingaCheckDirectory"

    arguments += {
        "-Path" = {
            value = "$IcingaCheckDirectory_String_Path$"
            order = 1
        }
        "-FileNames" = {
            value = "$IcingaCheckDirectory_Array_FileNames$"
            order = 2
        }
        "-Critical" = {
            value = "$IcingaCheckDirectory_String_Critical$"
            order = 3
        }
        "-ShowFileList" = {
            set_if = "$IcingaCheckDirectory_Switchparameter_ShowFileList$"
            order = 4
        }
    }
}
```

In this mode, `ConvertFrom-IcingaProtocolMacros` resolves `$MacroName$` tokens directly against `macros`, preserves native JSON types (arrays, numbers, booleans), handles Icinga 2 serialized valueless flags (`"value": null` on `[switch]` parameters), evaluates `set_if` switches safely via `ConvertFrom-ModuleBoolean`, and validates that every parameter supplied with a **non-empty** value exists on the target PowerShell check plugin (otherwise returning `[UNKNOWN]` with **[IWKB001001](../../Knowledgebase/IWKB001001.md)**). Unpopulated optional template macros (`null` or empty string `""`) are automatically skipped.

### 3.2 Fallback Mode: Without `ifw-api`

If `ifw_api_command` is provided in `macros` without `ifw_api_arguments`, `ConvertFrom-IcingaProtocolMacros` falls back to convention-based custom variable mapping:

- Internal transport variables (`ifw_api_*`, `IcingaPowerShellBase_*`) and empty `""` placeholder keys are ignored.
- Custom variables matching an exact plugin parameter or alias name (for example `vars.Path = "C:\\Logs"`) are bound directly.
- Custom variables following the Icinga for Windows naming convention `IcingaCheck<CheckName>_<DataType>_<ParameterName>` (for example `vars.IcingaCheckDirectory_String_Path = "C:\\Logs"`) are mapped to `-<ParameterName>`.
- If one or more custom variables (including inherited Host `vars.*` forwarded when `ifw-api` is inactive) cannot be mapped to any parameter of the check plugin, execution aborts with `[UNKNOWN]` and **[IWKB001000](../../Knowledgebase/IWKB001000.md)**.

---

## 4. Configuring External Binaries and Scripts

External Nagios/Icinga plugins (`.exe`, `.cmd`, `.bat`, `.com`) and custom PowerShell scripts (`.ps1`) are restricted exclusively to `Get-ModuleBinaryDirectory()` without exposing `$env:PATH`. Icinga for Windows applies two distinct execution and timeout models depending on whether the target is PowerShell or a non-PowerShell OS binary:

1. **PowerShell Check Plugins (`Invoke-IcingaCheck*`) and `.ps1` Scripts in `Binaries`:**
   Executed natively in-process using PowerShell's `&` call operator (never dot-sourced `.`) with `Protected.IsBackgroundDaemon = $true` and **no** custom process timeout wrapper. Hung PowerShell threads are governed centrally by `Start-ThreadHouseKeeper` (`FROZEN` -> `ZOMBIE` + automatic `-KeepAlive` worker thread replacement) and the Icinga 2 master's check timeout. External `.ps1` scripts support typed parameter coercion (`[bool]`, `[switch]`, arrays, `[securestring]`), `New-IcingaPlugin` `.Compile()` results via `Private.Icinga.CheckResult`, and standard Nagios/Icinga `|` stdout + `exit` code handling.
2. **Native Executables (`.exe`, `.com`) and Batch Scripts (`.cmd`, `.bat`) in `Binaries`:**
   Executed as isolated OS processes via `System.Diagnostics.Process` (`UseShellExecute = $false`) and enforced against `params.check_timeout` (`60s` default) with full descendant process-tree termination on timeout so hung third-party binaries cannot accumulate in memory on the Windows host.

### Step 1: Place the Binary in the Approved Directory

Copy the executable or script into:

```text
C:\ProgramData\IcingaForWindows\Binaries\
```

For example: `C:\ProgramData\IcingaForWindows\Binaries\check_load.exe`.

### Step 2: Configure the `CheckCommand` in Icinga 2 DSL

Do **not** use an unmodified ITL command such as `load-windows` directly, because `load-windows` uses `PluginCheck` and does not define `ifw_api_command`. Instead, define a `CheckCommand` that imports `ifw-api` and explicitly sets `vars.ifw_api_command`:

```icinga2
object CheckCommand "ifw-check-load" {
    import "ifw-api"

    vars.ifw_api_command = "check_load.exe"

    arguments = {
        "-w" = {
            value = "$load_win_warn$"
            description = "Warning threshold"
            order = 1
        }
        "-c" = {
            value = "$load_win_crit$"
            description = "Critical threshold"
            order = 2
        }
    }
}

apply Service "Windows Load (Binary)" {
    check_command = "ifw-check-load"
    vars.load_win_warn = "80%"
    vars.load_win_crit = "90%"
    assign where host.vars.os == "Windows"
}
```

### Step 3: Equivalent Configuration in Icinga Director

1. Navigate to **Icinga Director -> Commands -> Commands** and create a new Command (or clone the desired command).
2. Under **Imports**, import the **`ifw-api`** CheckCommand template.
3. On the **Arguments** tab, configure the CLI flags expected by the binary (such as `-w` and `-c` with `value`, `set_if`, `order`, `skip_key`, `repeat_key`).
4. On the **Custom properties** (`Fields` / `Vars`) tab of the Command, set:
   - `ifw_api_command` = `check_load.exe` *(overrides any `$command.name$` default when the Icinga Command object name differs from the executable filename)*.
5. Deploy the configuration through Icinga Director.

### Output, Performance Data, Timeout & Exit Code Handling for Binaries

- **Full-path execution, argument escaping & `.cmd`/`.bat` metacharacter protection:** Native `.exe`/`.com` executables are started directly via `System.Diagnostics.Process` with `UseShellExecute = $false` and `FileName` set to the full canonical path in `C:\ProgramData\IcingaForWindows\Binaries\...`, preserving case-distinct CLI flags (`-p` vs `-P`, `-c` vs `-C`) and Icinga 2 serialized valueless flags (`"value": null`) with Windows `CommandLineToArgvW` quoting. Because Windows `CreateProcess` invokes `.cmd` and `.bat` files through `cmd.exe /c`, arguments passed to `.cmd`/`.bat` scripts are validated beforehand and rejected with `[UNKNOWN]` (`3`) if they contain `cmd.exe` command, redirection, or variable-expansion metacharacters (`&`, `|`, `<`, `>`, `^`, `\r`, `\n`, `"`, `!`, or paired `%VAR%` patterns), while standalone percent thresholds (`80%`, `90%`) remain permitted.
- **OS process timeout & descendant tree termination:** Non-PowerShell binaries enforce `params.check_timeout` (`60s` default, clamped safely to `Int32.MaxValue` ms) across both process execution and asynchronous `stdout`/`stderr` pipe closure. When a binary times out or leaves a background child holding `stdout`/`stderr` open, Icinga for Windows terminates the root process and every descendant process (`Win32_Process` `ParentProcessId` walk + handle `WaitForExit` rundown on Windows; `Process.Kill($true)` + `pgrep -P` walk on Unix) before returning `[UNKNOWN]` (`3`).
- **Nagios/Icinga pipe splitting & `stderr` fallback:** Standard output (falling back to `stderr` when `stdout` is blank) is split at `|` via `Split-IcingaBinaryPluginOutput` into human-readable check output and individual performance-data metric strings, preserving quoted, Icinga 2 scoped, and doubled-quote metric labels containing spaces (such as `'C:\ Free Space'=50GB;20;10;0;100` or `check_disk::'C:\ Free Space'=12GB`).
- **Exit code normalization:** Exit codes `0` (`OK`), `1` (`WARNING`), `2` (`CRITICAL`), and `3` (`UNKNOWN`) are preserved; any exit code outside `0..3` is normalized to `3` (`UNKNOWN`).
- **Fallback without `ifw-api`:** If a binary is invoked without `ifw_api_arguments`, execution succeeds when no custom variables are passed or when every custom variable starts with `-` or `/`. Unprefixed custom variables trigger `[UNKNOWN]` with **[IWKB001002](../../Knowledgebase/IWKB001002.md)**.

---

## 5. SecureString Parameters & Secret Masking

When a PowerShell check plugin (`Invoke-IcingaCheck*`) or an external `.ps1` script in `Binaries` declares a parameter of type `[System.Security.SecureString]`:

1. Plain-text secret strings transmitted in Icinga 2 macros are automatically converted into read-only `[System.Security.SecureString]` instances via `ConvertTo-ModuleSecureString` (`AppendChar` + `MakeReadOnly`, safely supporting empty strings on Windows PowerShell 5.1 and PowerShell 7+).
2. In the rendered command string (`cr.command` returned to Icinga Web 2 and debug logs), the parameter value is always masked as `'********'`.
3. Immediately after plugin or `.ps1` execution finishes, `Invoke-IcingaProtocolCheckCommand` calls `.Dispose()` on every allocated `SecureString` inside a `finally` block.

---

## 6. Execution Timing & Host/Service Result Dispatch

Inside `Start-IcingaProtocolWorker`, execution timing for `event::ExecuteCommand` measures the complete local check processing window without including idle queue wait time or network transmission overhead:

1. **Start timer:** Capture `CheckStarted` (`Get-IcingaUnixTime -Milliseconds` in UTC) and start a monotonic `[System.Diagnostics.Stopwatch]` immediately upon entering `event::ExecuteCommand`.
2. **Resolve, parse & execute:** Run `Invoke-IcingaProtocolCheckCommand` (command resolution, macro parsing, type coercion, `SecureString` conversion, and check/binary execution).
3. **Stop timer:** Stop `$Stopwatch` immediately upon return and compute `CheckFinished = CheckStarted + Stopwatch.Elapsed.TotalSeconds`.
4. **Log & transmit:** Emit debug telemetry and enqueue `event::CheckResult` via `Send-IcingaProtocolCheckResult` (omitting the `'service'` field when `params.service` is absent or empty so Icinga 2 processes Host checks accurately, and falling back `'check_source'` to `params.host` if `Config.Hostname` is unset).

---

## 7. Related Knowledgebase Articles

- [IWKB001000 — Unable to map Custom-Variables to Icinga for Windows Check](../../Knowledgebase/IWKB001000.md)
- [IWKB001001 — Unknown Check-Command Parameter in `ifw_api_arguments`](../../Knowledgebase/IWKB001001.md)
- [IWKB001002 — Unable to map Custom-Variables to External Binary Check without `ifw-api`](../../Knowledgebase/IWKB001002.md)
- [IWKB001003 — Check Command Not Found, Missing `ifw_api_command`, or Binary Outside Approved Directory](../../Knowledgebase/IWKB001003.md)

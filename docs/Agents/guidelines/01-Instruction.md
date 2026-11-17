# Icinga for Windows -- Code, Architecture & Documentation Ruleset

This document defines the **binding code style, SPDX licensing, project layout, threading safety, documentation, changelog/roadmap governance, and task-tracking rules** for the **Icinga for Windows** PowerShell module. It is the single source of truth that all AI coding assistants (Claude, Gemini / Antigravity, OpenAI Codex / ChatGPT, GitHub Copilot, Cursor, Windsurf, ...) and human contributors **MUST** follow when editing this repository.

If anything here contradicts a tutorial, blog post, or general PowerShell convention -- **this file wins**.

---

## 1. Project Layout

```text
IcingaForWindows/
├── .github/copilot-instructions.md  <- Entrypoint for GitHub Copilot -> points here
├── AGENTS.md                        <- Entrypoint for Codex / Copilot / Cursor / Windsurf -> points here
├── CLAUDE.md                        <- Entrypoint for Claude Code -> points here
├── GEMINI.md                        <- Entrypoint for Gemini / Antigravity -> points here
├── IcingaForWindows.psd1            <- Module manifest (GPL-3.0-or-later + PrivateData.SPDX)
├── IcingaForWindows.psm1            <- Hand-written runtime bootstrap ($Global:IcingaForWindows)
├── build/
│   ├── Build-ModuleProject.ps1      <- Compiler: src/ -> lib/IcingaForWindows.{Classes,Kernel}.ps1
│   ├── Build-ModuleDocs.ps1         <- Doc generator: src/ -> docs/Icinga.*.md & docs/index.md
│   ├── Invoke-ModuleTests.ps1       <- Standalone Pester test runner
│   ├── Invoke-ScriptAnalysis.ps1    <- PSScriptAnalyzer runner
│   ├── Test-ModuleChangelog.ps1     <- Non-main PR Changelog.md & Roadmap.md governance gate
│   ├── Test-ModuleCodeStyling.ps1   <- Code-styling, function-scope & SPDX license validator
│   └── Test-ModuleDaemonMemoryLeak.ps1 <- AST daemon loop & IDisposable leak checker
├── src/                             <- Source code (strictly one function or class/enum file)
│   ├── Classes/                     <- PowerShell classes & enums (compiled per runspace)
│   ├── Config/                      <- Environment & configuration directory helpers
│   ├── Core/                        <- ErrorHandling, Logging, RestApi, Runtime, TCPStack, Threading, WebSocket
│   ├── IcingaProtocol/              <- Native Icinga 2 JSON-RPC protocol & check execution
│   ├── PerformanceCounter/          <- Background performance counter daemon & readers
│   ├── Plugins/
│   │   ├── Checks/Public/           <- Exported Invoke-IcingaCheck* monitoring plugins
│   │   ├── Lib/                     <- Public/internal plugin SDK helpers (New-IcingaPlugin, ...)
│   │   └── Provider/                <- OS data providers (Disk, FileSystem, Process, ScheduledTask, ...)
│   ├── Security/                    <- Approved-path file & directory wrappers
│   └── Tools/                       <- JSON, unit conversion, sorting, CIM, boolean & SecureString helpers
├── lib/                             <- Auto-generated compiled artifacts, NEVER edit by hand
│   ├── IcingaForWindows.Classes.ps1
│   └── IcingaForWindows.Kernel.ps1
├── data/                            <- Static runtime assets (Web UI, templates)
├── docs/
│   ├── Agents/
│   │   ├── guidelines/
│   │   │   └── 01-Instruction.md    <- This binding ruleset (Single Source of Truth)
│   │   └── tasks/
│   │       └── <BranchSlug>/        <- Persistent per-branch feature tracking (Section 9)
│   │           ├── implementation_plan.md
│   │           ├── todo.md
│   │           └── walkthrough.md
│   ├── Developer/                   <- Hand-written architectural & developer guides
│   ├── General/
│   │   ├── Changelog.md             <- Mandatory PR / feature-branch release changelog
│   │   └── Roadmap.md               <- Completed milestones & prioritized future backlog
│   ├── Knowledgebase/               <- Hand-written IWKB001xxx troubleshooting articles
│   ├── Icinga.*.md                  <- Auto-generated API reference, NEVER edit by hand
│   └── index.md                     <- Auto-generated API reference index, NEVER edit by hand
└── Tests/                           <- Pester unit & static-analysis test suites
```

**Function Scope & File Rules (`src/` vs. `build/`):**
- **Under `src/` (outside `src/Classes/`):** Every PowerShell `.ps1` file defines **at most one top-level `function`**, named identically to the `.ps1` file (for example `Invoke-IcingaCheckCPU.ps1` contains `function Invoke-IcingaCheckCPU()`). **Never** place multiple functions in a single `src/` file and **never** nest a `function` inside another `function` under `src/`.
- **Under `src/Classes/`:** Files contain only `class` and `enum` definitions (and their class methods/constructors) -- never standalone `function` declarations.
- **Under `build/`, `IcingaForWindows.psm1`, and `Tests/`:** Internal helper functions and nested functions inside scripts or functions **are permitted**, provided every `function` declaration still follows Allman brace formatting (`function Name()`).
- `Public/` = exported, user-facing. `Private/` = internal helpers, not exported.
- Files in `lib/` and auto-generated `docs/Icinga.*.md` / `docs/index.md` are **always regenerated** -- manual edits will be lost.

---

## 2. PowerShell Code Style

### 2.1 The semicolon rule

> **Every non-function statement ends with a semicolon `;`.**

This includes `param (...)` blocks (`);`), assignments, pipeline ends, `return` statements, and expressions inside control-flow blocks -- everything that is *not* a bare `function Name() { ... }` or block brace.

```powershell
function Get-IcingaExample()
{
    param (
        [string]$Name = $null,
        [int]$Count   = 0
    );

    if ([string]::IsNullOrEmpty($Name)) {
        return $null;
    }

    [array]$Results = @();

    for ($i = 0; $i -lt $Count; $i++) {
        $Results += "$Name-$i";
    }

    return $Results;
}
```

### 2.2 Function & control-flow declaration

- Opening brace on its **own line** (Allman style) for `function`, `class`, and `enum` declarations, not K&R.
- Explicit empty parentheses after the function name (`function Foo()`), even when parameters are declared inside `param ()`.
- `param ()` block always uses one parameter per line with explicit type prefix and default value (`= $null` for nullable refs, `= @()` for arrays, `= @{ }` for hashtables, `= $false` for switches).
- `if (...) {` and `} elseif (...) {` conditions **must stay on a single line** ending with `{` (do not wrap multi-line conditions across newlines; extract intermediate `[bool]` variables beforehand when a condition grows long).

### 2.3 Naming & Prose Convention (`"Icinga for Windows"` vs. `IcingaForWindows`)

| Kind | Convention | Example |
|------|------------|---------|
| Prose product name | **"Icinga for Windows"** (always spaced) | `Icinga for Windows monitoring stack` |
| Technical module / variable name | **`IcingaForWindows`** (no spaces, code only) | `Import-Module IcingaForWindows`, `$Global:IcingaForWindows` |
| Public function | `Verb-IcingaNoun` (approved PS verbs only) | `Invoke-IcingaCheckCPU` |
| Private helper | `Verb-ModuleNoun` **or** `Verb-IcingaInternalNoun` | `ConvertFrom-ModuleBoolean`, `Write-LoggingEntry` |
| Variable | `PascalCase` with `$` | `$CheckResultData`, `$WorkerId` |
| Loop counter | lowercase | `$i`, `$idx` |
| Type-annotated variable | `[Type]$Name = ...` | `[int]$WorkerId = -1` |
| Constants in `$Global:IcingaForWindows` | nested hashtables/PSCustomObjects under `Public/Private/Protected` | `$Global:IcingaForWindows.Public.IcingaProtocol.Config` |

- **Prose Naming Rule (Binding):** Always write **"Icinga for Windows"** in prose across all Markdown documents (`README.md`, `docs/**`), inline comments, comment-based help blocks, changelogs, roadmaps, implementation plans, todos, and walkthroughs. Reserve **`IcingaForWindows`** exclusively for technical identifiers (`Import-Module IcingaForWindows`, `IcingaForWindows.psd1`, `IcingaForWindows.psm1`, `lib/IcingaForWindows.*.ps1`, directory paths such as `C:\ProgramData\IcingaForWindows`, and `$Global:IcingaForWindows`).
- **Approved PS verbs only** -- run `Get-Verb` to check. Avoid `Process-`, `Validate-`, `Execute-`.
- **Never collide with PowerShell built-ins or other modules.** Prefix everything user-facing with `Icinga`.
- Acronyms keep their case: `RestApi`, `IcingaProtocol`, `AccessControl`, `CPU`.

### 2.4 Encoding, indentation, whitespace & vertical alignment

All rules below are automatically enforced by `build/Test-ModuleCodeStyling.ps1`:

- **UTF-8 without BOM & strict 7-bit ASCII (`0x00`-`0x7F`) in PowerShell files:** UTF-8/UTF-16/UTF-32 byte order marks (`0xEF 0xBB 0xBF`, ...) and literal non-ASCII characters (`> 0x7F`) are strictly forbidden in `.ps1`, `.psm1`, and `.psd1` files. Concatenated `lib/` files break on mid-file BOMs, while Windows PowerShell 5.1 decodes BOM-less scripts as Windows-1252 (turning UTF-8 bytes `0x91`-`0x94` into smart-quote string delimiters that corrupt the AST). Use plain 7-bit ASCII (`--`, `->`, `...`, `*`) or `[char]0xXXXX` when a runtime Unicode glyph is intentionally needed.
- **4 spaces** per indentation level; **no tab characters**.
- One blank line between logical function body sections (initialization, processing, return).
- **No trailing whitespace** on any line; files end with a single trailing newline.
- **Vertical alignment of assignment operators (`=`, `+=`, `-=`, `*=`, `/=`):**
  Within any assignment block at the same indentation depth (spanning blank lines, inline comments, and multi-line RHS expressions until interrupted by control-flow keywords or braces), align the `=` character vertically so the widest left-hand side has **exactly one space** before the operator and **one space** after `=`:
  ```powershell
  [int]$ExitCode        = 3;
  [string]$CheckOutput  = '';
  [array]$CheckPerfData = @();
  ```
- **Vertical alignment of hashtable & enum entries:**
  Single-entry hashtables and enums must use `1` space before and `1` space after `=`; contiguous `'Key' = Value;` or `EnumMember = Value` lines at the same indentation level must align `=` vertically with exactly one space after the widest key and one space after `=`.
- **Vertical alignment of `.PARAMETER` Markdown tables:**
  All `|` column separators across header, separator, and every value row of every `.PARAMETER` help table must be vertically aligned at identical column indices.

### 2.5 Global state access

`$Global:IcingaForWindows` is the shared runtime state initialized by `New-ModuleBaseEnvironment` in [IcingaForWindows.psm1](../../../IcingaForWindows.psm1). Access patterns:

```powershell
# Inside a thread / worker / background helper -- ALWAYS go through Get-GlobalRuntimeVariable
$GlobalVariable = Get-GlobalRuntimeVariable;
$GlobalVariable.Public.RestApi.Config.ListenPort;

# Inside a normal function guaranteed to run only on the main thread, direct access is acceptable:
$Global:IcingaForWindows.Public.IcingaProtocol.Config.Hostname;
```

**Rule of thumb:** anything that runs inside `Start-*Daemon`, `Start-*Worker`, or any helper invoked from a background thread **MUST** go through `Get-GlobalRuntimeVariable` so thread-local `Private` and `Protected` state resolves to the active runspace.

Inside infinite daemon loops (`while (Test-ThreadRunning ...)`), every non-primitive local variable assigned inside the loop **must** be explicitly reset to `$null` in the loop's `finally` block, and every `IDisposable` object must have `.Dispose()` called (`build/Test-ModuleDaemonMemoryLeak.ps1`).

### 2.6 Return values and error handling

- Public functions: return the structured result the caller expects (exit code, object, hashtable, `$null`).
- Private functions that participate in the return-code system: register semantic keys in `src/Core/ErrorHandling/Private/Set-InternalExitCodes.ps1` and emit via `Write-FunctionReturnValue -ReturnValue 'SemanticKey' -Data @{ ... }`.
- Never `throw` for expected runtime/configuration error paths inside daemons or checks. Log via `Write-LoggingEntry` / `Write-FunctionReturnValue` and return `$null` or a structured `[UNKNOWN]` result so worker threads stay alive.
- `throw` is reserved for **programmer errors** (impossible state, build/test script failures).

### 2.7 Logging

```powershell
Write-LoggingEntry -Message 'Short, present-tense description' -Level 'Info' -Data @{
    'ContextKey1' = $Value1;
    'ContextKey2' = $Value2;
};
```

Levels: `Debug`, `Output`, `Audit`, `Info`, `Success`, `Warning`, `Error`, `Fatal`. Use `Debug` for hot-loop telemetry, `Info` for state transitions, `Warning` for recoverable issues, `Error` for unhandled exceptions. Never log plain-text passwords or `SecureString` contents; always mask secrets as `'********'`.

### 2.8 Forbidden constructs

- ❌ `Write-Host` outside of `build/` scripts (and console prompt/logging formatters). Use `Write-LoggingEntry -Level 'Output'`.
- ❌ `Write-Output` for logging -- use it only when genuinely returning a value to the pipeline.
- ❌ Stream redirects like `2>$null` or `*>&1`. Handle errors explicitly with `try / catch`.
- ❌ Aliases in source code (`%`, `?`, `select`, `where`). Use full cmdlet names (`ForEach-Object`, `Where-Object`, `Select-Object`).
- ❌ Any literal non-ASCII character (`> 0x7F`, including em-dashes U+2014, en-dashes U+2013, arrows `->`, box-drawing glyphs, checkmarks, or emojis) in PowerShell `.ps1` / `.psm1` / `.psd1` files -- Windows PowerShell 5.1 reads BOM-less UTF-8 files as Windows-1252, causing Mojibake and turning UTF-8 bytes `0x91`-`0x94` into smart-quote string delimiters that break compilation. Use plain 7-bit ASCII (`-`, `--`, `->`, `...`, `*`) or `[char]0xXXXX`.
- ❌ `-ErrorAction SilentlyContinue` as a "make the warning go away" shortcut. Use explicit checks or `try / catch` with `-ErrorAction Stop`.
- ❌ Multiple top-level functions or nested functions inside any file under `src/`.
- ❌ Missing `.NOTES` or missing Icinga GmbH SPDX license headers in any `.ps1`, `.psm1`, or `.psd1` file.
- ❌ Editing generated files under `lib/` or `docs/Icinga.*.md` / `docs/index.md` by hand.
- ❌ PowerShell class literals in functions outside `src/Classes` (`[IcingaPlugin]::new()`, `[IcingaSortKey]::FromObject()`, `-is [IcingaError]`). See Section 2.9.

### 2.9 Classes and threads

Every runspace dot-sources the same compiled kernel, while the classes from `src/Classes` are loaded separately into each runspace. A class literal inside a function is resolved once and points to the class type of the **main** runspace -- even when the function runs in a daemon or worker thread. On Windows PowerShell 5.1 a constructor, method, or static call on that type from a thread waits until the main runspace is idle, stalling the thread. Objects of the thread's own type also no longer match the literal (`-is` returns `$false` and typed parameters fail with *Cannot convert the "IcingaError" value of type "IcingaError" to type "IcingaError"*).

1. **Never use a PowerShell class literal in a function** -- not to create an object, not for a static member, not for `-is`, casts, or typed variables/parameters. Resolve the class of the current runspace instead:

   | Instead of | Use |
   |------------|-----|
   | `[IcingaPlugin]::new('C:', 55, '%')` | `New-IcingaPlugin 'C:' 55 '%'` |
   | `$Data -is [IcingaError]` | `Test-IcingaError -InputObject $Data` |
   | `[IcingaError]::new(...)` | `('IcingaError' -as [type])::new(...)` |
   | `[IcingaSortKey]::FromObject(...)` in a loop | `$SortKeyType = 'IcingaSortKey' -as [type];` once before the loop, then `$SortKeyType::FromObject(...)` |

2. **Exceptions:** code inside `src/Classes` (loaded per runspace, except `IcingaPerformanceCounter.ps1` which also uses runtime lookups), Pester tests, .NET BCL classes (`[System.Text.StringBuilder]`, `[System.Security.SecureString]`), and enums such as `[IcingaServiceStatus]::Running` (enums carry no script methods and convert by value).
3. **Never pass PowerShell class instances between threads.** Hand over only primitive values, hashtables, and arrays. A plugin result travels as its rendered output, integer exit code, and performance-data string array, never as the `IcingaCheckResult` object.
4. `Tests/ClassLiteral.Tests.ps1` enforces rule 1 and reports the file and line of every offending literal.

Background and examples: [docs/Developer/Threading/01-Threading.md](../../Developer/Threading/01-Threading.md#classes-and-threads).

---

## 3. Comment-Based Help & Mandatory SPDX Licensing

Every PowerShell source file -- **public functions, private functions, classes/enums, bootstrap scripts, build scripts, and Pester test files** -- must carry a comment-based help block containing `.NOTES` with the Icinga GmbH SPDX license lines:

> **Language rule:** All code, inline comments, comment-based help, developer guides, changelogs, roadmaps, knowledgebase entries, implementation plans, todos, and walkthroughs **must be written 100% in English**. No exceptions.

```powershell
<#
.SYNOPSIS
One-line summary in imperative voice without a trailing period

.DESCRIPTION
Detailed multi-line description (~80 columns). Cover what the function does,
how it fits into the larger workflow, any threading or networking behavior,
and important side-effects (writes to global state, blocking I/O, external
dependencies).

.PARAMETER Name
| Name | Type          | Description                             | Default |
|------|---------------|-----------------------------------------|---------|
| Name | System.String | Display name of the resource to act on. | ''      |

.PARAMETER Count
| Name  | Type         | Description                      | Default |
|-------|--------------|----------------------------------|---------|
| Count | System.Int32 | Number of iterations to perform. | 1       |

.OUTPUTS
System.Object -- Description of the returned value or object shape.
Use None if the function returns nothing.

.EXAMPLE
PS> Verb-IcingaNoun -Name 'Foo' -Count 3

Short prose describing what the example does.

.NOTES
Module-level dependencies (external services, credentials, config files),
required privileges, and threading caveats.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Verb-IcingaNoun()
{
    ...
}
```

### 3.1 Strict help & SPDX license rules

1. **All seven sections** are mandatory on **public** functions: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` (one per declared parameter), `.OUTPUTS`, `.EXAMPLE`, `.NOTES`.
2. **Private functions** must have `.SYNOPSIS`, `.DESCRIPTION`, a `.PARAMETER` Markdown table for **every** declared parameter in `param ()`, and **`.NOTES`** (including `.OUTPUTS` and `.EXAMPLE` is strongly recommended).
3. **Classes and enums (`src/Classes/`)** must carry a top-level comment-based help block above each top-level `class` / `enum` declaration including `.SYNOPSIS`, `.DESCRIPTION`, and **`.NOTES`**.
4. **Mandatory Icinga GmbH SPDX Footer & Header Comments (Every File):**
   - Inside `<# ... #>` comment blocks (specifically concluding every `.NOTES` section across `src/` (`Public/`, `Private/`, `Classes/`), `IcingaForWindows.psm1`, `build/*.ps1`, `Tests/*.Tests.ps1`, and the top-of-file header block of compiled `lib/IcingaForWindows.Classes.ps1` and `lib/IcingaForWindows.Kernel.ps1`), write these exact two lines without any comment prefix:
     ```text
     SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
     SPDX-License-Identifier: GPL-3.0-or-later
     ```
   - Outside `<# ... #>` block comments (such as `.psd1` data files), prefix both lines with `# `:
     ```powershell
     # SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
     # SPDX-License-Identifier: GPL-3.0-or-later
     ```
     Specifically, `IcingaForWindows.psd1` declares `Copyright = '(c) 2026 Icinga GmbH | GPL-3.0-or-later';`, points `LicenseUri` to `blob/main/LICENSE`, and defines `SPDX = '';` followed by the two `# SPDX-...` lines beneath `Endpoint` inside `PrivateData` (`PSScriptAnalyzerSettings.psd1` likewise carries the two `# SPDX-...` lines at the top of the file).
5. **Every `.PARAMETER` block uses the four-column Markdown table** (`Name | Type | Description | Default`) with vertically aligned `|` pipes.
6. `.SYNOPSIS` is **one line, no trailing period** unless it contains multiple sentences.
7. `.DESCRIPTION` uses plain prose wrapped around ~80 columns.
8. `.OUTPUTS` starts with the .NET type name (`System.Int32`, `System.Collections.Hashtable`, `System.Object`, `None`), followed by `-- Description` (plain ASCII `--`, never an em-dash).
9. `.EXAMPLE` begins with `PS> ` and shows a realistic invocation.

### 3.2 Inline comments

- **Always include and preserve helpful inline comments** explaining numbered workflow steps, section boundaries (`Mode A` / `Mode B`), protocol quirks, Windows PowerShell 5.1 compatibility constraints, and security invariants so readers immediately understand what happens and why. Never strip existing explanatory comments during refactoring.
- Avoid noisy filler comments that merely restate a trivial statement (`# increment counter` above `$i++`) or reference transient PR history (`# added for PR #12`).

---

## 4. Build, Validation & Generated Artifacts

### 4.1 Compilation

`build/Build-ModuleProject.ps1` walks `src/`, compiles classes into `lib/IcingaForWindows.Classes.ps1` and functions into `lib/IcingaForWindows.Kernel.ps1` (as BOM-less UTF-8 with top-of-file SPDX headers), and reloads the module:

```powershell
.\build\Build-ModuleProject.ps1 -SkipTests -TestDaemonMemoryLeaks;
```

### 4.2 Documentation generation

`build/Build-ModuleDocs.ps1` parses the comment-based help block of every `.ps1` file under `src/`, enforces `.NOTES` + SPDX completeness across both `Public` and `Private` functions, strips machine-readable `SPDX-...` lines from rendered Markdown notes, and writes component reference files into `docs/Icinga.*.md` and `docs/index.md` without touching hand-written subdirectories (`docs/General/`, `docs/Developer/`, `docs/Knowledgebase/`, `docs/Agents/`):

```powershell
.\build\Build-ModuleDocs.ps1 -Strict $true;
```

**If any `.ps1` file is missing required help sections, parameter tables, `.NOTES`, or SPDX lines, `Build-ModuleDocs.ps1` fails with a non-zero exit code.** Fix the `.ps1` source file -- never weaken the generator.

### 4.3 Static, style & governance validation

The entire repository (`src/`, `build/`, `IcingaForWindows.psm1`, `IcingaForWindows.psd1`, `Tests/`, and `lib/` SPDX headers) must pass all validators with **zero** violations:

```powershell
.\build\Test-ModuleCodeStyling.ps1;
.\build\Test-ModuleChangelog.ps1;
.\build\Test-ModuleDaemonMemoryLeak.ps1;
.\build\Invoke-ScriptAnalysis.ps1 -FailOn 'Warning';
```

In CI (`.github/workflows/ci.yml`), `Invoke-ScriptAnalysis.ps1`, `Test-ModuleCodeStyling.ps1`, and `Test-ModuleChangelog.ps1` execute once inside the `analyze` job. `Tests/CodeStyling.Tests.ps1` and `Tests/Changelog.Tests.ps1` are strictly fast `$TestDrive` unit test suites validating parser/gate behavior so the repository tree is never scanned twice during `Invoke-ModuleTests.ps1`.

---

## 5. Testing

- Pester test suites live under `Tests/` (`*.Tests.ps1`) and carry a top-level `<# .SYNOPSIS ... .NOTES SPDX-... #>` block.
- Every new public check/cmdlet -- and complex private subsystems such as protocol parsers or providers -- must ship with comprehensive unit tests covering happy paths, boundary conditions, PS 5.1 vs. PS 7 data shapes (`Dictionary[string, object]` vs. `Hashtable`), and error codes.
- Tests import `IcingaForWindows.psd1` and mock external OS/network boundaries (for example shadowing internal provider/directory functions inside `& $script:IcingaModule { ... }`) so unit tests run deterministically offline on Windows, Linux, and macOS.
- Never weaken, skip, or delete an existing test to make a change pass.

---

## 6. Commits, Branching, Changelog & Roadmap Governance

- Primary integration branch: `main`.
- Commit subjects in present-tense imperative (`Add ...`, `Fix ...`, `Update ...`), concise single line, in English.
- Commit body explains **why**, not **what**.
- Never amend pushed commits, never force-push shared branches, and never bypass Git hooks (`--no-verify`, `--no-gpg-sign`).
- **Mandatory `docs/General/Changelog.md` Entry (Non-`main` Branches & PRs):**
  Every branch not on `main` (`feature/*`, `fix/*`, `bugfix/*`, `chore/*`, ...) and every GitHub Pull Request **MUST** add at least one bullet entry (`* ...`) under the current unreleased version section (`### Enhancements`, `### Bugfixes`, `### Security`, or `### Documentation`) in [docs/General/Changelog.md](../../General/Changelog.md). Missing changelog entries fail `build/Test-ModuleChangelog.ps1` in CI.
- **Mandatory `docs/General/Roadmap.md` Synchronization:**
  Whenever an implementation plan (`docs/Agents/tasks/<BranchSlug>/implementation_plan.md`) is created or a branch milestone is completed, [docs/General/Roadmap.md](../../General/Roadmap.md) **MUST** be updated in the same branch so completed subsystems and prioritized upcoming work remain accurate.

---

## 7. Cross-Platform & Runtime Compatibility Notes

- **Primary production target:** Windows PowerShell 5.1 and PowerShell 7.5+ on Windows Server / Windows 11.
- **Development & CI compatibility:** Linux and macOS via the `$env:ProgramData` fallback in `IcingaForWindows.psm1`.
- Always use `Join-Path` for path construction; never hardcode `\` or `/` when building filesystem paths.
- Remember `ConvertFrom-ModuleJson` returns `Dictionary[string, object]` on Windows PowerShell 5.1 and `Hashtable` on PowerShell 7+ -- always accept `[System.Collections.IDictionary]` rather than forcing `[hashtable]` on deserialized JSON objects.

---

## 8. AI Assistant Etiquette

When you (Claude, Gemini / Antigravity, Codex, Copilot, Cursor, ...) work in this repository:

- **Match house style & SPDX rules 100%.** Inspect neighboring files in the same component before writing code, include `.NOTES` with the two Icinga GmbH SPDX lines on every PowerShell file, and verify zero violations with `.\build\Test-ModuleCodeStyling.ps1`.
- **Use `"Icinga for Windows"` in all prose** and reserve `IcingaForWindows` strictly for technical module, path, file, and `$Global:IcingaForWindows` identifiers.
- **Write everything 100% in English** -- code, comments, help blocks, changelogs, roadmaps, knowledgebase articles, and task-tracking artifacts (`implementation_plan.md`, `todo.md`, `walkthrough.md`).
- **Maintain `Changelog.md` & `Roadmap.md`.** Add a changelog bullet to `docs/General/Changelog.md` on every non-`main` branch (`.\build\Test-ModuleChangelog.ps1`) and synchronize `docs/General/Roadmap.md` whenever creating or completing task plans under `docs/Agents/tasks/`.
- **Don't add backwards-compatibility shims** for unreleased internal code.
- **Don't introduce premature abstractions** for a single caller.
- **Don't widen surface area.** Keep diffs focused on the requested task.
- **Don't commit to Git unless explicitly instructed by the user.**
- **Persist feature and task documentation** (`implementation_plan.md`, `todo.md`, `walkthrough.md`) in `docs/Agents/tasks/<BranchSlug>/` (see Section 9).
- **When requirements are ambiguous, ask a concise clarifying question** rather than guessing.

---

## 9. Feature & Task Implementation Tracking (`docs/Agents/tasks/`)

Every non-trivial feature, subsystem enhancement, or major refactoring in **Icinga for Windows** **MUST** maintain a dedicated task documentation folder under:

```text
docs/Agents/tasks/<BranchSlug>/
├── implementation_plan.md   <- Architecture, technical rationale, and proposed file changes
├── todo.md                  <- Granular checklist (completed items, open points, follow-ups)
└── walkthrough.md           <- Post-implementation deep dive, runtime flow & test proof
```

Where `<BranchSlug>` is derived from the Git branch name with prefixes such as `feature/`, `bugfix/`, or `chore/` stripped and underscores normalized to hyphens (for example `feature/plugins-cpu-service-partition` -> `plugins-cpu-service-partition`, `feature/update-code-styling` -> `update-code-styling`), sensibly shortened to ~40-50 characters if a branch name is excessively long.

### 9.1 Purpose and Technical Rationale

1. **Persistent Architectural Memory:** In-chat planning and ephemeral agent scratchpads disappear once a session ends or context is compacted. Versioning these three artifacts inside `docs/Agents/tasks/<BranchSlug>/` preserves *why* specific design choices were made, which security or performance trade-offs were evaluated, and how subtle runtime constraints (Windows PowerShell 5.1 vs. PowerShell 7 runspace class isolation, `$Global:IcingaForWindows` state partitioning, `SecureString` lifecycle, daemon memory-leak prevention) were solved.
2. **Seamless Multi-Agent & Incremental Handoffs:** Complex features often span multiple sessions, branches, or different AI tools (Claude, Gemini, Codex, Copilot) and human reviewers. A tracked `todo.md` makes completed work, deliberately deferred items, and next steps immediately visible without reverse-engineering diffs.
3. **Auditability & Roadmap Synchronization:** Provides reviewers and future maintainers with a self-contained architectural blueprint and verification record right beside the code, synchronized with [docs/General/Roadmap.md](../../General/Roadmap.md) and [docs/General/Changelog.md](../../General/Changelog.md).

### 9.2 The Three Required Artifacts (All in English)

#### 1. `implementation_plan.md` (Design & Architecture)
Drafted **prior to implementation** (and updated if architectural scope changes):
- **Problem Statement & Objectives:** User requirements, protocol/OS constraints, and security boundaries.
- **Architecture & Design Decisions:** Detailed coverage of:
  - Runspace & threading model (`Get-GlobalRuntimeVariable`, class-literal avoidance per Section 2.9, daemon loop cleanup).
  - State usage in `$Global:IcingaForWindows` (`Public`, `Private`, `Protected`).
  - Internal return codes (`Set-InternalExitCodes`) and user-facing `IWKB001xxx` Knowledgebase mappings where applicable.
  - Windows PowerShell 5.1 vs. PowerShell 7+ and cross-platform considerations.
- **Proposed Changes:** Grouped by component with relative repository paths marked `[NEW]`, `[MODIFY]`, or `[DELETE]`.
- **Data Flow:** Mermaid flowcharts or sequence diagrams illustrating execution lifecycles.
- **Verification Plan:** Exact build, code-styling, changelog, static-analysis, Pester, and manual verification steps.

#### 2. `todo.md` (Task Tracking & Open Points)
Actively maintained throughout implementation:
- **Categorized Checklist:**
  - `[x]` Completed items referencing the implemented source, test, and documentation files.
  - `[ ]` Open, deferred, or follow-up items for subsequent iterations or branches.
- **Known Limitations & Technical Debt:** Honest documentation of deferred edge cases or Windows-only integration tests requiring live agent verification.
- **Next Steps:** Concrete follow-up actions.

#### 3. `walkthrough.md` (Implementation Walkthrough & Verification Record)
Completed **after implementation and verification**:
- **Executive Summary:** Concise overview of what was built and why.
- **Under-the-Hood Deep Dive:** Explanation of core algorithms, security checks, type/macro coercion, resource disposal, and error handling.
- **Runtime Flow:** Step-by-step trace from entry point to final output/transmission.
- **Verification Results:** Exact commands executed (`Build-ModuleProject.ps1`, `Build-ModuleDocs.ps1`, `Test-ModuleCodeStyling.ps1`, `Test-ModuleChangelog.ps1`, `Test-ModuleDaemonMemoryLeak.ps1`, `Invoke-ModuleTests.ps1`) with real pass/fail counts.
- **Practical Examples:** Copy-pasteable PowerShell and/or Icinga 2 DSL snippets demonstrating usage.

### 9.3 Rules for AI Assistants

- **Mandatory Persistence & Roadmap Sync:** Every non-trivial feature or refactoring task must create or update `implementation_plan.md`, `todo.md`, and `walkthrough.md` under `docs/Agents/tasks/<BranchSlug>/`, update `docs/General/Roadmap.md` when plans are created or completed, and add a changelog entry to `docs/General/Changelog.md` whenever not on `main`.
- **100% English:** Even when the user prompts in German or another language, all repository documentation -- including `docs/Agents/tasks/<BranchSlug>/*.md`, `docs/General/Changelog.md`, and `docs/General/Roadmap.md` -- **must** be written in English.
- **Technical Depth Over Boilerplate:** Write concrete, accurate engineering documentation tied to real file paths, exit codes, and test results -- never vague filler text.

---

*Last updated: 2026-11-17*

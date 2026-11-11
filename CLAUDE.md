# CLAUDE.md — IcingaForWindows Code & Documentation Ruleset

This document defines the **binding code style, project layout and documentation rules** for the Icinga For Windows PowerShell module. It is the single source of truth that AI assistants (Claude, Copilot, …) and human contributors **MUST** follow when editing this repository.

If something here contradicts a tutorial, blog post or general PowerShell convention — **this file wins**.

---

## 1. Project Layout

```
IcingaForWindows/
├── IcingaForWindows.psd1            ← Module manifest, auto-updated by the build script
├── IcingaForWindows.psm1            ← Hand-written runtime bootstrap ($Global:Icinga)
├── build/
│   ├── Build-ModuleProject.ps1   ← Compiler: src/ → lib/
│   └── Build-ModuleDocs.ps1      ← Doc generator: src/ → docs/api/
├── src/                    ← Source code (one function per .ps1 file)
│   └── <Component>/<Subcomponent>/{Public,Private}/*.ps1
├── lib/                    ← Auto-generated, NEVER edit by hand
│   └── IcingaForWindows.<Component>.<Sub>.psm1
├── data/                   ← Static runtime assets (prompts, web UI, python daemons)
├── docs/
│   ├── api/                ← Auto-generated API reference (NEVER edit by hand)
│   ├── Architecture.md     ← Hand-written
│   ├── Setup.md            ← Hand-written
│   └── Configuration.md    ← Hand-written
└── Tests/                  ← Pester tests
```

**Rules:**
- Every PowerShell function lives in **its own `.ps1` file**, named exactly after the function (e.g. `Add-IcingaFirewallRule.ps1` contains `function Add-IcingaFirewallRule`).
- `Public/` = exported, user-facing. `Private/` = internal helpers, not exported.
- Files in `lib/` and `docs/api/` are **always regenerated** — manual edits will be lost.

---

## 2. PowerShell Code Style

### 2.1 The semicolon rule

> **Every non-function statement ends with a semicolon `;`.**

This includes `param` lines, assignments, pipeline ends, `return` statements, control-flow blocks (`if`, `switch`, `foreach`, `while`) — everything that is *not* the bare `function Name() { … }` declaration.

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

### 2.2 Function declaration

- Opening brace on its **own line** (Allman style), not K&R.
- Empty parentheses after the name (`function Foo()`), even when there is no positional binding — they make `param()` blocks visually consistent.
- `param()` block always uses one parameter per line with type prefix and default value.
- Param defaults use `= $null` for nullable refs, `= @()` for arrays, `= @{ }` for hashtables, `= $false` for switches.

### 2.3 Naming

| Kind                    | Convention                                            | Example |
|-------------------------|-------------------------------------------------------|---------|
| Public function         | `Verb-IcingaNoun` (approved PS verbs only)           | `Set-IcingaLogLevel` |
| Private helper          | `Verb-ModuleNoun` **or** `Verb-IcingaInternalNoun`   | `Read-ModuleAccessControl`, `Write-LoggingEntry` |
| Variable                | `PascalCase` with `$`                                 | `$ChatHistory`, `$WorkerId` |
| Loop counter            | lowercase                                             | `$i`, `$idx` |
| Type-annotated variable | `[Type]$Name = …`                                     | `[int]$WorkerId = -1` |
| Constants in `$Global:Icinga` | nested hashtables/PSCustomObjects under `Public/Private/Protected` | `$Global:Icinga.Public.AICore.Config` |

- **Approved PS verbs only** — run `Get-Verb` to check. Avoid `Process-`, `Validate-`, `Execute-`.
- **Never collide with PowerShell built-ins or other modules.** Prefix everything user-facing with `Icinga`.
- Acronyms keep their case: `RestApi`, `IcingaProtocol`, `AccessControl`.

### 2.4 Indentation and whitespace

- **4 spaces**, no tabs.
- One blank line between function body sections (init, processing, return).
- No trailing whitespace on any line.
- Files end with a single newline.

### 2.5 Global state access

`$Global:Icinga` is the shared runtime state, populated by `New-ModuleBaseEnvironment` in [IcingaForWindows.psm1](IcingaForWindows.psm1). Access patterns:

```powershell
# Inside a thread / worker — always go through Get-GlobalRuntimeVariable
$GlobalVariable = Get-GlobalRuntimeVariable;
$GlobalVariable.Public.RestApi.Config.ListenPort;

# Inside a normal function on the main thread, direct access is fine:
$Global:Icinga.Public.IcingaProtocol.Config.Hostname;
```

**Rule of thumb:** anything that runs inside `Start-*Daemon` or a worker thread **MUST** go through `Get-GlobalRuntimeVariable`, because thread runspaces receive a snapshot.

### 2.6 Return values and error handling

- Public functions: return the structured result the caller expects (object, hashtable, `$null`).
- Private functions that participate in the return-code system: use `Write-FunctionReturnValue -ReturnValue 'SemanticKey' -Data @{…}`.
- Never `throw` for expected error paths inside daemons. Log via `Write-LoggingEntry -Level 'Error'` and return `$null` / a structured error object so the worker can continue.
- `throw` is reserved for **programmer errors** (bad arguments, impossible state).

### 2.7 Logging

```powershell
Write-LoggingEntry -Message 'Short, present-tense description' -Level 'Info' -Data @{
    'ContextKey1' = $value1;
    'ContextKey2' = $value2;
};
```

Levels: `Debug`, `Output`, `Audit`, `Info`, `Success`, `Warning`, `Error`, `Fatal`. Use `Debug` for hot-loop telemetry, `Info` for state transitions, `Warning` for recoverable issues, `Error` for unhandled exceptions.

### 2.8 Forbidden constructs

- ❌ `Write-Host` outside of build scripts. Use `Write-LoggingEntry -Level 'Output'`.
- ❌ `Write-Output` for logging — use it only when you genuinely return a value to the pipeline.
- ❌ Stream redirects like `2>$null` or `*>&1`. Handle errors explicitly.
- ❌ Aliases in source code (`%`, `?`, `select`, `where`). Use full cmdlet names (`ForEach-Object`, `Where-Object`).
- ❌ Em-dashes (`—`, U+2014) or en-dashes (`–`, U+2013) in PowerShell files — Windows PowerShell 5.1 reads BOM-less UTF-8 files as Windows-1252 and turns them into `â€”` Mojibake. Use plain ASCII `-` or `--` instead.
- ❌ `-ErrorAction SilentlyContinue` as a "make the warning go away" tool. If you don't want to handle the error, that's a bug.
- ❌ Editing files under `lib/` or `docs/api/` by hand.
- ❌ Class literals in functions (`[IcingaPlugin]::new()`, `[IcingaSortKey]::FromObject()`, `-is [IcingaError]`). See §2.9.

### 2.9 Classes and threads

Every runspace dot-sources the same compiled kernel, while the classes from `src/Classes` are loaded separately into each runspace. A class literal inside a function is resolved once and then points to the class type of the **main** runspace — also when the function runs in a daemon or worker thread. On Windows PowerShell 5.1 a constructor, method or static call on that type from a thread waits until the main runspace is idle, so the thread stalls. Objects of the thread's own type also no longer match the literal: `-is` returns `$false` and typed parameters fail with *Cannot convert the "IcingaError" value of type "IcingaError" to type "IcingaError"*.

1. **Never use a class literal in a function** — not to create an object, not for a static member, not for `-is`, casts or typed variables and parameters. Resolve the class of the current runspace instead:

   | Instead of                           | Use |
   |--------------------------------------|-----|
   | `[IcingaPlugin]::new('C:', 55, '%')` | `New-IcingaPlugin 'C:' 55 '%'` |
   | `$Data -is [IcingaError]`            | `Test-IcingaError -InputObject $Data` |
   | `[IcingaError]::new(...)`            | `('IcingaError' -as [type])::new(...)` |
   | `[IcingaSortKey]::FromObject(...)` in a loop | `$SortKeyType = 'IcingaSortKey' -as [type];` once before the loop, then `$SortKeyType::FromObject(...)` |

2. Exceptions: code inside `src/Classes` (the class files are loaded per runspace, so literals there resolve correctly), Pester tests, and enums such as `[IcingaServiceStatus]::Running` — enums carry no script code and convert by value.
3. **Never pass class instances between threads.** Hand over only primitive values, hashtables and arrays. A plugin result travels as its rendered output, exit code and performance data array, never as the `IcingaCheckResult` object (see `Start-IcingaProtocolWorker`).
4. `Tests/ClassLiteral.Tests.ps1` enforces rule 1 and names the file and line of every literal it finds.

Background and examples: [docs/Developer/Threading/01-Threading.md](docs/Developer/Threading/01-Threading.md#classes-and-threads).

---

## 3. Comment-Based Help (the binding doc format)

Every function — **public AND private** — must carry a comment-based help block immediately before the `function` keyword. The block uses this exact structure:

> **Language rule:** All comment-based help — every `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.OUTPUTS`, `.EXAMPLE` and `.NOTES` section — **must be written in English**. No exceptions.

```powershell
<#
.SYNOPSIS
One-line summary. Imperative voice, no trailing period.

.DESCRIPTION
Detailed multi-line description. Cover what the function does, how it
fits into the larger workflow, any threading or networking behaviour,
and important side-effects (writes to global state, blocking I/O,
external dependencies).

.PARAMETER Name
| Name | Type          | Description                                | Default |
|------|---------------|--------------------------------------------|---------|
| Name | System.String | Display name of the resource to act on.    |         |

.PARAMETER Count
| Name  | Type         | Description                       | Default |
|-------|--------------|-----------------------------------|---------|
| Count | System.Int32 | Number of iterations to perform.  | 1       |

.OUTPUTS
System.Object -- Description of the returned value or object shape.
Use `None` if the function returns nothing.

.EXAMPLE
PS> Verb-IcingaNoun -Name 'Foo' -Count 3

Short prose describing what the example does, when useful.

.NOTES
Module-level dependencies (external services, credentials, config
files), required privileges, and any non-obvious side-effects.
#>
function Verb-IcingaNoun()
{
    …
}
```

### 3.1 Doc rules — strict

1. **All seven sections** are mandatory on **public** functions: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` (one per parameter), `.OUTPUTS`, `.EXAMPLE`, `.NOTES`.
2. **Private functions** must have at least `.SYNOPSIS` + `.DESCRIPTION`. `.PARAMETER`, `.OUTPUTS`, `.EXAMPLE`, `.NOTES` are required when the helper has parameters, returns a value, or has non-obvious side-effects — i.e. almost always.
3. **Every `.PARAMETER` block uses the Markdown table form** shown above. The table has exactly four columns: `Name | Type | Description | Default`. This is what the doc generator extracts.
4. `.SYNOPSIS` is **one line, no period at the end** unless it is a full sentence.
5. `.DESCRIPTION` wraps at ~80 columns. Use plain prose, not bullet lists.
6. `.OUTPUTS` starts with the .NET type name (`System.Int32`, `System.Collections.Hashtable`, `System.Object`, `None`), followed by `-- Description`.
7. `.EXAMPLE` begins with `PS> ` and shows a realistic invocation.
8. `.NOTES` mentions: external services touched, config files read, required permissions, threading caveats.
9. **All documentation is written in English.** No German (or any other language) in any help block section.

### 3.2 What you do **not** comment inline

- Don't restate what well-named code already says (`# increment counter` above `$i++`).
- Don't reference the current task, fix, or callers (`# used by X`, `# added for the Y flow`).
- Inline comments are reserved for the **why**: hidden constraints, workarounds for specific bugs, invariants that would surprise a future reader.

---

## 4. Build & Generated Artifacts

### 4.1 Compilation

`build/Build-ModuleProject.ps1` walks `src/`, concatenates the per-component `Private/` + `Public/` `.ps1` files into `lib/IcingaForWindows.<Component>.psm1`, and updates `NestedModules` + `FunctionsToExport` in `IcingaForWindows.psd1`.

Triggering a rebuild:
```powershell
Build-ModuleProject;        # compile + run Pester tests
Build-ModuleProject -SkipTests;
```

### 4.2 Documentation

`build/Build-ModuleDocs.ps1` walks `src/`, parses the comment-based help block of every `.ps1` file, and writes one Markdown file per component into `docs/api/`. Triggering:
```powershell
.\build\Build-ModuleDocs.ps1;                       # default: docs/api/
.\build\Build-ModuleDocs.ps1 -IncludePrivate:$false; # only Public functions
Build-ModuleProject -GenerateDocs;                   # compile + docs in one shot
```

**If a `.ps1` file is missing required help sections, the generator fails with a non-zero exit code and lists every offending file.** Fix the source — never paper over it in the generator.

---

## 5. Testing

- Pester ≥ 5 under `Tests/`.
- One `*.Tests.ps1` per public function, named after the function.
- Tests assume `Import-Module IcingaForWindows -Force -Global` has been called.
- Network/IcingaProtocol/ integration tests are **out of scope** for unit tests; mock at the function boundary or stage them separately.

---

## 6. Commits & Branching

- Default branch: `master`.
- Commit subjects in present-tense imperative ("Fix …", "Add …", "Update …"), one short line.
- Body explains **why**, not **what** — the diff already shows the what.
- Never amend pushed commits. Never force-push to `master`.
- Hooks must not be bypassed (`--no-verify`, `--no-gpg-sign`).

---

## 7. Cross-platform notes

- Target: PowerShell 7.5 on Windows 11 (primary) and Linux/macOS via the `$env:ProgramData` fallback in `IcingaForWindows.psm1`.
- Use `Join-Path` for every path concatenation. Never hardcode `\` or `/`.
- Path separators in `Build-ModuleProject.ps1` are normalised to `\` for the manifest section that lists nested modules — leave that logic alone.

---

## 8. AI Assistant Etiquette

When you (Claude, Copilot, etc.) edit this repo:

- **Match style exactly.** Look at a neighbouring file in the same component first.
- **Don't add backwards-compatibility shims** for code that hasn't shipped yet.
- **Don't introduce new abstractions** for a single caller. Inline beats premature reuse.
- **Don't widen surface area.** If the user asks for a fix, fix that — don't refactor surrounding code.
- **Don't commit unless explicitly asked.**
- **Don't run `Build-ModuleProject`** as part of "verification". It rewrites `lib/` and `IcingaForWindows.psd1` and is the user's call, not yours.
- **When in doubt, ask.** A one-line clarifying question beats a 200-line speculative change.

---

*Last updated: 2026-10-02*

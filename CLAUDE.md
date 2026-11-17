# CLAUDE.md -- Icinga for Windows AI Agent Entrypoint

@docs/Agents/guidelines/01-Instruction.md

All binding architecture, PowerShell code-style, SPDX licensing, runspace/threading safety, comment-based help, changelog/roadmap governance, testing, and feature task-tracking rules for **Icinga for Windows** are maintained in the central single source of truth:

- **Binding Ruleset (MUST READ FIRST):** [docs/Agents/guidelines/01-Instruction.md](docs/Agents/guidelines/01-Instruction.md)
- **Changelog & Roadmap Governance:** [docs/General/Changelog.md](docs/General/Changelog.md) · [docs/General/Roadmap.md](docs/General/Roadmap.md)
- **Per-Branch Feature Plans, Todos & Walkthroughs:** [docs/Agents/tasks/](docs/Agents/tasks/)
- **Knowledgebase (`IWKB001xxx`):** [docs/Knowledgebase/index.md](docs/Knowledgebase/index.md)

## Mandatory Quick Checklist

1. **Read [docs/Agents/guidelines/01-Instruction.md](docs/Agents/guidelines/01-Instruction.md) in full** before creating or modifying any file.
2. **100% English & prose naming:** Write all code, inline comments, help blocks, documentation, changelogs, roadmaps, and task plans 100% in English -- regardless of conversation language. Always write **"Icinga for Windows"** in prose and reserve **`IcingaForWindows`** strictly for technical module, file, path, and `$Global:IcingaForWindows` identifiers.
3. **Strict PowerShell house style & function scope:** UTF-8 without BOM, 4-space indentation, Allman braces on `function Name()`, trailing semicolons `;` on every non-function statement, single-line `if (...) {` conditions, vertical `=` alignment in assignment and hashtable blocks, vertical `|` alignment in `.PARAMETER` tables, and strictly one top-level function with zero nested functions per file under `src/` (helper/nested functions are permitted in `build/`, `IcingaForWindows.psm1`, and `Tests/`).
4. **Mandatory `.NOTES` & Icinga SPDX headers:** Every file under `src/`, `build/`, `Tests/`, and `IcingaForWindows.psm1` must carry `.NOTES` concluding with `SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>` and `SPDX-License-Identifier: GPL-3.0-or-later` (and `# SPDX-...` when commented outside `<# ... #>`, such as under `PrivateData.SPDX` in `IcingaForWindows.psd1`, in `PSScriptAnalyzerSettings.psd1`, and at the top of compiled `lib/` files).
5. **Runspace & daemon safety:** Never use PowerShell class literals from `src/Classes` inside functions (`Tests/ClassLiteral.Tests.ps1`), access runtime state in threads via `Get-GlobalRuntimeVariable`, and null loop variables in `finally` (`build/Test-ModuleDaemonMemoryLeak.ps1`).
6. **Validate & track before finishing:** Run `.\build\Test-ModuleCodeStyling.ps1` (`0` violations) and `.\build\Test-ModuleChangelog.ps1`, add an entry to `docs/General/Changelog.md` on every non-`main` branch, synchronize `docs/General/Roadmap.md` whenever creating or completing plans in `docs/Agents/tasks/<BranchSlug>/`, and persist `implementation_plan.md`, `todo.md`, and `walkthrough.md`.
7. **Never commit to Git** unless explicitly requested by the user.

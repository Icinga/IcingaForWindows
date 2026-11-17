# AGENTS.md -- Icinga for Windows AI Agent Entrypoint

All binding architecture, PowerShell code-style, SPDX licensing, runspace/threading safety, comment-based help, changelog/roadmap governance, testing, and feature task-tracking rules for **Icinga for Windows** are maintained in the central single source of truth:

- **Binding Ruleset (MUST READ FIRST):** [docs/Agents/guidelines/01-Instruction.md](docs/Agents/guidelines/01-Instruction.md)
- **Changelog & Roadmap Governance:** [docs/General/Changelog.md](docs/General/Changelog.md) · [docs/General/Roadmap.md](docs/General/Roadmap.md)
- **Per-Branch Feature Plans, Todos & Walkthroughs:** [docs/Agents/tasks/](docs/Agents/tasks/)
- **Knowledgebase (`IWKB001xxx`):** [docs/Knowledgebase/index.md](docs/Knowledgebase/index.md)

## Mandatory Instructions for All Coding Agents

1. **Read [docs/Agents/guidelines/01-Instruction.md](docs/Agents/guidelines/01-Instruction.md) first** before proposing or applying changes in this repository.
2. **100% English & prose naming:** Write all code, comments, help blocks, Markdown docs, changelogs, roadmaps, and task artifacts 100% in English. Always write **"Icinga for Windows"** in prose and reserve **`IcingaForWindows`** strictly for technical module, file, path, and `$Global:IcingaForWindows` identifiers.
3. **Strict PowerShell formatting & function scope:** UTF-8 without BOM, 4-space indentation, Allman `function Name()` braces, semicolons `;` ending every non-function statement, single-line `if`/`elseif` conditions, vertical `=` alignment across assignment and hashtable blocks, vertical `|` alignment in `.PARAMETER` tables, and at most **one** top-level function with **no** nested functions in `src/` (helper/nested functions are permitted in `build/`, `IcingaForWindows.psm1`, and `Tests/`).
4. **Mandatory `.NOTES` & Icinga SPDX headers:** Every file under `src/`, `build/`, `Tests/`, and `IcingaForWindows.psm1` must include `.NOTES` ending with `SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>` and `SPDX-License-Identifier: GPL-3.0-or-later` (and `# SPDX-...` when commented outside `<# ... #>`, such as under `PrivateData.SPDX` in `IcingaForWindows.psd1`, in `PSScriptAnalyzerSettings.psd1`, and at the top of compiled `lib/` artifacts).
5. **Threading & class isolation:** Never use PowerShell class literals from `src/Classes` inside functions (`Tests/ClassLiteral.Tests.ps1`), use `Get-GlobalRuntimeVariable` inside worker/daemon contexts, and null per-iteration variables in daemon `finally` blocks (`build/Test-ModuleDaemonMemoryLeak.ps1`).
6. **Validation, Changelog & Roadmap tracking:** Run `.\build\Test-ModuleCodeStyling.ps1` (`0` violations) and `.\build\Test-ModuleChangelog.ps1`, add a bullet entry to `docs/General/Changelog.md` on every non-`main` branch, synchronize `docs/General/Roadmap.md` whenever creating or completing plans under `docs/Agents/tasks/<BranchSlug>/`, and never hand-edit generated files under `lib/` or `docs/Icinga.*.md`.
7. **Do not commit to Git** unless explicitly instructed by the user.

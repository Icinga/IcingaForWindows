# GEMINI.md -- Icinga for Windows AI Agent Entrypoint

All binding architecture, PowerShell code-style, SPDX licensing, runspace/threading safety, comment-based help, changelog/roadmap governance, testing, and feature task-tracking rules for **Icinga for Windows** are maintained in the central single source of truth:

- **Binding Ruleset (MUST READ FIRST):** [docs/Agents/guidelines/01-Instruction.md](docs/Agents/guidelines/01-Instruction.md)
- **Changelog & Roadmap Governance:** [docs/General/Changelog.md](docs/General/Changelog.md) · [docs/General/Roadmap.md](docs/General/Roadmap.md)
- **Per-Branch Feature Plans, Todos & Walkthroughs:** [docs/Agents/tasks/](docs/Agents/tasks/)
- **Knowledgebase (`IWKB001xxx`):** [docs/Knowledgebase/index.md](docs/Knowledgebase/index.md)

## Mandatory Instructions for Gemini / Antigravity Agents

1. **Read [docs/Agents/guidelines/01-Instruction.md](docs/Agents/guidelines/01-Instruction.md) first** before planning or editing any file in this repository.
2. **100% English & prose naming:** Write all code, comments, help blocks, Markdown docs, changelogs, roadmaps, and `docs/Agents/tasks/<BranchSlug>/{implementation_plan,todo,walkthrough}.md` artifacts 100% in English -- even when the user writes in German or another language. Always write **"Icinga for Windows"** in prose and reserve **`IcingaForWindows`** strictly for technical module, file, path, and `$Global:IcingaForWindows` identifiers.
3. **Enforce PowerShell house style & function scope:** UTF-8 without BOM, 4-space indentation, Allman `function Name()` declarations, semicolons `;` on every non-function statement, single-line `if`/`elseif` conditions, vertically aligned `=` across assignment and hashtable blocks, vertically aligned `|` pipes in `.PARAMETER` help tables, and strictly one top-level function with zero nested functions per file under `src/` (helper/nested functions are permitted under `build/`, `IcingaForWindows.psm1`, and `Tests/`).
4. **Enforce `.NOTES` & Icinga SPDX headers:** Every file under `src/`, `build/`, `Tests/`, `IcingaForWindows.psm1`, and compiled `lib/` artifacts must carry `.NOTES` ending with `SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>` and `SPDX-License-Identifier: GPL-3.0-or-later` (and `# SPDX-...` when commented outside `<# ... #>`, such as under `PrivateData.SPDX` in `IcingaForWindows.psd1` and in `PSScriptAnalyzerSettings.psd1`).
5. **Enforce runspace & memory safety:** Never reference PowerShell classes from `src/Classes` via type literals inside functions (`Tests/ClassLiteral.Tests.ps1`), always use `Get-GlobalRuntimeVariable` in worker/daemon code, and null loop variables in `finally` (`build/Test-ModuleDaemonMemoryLeak.ps1`).
6. **Verify & persist governance artifacts:** Validate with `.\build\Test-ModuleCodeStyling.ps1` (`0` violations) and `.\build\Test-ModuleChangelog.ps1`, add an entry to `docs/General/Changelog.md` on every non-`main` branch, synchronize `docs/General/Roadmap.md` whenever creating or completing plans in `docs/Agents/tasks/<BranchSlug>/`, and maintain `implementation_plan.md`, `todo.md`, and `walkthrough.md`.
7. **Do not create Git commits** unless the user explicitly asks you to commit.

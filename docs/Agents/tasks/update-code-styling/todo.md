# Task Checklist -- `update-code-styling`

## Completed Tasks

- [x] **Branch Setup & Agent Guidelines (`docs/Agents/guidelines/01-Instruction.md`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`)**
  - Created `feature/update-code-styling` from `main` (`3f7fa6e`) and initialized `docs/Agents/tasks/update-code-styling/`.
  - Anchored all five binding rules in `docs/Agents/guidelines/01-Instruction.md` and synchronized `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, and `.github/copilot-instructions.md`:
    1. `"Icinga for Windows"` prose naming vs. `IcingaForWindows` technical identifiers.
    2. Strictly one top-level function and zero nested functions per file under `src/` (helper/nested functions permitted in `build/`, `IcingaForWindows.psm1`, and `Tests/`).
    3. Mandatory `.NOTES` concluding with the two Icinga GmbH `GPL-3.0-or-later` SPDX lines across all PowerShell files.
    4. Mandatory changelog bullet entry in `docs/General/Changelog.md` on every non-`main` branch / Pull Request.
    5. Mandatory synchronization of `docs/General/Roadmap.md` whenever creating or completing task plans under `docs/Agents/tasks/<BranchSlug>/`.
- [x] **Manifest, Bootstrap, Compiler & Doc Generator (`IcingaForWindows.psd1`, `IcingaForWindows.psm1`, `build/Build-ModuleProject.ps1`, `build/Build-ModuleDocs.ps1`)**
  - Updated `IcingaForWindows.psd1` `Copyright` from `MIT` to `GPL-3.0-or-later`, updated `LicenseUri` to `blob/main/LICENSE`, aligned all hashtable `=` columns with trailing semicolons, and added `PrivateData.SPDX` plus the two-line SPDX block comment beneath `Endpoint`.
  - Added SPDX lines to `.NOTES` across all documented bootstrap functions in `IcingaForWindows.psm1` and aligned prose naming.
  - Added complete comment-based help + SPDX lines and `-TestCodeStyling` support to `build/Build-ModuleProject.ps1`, emitted top-of-file SPDX headers in `lib/IcingaForWindows.{Classes,Kernel}.ps1`, and switched artifact writing to BOM-less `UTF8Encoding($false)`.
  - Updated `build/Build-ModuleDocs.ps1` to enforce `.NOTES` + SPDX lines across all `198` `Public` and `Private` functions, strip `SPDX-...` lines from rendered `#### Notes` Markdown, compute accurate relative `*Source:*` links (`../src/...`), and restrict cleanup in `docs/` to `Icinga.*.md` and `index.md`.
- [x] **Full-Repository Code-Styling & SPDX Remediation (`src/`, `build/`, `Tests/`)**
  - Upgraded `build/Test-ModuleCodeStyling.ps1` to scan `src/`, `build/`, `Tests/`, root `*.ps1`/`*.psm1`/`*.psd1` (`IcingaForWindows.psm1`, `IcingaForWindows.psd1`, `PSScriptAnalyzerSettings.psd1`), and compiled `lib/` SPDX headers by default, enforcing `src/` vs. `build/` function/type scope rules and mandatory concluding `.NOTES` + SPDX headers.
  - Remediated all `208` files in `src/` (`0` violations; verified `0` non-comment/non-newline AST token differences against `main`), all `7` scripts in `build/` (`0` violations), and all `38` test suites in `Tests/` (`0` violations).
  - Refactored `Tests/CodeStyling.Tests.ps1` (`6` tests) to fast `$TestDrive` unit tests (~250ms) so CI never scans the repository twice.
- [x] **Changelog, Roadmap & CI Governance (`docs/General/{Changelog,Roadmap}.md`, `build/Test-ModuleChangelog.ps1`, `Tests/Changelog.Tests.ps1`, `.github/workflows/ci.yml`)**
  - Created `docs/General/Changelog.md` and `docs/General/Roadmap.md` covering completed `27.0.0` milestones and prioritized (`1` - `4`) planned work.
  - Implemented `build/Test-ModuleChangelog.ps1` (enforcing net-new `* ` bullet additions against merge-base) and synthetic Git `$TestDrive` unit tests in `Tests/Changelog.Tests.ps1` (`6` tests).
  - Integrated `Test-ModuleCodeStyling.ps1` and `Test-ModuleChangelog.ps1` alongside `Invoke-ScriptAnalysis.ps1` inside the `analyze` job of `.github/workflows/ci.yml` (`fetch-depth: 0`), plus targeted `lib/` SPDX validation in the `build` job.
- [x] **`README.md` Overhaul & Prose Naming Audit**
  - Rewrote `README.md` in English with subsystem summaries, Mermaid runtime and CI pipeline diagrams, verified Quick Start and `New-IcingaPlugin` SDK examples, developer validation commands, documentation map, and `GPL-3.0-or-later` licensing.
  - Audited all hand-written Markdown docs and source help blocks for strict `"Icinga for Windows"` prose naming and regenerated all `20` `docs/Icinga.*.md` + `docs/index.md` files (`0` broken relative links across all `52` Markdown files).
- [x] **Windows PowerShell 5.1 BOM-Less CP1252 & UNC Share Hardening**
  - Eliminated all literal non-ASCII characters (`> 0x7F`, including `U+2192` `->`, box-drawing glyphs, ellipses, and emojis whose UTF-8 continuation bytes `0x91`-`0x94` are lexed as smart-quote string delimiters in Windows PowerShell 5.1 when dot-sourcing BOM-less `.ps1` files) across `src/`, `build/`, and compiled `lib/`.
  - Enforced strict 7-bit ASCII (`0x00`-`0x7F`) across all PowerShell source, build, test, manifest, and compiled `lib/` files in `build/Test-ModuleCodeStyling.ps1` and `Tests/CodeStyling.Tests.ps1`.
  - Replaced chunk-unsafe `FileStream.Read` in `build/Build-ModuleProject.ps1` with `[System.IO.File]::ReadAllText`, added alphabetical sorting for `Private` and `Public` kernel files, enforced Pester 5.0+ `New-PesterConfiguration` in Step `[5/5]`, and normalized `Resolve-Path` via `.ProviderPath` across `build/` and `Tests/` for UNC paths (`\\Mac\Home\...`).

---

## Open Points & Known Limitations

- [ ] **Windows-Only OS API Integration Suites (`17` Tests on macOS):**
  `Get-IcingaPerformanceCounter.Tests.ps1` (`14` tests using `System.Diagnostics.PerformanceCounter`), `MemoryLeak.Tests.ps1` (`2` tests using `New-SelfSignedCertificate`), and `Get-IcingaDirectoryInformation.Tests.ps1` (`1` test using `WindowsPrincipal::GetCurrent()`) require native Windows APIs and execute in the `windows-latest` GitHub Actions runner (`test` job). All `489` cross-platform Pester tests pass locally on macOS.
- [ ] **Follow-Up Functional & Security Branches:**
  Execute queued Priority 1 REST API, approved-path boundary, TLS certificate, and `IcingaProtocol` netstring/socket concurrency milestones tracked in [Roadmap.md](../../../General/Roadmap.md) on dedicated branches after `feature/update-code-styling` is merged.

---

## Next Steps

1. Merge `feature/update-code-styling` via Pull Request once the `windows-latest` GitHub Actions `analyze`, `build`, `docs`, `memory`, and `test` jobs pass end-to-end.

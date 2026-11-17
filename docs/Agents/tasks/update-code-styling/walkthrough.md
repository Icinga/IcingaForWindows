# Implementation Walkthrough -- Holistic Code-Styling, SPDX Licensing, Documentation & Governance (`update-code-styling`)

## 1. Executive Summary

Delivered complete code-styling, `GPL-3.0-or-later` SPDX licensing, changelog/roadmap governance, CI integration, and English architecture documentation across **Icinga for Windows** on branch `feature/update-code-styling`:

1. **Zero-Exemption Code Styling Across 255+ PowerShell Files:** Brought all `208` source files in `src/`, `7` build scripts in `build/`, `38` test files in `Tests/`, `IcingaForWindows.psm1`, `IcingaForWindows.psd1`, and `PSScriptAnalyzerSettings.psd1` to **`0` violations** in [build/Test-ModuleCodeStyling.ps1](../../../../build/Test-ModuleCodeStyling.ps1), with mathematically verified **zero** non-comment/non-newline AST token changes across all `208` `src/*.ps1` files compared to `main` (`3f7fa6e`).
2. **End-to-End `GPL-3.0-or-later` SPDX Licensing:** Added mandatory `.NOTES` sections concluding with the two Icinga GmbH SPDX lines across `src/`, `build/`, `Tests/`, and `IcingaForWindows.psm1`; updated [IcingaForWindows.psd1](../../../../IcingaForWindows.psd1) (`Copyright` -> `GPL-3.0-or-later`, `LicenseUri` -> `blob/main/LICENSE`, `PrivateData.SPDX`); and updated [build/Build-ModuleProject.ps1](../../../../build/Build-ModuleProject.ps1) to emit BOM-less UTF-8 `lib/IcingaForWindows.{Classes,Kernel}.ps1` artifacts with top-of-file SPDX headers.
3. **Changelog, Roadmap & Single-Run CI Gates:** Added [docs/General/Changelog.md](../../../General/Changelog.md), [docs/General/Roadmap.md](../../../General/Roadmap.md), [build/Test-ModuleChangelog.ps1](../../../../build/Test-ModuleChangelog.ps1), and fast `$TestDrive` unit suites in [Tests/CodeStyling.Tests.ps1](../../../../Tests/CodeStyling.Tests.ps1) and [Tests/Changelog.Tests.ps1](../../../../Tests/Changelog.Tests.ps1), wiring both repository gates alongside `PSScriptAnalyzer` inside the `analyze` job of [.github/workflows/ci.yml](../../../../.github/workflows/ci.yml) without duplicate scans.
4. **English `README.md` & `"Icinga for Windows"` Prose Naming:** Rewrote [README.md](../../../../README.md) with Mermaid runtime and CI governance diagrams, audited all hand-written documentation and source help blocks for strict `"Icinga for Windows"` prose naming, and regenerated all `20` API reference files via [build/Build-ModuleDocs.ps1](../../../../build/Build-ModuleDocs.ps1).

---

## 2. Under-the-Hood Deep Dive

### 2.1 Scoped Function Rules & SPDX Enforcement (`build/Test-ModuleCodeStyling.ps1`)
- **Default Repository Scope:** When invoked without `-Path` or `-SourceFolder`, `Test-ModuleCodeStyling.ps1` automatically validates `src/`, `build/`, `Tests/`, all root `*.ps1`/`*.psm1`/`*.psd1` files (`IcingaForWindows.psm1`, `IcingaForWindows.psd1`, `PSScriptAnalyzerSettings.psd1`), and (when `lib/` exists) the BOM-less UTF-8 encoding and top-of-file SPDX header of `lib/IcingaForWindows.{Classes,Kernel}.ps1`.
- **`src/` vs. `build/` Function & Type Scope Rule:** AST inspection of `FunctionDefinitionAst` and `TypeDefinitionAst` nodes enforces exactly **one** top-level function, **zero** nested functions, and **zero** stray `class`/`enum` definitions per file in `src/` outside `src/Classes/` (and zero standalone functions in `src/Classes/`), while permitting internal helper and nested functions in `build/`, `IcingaForWindows.psm1`, and `Tests/`.
- **`.NOTES` & SPDX Validation:** Verifies that every function in `src/`, every top-level `class`/`enum` in `src/Classes/`, and every comment-based help block in `IcingaForWindows.psm1`, `build/*.ps1`, and `Tests/*.Tests.ps1` concludes `.NOTES` with `SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>` followed by `SPDX-License-Identifier: GPL-3.0-or-later` (and `# SPDX-...` comments in `.psd1` files and at the top of compiled `lib/` artifacts).

### 2.2 Non-`main` PR Changelog & Roadmap Gate (`build/Test-ModuleChangelog.ps1`)
- Validates UTF-8 without BOM encoding and required Markdown sections in `docs/General/Changelog.md` and `docs/General/Roadmap.md`.
- Detects `main` pushes (`GITHUB_REF_NAME=main` or local `HEAD == main`) vs. feature branches and GitHub Actions `pull_request` runs (`GITHUB_EVENT_NAME=pull_request` / `GITHUB_BASE_REF`, including non-`main` release base branches).
- Computes `git merge-base <BaseRef> HEAD` and compares `MergeBase` against the working-tree `docs/General/Changelog.md`, requiring at least one **net-new** `* ...` bullet entry (`AddedBulletCount > RemovedBullets`) so merely rewording or deleting existing bullets cannot bypass the gate.

### 2.3 Strict Doc Generator & BOM-Free Compiler (`Build-ModuleDocs.ps1` & `Build-ModuleProject.ps1`)
- `Build-ModuleDocs.ps1` requires `.NOTES` + both SPDX lines on all `198` `Public` and `Private` functions in `src/`, strips the machine-readable `SPDX-...` lines when rendering `#### Notes` into `docs/Icinga.*.md`, computes exact relative `*Source:*` links (`../src/...`) from `OutputPath` to `ModuleBasePath`, and cleans only `Icinga.*.md` and `index.md` inside `docs/`.
- `Build-ModuleProject.ps1` writes `lib/IcingaForWindows.Classes.ps1` and `lib/IcingaForWindows.Kernel.ps1` using `System.Text.UTF8Encoding($false)` (preventing Windows PowerShell 5.1 `Set-Content -Encoding UTF8` from inserting UTF-8 BOM bytes) with the two SPDX lines at lines 2-3 of each artifact, sorts `Classes`, `Private`, and `Public` files deterministically across filesystems, reads sources via SMB-safe `[System.IO.File]::ReadAllText`, and explicitly imports Pester 5.0+ with `New-PesterConfiguration`.
- **Windows PowerShell 5.1 CP1252 Quote-Lexer & UNC Path Safeguard:** Because Windows PowerShell 5.1 reads BOM-less `.ps1` files via Windows-1252 (where UTF-8 continuation bytes `0x91`-`0x94` such as `0x92` inside `U+2192` `->` are lexed as closing smart quotes `'`), all `258` PowerShell files across `src/`, `build/`, `Tests/`, root, and `lib/` are strictly 7-bit ASCII (`0x00`-`0x7F`, enforced by `Test-ModuleCodeStyling.ps1`), runtime console tree glyphs use `[char]0x2514` / `[char]0x2500`, and `Resolve-Path` calls combine `[System.IO.Path]::GetFullPath((Resolve-Path ...).ProviderPath)` to strip `FileSystem::` provider prefixes and collapse `\..\` segments on UNC shares (`\\Mac\Home\...`).

---

## 3. Verification Results

All build, documentation, styling, changelog, static-analysis, AST token-equivalence, link-validation, and Pester checks were executed on PowerShell 7.7.0 / Pester 6.1.0:

- **AST Executable Token-Stream Equivalence (`src/` vs. `main` `3f7fa6e`):**
  `208 / 208` `src/*.ps1` files verified with **`0` non-comment, non-newline PowerShell token differences** and **`0` deleted inline comments** against `main`.
- **Module Compilation & AST Daemon Memory-Leak Check:**
  `.\build\Build-ModuleProject.ps1 -SkipTests -TestDaemonMemoryLeaks` -> Compiled `10` classes, `156` private functions, and `42` public functions into BOM-less `lib/IcingaForWindows.{Classes,Kernel}.ps1` with top SPDX headers and **`0` daemon memory leaks**.
- **Module Manifest Validation:**
  `Test-ModuleManifest -Path .\IcingaForWindows.psd1` & `Import-PowerShellDataFile` -> `IcingaForWindows v27.0.0`, `Copyright = '(c) 2026 Icinga GmbH | GPL-3.0-or-later'`, `PrivateData.SPDX` present.
- **Strict API Documentation Build:**
  `.\build\Build-ModuleDocs.ps1 -Strict $true` -> Parsed `208` files (`198` functions across `19` components), wrote `20` Markdown files with **`0` violations**.
- **Repository-Wide Code-Styling & SPDX Gate:**
  `.\build\Test-ModuleCodeStyling.ps1` -> **`0` violations** across all `src/`, `build/`, `Tests/`, `IcingaForWindows.psm1`, `IcingaForWindows.psd1`, `PSScriptAnalyzerSettings.psd1`, and `lib/` files (verified under both LF and simulated Windows CRLF checkouts).
- **Changelog & Roadmap Governance Gate:**
  `.\build\Test-ModuleChangelog.ps1` -> **Passed (`0` violations)** on `feature/update-code-styling`.
- **`PSScriptAnalyzer` Static Analysis:**
  `.\build\Invoke-ScriptAnalysis.ps1 -FailOn 'Warning'` -> **`0` build-breaking findings**.
- **Pester Unit Test Suite (`38` Test Files / `508` Tests):**
  - `Tests/CodeStyling.Tests.ps1`: **`6 / 6` passed** (`$TestDrive` fixtures only; zero duplicate repo scan).
  - `Tests/Changelog.Tests.ps1`: **`6 / 6` passed** (`$TestDrive` synthetic Git repos, including net-new bullet and non-`main` `GITHUB_BASE_REF` checks).
  - Full suite (`.\build\Invoke-ModuleTests.ps1`): **`491` passed** (`479` baseline + `12` new governance unit tests; `0` regressions; `17` pre-existing Windows-only `PerformanceCounter` / `New-SelfSignedCertificate` / `WindowsPrincipal` OS API tests fail as expected on macOS).
- **Relative Markdown Link Audit:**
  Validated all `52` Markdown files across root and `docs/` (both hand-written and generated `docs/Icinga.*.md`) -> **`0` broken relative links**.

---

## 4. Practical Examples

```powershell
# Run full repository code-styling and SPDX validation
.\build\Test-ModuleCodeStyling.ps1;

# Validate PR / feature-branch changelog entry and Roadmap structure
.\build\Test-ModuleChangelog.ps1;

# Run fast unit tests for both governance validators (~2s total)
Invoke-Pester -Path .\Tests\CodeStyling.Tests.ps1, .\Tests\Changelog.Tests.ps1;
```

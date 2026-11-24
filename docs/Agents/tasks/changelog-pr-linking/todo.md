# Task Checklist -- `changelog-pr-linking`

## Completed Tasks

- [x] **Branch Setup & Isolation**
  - Verified clean working tree on `feature/install-icinga-for-windows`, switched cleanly to `main` (`c4c0c0a`), fast-forwarded from `origin/main`, and created `feature/changelog-pr-linking` without PR `#25` while leaving all existing `git stash` entries untouched.
- [x] **Zero-Credential PR Link Updater ([build/Update-ModuleChangelog.ps1](../../../../build/Update-ModuleChangelog.ps1))**
  - Implemented `Update-ModuleChangelog.ps1` with full comment-based help, aligned `.PARAMETER` tables, `.NOTES` + Icinga GmbH `GPL-3.0-or-later` SPDX header, UTF-8 `ProcessStartInfo` `git` execution, and strict 7-bit ASCII PowerShell 5.1 / 7+ compatibility.
  - Added canonical `ProjectUri` resolution from [IcingaForWindows.psd1](../../../../IcingaForWindows.psd1), closest `merge-base` selection across `upstream/main`, `origin/main`, and `main`, `$env:GITHUB_EVENT_PATH` detection, fork-aware unauthenticated GitHub REST API lookup (`/commits/<sha>/pulls`, `/pulls?state=open&head=<owner>:<branch>`, and bounded ancestor fallback), top-level bullet + code-fence scoping, strict parity checks against malformed/historical-only/zero-net-new bullets, CRLF/LF preservation, and `-SyncHistory` backfill mode.
- [x] **Two-Stage Pre-Merge Validator ([build/Test-ModuleChangelog.ps1](../../../../build/Test-ModuleChangelog.ps1))**
  - Added `-PullRequestNumber` and `-RepositoryUrl` parameters, closest `merge-base` resolution (`upstream/main`, `origin/main`, `main`), UTF-8 `ProcessStartInfo` `git` execution, top-level bullet + code-fence scoping (preserving indented sub-bullets), hyphen-bullet hints, and automatic `pull_request.number` detection from `$env:GITHUB_EVENT_PATH`.
  - Preserved frictionless local pre-PR validation (`$PullRequestNumber -le 0`) while enforcing valid `[#<PR>](.../pull/<PR>) <Summary>` prefixes on every added top-level bullet and active `[#<PullRequestNumber>](...)` presence in Pull Request mode, with clear `Update-ModuleChangelog.ps1` remediation output.
- [x] **GitHub Actions Auto-Link & Gate Workflow ([.github/workflows/ci.yml](../../../../.github/workflows/ci.yml))**
  - Added `changelog-link` job restricted to internal non-`main` `pull_request` runs using only the ephemeral per-job `GITHUB_TOKEN`, safe `env:` variable passing, and `github-actions[bot]` noreply identity.
  - Sequenced `analyze` (`needs: [changelog-link]`) and configured conditional `head.ref` checkout on internal repository PRs so `Test-ModuleChangelog.ps1` validates the post-`changelog-link` branch head on the initial PR run while preserving default `$GITHUB_SHA` checkouts on external fork PRs and `main` pushes.
- [x] **Historical Backfill, Documentation & Roadmap Sync**
  - Executed `.\build\Update-ModuleChangelog.ps1 -SyncHistory` on [docs/General/Changelog.md](../../../General/Changelog.md) to backfill `[#24]`, `[#23]`, `[#22]`, `[#20]`, and `[#19]` (attributing the two `3f7fa6e` security items accurately to `[#22]` and preserving direct commit `c678e4f`), and added the unlinked enhancement entry for `feature/changelog-pr-linking`.
  - Updated [docs/General/Roadmap.md](../../../General/Roadmap.md), [docs/Agents/guidelines/01-Instruction.md](../../guidelines/01-Instruction.md), and [README.md](../../../../README.md).
- [x] **Offline `$TestDrive` Pester Unit Tests ([Tests/Changelog.Tests.ps1](../../../../Tests/Changelog.Tests.ps1))**
  - Isolated `$env:GITHUB_EVENT_PATH` in `BeforeEach`/`AfterEach` so live GitHub Actions PR runs never pollute synthetic local-mode tests.
  - Added `9` new `It` blocks (`15` total tests in `Tests/Changelog.Tests.ps1`) covering PR mode failure cases, `$env:GITHUB_EVENT_PATH` auto-detection, historical backfills alongside active PR links, multi-section stamping, CRLF preservation, custom `RepositoryUrl` normalization, brand-new `Changelog.md` files, nested sub-bullets + code fences + `++` hunk lines, `Update`/`Test` rejection parity, `upstream/main` vs. stale local `main` fork resolution, mocked fork PR discovery, `-SyncHistory`, and byte-for-byte idempotency.

---

## Known Limitations & Open Points

- [ ] **GitHub `GITHUB_TOKEN` Check-Suite Association on Newly Pushed Bot Commits (Platform Behavior):**
  While `analyze` checks out the updated internal PR head branch and passes green on the initial workflow run, commits pushed by `GITHUB_TOKEN` do not trigger a separate `pull_request` `synchronize` check suite on the newly created bot commit SHA. If repository branch-protection rules require status checks attached specifically to the latest head SHA, pushing a follow-up commit, closing/reopening the PR, or running `.\build\Update-ModuleChangelog.ps1` locally avoids a separate bot commit.
- [ ] **Live GitHub Actions Workflow Run Verification:**
  End-to-end execution of the `changelog-link` -> `analyze` job sequence on GitHub's hosted runners requires pushing `feature/changelog-pr-linking` and opening the Pull Request on GitHub.
- [ ] **Open PR `#25` (`feature/install-icinga-for-windows`):**
  Deliberately excluded from this branch per user instruction while `#25` remains under testing; once merged or rebased onto `main`, `#25` will automatically inherit the PR changelog link workflow.

---

## Next Steps

1. Review the uncommitted changes on `feature/changelog-pr-linking`, commit, push `origin feature/changelog-pr-linking` (leaving the new changelog bullet initially unlinked), and open the Pull Request on GitHub to verify the live `changelog-link` job stamps `[#<PR>](...)` automatically with zero credentials.

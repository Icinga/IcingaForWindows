<#
.SYNOPSIS
Fast Pester unit test suite for the Icinga for Windows Changelog and Roadmap validators

.DESCRIPTION
Validates `build/Test-ModuleChangelog.ps1` and `build/Update-ModuleChangelog.ps1`
against isolated synthetic Git repositories in `$TestDrive` with zero network calls.
Tests `main` branch exemption, non-`main` branch failure when no bullet entry is
added, committed and working-tree bullet detection on feature branches, two-stage
Pull Request link enforcement (`-PullRequestNumber` and `$env:GITHUB_EVENT_PATH`),
multi-section PR link stamping, idempotency, UTF-8 without BOM preservation, and
structural validation of `docs/General/Changelog.md` and `docs/General/Roadmap.md`.

.NOTES
Executes purely against `$TestDrive` fixtures so CI never runs repository checks twice.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>

$ModulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Test-ModuleChangelog Governance Rules' {
    BeforeAll {
        $script:ModuleRoot      = [System.IO.Path]::GetFullPath((Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath);
        $script:ChangelogScript = Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'build') -ChildPath 'Test-ModuleChangelog.ps1';
        $script:UpdateScript    = Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'build') -ChildPath 'Update-ModuleChangelog.ps1';
        $script:Utf8NoBom       = New-Object System.Text.UTF8Encoding($false);

        function Invoke-QuietGit()
        {
            param (
                [string]$RepoPath  = '',
                [string[]]$GitArgs = @()
            );

            & git -C $RepoPath @GitArgs | Out-Null;
        }

        function New-SyntheticGovernanceRepo()
        {
            param (
                [string]$RepoName = 'TestRepo'
            );

            [string]$RepoPath      = Join-Path -Path $TestDrive -ChildPath $RepoName;
            [string]$GeneralDir    = Join-Path -Path $RepoPath -ChildPath (Join-Path -Path 'docs' -ChildPath 'General');
            New-Item -Path $GeneralDir -ItemType Directory -Force | Out-Null;

            [string]$BaseChangelog = @(
                '# Icinga for Windows Changelog',
                '',
                '## 27.0.0 (Unreleased)',
                '',
                '### Enhancements',
                '',
                '* Initial baseline changelog entry for unit testing',
                ''
            ) -join "`n";

            [string]$BaseRoadmap   = @(
                '# Icinga for Windows Roadmap',
                '',
                '## Completed Milestones & Subsystems',
                '',
                '| Status | Subsystem | Summary |',
                '| ------ | --------- | ------- |',
                '| Completed | Core | Baseline |',
                '',
                '## Feature List & Planned Work',
                '',
                '| Priority | Scenario | Description |',
                '| -------- | -------- | ----------- |',
                '| 1 | Hardening | Planned |',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText((Join-Path -Path $GeneralDir -ChildPath 'Changelog.md'), $BaseChangelog, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText((Join-Path -Path $GeneralDir -ChildPath 'Roadmap.md'), $BaseRoadmap, $script:Utf8NoBom);

            Invoke-QuietGit -RepoPath $RepoPath -GitArgs @( 'init', '-q', '-b', 'main' );
            Invoke-QuietGit -RepoPath $RepoPath -GitArgs @( 'config', 'user.name', 'Icinga Test' );
            Invoke-QuietGit -RepoPath $RepoPath -GitArgs @( 'config', 'user.email', 'test@icinga.com' );
            Invoke-QuietGit -RepoPath $RepoPath -GitArgs @( 'config', 'commit.gpgsign', 'false' );
            Invoke-QuietGit -RepoPath $RepoPath -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $RepoPath -GitArgs @( 'commit', '-q', '-m', 'Initial main commit' );

            return $RepoPath;
        }
    }

    BeforeEach {
        $script:SavedEventName = $env:GITHUB_EVENT_NAME;
        $script:SavedEventPath = $env:GITHUB_EVENT_PATH;
        $script:SavedRefName   = $env:GITHUB_REF_NAME;
        $script:SavedBaseRef   = $env:GITHUB_BASE_REF;

        $env:GITHUB_EVENT_NAME = $null;
        $env:GITHUB_EVENT_PATH = $null;
        $env:GITHUB_REF_NAME   = $null;
        $env:GITHUB_BASE_REF   = $null;
    }

    AfterEach {
        $env:GITHUB_EVENT_NAME = $script:SavedEventName;
        $env:GITHUB_EVENT_PATH = $script:SavedEventPath;
        $env:GITHUB_REF_NAME   = $script:SavedRefName;
        $env:GITHUB_BASE_REF   = $script:SavedBaseRef;
    }

    Context 'Branch and Pull Request changelog enforcement' {
        It 'passes on main branch without requiring new diff entries' {
            [string]$Repo      = New-SyntheticGovernanceRepo -RepoName 'MainPassRepo';
            [array]$Violations = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $Violations | Should -BeNullOrEmpty;
        }

        It 'fails on a non-main branch when no bullet entry was added to Changelog.md' {
            [string]$Repo      = New-SyntheticGovernanceRepo -RepoName 'FeatureFailRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/missing-changelog' );
            [string]$Dummy     = Join-Path -Path $Repo -ChildPath 'dummy.txt';
            [System.IO.File]::WriteAllText($Dummy, "change`n", $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'Add feature without changelog' );

            [array]$Violations = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            ($Violations -join "`n") | Should -Match 'Missing changelog entry';

            # Also verify non-PassThru mode throws the expected message
            { & $script:ChangelogScript -ModuleBasePath $Repo } | Should -Throw '*Missing changelog entry*';
        }

        It 'rejects non-bullet edits to Changelog.md and passes once a real "* " bullet is added' {
            [string]$Repo               = New-SyntheticGovernanceRepo -RepoName 'FeatureBulletRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/with-bullet' );
            [string]$ClPath             = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));

            # Prose-only edit without "* " bullet must still fail
            [string]$Current            = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            [System.IO.File]::WriteAllText($ClPath, ($Current + "`nSome non-bullet note.`n"), $script:Utf8NoBom);
            [array]$BadViolations       = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            ($BadViolations -join "`n") | Should -Match 'Missing changelog entry';

            # Uncommitted working-tree "* " bullet passes
            [System.IO.File]::WriteAllText($ClPath, ($Current + "* Adds new feature on working tree`n"), $script:Utf8NoBom);
            [array]$WtViolations        = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $WtViolations | Should -BeNullOrEmpty;

            # Committed "* " bullet continues to pass even after main advances independently
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'Document feature in Changelog' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', 'main' );
            [System.IO.File]::WriteAllText((Join-Path -Path $Repo -ChildPath 'other.txt'), "main advance`n", $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'Advance main' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', 'feature/with-bullet' );

            [array]$CommittedViolations = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $CommittedViolations | Should -BeNullOrEmpty;
        }

        It 'enforces changelog entry in simulated GitHub Actions pull_request detached HEAD runs and non-main base refs' {
            [string]$Repo          = New-SyntheticGovernanceRepo -RepoName 'CiPrRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'branch', 'support/27.0', 'main' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/pr-check', 'support/27.0' );
            [System.IO.File]::WriteAllText((Join-Path -Path $Repo -ChildPath 'pr.txt'), "pr`n", $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'PR commit without changelog' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '--detach', 'HEAD' );

            $env:GITHUB_EVENT_NAME = 'pull_request';
            $env:GITHUB_BASE_REF   = 'support/27.0';

            [array]$Violations     = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            ($Violations -join "`n") | Should -Match 'Missing changelog entry';

            # Adding a bullet against support/27.0 passes
            [string]$ClPath        = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$Existing      = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            [System.IO.File]::WriteAllText($ClPath, ($Existing + "* Adds backport fix for 27.0`n"), $script:Utf8NoBom);
            [array]$PassViolations = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $PassViolations | Should -BeNullOrEmpty;
        }

        It 'rejects rewording or deleting existing bullets when no net-new bullet is added' {
            [string]$Repo           = New-SyntheticGovernanceRepo -RepoName 'RewordBypassRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/reword-only' );
            [string]$ClPath         = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$Original       = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);

            # Merely rewording the baseline bullet (+1 / -1 = 0 net bullets) must fail
            [string]$Reworded       = $Original.Replace('* Initial baseline changelog entry for unit testing', '* Initial baseline changelog entry with typo fix');
            [System.IO.File]::WriteAllText($ClPath, $Reworded, $script:Utf8NoBom);
            [array]$RewordViolation = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            ($RewordViolation -join "`n") | Should -Match 'Missing changelog entry';

            # Rewording an existing bullet AND adding a new bullet (+2 / -1 = +1 net bullet) passes
            [System.IO.File]::WriteAllText($ClPath, ($Reworded + "* Adds genuine branch changelog entry`n"), $script:Utf8NoBom);
            [array]$NetNewPass      = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $NetNewPass | Should -BeNullOrEmpty;
        }
    }

    Context 'Two-stage Pull Request link enforcement' {
        It 'fails in PR mode when added bullets are unlinked or omit the active PR link and emits Update-ModuleChangelog remediation' {
            [string]$Repo              = New-SyntheticGovernanceRepo -RepoName 'PrModeFailRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/pr-link-gate' );
            [string]$ClPath            = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$Baseline          = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);

            # Unlinked bullet passes locally ($PullRequestNumber = 0)
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* Adds feature without PR link yet`n"), $script:Utf8NoBom);
            [array]$LocalViolations    = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $LocalViolations | Should -BeNullOrEmpty;

            # Same unlinked bullet fails in PR #42 mode with remediation command
            [array]$UnlinkedViolations = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 42 -PassThru;
            [string]$UnlinkedText      = ($UnlinkedViolations -join "`n");
            $UnlinkedText | Should -Match 'Unlinked changelog entry';
            $UnlinkedText | Should -Match 'Missing Pull Request #42 link';
            $UnlinkedText | Should -Match 'Update-ModuleChangelog\.ps1';

            # Added bullet linking only historical PR #23 (without #42) fails active PR check
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* [#23](https://github.com/Icinga/IcingaForWindows/pull/23) Backfilled historical item only`n"), $script:Utf8NoBom);
            [array]$WrongPrViolations  = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 42 -PassThru;
            ($WrongPrViolations -join "`n") | Should -Match 'Missing Pull Request #42 link';

            # Leaving a second added bullet unlinked alongside a linked #42 bullet still fails
            [string]$MixedContent      = $Baseline + "* [#42](https://github.com/Icinga/IcingaForWindows/pull/42) Linked primary bullet`n* Unlinked secondary bullet`n";
            [System.IO.File]::WriteAllText($ClPath, $MixedContent, $script:Utf8NoBom);
            [array]$MixedViolations    = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 42 -PassThru;
            ($MixedViolations -join "`n") | Should -Match 'Unlinked changelog entry';

            # Malformed mismatched URL number or bare link without summary text also fails
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* [#42](https://github.com/Icinga/IcingaForWindows/pull/99) Mismatched pull URL`n"), $script:Utf8NoBom);
            [array]$BadUrlViolations   = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 42 -PassThru;
            ($BadUrlViolations -join "`n") | Should -Match 'Unlinked changelog entry';

            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* [#42](https://github.com/Icinga/IcingaForWindows/pull/42)`n"), $script:Utf8NoBom);
            [array]$EmptySummaryViol   = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 42 -PassThru;
            ($EmptySummaryViol -join "`n") | Should -Match 'Unlinked changelog entry';
        }

        It 'auto-detects pull_request.number from GITHUB_EVENT_PATH and allows historical PR backfills alongside the active PR' {
            [string]$Repo          = New-SyntheticGovernanceRepo -RepoName 'PrEventPayloadRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/event-payload' );
            [string]$ClPath        = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$Baseline      = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            [string]$EventPath     = Join-Path -Path $TestDrive -ChildPath 'github-pr-event.json';
            [string]$EventJson     = '{"pull_request":{"number":42}}';
            [System.IO.File]::WriteAllText($EventPath, $EventJson, $script:Utf8NoBom);

            $env:GITHUB_EVENT_NAME = 'pull_request';
            $env:GITHUB_EVENT_PATH = $EventPath;
            $env:GITHUB_BASE_REF   = 'main';

            # Fails when unlinked under GITHUB_EVENT_PATH
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* Adds feature before stamping`n"), $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'Unlinked commit' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '--detach', 'HEAD' );

            [array]$EventFail      = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            ($EventFail -join "`n") | Should -Match 'Missing Pull Request #42 link';

            # Passes when baseline bullet is backfilled to #23 AND net-new bullet links #42 (including multi-PR bullets)
            [string]$WithBackfill  = $Baseline.Replace(
                '* Initial baseline changelog entry for unit testing',
                '* [#23](https://github.com/Icinga/IcingaForWindows/pull/23) Initial baseline changelog entry for unit testing'
            ) + "* [#41](https://github.com/Icinga/IcingaForWindows/pull/41) [#42](https://github.com/Icinga/IcingaForWindows/pull/42) Adds automated PR changelog gate`n";
            [System.IO.File]::WriteAllText($ClPath, $WithBackfill, $script:Utf8NoBom);

            [array]$EventPass      = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $EventPass | Should -BeNullOrEmpty;
        }
    }

    Context 'Update-ModuleChangelog offline PR link stamping and idempotency' {
        It 'stamps multiple added bullets across sections, preserves linked bullets, maintains BOM-less UTF-8, and is idempotent' {
            [string]$Repo          = New-SyntheticGovernanceRepo -RepoName 'UpdateStamperRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/auto-stamp' );
            [string]$ClPath        = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));

            [string]$DraftCl       = @(
                '# Icinga for Windows Changelog',
                '',
                '## 27.0.0 (Unreleased)',
                '',
                '### Enhancements',
                '',
                '* Adds zero-credential PR changelog updater',
                '* [#23](https://github.com/Icinga/IcingaForWindows/pull/23) Backfilled code-styling governance entry',
                '* Initial baseline changelog entry for unit testing',
                '',
                '### Bugfixes',
                '',
                '* #42 Fixes duplicate plain hash prefix when stamping PR links',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($ClPath, $DraftCl, $script:Utf8NoBom);

            [bool]$FirstRun        = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $FirstRun | Should -BeTrue;

            [byte[]]$StampedBytes  = [System.IO.File]::ReadAllBytes($ClPath);
            ($StampedBytes[0] -eq 0xEF -and $StampedBytes[1] -eq 0xBB -and $StampedBytes[2] -eq 0xBF) | Should -BeFalse;

            [string]$StampedText   = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            $StampedText | Should -Match '(?m)^\* \[#42\]\(https://github\.com/Icinga/IcingaForWindows/pull/42\) Adds zero-credential PR changelog updater$';
            $StampedText | Should -Match '(?m)^\* \[#23\]\(https://github\.com/Icinga/IcingaForWindows/pull/23\) Backfilled code-styling governance entry$';
            $StampedText | Should -Match '(?m)^\* Initial baseline changelog entry for unit testing$';
            $StampedText | Should -Match '(?m)^\* \[#42\]\(https://github\.com/Icinga/IcingaForWindows/pull/42\) Fixes duplicate plain hash prefix when stamping PR links$';

            # Validator passes in PR #42 mode immediately after Update-ModuleChangelog
            [array]$PostViolations = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 42 -PassThru;
            $PostViolations | Should -BeNullOrEmpty;

            # Second run is byte-for-byte idempotent
            [bool]$SecondRun       = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $SecondRun | Should -BeTrue;
            [string]$SecondText    = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            $SecondText | Should -BeExactly $StampedText;
        }

        It 'resolves pull_request.number from GITHUB_EVENT_PATH offline, preserves CRLF line endings, and returns false when no bullet was added' {
            [string]$Repo      = New-SyntheticGovernanceRepo -RepoName 'UpdateEventCrlfRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/crlf-event' );

            # No added bullet yet -> returns $false cleanly without throwing
            [bool]$NoBulletRun = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 55;
            $NoBulletRun | Should -BeFalse;

            [string]$EventPath = Join-Path -Path $TestDrive -ChildPath 'update-event-55.json';
            [System.IO.File]::WriteAllText($EventPath, '{"pull_request":{"number":55}}', $script:Utf8NoBom);
            $env:GITHUB_EVENT_PATH = $EventPath;

            [string]$ClPath        = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$CrlfContent   = ([System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8) -replace "`r?`n", "`r`n") + "* Adds CRLF-safe changelog entry`r`n";
            [System.IO.File]::WriteAllText($ClPath, $CrlfContent, $script:Utf8NoBom);

            [bool]$EventStampRun   = & $script:UpdateScript -ModuleBasePath $Repo;
            $EventStampRun | Should -BeTrue;

            [string]$AfterStamp    = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            $AfterStamp.Contains("`r`n") | Should -BeTrue;
            $AfterStamp | Should -Match '(?m)^\* Initial baseline changelog entry for unit testing\r?$';
            $AfterStamp | Should -Match '\[#55\]\(https://github\.com/Icinga/IcingaForWindows/pull/55\) Adds CRLF-safe changelog entry';

            [array]$GateResult     = & $script:ChangelogScript -ModuleBasePath $Repo -PassThru;
            $GateResult | Should -BeNullOrEmpty;
        }

        It 'normalizes custom RepositoryUrl suffixes and handles brand-new Changelog.md files absent from MergeBase' {
            [string]$Repo         = Join-Path -Path $TestDrive -ChildPath 'BrandNewClRepo';
            [string]$GeneralDir   = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath 'General');
            New-Item -Path $GeneralDir -ItemType Directory -Force | Out-Null;

            [System.IO.File]::WriteAllText((Join-Path -Path $Repo -ChildPath 'seed.txt'), "seed`n", $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'init', '-q', '-b', 'main' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'config', 'user.name', 'Icinga Test' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'config', 'user.email', 'test@icinga.com' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'config', 'commit.gpgsign', 'false' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'Seed main without docs/General' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/introduce-changelog' );

            [string]$NewCl        = @(
                '# Icinga for Windows Changelog',
                '',
                '## 27.0.0 (Unreleased)',
                '',
                '### Enhancements',
                '',
                '* Introduces initial project changelog',
                ''
            ) -join "`n";

            [string]$NewRm        = @(
                '# Icinga for Windows Roadmap',
                '',
                '## Completed Milestones & Subsystems',
                '',
                '## Feature List & Planned Work',
                ''
            ) -join "`n";

            [string]$ClFile       = Join-Path -Path $GeneralDir -ChildPath 'Changelog.md';
            [System.IO.File]::WriteAllText($ClFile, $NewCl, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText((Join-Path -Path $GeneralDir -ChildPath 'Roadmap.md'), $NewRm, $script:Utf8NoBom);

            [string]$RawCustomUrl = 'https://github.com/ExampleOrg/IcingaForWindows.git/';
            [array]$PreStampFail  = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 7 -RepositoryUrl $RawCustomUrl -PassThru;
            ($PreStampFail -join "`n") | Should -Match 'Unlinked changelog entry';

            [bool]$StampedOk      = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 7 -RepositoryUrl $RawCustomUrl;
            $StampedOk | Should -BeTrue;

            [string]$UpdatedCl    = [System.IO.File]::ReadAllText($ClFile, [System.Text.Encoding]::UTF8);
            $UpdatedCl | Should -Match '\[#7\]\(https://github\.com/ExampleOrg/IcingaForWindows/pull/7\) Introduces initial project changelog';

            [array]$PostStampPass = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 7 -RepositoryUrl $RawCustomUrl -PassThru;
            $PostStampPass | Should -BeNullOrEmpty;
        }

        It 'preserves indented nested sub-bullets, fenced code blocks, and ++ hunk lines without corrupting sub-items' {
            [string]$Repo      = New-SyntheticGovernanceRepo -RepoName 'SubBulletFenceRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/sub-bullets-and-fences' );
            [string]$ClPath    = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));

            [string]$Draft     = @(
                '# Icinga for Windows Changelog',
                '',
                '## 27.0.0 (Unreleased)',
                '',
                '### Enhancements',
                '',
                '++Section note',
                '* [#42] Adds composite IcingaProtocol subsystem:',
                '  * Supports persistent TLS session resumption',
                '  * Adds configurable idle socket timeout',
                '```markdown',
                '* Example bullet inside fenced code block must remain untouched',
                '```',
                '* Initial baseline changelog entry for unit testing',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($ClPath, $Draft, $script:Utf8NoBom);

            [bool]$Stamped     = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $Stamped | Should -BeTrue;

            [string]$ResultCl  = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            $ResultCl | Should -Match '(?m)^\* \[#42\]\(https://github\.com/Icinga/IcingaForWindows/pull/42\) Adds composite IcingaProtocol subsystem:$';
            $ResultCl | Should -Match '(?m)^  \* Supports persistent TLS session resumption$';
            $ResultCl | Should -Match '(?m)^  \* Adds configurable idle socket timeout$';
            $ResultCl | Should -Match '(?m)^\* Example bullet inside fenced code block must remain untouched$';

            [array]$Violations = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 42 -PassThru;
            $Violations | Should -BeNullOrEmpty;
        }

        It 'returns false in Update-ModuleChangelog whenever Test-ModuleChangelog would reject malformed, historical-only, or zero-net-new bullets' {
            [string]$Repo      = New-SyntheticGovernanceRepo -RepoName 'ParityMismatchRepo';
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/parity-check' );
            [string]$ClPath    = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$Baseline  = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);

            # Case 1: Only historical PR #23 link added (missing active PR #42) -> Update must return $false
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* [#23](https://github.com/Icinga/IcingaForWindows/pull/23) Historical backfill without active PR`n"), $script:Utf8NoBom);
            [bool]$HistOnlyRes = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $HistOnlyRes | Should -BeFalse;

            # Case 2: Bare link with empty summary text -> Update must return $false without double-stamping
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* [#42](https://github.com/Icinga/IcingaForWindows/pull/42)`n"), $script:Utf8NoBom);
            [bool]$BareLinkRes = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $BareLinkRes | Should -BeFalse;

            # Case 3: Mismatched URL PR number -> Update must return $false
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* [#42](https://github.com/Icinga/IcingaForWindows/pull/99) Wrong URL`n"), $script:Utf8NoBom);
            [bool]$MismatchRes = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $MismatchRes | Should -BeFalse;

            # Case 4: Rewording baseline bullet without net-new bullet (+1 / -1 = 0) -> Update must return $false
            [string]$Reworded  = $Baseline.Replace('* Initial baseline changelog entry for unit testing', '* Reworded baseline entry only');
            [System.IO.File]::WriteAllText($ClPath, $Reworded, $script:Utf8NoBom);
            [bool]$RewordRes   = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $RewordRes | Should -BeFalse;

            # Case 5: Bare "#42:" without summary text -> Update must return $false
            [System.IO.File]::WriteAllText($ClPath, ($Baseline + "* #42:`n"), $script:Utf8NoBom);
            [bool]$BareHashRes = & $script:UpdateScript -ModuleBasePath $Repo -PullRequestNumber 42;
            $BareHashRes | Should -BeFalse;
        }

        It 'selects upstream/main over stale local main in external forks and hints when "-" is used instead of "* "' {
            [string]$UpstreamRepo  = New-SyntheticGovernanceRepo -RepoName 'UpstreamMainRepo';
            [string]$ForkRepo      = Join-Path -Path $TestDrive -ChildPath 'StaleForkRepo';
            & git clone -q $UpstreamRepo $ForkRepo | Out-Null;
            Invoke-QuietGit -RepoPath $ForkRepo -GitArgs @( 'config', 'user.name', 'Fork Contributor' );
            Invoke-QuietGit -RepoPath $ForkRepo -GitArgs @( 'config', 'user.email', 'fork@icinga.com' );
            Invoke-QuietGit -RepoPath $ForkRepo -GitArgs @( 'config', 'commit.gpgsign', 'false' );
            Invoke-QuietGit -RepoPath $ForkRepo -GitArgs @( 'remote', 'add', 'upstream', $UpstreamRepo );

            # Advance upstream/main with an unlinked direct commit while fork's local main stays behind
            [string]$UpClPath      = Join-Path -Path $UpstreamRepo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$UpClText      = [System.IO.File]::ReadAllText($UpClPath, [System.Text.Encoding]::UTF8);
            [System.IO.File]::WriteAllText($UpClPath, ($UpClText + "* Fixes upstream socket disposal race (`c678e4f`)`n"), $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $UpstreamRepo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $UpstreamRepo -GitArgs @( 'commit', '-q', '-m', 'Direct upstream commit' );

            Invoke-QuietGit -RepoPath $ForkRepo -GitArgs @( 'fetch', '-q', 'upstream' );
            Invoke-QuietGit -RepoPath $ForkRepo -GitArgs @( 'checkout', '-q', '-b', 'feature/fork-pr', 'upstream/main' );

            # Zero bullets added on fork branch -> must fail Test-ModuleChangelog and return $false in Update-ModuleChangelog
            [array]$ZeroViol       = & $script:ChangelogScript -ModuleBasePath $ForkRepo -PassThru;
            ($ZeroViol -join "`n") | Should -Match 'Missing changelog entry';

            [bool]$NoStampUpstream = & $script:UpdateScript -ModuleBasePath $ForkRepo -PullRequestNumber 88;
            $NoStampUpstream | Should -BeFalse;

            [string]$ForkClPath    = Join-Path -Path $ForkRepo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));
            [string]$ForkClBefore  = [System.IO.File]::ReadAllText($ForkClPath, [System.Text.Encoding]::UTF8);
            $ForkClBefore | Should -Not -Match '\[#88\]';

            # Adding a "- " hyphen bullet instead of "* " emits an explicit asterisk hint
            [System.IO.File]::WriteAllText($ForkClPath, ($ForkClBefore + "- Hyphen bullet instead of asterisk`n"), $script:Utf8NoBom);
            [array]$HyphenViol     = & $script:ChangelogScript -ModuleBasePath $ForkRepo -PassThru;
            ($HyphenViol -join "`n") | Should -Match 'asterisk';
        }

        It 'discovers external fork open PRs via mocked GitHub REST API and backfills historical commits via -SyncHistory' {
            [string]$Repo            = New-SyntheticGovernanceRepo -RepoName 'MockApiSyncRepo';
            [string]$ClPath          = Join-Path -Path $Repo -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));

            # Create two commits on main: one merged PR commit and one direct commit without PR
            [string]$HistCl          = @(
                '# Icinga for Windows Changelog',
                '',
                '## 27.0.0 (Unreleased)',
                '',
                '### Enhancements',
                '',
                '* Adds historical PR-backed feature',
                '  * Nested detail line that must not be blamed or stamped',
                '',
                '## 26.0.0 (2025-12-01)',
                '',
                '### Enhancements',
                '',
                '* Legacy released entry outside Unreleased section',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($ClPath, $HistCl, $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'Add historical entries' );
            [string]$FirstCommitSha  = ((& git -C $Repo rev-parse HEAD) -join '').Trim();

            # Second commit is a direct commit without PR that adds one unlinked direct entry plus one trailing-SHA entry pointing to FirstCommitSha
            [string]$ShortSha        = $FirstCommitSha.Substring(0, 7);
            [string]$WithShaSuffix   = $HistCl.Replace(
                '  * Nested detail line that must not be blamed or stamped',
                ("  * Nested detail line that must not be blamed or stamped`n* Direct commit entry without associated PR`n* Adds trailing-SHA attributed feature (``{0}``)" -f $ShortSha)
            );
            [System.IO.File]::WriteAllText($ClPath, $WithShaSuffix, $script:Utf8NoBom);
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'add', '.' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'commit', '-q', '-m', 'Second main commit without PR' );
            [string]$SecondCommitSha = ((& git -C $Repo rev-parse HEAD) -join '').Trim();

            # Configure origin remote as an external contributor fork (SSH URL) and create a feature branch
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'remote', 'add', 'origin', 'git@github.com:ExternalDev/IcingaForWindows.git' );
            Invoke-QuietGit -RepoPath $Repo -GitArgs @( 'checkout', '-q', '-b', 'feature/external-fork-work' );

            # Verify -SyncHistory returns $false (never false-positive $true) when GitHub API fails offline
            Mock -CommandName Invoke-RestMethod -MockWith {
                throw 'Simulated network failure';
            };
            [bool]$OfflineSync = & $script:UpdateScript -ModuleBasePath $Repo -SyncHistory;
            $OfflineSync | Should -BeFalse;

            # Mock Invoke-RestMethod offline for both -SyncHistory and fork branch PR lookup
            Mock -CommandName Invoke-RestMethod -MockWith {
                if ($Uri -match ([regex]::Escape($FirstCommitSha) + '/pulls$')) {
                    return @(
                        [PSCustomObject]@{
                            number    = 21;
                            state     = 'closed';
                            merged_at = '2026-11-20T10:00:00Z';
                            base      = [PSCustomObject]@{ ref = 'main' };
                        }
                    );
                }
                if ($Uri -match ([regex]::Escape($SecondCommitSha) + '/pulls$')) {
                    return @();
                }
                if ($Uri -match 'pulls\?state=open&head=ExternalDev%3Afeature%2Fexternal-fork-work$') {
                    return @(
                        [PSCustomObject]@{
                            number = 64;
                            state  = 'open';
                            base   = [PSCustomObject]@{ ref = 'main' };
                        }
                    );
                }
                return @();
            };

            [bool]$SyncOk     = & $script:UpdateScript -ModuleBasePath $Repo -SyncHistory;
            $SyncOk | Should -BeTrue;

            [string]$SyncedCl = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            $SyncedCl | Should -Match '(?m)^\* \[#21\]\(https://github\.com/Icinga/IcingaForWindows/pull/21\) Adds historical PR-backed feature$';
            $SyncedCl | Should -Match '(?m)^  \* Nested detail line that must not be blamed or stamped$';
            $SyncedCl | Should -Match '(?m)^\* \[#21\]\(https://github\.com/Icinga/IcingaForWindows/pull/21\) Adds trailing-SHA attributed feature$';
            $SyncedCl | Should -Match '(?m)^\* Direct commit entry without associated PR$';
            $SyncedCl | Should -Match '(?m)^\* Legacy released entry outside Unreleased section$';

            # Add an unlinked branch bullet and verify external fork head filter ("ExternalDev:feature/external-fork-work") resolves PR #64
            [System.IO.File]::WriteAllText($ClPath, ($SyncedCl + "* Adds external fork contribution`n"), $script:Utf8NoBom);
            [bool]$ForkStamp  = & $script:UpdateScript -ModuleBasePath $Repo;
            $ForkStamp | Should -BeTrue;

            [string]$FinalCl  = [System.IO.File]::ReadAllText($ClPath, [System.Text.Encoding]::UTF8);
            $FinalCl | Should -Match '(?m)^\* \[#64\]\(https://github\.com/Icinga/IcingaForWindows/pull/64\) Adds external fork contribution$';

            [array]$FinalViol = & $script:ChangelogScript -ModuleBasePath $Repo -PullRequestNumber 64 -PassThru;
            $FinalViol | Should -BeNullOrEmpty;
        }
    }

    Context 'Document presence and structural validation' {
        It 'reports missing Changelog.md or Roadmap.md files' {
            [string]$EmptyRepo = Join-Path -Path $TestDrive -ChildPath 'MissingDocsRepo';
            New-Item -Path $EmptyRepo -ItemType Directory -Force | Out-Null;

            [array]$Violations = & $script:ChangelogScript -ModuleBasePath $EmptyRepo -CurrentBranch 'main' -PassThru;
            [string]$Joined    = ($Violations -join "`n");

            $Joined | Should -Match 'Missing required file: docs/General/Changelog\.md';
            $Joined | Should -Match 'Missing required file: docs/General/Roadmap\.md';
        }
    }
}

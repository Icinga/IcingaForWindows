<#
.SYNOPSIS
Fast Pester unit test suite for the Icinga for Windows Changelog and Roadmap validator

.DESCRIPTION
Validates `build/Test-ModuleChangelog.ps1` against isolated synthetic Git repositories
in `$TestDrive`. Tests `main` branch exemption, non-`main` branch failure when no
bullet entry is added, committed and working-tree bullet detection on feature branches,
GitHub Actions `pull_request` environment detection, and structural validation of
`docs/General/Changelog.md` and `docs/General/Roadmap.md`.

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
        $script:SavedRefName   = $env:GITHUB_REF_NAME;
        $script:SavedBaseRef   = $env:GITHUB_BASE_REF;

        $env:GITHUB_EVENT_NAME = $null;
        $env:GITHUB_REF_NAME   = $null;
        $env:GITHUB_BASE_REF   = $null;
    }

    AfterEach {
        $env:GITHUB_EVENT_NAME = $script:SavedEventName;
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

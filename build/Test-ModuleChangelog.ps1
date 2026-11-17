<#
.SYNOPSIS
Validate Changelog.md and Roadmap.md governance and require changelog entries on non-main branches

.DESCRIPTION
Verifies that `docs/General/Changelog.md` and `docs/General/Roadmap.md` exist, use
UTF-8 without BOM encoding, and conform to the Icinga for Windows governance layout
defined in `docs/Agents/guidelines/01-Instruction.md`.

Whenever execution is NOT on `main` (any local feature/fix/refactoring branch or any
GitHub Actions `pull_request` workflow), the script compares `docs/General/Changelog.md`
against the merge-base with the target base branch (`origin/$env:GITHUB_BASE_REF` in CI
or `main` locally, including uncommitted working-tree changes) and requires at least one
added changelog bullet (`* ...`). Missing changelog entries fail with a clear error.

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                                   | Default                       |
|----------------|---------------|-------------------------------------------------------------------------------|-------------------------------|
| ModuleBasePath | System.String | Absolute path to the Icinga for Windows module root (the folder above `src`). | Resolved from the script path |

.PARAMETER BaseBranch
| Name       | Type          | Description                                                            | Default                                    |
|------------|---------------|------------------------------------------------------------------------|--------------------------------------------|
| BaseBranch | System.String | Optional explicit Git base ref to compare against when not on `main`.  | `origin/$env:GITHUB_BASE_REF` or `main`    |

.PARAMETER CurrentBranch
| Name          | Type          | Description                                                               | Default                              |
|---------------|---------------|---------------------------------------------------------------------------|--------------------------------------|
| CurrentBranch | System.String | Optional explicit branch name override (used by synthetic Pester tests).  | Detected from GitHub CI or `git`     |

.PARAMETER PassThru
| Name     | Type                                         | Description                                                         | Default |
|----------|----------------------------------------------|---------------------------------------------------------------------|---------|
| PassThru | System.Management.Automation.SwitchParameter | Return the array of violation strings instead of throwing on error. | False   |

.OUTPUTS
System.Object -- Returns `$true` when all governance checks pass (or the array of violation strings when `-PassThru` is set).

.EXAMPLE
PS> .\build\Test-ModuleChangelog.ps1

Validates `docs/General/Changelog.md` and `docs/General/Roadmap.md` and enforces a
changelog entry whenever the active branch is not `main`.

.NOTES
Requires `git` on `PATH` when evaluating branch diffs.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>

[CmdletBinding()]
param (
    [string]$ModuleBasePath = $null,
    [string]$BaseBranch     = $null,
    [string]$CurrentBranch  = $null,
    [switch]$PassThru       = $false
);

$ErrorActionPreference = 'Stop';
$ProgressPreference    = 'SilentlyContinue';

if ([string]::IsNullOrEmpty($ModuleBasePath)) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath);
} elseif (Test-Path -Path $ModuleBasePath) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $ModuleBasePath).ProviderPath);
}

function Test-GitRefExists()
{
    param (
        [string]$RepoPath = '',
        [string]$RefName  = ''
    );

    if ([string]::IsNullOrWhiteSpace($RefName)) {
        return $false;
    }

    $null = & git -C $RepoPath rev-parse --verify --quiet $RefName;
    return ($LASTEXITCODE -eq 0);
}

function Invoke-IcingaChangelogGovernanceCheck()
{
    param (
        [string]$RepoRoot       = '',
        [string]$ExplicitBase   = '',
        [string]$ExplicitBranch = ''
    );

    [array]$Violations    = @();
    [string]$GeneralDir   = Join-Path -Path $RepoRoot -ChildPath (Join-Path -Path 'docs' -ChildPath 'General');
    [string]$ChangelogRel = 'docs/General/Changelog.md';
    [string]$RoadmapRel   = 'docs/General/Roadmap.md';
    [string]$ChangelogAbs = Join-Path -Path $GeneralDir -ChildPath 'Changelog.md';
    [string]$RoadmapAbs   = Join-Path -Path $GeneralDir -ChildPath 'Roadmap.md';

    # 1. Verify docs/General/Changelog.md exists and matches structure
    if (-not (Test-Path -Path $ChangelogAbs -PathType Leaf)) {
        $Violations += ('Missing required file: {0}' -f $ChangelogRel);
    } else {
        [byte[]]$ClBytes = [System.IO.File]::ReadAllBytes($ChangelogAbs);
        if ($ClBytes.Length -ge 3 -and $ClBytes[0] -eq 0xEF -and $ClBytes[1] -eq 0xBB -and $ClBytes[2] -eq 0xBF) {
            $Violations += ('{0}:1 -- File contains a UTF-8 BOM; save as UTF-8 without BOM' -f $ChangelogRel);
        }

        [string]$ClContent = [System.IO.File]::ReadAllText($ChangelogAbs, [System.Text.Encoding]::UTF8);
        if ($ClContent -notmatch '(?mi)^#\s+Icinga for Windows Changelog\b') {
            $Violations += ('{0}:1 -- Missing "# Icinga for Windows Changelog" top-level heading' -f $ChangelogRel);
        }
        if ($ClContent -notmatch '(?m)^##\s+\d+\.\d+\.\d+') {
            $Violations += ('{0} -- Missing "## <Major.Minor.Patch>" version section heading' -f $ChangelogRel);
        }
        if ($ClContent -notmatch '(?m)^\s*\*\s+\S+') {
            $Violations += ('{0} -- Changelog must contain at least one "* " bullet entry' -f $ChangelogRel);
        }
    }

    # 2. Verify docs/General/Roadmap.md exists and matches structure
    if (-not (Test-Path -Path $RoadmapAbs -PathType Leaf)) {
        $Violations += ('Missing required file: {0}' -f $RoadmapRel);
    } else {
        [byte[]]$RmBytes = [System.IO.File]::ReadAllBytes($RoadmapAbs);
        if ($RmBytes.Length -ge 3 -and $RmBytes[0] -eq 0xEF -and $RmBytes[1] -eq 0xBB -and $RmBytes[2] -eq 0xBF) {
            $Violations += ('{0}:1 -- File contains a UTF-8 BOM; save as UTF-8 without BOM' -f $RoadmapRel);
        }

        [string]$RmContent = [System.IO.File]::ReadAllText($RoadmapAbs, [System.Text.Encoding]::UTF8);
        if ($RmContent -notmatch '(?mi)^#\s+Icinga for Windows Roadmap\b') {
            $Violations += ('{0}:1 -- Missing "# Icinga for Windows Roadmap" top-level heading' -f $RoadmapRel);
        }
        if ($RmContent -notmatch '(?m)^##\s+Completed') {
            $Violations += ('{0} -- Missing "## Completed ..." milestones section' -f $RoadmapRel);
        }
        if ($RmContent -notmatch '(?m)^##\s+Feature List') {
            $Violations += ('{0} -- Missing "## Feature List ..." planned work section' -f $RoadmapRel);
        }
    }

    if ($Violations.Count -gt 0) {
        return $Violations;
    }

    # 3. Determine whether current execution is on 'main' or on a PR / feature branch
    [bool]$IsOnMain = $false;

    if (-not [string]::IsNullOrWhiteSpace($ExplicitBranch)) {
        $IsOnMain = ($ExplicitBranch.Trim() -eq 'main');
    } elseif ($env:GITHUB_EVENT_NAME -eq 'pull_request' -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        $IsOnMain = $false;
    } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF_NAME)) {
        $IsOnMain = ($env:GITHUB_REF_NAME.Trim() -eq 'main');
    } else {
        [string]$GitBranch = ((& git -C $RepoRoot rev-parse --abbrev-ref HEAD) -join '').Trim();
        if ($LASTEXITCODE -ne 0) {
            $Violations += 'Unable to determine current Git branch via "git rev-parse --abbrev-ref HEAD".';
            return $Violations;
        }
        $IsOnMain = ($GitBranch -eq 'main');
    }

    if ($IsOnMain) {
        return $Violations;
    }

    # 4. Resolve base reference to diff against
    [string]$ResolvedBase = '';

    if (-not [string]::IsNullOrWhiteSpace($ExplicitBase)) {
        if (Test-GitRefExists -RepoPath $RepoRoot -RefName $ExplicitBase.Trim()) {
            $ResolvedBase = $ExplicitBase.Trim();
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        [string]$OriginBase = ('origin/{0}' -f $env:GITHUB_BASE_REF.Trim());
        if (Test-GitRefExists -RepoPath $RepoRoot -RefName $OriginBase) {
            $ResolvedBase = $OriginBase;
        } elseif (Test-GitRefExists -RepoPath $RepoRoot -RefName $env:GITHUB_BASE_REF.Trim()) {
            $ResolvedBase = $env:GITHUB_BASE_REF.Trim();
        }
    } else {
        if (Test-GitRefExists -RepoPath $RepoRoot -RefName 'main') {
            $ResolvedBase = 'main';
        } elseif (Test-GitRefExists -RepoPath $RepoRoot -RefName 'origin/main') {
            $ResolvedBase = 'origin/main';
        }
    }

    if ([string]::IsNullOrEmpty($ResolvedBase)) {
        $Violations += 'Unable to resolve base Git branch ("main" or "origin/main") for changelog comparison. Ensure fetch-depth: 0 in CI.';
        return $Violations;
    }

    [string]$MergeBase = ((& git -C $RepoRoot merge-base $ResolvedBase HEAD) -join '').Trim();
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($MergeBase)) {
        $Violations += ('Unable to compute Git merge-base between "{0}" and HEAD for changelog comparison.' -f $ResolvedBase);
        return $Violations;
    }

    # Check whether docs/General/Changelog.md existed in MergeBase without stderr noise
    [string]$TreeHit      = ((& git -C $RepoRoot ls-tree -r --name-only $MergeBase -- $ChangelogRel) -join '').Trim();
    [bool]$ExistedInBase  = (-not [string]::IsNullOrEmpty($TreeHit));
    [bool]$HasAddedBullet = $false;

    if (-not $ExistedInBase) {
        # Brand-new Changelog.md introduced on this branch (tracked or untracked in working tree)
        [string]$DiskChangelog = [System.IO.File]::ReadAllText($ChangelogAbs, [System.Text.Encoding]::UTF8);
        $HasAddedBullet        = ($DiskChangelog -match '(?m)^\s*\*\s+\S+');
    } else {
        # Compare MergeBase against working-tree file and require at least one net-new bullet
        # so rewording or deleting existing bullets cannot bypass the PR changelog requirement
        [array]$DiffLines      = @(& git -C $RepoRoot diff --unified=0 $MergeBase -- $ChangelogRel);
        [int]$AddedBulletCount = 0;
        [int]$RemovedBullets   = 0;

        foreach ($DiffLine in $DiffLines) {
            [string]$LineStr = [string]$DiffLine;
            if ($LineStr.StartsWith('+++') -or $LineStr.StartsWith('---')) {
                continue;
            }
            if ($LineStr -match '^\+\s*\*\s+\S+') {
                $AddedBulletCount++;
            } elseif ($LineStr -match '^-\s*\*\s+\S+') {
                $RemovedBullets++;
            }
        }

        $HasAddedBullet = ($AddedBulletCount -gt $RemovedBullets);
    }

    if (-not $HasAddedBullet) {
        $Violations += "Missing changelog entry: Every branch and pull request not on 'main' must add an entry to docs/General/Changelog.md.";
    }

    return $Violations;
}

[array]$AllChangelogViolations = Invoke-IcingaChangelogGovernanceCheck -RepoRoot $ModuleBasePath -ExplicitBase $BaseBranch -ExplicitBranch $CurrentBranch;

if ($PassThru) {
    return $AllChangelogViolations;
}

Write-Host "`n[+] Running Changelog & Roadmap governance checks..." -ForegroundColor Yellow;

if ($AllChangelogViolations.Count -gt 0) {
    foreach ($Issue in $AllChangelogViolations) {
        Write-Host ('[ERROR] {0}' -f $Issue) -ForegroundColor Red;
    }
    throw ($AllChangelogViolations -join "`n");
}

Write-Host '  * Changelog & Roadmap governance checks passed' -ForegroundColor Green;
return $true;

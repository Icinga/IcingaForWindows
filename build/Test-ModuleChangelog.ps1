<#
.SYNOPSIS
Validate Changelog.md and Roadmap.md governance and enforce PR-linked changelog entries

.DESCRIPTION
Verifies that `docs/General/Changelog.md` and `docs/General/Roadmap.md` exist, use
UTF-8 without BOM encoding, and conform to the Icinga for Windows governance layout
defined in `docs/Agents/guidelines/01-Instruction.md`.

Whenever execution is NOT on `main` (any local feature/fix/refactoring branch or any
GitHub Actions `pull_request` workflow), the script compares `docs/General/Changelog.md`
against the closest merge-base across `upstream/main`, `origin/main`, and `main` (or
`origin/$env:GITHUB_BASE_REF` in CI, including uncommitted working-tree changes) using
a two-stage gate:

1. Local Pre-PR Mode (`$PullRequestNumber -le 0` and outside a `pull_request` event):
   Requires at least one net-new top-level `* ...` bullet entry (`AddedBulletCount > RemovedBullets`).
2. Pull Request Mode (`$PullRequestNumber -gt 0` or `$env:GITHUB_EVENT_PATH` contains
   `pull_request.number`): Requires at least one net-new top-level bullet entry, requires
   every added top-level bullet to begin with a valid `[#<PR>](<RepositoryUrl>/pull/<PR>) <Summary>`
   link, and requires at least one added bullet to reference the active Pull Request.

Indented nested sub-bullets (`  * ...`) and fenced Markdown code blocks inside
`docs/General/Changelog.md` are permitted beneath a linked top-level entry.

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                                   | Default                       |
|----------------|---------------|-------------------------------------------------------------------------------|-------------------------------|
| ModuleBasePath | System.String | Absolute path to the Icinga for Windows module root (the folder above `src`). | Resolved from the script path |

.PARAMETER BaseBranch
| Name       | Type          | Description                                                            | Default                                              |
|------------|---------------|------------------------------------------------------------------------|------------------------------------------------------|
| BaseBranch | System.String | Optional explicit Git base ref to compare against when not on `main`.  | Closest of `upstream/main`, `origin/main`, or `main` |

.PARAMETER CurrentBranch
| Name          | Type          | Description                                                               | Default                          |
|---------------|---------------|---------------------------------------------------------------------------|----------------------------------|
| CurrentBranch | System.String | Optional explicit branch name override (used by synthetic Pester tests).  | Detected from GitHub CI or `git` |

.PARAMETER PullRequestNumber
| Name              | Type         | Description                                                                   | Default                                     |
|-------------------|--------------|-------------------------------------------------------------------------------|---------------------------------------------|
| PullRequestNumber | System.Int32 | Optional explicit Pull Request number enabling pre-merge PR link enforcement. | Auto-detected from `$env:GITHUB_EVENT_PATH` |

.PARAMETER RepositoryUrl
| Name          | Type          | Description                                                                   | Default                                     |
|---------------|---------------|-------------------------------------------------------------------------------|---------------------------------------------|
| RepositoryUrl | System.String | Canonical GitHub repository base URL expected in `[#<PR>](.../pull/<PR>)`.    | `PrivateData.PSData.ProjectUri` in manifest |

.PARAMETER PassThru
| Name     | Type                                         | Description                                                         | Default |
|----------|----------------------------------------------|---------------------------------------------------------------------|---------|
| PassThru | System.Management.Automation.SwitchParameter | Return the array of violation strings instead of throwing on error. | False   |

.OUTPUTS
System.Object -- Returns `$true` when all governance checks pass (or the array of violation strings when `-PassThru` is set).

.EXAMPLE
PS> .\build\Test-ModuleChangelog.ps1

Validates `docs/General/Changelog.md` and `docs/General/Roadmap.md` and enforces a
changelog entry whenever the active branch is not `main` (plus PR links in CI).

.EXAMPLE
PS> .\build\Test-ModuleChangelog.ps1 -PullRequestNumber 42

Validates that newly added top-level changelog bullets are linked and include
`[#42](https://github.com/Icinga/IcingaForWindows/pull/42)`.

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
    [int]$PullRequestNumber = 0,
    [string]$RepositoryUrl  = $null,
    [switch]$PassThru       = $false
);

$ErrorActionPreference = 'Stop';
$ProgressPreference    = 'SilentlyContinue';

if ([string]::IsNullOrEmpty($ModuleBasePath)) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath);
} elseif (Test-Path -Path $ModuleBasePath) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $ModuleBasePath).ProviderPath);
}

function Format-GitProcessArgument()
{
    param (
        [string]$Argument = ''
    );

    if ([string]::IsNullOrEmpty($Argument)) {
        return '""';
    }

    if ($Argument -notmatch '[\s"\\]') {
        return $Argument;
    }

    [System.Text.StringBuilder]$Builder = New-Object System.Text.StringBuilder;
    $null                               = $Builder.Append('"');
    [int]$BackslashCount                = 0;

    for ($i = 0; $i -lt $Argument.Length; $i++) {
        [char]$Ch = $Argument[$i];
        if ($Ch -eq '\') {
            $BackslashCount++;
            continue;
        }
        if ($Ch -eq '"') {
            $null           = $Builder.Append('\', ($BackslashCount * 2) + 1);
            $null           = $Builder.Append('"');
            $BackslashCount = 0;
            continue;
        }
        if ($BackslashCount -gt 0) {
            $null           = $Builder.Append('\', $BackslashCount);
            $BackslashCount = 0;
        }
        $null = $Builder.Append($Ch);
    }

    if ($BackslashCount -gt 0) {
        $null = $Builder.Append('\', ($BackslashCount * 2));
    }

    $null = $Builder.Append('"');
    return $Builder.ToString();
}

function Invoke-GitProcess()
{
    param (
        [string]$RepoPath  = '',
        [string[]]$GitArgs = @()
    );

    if ([string]::IsNullOrWhiteSpace($RepoPath) -or -not (Test-Path -Path $RepoPath -PathType Container)) {
        return @{
            'ExitCode' = 128;
            'StdOut'   = '';
            'StdErr'   = 'Repository directory does not exist.';
        };
    }

    [array]$FormattedArgs = @();
    foreach ($RawArg in $GitArgs) {
        $FormattedArgs += (Format-GitProcessArgument -Argument ([string]$RawArg));
    }

    $StartInfo                        = New-Object System.Diagnostics.ProcessStartInfo;
    $StartInfo.FileName               = 'git';
    $StartInfo.Arguments              = ($FormattedArgs -join ' ');
    $StartInfo.WorkingDirectory       = $RepoPath;
    $StartInfo.UseShellExecute        = $false;
    $StartInfo.CreateNoWindow         = $true;
    $StartInfo.RedirectStandardOutput = $true;
    $StartInfo.RedirectStandardError  = $true;
    $StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8;
    $StartInfo.StandardErrorEncoding  = [System.Text.Encoding]::UTF8;

    $Proc                             = New-Object System.Diagnostics.Process;
    try {
        $Proc.StartInfo     = $StartInfo;
        $null               = $Proc.Start();
        $StdOutTask         = $Proc.StandardOutput.ReadToEndAsync();
        $StdErrTask         = $Proc.StandardError.ReadToEndAsync();
        $Proc.WaitForExit();
        [string]$StdOutText = $StdOutTask.GetAwaiter().GetResult();
        [string]$StdErrText = $StdErrTask.GetAwaiter().GetResult();

        return @{
            'ExitCode' = [int]$Proc.ExitCode;
            'StdOut'   = $StdOutText;
            'StdErr'   = $StdErrText;
        };
    } finally {
        $Proc.Dispose();
    }
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

    [hashtable]$GitResult = Invoke-GitProcess -RepoPath $RepoPath -GitArgs @( 'rev-parse', '--verify', '--quiet', $RefName );
    return ($GitResult['ExitCode'] -eq 0);
}

function Get-MarkdownCodeFenceMask()
{
    param (
        [array]$Lines = @()
    );

    [array]$Mask        = New-Object bool[] $Lines.Count;
    [bool]$InsideFence  = $false;
    [char]$FenceChar    = [char]0;
    [int]$FenceMinCount = 0;

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        [string]$Current = [string]$Lines[$i];

        if (-not $InsideFence) {
            if ($Current -match '^ {0,3}(`{3,}|~{3,})') {
                [string]$Marker = $Matches[1];
                $InsideFence    = $true;
                $FenceChar      = $Marker[0];
                $FenceMinCount  = $Marker.Length;
                $Mask[$i]       = $true;
            }
        } else {
            $Mask[$i]            = $true;
            [string]$CloseExpect = ('^ {{0,3}}{0}{{{1},}}\s*$' -f [regex]::Escape([string]$FenceChar), $FenceMinCount);
            if ($Current -match $CloseExpect) {
                $InsideFence   = $false;
                $FenceChar     = [char]0;
                $FenceMinCount = 0;
            }
        }
    }

    return $Mask;
}

function Resolve-CanonicalRepositoryUrl()
{
    param (
        [string]$RepoRoot       = '',
        [string]$ScriptRootPath = '',
        [string]$ExplicitUrl    = ''
    );

    [string]$Resolved = '';

    if (-not [string]::IsNullOrWhiteSpace($ExplicitUrl)) {
        $Resolved = $ExplicitUrl.Trim();
    } else {
        [array]$CandidateManifests = @(
            (Join-Path -Path $RepoRoot -ChildPath 'IcingaForWindows.psd1'),
            (Join-Path -Path (Join-Path -Path $ScriptRootPath -ChildPath '..') -ChildPath 'IcingaForWindows.psd1')
        );

        foreach ($ManifestPath in $CandidateManifests) {
            if (Test-Path -Path $ManifestPath -PathType Leaf) {
                try {
                    [hashtable]$ManifestData = Import-PowerShellDataFile -Path $ManifestPath;
                    if ($null -ne $ManifestData.PrivateData -and $null -ne $ManifestData.PrivateData.PSData) {
                        [string]$ProjectUri = [string]$ManifestData.PrivateData.PSData.ProjectUri;
                        if (-not [string]::IsNullOrWhiteSpace($ProjectUri)) {
                            $Resolved = $ProjectUri.Trim();
                            break;
                        }
                    }
                } catch {
                    $Resolved = '';
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($Resolved)) {
        $Resolved = 'https://github.com/Icinga/IcingaForWindows';
    }

    $Resolved = $Resolved.TrimEnd('/');
    $Resolved = ($Resolved -replace '\.git$', '');
    $Resolved = $Resolved.TrimEnd('/');

    return $Resolved;
}

function Get-DetectedPullRequestNumber()
{
    param (
        [int]$ExplicitPrNumber = 0
    );

    if ($ExplicitPrNumber -gt 0) {
        return $ExplicitPrNumber;
    }

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_EVENT_PATH)) {
        return 0;
    }

    if (-not (Test-Path -Path $env:GITHUB_EVENT_PATH -PathType Leaf)) {
        return 0;
    }

    try {
        [string]$RawJson = [System.IO.File]::ReadAllText($env:GITHUB_EVENT_PATH, [System.Text.Encoding]::UTF8);
        $EventPayload    = $RawJson | ConvertFrom-Json;
        if ($null -ne $EventPayload -and $null -ne $EventPayload.pull_request -and $null -ne $EventPayload.pull_request.number) {
            [int]$ParsedPr = 0;
            if ([int]::TryParse([string]$EventPayload.pull_request.number, [ref]$ParsedPr) -and $ParsedPr -gt 0) {
                return $ParsedPr;
            }
        }
    } catch {
        return 0;
    }

    return 0;
}

function Resolve-ComparisonMergeBase()
{
    param (
        [string]$RepoRoot     = '',
        [string]$ExplicitBase = ''
    );

    [array]$Candidates = @();

    if (-not [string]::IsNullOrWhiteSpace($ExplicitBase)) {
        $Candidates = @( $ExplicitBase.Trim() );
    } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        [string]$TrimmedEnv = $env:GITHUB_BASE_REF.Trim();
        $Candidates         = @(
            ('origin/{0}' -f $TrimmedEnv),
            ('upstream/{0}' -f $TrimmedEnv),
            $TrimmedEnv
        );
    } else {
        $Candidates = @( 'upstream/main', 'origin/main', 'main' );
    }

    [array]$ExistingRefs   = @();
    [string]$BestRef       = '';
    [string]$BestMergeBase = '';

    foreach ($RefName in $Candidates) {
        if (-not (Test-GitRefExists -RepoPath $RepoRoot -RefName $RefName)) {
            continue;
        }
        $ExistingRefs    += $RefName;
        [hashtable]$MbRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'merge-base', $RefName, 'HEAD' );
        [string]$CandMb   = ([string]$MbRes['StdOut']).Trim();

        if ($MbRes['ExitCode'] -ne 0 -or [string]::IsNullOrWhiteSpace($CandMb)) {
            continue;
        }

        if ([string]::IsNullOrEmpty($BestMergeBase)) {
            $BestRef       = $RefName;
            $BestMergeBase = $CandMb;
        } elseif ($CandMb -ne $BestMergeBase) {
            [hashtable]$AncRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'merge-base', '--is-ancestor', $BestMergeBase, $CandMb );
            if ($AncRes['ExitCode'] -eq 0) {
                $BestRef       = $RefName;
                $BestMergeBase = $CandMb;
            }
        }
    }

    return @{
        'ExistingCount' = $ExistingRefs.Count;
        'FirstExisting' = $(if ($ExistingRefs.Count -gt 0) { $ExistingRefs[0] } else { '' });
        'ResolvedBase'  = $BestRef;
        'MergeBase'     = $BestMergeBase;
    };
}

function Invoke-IcingaChangelogGovernanceCheck()
{
    param (
        [string]$RepoRoot        = '',
        [string]$ScriptRootPath  = '',
        [string]$ExplicitBase    = '',
        [string]$ExplicitBranch  = '',
        [int]$ExplicitPrNumber   = 0,
        [string]$ExplicitRepoUrl = ''
    );

    [array]$Violations    = @();
    [string]$GeneralDir   = Join-Path -Path $RepoRoot -ChildPath (Join-Path -Path 'docs' -ChildPath 'General');
    [string]$ChangelogRel = 'docs/General/Changelog.md';
    [string]$RoadmapRel   = 'docs/General/Roadmap.md';
    [string]$ChangelogAbs = Join-Path -Path $GeneralDir -ChildPath 'Changelog.md';
    [string]$RoadmapAbs   = Join-Path -Path $GeneralDir -ChildPath 'Roadmap.md';
    [string]$ClContent    = '';

    # 1. Verify docs/General/Changelog.md exists and matches structure
    if (-not (Test-Path -Path $ChangelogAbs -PathType Leaf)) {
        $Violations += ('Missing required file: {0}' -f $ChangelogRel);
    } else {
        [byte[]]$ClBytes = [System.IO.File]::ReadAllBytes($ChangelogAbs);
        if ($ClBytes.Length -ge 3 -and $ClBytes[0] -eq 0xEF -and $ClBytes[1] -eq 0xBB -and $ClBytes[2] -eq 0xBF) {
            $Violations += ('{0}:1 -- File contains a UTF-8 BOM; save as UTF-8 without BOM' -f $ChangelogRel);
        }

        $ClContent = [System.IO.File]::ReadAllText($ChangelogAbs, [System.Text.Encoding]::UTF8);
        if ($ClContent -notmatch '(?mi)^#\s+Icinga for Windows Changelog\b') {
            $Violations += ('{0}:1 -- Missing "# Icinga for Windows Changelog" top-level heading' -f $ChangelogRel);
        }
        if ($ClContent -notmatch '(?m)^##\s+\d+\.\d+\.\d+') {
            $Violations += ('{0} -- Missing "## <Major.Minor.Patch>" version section heading' -f $ChangelogRel);
        }
        if ($ClContent -notmatch '(?m)^ ?\*\s+\S+') {
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

    # 3. Determine Pull Request context and whether current execution is on 'main'
    [int]$ResolvedPrNumber = Get-DetectedPullRequestNumber -ExplicitPrNumber $ExplicitPrNumber;
    [bool]$IsOnMain        = $false;

    if (-not [string]::IsNullOrWhiteSpace($ExplicitBranch)) {
        $IsOnMain = ($ExplicitBranch.Trim() -eq 'main');
    } elseif ($ResolvedPrNumber -gt 0 -or $env:GITHUB_EVENT_NAME -eq 'pull_request' -or -not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        $IsOnMain = $false;
    } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF_NAME)) {
        $IsOnMain = ($env:GITHUB_REF_NAME.Trim() -eq 'main');
    } else {
        [hashtable]$BranchRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'rev-parse', '--abbrev-ref', 'HEAD' );
        [string]$GitBranch    = ([string]$BranchRes['StdOut']).Trim();
        if ($BranchRes['ExitCode'] -ne 0 -or [string]::IsNullOrEmpty($GitBranch)) {
            $Violations += 'Unable to determine current Git branch via "git rev-parse --abbrev-ref HEAD".';
            return $Violations;
        }
        $IsOnMain = ($GitBranch -eq 'main');
    }

    if ($IsOnMain) {
        return $Violations;
    }

    # 4. Resolve closest base reference and merge-base across upstream/main, origin/main, and main
    [hashtable]$BaseInfo = Resolve-ComparisonMergeBase -RepoRoot $RepoRoot -ExplicitBase $ExplicitBase;
    if ([int]$BaseInfo['ExistingCount'] -eq 0) {
        $Violations += 'Unable to resolve base Git branch ("upstream/main", "origin/main", or "main") for changelog comparison. Ensure fetch-depth: 0 in CI.';
        return $Violations;
    }

    [string]$MergeBase = [string]$BaseInfo['MergeBase'];
    if ([string]::IsNullOrEmpty($MergeBase)) {
        $Violations += ('Unable to compute Git merge-base between "{0}" and HEAD for changelog comparison.' -f [string]$BaseInfo['FirstExisting']);
        return $Violations;
    }

    # 5. Collect added and removed top-level changelog bullets between MergeBase and the working tree
    [string]$TrimmedCl        = ($ClContent -replace '\r?\n\z', '');
    [array]$DiskLines         = @($TrimmedCl -split '\r?\n');
    [array]$FenceMask         = Get-MarkdownCodeFenceMask -Lines $DiskLines;
    [hashtable]$TreeRes       = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'ls-tree', '-r', '--name-only', $MergeBase, '--', $ChangelogRel );
    [bool]$ExistedInBase      = ($TreeRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($TreeRes['StdOut']));
    [array]$AddedBulletLines  = @();
    [int]$AddedBulletCount    = 0;
    [int]$RemovedBullets      = 0;
    [bool]$AddedHyphenBullets = $false;

    if (-not $ExistedInBase) {
        # Brand-new Changelog.md introduced on this branch (tracked or untracked in working tree)
        for ($idx = 0; $idx -lt $DiskLines.Count; $idx++) {
            if ($FenceMask[$idx]) {
                continue;
            }
            if ($DiskLines[$idx] -match '^ ?\*\s+\S+') {
                $AddedBulletLines += $DiskLines[$idx];
            } elseif ($DiskLines[$idx] -match '^ ?-\s+\S+') {
                $AddedHyphenBullets = $true;
            }
        }
        $AddedBulletCount = $AddedBulletLines.Count;
    } else {
        # Compare MergeBase against working-tree file and require at least one net-new top-level bullet
        # so rewording or deleting existing bullets cannot bypass the PR changelog requirement
        [hashtable]$DiffRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'diff', '--unified=0', '--ignore-cr-at-eol', $MergeBase, '--', $ChangelogRel );
        if ($DiffRes['ExitCode'] -ne 0) {
            $Violations += ('Failed to execute "git diff" against merge-base "{0}" for {1}.' -f $MergeBase, $ChangelogRel);
            return $Violations;
        }

        [array]$DiffLines = @();
        if (-not [string]::IsNullOrEmpty($DiffRes['StdOut'])) {
            $DiffLines = @($DiffRes['StdOut'] -split '\r?\n');
        }

        [int]$CurrentNewLine = 0;
        [bool]$InHunk        = $false;

        foreach ($DiffLine in $DiffLines) {
            [string]$LineStr = ([string]$DiffLine).TrimEnd("`r");

            if ($LineStr -match '^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,(\d+))?\s+@@') {
                $CurrentNewLine = [int]$Matches[1];
                $InHunk         = $true;
                continue;
            }

            if (-not $InHunk -or $LineStr.StartsWith('\')) {
                continue;
            }

            if ($LineStr.StartsWith('+')) {
                [int]$ZeroBasedIdx = $CurrentNewLine - 1;
                if ($ZeroBasedIdx -ge 0 -and $ZeroBasedIdx -lt $DiskLines.Count -and -not $FenceMask[$ZeroBasedIdx]) {
                    if ($DiskLines[$ZeroBasedIdx] -match '^ ?\*\s+\S+') {
                        $AddedBulletCount++;
                        $AddedBulletLines += $DiskLines[$ZeroBasedIdx];
                    } elseif ($DiskLines[$ZeroBasedIdx] -match '^ ?-\s+\S+') {
                        $AddedHyphenBullets = $true;
                    }
                }
                $CurrentNewLine++;
            } elseif ($LineStr.StartsWith('-')) {
                [string]$RemovedText = $LineStr.Substring(1);
                if ($RemovedText -match '^ ?\*\s+\S+') {
                    $RemovedBullets++;
                }
            }
        }
    }

    [bool]$HasAddedBullet = ($AddedBulletCount -gt $RemovedBullets);

    if (-not $HasAddedBullet) {
        [string]$HyphenHint = '';
        if ($AddedHyphenBullets) {
            $HyphenHint = ' Top-level changelog entries must begin with "* " (asterisk) rather than "- ".';
        }
        if ($ResolvedPrNumber -gt 0) {
            $Violations += ('Missing changelog entry: Every branch and pull request not on ''main'' must add an entry to {0}.{1} Add a "* <Summary>" bullet, run ".\build\Update-ModuleChangelog.ps1", commit {0}, and push.' -f $ChangelogRel, $HyphenHint);
        } else {
            $Violations += ('Missing changelog entry: Every branch and pull request not on ''main'' must add an entry to {0}.{1}' -f $ChangelogRel, $HyphenHint);
        }
        return $Violations;
    }

    # 6. Pull Request Mode: enforce [#<PR>](<RepositoryUrl>/pull/<PR>) links on every added top-level bullet
    if ($ResolvedPrNumber -gt 0) {
        [string]$ResolvedRepoUrl    = Resolve-CanonicalRepositoryUrl -RepoRoot $RepoRoot -ScriptRootPath $ScriptRootPath -ExplicitUrl $ExplicitRepoUrl;
        [string]$EscapedRepoUrl     = [regex]::Escape($ResolvedRepoUrl);
        [string]$LeadingPrLinkRegex = ('^\[#(?<pr>[1-9]\d*)\]\({0}/pull/\k<pr>\)\s+' -f $EscapedRepoUrl);
        [bool]$HasUnlinkedBullet    = $false;
        [bool]$HasCurrentPrBullet   = $false;

        foreach ($BulletLine in $AddedBulletLines) {
            if ($BulletLine -notmatch '^ ?\*\s+(\S.*)$') {
                $HasUnlinkedBullet = $true;
                continue;
            }

            [string]$BodyCursor      = $Matches[1];
            [int]$LeadingLinksOnLine = 0;

            while ($BodyCursor -match $LeadingPrLinkRegex) {
                [int]$LinkedPrNum = [int]$Matches['pr'];
                if ($LinkedPrNum -eq $ResolvedPrNumber) {
                    $HasCurrentPrBullet = $true;
                }
                $LeadingLinksOnLine++;
                $BodyCursor = $BodyCursor.Substring($Matches[0].Length);
            }

            [bool]$MissingSummaryText  = [string]::IsNullOrWhiteSpace($BodyCursor);
            [bool]$MalformedLinkPrefix = ($BodyCursor -match '^\[#\d+\]\(');

            if ($LeadingLinksOnLine -eq 0 -or $MissingSummaryText -or $MalformedLinkPrefix) {
                $HasUnlinkedBullet = $true;
            }
        }

        if ($HasUnlinkedBullet) {
            $Violations += ('Unlinked changelog entry in {0}: Every added changelog bullet on Pull Request #{1} must begin with "[#<PR>]({2}/pull/<PR>) <Summary>". Run ".\build\Update-ModuleChangelog.ps1", commit {0}, and push.' -f $ChangelogRel, $ResolvedPrNumber, $ResolvedRepoUrl);
        }

        if (-not $HasCurrentPrBullet) {
            $Violations += ('Missing Pull Request #{0} link in {1}: At least one added changelog bullet must begin with "[#{0}]({2}/pull/{0}) <Summary>". Run ".\build\Update-ModuleChangelog.ps1", commit {1}, and push.' -f $ResolvedPrNumber, $ChangelogRel, $ResolvedRepoUrl);
        }
    }

    return $Violations;
}

[array]$AllChangelogViolations = Invoke-IcingaChangelogGovernanceCheck -RepoRoot $ModuleBasePath -ScriptRootPath $PSScriptRoot -ExplicitBase $BaseBranch -ExplicitBranch $CurrentBranch -ExplicitPrNumber $PullRequestNumber -ExplicitRepoUrl $RepositoryUrl;

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

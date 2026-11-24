<#
.SYNOPSIS
Automatically stamp GitHub Pull Request links onto Changelog.md bullet entries

.DESCRIPTION
Resolves the canonical project URL (`https://github.com/Icinga/IcingaForWindows`
from `IcingaForWindows.psd1`) and stamps clickable `[#<PR>](<RepoUrl>/pull/<PR>)`
links onto newly added top-level `* ...` bullet entries in `docs/General/Changelog.md`
without requiring any GitHub credentials, personal access tokens, or secrets.

In default branch mode, the script selects the closest merge-base across
`upstream/main`, `origin/main`, and `main` (or `origin/$env:GITHUB_BASE_REF` in CI),
resolves the active Pull Request number from `-PullRequestNumber`,
`$env:GITHUB_EVENT_PATH`, or GitHub's unauthenticated REST API
(`/repos/<owner>/<repo>/commits/<sha>/pulls`, fork-aware `/pulls?state=open&head=...`,
and bounded ancestor fallback), and prefixes every unlinked newly added top-level
bullet entry as UTF-8 without BOM while leaving indented sub-bullets and fenced
code blocks untouched.

When `-SyncHistory` is specified, the script inspects unlinked top-level bullets
inside the current `Unreleased` version section of `docs/General/Changelog.md`,
resolves each originating commit via trailing `(<sha>)` placeholders or `git blame`,
looks up the corresponding merged Pull Request via GitHub's public REST API,
prepends `[#<PR>](...)`, and removes superseded trailing `(<sha>)` placeholders.

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                                   | Default                       |
|----------------|---------------|-------------------------------------------------------------------------------|-------------------------------|
| ModuleBasePath | System.String | Absolute path to the Icinga for Windows module root (the folder above `src`). | Resolved from the script path |

.PARAMETER PullRequestNumber
| Name              | Type         | Description                                                                   | Default                               |
|-------------------|--------------|-------------------------------------------------------------------------------|---------------------------------------|
| PullRequestNumber | System.Int32 | Optional explicit Pull Request number (bypasses GitHub REST API lookup).      | Detected from CI or GitHub public API |

.PARAMETER RepositoryUrl
| Name          | Type          | Description                                                                    | Default                                     |
|---------------|---------------|--------------------------------------------------------------------------------|---------------------------------------------|
| RepositoryUrl | System.String | Canonical GitHub repository base URL used when formatting `/pull/<PR>` links.  | `PrivateData.PSData.ProjectUri` in manifest |

.PARAMETER BaseBranch
| Name       | Type          | Description                                                                   | Default                                                  |
|------------|---------------|-------------------------------------------------------------------------------|----------------------------------------------------------|
| BaseBranch | System.String | Optional explicit Git base ref to compare against in default branch mode.     | Closest of `upstream/main`, `origin/main`, or `main`     |

.PARAMETER SyncHistory
| Name        | Type                                         | Description                                                                   | Default |
|-------------|----------------------------------------------|-------------------------------------------------------------------------------|---------|
| SyncHistory | System.Management.Automation.SwitchParameter | Backfill missing `[#<PR>](...)` links across existing `Unreleased` bullets.   | False   |

.OUTPUTS
System.Boolean -- Returns `$true` when `docs/General/Changelog.md` is validly linked (or already up to date), or `$false` when no open Pull Request or valid net-new bullet is available yet.

.EXAMPLE
PS> .\build\Update-ModuleChangelog.ps1

Queries GitHub's public unauthenticated API for the open Pull Request matching
the current branch (including external forks) and stamps
`[#<PR>](https://github.com/Icinga/IcingaForWindows/pull/<PR>)` onto unlinked
top-level bullets added on this branch.

.EXAMPLE
PS> .\build\Update-ModuleChangelog.ps1 -PullRequestNumber 42

Stamps `[#42](https://github.com/Icinga/IcingaForWindows/pull/42)` onto unlinked
branch changelog bullets offline without performing any network requests.

.EXAMPLE
PS> .\build\Update-ModuleChangelog.ps1 -SyncHistory

Backfills `[#<PR>](...)` links onto historical unlinked bullets under the
`Unreleased` section of `docs/General/Changelog.md`.

.NOTES
Uses zero stored credentials, tokens, or secrets. Requires `git` on `PATH`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>

[CmdletBinding()]
param (
    [string]$ModuleBasePath = $null,
    [int]$PullRequestNumber = 0,
    [string]$RepositoryUrl  = $null,
    [string]$BaseBranch     = $null,
    [switch]$SyncHistory    = $false
);

$ErrorActionPreference     = 'Stop';
$ProgressPreference        = 'SilentlyContinue';
$script:LastGitHubApiError = '';
$script:GitHubRateLimited  = $false;

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

function Get-GitHubOwnerAndRepo()
{
    param (
        [string]$RepoUrl = ''
    );

    if ($RepoUrl -match '^https?://github\.com/([^/\s]+)/([^/\s]+)$') {
        return @{
            'Owner' = $Matches[1];
            'Repo'  = $Matches[2];
        };
    }

    return $null;
}

function Get-SanitizedRemoteOwner()
{
    param (
        [string]$RepoRoot   = '',
        [string]$RemoteName = ''
    );

    if ([string]::IsNullOrWhiteSpace($RemoteName)) {
        return '';
    }

    [hashtable]$UrlResult = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'remote', 'get-url', $RemoteName.Trim() );
    if ($UrlResult['ExitCode'] -ne 0) {
        return '';
    }

    [string]$RawUrl = ([string]$UrlResult['StdOut']).Trim();

    # Extract strictly the GitHub owner path segment and discard everything else so any embedded userinfo is never retained
    if ($RawUrl -match '^(?:https?://(?:[^/@\s]+@)?github\.com/|ssh://(?:[^/@\s]+@)?github\.com/|git@github\.com:)([^/\s:]+)/([^/\s]+?)(?:\.git)?/?$') {
        return [string]$Matches[1];
    }

    return '';
}

function Get-CandidatePullRequestHeadFilters()
{
    param (
        [string]$RepoRoot       = '',
        [string]$CanonicalOwner = '',
        [string]$LocalBranch    = ''
    );

    [array]$Filters         = @();
    [hashtable]$Seen        = @{ };
    [array]$RemoteOrder     = @();
    [string]$TrackRef       = '';

    [hashtable]$UpstreamRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}' );
    if ($UpstreamRes['ExitCode'] -eq 0) {
        $TrackRef = ([string]$UpstreamRes['StdOut']).Trim();
        if ($TrackRef -match '^([^/\s]+)/(.+)$') {
            [string]$TrackRemote = $Matches[1];
            [string]$TrackBranch = $Matches[2];
            [string]$TrackOwner  = Get-SanitizedRemoteOwner -RepoRoot $RepoRoot -RemoteName $TrackRemote;
            if (-not [string]::IsNullOrWhiteSpace($TrackOwner) -and -not [string]::IsNullOrWhiteSpace($TrackBranch) -and $TrackBranch -ne 'main') {
                [string]$TrackFilter = ('{0}:{1}' -f $TrackOwner, $TrackBranch);
                if (-not $Seen.ContainsKey($TrackFilter)) {
                    $Seen[$TrackFilter] = $true;
                    $Filters           += $TrackFilter;
                }
            }
            $RemoteOrder += $TrackRemote;
        }
    }

    [array]$ConfigKeys = @(
        ('branch.{0}.pushRemote' -f $LocalBranch),
        'remote.pushDefault',
        ('branch.{0}.remote' -f $LocalBranch)
    );

    foreach ($CfgKey in $ConfigKeys) {
        [hashtable]$CfgRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'config', '--get', $CfgKey );
        if ($CfgRes['ExitCode'] -eq 0) {
            [string]$CfgVal = ([string]$CfgRes['StdOut']).Trim();
            if (-not [string]::IsNullOrWhiteSpace($CfgVal)) {
                $RemoteOrder += $CfgVal;
            }
        }
    }

    $RemoteOrder             += 'origin';

    [hashtable]$AllRemotesRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'remote' );
    if ($AllRemotesRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($AllRemotesRes['StdOut'])) {
        foreach ($RemLine in ($AllRemotesRes['StdOut'] -split '\r?\n')) {
            [string]$TrimRem = ([string]$RemLine).Trim();
            if (-not [string]::IsNullOrWhiteSpace($TrimRem)) {
                $RemoteOrder += $TrimRem;
            }
        }
    }

    foreach ($RemoteCandidate in $RemoteOrder) {
        [string]$RemOwner = Get-SanitizedRemoteOwner -RepoRoot $RepoRoot -RemoteName $RemoteCandidate;
        if (-not [string]::IsNullOrWhiteSpace($RemOwner)) {
            [string]$CandFilter = ('{0}:{1}' -f $RemOwner, $LocalBranch);
            if (-not $Seen.ContainsKey($CandFilter)) {
                $Seen[$CandFilter] = $true;
                $Filters          += $CandFilter;
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($CanonicalOwner)) {
        [string]$CanonicalFilter = ('{0}:{1}' -f $CanonicalOwner, $LocalBranch);
        if (-not $Seen.ContainsKey($CanonicalFilter)) {
            $Seen[$CanonicalFilter] = $true;
            $Filters               += $CanonicalFilter;
        }
    }

    return $Filters;
}

function Enable-Tls12Support()
{
    try {
        [System.Net.SecurityProtocolType]$CurrentProtocol = [System.Net.ServicePointManager]::SecurityProtocol;
        [bool]$MissingTls12                               = (($CurrentProtocol -band [System.Net.SecurityProtocolType]::Tls12) -eq 0);
        if ($MissingTls12) {
            [System.Net.ServicePointManager]::SecurityProtocol = ($CurrentProtocol -bor [System.Net.SecurityProtocolType]::Tls12);
        }
    } catch {
        # Modern .NET runtimes manage TLS cipher negotiation automatically via the OS stack
        $null = $_;
    }
}

function Get-GitHubPublicApiHeaders()
{
    return @{
        'Accept'               = 'application/vnd.github+json';
        'User-Agent'           = 'IcingaForWindows-ChangelogUpdater';
        'X-GitHub-Api-Version' = '2022-11-28';
    };
}

function Get-ExceptionHttpStatusCode()
{
    param (
        [object]$ErrorRecord = $null
    );

    if ($null -eq $ErrorRecord -or $null -eq $ErrorRecord.Exception) {
        return 0;
    }

    try {
        $ResponseObj = $ErrorRecord.Exception.Response;
        if ($null -ne $ResponseObj -and $null -ne $ResponseObj.StatusCode) {
            return ([int]$ResponseObj.StatusCode);
        }
    } catch {
        return 0;
    }

    return 0;
}

function Invoke-GitHubPublicGet()
{
    param (
        [string]$Uri              = '',
        [bool]$IgnoreNotFoundCode = $false
    );

    if ($script:GitHubRateLimited) {
        return $null;
    }

    Enable-Tls12Support;
    [hashtable]$Headers = Get-GitHubPublicApiHeaders;

    try {
        $Response = Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -TimeoutSec 15 -ErrorAction Stop;
        return $Response;
    } catch {
        [int]$StatusCode = Get-ExceptionHttpStatusCode -ErrorRecord $_;
        if ($IgnoreNotFoundCode -and ($StatusCode -eq 404 -or $StatusCode -eq 422)) {
            return $null;
        }
        if ($StatusCode -eq 403 -or $StatusCode -eq 429) {
            $script:GitHubRateLimited  = $true;
            $script:LastGitHubApiError = ('GitHub public API rate limit or access restriction (HTTP {0})' -f $StatusCode);
            return $null;
        }
        if ($StatusCode -gt 0) {
            $script:LastGitHubApiError = ('HTTP {0} from GitHub public API' -f $StatusCode);
        } else {
            $script:LastGitHubApiError = [string]$_.Exception.Message;
        }
        return $null;
    }
}

function Get-PullRequestNumberFromEventFile()
{
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

function Get-PullRequestForCommitSha()
{
    param (
        [string]$Owner            = '',
        [string]$Repo             = '',
        [string]$CommitSha        = '',
        [bool]$RequireOpen        = $false,
        [string]$PreferredBaseRef = ''
    );

    if ([string]::IsNullOrWhiteSpace($Owner) -or [string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($CommitSha)) {
        return 0;
    }

    [string]$Uri  = ('https://api.github.com/repos/{0}/{1}/commits/{2}/pulls' -f $Owner, $Repo, $CommitSha.Trim());
    $Response     = Invoke-GitHubPublicGet -Uri $Uri -IgnoreNotFoundCode $true;
    [array]$Pulls = @();

    if ($null -ne $Response) {
        $Pulls = @($Response);
    }

    [array]$Candidates = @();

    foreach ($Item in $Pulls) {
        if ($null -eq $Item -or $null -eq $Item.number) {
            continue;
        }
        [int]$PrNum = 0;
        if (-not [int]::TryParse([string]$Item.number, [ref]$PrNum) -or $PrNum -le 0) {
            continue;
        }
        if ($RequireOpen -and [string]$Item.state -ne 'open') {
            continue;
        }
        $Candidates += $Item;
    }

    if ($Candidates.Count -eq 0) {
        return 0;
    }

    if (-not [string]::IsNullOrWhiteSpace($PreferredBaseRef)) {
        foreach ($Cand in $Candidates) {
            if ($null -ne $Cand.base -and [string]$Cand.base.ref -eq $PreferredBaseRef) {
                return ([int]$Cand.number);
            }
        }
    }

    foreach ($Cand in $Candidates) {
        if ([string]$Cand.state -eq 'open' -or $null -ne $Cand.merged_at) {
            return ([int]$Cand.number);
        }
    }

    return ([int]$Candidates[0].number);
}

function Resolve-ActivePullRequestNumber()
{
    param (
        [string]$RepoRoot         = '',
        [int]$ExplicitPrNumber    = 0,
        [string]$RepoUrl          = '',
        [string]$MergeBaseSha     = '',
        [string]$PreferredBaseRef = ''
    );

    if ($ExplicitPrNumber -gt 0) {
        return $ExplicitPrNumber;
    }

    [int]$EventPr = Get-PullRequestNumberFromEventFile;
    if ($EventPr -gt 0) {
        return $EventPr;
    }

    $RepoMeta = Get-GitHubOwnerAndRepo -RepoUrl $RepoUrl;
    if ($null -eq $RepoMeta) {
        return 0;
    }

    [string]$Owner      = $RepoMeta['Owner'];
    [string]$Repo       = $RepoMeta['Repo'];
    [hashtable]$HeadRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'rev-parse', 'HEAD' );
    [string]$HeadSha    = ([string]$HeadRes['StdOut']).Trim();

    if ($HeadRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($HeadSha)) {
        [int]$HeadPr = Get-PullRequestForCommitSha -Owner $Owner -Repo $Repo -CommitSha $HeadSha -RequireOpen $true -PreferredBaseRef $PreferredBaseRef;
        if ($HeadPr -gt 0) {
            return $HeadPr;
        }
    }

    # Fallback 1: Query open Pull Requests matching fork/origin/canonical <owner>:<branch> in a single call per unique remote owner
    [hashtable]$BranchRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'rev-parse', '--abbrev-ref', 'HEAD' );
    [string]$BranchName   = ([string]$BranchRes['StdOut']).Trim();
    [bool]$CanQueryBranch = ($BranchRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($BranchName) -and $BranchName -ne 'HEAD' -and $BranchName -ne 'main');

    if ($CanQueryBranch -and -not $script:GitHubRateLimited) {
        [array]$HeadFilters = Get-CandidatePullRequestHeadFilters -RepoRoot $RepoRoot -CanonicalOwner $Owner -LocalBranch $BranchName;
        foreach ($HeadFilter in $HeadFilters) {
            if ($script:GitHubRateLimited) {
                break;
            }
            [string]$PullsUri = ('https://api.github.com/repos/{0}/{1}/pulls?state=open&head={2}' -f $Owner, $Repo, [System.Uri]::EscapeDataString($HeadFilter));
            $OpenResponse     = Invoke-GitHubPublicGet -Uri $PullsUri -IgnoreNotFoundCode $false;
            if ($null -ne $OpenResponse) {
                [array]$OpenPulls = @($OpenResponse);
                foreach ($OpenItem in $OpenPulls) {
                    if ($null -ne $OpenItem -and $null -ne $OpenItem.number -and [int]$OpenItem.number -gt 0) {
                        if ([string]::IsNullOrWhiteSpace($PreferredBaseRef) -or ($null -ne $OpenItem.base -and [string]$OpenItem.base.ref -eq $PreferredBaseRef)) {
                            return ([int]$OpenItem.number);
                        }
                    }
                }
                foreach ($OpenItem in $OpenPulls) {
                    if ($null -ne $OpenItem -and $null -ne $OpenItem.number -and [int]$OpenItem.number -gt 0) {
                        return ([int]$OpenItem.number);
                    }
                }
            }
        }
    }

    # Fallback 2: Bounded ancestor commit check (for detached HEAD with unpushed local commits on top of an open PR)
    if (-not [string]::IsNullOrWhiteSpace($MergeBaseSha) -and -not $script:GitHubRateLimited) {
        [hashtable]$RevRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'rev-list', '--max-count=3', ('{0}..HEAD' -f $MergeBaseSha) );
        if ($RevRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($RevRes['StdOut'])) {
            foreach ($RawRev in ($RevRes['StdOut'] -split '\r?\n')) {
                if ($script:GitHubRateLimited) {
                    break;
                }
                [string]$CandidateSha = ([string]$RawRev).Trim();
                if ([string]::IsNullOrWhiteSpace($CandidateSha) -or $CandidateSha -eq $HeadSha) {
                    continue;
                }
                [int]$AncestorPr = Get-PullRequestForCommitSha -Owner $Owner -Repo $Repo -CommitSha $CandidateSha -RequireOpen $true -PreferredBaseRef $PreferredBaseRef;
                if ($AncestorPr -gt 0) {
                    return $AncestorPr;
                }
            }
        }
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

function Get-ChangelogBulletLinkState()
{
    param (
        [string]$Line            = '',
        [string]$ResolvedRepoUrl = ''
    );

    if ($Line -notmatch '^( ?\*\s+)(\S.*)$') {
        return @{
            'Status'    = 'NotTopLevelBullet';
            'Prefix'    = '';
            'Body'      = '';
            'LinkedPrs' = @();
        };
    }

    [string]$BulletPrefix     = $Matches[1];
    [string]$BulletBody       = $Matches[2];
    [string]$EscapedRepoUrl   = [regex]::Escape($ResolvedRepoUrl);
    [string]$LeadingLinkRegex = ('^\[#(?<pr>[1-9]\d*)\]\({0}/pull/\k<pr>\)(?:\s+|$)' -f $EscapedRepoUrl);
    [string]$BodyCursor       = $BulletBody;
    [array]$LinkedPrs         = @();

    while ($BodyCursor -match $LeadingLinkRegex) {
        [string]$MatchedToken = $Matches[0];
        $LinkedPrs           += ([int]$Matches['pr']);
        $BodyCursor           = $BodyCursor.Substring($MatchedToken.Length);
        if (-not ($MatchedToken -match '\s+$') -and -not [string]::IsNullOrEmpty($BodyCursor)) {
            # Missing required whitespace between "[#<PR>](...)" and summary text
            return @{
                'Status'    = 'Malformed';
                'Prefix'    = $BulletPrefix;
                'Body'      = $BulletBody;
                'LinkedPrs' = $LinkedPrs;
            };
        }
    }

    if ($BodyCursor -match '^\[#\d+\]\(') {
        return @{
            'Status'    = 'Malformed';
            'Prefix'    = $BulletPrefix;
            'Body'      = $BulletBody;
            'LinkedPrs' = $LinkedPrs;
        };
    }

    if ($LinkedPrs.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($BodyCursor)) {
            return @{
                'Status'    = 'Malformed';
                'Prefix'    = $BulletPrefix;
                'Body'      = $BulletBody;
                'LinkedPrs' = $LinkedPrs;
            };
        }

        return @{
            'Status'    = 'ValidLinked';
            'Prefix'    = $BulletPrefix;
            'Body'      = $BulletBody;
            'LinkedPrs' = $LinkedPrs;
        };
    }

    return @{
        'Status'    = 'NeedsStamping';
        'Prefix'    = $BulletPrefix;
        'Body'      = $BulletBody;
        'LinkedPrs' = @();
    };
}

function Invoke-ChangelogHistorySync()
{
    param (
        [string]$RepoRoot        = '',
        [string]$ChangelogAbs    = '',
        [string]$ChangelogRel    = '',
        [string]$ResolvedRepoUrl = ''
    );

    $RepoMeta = Get-GitHubOwnerAndRepo -RepoUrl $ResolvedRepoUrl;
    if ($null -eq $RepoMeta) {
        throw ('Cannot run -SyncHistory: RepositoryUrl "{0}" is not a standard https://github.com/<owner>/<repo> URL.' -f $ResolvedRepoUrl);
    }

    $script:LastGitHubApiError = '';
    $script:GitHubRateLimited  = $false;

    [string]$Owner             = $RepoMeta['Owner'];
    [string]$Repo              = $RepoMeta['Repo'];
    [string]$RawContent        = [System.IO.File]::ReadAllText($ChangelogAbs, [System.Text.Encoding]::UTF8);
    [string]$NewLine           = "`n";
    if ($RawContent.Contains("`r`n")) {
        $NewLine = "`r`n";
    }

    [bool]$HadFinalNewline   = $RawContent.EndsWith("`n");
    [string]$TrimmedTrailing = ($RawContent -replace '\r?\n\z', '');
    [array]$Lines            = @($TrimmedTrailing -split '\r?\n');
    [array]$FenceMask        = Get-MarkdownCodeFenceMask -Lines $Lines;
    [hashtable]$CommitCache  = @{ };
    [bool]$InUnreleased      = $false;
    [int]$UpdatedBullets     = 0;

    for ($idx = 0; $idx -lt $Lines.Count; $idx++) {
        if ($FenceMask[$idx]) {
            continue;
        }

        [string]$Line = $Lines[$idx];

        if ($Line -match '(?i)^##\s+v?\d+\.\d+\.\d+\s+\(Unreleased\)') {
            $InUnreleased = $true;
            continue;
        }
        if ($InUnreleased -and $Line -match '^##\s+') {
            break;
        }
        if (-not $InUnreleased) {
            continue;
        }

        [hashtable]$BulletState = Get-ChangelogBulletLinkState -Line $Line -ResolvedRepoUrl $ResolvedRepoUrl;
        if ($BulletState['Status'] -ne 'NeedsStamping') {
            continue;
        }

        [string]$BulletPrefix = $BulletState['Prefix'];
        [string]$BulletBody   = $BulletState['Body'];
        [string]$CommitSha    = '';
        [bool]$HasTrailingSha = $false;

        if ($BulletBody -match '\s+\(`?([0-9a-f]{7,40})`?\)\s*$') {
            [string]$ShaCandidate = $Matches[1];
            [hashtable]$RevRes    = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'rev-parse', '--verify', '--quiet', ('{0}^{{commit}}' -f $ShaCandidate) );
            [string]$FullCommit   = ([string]$RevRes['StdOut']).Trim();
            if ($RevRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($FullCommit)) {
                $CommitSha      = $FullCommit;
                $HasTrailingSha = $true;
            }
        }

        if ([string]::IsNullOrWhiteSpace($CommitSha)) {
            [int]$OneBasedLine   = $idx + 1;
            [hashtable]$BlameRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'blame', '--line-porcelain', '-L', ('{0},{0}' -f $OneBasedLine), '--', $ChangelogRel );
            if ($BlameRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($BlameRes['StdOut'])) {
                [array]$BlameLines = @($BlameRes['StdOut'] -split '\r?\n');
                [string]$FirstLine = ([string]$BlameLines[0]).Trim();
                if ($FirstLine -match '^([0-9a-f]{40})\s+' -and $Matches[1] -ne '0000000000000000000000000000000000000000') {
                    $CommitSha = $Matches[1];
                }
            }
        }

        if ([string]::IsNullOrWhiteSpace($CommitSha)) {
            continue;
        }

        if (-not $CommitCache.ContainsKey($CommitSha)) {
            if ($script:GitHubRateLimited) {
                break;
            }
            $CommitCache[$CommitSha] = Get-PullRequestForCommitSha -Owner $Owner -Repo $Repo -CommitSha $CommitSha -RequireOpen $false -PreferredBaseRef 'main';
        }

        [int]$ResolvedPr = [int]$CommitCache[$CommitSha];
        if ($ResolvedPr -le 0) {
            continue;
        }

        if ($HasTrailingSha) {
            $BulletBody = ($BulletBody -replace '\s+\(`?[0-9a-f]{7,40}`?\)\s*$', '');
        }

        $Lines[$idx] = ('{0}[#{1}]({2}/pull/{1}) {3}' -f $BulletPrefix, $ResolvedPr, $ResolvedRepoUrl, $BulletBody);
        $UpdatedBullets++;
    }

    if ($UpdatedBullets -gt 0) {
        [string]$NewContent = ($Lines -join $NewLine);
        if ($HadFinalNewline) {
            $NewContent += $NewLine;
        }
        $Utf8NoBom = New-Object System.Text.UTF8Encoding($false);
        [System.IO.File]::WriteAllText($ChangelogAbs, $NewContent, $Utf8NoBom);
        Write-Host ('  * Backfilled PR links on {0} historical changelog bullet(s) in {1}' -f $UpdatedBullets, $ChangelogRel) -ForegroundColor Green;
    }

    if (-not [string]::IsNullOrWhiteSpace($script:LastGitHubApiError)) {
        Write-Host ('[WARN] Historical PR lookup encountered a GitHub public API error ({0}). Retry once connectivity or rate limits reset.' -f $script:LastGitHubApiError) -ForegroundColor Yellow;
        return $false;
    }

    if ($UpdatedBullets -eq 0) {
        Write-Host ('  * No unlinked historical bullets with matching GitHub PRs found in {0}' -f $ChangelogRel) -ForegroundColor Green;
    }

    return $true;
}

function Invoke-BranchChangelogUpdate()
{
    param (
        [string]$RepoRoot         = '',
        [string]$ChangelogAbs     = '',
        [string]$ChangelogRel     = '',
        [string]$ResolvedRepoUrl  = '',
        [int]$ExplicitPrNumber    = 0,
        [string]$ExplicitBaseName = ''
    );

    $script:LastGitHubApiError = '';
    $script:GitHubRateLimited  = $false;

    [hashtable]$BaseInfo       = Resolve-ComparisonMergeBase -RepoRoot $RepoRoot -ExplicitBase $ExplicitBaseName;
    if ([int]$BaseInfo['ExistingCount'] -eq 0) {
        throw 'Unable to resolve base Git branch ("upstream/main", "origin/main", or "main") for changelog diffing.';
    }

    [string]$ResolvedBase = [string]$BaseInfo['ResolvedBase'];
    [string]$MergeBase    = [string]$BaseInfo['MergeBase'];

    if ([string]::IsNullOrEmpty($MergeBase)) {
        throw ('Unable to compute Git merge-base between "{0}" and HEAD.' -f [string]$BaseInfo['FirstExisting']);
    }

    [string]$RawContent = [System.IO.File]::ReadAllText($ChangelogAbs, [System.Text.Encoding]::UTF8);
    [string]$NewLine    = "`n";
    if ($RawContent.Contains("`r`n")) {
        $NewLine = "`r`n";
    }

    [bool]$HadFinalNewline   = $RawContent.EndsWith("`n");
    [string]$TrimmedTrailing = ($RawContent -replace '\r?\n\z', '');
    [array]$Lines            = @($TrimmedTrailing -split '\r?\n');
    [array]$FenceMask        = Get-MarkdownCodeFenceMask -Lines $Lines;

    [hashtable]$TreeRes      = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'ls-tree', '-r', '--name-only', $MergeBase, '--', $ChangelogRel );
    [bool]$ExistedInBase     = ($TreeRes['ExitCode'] -eq 0 -and -not [string]::IsNullOrWhiteSpace($TreeRes['StdOut']));
    [array]$AddedLineIndices = @();
    [int]$RemovedBullets     = 0;

    if (-not $ExistedInBase) {
        for ($idx = 0; $idx -lt $Lines.Count; $idx++) {
            if (-not $FenceMask[$idx] -and $Lines[$idx] -match '^ ?\*\s+\S+') {
                $AddedLineIndices += $idx;
            }
        }
    } else {
        [hashtable]$DiffRes = Invoke-GitProcess -RepoPath $RepoRoot -GitArgs @( 'diff', '--unified=0', '--ignore-cr-at-eol', $MergeBase, '--', $ChangelogRel );
        if ($DiffRes['ExitCode'] -ne 0) {
            throw ('Failed to execute "git diff" against merge-base "{0}" for {1}.' -f $MergeBase, $ChangelogRel);
        }

        [array]$DiffLines = @();
        if (-not [string]::IsNullOrEmpty($DiffRes['StdOut'])) {
            $DiffLines = @($DiffRes['StdOut'] -split '\r?\n');
        }

        [int]$CurrentNewLine = 0;
        [bool]$InHunk        = $false;

        foreach ($RawDiffLine in $DiffLines) {
            [string]$DiffStr = ([string]$RawDiffLine).TrimEnd("`r");

            if ($DiffStr -match '^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,(\d+))?\s+@@') {
                $CurrentNewLine = [int]$Matches[1];
                $InHunk         = $true;
                continue;
            }

            if (-not $InHunk -or $DiffStr.StartsWith('\')) {
                continue;
            }

            if ($DiffStr.StartsWith('+')) {
                [int]$ZeroBasedIdx = $CurrentNewLine - 1;
                if ($ZeroBasedIdx -ge 0 -and $ZeroBasedIdx -lt $Lines.Count -and -not $FenceMask[$ZeroBasedIdx]) {
                    if ($Lines[$ZeroBasedIdx] -match '^ ?\*\s+\S+') {
                        $AddedLineIndices += $ZeroBasedIdx;
                    }
                }
                $CurrentNewLine++;
            } elseif ($DiffStr.StartsWith('-')) {
                [string]$RemovedText = $DiffStr.Substring(1);
                if ($RemovedText -match '^ ?\*\s+\S+') {
                    $RemovedBullets++;
                }
            }
        }
    }

    if ($AddedLineIndices.Count -le $RemovedBullets) {
        Write-Host ('[WARN] No net-new "* " changelog bullets found in {0} compared to {1}. Add a "* <Summary>" bullet entry under the Unreleased section first.' -f $ChangelogRel, $ResolvedBase) -ForegroundColor Yellow;
        return $false;
    }

    [array]$UnlinkedIndices = @();
    [array]$MalformedLines  = @();
    [array]$ExistingPrNums  = @();

    foreach ($LineIdx in $AddedLineIndices) {
        [hashtable]$State = Get-ChangelogBulletLinkState -Line $Lines[$LineIdx] -ResolvedRepoUrl $ResolvedRepoUrl;
        if ($State['Status'] -eq 'NeedsStamping') {
            $UnlinkedIndices += $LineIdx;
        } elseif ($State['Status'] -eq 'Malformed') {
            $MalformedLines += ($LineIdx + 1);
        } elseif ($State['Status'] -eq 'ValidLinked') {
            $ExistingPrNums += @($State['LinkedPrs']);
        }
    }

    if ($MalformedLines.Count -gt 0) {
        Write-Host ('[WARN] Malformed PR link or missing summary text on line(s) {0} in {1}. Expected "* [#<PR>]({2}/pull/<PR>) <Summary>".' -f ($MalformedLines -join ', '), $ChangelogRel, $ResolvedRepoUrl) -ForegroundColor Yellow;
        return $false;
    }

    [string]$PreferredBaseName = ($ResolvedBase -replace '^(?:origin|upstream)/', '');

    if ($UnlinkedIndices.Count -eq 0) {
        [int]$ActivePrCheck = Resolve-ActivePullRequestNumber -RepoRoot $RepoRoot -ExplicitPrNumber $ExplicitPrNumber -RepoUrl $ResolvedRepoUrl -MergeBaseSha $MergeBase -PreferredBaseRef $PreferredBaseName;
        if ($ActivePrCheck -gt 0 -and ($ExistingPrNums -notcontains $ActivePrCheck)) {
            Write-Host ('[WARN] Newly added changelog bullet(s) in {0} do not reference active Pull Request #{1}. Add a "* <Summary>" bullet for Pull Request #{1} first.' -f $ChangelogRel, $ActivePrCheck) -ForegroundColor Yellow;
            return $false;
        }

        Write-Host ('  * All {0} newly added changelog bullet(s) in {1} already carry a valid PR link' -f $AddedLineIndices.Count, $ChangelogRel) -ForegroundColor Green;
        return $true;
    }

    [int]$ResolvedPr = Resolve-ActivePullRequestNumber -RepoRoot $RepoRoot -ExplicitPrNumber $ExplicitPrNumber -RepoUrl $ResolvedRepoUrl -MergeBaseSha $MergeBase -PreferredBaseRef $PreferredBaseName;

    if ($ResolvedPr -le 0) {
        if (-not [string]::IsNullOrWhiteSpace($script:LastGitHubApiError)) {
            Write-Host ('[WARN] Could not query GitHub public API ({0}). Pass -PullRequestNumber <ID> explicitly or retry once connectivity/rate-limit resets.' -f $script:LastGitHubApiError) -ForegroundColor Yellow;
        } else {
            Write-Host '[INFO] No open Pull Request found on GitHub for current branch HEAD yet. Push your branch and open a Pull Request first, then re-run ".\build\Update-ModuleChangelog.ps1" (or pass -PullRequestNumber <ID>).' -ForegroundColor Cyan;
        }
        return $false;
    }

    foreach ($TargetIdx in $UnlinkedIndices) {
        if ($Lines[$TargetIdx] -match '^( ?\*\s+)(\S.*)$') {
            [string]$Prefix    = $Matches[1];
            [string]$BodyText  = $Matches[2];
            [string]$CleanBody = ($BodyText -replace ('^(?:[\(\[]?#{0}[\)\]]?(?:[:\s-]+|$))+' -f $ResolvedPr), '').Trim();
            if ([string]::IsNullOrWhiteSpace($CleanBody)) {
                Write-Host ('[WARN] Changelog bullet on line {0} in {1} has no summary text after "#{2}". Add a descriptive summary first.' -f ($TargetIdx + 1), $ChangelogRel, $ResolvedPr) -ForegroundColor Yellow;
                return $false;
            }
            $Lines[$TargetIdx] = ('{0}[#{1}]({2}/pull/{1}) {3}' -f $Prefix, $ResolvedPr, $ResolvedRepoUrl, $CleanBody);
        }
    }

    [string]$UpdatedContent = ($Lines -join $NewLine);
    if ($HadFinalNewline) {
        $UpdatedContent += $NewLine;
    }

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false);
    [System.IO.File]::WriteAllText($ChangelogAbs, $UpdatedContent, $Utf8NoBom);
    Write-Host ('  * Stamped [#{0}]({1}/pull/{0}) onto {2} changelog bullet(s) in {3}' -f $ResolvedPr, $ResolvedRepoUrl, $UnlinkedIndices.Count, $ChangelogRel) -ForegroundColor Green;
    return $true;
}

[string]$ChangelogRelPath = 'docs/General/Changelog.md';
[string]$ChangelogAbsPath = Join-Path -Path $ModuleBasePath -ChildPath (Join-Path -Path 'docs' -ChildPath (Join-Path -Path 'General' -ChildPath 'Changelog.md'));

if (-not (Test-Path -Path $ChangelogAbsPath -PathType Leaf)) {
    throw ('Required file not found: {0}' -f $ChangelogAbsPath);
}

[string]$CanonicalRepoUrl = Resolve-CanonicalRepositoryUrl -RepoRoot $ModuleBasePath -ScriptRootPath $PSScriptRoot -ExplicitUrl $RepositoryUrl;

Write-Host "`n[+] Running Changelog PR Link Updater..." -ForegroundColor Yellow;

if ($SyncHistory) {
    return (Invoke-ChangelogHistorySync -RepoRoot $ModuleBasePath -ChangelogAbs $ChangelogAbsPath -ChangelogRel $ChangelogRelPath -ResolvedRepoUrl $CanonicalRepoUrl);
}

return (Invoke-BranchChangelogUpdate -RepoRoot $ModuleBasePath -ChangelogAbs $ChangelogAbsPath -ChangelogRel $ChangelogRelPath -ResolvedRepoUrl $CanonicalRepoUrl -ExplicitPrNumber $PullRequestNumber -ExplicitBaseName $BaseBranch);

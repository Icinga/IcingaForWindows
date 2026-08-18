<#
.SYNOPSIS
Run PSScriptAnalyzer over the Icinga for Windows source tree.

.DESCRIPTION
Standalone code-style gate for the CI/CD pipeline. Runs
PSScriptAnalyzer recursively over the hand-written parts of the
repository (`src/`, `build/` and the root `IcingaForWindows.psm1`)
and prints every finding grouped into build-breaking and advisory
buckets. The auto-generated `lib/` and `docs/api/` artifacts are
intentionally excluded because they are never edited by hand.

Which rules run is controlled by `PSScriptAnalyzerSettings.psd1` in
the module root, which switches off the rules that conflict with the
documented house style (UTF-8 without BOM, the `$Global:` runtime
state, intentional plural nouns, Write-Host in build/logging code,
and so on). That same settings file is picked up automatically by
editor integrations.

On top of the severity model, a small set of rules is treated as
build-breaking regardless of the severity PSScriptAnalyzer assigns,
because they map directly onto mandatory CLAUDE.md house rules
(approved verbs only, no aliases in source). A finding fails the run
when it is one of those rules, when its severity is `Error`, or —
with `-FailOn 'Warning'` — when its severity is `Warning`. Everything
else is reported as advisory and does not break the build.

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                       | Default                       |
|----------------|---------------|-------------------------------------------------------------------|-------------------------------|
| ModuleBasePath | System.String | Absolute path to the Icinga module root (the folder above `src`). | Resolved from the script path |

.PARAMETER SettingsPath
| Name         | Type          | Description                                                              | Default                                       |
|--------------|---------------|--------------------------------------------------------------------------|-----------------------------------------------|
| SettingsPath | System.String | PSScriptAnalyzer settings file to apply.                                 | `<ModuleBasePath>\PSScriptAnalyzerSettings.psd1` |

.PARAMETER FailOn
| Name   | Type          | Description                                                                              | Default |
|--------|---------------|------------------------------------------------------------------------------------------|---------|
| FailOn | System.String | Lowest severity that fails the run. One of `Error` or `Warning`.                         | Error   |

.OUTPUTS
System.Object[] — All analyzer findings. Throws when any build-breaking
finding is present.

.EXAMPLE
PS> .\build\Invoke-ScriptAnalysis.ps1

Analyses the source tree and fails on Error-severity findings plus the
house-rule rules elevated to errors.

.EXAMPLE
PS> .\build\Invoke-ScriptAnalysis.ps1 -FailOn 'Warning'

Treats warnings as build failures as well.

.NOTES
Requires the PSScriptAnalyzer module. In CI install it with
`Install-Module PSScriptAnalyzer -Force -SkipPublisherCheck`.
Designed for PowerShell 7.5+ on Windows.
#>

[CmdletBinding()]
param (
    [string]$ModuleBasePath = $null,
    [string]$SettingsPath   = $null,
    [ValidateSet('Error', 'Warning')]
    [string]$FailOn         = 'Error'
);

$ErrorActionPreference = 'Stop';
$ProgressPreference    = 'SilentlyContinue';

# Rules elevated to build-breaking errors. They map directly onto mandatory
# CLAUDE.md house rules and currently have zero violations, so they act as
# forward guards without flagging existing code. PSScriptAnalyzer settings
# cannot reassign rule severity, which is why this lives here and not in the
# settings file.
[string[]]$ErrorRules = @(
    'PSUseApprovedVerbs',
    'PSAvoidUsingCmdletAliases',
    'PSAvoidTrailingWhitespace'
);

if ([string]::IsNullOrEmpty($ModuleBasePath)) {
    $ModuleBasePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') | Select-Object -ExpandProperty Path;
}

if ([string]::IsNullOrEmpty($SettingsPath)) {
    $SettingsPath = Join-Path -Path $ModuleBasePath -ChildPath 'PSScriptAnalyzerSettings.psd1';
}

if ($null -eq (Get-Module -ListAvailable -Name 'PSScriptAnalyzer')) {
    throw 'PSScriptAnalyzer is required. Install it with: Install-Module PSScriptAnalyzer -Force -SkipPublisherCheck';
}

Import-Module -Name 'PSScriptAnalyzer' -Force;

Write-Host '' -ForegroundColor White;
Write-Host '╔═════════════════════════════════════════════════════════════════════╗' -ForegroundColor Cyan;
Write-Host '║                                                                     ║' -ForegroundColor Cyan;
Write-Host '║                  Icinga for Windows - Code Style                   ║' -ForegroundColor Cyan;
Write-Host '║                                                                     ║' -ForegroundColor Cyan;
Write-Host '╚═════════════════════════════════════════════════════════════════════╝' -ForegroundColor Cyan;
Write-Host '' -ForegroundColor White;

# Only the hand-written parts of the repository are analysed. lib/ and
# docs/api/ are regenerated by the build and must never be edited by hand.
[array]$AnalysisTargets = @(
    (Join-Path -Path $ModuleBasePath -ChildPath 'src'),
    (Join-Path -Path $ModuleBasePath -ChildPath 'build'),
    (Join-Path -Path $ModuleBasePath -ChildPath 'IcingaForWindows.psm1')
);

[hashtable]$AnalyzerSplat = @{ Recurse = $true };

if (Test-Path -Path $SettingsPath) {
    $AnalyzerSplat['Settings'] = $SettingsPath;
    Write-Host "  Using settings: $($SettingsPath.Substring($ModuleBasePath.Length).TrimStart('\', '/'))" -ForegroundColor Gray;
} else {
    Write-Host "  ⚠ Settings file not found, running with default rules: $SettingsPath" -ForegroundColor Yellow;
}

[array]$Findings = @();

Write-Host '' -ForegroundColor White;
Write-Host '[1/2] Analysing source files ...' -ForegroundColor Yellow;

foreach ($target in $AnalysisTargets) {
    if (-not (Test-Path -Path $target)) {
        continue;
    }

    Write-Host "  🔍 $($target.Substring($ModuleBasePath.Length).TrimStart('\', '/'))" -ForegroundColor White;
    $Findings += Invoke-ScriptAnalyzer -Path $target @AnalyzerSplat;
}

Write-Host '' -ForegroundColor White;
Write-Host '[2/2] Evaluating findings ...' -ForegroundColor Yellow;

# A finding breaks the build when it is one of the elevated house-rule rules,
# when PSScriptAnalyzer flags it as an Error, or — under -FailOn 'Warning' —
# when it is a Warning. Anything else is advisory only.
[array]$Blocking = @(
    $Findings | Where-Object {
        $_.RuleName -in $ErrorRules -or
        $_.Severity -eq 'Error' -or
        ($FailOn -eq 'Warning' -and $_.Severity -eq 'Warning')
    }
);
[array]$Advisory = @($Findings | Where-Object { $_ -notin $Blocking });

Write-Host "  Total findings:   $($Findings.Count)" -ForegroundColor White;
Write-Host "  Build-breaking:   $($Blocking.Count)" -ForegroundColor Red;
Write-Host "  Advisory:         $($Advisory.Count)" -ForegroundColor Gray;

if ($Advisory.Count -gt 0) {
    Write-Host '' -ForegroundColor White;
    Write-Host '  Advisory findings (do not fail the build):' -ForegroundColor Gray;
    $Advisory |
        Group-Object RuleName |
        Sort-Object Count -Descending |
        ForEach-Object {
            Write-Host ("    {0,-4} {1}" -f $_.Count, $_.Name) -ForegroundColor DarkGray;
        };
}

if ($Blocking.Count -gt 0) {
    Write-Host '' -ForegroundColor White;
    Write-Host '  Build-breaking findings:' -ForegroundColor Red;
    $Blocking |
        Sort-Object ScriptName, Line |
        Format-Table -AutoSize -Property Severity, RuleName, ScriptName, Line, Message |
        Out-Host;

    throw "PSScriptAnalyzer found $($Blocking.Count) build-breaking finding(s). See the table above.";
}

Write-Host '' -ForegroundColor White;
Write-Host '  ✓ No build-breaking findings' -ForegroundColor Green;

return $Findings;

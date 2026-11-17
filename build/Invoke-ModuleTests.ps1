<#
.SYNOPSIS
Run the Pester test suite for the Icinga for Windows module

.DESCRIPTION
Standalone test runner extracted from the module build so the unit
tests can be executed as their own CI/CD step, independent of the
compile and documentation stages. The script ensures the module's
parent directory is on `$env:PSModulePath` (so `Import-Module
IcingaForWindows` resolves the checked-out copy), verifies that
Pester 5 or newer is available, executes every `*.Tests.ps1` file
under `Tests/`, and throws when any test fails so the calling shell
exits with a non-zero code.

The compiled `lib/` artifact and an up-to-date manifest must exist
before this runs, because the tests import the full module. In CI
the build job produces those artifacts; locally run
`Build-ModuleProject` first.

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                                   | Default                       |
|----------------|---------------|-------------------------------------------------------------------------------|-------------------------------|
| ModuleBasePath | System.String | Absolute path to the Icinga for Windows module root (the folder above `src`). | Resolved from the script path |

.PARAMETER Path
| Name | Type          | Description                                              | Default                  |
|------|---------------|----------------------------------------------------------|--------------------------|
| Path | System.String | Directory containing the `*.Tests.ps1` files to execute. | `<ModuleBasePath>\Tests` |

.OUTPUTS
System.Object -- The Pester result object. Throws when one or more
tests fail.

.EXAMPLE
PS> .\build\Invoke-ModuleTests.ps1

Runs every test under Tests/ against the locally compiled module.

.EXAMPLE
PS> .\build\Invoke-ModuleTests.ps1 -Path '.\Tests\Join-WebPath.Tests.ps1'

Runs a single test file.

.NOTES
Requires Pester 5.0+. Imports the `IcingaForWindows` module, which
initializes `$Global:IcingaForWindows`. Designed for PowerShell 5.1+
and PowerShell 7.5+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>

[CmdletBinding()]
param (
    [string]$ModuleBasePath = $null,
    [string]$Path           = $null
);

$ErrorActionPreference = 'Stop';
$ProgressPreference    = 'SilentlyContinue';

if ([string]::IsNullOrEmpty($ModuleBasePath)) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath);
} elseif (Test-Path -Path $ModuleBasePath) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $ModuleBasePath).ProviderPath);
}

if ([string]::IsNullOrEmpty($Path)) {
    $Path = Join-Path -Path $ModuleBasePath -ChildPath 'Tests';
}

if (-not (Test-Path -Path $Path)) {
    throw "Test path not found: $Path";
}

# Ensure the compiled kernel and classes artifacts exist before running tests
$KernelPath  = Join-Path -Path $ModuleBasePath -ChildPath (Join-Path -Path 'lib' -ChildPath 'IcingaForWindows.Kernel.ps1');
$ClassesPath = Join-Path -Path $ModuleBasePath -ChildPath (Join-Path -Path 'lib' -ChildPath 'IcingaForWindows.Classes.ps1');
if (-not (Test-Path -Path $KernelPath) -or -not (Test-Path -Path $ClassesPath)) {
    Write-Host 'Kernel or classes artifact not found, building module first...' -ForegroundColor Yellow;
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Build-ModuleProject.ps1') -ModuleBasePath $ModuleBasePath -SkipTests;
}

# Make sure the checked-out module is discoverable by Import-Module. The
# module folder must be named 'IcingaForWindows'; we add its parent so
# 'Import-Module IcingaForWindows' resolves this copy rather than any other.
[string]$ModuleParent = Split-Path -Path $ModuleBasePath -Parent;

if (-not ($env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { $_ -eq $ModuleParent })) {
    $env:PSModulePath = [string]::Concat($ModuleParent, [System.IO.Path]::PathSeparator, $env:PSModulePath);
}

Write-Host '' -ForegroundColor White;
Write-Host '+---------------------------------------------------------------------+' -ForegroundColor Cyan;
Write-Host '|                                                                     |' -ForegroundColor Cyan;
Write-Host '|                      Icinga for Windows - Tests                     |' -ForegroundColor Cyan;
Write-Host '|                                                                     |' -ForegroundColor Cyan;
Write-Host '+---------------------------------------------------------------------+' -ForegroundColor Cyan;
Write-Host '' -ForegroundColor White;

# The suite targets Pester 5+. Importing it explicitly avoids silently
# running under the Pester 3 shipped with Windows PowerShell.
[array]$Pester5 = Get-Module -ListAvailable -Name 'Pester' | Where-Object { $_.Version.Major -ge 5 };

if ($Pester5.Count -eq 0) {
    throw 'Pester 5.0+ is required to run the test suite. Install it with: Install-Module Pester -MinimumVersion 5.0.0 -Force -SkipPublisherCheck';
}

Import-Module -Name 'Pester' -MinimumVersion '5.0.0' -Force;

# Unload any existing copies of the module to prevent duplicate module instances in the session
Remove-Module 'IcingaForWindows' -Force -ErrorAction SilentlyContinue;

Write-Host "[1/2] Running Pester against $Path ..." -ForegroundColor Yellow;

$PesterConfiguration                         = New-PesterConfiguration;
$PesterConfiguration.Run.Path                = $Path;
$PesterConfiguration.Run.PassThru            = $true;
$PesterConfiguration.Output.Verbosity        = 'Detailed';
$PesterConfiguration.TestResult.Enabled      = $true;
$PesterConfiguration.TestResult.OutputPath   = Join-Path -Path $ModuleBasePath -ChildPath 'TestResults.xml';
$PesterConfiguration.TestResult.OutputFormat = 'NUnitXml';

$TestResults                                 = Invoke-Pester -Configuration $PesterConfiguration;

Write-Host '' -ForegroundColor White;
Write-Host '[2/2] Evaluating results ...' -ForegroundColor Yellow;
Write-Host "  Total:   $($TestResults.TotalCount)" -ForegroundColor White;
Write-Host "  Passed:  $($TestResults.PassedCount)" -ForegroundColor Green;
Write-Host "  Failed:  $($TestResults.FailedCount)" -ForegroundColor Red;
Write-Host "  Skipped: $($TestResults.SkippedCount)" -ForegroundColor Gray;

if ($TestResults.FailedCount -gt 0) {
    Write-Host "Pester run failed: $($TestResults.FailedCount) test(s) did not pass." -ForegroundColor Red;
    Exit-Icinga -ExitCode 1;
}

Write-Host '' -ForegroundColor White;
Write-Host '  * All tests passed' -ForegroundColor Green;

Exit-Icinga -ExitCode 0;

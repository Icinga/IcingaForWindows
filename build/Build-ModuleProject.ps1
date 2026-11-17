<#
.SYNOPSIS
Compile the Icinga for Windows module classes and kernel into lib/

.DESCRIPTION
Walks `src/` in the Icinga for Windows repository, minifies PowerShell classes,
enums, and private helper functions, preserves public function help blocks, and
writes two UTF-8 without BOM artifacts under `lib/`:
- `lib/IcingaForWindows.Classes.ps1` (loaded per runspace for PS 5.1 isolation)
- `lib/IcingaForWindows.Kernel.ps1` (consolidated private + public functions)

Both generated artifacts include the Icinga GmbH SPDX license header at the top
of the file. After compilation, the script reloads `IcingaForWindows.psd1` into
the active session and optionally executes Pester tests, API documentation
generation, daemon memory-leak AST analysis, and code-styling validation.

.PARAMETER BuildModule
| Name        | Type          | Description                                            | Default |
|-------------|---------------|--------------------------------------------------------|---------|
| BuildModule | System.String | Target module build mode (currently `'core'` only).    | 'core'  |

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                        | Default                       |
|----------------|---------------|--------------------------------------------------------------------|-------------------------------|
| ModuleBasePath | System.String | Optional explicit path to the Icinga for Windows repository root.  | Resolved from the script path |

.PARAMETER SkipTests
| Name      | Type                                         | Description                                               | Default |
|-----------|----------------------------------------------|-----------------------------------------------------------|---------|
| SkipTests | System.Management.Automation.SwitchParameter | When set, skip running Pester tests after compilation.    | $false  |

.PARAMETER GenerateDocs
| Name         | Type                                         | Description                                                      | Default |
|--------------|----------------------------------------------|------------------------------------------------------------------|---------|
| GenerateDocs | System.Management.Automation.SwitchParameter | When set, regenerate `docs/Icinga.*.md` via Build-ModuleDocs.    | $false  |

.PARAMETER TestDaemonMemoryLeaks
| Name                  | Type                                         | Description                                                          | Default |
|-----------------------|----------------------------------------------|----------------------------------------------------------------------|---------|
| TestDaemonMemoryLeaks | System.Management.Automation.SwitchParameter | When set, run AST-based daemon loop and IDisposable leak validation. | $false  |

.PARAMETER TestCodeStyling
| Name            | Type                                         | Description                                                            | Default |
|-----------------|----------------------------------------------|------------------------------------------------------------------------|---------|
| TestCodeStyling | System.Management.Automation.SwitchParameter | When set, run repository-wide code-styling and SPDX header validation. | $false  |

.OUTPUTS
None -- Compiles `lib/IcingaForWindows.{Classes,Kernel}.ps1` and reloads the module.

.EXAMPLE
PS> .\build\Build-ModuleProject.ps1 -SkipTests -TestDaemonMemoryLeaks

Compiles `lib/IcingaForWindows.Classes.ps1` and `lib/IcingaForWindows.Kernel.ps1`
without running Pester and validates daemon memory-leak rules.

.EXAMPLE
PS> .\build\Build-ModuleProject.ps1 -SkipTests -GenerateDocs -TestCodeStyling

Compiles the module, regenerates API documentation, and validates code styling.

.NOTES
Designed for Windows PowerShell 5.1 and PowerShell 7+. Writes compiled files
using UTF-8 without BOM (`UTF8Encoding($false)`).

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>

[CmdletBinding()]
param (
    [string]$BuildModule           = 'core',
    [string]$ModuleBasePath        = '',
    [switch]$SkipTests             = $false,
    [switch]$GenerateDocs          = $false,
    [switch]$TestDaemonMemoryLeaks = $false,
    [switch]$TestCodeStyling       = $false
);

$ErrorActionPreference = 'Stop';
$ProgressPreference    = 'SilentlyContinue';

if ($BuildModule -eq 'core') {
    if ([string]::IsNullOrEmpty($ModuleBasePath)) {
        [array]$InstalledModules     = Get-Module -ListAvailable -Name 'IcingaForWindows';
        [string]$BuildScriptLocation = [System.IO.Path]::GetFullPath((Resolve-Path -Path $PSScriptRoot).ProviderPath);

        foreach ($module in $InstalledModules) {
            [string]$CandidateBase = [System.IO.Path]::GetFullPath((Resolve-Path -Path $module.ModuleBase).ProviderPath);
            if ($BuildScriptLocation.StartsWith($CandidateBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                $ModuleBasePath = $CandidateBase;
                break;
            }
        }
    }

    if ([string]::IsNullOrEmpty($ModuleBasePath)) {
        [string]$FallbackBase = [System.IO.Path]::GetFullPath((Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath);
        if (Test-Path -Path (Join-Path -Path $FallbackBase -ChildPath 'IcingaForWindows.psd1')) {
            $ModuleBasePath = $FallbackBase;
        }
    } elseif (Test-Path -Path $ModuleBasePath) {
        $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $ModuleBasePath).ProviderPath);
    }

    if ([string]::IsNullOrEmpty($ModuleBasePath)) {
        throw 'Could not determine module base path for Icinga for Windows module.';
    }
} else {
    # TODO: Implement non-core module builds
    throw 'Only core module builds are supported at the moment.';
}

function Read-IcingaSourceFile()
{
    [CmdletBinding()]
    param (
        [string]$Path = $null
    );

    $UTF8Encoding        = New-Object System.Text.UTF8Encoding($false);
    [string]$FileContent = [System.IO.File]::ReadAllText($Path, $UTF8Encoding);

    return $FileContent.TrimStart([char]0xFEFF);
}

function Remove-IcingaComments()
{
    [CmdletBinding()]
    param (
        [string]$Content = ''
    );

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return '';
    }

    $Tokens = $null;
    $Errors = $null;
    [void][System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$Tokens, [ref]$Errors);

    if ($null -eq $Tokens -or $Tokens.Count -eq 0) {
        return $Content;
    }

    $CommentTokens = @($Tokens | Where-Object { [string]$_.Kind -eq 'Comment' } | Sort-Object -Property { $_.Extent.StartOffset } -Descending);

    if ($CommentTokens.Count -eq 0) {
        return $Content;
    }

    [System.Text.StringBuilder]$Builder = New-Object System.Text.StringBuilder($Content);

    foreach ($token in $CommentTokens) {
        $start  = $token.Extent.StartOffset;
        $length = $token.Extent.EndOffset - $start;
        $Builder.Remove($start, $length) | Out-Null;
    }

    [string]$Result = $Builder.ToString();
    $Result         = [regex]::Replace($Result, '(?m)^\s+$', '');
    $Result         = [regex]::Replace($Result, '(\r?\n){3,}', "$1$1");

    return $Result.Trim();
}

function Write-IcingaSourceFile()
{
    [CmdletBinding()]
    param (
        [string]$Path  = $null,
        [string]$Value = ''
    );

    [System.Text.UTF8Encoding]$Utf8NoBom = New-Object System.Text.UTF8Encoding($false);
    [System.IO.File]::WriteAllText($Path, $Value, $Utf8NoBom);
}

function Get-IcingaModuleStructure()
{
    [CmdletBinding()]
    param (
        [string]$ModuleBasePath = $null
    );

    if ([string]::IsNullOrEmpty($ModuleBasePath)) {
        throw 'Module base path must be provided to analyze the module structure.';
    }

    [hashtable]$ModuleStructure  = @{
        'Classes' = @();
        'Public'  = @();
        'Private' = @();
    };
    [int]$FileCount              = 0;
    $PowerShellSourcePath        = Join-Path -Path $ModuleBasePath -ChildPath 'src';
    [string]$NormalizedSrcPrefix = $PowerShellSourcePath.Replace('/', '\').TrimEnd('\') + '\';
    [array]$SourceFiles          = Get-ChildItem -Path $PowerShellSourcePath -Recurse -Filter '*.ps1';

    foreach ($sourceFile in $SourceFiles) {
        $FileCount                                  += 1;
        # Make sure to convert to a universal path format, allowing both Unix and Windows style paths in the source files
        [string]$UniversalPath                       = $sourceFile.FullName.Replace('/', '\');
        $relativePath                                = $UniversalPath.Substring($NormalizedSrcPrefix.Length).TrimStart('\');
        [System.Collections.ArrayList]$CodeStructure = $relativePath.Split('\');

        # Classes must be checked first so they are compiled into the kernel
        # ahead of every function that may reference them at parse time.
        if ($CodeStructure -contains 'Classes') {
            $ModuleStructure['Classes'] += $sourceFile.FullName;
        } elseif ($CodeStructure -contains 'Public') {
            $ModuleStructure['Public'] += $sourceFile.FullName;
        } elseif ($CodeStructure -contains 'Private') {
            $ModuleStructure['Private'] += $sourceFile.FullName;
        }
    }

    return $ModuleStructure;
}

Write-Host "`n+---------------------------------------------------------------------+" -ForegroundColor Cyan;
Write-Host "|                                                                     |" -ForegroundColor Cyan;
Write-Host "|                Icinga for Windows - Module Compiler                 |" -ForegroundColor Cyan;
Write-Host "|                                                                     |" -ForegroundColor Cyan;
Write-Host "+---------------------------------------------------------------------+`n" -ForegroundColor Cyan;

$BuildStartTime        = Get-Date;

# First we need to analyze the module structure and gather all components
Write-Host '[1/4] Analyzing module structure...' -ForegroundColor Yellow;

[hashtable]$Components = Get-IcingaModuleStructure -ModuleBasePath $ModuleBasePath;

if ($Components.Public.Count -eq 0) {
    throw "No components found in $ModuleBasePath";
}

Write-Host "  * Found $($Components.Public.Count) public function file(s), $($Components.Private.Count) private function file(s) and $($Components.Classes.Count) class file(s)" -ForegroundColor Green;

# Make sure we always start with a clean output directory
Write-Host "`n[2/4] Preparing output directory..." -ForegroundColor Yellow;

[string]$OutputPath = Join-Path -Path $ModuleBasePath -ChildPath 'lib';

if (Test-Path -Path $OutputPath) {
    Write-Host '  Cleaning existing output directory' -ForegroundColor Yellow;
    Remove-Item -Path (Join-Path -Path $OutputPath -ChildPath '*.psm1') -Force -ErrorAction SilentlyContinue;
    Remove-Item -Path (Join-Path -Path $OutputPath -ChildPath '*.ps1') -Force -ErrorAction SilentlyContinue;
} else {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null;
}

Write-Host "  * Output directory ready: $OutputPath" -ForegroundColor Green;

# TODO: Compile native helpers into signed DLLs here instead of generating them at runtime.
# Keep their C# sources as .cs files in the repository (e.g. the DeviceIoControl based
# volume/disk-extent and NTFS volume data reader for Get-IcingaDiskInformation), build
# them into lib/ during this step, sign them together with the module and load them at
# import time only when the type is not present yet. Nothing may call Add-Type with a
# type definition at runtime anymore.

# Build consolidated classes and kernel files
Write-Host "`n[3/4] Building consolidated classes and kernel modules..." -ForegroundColor Yellow;

[string]$ClassesModuleName                 = 'IcingaForWindows.Classes.ps1';
[string]$ClassesOutput                     = Join-Path -Path $OutputPath -ChildPath $ClassesModuleName;
[System.Text.StringBuilder]$ClassesContent = New-Object System.Text.StringBuilder;

# Add classes header with top-level Icinga GmbH SPDX license comments
$ClassesContent.AppendLine('# SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>') | Out-Null;
$ClassesContent.AppendLine('# SPDX-License-Identifier: GPL-3.0-or-later') | Out-Null;
$ClassesContent.AppendLine() | Out-Null;
$ClassesContent.AppendLine('<#') | Out-Null;
$ClassesContent.AppendLine('.SYNOPSIS') | Out-Null;
$ClassesContent.AppendLine('    Icinga for Windows - Classes Module') | Out-Null;
$ClassesContent.AppendLine('.DESCRIPTION') | Out-Null;
$ClassesContent.AppendLine('    Single compiled file containing all Icinga for Windows class definitions') | Out-Null;
$ClassesContent.AppendLine("    Auto-generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null;
$ClassesContent.AppendLine('.NOTES') | Out-Null;
$ClassesContent.AppendLine("    Source: $(Join-Path -Path $ModuleBasePath -ChildPath (Join-Path -Path 'src' -ChildPath 'Classes'))") | Out-Null;
$ClassesContent.AppendLine('#>') | Out-Null;
$ClassesContent.AppendLine() | Out-Null;

# Append all classes sorted alphabetically (stripped of comments for minimal runtime memory)
Write-Host "  * Appending $($Components['Classes'].Count) class file(s) (minified)..." -ForegroundColor White;
foreach ($classFile in ($Components['Classes'] | Sort-Object)) {
    $FileContent  = Read-IcingaSourceFile -Path $classFile;
    $CleanContent = Remove-IcingaComments -Content $FileContent;
    if (-not [string]::IsNullOrWhiteSpace($CleanContent)) {
        $ClassesContent.AppendLine($CleanContent) | Out-Null;
        $ClassesContent.AppendLine() | Out-Null;
    }
}

Write-IcingaSourceFile -Path $ClassesOutput -Value $ClassesContent.ToString();
Write-Host "  * Classes file built successfully: $ClassesModuleName" -ForegroundColor Green;

# Build single consolidated kernel module file (functions only)
[string]$SingleModuleName                 = 'IcingaForWindows.Kernel.ps1';
[string]$ModuleOutput                     = Join-Path -Path $OutputPath -ChildPath $SingleModuleName;
[hashtable]$FncCache                      = @{ };
[System.Text.StringBuilder]$ModuleContent = New-Object System.Text.StringBuilder;

# Add module header with top-level Icinga GmbH SPDX license comments
$ModuleContent.AppendLine('# SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>') | Out-Null;
$ModuleContent.AppendLine('# SPDX-License-Identifier: GPL-3.0-or-later') | Out-Null;
$ModuleContent.AppendLine() | Out-Null;
$ModuleContent.AppendLine('<#') | Out-Null;
$ModuleContent.AppendLine('.SYNOPSIS') | Out-Null;
$ModuleContent.AppendLine('    Icinga for Windows - Kernel Module') | Out-Null;
$ModuleContent.AppendLine('.DESCRIPTION') | Out-Null;
$ModuleContent.AppendLine('    Single compiled kernel file containing all Icinga for Windows private and public functions') | Out-Null;
$ModuleContent.AppendLine("    Auto-generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null;
$ModuleContent.AppendLine('.NOTES') | Out-Null;
$ModuleContent.AppendLine("    Source: $(Join-Path -Path $ModuleBasePath -ChildPath 'src')") | Out-Null;
$ModuleContent.AppendLine('#>') | Out-Null;
$ModuleContent.AppendLine() | Out-Null;

# Append all private functions once sorted alphabetically (stripped of comments for minimal runtime memory)
Write-Host "  * Appending $($Components['Private'].Count) private function file(s) (minified)..." -ForegroundColor White;
foreach ($privateFile in ($Components['Private'] | Sort-Object)) {
    $FileContent  = Read-IcingaSourceFile -Path $privateFile;
    $CleanContent = Remove-IcingaComments -Content $FileContent;
    if (-not [string]::IsNullOrWhiteSpace($CleanContent)) {
        $ModuleContent.AppendLine($CleanContent) | Out-Null;
        $ModuleContent.AppendLine() | Out-Null;
    }
}

# Append all public functions once sorted alphabetically
Write-Host "  * Appending $($Components['Public'].Count) public function file(s)..." -ForegroundColor White;
foreach ($publicFile in ($Components['Public'] | Sort-Object)) {
    $FileContent     = Read-IcingaSourceFile -Path $publicFile;
    $FunctionMatches = [regex]::Matches($FileContent, '(?m)^\s*function\s+([a-zA-Z0-9_-]+)');

    foreach ($match in $FunctionMatches) {
        $fnName = $match.Groups[1].Value;
        if (-not $FncCache.ContainsKey($fnName)) {
            if ($fnName -eq 'prompt') {
                continue;
            }
            $FncCache.Add($fnName, 0);
        }
    }

    $ModuleContent.AppendLine($FileContent) | Out-Null;
    $ModuleContent.AppendLine() | Out-Null;
}

[array]$PublicFunctionList = @($FncCache.Keys | Sort-Object);

Write-Host "  * Found $($PublicFunctionList.Count) public function(s) to export." -ForegroundColor Green;

$ModuleContent.AppendLine() | Out-Null;
$ModuleContent.AppendLine('# Export all public functions') | Out-Null;
$ModuleContent.AppendLine("Export-ModuleMember -Alias @( '*' ) -Function @(") | Out-Null;

for ($i = 0; $i -lt $PublicFunctionList.Count; $i++) {
    $fn = $PublicFunctionList[$i];
    if ($i -eq $PublicFunctionList.Count - 1) {
        $ModuleContent.AppendLine("    '$fn'") | Out-Null;
    } else {
        $ModuleContent.AppendLine("    '$fn',") | Out-Null;
    }
}

$ModuleContent.AppendLine(');') | Out-Null;

Write-IcingaSourceFile -Path $ModuleOutput -Value $ModuleContent.ToString();

Write-Host "  * Kernel file built successfully: $SingleModuleName" -ForegroundColor Green;

Write-Host "`n[4/4] Module manifest..." -ForegroundColor Yellow;
Write-Host '  * Using static manifest (IcingaForWindows.psd1)' -ForegroundColor Green;

[string]$ManifestPath = Join-Path -Path $ModuleBasePath -ChildPath 'IcingaForWindows.psd1';
if (Test-Path -Path $ManifestPath -PathType Leaf) {
    [string]$ModuleParent = Split-Path -Path $ModuleBasePath -Parent;
    if (-not ($env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object { $_ -eq $ModuleParent })) {
        $env:PSModulePath = [string]::Concat($ModuleParent, [System.IO.Path]::PathSeparator, $env:PSModulePath);
    }

    Get-Module -Name 'IcingaForWindows' | Remove-Module -Force -ErrorAction SilentlyContinue;
    Import-Module -Name $ManifestPath -Force -Global;
    Write-Host '  * Module loaded successfully into session' -ForegroundColor Green;
}

# Final step: Run tests unless skipped
if (-not $SkipTests) {
    Write-Host "`n[5/5] Running tests..." -ForegroundColor Yellow;

    $TestPath = Join-Path -Path $ModuleBasePath -ChildPath 'Tests';

    if (Test-Path -Path $TestPath) {
        # Check if Pester 5.0+ is installed (avoid built-in Windows PowerShell Pester 3.4.0)
        [array]$Pester5 = @(Get-Module -ListAvailable -Name 'Pester' | Where-Object { $_.Version.Major -ge 5 });

        if ($Pester5.Count -eq 0) {
            Write-Warning '  Pester 5.0+ not installed, skipping tests';
        } else {
            try {
                Import-Module -Name 'Pester' -MinimumVersion '5.0.0' -Force;
                $PesterConfig              = New-PesterConfiguration;
                $PesterConfig.Run.Path     = $TestPath;
                $PesterConfig.Run.PassThru = $true;
                $TestResults               = Invoke-Pester -Configuration $PesterConfig;

                if ($TestResults.FailedCount -gt 0) {
                    throw "Tests failed! Failed: $($TestResults.FailedCount)";
                }

                Write-Host '  * All tests passed' -ForegroundColor Green;
                Write-Host "    Total: $($TestResults.TotalCount), Passed: $($TestResults.PassedCount)" -ForegroundColor Gray;
            } catch {
                Write-Error "Test execution failed: $_";
                throw;
            }
        }
    } else {
        Write-Warning "  Test directory not found: $TestPath";
    }
} else {
    Write-Host "`n[5/5] Tests skipped" -ForegroundColor Gray;
}

# Optional: generate API documentation from comment-based help blocks
if ($GenerateDocs) {
    Write-Host "`n[+] Generating API documentation..." -ForegroundColor Yellow;
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Build-ModuleDocs.ps1') -ModuleBasePath $ModuleBasePath -Strict $false | Out-Null;
}

# Optional: AST-based Memory Leak tests for Daemons
if ($TestDaemonMemoryLeaks) {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Test-ModuleDaemonMemoryLeak.ps1') -ModuleBasePath $ModuleBasePath;
}

# Optional: Repository-wide Code Styling and SPDX license check
if ($TestCodeStyling) {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Test-ModuleCodeStyling.ps1') -ModuleBasePath $ModuleBasePath;
}

# Build process is complete
$BuildDuration = (Get-Date) - $BuildStartTime;
$DurationText  = '{0:N2}s' -f $BuildDuration.TotalSeconds;

Write-Host "`n+---------------------------------------------------------------------+" -ForegroundColor Green;
Write-Host '|                                                                     |' -ForegroundColor Green;
Write-Host '|                          * BUILD COMPLETED                          |' -ForegroundColor Green;
Write-Host '|                                                                     |' -ForegroundColor Green;
Write-Host "+---------------------------------------------------------------------+`n" -ForegroundColor Green;

Write-Host "  Components built:     $($Components.Public.Count)" -ForegroundColor White;
Write-Host "  Functions exported:   $($PublicFunctionList.Count)" -ForegroundColor White;
Write-Host "  Build duration:       $DurationText" -ForegroundColor White;
Write-Host "  Output directory:     $OutputPath" -ForegroundColor Gray;

Write-Host "`n  Next steps:" -ForegroundColor Yellow;
Write-Host "    1. Review built modules in: $OutputPath" -ForegroundColor Gray;
Write-Host '    2. Sign modules: .\build\Sign-Module.ps1 -CertificateThumbprint <thumbprint>' -ForegroundColor Gray;
Write-Host '    3. Test import: Import-Module .\IcingaForWindows.psd1 -Force' -ForegroundColor Gray;

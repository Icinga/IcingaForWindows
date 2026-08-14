[CmdletBinding()]
param (
    [string]$BuildModule           = 'core',
    [switch]$SkipTests             = $false,
    [switch]$GenerateDocs          = $false,
    [switch]$TestDaemonMemoryLeaks = $false
);

$ErrorActionPreference  = 'Stop';
$ProgressPreference     = 'SilentlyContinue';
[string]$ModuleBasePath = '';
$NewLine                = [Environment]::NewLine;

if ($BuildModule -eq 'core') {
    [array]$InstalledModules     = Get-Module -ListAvailable -Name 'IcingaForWindows';
    [string]$BuildScriptLocation = Resolve-Path -Path $PSScriptRoot;

    foreach ($module in $InstalledModules) {
        if ($BuildScriptLocation.StartsWith((Resolve-Path -Path $module.ModuleBase))) {
            $ModuleBasePath = $module.ModuleBase;
            break;
        }
    }

    if ([string]::IsNullOrEmpty($ModuleBasePath)) {
        throw 'Could not determine module base path for Icinga for Icinga for Windows module.';
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

    [System.IO.FileStream]$FileStream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    );

    $ReadArray     = New-Object Byte[] $FileStream.Length;
    $UTF8Encoding  = New-Object System.Text.UTF8Encoding $false;
    $FileContent   = '';

    while ($FileStream.Read($ReadArray, 0, $ReadArray.Length)) {
        $FileContent = [System.String]::Concat($FileContent, $UTF8Encoding.GetString($ReadArray));
    }

    $FileStream.Dispose();

    return $FileContent;
}

function Write-IcingaSourceFile()
{
    [CmdletBinding()]
    param (
        [string]$Path  = $null,
        [string]$Value = ''
    );

    [System.IO.FileStream]$FileStream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Truncate,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::Read
    );

    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($Value);
    $FileStream.Write($ContentBytes, 0, $ContentBytes.Length);
    $FileStream.Dispose();
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

    [hashtable]$ModuleStructure = @{ 
        'Public'  = @();
        'Private' = @();
    };
    [int]$FileCount             = 0;

    $PowerShellSourcePath = Join-Path -Path $ModuleBasePath -ChildPath 'src\';
    [array]$SourceFiles   = Get-ChildItem -Path $PowerShellSourcePath -Recurse -Filter '*.ps1';

    foreach ($sourceFile in $SourceFiles) {
        $FileCount                                  += 1;
        # Make sure to convert to a universal path format, allowing both Unix and Windows style paths in the source files
        [string]$UniversalPath                       = $sourceFile.FullName.Replace('/', '\');
        $relativePath                                = $UniversalPath.Substring($PowerShellSourcePath.Length).TrimStart('\');
        [System.Collections.ArrayList]$CodeStructure = $relativePath.Split('\');

        if ($CodeStructure -contains 'Public') {
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

$BuildStartTime = Get-Date

# First we need to analyze the module structure and gather all components
Write-Host "[1/4] Analyzing module structure..." -ForegroundColor Yellow;

[hashtable]$Components = Get-IcingaModuleStructure -ModuleBasePath $ModuleBasePath;

if ($Components.Public.Count -eq 0) {
    throw "No components found in $SourcePath"
}

Write-Host "  * Found $($Components.Public.Count) public function file(s) and $($Components.Private.Count) private function file(s)" -ForegroundColor Green;

# Make sure we always start with a clean output directory
Write-Host "`n[2/4] Preparing output directory..." -ForegroundColor Yellow;

[string]$OutputPath = Join-Path -Path $ModuleBasePath -ChildPath 'lib';

if (Test-Path $OutputPath) {
    Write-Host "  Cleaning existing output directory" -ForegroundColor Yellow
    Remove-Item -Path (Join-Path -Path $OutputPath -ChildPath '*.psm1') -Force -ErrorAction SilentlyContinue;
    Remove-Item -Path (Join-Path -Path $OutputPath -ChildPath '*.ps1') -Force -ErrorAction SilentlyContinue;
} else {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null;
}

Write-Host "  * Output directory ready: $OutputPath" -ForegroundColor Green;

# Build single consolidated module file
Write-Host "`n[3/4] Building single consolidated module..." -ForegroundColor Yellow;

[string]$SingleModuleName = 'IcingaForWindows.Kernel.ps1';
[string]$ModuleOutput     = Join-Path -Path $OutputPath -ChildPath $SingleModuleName;
[hashtable]$FncCache      = @{ };

[System.Text.StringBuilder]$ModuleContent = New-Object System.Text.StringBuilder;

# Add module header
$ModuleContent.AppendLine('<#') | Out-Null;
$ModuleContent.AppendLine('.SYNOPSIS') | Out-Null;
$ModuleContent.AppendLine('    Icinga for Windows - Kernel Module') | Out-Null;
$ModuleContent.AppendLine('.DESCRIPTION') | Out-Null;
$ModuleContent.AppendLine('    Single compiled kernel file containing all Icinga for Windows private and public functions') | Out-Null;
$ModuleContent.AppendLine("    Auto-generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null;
$ModuleContent.AppendLine('.NOTES') | Out-Null;
$ModuleContent.AppendLine("    Source: $ModuleBasePath\src") | Out-Null;
$ModuleContent.AppendLine('#>') | Out-Null;
$ModuleContent.AppendLine() | Out-Null;

# Append all private functions once
Write-Host "  * Appending $($Components['Private'].Count) private function file(s)..." -ForegroundColor White;
foreach ($privateFile in $Components['Private']) {
    $FileContent = Read-IcingaSourceFile -Path $privateFile;
    $ModuleContent.AppendLine($FileContent) | Out-Null;
    $ModuleContent.AppendLine() | Out-Null;
}

# Append all public functions once
Write-Host "  * Appending $($Components['Public'].Count) public function file(s)..." -ForegroundColor White;
foreach ($publicFile in $Components['Public']) {
    $FileContent = Read-IcingaSourceFile -Path $publicFile;

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

Set-Content -Path $ModuleOutput -Value $ModuleContent.ToString() -Encoding UTF8 -Force;

Write-Host "  * Kernel file built successfully: $SingleModuleName" -ForegroundColor Green;

Write-Host "`n[4/4] Module manifest..." -ForegroundColor Yellow;
Write-Host "  * Using static manifest (IcingaForWindows.psd1)" -ForegroundColor Green;

$ManifestFile = Get-ChildItem -Path $ModuleBasePath -Filter '*.psd1' -File | Select-Object -First 1;
if ($null -ne $ManifestFile) {
    Import-Module -Name $ManifestFile.FullName -Force;
    Import-Module -Name $ManifestFile.FullName -Force -Global;
    Write-Host "  * Module loaded successfully into session" -ForegroundColor Green;
}

# Final step: Run tests unless skipped
if (-not $SkipTests) {
    Write-Host "`n[5/5] Running tests..." -ForegroundColor Yellow;
    
    $TestPath = Join-Path -Path $ModuleBasePath -ChildPath 'Tests';
    
    if (Test-Path $TestPath) {
        # Check if Pester is installed
        if (-not (Get-Module -ListAvailable -Name Pester)) {
            Write-Warning "  Pester not installed, skipping tests";
        } else {
            try {
                $TestResults = Invoke-Pester -Path $TestPath -PassThru;
                
                if ($TestResults.FailedCount -gt 0) {
                    throw "Tests failed! Failed: $($TestResults.FailedCount)";
                }
                
                Write-Host "  * All tests passed" -ForegroundColor Green;
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
    Write-Host "`n[+] Running Daemon Memory Leak tests..." -ForegroundColor Yellow;
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Test-ModuleDaemonMemoryLeak.ps1');
    
    $SourcePath = Join-Path -Path $ModuleBasePath -ChildPath 'src';
    if (-not (Test-ModuleDaemonMemoryLeak -SourceFolder $SourcePath)) {
        throw 'Daemon Memory Leak test failed! Un-nulled variables were found in endless loops.';
    }
    Write-Host "  * No Daemon memory leaks detected" -ForegroundColor Green;
}

# Build process is complete

$BuildDuration = (Get-Date) - $BuildStartTime;
$DurationText  = "{0:N2}s" -f $BuildDuration.TotalSeconds;

Write-Host "`n+---------------------------------------------------------------------+" -ForegroundColor Green;
Write-Host "|                                                                     |" -ForegroundColor Green;
Write-Host "|                          * BUILD COMPLETED                          |" -ForegroundColor Green;
Write-Host "|                                                                     |" -ForegroundColor Green;
Write-Host "+---------------------------------------------------------------------+`n" -ForegroundColor Green;

Write-Host "  Components built:     $($Components.Public.Count)" -ForegroundColor White;
Write-Host "  Functions exported:   $($PublicFunctionList.Count)" -ForegroundColor White;
Write-Host "  Build duration:       $DurationText" -ForegroundColor White;
Write-Host "  Output directory:     $OutputPath" -ForegroundColor Gray;

Write-Host "`n  Next steps:" -ForegroundColor Yellow;
Write-Host "    1. Review built modules in: $OutputPath" -ForegroundColor Gray;
Write-Host "    2. Sign modules: .\build\Sign-Module.ps1 -CertificateThumbprint <thumbprint>" -ForegroundColor Gray;
Write-Host "    3. Test import: Import-Module .\IcingaForWindows.psd1 -Force" -ForegroundColor Gray;

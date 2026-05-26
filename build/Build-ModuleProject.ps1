[CmdletBinding()]
param (
    [string]$BuildModule = 'core',
    [switch]$SkipTests   = $false
);

$ErrorActionPreference  =  'Stop';
$ProgressPreference     = 'SilentlyContinue';
[string]$ModuleBasePath = '';

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

    [System.IO.FileStream]$FileStream = [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    );

    $ReadArray     = New-Object Byte[] $FileStream.Length;
    $UTF8Encoding  = New-Object System.Text.UTF8Encoding $false;
    $FileContent   = '';

    while ($FileStream.Read($ReadArray, 0 , $ReadArray.Length)) {
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

function Get-IcingaForWindowsModuleStructure()
{
    [CmdletBinding()]
    param (
        [string]$ModuleBasePath = $null
    );

    if ([string]::IsNullOrEmpty($ModuleBasePath)) {
        throw 'Module base path must be provided to analyze the module structure.';
    }

    [hashtable]$ModuleStructure = @{ 
        'Public'  = @{ };
        'Private' = @();
    };
    [int]$FileCount             = 0;

    $PowerShellSourcePath = Join-Path -Path $ModuleBasePath -ChildPath 'src\';
    [array]$SourceFiles   = Get-ChildItem -Path $PowerShellSourcePath -Recurse -Filter '*.ps1';

    foreach ($sourceFile in $SourceFiles) {
        $FileCount                                  += 1;
        $relativePath                                = $sourceFile.FullName.Substring($PowerShellSourcePath.Length).TrimStart('\');
        [System.Collections.ArrayList]$CodeStructure = $relativePath.Split('\');

        [string]$LibName = [string]::Format('IcingaForWindows.{0}.psm1', $relativePath.Replace($sourceFile.Name, '').Replace('Public', '').Replace('Private', '').Replace('\', '.').Replace('-', '').Replace(' ', '').TrimEnd('.'));

        if (-not $ModuleStructure['Public'].ContainsKey($LibName)) {
            $ModuleStructure['Public'][$LibName] = @();
        }

        if ($CodeStructure -contains 'Public') {
            $ModuleStructure['Public'][$LibName] += $sourceFile.FullName;
        } elseif ($CodeStructure -Contains 'Private') {
            $ModuleStructure['Private'] += $sourceFile.FullName;
        }
    }

    return $ModuleStructure;
}

function Update-ModuleManifest {
    <#
    .SYNOPSIS
        Updates the module manifest with discovered components and functions
    #>
    [CmdletBinding()]
    param (
        [string]$ManifestPath,
        [array]$NestedModules,
        [array]$ExportedFunctions
    );
    
    Write-Host "  🔄 Updating module manifest at $ManifestPath..." -ForegroundColor White;
    
    if (-not (Test-Path $ManifestPath)) {
        Write-Warning "Manifest not found: $ManifestPath";
        return;
    }
    
    # Lese aktuelles Manifest
    $ManifestContent = Read-IcingaSourceFile -Path $ManifestPath;
    
    # Update NestedModules
    Write-Host "  Updating NestedModules ($($NestedModules.Count) modules)" -ForegroundColor White;
    
    $NestedModulesString = "@(`r`n"
    $NestedModules | Sort-Object | ForEach-Object {
        $NestedModulesString += "        '.\lib\$_',`r`n";
    }
    $NestedModulesString = $NestedModulesString.TrimEnd(",`r`n") + "`r`n    )";
    
    # Replace the entire content of the nexted modules array
    if ($ManifestContent -match 'NestedModules\s*=\s*@\(') {
        $ManifestContent = $ManifestContent -replace 'NestedModules\s*=\s*@\([^)]*\)', "NestedModules = $NestedModulesString";
    } else {
        Write-Warning '  Could not find NestedModules in manifest';
    }
    
    # Update FunctionsToExport
    Write-Host "  Updating FunctionsToExport ($($ExportedFunctions.Count) functions)" -ForegroundColor White;
    
    $FunctionsExportString = "@(`r`n";
    $ExportedFunctions | Sort-Object | ForEach-Object {
        $FunctionsExportString += "        '$_',`r`n";
    }
    $FunctionsExportString = $FunctionsExportString.TrimEnd(",`r`n") + "`r`n    )";
    
    # Replace the entire content of the FunctionsToExport array
    if ($ManifestContent -match 'FunctionsToExport\s*=\s*@\(') {
        $ManifestContent = $ManifestContent -replace "FunctionsToExport\s*=\s*@\([^)]*\)", "FunctionsToExport = $FunctionsExportString";
    } else {
        Write-Warning '  Could not find FunctionsToExport in manifest';
    }
       
    # Write updated manifest back to file
    Write-IcingaSourceFile -Path $ManifestPath -Value $ManifestContent.Trim();
    
    Write-Host '  ✓ Manifest updated' -ForegroundColor Green;
}

Write-Host @"

╔═════════════════════════════════════════════════════════════════════╗
║                                                                     ║
║                 Icinga for Windows - Module Builder                 ║
║                                                                     ║
╚═════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan;

$BuildStartTime = Get-Date

# First we need to analyze the module structure and gather all components
Write-Host "[1/5] Analyzing module structure..." -ForegroundColor Yellow;

[hashtable]$Components = Get-IcingaForWindowsModuleStructure -ModuleBasePath $ModuleBasePath;

if ($Components.Public.Count -eq 0) {
    throw "No components found in $SourcePath"
}

Write-Host "  ✓ Found $($Components.Public.Count) component(s)" -ForegroundColor Green;

foreach ($component in ($Components.Public.Keys | Sort-Object)) {
    $ComponentName        = $component.Replace('IcingaForWindows.', '').Replace('.psm1', '');
    [array]$SubComponents = $ComponentName.Split('.');

    if ($SubComponents.Count -eq 1) {
        Write-Host "    📦 $ComponentName" -ForegroundColor White;
    } else {
        Write-Host "    📦 $($ComponentName.Replace('.',' → '))" -ForegroundColor Gray;
    }
}

# Make sure we always start with a clean output directory
Write-Host "`n[2/5] Preparing output directory..." -ForegroundColor Yellow;

[string]$OutputPath = Join-Path -Path $ModuleBasePath -ChildPath 'lib';

if (Test-Path $OutputPath) {
    Write-Host "  Cleaning existing output directory" -ForegroundColor Yellow
    Remove-Item -Path (Join-Path -Path $OutputPath -ChildPath '*.psm1') -Force -ErrorAction SilentlyContinue;
} else {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null;
}

Write-Host "  ✓ Output directory ready: $OutputPath" -ForegroundColor Green;

# Now lets read all our files for each component and build the module files
Write-Host "`n[3/5] Building components..." -ForegroundColor Yellow;

[array]$PublicFunctionList = @();

foreach ($component in ($Components.Public.Keys | Sort-Object)) {
    $ComponentName        = $component.Replace('IcingaForWindows.', '').Replace('.psm1', '');
    [array]$PublicFiles   = $Components['Public'][$component];
    [array]$PrivateFiles  = $Components['Private'];
    [string]$ModuleOutput = Join-Path -Path $OutputPath -ChildPath $component;
    [int]$Index           = 0;
    [hashtable]$FncCache  = @{ };

    Write-Host "  🔨 Building $($ComponentName.Replace('.',' → '))..." -ForegroundColor White;

    [System.Text.StringBuilder]$ModuleContent = New-Object System.Text.StringBuilder;

    # Add module header
    $ModuleContent.AppendLine('<#') | Out-Null;
    $ModuleContent.AppendLine('.SYNOPSIS') | Out-Null;
    $ModuleContent.AppendLine("    Icinga for Windows - $ComponentName component") | Out-Null;
    $ModuleContent.AppendLine('.DESCRIPTION') | Out-Null;
    $ModuleContent.AppendLine("    Compiled module containing all $ComponentName functions") | Out-Null;
    $ModuleContent.AppendLine("    Auto-generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')") | Out-Null;
    $ModuleContent.AppendLine('.NOTES') | Out-Null;
    $ModuleContent.AppendLine("    Source: $ModuleBasePath\src\$ComponentName") | Out-Null;
    $ModuleContent.AppendLine('#>') | Out-Null;
    $ModuleContent.AppendLine() | Out-Null;

    # Append private functions first
    foreach ($privateFile in $PrivateFiles) {
        $FileContent = Read-IcingaSourceFile -Path $privateFile;
        $ModuleContent.AppendLine($FileContent) | Out-Null;
        $ModuleContent.AppendLine() | Out-Null;
    }

    # Append public functions next
    foreach ($publicFile in $PublicFiles) {
        $FileContent = Read-IcingaSourceFile -Path $publicFile;

        $FunctionMatches = [regex]::Matches($FileContent, '(?m)^\s*function\s+([a-zA-Z0-9_-]+)');

        foreach ($match in $FunctionMatches) {
            $fnName = $match.Groups[1].Value;
            if (-not $FncCache.ContainsKey($fnName)) {
                # Ensure our "prompt" function is never added anywhere for export or public listing
                if ($fnName -eq 'prompt') {
                    continue;
                }
                $FncCache.Add($fnName, 0);
            }
        }

        $ModuleContent.AppendLine($FileContent) | Out-Null;
        $ModuleContent.AppendLine() | Out-Null;
    }

    if ($FncCache.Keys.Count -eq 0) {
        Write-Host "    ⚠️  No public functions found in component $($ComponentName.Replace('.',' → ')), skipping export statement." -ForegroundColor Yellow;
    } else {
        Write-Host "    🚀 Found $($FncCache.Keys.Count) public function(s) in component $($ComponentName.Replace('.',' → '))." -ForegroundColor Green;

        $ModuleContent.AppendLine() | Out-Null;

        [System.Text.StringBuilder]$ExportFunctions = New-Object System.Text.StringBuilder;

        $ExportFunctions.AppendLine('# Export all public functions') | Out-Null;
        $ExportFunctions.AppendLine("Export-ModuleMember -Alias @( '*' ) -Function @(") | Out-Null;
        foreach ($fnc in ($FncCache.Keys | Sort-Object)) {
            $ExportFunctions.AppendLine("    '$fnc',") | Out-Null;
        }
        $ExportFunctions.Remove($ExportFunctions.Length - 3, 3) | Out-Null; # Remove last comma
        $ExportFunctions.AppendLine() | Out-Null;
        $ExportFunctions.AppendLine(');') | Out-Null;

        $ModuleContent.AppendLine($ExportFunctions.ToString()) | Out-Null;
    }

    $PublicFunctionList += $FncCache.Keys;

    # Finally write the module file
    Set-Content -Path $ModuleOutput -Value $ModuleContent.ToString() -Encoding UTF8 -Force;
}

Write-Host "  ✓ All components built successfully." -ForegroundColor Green;

# Finally we need to update the module manifest with our new components and functions
Write-Host "`n[4/5] Updating module manifest..." -ForegroundColor Yellow;

Update-ModuleManifest `
    -ManifestPath (Join-Path -Path $ModuleBasePath -ChildPath 'IcingaForWindows.psd1') `
    -NestedModules ($Components.Public.Keys) `
    -ExportedFunctions @($PublicFunctionList);

# Final step: Run tests unless skipped
if (-not $SkipTests) {
    Write-Host "`n[5/5] Running tests..." -ForegroundColor Yellow;
    
    $TestPath = Join-Path -Path $ModuleBasePath -ChildPath 'tests';
    
    if (Test-Path $TestPath) {
        # Prüfe ob Pester installiert ist
        if (-not (Get-Module -ListAvailable -Name Pester)) {
            Write-Warning "  Pester not installed, skipping tests";
        } else {
            try {
                $TestResults = Invoke-Pester -Path $TestPath -PassThru;
                
                if ($TestResults.FailedCount -gt 0) {
                    throw "Tests failed! Failed: $($TestResults.FailedCount)";
                }
                
                Write-Host "  ✓ All tests passed" -ForegroundColor Green;
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

# Build process is complete

$BuildDuration = (Get-Date) - $BuildStartTime

Write-Host @"

╔═════════════════════════════════════════════════════════════════════╗
║                                                                     ║
║                          ✓ BUILD COMPLETED                          ║
║                                                                     ║
╚═════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green;

Write-Host "  Components built:     $($Components.Public.Count)" -ForegroundColor White;
Write-Host "  Functions exported:   $($PublicFunctionList.Count)" -ForegroundColor White;
Write-Host "  Build duration:       $($BuildDuration.TotalSeconds.ToString('0.00'))s" -ForegroundColor White;
Write-Host "  Output directory:     $OutputPath" -ForegroundColor Gray;

Write-Host "`n  Next steps:" -ForegroundColor Yellow;
Write-Host "    1. Review built modules in: $OutputPath" -ForegroundColor Gray;
Write-Host "    2. Sign modules: .\build\Sign-Module.ps1 -CertificateThumbprint <thumbprint>" -ForegroundColor Gray;
Write-Host "    3. Test import: Import-Module .\IcingaForWindows.psd1 -Force" -ForegroundColor Gray;

<#
.SYNOPSIS
Generate Markdown API documentation for all Icinga source functions.

.DESCRIPTION
Walks every `*.ps1` file under `src/`, extracts the comment-based help
block that immediately precedes each `function` declaration and emits
one Markdown file per component into `docs/api/`. Also produces an
`index.md` summarising every component and exported function.

The generator enforces the doc rules defined in `CLAUDE.md`:
- Every public function must have `.SYNOPSIS`, `.DESCRIPTION`,
  `.PARAMETER` (one per parameter, Markdown table), `.OUTPUTS`,
  `.EXAMPLE`, `.NOTES`.
- Every private function must have at least `.SYNOPSIS` + `.DESCRIPTION`.
- `.PARAMETER` blocks must use the four-column Markdown table format
  shown in `CLAUDE.md`.

When `-Strict` is enabled (default), the generator fails with a non-zero
exit code if any file violates these rules.

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                       | Default                          |
|----------------|---------------|-------------------------------------------------------------------|----------------------------------|
| ModuleBasePath | System.String | Absolute path to the Icinga module root (the folder above `src`).| Resolved from the script path    |

.PARAMETER OutputPath
| Name       | Type          | Description                                              | Default                                       |
|------------|---------------|----------------------------------------------------------|-----------------------------------------------|
| OutputPath | System.String | Directory where the generated Markdown files are written.| `<ModuleBasePath>\docs\api`                   |

.PARAMETER IncludePrivate
| Name           | Type                    | Description                                                       | Default |
|----------------|-------------------------|-------------------------------------------------------------------|---------|
| IncludePrivate | System.Boolean          | When `$true`, private functions are documented too. When `$false`,| $true   |
|                |                         | only `Public/` functions are included.                            |         |

.PARAMETER Strict
| Name   | Type            | Description                                                              | Default |
|--------|-----------------|--------------------------------------------------------------------------|---------|
| Strict | System.Boolean  | Fail with a non-zero exit code if any function violates the doc rules.   | True    |

.OUTPUTS
System.Int32 -- Number of Markdown files written. Throws on strict violations.

.EXAMPLE
PS> .\build\Build-ModuleDocs.ps1

Generates docs/api/*.md for every component, including private helpers.

.EXAMPLE
PS> .\build\Build-ModuleDocs.ps1 -IncludePrivate:$false -Strict $false

Generate only public API docs, do not fail on missing help sections.

.NOTES
Designed to run on PowerShell 7.5+. Reads source from `src/` and writes
to `docs/api/`. Does NOT modify any `.ps1` source file; if you see
violations, fix the help block in the source file.
#>

[CmdletBinding()]
param (
    [string]$ModuleBasePath  = $null,
    [string]$OutputPath      = $null,
    [bool]$IncludePrivate    = $true,
    [bool]$Strict            = $true
);

$ErrorActionPreference = 'Stop';
$ProgressPreference    = 'SilentlyContinue';

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------
if ([string]::IsNullOrEmpty($ModuleBasePath)) {
    $ModuleBasePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') | Select-Object -ExpandProperty Path;
}

if ([string]::IsNullOrEmpty($OutputPath)) {
    $OutputPath = Join-Path -Path $ModuleBasePath -ChildPath 'docs\';
}

$SourcePath = Join-Path -Path $ModuleBasePath -ChildPath 'src';

if (-not (Test-Path -Path $SourcePath)) {
    throw "Source path not found: $SourcePath";
}

# ---------------------------------------------------------------------------
# Help block parser
# ---------------------------------------------------------------------------
function Read-IcingaHelpBlock()
{
    <#
    .SYNOPSIS
    Extract the comment-based help block and function name from a .ps1 file.

    .DESCRIPTION
    Reads the file, locates the comment-based help block that immediately
    precedes the first `function` declaration and returns a parsed object
    with every help section split out. If no help block is present, returns
    `$null` for the `Help` property so the caller can report it.

    .PARAMETER Path
    | Name | Type          | Description                              | Default |
    |------|---------------|------------------------------------------|---------|
    | Path | System.String | Absolute path to a Icinga `.ps1` source.|         |

    .OUTPUTS
    System.Collections.Hashtable -- Parsed structure with keys:
    Visibility, FunctionName, Synopsis, Description, Parameters, Outputs, Example, Notes.

    .EXAMPLE
    PS> Read-IcingaHelpBlock -Path '.\src\Core\Logging\Public\Set-IcingaLogLevel.ps1'

    .NOTES
    Pure parser -- does not import or execute the source file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    );

    $Content = Get-Content -Path $Path -Raw -Encoding UTF8;

    # Find all comment-based help blocks in the file.
    $HelpBlocks = [regex]::Matches($Content, '(?s)<#(.*?)#>');

    # Build a set of [start, end] ranges covered by comment blocks so the
    # function-declaration search can skip them. Prose like "the function
    # returns ..." inside a .DESCRIPTION would otherwise be misread as a
    # real declaration.
    $CommentRanges = New-Object System.Collections.ArrayList;
    foreach ($block in $HelpBlocks) {
        [void]$CommentRanges.Add(@{ Start = $block.Index; End = $block.Index + $block.Length });
    }

    # Walk every `function NAME` match and accept the first one that does
    # not fall inside a comment range.
    $AllFuncMatches = [regex]::Matches($Content, '(?m)^\s*function\s+([a-zA-Z0-9_\-:]+)\s*\(?');
    $FuncMatch      = $null;
    foreach ($candidate in $AllFuncMatches) {
        $insideComment = $false;
        foreach ($range in $CommentRanges) {
            if ($candidate.Index -ge $range.Start -and $candidate.Index -lt $range.End) {
                $insideComment = $true;
                break;
            }
        }
        if (-not $insideComment) {
            $FuncMatch = $candidate;
            break;
        }
    }

    if ($null -eq $FuncMatch) {
        return $null;
    }
    $FunctionName = $FuncMatch.Groups[1].Value -replace '^Global:', '';

    # Determine visibility from path
    $Visibility = if ($Path -match '[\\/]Public[\\/]') { 'Public' } elseif ($Path -match '[\\/]Private[\\/]') { 'Private' } else { 'Unknown' };

    # Pick the last help block that ends before the function declaration
    $HelpMatch = $null;
    foreach ($block in $HelpBlocks) {
        if (($block.Index + $block.Length) -le $FuncMatch.Index) {
            $HelpMatch = $block;
        }
    }

    $HelpSections = $null;

    if ($null -ne $HelpMatch) {
        $HelpBody     = $HelpMatch.Groups[1].Value;
        $HelpSections = @{
            Synopsis    = $null;
            Description = $null;
            Parameters  = @();
            Outputs     = $null;
            Examples    = @();
            Notes       = $null;
        };

        # Split on top-level dot-prefixed section headers (.SYNOPSIS, .DESCRIPTION, etc.)
        # Section headers must be at line start (possibly after whitespace).
        $Sections = [regex]::Split($HelpBody, '(?m)^\s*\.(?=[A-Z]+)');

        foreach ($section in $Sections) {
            if ([string]::IsNullOrWhiteSpace($section)) {
                continue;
            }

            # First word is the section name, rest is body
            $Match = [regex]::Match($section, '^([A-Z]+)\s*(.*)$', 'Singleline');
            if (-not $Match.Success) {
                continue;
            }

            $Name = $Match.Groups[1].Value.ToUpper();
            $Body = $Match.Groups[2].Value.Trim();

            switch ($Name) {
                'SYNOPSIS'    { $HelpSections.Synopsis    = $Body;                       break; }
                'DESCRIPTION' { $HelpSections.Description = $Body;                       break; }
                'OUTPUTS'     { $HelpSections.Outputs     = $Body;                       break; }
                'NOTES'       { $HelpSections.Notes       = $Body;                       break; }
                'EXAMPLE'     { $HelpSections.Examples   += $Body;                       break; }
                'PARAMETER'   {
                    # Body starts with the parameter name, then the table
                    $ParamMatch = [regex]::Match($Body, '^([a-zA-Z0-9_]+)\s*(.*)$', 'Singleline');
                    if ($ParamMatch.Success) {
                        $HelpSections.Parameters += [PSCustomObject]@{
                            Name = $ParamMatch.Groups[1].Value;
                            Body = $ParamMatch.Groups[2].Value.Trim();
                        };
                    }
                    break;
                };
            }
        }
    }

    return @{
        File         = $Path;
        FunctionName = $FunctionName;
        Visibility   = $Visibility;
        Help         = $HelpSections;
    };
}

# ---------------------------------------------------------------------------
# Validation per CLAUDE.md
# ---------------------------------------------------------------------------
function Test-IcingaHelpCompleteness()
{
    <#
    .SYNOPSIS
    Validate that a parsed help block meets the rules defined in CLAUDE.md.

    .DESCRIPTION
    Public functions require all seven sections. Private functions
    require at least Synopsis + Description; if they have parameters
    declared in the source file, those must also be documented via the
    Markdown table form. Returns a list of human-readable violation
    strings (empty when the block is valid).

    .PARAMETER ParsedEntry
    | Name        | Type                          | Description                                              | Default |
    |-------------|-------------------------------|----------------------------------------------------------|---------|
    | ParsedEntry | System.Collections.Hashtable  | Output of `Read-IcingaHelpBlock`.                       |         |

    .PARAMETER DeclaredParameters
    | Name               | Type                 | Description                                                              | Default |
    |--------------------|----------------------|--------------------------------------------------------------------------|---------|
    | DeclaredParameters | System.String[]      | Parameter names found in the source file's `param( ... )` block.         | @()     |

    .OUTPUTS
    System.String[] -- Zero or more violation messages.

    .EXAMPLE
    PS> Test-IcingaHelpCompleteness -ParsedEntry $entry -DeclaredParameters @('Name', 'Count')

    .NOTES
    Internal generator helper. Used by the strict-mode validator.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$ParsedEntry,
        [string[]]$DeclaredParameters = @()
    );

    $Violations = @();
    $Help       = $ParsedEntry.Help;

    if ($null -eq $Help) {
        $Violations += "missing comment-based help block";
        return $Violations;
    }

    # Synopsis + Description are required for ALL functions
    if ([string]::IsNullOrWhiteSpace($Help.Synopsis)) {
        $Violations += "missing .SYNOPSIS";
    }
    if ([string]::IsNullOrWhiteSpace($Help.Description)) {
        $Violations += "missing .DESCRIPTION";
    }

    if ($ParsedEntry.Visibility -eq 'Public') {
        # Outputs, Example, Notes are required on public functions
        if ([string]::IsNullOrWhiteSpace($Help.Outputs)) {
            $Violations += "missing .OUTPUTS";
        }
        if ($Help.Examples.Count -eq 0) {
            $Violations += "missing .EXAMPLE";
        }
        if ([string]::IsNullOrWhiteSpace($Help.Notes)) {
            $Violations += "missing .NOTES";
        }
    }

    # Each declared param must have a matching .PARAMETER block
    $DocumentedParams = @($Help.Parameters | ForEach-Object { $_.Name });
    foreach ($declared in $DeclaredParameters) {
        if ($declared -notin $DocumentedParams) {
            $Violations += "missing .PARAMETER block for '$declared'";
        }
    }

    # Each documented .PARAMETER body must look like a Markdown table
    foreach ($param in $Help.Parameters) {
        if ($param.Body -notmatch '\|\s*Name\s*\|\s*Type\s*\|\s*Description\s*\|\s*Default\s*\|') {
            $Violations += ".PARAMETER '$($param.Name)' is missing the Markdown table (Name|Type|Description|Default)";
        }
    }

    return $Violations;
}

function Get-IcingaDeclaredParameters()
{
    <#
    .SYNOPSIS
    Extract the parameter names from a .ps1 source file's param block.

    .DESCRIPTION
    Reads the file, locates the first `param( ... )` block following the
    `function` declaration and returns an array of parameter names. Used
    by the validator to detect undocumented parameters.

    .PARAMETER Path
    | Name | Type          | Description                              | Default |
    |------|---------------|------------------------------------------|---------|
    | Path | System.String | Absolute path to a Icinga `.ps1` source.|         |

    .OUTPUTS
    System.String[] -- Parameter names (without `$` prefix).

    .EXAMPLE
    PS> Get-IcingaDeclaredParameters -Path '.\src\Core\Logging\Private\Write-LoggingEntry.ps1'

    .NOTES
    Regex-based; does not use AST. Sufficient for the Icinga house
    style where params are one-per-line with explicit types.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    );

    $Content = Get-Content -Path $Path -Raw -Encoding UTF8;

    # Locate the param block of the first function
    $FuncMatch = [regex]::Match($Content, '(?ms)function\s+[a-zA-Z0-9_\-:]+\s*\([^\)]*\)\s*\{(.*?)\}');
    if (-not $FuncMatch.Success) {
        # Fallback: find param() block anywhere
        $ParamMatch = [regex]::Match($Content, '(?ms)param\s*\((.*?)\)');
    } else {
        $Body       = $FuncMatch.Groups[1].Value;
        $ParamMatch = [regex]::Match($Body, '(?ms)param\s*\((.*?)\)');
    }

    if (-not $ParamMatch.Success) {
        return @();
    }

    $ParamBody = $ParamMatch.Groups[1].Value;

    # A parameter declaration in Icinga always has the shape:
    #   [Type]$Name        ...optional default
    # or [Parameter(...)] [ValidateSet(...)] [Type]$Name ...
    # The token immediately before $Name is always a closing bracket of an
    # attribute or type annotation. Match exactly that to avoid picking up
    # $null / $false / $true used as default values.
    $Names = [regex]::Matches($ParamBody, '\]\s*\$([a-zA-Z_][a-zA-Z0-9_]*)');

    return @($Names | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique);
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------
Write-Host '+---------------------------------------------------------------------+' -ForegroundColor Cyan;
Write-Host '|                                                                     |' -ForegroundColor Cyan;
Write-Host '|                       Icinga Documentation Builder                 |' -ForegroundColor Cyan;
Write-Host '|                                                                     |' -ForegroundColor Cyan;
Write-Host '+---------------------------------------------------------------------+' -ForegroundColor Cyan;
Write-Host '' -ForegroundColor White;

$BuildStartTime = Get-Date;

Write-Host "[1/4] Discovering source files in $SourcePath ..." -ForegroundColor Yellow;

$SourceFiles = Get-ChildItem -Path $SourcePath -Recurse -Filter '*.ps1';

if (-not $IncludePrivate) {
    $SourceFiles = $SourceFiles | Where-Object { $_.FullName -match '[\\/]Public[\\/]' };
}

Write-Host "  * Found $($SourceFiles.Count) source files" -ForegroundColor Green;

# ---------------------------------------------------------------------------
# Parse + validate
# ---------------------------------------------------------------------------
Write-Host '' -ForegroundColor White;
Write-Host '[2/4] Parsing comment-based help blocks ...' -ForegroundColor Yellow;

$Parsed     = New-Object System.Collections.ArrayList;
$Violations = New-Object System.Collections.ArrayList;

foreach ($file in $SourceFiles) {
    $entry = Read-IcingaHelpBlock -Path $file.FullName;
    if ($null -eq $entry) {
        continue;
    }

    $declared = Get-IcingaDeclaredParameters -Path $file.FullName;
    $issues   = Test-IcingaHelpCompleteness -ParsedEntry $entry -DeclaredParameters $declared;

    if ($issues.Count -gt 0) {
        $relPath = $file.FullName.Substring($ModuleBasePath.Length).TrimStart('\', '/');
        foreach ($issue in $issues) {
            [void]$Violations.Add([PSCustomObject]@{
                File         = $relPath;
                FunctionName = $entry.FunctionName;
                Visibility   = $entry.Visibility;
                Issue        = $issue;
            });
        }
    }

    [void]$Parsed.Add($entry);
}

Write-Host "  * Parsed $($Parsed.Count) functions" -ForegroundColor Green;
if ($Violations.Count -gt 0) {
    Write-Host "  ! $($Violations.Count) violation(s) found" -ForegroundColor Yellow;
}

# ---------------------------------------------------------------------------
# Generate Markdown
# ---------------------------------------------------------------------------
Write-Host '' -ForegroundColor White;
Write-Host "[3/4] Writing Markdown into $OutputPath ..." -ForegroundColor Yellow;

if (Test-Path -Path $OutputPath) {
    Remove-Item -Path (Join-Path -Path $OutputPath -ChildPath '*.md') -Force -ErrorAction SilentlyContinue;
} else {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null;
}

# Group functions by component (relative path under src/, up to and including the subcomponent)
$Grouped = $Parsed | Group-Object -Property {
    $rel    = $_.File.Substring($SourcePath.Length).TrimStart('\', '/');
    $parts  = $rel -split '[\\/]';
    # parts: <Component>, <Subcomponent>, {Public|Private}, <file>.ps1
    if ($parts.Count -ge 3) {
        return ($parts[0..($parts.Count - 3)] -join '.');
    }
    return $parts[0];
};

$WrittenFiles = 0;

foreach ($group in ($Grouped | Sort-Object Name)) {
    $componentName = $group.Name;
    $outFile       = Join-Path -Path $OutputPath -ChildPath ("Icinga.$componentName.md");

    [System.Text.StringBuilder]$md = New-Object System.Text.StringBuilder;

    [void]$md.AppendLine("# Icinga.$componentName");
    [void]$md.AppendLine();
    $srcDir = $componentName.Replace('.', '/');
    [void]$md.AppendLine('*Auto-generated from `src/' + $srcDir + '/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*');
    [void]$md.AppendLine();

    $publicFns  = $group.Group | Where-Object { $_.Visibility -eq 'Public'  } | Sort-Object FunctionName;
    $privateFns = $group.Group | Where-Object { $_.Visibility -eq 'Private' } | Sort-Object FunctionName;

    if ($publicFns.Count -gt 0) {
        [void]$md.AppendLine('## Public functions');
        [void]$md.AppendLine();
        foreach ($fn in $publicFns) {
            [void]$md.AppendLine("- [$($fn.FunctionName)](#$($fn.FunctionName.ToLower()))");
        }
        [void]$md.AppendLine();
    }

    if ($privateFns.Count -gt 0 -and $IncludePrivate) {
        [void]$md.AppendLine('## Private helpers');
        [void]$md.AppendLine();
        foreach ($fn in $privateFns) {
            [void]$md.AppendLine("- [$($fn.FunctionName)](#$($fn.FunctionName.ToLower()))");
        }
        [void]$md.AppendLine();
    }

    foreach ($fn in @($publicFns) + @($privateFns)) {
        [void]$md.AppendLine('---');
        [void]$md.AppendLine();
        [void]$md.AppendLine("### $($fn.FunctionName)");
        [void]$md.AppendLine();
        [void]$md.AppendLine("*$($fn.Visibility) function*");
        [void]$md.AppendLine();

        if ($null -eq $fn.Help) {
            [void]$md.AppendLine('> ! No comment-based help block found in source.');
            [void]$md.AppendLine();
            continue;
        }

        if (-not [string]::IsNullOrWhiteSpace($fn.Help.Synopsis)) {
            [void]$md.AppendLine("**Synopsis:** $($fn.Help.Synopsis)");
            [void]$md.AppendLine();
        }

        if (-not [string]::IsNullOrWhiteSpace($fn.Help.Description)) {
            [void]$md.AppendLine('#### Description');
            [void]$md.AppendLine();
            [void]$md.AppendLine($fn.Help.Description);
            [void]$md.AppendLine();
        }

        if ($fn.Help.Parameters.Count -gt 0) {
            [void]$md.AppendLine('#### Parameters');
            [void]$md.AppendLine();
            foreach ($p in $fn.Help.Parameters) {
                [void]$md.AppendLine('**`$' + $p.Name + '`**');
                [void]$md.AppendLine();
                [void]$md.AppendLine($p.Body);
                [void]$md.AppendLine();
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($fn.Help.Outputs)) {
            [void]$md.AppendLine('#### Outputs');
            [void]$md.AppendLine();
            [void]$md.AppendLine($fn.Help.Outputs);
            [void]$md.AppendLine();
        }

        if ($fn.Help.Examples.Count -gt 0) {
            [void]$md.AppendLine('#### Examples');
            [void]$md.AppendLine();
            foreach ($ex in $fn.Help.Examples) {
                [void]$md.AppendLine('```powershell');
                [void]$md.AppendLine($ex);
                [void]$md.AppendLine('```');
                [void]$md.AppendLine();
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($fn.Help.Notes)) {
            [void]$md.AppendLine('#### Notes');
            [void]$md.AppendLine();
            [void]$md.AppendLine($fn.Help.Notes);
            [void]$md.AppendLine();
        }

        $srcRel = $fn.File.Substring($ModuleBasePath.Length).TrimStart('\', '/').Replace('\', '/');
        [void]$md.AppendLine("*Source: [$srcRel](../../$srcRel)*");
        [void]$md.AppendLine();
    }

    Set-Content -Path $outFile -Value $md.ToString() -Encoding UTF8 -Force;
    $WrittenFiles++;
}

# Index file
$indexFile = Join-Path -Path $OutputPath -ChildPath 'index.md';
[System.Text.StringBuilder]$idx = New-Object System.Text.StringBuilder;
[void]$idx.AppendLine('# Icinga API Reference');
[void]$idx.AppendLine();
[void]$idx.AppendLine('*Auto-generated on ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '.*');
[void]$idx.AppendLine();
[void]$idx.AppendLine('| Component | Public functions | Private helpers |');
[void]$idx.AppendLine('|-----------|------------------|-----------------|');

foreach ($group in ($Grouped | Sort-Object Name)) {
    $pubCount = ($group.Group | Where-Object { $_.Visibility -eq 'Public'  }).Count;
    $prvCount = ($group.Group | Where-Object { $_.Visibility -eq 'Private' }).Count;
    [void]$idx.AppendLine("| [Icinga.$($group.Name)](Icinga.$($group.Name).md) | $pubCount | $prvCount |");
}

[void]$idx.AppendLine();
[void]$idx.AppendLine('## Totals');
[void]$idx.AppendLine();
[void]$idx.AppendLine("- Components: $($Grouped.Count)");
[void]$idx.AppendLine("- Documented functions: $($Parsed.Count)");
[void]$idx.AppendLine("- Public: $($Parsed | Where-Object { $_.Visibility -eq 'Public'  } | Measure-Object | Select-Object -ExpandProperty Count)");
[void]$idx.AppendLine("- Private: $($Parsed | Where-Object { $_.Visibility -eq 'Private' } | Measure-Object | Select-Object -ExpandProperty Count)");

Set-Content -Path $indexFile -Value $idx.ToString() -Encoding UTF8 -Force;
$WrittenFiles++;

Write-Host "  * Wrote $WrittenFiles Markdown file(s)" -ForegroundColor Green;

# ---------------------------------------------------------------------------
# Report violations
# ---------------------------------------------------------------------------
Write-Host '' -ForegroundColor White;
Write-Host '[4/4] Reporting documentation violations ...' -ForegroundColor Yellow;

if ($Violations.Count -eq 0) {
    Write-Host '  * No violations -- every function meets the CLAUDE.md doc rules' -ForegroundColor Green;
} else {
    Write-Host "  ! $($Violations.Count) violation(s):" -ForegroundColor Yellow;
    $Violations |
        Sort-Object Visibility, File |
        ForEach-Object {
            Write-Host ("    [{0,-7}] {1} :: {2} -- {3}" -f $_.Visibility, $_.FunctionName, $_.File, $_.Issue) -ForegroundColor DarkYellow;
        };
}

$BuildDuration = (Get-Date) - $BuildStartTime;
$DurationText  = "{0:N2}s" -f $BuildDuration.TotalSeconds;

Write-Host '' -ForegroundColor White;
Write-Host '+---------------------------------------------------------------------+' -ForegroundColor Green;
Write-Host '|                                                                     |' -ForegroundColor Green;
Write-Host '|                       * DOCUMENTATION BUILD DONE                    |' -ForegroundColor Green;
Write-Host '|                                                                     |' -ForegroundColor Green;
Write-Host '+---------------------------------------------------------------------+' -ForegroundColor Green;
Write-Host '' -ForegroundColor White;
Write-Host "  Components:           $($Grouped.Count)"     -ForegroundColor White;
Write-Host "  Functions documented: $($Parsed.Count)"      -ForegroundColor White;
Write-Host "  Markdown files:       $WrittenFiles"         -ForegroundColor White;
Write-Host "  Violations:           $($Violations.Count)"  -ForegroundColor White;
Write-Host "  Build duration:       $DurationText"         -ForegroundColor White;
Write-Host "  Output:               $OutputPath"           -ForegroundColor Gray;
Write-Host '' -ForegroundColor White;

if ($Strict -and $Violations.Count -gt 0) {
    throw "Documentation violations detected ($($Violations.Count)). See list above. Use -Strict:`$false to suppress.";
}

return $WrittenFiles;

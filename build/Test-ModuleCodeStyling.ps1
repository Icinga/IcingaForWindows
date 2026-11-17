<#
.SYNOPSIS
Validate PowerShell files in Icinga for Windows for code-styling and SPDX license compliance

.DESCRIPTION
Scans the Icinga for Windows repository (`src/`, `build/`, `IcingaForWindows.psm1`,
`IcingaForWindows.psd1`, `Tests/`, and compiled `lib/` SPDX headers by default, or
explicit `-Path` / `-SourceFolder` targets) and verifies compliance with the binding
rules defined in `docs/Agents/guidelines/01-Instruction.md`:

1. UTF-8 without BOM encoding (no UTF-8, UTF-16, or UTF-32 BOMs and no NUL bytes).
2. Indentation and whitespace (4 spaces per indentation level, no tab characters,
   no trailing whitespace, and a single trailing newline at end of file).
3. Strict 7-bit ASCII characters (`0x00`-`0x7F`) across all BOM-less PowerShell files
   (no Unicode em-dashes U+2014, en-dashes U+2013, arrows, box-drawing glyphs, or emojis,
   which cause Windows-1252 Mojibake or smart-quote lexer parse errors in Windows PowerShell 5.1).
4. Allman brace style on `function`, `class`, and `enum` declarations, explicit empty
   parentheses on function declarations (`function Name()`), and single-line `if`/`elseif`
   conditions ending with `{`.
5. Function scope rules: files under `src/` (outside `src/Classes/`) may define at most
   one top-level `function` and zero nested functions (`src/Classes/` may not define
   standalone functions); helper and nested functions are permitted in `build/`,
   `IcingaForWindows.psm1`, and `Tests/`.
6. Vertical alignment of `=` (`+=`, `-=`, `*=`, `/=`) across assignment blocks at the
   same indentation depth and across contiguous hashtable/enum key-value entries.
7. Vertical alignment of `|` column pipes across all rows of Markdown `.PARAMETER`
   tables inside comment-based help blocks.
8. Mandatory `.NOTES` section concluding with the two Icinga GmbH SPDX lines
   (`SPDX-FileCopyrightText` and `SPDX-License-Identifier: GPL-3.0-or-later`) across
   `src/`, `build/`, `IcingaForWindows.psm1`, and `Tests/`, `PrivateData.SPDX` +
   `GPL-3.0-or-later` in `IcingaForWindows.psd1`, and top-of-file SPDX headers in
   compiled `lib/IcingaForWindows.{Classes,Kernel}.ps1` files.

.PARAMETER ModuleBasePath
| Name           | Type          | Description                                                                   | Default                       |
|----------------|---------------|-------------------------------------------------------------------------------|-------------------------------|
| ModuleBasePath | System.String | Absolute path to the Icinga for Windows module root (the folder above `src`). | Resolved from the script path |

.PARAMETER SourceFolder
| Name         | Type          | Description                                                              | Default |
|--------------|---------------|--------------------------------------------------------------------------|---------|
| SourceFolder | System.String | Optional single folder override to scan when `-Path` is not provided.    | ''      |

.PARAMETER Path
| Name | Type         | Description                                                                   | Default |
|------|--------------|-------------------------------------------------------------------------------|---------|
| Path | System.Array | Optional specific file or directory paths to scan instead of the full module. | @()     |

.PARAMETER PassThru
| Name     | Type                                         | Description                                                         | Default |
|----------|----------------------------------------------|---------------------------------------------------------------------|---------|
| PassThru | System.Management.Automation.SwitchParameter | Return the array of violation strings instead of throwing on error. | False   |

.OUTPUTS
System.Object -- Returns $true when all checks pass (or the array of violation strings when -PassThru is set).

.EXAMPLE
PS> .\build\Test-ModuleCodeStyling.ps1

Scans `src/`, `build/`, `IcingaForWindows.psm1`, `IcingaForWindows.psd1`, `Tests/`,
and compiled `lib/` SPDX headers, throwing if any violation is found.

.EXAMPLE
PS> .\build\Test-ModuleCodeStyling.ps1 -Path .\src\Classes\Icinga\IcingaPlugin.ps1, .\IcingaForWindows.psd1

Scans only the specified files for code-styling and SPDX compliance.

.NOTES
Designed for Windows PowerShell 5.1 and PowerShell 7+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>

[CmdletBinding()]
param (
    [string]$ModuleBasePath = $null,
    [string]$SourceFolder   = $null,
    [array]$Path            = @(),
    [switch]$PassThru       = $false
);

$ErrorActionPreference = 'Stop';
$ProgressPreference    = 'SilentlyContinue';

if ([string]::IsNullOrEmpty($ModuleBasePath)) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath);
} elseif (Test-Path -Path $ModuleBasePath) {
    $ModuleBasePath = [System.IO.Path]::GetFullPath((Resolve-Path -Path $ModuleBasePath).ProviderPath);
}

[bool]$HasExplicitSourceFolder = ($PSBoundParameters.ContainsKey('SourceFolder') -and -not [string]::IsNullOrEmpty($SourceFolder));

function Test-AssignmentBlockAlignment()
{
    param (
        [string]$RelativePath = '',
        [array]$Block         = @()
    );

    [array]$BlockViolations = @();

    if ($null -eq $Block -or $Block.Count -eq 0) {
        return $BlockViolations;
    }

    [int]$ExpectedEqCol = 0;

    foreach ($Item in $Block) {
        [int]$CandidateCol = $Item.LhsEnd + $Item.Op.Length;
        if ($CandidateCol -gt $ExpectedEqCol) {
            $ExpectedEqCol = $CandidateCol;
        }
    }

    [bool]$HasMismatch = $false;

    foreach ($Item in $Block) {
        if ($Item.EqCol -ne $ExpectedEqCol) {
            $HasMismatch = $true;
            break;
        }
        if ($Item.PostSpaces -ne 1 -and -not [string]::IsNullOrWhiteSpace($Item.Rhs)) {
            $HasMismatch = $true;
            break;
        }
    }

    if ($HasMismatch) {
        [int]$StartLine = $Block[0].Line;
        [int]$EndLine   = $Block[$Block.Count - 1].Line;

        if ($Block.Count -eq 1) {
            $Single           = $Block[0];
            $BlockViolations += ('{0}:{1} -- Assignment spacing around "{2}" must have exactly 1 space before (expected "=" at col {3}, found col {4}) and 1 space after: {5}' -f $RelativePath, $Single.Line, $Single.Op, ($ExpectedEqCol + 1), ($Single.EqCol + 1), $Single.Raw.Trim());
        } else {
            [array]$Details = @();
            foreach ($Item in $Block) {
                $Details += ('L{0}(col {1}, post {2})' -f $Item.Line, ($Item.EqCol + 1), $Item.PostSpaces);
            }
            $BlockViolations += ('{0}:{1}-{2} -- Assignment "=" alignment or post-"=" spacing mismatch in block (expected col {3} and 1 post-space; found {4})' -f $RelativePath, $StartLine, $EndLine, ($ExpectedEqCol + 1), ($Details -join ', '));
        }
    }

    return $BlockViolations;
}

function Test-KeyValueBlockAlignment()
{
    param (
        [string]$RelativePath    = '',
        [array]$Block            = @(),
        [hashtable]$EnumLineNums = @{ }
    );

    [array]$KvViolations = @();

    if ($null -eq $Block -or $Block.Count -eq 0) {
        return $KvViolations;
    }

    if ($Block.Count -eq 1) {
        $SingleKv = $Block[0];
        if ($EnumLineNums.ContainsKey([int]$SingleKv.Line)) {
            [int]$ExpectedEnumEq = $SingleKv.LhsEnd + 1;
            if ($SingleKv.EqCol -ne $ExpectedEnumEq -or ($SingleKv.PostSpaces -ne 1 -and -not [string]::IsNullOrWhiteSpace($SingleKv.Rhs))) {
                $KvViolations += ('{0}:{1} -- Enum member "=" spacing must have 1 space before and 1 space after "=": {2}' -f $RelativePath, $SingleKv.Line, $SingleKv.Raw.Trim());
            }
        } elseif ($SingleKv.PostSpaces -ne 1 -and -not [string]::IsNullOrWhiteSpace($SingleKv.Rhs)) {
            $KvViolations += ('{0}:{1} -- Key-value entry must have exactly 1 space after "=": {2}' -f $RelativePath, $SingleKv.Line, $SingleKv.Raw.Trim());
        }
        return $KvViolations;
    }

    [int]$ExpectedEqCol = 0;

    foreach ($Item in $Block) {
        [int]$CandidateCol = $Item.LhsEnd + 1;
        if ($CandidateCol -gt $ExpectedEqCol) {
            $ExpectedEqCol = $CandidateCol;
        }
    }

    [bool]$HasMismatch = $false;

    foreach ($Item in $Block) {
        if ($Item.EqCol -ne $ExpectedEqCol) {
            $HasMismatch = $true;
            break;
        }
        if ($Item.PostSpaces -ne 1 -and -not [string]::IsNullOrWhiteSpace($Item.Rhs)) {
            $HasMismatch = $true;
            break;
        }
    }

    if ($HasMismatch) {
        [int]$StartLine = $Block[0].Line;
        [int]$EndLine   = $Block[$Block.Count - 1].Line;
        [array]$Details = @();

        foreach ($Item in $Block) {
            $Details += ('L{0}(col {1}, post {2})' -f $Item.Line, ($Item.EqCol + 1), $Item.PostSpaces);
        }

        $KvViolations += ('{0}:{1}-{2} -- Hashtable/enum "=" alignment or post-"=" spacing mismatch (expected col {3} and 1 post-space; found {4})' -f $RelativePath, $StartLine, $EndLine, ($ExpectedEqCol + 1), ($Details -join ', '));
    }

    return $KvViolations;
}

function Get-PipeIndices()
{
    param (
        [string]$Line = ''
    );

    [array]$Indices = @();

    for ($i = 0; $i -lt $Line.Length; $i++) {
        if ($Line[$i] -eq '|') {
            $Indices += $i;
        }
    }

    return ($Indices -join ',');
}

function Get-TokenDelimiterDelta()
{
    param (
        [array]$LineTokens = @(),
        [int]$MinColumn    = 1
    );

    [int]$Delta = 0;

    if ($null -eq $LineTokens) {
        return 0;
    }

    foreach ($Tok in $LineTokens) {
        if ($Tok.Extent.StartColumnNumber -lt $MinColumn) {
            continue;
        }

        [string]$KindName = [string]$Tok.Kind;
        if ($KindName -eq 'LParen' -or $KindName -eq 'AtParen' -or $KindName -eq 'DollarParen' -or $KindName -eq 'LCurly' -or $KindName -eq 'AtCurly') {
            $Delta++;
        } elseif ($KindName -eq 'RParen' -or $KindName -eq 'RCurly') {
            $Delta--;
        }
    }

    return $Delta;
}

function Test-BlockCommentNotesAndSpdx()
{
    param (
        [string]$CommentText = ''
    );

    if ([string]::IsNullOrWhiteSpace($CommentText)) {
        return 'missing .NOTES section and Icinga GmbH SPDX license lines';
    }

    if ($CommentText -notmatch '(?m)^\s*\.NOTES\b') {
        return 'missing mandatory .NOTES section in comment-based help';
    }

    $NotesSplit        = [regex]::Split($CommentText, '(?m)^\s*\.NOTES\b');
    [string]$NotesTail = $NotesSplit[$NotesSplit.Count - 1];
    $NotesTail         = $NotesTail -replace '\s*#>\z', '';
    # Truncate if another dot-section somehow follows .NOTES
    $NextSectionMatch  = [regex]::Match($NotesTail, '(?m)^\s*\.[A-Z]{3,}\b');
    if ($NextSectionMatch.Success) {
        $NotesTail = $NotesTail.Substring(0, $NextSectionMatch.Index);
    }

    [bool]$ConcludesWithSpdx = ($NotesTail -match '(?s)(?:^|\r?\n)[ \t]*SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga\.com>[ \t]*\r?\n[ \t]*SPDX-License-Identifier: GPL-3\.0-or-later\s*\z');

    if (-not $ConcludesWithSpdx) {
        return '.NOTES must conclude with "SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>" followed by "SPDX-License-Identifier: GPL-3.0-or-later"';
    }

    return '';
}

function Test-EncodingWithoutBom()
{
    param (
        [string]$RelativePath = '',
        [byte[]]$RawBytes     = @()
    );

    [array]$EncViolations = @();

    if ($RawBytes.Length -ge 3 -and $RawBytes[0] -eq 0xEF -and $RawBytes[1] -eq 0xBB -and $RawBytes[2] -eq 0xBF) {
        $EncViolations += ('{0}:1 -- File contains a UTF-8 BOM (0xEF 0xBB 0xBF); save as UTF-8 without BOM' -f $RelativePath);
    } elseif ($RawBytes.Length -ge 2 -and (($RawBytes[0] -eq 0xFF -and $RawBytes[1] -eq 0xFE) -or ($RawBytes[0] -eq 0xFE -and $RawBytes[1] -eq 0xFF))) {
        $EncViolations += ('{0}:1 -- File contains a UTF-16/UTF-32 BOM; save as UTF-8 without BOM' -f $RelativePath);
    } elseif ([System.Array]::IndexOf($RawBytes, [byte]0) -ge 0) {
        $EncViolations += ('{0}:1 -- File contains NUL bytes (non-UTF-8 encoding); save as UTF-8 without BOM' -f $RelativePath);
    }

    return $EncViolations;
}

function Test-CompiledLibSpdxFile()
{
    param (
        [string]$RelativePath = '',
        [string]$FullPath     = ''
    );

    [array]$LibViolations = @();
    [byte[]]$RawBytes     = [System.IO.File]::ReadAllBytes($FullPath);
    $LibViolations       += Test-EncodingWithoutBom -RelativePath $RelativePath -RawBytes $RawBytes;

    for ($bIdx = 0; $bIdx -lt $RawBytes.Length; $bIdx++) {
        if ($RawBytes[$bIdx] -gt 0x7F) {
            $LibViolations += ('{0}:1 -- Compiled lib artifact contains non-ASCII byte 0x{1:X2} at offset {2} (breaks BOM-less Windows-1252 loading in Windows PowerShell 5.1)' -f $RelativePath, $RawBytes[$bIdx], $bIdx);
            break;
        }
    }

    [string]$Content = [System.IO.File]::ReadAllText($FullPath, [System.Text.Encoding]::UTF8);
    $LibTokens       = $null;
    $LibErrors       = $null;
    [void][System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$LibTokens, [ref]$LibErrors);

    if ($null -ne $LibErrors -and $LibErrors.Count -gt 0) {
        $FirstErr       = $LibErrors[0];
        $LibViolations += ('{0}:{1} -- Compiled lib artifact failed PowerShell AST parsing: {2}' -f $RelativePath, $FirstErr.Extent.StartLineNumber, $FirstErr.Message);
    }

    $TopHeaderToken = $null;
    if ($null -ne $LibTokens) {
        foreach ($LibTok in $LibTokens) {
            if ([string]$LibTok.Kind -eq 'Comment' -and $LibTok.Text.StartsWith('<#') -and $LibTok.Extent.StartLineNumber -eq 1) {
                $TopHeaderToken = $LibTok;
                break;
            }
        }
    }

    if ($null -eq $TopHeaderToken) {
        $LibViolations += ('{0}:1 -- Compiled lib artifact must start with a top-level <# ... #> header block containing .NOTES and Icinga GmbH SPDX license lines' -f $RelativePath);
    } else {
        [string]$LibSpdxIssue = Test-BlockCommentNotesAndSpdx -CommentText $TopHeaderToken.Text;
        if (-not [string]::IsNullOrEmpty($LibSpdxIssue)) {
            $LibViolations += ('{0}:1 -- Compiled lib artifact header block: {1}' -f $RelativePath, $LibSpdxIssue);
        }
    }

    return $LibViolations;
}

function Invoke-IcingaCodeStylingCheck()
{
    param (
        [string]$BasePath        = '',
        [string]$ExplicitSrcRoot = '',
        [bool]$UseExplicitSrc    = $false,
        [array]$TargetPaths      = @()
    );

    [array]$FilesToScan    = @();
    [array]$LibFilesToScan = @();

    if ($null -ne $TargetPaths -and $TargetPaths.Count -gt 0) {
        foreach ($Target in $TargetPaths) {
            [string]$Resolved = [System.IO.Path]::GetFullPath((Resolve-Path -Path $Target).ProviderPath);
            if (Test-Path -Path $Resolved -PathType Container) {
                $FilesToScan += Get-ChildItem -Path $Resolved -Recurse -Include '*.ps1', '*.psm1', '*.psd1';
            } elseif (Test-Path -Path $Resolved -PathType Leaf) {
                [string]$NormTarget = $Resolved.Replace('\', '/');
                if ($NormTarget -match '/lib/IcingaForWindows\.(Classes|Kernel)\.ps1$') {
                    $LibFilesToScan += Get-Item -Path $Resolved;
                } else {
                    $FilesToScan += Get-Item -Path $Resolved;
                }
            }
        }
    } elseif ($UseExplicitSrc) {
        if (-not (Test-Path -Path $ExplicitSrcRoot)) {
            throw "Source path not found: $ExplicitSrcRoot";
        }
        $FilesToScan = Get-ChildItem -Path $ExplicitSrcRoot -Recurse -Include '*.ps1', '*.psm1', '*.psd1';
    } else {
        # Full repository governance scope: src/, build/, Tests/, root *.ps1/*.psm1/*.psd1, and compiled lib/ headers
        [array]$DefaultDirs = @(
            (Join-Path -Path $BasePath -ChildPath 'src'),
            (Join-Path -Path $BasePath -ChildPath 'build'),
            (Join-Path -Path $BasePath -ChildPath 'Tests')
        );

        foreach ($Dir in $DefaultDirs) {
            if (Test-Path -Path $Dir -PathType Container) {
                $FilesToScan += Get-ChildItem -Path $Dir -Recurse -Include '*.ps1', '*.psm1', '*.psd1';
            }
        }

        if (Test-Path -Path $BasePath -PathType Container) {
            $FilesToScan += Get-ChildItem -Path $BasePath -File | Where-Object { $_.Extension -in @( '.ps1', '.psm1', '.psd1' ) };
        }

        [string]$LibDir = Join-Path -Path $BasePath -ChildPath 'lib';
        if (Test-Path -Path $LibDir -PathType Container) {
            foreach ($CompiledName in @( 'IcingaForWindows.Classes.ps1', 'IcingaForWindows.Kernel.ps1' )) {
                [string]$CompiledPath = Join-Path -Path $LibDir -ChildPath $CompiledName;
                if (Test-Path -Path $CompiledPath -PathType Leaf) {
                    $LibFilesToScan += Get-Item -Path $CompiledPath;
                }
            }
        }
    }

    [array]$Violations     = @();
    [string]$AssignPattern = '^(\s*)((?:(?:static|hidden)\s+)*(?:\[[A-Za-z0-9_.,\s\[\]]+\])?\s*(?:\$[A-Za-z0-9_:.]+(?:\[[^\]]+\]|\.[A-Za-z0-9_]+)*|\[[A-Za-z0-9_.]+\]::[A-Za-z0-9_]+))(\s*)((?:\+|-|\*|/)?=)(\s*)(.+)$';
    [string]$KvPattern     = '^(\s*)([A-Za-z0-9_]+|''[^'']+''|"[^"]+")(\s*)=(\s*)(.+)$';

    foreach ($LibFile in $LibFilesToScan) {
        [string]$LibRelPath = $LibFile.FullName;
        if ($LibRelPath.StartsWith($BasePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $LibRelPath = $LibRelPath.Substring($BasePath.Length).TrimStart('\', '/');
        }
        $Violations += Test-CompiledLibSpdxFile -RelativePath $LibRelPath -FullPath $LibFile.FullName;
    }

    foreach ($File in $FilesToScan) {
        [string]$RelPath = $File.FullName;
        if ($RelPath.StartsWith($BasePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $RelPath = $RelPath.Substring($BasePath.Length).TrimStart('\', '/');
        }
        [string]$NormRelPath = $RelPath.Replace('\', '/');
        [string]$NormFull    = $File.FullName.Replace('\', '/');

        [bool]$IsPsd1File    = ($File.Extension -ieq '.psd1');
        [bool]$IsSrcFile     = ($NormRelPath -match '^src/' -or $NormFull -match '/src/');
        [bool]$IsClassesFile = ($NormRelPath -match '^src/Classes/' -or $NormFull -match '/src/Classes/');

        [byte[]]$RawBytes    = [System.IO.File]::ReadAllBytes($File.FullName);

        # 1. Check UTF-8 without BOM (reject UTF-8 BOM, UTF-16 LE/BE BOM, UTF-32 BOM and NUL-interleaved encodings)
        $Violations         += Test-EncodingWithoutBom -RelativePath $RelPath -RawBytes $RawBytes;

        [string]$Content     = [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8);
        [array]$Lines        = $Content -split "`r?`n";
        [int]$LineCount      = $Lines.Count;

        # 2a. Check single trailing newline at end of file
        if ($Content.Length -eq 0 -or -not $Content.EndsWith("`n")) {
            $Violations += ('{0}:{1} -- File must end with a single trailing newline' -f $RelPath, [System.Math]::Max(1, $LineCount));
        } elseif ($Content -match '(\r?\n){2}\z') {
            $Violations += ('{0}:{1} -- File ends with multiple trailing blank lines; end with a single trailing newline' -f $RelPath, [System.Math]::Max(1, ($LineCount - 1)));
        }

        # Strip trailing empty element produced by final newline for line-by-line scan
        if ($LineCount -gt 0 -and '' -eq $Lines[$LineCount - 1]) {
            $LineCount--;
        }

        # Parse PowerShell AST & tokens for comment/string-safe delimiter, block-comment, class/enum and hashtable checks
        $Tokens                         = $null;
        $ParseErrors                    = $null;
        $Ast                            = [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$Tokens, [ref]$ParseErrors);

        [hashtable]$BlockCommentLines   = @{ };
        [hashtable]$StringInteriorLines = @{ };
        [hashtable]$TokensByLine        = @{ };
        [hashtable]$InlineCommentCol    = @{ };
        [array]$BlockCommentTokens      = @();

        if ($null -ne $Tokens) {
            foreach ($Tok in $Tokens) {
                [string]$TokKind = [string]$Tok.Kind;
                [int]$TokStartLn = $Tok.Extent.StartLineNumber;
                [int]$TokEndLn   = $Tok.Extent.EndLineNumber;

                if (-not $TokensByLine.ContainsKey($TokStartLn)) {
                    $TokensByLine[$TokStartLn] = New-Object System.Collections.ArrayList;
                }
                [void]$TokensByLine[$TokStartLn].Add($Tok);

                if ($TokKind -eq 'Comment') {
                    if ($Tok.Text.StartsWith('<#')) {
                        $BlockCommentTokens += $Tok;
                        for ($cLn = $TokStartLn; $cLn -le $TokEndLn; $cLn++) {
                            $BlockCommentLines[$cLn] = $true;
                        }
                    } else {
                        if (-not $InlineCommentCol.ContainsKey($TokStartLn) -or $Tok.Extent.StartColumnNumber -lt $InlineCommentCol[$TokStartLn]) {
                            $InlineCommentCol[$TokStartLn] = $Tok.Extent.StartColumnNumber;
                        }
                    }
                } elseif ($TokKind -eq 'StringLiteral' -or $TokKind -eq 'StringExpandable' -or $TokKind -eq 'HereStringLiteral' -or $TokKind -eq 'HereStringExpandable') {
                    for ($sLn = ($TokStartLn + 1); $sLn -le $TokEndLn; $sLn++) {
                        $StringInteriorLines[$sLn] = $true;
                    }
                }
            }
        }

        # 7. Check all rows of Markdown .PARAMETER tables strictly inside AST <# ... #> block comments
        foreach ($BlockComment in $BlockCommentTokens) {
            [int]$HelpStartIdx = $BlockComment.Extent.StartLineNumber - 1;
            [int]$HelpEndIdx   = [System.Math]::Min($LineCount, $BlockComment.Extent.EndLineNumber);

            for ($hIdx = $HelpStartIdx; $hIdx -lt $HelpEndIdx; $hIdx++) {
                if (($hIdx + 1) -lt $HelpEndIdx -and $Lines[$hIdx] -match '^\s*\|\s*Name\s*\|' -and $Lines[$hIdx + 1] -match '^\s*\|\s*-+\s*\|') {
                    [string]$ExpectedPipes = Get-PipeIndices -Line $Lines[$hIdx];
                    [int]$PipeCount        = ($ExpectedPipes -split ',').Count;
                    [int]$RowCursor        = $hIdx + 1;
                    [bool]$TableMismatch   = ($PipeCount -lt 5);

                    while ($RowCursor -lt $HelpEndIdx -and $Lines[$RowCursor].TrimStart().StartsWith('|')) {
                        [string]$RowPipes = Get-PipeIndices -Line $Lines[$RowCursor];
                        if ($RowPipes -ne $ExpectedPipes) {
                            $TableMismatch = $true;
                        }
                        $RowCursor++;
                    }

                    [int]$DataRows = $RowCursor - ($hIdx + 2);
                    if ($DataRows -lt 1 -or $TableMismatch) {
                        $Violations += ('{0}:{1}-{2} -- Markdown .PARAMETER table "|" pipes must be vertically aligned across header, separator and all value rows' -f $RelPath, ($hIdx + 1), $RowCursor);
                    }

                    $hIdx = $RowCursor - 1;
                }
            }
        }

        # 4a. Check AST class and enum declarations for Allman brace style and record enum member lines
        [hashtable]$EnumMemberLines = @{ };
        [array]$TypeDefs            = @($Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.TypeDefinitionAst] }, $true));
        [array]$TopLevelTypeDefs    = @();

        foreach ($TypeDef in $TypeDefs) {
            [bool]$HasAncestorType = $false;
            $ParentCursor          = $TypeDef.Parent;
            while ($null -ne $ParentCursor) {
                if ($ParentCursor -is [System.Management.Automation.Language.TypeDefinitionAst]) {
                    $HasAncestorType = $true;
                    break;
                }
                $ParentCursor = $ParentCursor.Parent;
            }
            if (-not $HasAncestorType) {
                $TopLevelTypeDefs += $TypeDef;
            }

            if ($TypeDef.IsEnum) {
                for ($eLn = $TypeDef.Extent.StartLineNumber; $eLn -le $TypeDef.Extent.EndLineNumber; $eLn++) {
                    $EnumMemberLines[$eLn] = $true;
                }
            }

            $OpenCurly = $null;
            if ($null -ne $Tokens) {
                foreach ($CandidateTok in $Tokens) {
                    if ([string]$CandidateTok.Kind -eq 'LCurly' -and $CandidateTok.Extent.StartOffset -ge $TypeDef.Extent.StartOffset) {
                        $OpenCurly = $CandidateTok;
                        break;
                    }
                }
            }

            if ($null -ne $OpenCurly) {
                [int]$BraceLineIdx = $OpenCurly.Extent.StartLineNumber - 1;
                [string]$BraceCode = $Lines[$BraceLineIdx];
                if ($InlineCommentCol.ContainsKey($OpenCurly.Extent.StartLineNumber)) {
                    $BraceCode = $BraceCode.Substring(0, ($InlineCommentCol[$OpenCurly.Extent.StartLineNumber] - 1));
                }

                if ($OpenCurly.Extent.StartLineNumber -le $TypeDef.Extent.StartLineNumber -or $BraceCode.Trim() -ne '{') {
                    [string]$KindLabel = 'class';
                    if ($TypeDef.IsEnum) {
                        $KindLabel = 'enum';
                    }
                    $Violations += ('{0}:{1} -- "{2} {3}" declaration must place opening "{{" on its own line (Allman style)' -f $RelPath, $TypeDef.Extent.StartLineNumber, $KindLabel, $TypeDef.Name);
                }
            }
        }

        # 4b & 5. Check AST function/class-method Allman braces and enforce function scope rules in src/
        [array]$FuncDefs         = @($Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and -not $Node.IsFilter -and -not $Node.IsWorkflow }, $true));
        [array]$TopStandaloneFns = @();
        [array]$NestedStandalone = @();

        foreach ($FuncDef in $FuncDefs) {
            [bool]$IsClassMethod = ($null -ne $FuncDef.Parent -and $FuncDef.Parent -is [System.Management.Automation.Language.FunctionMemberAst]);
            [int]$FuncHeaderLn   = $FuncDef.Extent.StartLineNumber;
            if ($IsClassMethod) {
                $FuncHeaderLn = $FuncDef.Parent.Extent.StartLineNumber;
            } else {
                [bool]$HasParentFunc = $false;
                $FnAncestor          = $FuncDef.Parent;
                while ($null -ne $FnAncestor) {
                    if ($FnAncestor -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                        $HasParentFunc = $true;
                        break;
                    }
                    $FnAncestor = $FnAncestor.Parent;
                }

                if ($HasParentFunc) {
                    $NestedStandalone += $FuncDef;
                } else {
                    $TopStandaloneFns += $FuncDef;
                }
            }

            [string]$FuncHdrCode = $Lines[$FuncHeaderLn - 1];
            if ($InlineCommentCol.ContainsKey($FuncHeaderLn)) {
                $FuncHdrCode = $FuncHdrCode.Substring(0, ($InlineCommentCol[$FuncHeaderLn] - 1));
            }

            $FuncOpenCurly = $null;
            if ($null -ne $Tokens) {
                foreach ($CandidateFuncTok in $Tokens) {
                    if ([string]$CandidateFuncTok.Kind -eq 'LCurly' -and $CandidateFuncTok.Extent.StartOffset -ge $FuncDef.Extent.StartOffset) {
                        $FuncOpenCurly = $CandidateFuncTok;
                        break;
                    }
                }
            }

            [bool]$ValidFuncBrace = ($null -ne $FuncOpenCurly -and $FuncOpenCurly.Extent.StartLineNumber -gt $FuncHeaderLn);

            if ($ValidFuncBrace) {
                [string]$FuncBraceCode = $Lines[$FuncOpenCurly.Extent.StartLineNumber - 1];
                if ($InlineCommentCol.ContainsKey($FuncOpenCurly.Extent.StartLineNumber)) {
                    $FuncBraceCode = $FuncBraceCode.Substring(0, ($InlineCommentCol[$FuncOpenCurly.Extent.StartLineNumber] - 1));
                }
                if ($FuncBraceCode.Trim() -ne '{') {
                    $ValidFuncBrace = $false;
                }
            }

            if ($IsClassMethod) {
                if (-not $ValidFuncBrace) {
                    $Violations += ('{0}:{1} -- Class method/constructor declaration must place opening "{{" on its own next line (Allman style): {2}' -f $RelPath, $FuncHeaderLn, $FuncHdrCode.Trim());
                }
            } else {
                [bool]$ValidFuncHeader = ($FuncHdrCode.Trim() -match '^function\s+(?:[A-Za-z]+:)?[A-Za-z0-9_-]+\(\)\s*$');
                if (-not $ValidFuncHeader -or -not $ValidFuncBrace) {
                    $Violations += ('{0}:{1} -- Function declaration must use "function Name()" with opening "{{" on its own next line (Allman style): {2}' -f $RelPath, $FuncHeaderLn, $FuncHdrCode.Trim());
                }
            }
        }

        if ($IsSrcFile) {
            if ($IsClassesFile) {
                foreach ($ForbiddenFn in ($TopStandaloneFns + $NestedStandalone)) {
                    $Violations += ('{0}:{1} -- Standalone function "{2}" is forbidden under src/Classes/; define classes and enums only' -f $RelPath, $ForbiddenFn.Extent.StartLineNumber, $ForbiddenFn.Name);
                }
            } else {
                foreach ($ForbiddenType in $TopLevelTypeDefs) {
                    $Violations += ('{0}:{1} -- Class or enum "{2}" is forbidden outside src/Classes/; move type definitions to src/Classes/' -f $RelPath, $ForbiddenType.Extent.StartLineNumber, $ForbiddenType.Name);
                }
                if ($TopStandaloneFns.Count -eq 0) {
                    $Violations += ('{0}:1 -- Source file under src/ (outside src/Classes/) must define a top-level function' -f $RelPath);
                } elseif ($TopStandaloneFns.Count -gt 1) {
                    $Violations += ('{0}:{1} -- Multiple top-level functions ({2}) in a single src/ file are forbidden; place each function in its own .ps1 file' -f $RelPath, $TopStandaloneFns[1].Extent.StartLineNumber, $TopStandaloneFns.Count);
                }
                foreach ($NestedFn in $NestedStandalone) {
                    $Violations += ('{0}:{1} -- Nested function "{2}" inside another function is forbidden under src/' -f $RelPath, $NestedFn.Extent.StartLineNumber, $NestedFn.Name);
                }
            }
        }

        # 8. Check mandatory .NOTES and Icinga GmbH SPDX license lines
        if ($IsPsd1File) {
            if ($Content -match '\bModuleVersion\s*=') {
                if ($Content -notmatch 'Copyright\s*=\s*''[^'']*GPL-3\.0-or-later[^'']*''') {
                    $Violations += ('{0}:1 -- Module manifest Copyright must specify GPL-3.0-or-later matching LICENSE' -f $RelPath);
                }
                if ($Content -notmatch '(?m)^\s*SPDX\s*=\s*''''\s*;') {
                    $Violations += ('{0}:1 -- Module manifest PrivateData must include "SPDX = '''';"' -f $RelPath);
                }
            }

            [bool]$HasPsd1Copy = $false;
            [bool]$HasPsd1Lic  = $false;
            if ($null -ne $Tokens) {
                foreach ($PsdTok in $Tokens) {
                    if ([string]$PsdTok.Kind -eq 'Comment') {
                        if ($PsdTok.Text -match '^\s*#\s*SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga\.com>\s*$') {
                            $HasPsd1Copy = $true;
                        } elseif ($PsdTok.Text -match '^\s*#\s*SPDX-License-Identifier: GPL-3\.0-or-later\s*$') {
                            $HasPsd1Lic = $true;
                        }
                    }
                }
            }
            if (-not ($HasPsd1Copy -and $HasPsd1Lic)) {
                $Violations += ('{0}:1 -- PowerShell data file (.psd1) must include "# SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>" and "# SPDX-License-Identifier: GPL-3.0-or-later" comments' -f $RelPath);
            }
        } elseif ($IsClassesFile) {
            if ($TopLevelTypeDefs.Count -eq 0) {
                $Violations += ('{0}:1 -- Class/enum file under src/Classes/ must define at least one class or enum with .NOTES and SPDX header' -f $RelPath);
            } else {
                [int]$PrevTypeEndOffset = 0;
                foreach ($TopType in $TopLevelTypeDefs) {
                    $PrecedingComment = $null;
                    foreach ($CandComment in $BlockCommentTokens) {
                        if ($CandComment.Extent.StartOffset -ge $PrevTypeEndOffset -and $CandComment.Extent.EndOffset -le $TopType.Extent.StartOffset) {
                            $PrecedingComment = $CandComment;
                        }
                    }

                    if ($null -eq $PrecedingComment) {
                        $Violations += ('{0}:{1} -- Type "{2}" is missing a preceding <# ... #> help block with .NOTES and Icinga GmbH SPDX lines' -f $RelPath, $TopType.Extent.StartLineNumber, $TopType.Name);
                    } else {
                        [string]$SpdxIssue = Test-BlockCommentNotesAndSpdx -CommentText $PrecedingComment.Text;
                        if (-not [string]::IsNullOrEmpty($SpdxIssue)) {
                            $Violations += ('{0}:{1} -- Type "{2}" help block: {3}' -f $RelPath, $PrecedingComment.Extent.StartLineNumber, $TopType.Name, $SpdxIssue);
                        }
                    }
                    $PrevTypeEndOffset = $TopType.Extent.EndOffset;
                }
            }
        } elseif ($IsSrcFile) {
            if ($TopStandaloneFns.Count -ge 1) {
                $PrimaryFn     = $TopStandaloneFns[0];
                $FnHelpComment = $null;
                foreach ($CandFnComment in $BlockCommentTokens) {
                    if ($CandFnComment.Extent.EndOffset -le $PrimaryFn.Extent.StartOffset) {
                        $FnHelpComment = $CandFnComment;
                    }
                }

                if ($null -eq $FnHelpComment) {
                    $Violations += ('{0}:{1} -- Function "{2}" is missing a preceding <# ... #> help block with .NOTES and Icinga GmbH SPDX lines' -f $RelPath, $PrimaryFn.Extent.StartLineNumber, $PrimaryFn.Name);
                } else {
                    [string]$FnSpdxIssue = Test-BlockCommentNotesAndSpdx -CommentText $FnHelpComment.Text;
                    if (-not [string]::IsNullOrEmpty($FnSpdxIssue)) {
                        $Violations += ('{0}:{1} -- Function "{2}" help block: {3}' -f $RelPath, $FnHelpComment.Extent.StartLineNumber, $PrimaryFn.Name, $FnSpdxIssue);
                    }
                }
            }
        } else {
            # build/*.ps1, IcingaForWindows.psm1, Tests/*.ps1, or standalone scripts
            [array]$TopLevelHelpBlocks = @($BlockCommentTokens | Where-Object { $_.Extent.StartColumnNumber -eq 1 -and $_.Text -match '(?m)^\s*\.(?:SYNOPSIS|NOTES)\b' });
            [array]$AllDocHelpBlocks   = @($BlockCommentTokens | Where-Object { $_.Text -match '(?m)^\s*\.(?:SYNOPSIS|DESCRIPTION|PARAMETER|NOTES)\b' });

            if ($TopLevelHelpBlocks.Count -eq 0) {
                $Violations += ('{0}:1 -- File is missing a top-level <# ... #> help block containing .NOTES and Icinga GmbH SPDX lines' -f $RelPath);
            }
            foreach ($DocHelpBlock in $AllDocHelpBlocks) {
                [string]$HeaderSpdxIssue = Test-BlockCommentNotesAndSpdx -CommentText $DocHelpBlock.Text;
                if (-not [string]::IsNullOrEmpty($HeaderSpdxIssue)) {
                    $Violations += ('{0}:{1} -- Help block: {2}' -f $RelPath, $DocHelpBlock.Extent.StartLineNumber, $HeaderSpdxIssue);
                }
            }
        }

        # 4c. Check AST if / elseif clauses for single-line condition + opening '{' on the same line
        [array]$IfAsts = @($Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.IfStatementAst] }, $true));

        foreach ($IfAst in $IfAsts) {
            foreach ($IfClause in $IfAst.Clauses) {
                $ClauseCondAst  = $IfClause.Item1;
                $ClauseBodyAst  = $IfClause.Item2;
                [int]$ClauseLn  = $ClauseCondAst.Extent.StartLineNumber;
                [bool]$SpanCond = ($ClauseCondAst.Extent.StartLineNumber -ne $ClauseCondAst.Extent.EndLineNumber -or $ClauseBodyAst.Extent.StartLineNumber -ne $ClauseLn);

                if ($SpanCond -and $ClauseLn -ge 1 -and $ClauseLn -le $LineCount) {
                    $Violations += ('{0}:{1} -- "if/elseif" condition must be on a single line ending with "{{" (do not split conditions across lines): {2}' -f $RelPath, $ClauseLn, $Lines[$ClauseLn - 1].Trim());
                }
            }
        }

        # 6a. Check AST HashtableAst entries for single-entry spacing and post-'=' single space
        [array]$HashtableAsts = @($Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.HashtableAst] }, $true));

        foreach ($HtAst in $HashtableAsts) {
            if ($HtAst.KeyValuePairs.Count -eq 0) {
                continue;
            }

            if ($HtAst.KeyValuePairs.Count -eq 1) {
                $SinglePair       = $HtAst.KeyValuePairs[0];
                $SingleKeyAst     = $SinglePair.Item1;
                $SingleValAst     = $SinglePair.Item2;
                [int]$SingleKeyLn = $SingleKeyAst.Extent.StartLineNumber;
                [string]$KeyLine  = $Lines[$SingleKeyLn - 1];
                [int]$KeyEndIdx   = $SingleKeyAst.Extent.EndColumnNumber - 1;
                [int]$EqPos       = $KeyLine.IndexOf('=', $KeyEndIdx);

                if ($EqPos -ge 0) {
                    [int]$PreEqSpaces  = $EqPos - $KeyEndIdx;
                    [int]$PostEqSpaces = 1;
                    if ($SingleValAst.Extent.StartLineNumber -eq $SingleKeyLn) {
                        $PostEqSpaces = ($SingleValAst.Extent.StartColumnNumber - 1) - ($EqPos + 1);
                    }

                    if ($PreEqSpaces -ne 1 -or $PostEqSpaces -ne 1) {
                        $Violations += ('{0}:{1} -- Single-entry hashtable must have 1 space before and 1 space after "=": {2}' -f $RelPath, $SingleKeyLn, $KeyLine.Trim());
                    }
                }
            } else {
                foreach ($MultiPair in $HtAst.KeyValuePairs) {
                    $MultiKeyAst     = $MultiPair.Item1;
                    $MultiValAst     = $MultiPair.Item2;
                    [int]$MultiKeyLn = $MultiKeyAst.Extent.StartLineNumber;
                    [string]$MKeyLn  = $Lines[$MultiKeyLn - 1];
                    [int]$MKeyEndIdx = $MultiKeyAst.Extent.EndColumnNumber - 1;
                    [int]$MEqPos     = $MKeyLn.IndexOf('=', $MKeyEndIdx);

                    if ($MEqPos -ge 0) {
                        [int]$MPreSpaces  = $MEqPos - $MKeyEndIdx;
                        [int]$MPostSpaces = 1;
                        if ($MultiValAst.Extent.StartLineNumber -eq $MultiKeyLn) {
                            $MPostSpaces = ($MultiValAst.Extent.StartColumnNumber - 1) - ($MEqPos + 1);
                        }

                        if ($MPreSpaces -lt 1 -or $MPostSpaces -ne 1) {
                            $Violations += ('{0}:{1} -- Hashtable entry must have at least 1 space before and exactly 1 space after "=": {2}' -f $RelPath, $MultiKeyLn, $MKeyLn.Trim());
                        }
                    }
                }
            }
        }

        [bool]$InMultiline   = $false;
        [int]$MultilineDepth = 0;
        [array]$AssignBlock  = @();
        [array]$KvBlock      = @();

        for ($idx = 0; $idx -lt $LineCount; $idx++) {
            [int]$LineNumber = $idx + 1;
            [string]$Line    = $Lines[$idx];

            # 2b & 3. Check tab characters, trailing whitespace and forbidden em/en-dashes
            if ($Line.Contains("`t")) {
                $Violations += ('{0}:{1} -- Tab character found; use 4 spaces for indentation' -f $RelPath, $LineNumber);
            }

            if ($Line -match '\s+$') {
                $Violations += ('{0}:{1} -- Trailing whitespace at end of line' -f $RelPath, $LineNumber);
            }

            if ($Line.IndexOf([char]0x2014) -ge 0 -or $Line.IndexOf([char]0x2013) -ge 0) {
                $Violations += ('{0}:{1} -- Forbidden Unicode em-dash or en-dash found; use plain ASCII "-" or "--"' -f $RelPath, $LineNumber);
            } elseif ($Line -match '[^\x00-\x7F]') {
                $NonAsciiMatch = [regex]::Match($Line, '[^\x00-\x7F]');
                [int]$CodePt   = [int][char]$Line[$NonAsciiMatch.Index];
                if ([char]::IsSurrogatePair($Line, $NonAsciiMatch.Index)) {
                    $CodePt = [char]::ConvertToUtf32($Line, $NonAsciiMatch.Index);
                }
                $Violations += ('{0}:{1} -- Forbidden non-ASCII character U+{2:X4} found in BOM-less PowerShell file (causes Windows-1252 Mojibake or quote-lexer parse errors in Windows PowerShell 5.1); use plain 7-bit ASCII or [char]0xXXXX' -f $RelPath, $LineNumber, $CodePt);
            }

            if ($BlockCommentLines.ContainsKey($LineNumber)) {
                if ($AssignBlock.Count -gt 0) {
                    $Violations += Test-AssignmentBlockAlignment -RelativePath $RelPath -Block $AssignBlock;
                    $AssignBlock = @();
                }
                if ($KvBlock.Count -gt 0) {
                    $Violations += Test-KeyValueBlockAlignment -RelativePath $RelPath -Block $KvBlock -EnumLineNums $EnumMemberLines;
                    $KvBlock     = @();
                }
                continue;
            }

            if ($StringInteriorLines.ContainsKey($LineNumber)) {
                if ($InMultiline) {
                    [array]$StrLineToks = $TokensByLine[$LineNumber];
                    $MultilineDepth    += Get-TokenDelimiterDelta -LineTokens $StrLineToks -MinColumn 1;
                    [string]$StrCode    = $Line;
                    if ($InlineCommentCol.ContainsKey($LineNumber)) {
                        $StrCode = $StrCode.Substring(0, ($InlineCommentCol[$LineNumber] - 1));
                    }
                    [string]$StrTrimmed = $StrCode.Trim();
                    if ($MultilineDepth -le 0 -and ($StrTrimmed.EndsWith(';') -or $StrTrimmed.EndsWith(','))) {
                        $InMultiline    = $false;
                        $MultilineDepth = 0;
                    }
                }
                continue;
            }

            [string]$Stripped = $Line.Trim();

            if ('' -ne $Stripped -and $Line -match '^( +)') {
                [int]$LeadingSpaceCount = $Matches[1].Length;
                if (($LeadingSpaceCount % 4) -ne 0) {
                    $Violations += ('{0}:{1} -- Indentation must use multiples of 4 spaces (found {2} leading spaces)' -f $RelPath, $LineNumber, $LeadingSpaceCount);
                }
            }

            [string]$CodeOnly = $Line;
            if ($InlineCommentCol.ContainsKey($LineNumber)) {
                $CodeOnly = $Line.Substring(0, ($InlineCommentCol[$LineNumber] - 1));
            }
            [string]$CodeStripped = $CodeOnly.Trim();

            if ('' -eq $CodeStripped -or $CodeStripped -match '^\[Validate[A-Za-z]+\(') {
                if ('' -eq $CodeStripped -and $KvBlock.Count -gt 0) {
                    $Violations += Test-KeyValueBlockAlignment -RelativePath $RelPath -Block $KvBlock -EnumLineNums $EnumMemberLines;
                    $KvBlock     = @();
                }
                continue;
            }

            # 4c. Check single-line if / elseif conditions (must open '{' on the same line, not wrap across newlines)
            if ($CodeStripped -match '^(?:\}\s*)?(?:if|elseif)\s*\(') {
                if ($CodeStripped -notmatch '\{\s*$' -and $CodeStripped -notmatch '\}\s*$') {
                    $Violations += ('{0}:{1} -- "if/elseif" condition must be on a single line ending with "{{" (do not split conditions across lines): {2}' -f $RelPath, $LineNumber, $CodeStripped);
                }
            }

            # 6b. Check contiguous hashtable / enum key = value blocks
            if ($CodeOnly -match $KvPattern -and -not $CodeStripped.StartsWith('$')) {
                [string]$KvIndent     = $Matches[1];
                [string]$KvKey        = $Matches[2];
                [string]$KvPreSpaces  = $Matches[3];
                [string]$KvPostSpaces = $Matches[4];
                [string]$KvRhs        = $Matches[5];
                [int]$KvLhsEnd        = $KvIndent.Length + $KvKey.Length;
                [int]$KvEqCol         = $KvLhsEnd + $KvPreSpaces.Length;

                if ($KvBlock.Count -gt 0 -and $KvBlock[0].Indent -ne $KvIndent.Length) {
                    $Violations += Test-KeyValueBlockAlignment -RelativePath $RelPath -Block $KvBlock -EnumLineNums $EnumMemberLines;
                    $KvBlock     = @();
                }

                $KvBlock += [PSCustomObject]@{
                    'Line'       = $LineNumber;
                    'Indent'     = $KvIndent.Length;
                    'LhsEnd'     = $KvLhsEnd;
                    'EqCol'      = $KvEqCol;
                    'PostSpaces' = $KvPostSpaces.Length;
                    'Rhs'        = $KvRhs;
                    'Raw'        = $Line;
                };
            } elseif ($KvBlock.Count -gt 0) {
                $Violations += Test-KeyValueBlockAlignment -RelativePath $RelPath -Block $KvBlock -EnumLineNums $EnumMemberLines;
                $KvBlock     = @();
            }

            # 6c. Check variable / property / param assignment alignment across blocks
            [array]$CurrentLineTokens = $TokensByLine[$LineNumber];

            if ($InMultiline) {
                $MultilineDepth += Get-TokenDelimiterDelta -LineTokens $CurrentLineTokens -MinColumn 1;
                if ($MultilineDepth -le 0 -and ($CodeStripped.EndsWith(';') -or $CodeStripped.EndsWith(','))) {
                    $InMultiline    = $false;
                    $MultilineDepth = 0;
                }
                continue;
            }

            if ($CodeOnly -match $AssignPattern) {
                [string]$IndentStr  = $Matches[1];
                [string]$Lhs        = $Matches[2];
                [string]$PreSpaces  = $Matches[3];
                [string]$Op         = $Matches[4];
                [string]$PostSpaces = $Matches[5];
                [string]$Rhs        = $Matches[6];

                if ($AssignBlock.Count -gt 0 -and $AssignBlock[0].Indent -ne $IndentStr.Length) {
                    $Violations += Test-AssignmentBlockAlignment -RelativePath $RelPath -Block $AssignBlock;
                    $AssignBlock = @();
                }

                [int]$LhsEnd       = $IndentStr.Length + $Lhs.Length;
                [int]$EqCol        = $LhsEnd + $PreSpaces.Length + ($Op.Length - 1);

                $AssignBlock      += [PSCustomObject]@{
                    'Line'       = $LineNumber;
                    'Indent'     = $IndentStr.Length;
                    'LhsEnd'     = $LhsEnd;
                    'Op'         = $Op;
                    'EqCol'      = $EqCol;
                    'PostSpaces' = $PostSpaces.Length;
                    'Rhs'        = $Rhs;
                    'Raw'        = $Line;
                };

                [int]$NextCheckIdx = $idx + 1;
                while ($NextCheckIdx -lt $LineCount) {
                    [string]$NextCheckCode = $Lines[$NextCheckIdx];
                    if ($InlineCommentCol.ContainsKey($NextCheckIdx + 1)) {
                        $NextCheckCode = $NextCheckCode.Substring(0, ($InlineCommentCol[$NextCheckIdx + 1] - 1));
                    }
                    if ('' -ne $NextCheckCode.Trim()) {
                        break;
                    }
                    $NextCheckIdx++;
                }

                [bool]$NextIsParamClose = ($NextCheckIdx -lt $LineCount -and $Lines[$NextCheckIdx].Trim().StartsWith(');'));
                [int]$RhsStartCol       = $EqCol + 1 + $PostSpaces.Length + 1;
                [int]$InitialDepth      = Get-TokenDelimiterDelta -LineTokens $CurrentLineTokens -MinColumn $RhsStartCol;

                if ($InitialDepth -gt 0 -or (-not $CodeStripped.EndsWith(';') -and -not $CodeStripped.EndsWith(',') -and -not $NextIsParamClose)) {
                    $InMultiline    = $true;
                    $MultilineDepth = $InitialDepth;
                }
            } else {
                if ($CodeStripped.Contains('{') -or $CodeStripped.Contains('}') -or $CodeStripped -match '^(if|elseif|else|foreach|for|while|switch|try|catch|finally|param|function|class|enum|return|throw|break|continue)\b') {
                    if ($AssignBlock.Count -gt 0) {
                        $Violations += Test-AssignmentBlockAlignment -RelativePath $RelPath -Block $AssignBlock;
                        $AssignBlock = @();
                    }
                }
            }
        }

        if ($AssignBlock.Count -gt 0) {
            $Violations += Test-AssignmentBlockAlignment -RelativePath $RelPath -Block $AssignBlock;
        }
        if ($KvBlock.Count -gt 0) {
            $Violations += Test-KeyValueBlockAlignment -RelativePath $RelPath -Block $KvBlock -EnumLineNums $EnumMemberLines;
        }
    }

    return @($Violations | Select-Object -Unique);
}

[array]$AllViolations = Invoke-IcingaCodeStylingCheck -BasePath $ModuleBasePath -ExplicitSrcRoot $SourceFolder -UseExplicitSrc $HasExplicitSourceFolder -TargetPaths $Path;

if ($PassThru) {
    return $AllViolations;
}

Write-Host "`n[+] Running Code Styling & SPDX License tests..." -ForegroundColor Yellow;

if ($AllViolations.Count -gt 0) {
    foreach ($Violation in $AllViolations) {
        Write-Host ('[ERROR] {0}' -f $Violation) -ForegroundColor Red;
    }
    throw ('Code Styling & SPDX License test failed with {0} violation(s).' -f $AllViolations.Count);
}

Write-Host '  * All Code Styling & SPDX License checks passed' -ForegroundColor Green;
return $true;

<#
.SYNOPSIS
Compares two text or JSON inputs and produces a unified diff

.DESCRIPTION
Compare-IcingaTextContent computes a line-level unified diff between an old and a
new content source. Pass the new content via -NewConfig and the old baseline either
as an inline string via -OldConfig or as a file path via -OldFile. When -OldFile is
provided the file is read via Read-SecureFile. Both inputs are normalized via
ConvertFrom-Json / ConvertTo-Json before comparison so that insignificant JSON
formatting differences are ignored. The diff is computed with a
Longest-Common-Subsequence (LCS) algorithm and output follows the unified diff
format with three lines of context around each changed block. When -Colorized is
set, removed lines carry ANSI red and added lines ANSI green; the output is
otherwise plain text. Compatible with PowerShell 5 and PowerShell 7. No external
tools or modules are required.

.PARAMETER NewConfig
| Name      | Type          | Description                                     | Default |
|-----------|---------------|-------------------------------------------------|---------|
| NewConfig | System.String | The new content as a JSON string or plain text. | $null   |

.PARAMETER OldConfig
| Name      | Type          | Description                                           | Default |
|-----------|---------------|-------------------------------------------------------|---------|
| OldConfig | System.String | The baseline content as a JSON string or plain text.  | $null   |

.PARAMETER OldFile
| Name    | Type          | Description                                                           | Default |
|---------|---------------|-----------------------------------------------------------------------|---------|
| OldFile | System.String | File path to the baseline; read via Read-SecureFile when provided.    | $null   |

.PARAMETER Colorized
| Name      | Type                                         | Description                                                    | Default |
|-----------|----------------------------------------------|----------------------------------------------------------------|---------|
| Colorized | System.Management.Automation.SwitchParameter | When set, embeds ANSI color codes (green/red/cyan) in output. | $false  |

.OUTPUTS
System.Collections.Hashtable — Always returns @{ ExitCode = System.Int32; Output = System.String }.
ExitCode is 0 when both inputs are identical after normalization, 1 when they differ.
Output is an empty string when identical; otherwise a unified diff with header lines
(--- old / +++ new), @@ hunk headers and +/-/space-prefixed content lines.
With -Colorized the Output string contains ANSI escape sequences.

.EXAMPLE
PS> Compare-IcingaTextContent -NewConfig '{"key":"new"}' -OldConfig '{"key":"old"}'

Compares two inline JSON strings and returns a hashtable with the unified diff in Output.

.EXAMPLE
PS> Compare-IcingaTextContent -NewConfig $JsonString -OldFile 'C:\icinga\restapi.json' -Colorized

Reads restapi.json via Read-SecureFile, normalizes both sides as JSON, and returns
a hashtable with a colorized unified diff in Output.

.NOTES
Read-SecureFile restricts reads to the module root and module config directories;
paths outside those locations will cause -OldFile to resolve to an empty baseline.
-OldConfig and -OldFile are mutually exclusive by convention; when both are provided
-OldConfig takes precedence. The LCS algorithm allocates an (m+1)x(n+1) integer
matrix; inputs beyond a few thousand lines will consume significant memory, which
is acceptable for config-file comparison. No external binaries, modules, or .NET
packages beyond the PowerShell standard library are used.
#>
function Compare-IcingaTextContent()
{
    param (
        [string]$NewConfig = $null,
        [string]$OldConfig = $null,
        [string]$OldFile   = $null,
        [switch]$Colorized = $false
    );


    # Resolve OldConfig: a string without newlines that exists as a file on disk
    # is treated as a path; everything else is treated as inline content.
    [string]$OldResolved = $OldConfig;

    if ([string]::IsNullOrEmpty($OldConfig) -and -not [string]::IsNullOrEmpty($OldFile)) {
        if (Test-Path -Path $OldFile -PathType Leaf) {
            $ReadResult = Read-SecureFile -File $OldFile;

            if (-not [string]::IsNullOrEmpty($ReadResult)) {
                $OldResolved = $ReadResult;
            }
        }
    }

    [string]$NormalizedOld = Get-NormalizedTextContent -Content $OldResolved;
    [string]$NormalizedNew = Get-NormalizedTextContent -Content $NewConfig;

    if ($NormalizedOld -ceq $NormalizedNew) {
        return @{
            'ExitCode' = 0;
            'Output'   = '';
        };
    }

    # Split into lines; strip trailing CR for mixed \r\n sources.
    [string[]]$OldLines = $NormalizedOld -split '\r?\n';
    [string[]]$NewLines = $NormalizedNew -split '\r?\n';
    [int]$OldCount      = $OldLines.Count;
    [int]$NewCount      = $NewLines.Count;

    # Build the LCS table — O(m*n) time and space.
    # Use a jagged int[][] instead of int[,] — New-Object 'int[,]' is unreliable
    # in PS5 and causes the array to be typed as System.Object[], which turns
    # two-index access into array slicing instead of element lookup.
    $LCS = New-Object 'int[][]' ($OldCount + 1);
    for ($i = 0; $i -le $OldCount; $i++) {
        $LCS[$i] = New-Object 'int[]' ($NewCount + 1);
    }

    for ($i = 1; $i -le $OldCount; $i++) {
        for ($j = 1; $j -le $NewCount; $j++) {
            if ($OldLines[$i - 1] -eq $NewLines[$j - 1]) {
                $LCS[$i][$j] = $LCS[$i - 1][$j - 1] + 1;
            } elseif ($LCS[$i - 1][$j] -ge $LCS[$i][$j - 1]) {
                $LCS[$i][$j] = $LCS[$i - 1][$j];
            } else {
                $LCS[$i][$j] = $LCS[$i][$j - 1];
            }
        }
    }

    # Backtrack through the LCS table; entries are collected in reverse order.
    $RawDiff = New-Object System.Collections.ArrayList;
    [int]$ri = $OldCount;
    [int]$rj = $NewCount;

    while ($ri -gt 0 -or $rj -gt 0) {
        if ($ri -gt 0 -and $rj -gt 0 -and $OldLines[$ri - 1] -eq $NewLines[$rj - 1]) {
            [void]$RawDiff.Add([PSCustomObject]@{ T = ' '; L = $OldLines[$ri - 1] });
            $ri--;
            $rj--;
        } elseif ($rj -gt 0 -and ($ri -eq 0 -or $LCS[$ri][$rj - 1] -ge $LCS[$ri - 1][$rj])) {
            [void]$RawDiff.Add([PSCustomObject]@{ T = '+'; L = $NewLines[$rj - 1] });
            $rj--;
        } else {
            [void]$RawDiff.Add([PSCustomObject]@{ T = '-'; L = $OldLines[$ri - 1] });
            $ri--;
        }
    }

    $RawDiff.Reverse();

    # Forward pass: assign 1-based old/new line numbers to every entry.
    $DiffEntries = New-Object System.Collections.ArrayList;
    [int]$OldNum = 0;
    [int]$NewNum = 0;

    foreach ($RawEntry in $RawDiff) {
        switch ($RawEntry.T) {
            ' ' { $OldNum++; $NewNum++; }
            '-' { $OldNum++; }
            '+' { $NewNum++; }
        }

        [int]$OldLineVal = 0;
        [int]$NewLineVal = 0;

        if ($RawEntry.T -ne '+') {
            $OldLineVal = $OldNum;
        }

        if ($RawEntry.T -ne '-') {
            $NewLineVal = $NewNum;
        }

        [void]$DiffEntries.Add([PSCustomObject]@{
            Type    = $RawEntry.T;
            Line    = $RawEntry.L;
            OldLine = $OldLineVal;
            NewLine = $NewLineVal;
        });
    }

    # Collect indices of changed (non-context) entries.
    [int]$ContextSize  = 3;
    [int]$TotalEntries = $DiffEntries.Count;
    $ChangeIdxList     = New-Object System.Collections.ArrayList;

    for ($idx = 0; $idx -lt $TotalEntries; $idx++) {
        if ($DiffEntries[$idx].Type -ne ' ') {
            [void]$ChangeIdxList.Add($idx);
        }
    }

    # Merge adjacent change positions into hunk ranges with context padding.
    $HunkRanges = New-Object System.Collections.ArrayList;
    [int]$HunkStart = [Math]::Max(0, [int]$ChangeIdxList[0] - $ContextSize);
    [int]$HunkEnd   = [Math]::Min($TotalEntries - 1, [int]$ChangeIdxList[0] + $ContextSize);

    for ($idx = 1; $idx -lt $ChangeIdxList.Count; $idx++) {
        [int]$CIdx          = [int]$ChangeIdxList[$idx];
        [int]$NextHunkStart = [Math]::Max(0, $CIdx - $ContextSize);

        if ($NextHunkStart -le $HunkEnd + 1) {
            $HunkEnd = [Math]::Min($TotalEntries - 1, $CIdx + $ContextSize);
        } else {
            [void]$HunkRanges.Add(@{ S = $HunkStart; E = $HunkEnd });
            $HunkStart = $NextHunkStart;
            $HunkEnd   = [Math]::Min($TotalEntries - 1, $CIdx + $ContextSize);
        }
    }
    [void]$HunkRanges.Add(@{ S = $HunkStart; E = $HunkEnd });

    # ANSI color codes; only embedded in output when -Colorized is set.
    [string]$Esc   = [char]27;
    [string]$Red   = "${Esc}[31m";
    [string]$Green = "${Esc}[32m";
    [string]$Cyan  = "${Esc}[36m";
    [string]$Reset = "${Esc}[0m";

    $OutputParts = New-Object System.Collections.ArrayList;

    if ($Colorized) {
        [void]$OutputParts.Add("${Red}--- old${Reset}");
        [void]$OutputParts.Add("${Green}+++ new${Reset}");
    } else {
        [void]$OutputParts.Add('--- old');
        [void]$OutputParts.Add('+++ new');
    }

    foreach ($Hunk in $HunkRanges) {
        [int]$OldStart     = 0;
        [int]$OldLineCount = 0;
        [int]$NewStart     = 0;
        [int]$NewLineCount = 0;
        [bool]$FirstOld    = $true;
        [bool]$FirstNew    = $true;

        for ($idx = [int]$Hunk.S; $idx -le [int]$Hunk.E; $idx++) {
            $HE = $DiffEntries[$idx];

            if ($HE.Type -eq ' ' -or $HE.Type -eq '-') {
                if ($FirstOld -and $HE.OldLine -gt 0) {
                    $OldStart = $HE.OldLine;
                    $FirstOld = $false;
                }
                $OldLineCount++;
            }

            if ($HE.Type -eq ' ' -or $HE.Type -eq '+') {
                if ($FirstNew -and $HE.NewLine -gt 0) {
                    $NewStart = $HE.NewLine;
                    $FirstNew = $false;
                }
                $NewLineCount++;
            }
        }

        [string]$HunkHeader = "@@ -${OldStart},${OldLineCount} +${NewStart},${NewLineCount} @@";

        if ($Colorized) {
            [void]$OutputParts.Add("${Cyan}${HunkHeader}${Reset}");
        } else {
            [void]$OutputParts.Add($HunkHeader);
        }

        for ($idx = [int]$Hunk.S; $idx -le [int]$Hunk.E; $idx++) {
            $DE = $DiffEntries[$idx];
            [string]$DiffLine = "$($DE.Type)$($DE.Line)";

            if ($Colorized) {
                switch ($DE.Type) {
                    '+' { [void]$OutputParts.Add("${Green}${DiffLine}${Reset}"); }
                    '-' { [void]$OutputParts.Add("${Red}${DiffLine}${Reset}"); }
                    default { [void]$OutputParts.Add($DiffLine); }
                }
            } else {
                [void]$OutputParts.Add($DiffLine);
            }
        }
    }

    return @{
        'ExitCode' = 1;
        'Output'   = ($OutputParts -join "`n");
    };
}

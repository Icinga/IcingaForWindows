<#
.SYNOPSIS
Split Nagios and Icinga binary plugin stdout into text output and performance data

.DESCRIPTION
Split-IcingaBinaryPluginOutput separates raw console output produced by an
external Nagios or Icinga plugin binary at the pipe delimiter ('|') according to
the Monitoring Plugins specification. Supports single-line and multi-line check
output as well as multi-line performance data blocks, while preserving quoted,
scoped and doubled-quote metric labels containing spaces (for example
"'C:\ Free Space'=50GB;20;10;0;100" or "check_disk::'C:\ Free Space'=12GB") as
individual elements in the returned PerformanceData array.

.PARAMETER RawOutput
| Name      | Type          | Description                                               | Default |
|-----------|---------------|-----------------------------------------------------------|---------|
| RawOutput | System.String | Raw stdout captured from an external binary or script.    | ''      |

.OUTPUTS
System.Collections.Hashtable -- Hashtable with keys Output (System.String) and
PerformanceData (System.Array of metric strings).

.EXAMPLE
PS> Split-IcingaBinaryPluginOutput -RawOutput "DISK OK - free space | 'C:\ Free'=50GB;20;10;0;100 inode=12%"

Splits the plugin output into its human-readable status message and two
individual performance-data metric strings.

.NOTES
Pure string parser with no external dependencies or side effects.
#>
function Split-IcingaBinaryPluginOutput()
{
    param (
        [string]$RawOutput = ''
    );

    if ([string]::IsNullOrWhiteSpace($RawOutput)) {
        return @{
            'Output'          = '';
            'PerformanceData' = @();
        };
    }

    # Normalize CRLF/CR line endings so single-line and multi-line Nagios/Icinga outputs parse identically
    [string]$Normalized       = ($RawOutput -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n");
    [array]$Lines             = $Normalized -split "`n";
    [array]$OutputLines       = @();
    [array]$PerfChunks        = @();
    [bool]$InTrailingPerfMode = $false;

    # Split status output from performance data at '|':
    # - Line 0: 'STATUS OK - message | perf1 perf2'
    # - Subsequent lines: additional human-readable output until a trailing '| perf...' block begins
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        [string]$CurrentLine = $Lines[$i];
        [int]$PipeIndex      = $CurrentLine.IndexOf('|');

        if ($PipeIndex -ge 0) {
            [string]$TextPart = $CurrentLine.Substring(0, $PipeIndex).TrimEnd();
            [string]$PerfPart = $CurrentLine.Substring($PipeIndex + 1).Trim();

            if ($i -eq 0 -or $TextPart.Length -gt 0) {
                $OutputLines += $TextPart;
            }

            if ($PerfPart.Length -gt 0) {
                $PerfChunks += $PerfPart;
            }

            if ($i -gt 0) {
                $InTrailingPerfMode = $true;
            }
        } elseif ($InTrailingPerfMode -and $CurrentLine -match '=') {
            # Continuation lines of a multi-line performance-data block
            $PerfChunks += $CurrentLine.Trim();
        } else {
            $OutputLines += $CurrentLine.TrimEnd();
        }
    }

    [string]$CombinedPerf = ($PerfChunks -join ' ').Trim();
    [array]$PerfMetrics   = @();

    if ($CombinedPerf.Length -gt 0) {
        # Tokenize space-separated metrics while keeping single/double-quoted labels, scoped labels
        # (check_disk::'C:\ Free Space'=12GB) and doubled quotes ('Label''s Space'=10%) intact as one token
        $MetricMatches = [regex]::Matches($CombinedPerf, '(?:''[^'']*''|"[^"]*"|\S)+');
        foreach ($MetricMatch in $MetricMatches) {
            if (-not [string]::IsNullOrWhiteSpace($MetricMatch.Value)) {
                $PerfMetrics += [string]$MetricMatch.Value;
            }
        }
    }

    return @{
        'Output'          = ($OutputLines -join "`n").Trim();
        'PerformanceData' = $PerfMetrics;
    };
}

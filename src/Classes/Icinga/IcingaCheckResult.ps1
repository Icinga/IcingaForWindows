<#
.SYNOPSIS
Immutable result of a compiled Icinga plugin run

.DESCRIPTION
IcingaCheckResult is the value object produced by IcingaPlugin.Compile(). It
carries the three artefacts a monitoring backend needs: the numeric Icinga plugin
exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN), the rendered multi-line plugin
output and the collected performance-data metrics as a flat array of strings.

Compile() stores an instance of this class in the thread-local runtime state at
$Global:IcingaForWindows.Private.Icinga.CheckResult so that a background daemon or
the REST API can read the result of a check that was executed in a worker thread,
instead of the output being written to the console.

.OUTPUTS
IcingaCheckResult -- Result container exposing ExitCode, Output and PerformanceData.

.EXAMPLE
PS> [IcingaCheckResult]::new(2, '[CRITICAL] Load: 95%', @("load=95%;80;90;0;100"))

.NOTES
Plain data container; performs no evaluation itself. Safe to construct in
multi-threaded runspaces.
#>
class IcingaCheckResult
{
    [int]$ExitCode          = 0;
    [string]$Output         = '';
    [array]$PerformanceData = @();

    <#
    .SYNOPSIS
    Create an empty check result

    .DESCRIPTION
    Creates a result with an OK exit code, an empty output and no performance data.
    Used as the initial, not-yet-compiled placeholder.

    .OUTPUTS
    IcingaCheckResult -- Empty result instance.

    .EXAMPLE
    PS> [IcingaCheckResult]::new()

    .NOTES
    Values are meant to be replaced by a later Compile() run.
    #>
    IcingaCheckResult()
    {
    }

    <#
    .SYNOPSIS
    Create a check result from a compiled plugin

    .DESCRIPTION
    Stores the numeric Icinga exit code, the rendered plugin output and the
    collected performance-data metrics.

    .PARAMETER ExitCode
    | Name     | Type         | Description                                                  | Default |
    |----------|--------------|--------------------------------------------------------------|---------|
    | ExitCode | System.Int32 | Icinga plugin state: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN. |         |

    .PARAMETER Output
    | Name   | Type          | Description                                     | Default |
    |--------|---------------|-------------------------------------------------|---------|
    | Output | System.String | Rendered, possibly multi-line, plugin output.   |         |

    .PARAMETER PerformanceData
    | Name            | Type           | Description                                      | Default |
    |-----------------|----------------|--------------------------------------------------|---------|
    | PerformanceData | System.Array   | Performance-data metrics, one string per metric. |         |

    .OUTPUTS
    IcingaCheckResult -- Configured result instance.

    .EXAMPLE
    PS> [IcingaCheckResult]::new(0, '[OK] Load: 5%', @("load=5%;80;90;0;100"))

    .NOTES
    Does not modify global state; the caller decides where to store the instance.
    #>
    IcingaCheckResult([int]$ExitCode, [string]$Output, [array]$PerformanceData)
    {
        $this.ExitCode        = $ExitCode;
        $this.Output          = $Output;
        $this.PerformanceData = $PerformanceData;
    }

    <#
    .SYNOPSIS
    Return the rendered plugin output

    .DESCRIPTION
    Returns the Output message so the result renders as its plugin output when used
    in string context.

    .OUTPUTS
    System.String -- The Output message.

    .EXAMPLE
    PS> $result.ToString()

    .NOTES
    Internal formatting helper.
    #>
    [string] ToString()
    {
        return $this.Output;
    }
}

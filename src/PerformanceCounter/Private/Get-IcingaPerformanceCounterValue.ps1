<#
.SYNOPSIS
Return the value of a performance counter result, or its error when one is present

.DESCRIPTION
`Get-IcingaPerformanceCounterValue` extracts the usable result from a single performance counter value
object (the leaf hashtable produced by `Get-IcingaPerformanceCounter`, containing the keys value,
sample, help, type and error). If the counter reported an error the error message is returned;
otherwise the numeric value is returned. This lets a plugin drill down to a single counter and get
back either a number to threshold against or the error text to surface, in one call.

Because the value is always numeric and the error is always a string, callers can tell the two apart
with a simple type check (`$result -is [string]` means an error was returned).

.PARAMETER InputObject
| Name        | Type          | Description                                                          | Default |
|-------------|---------------|----------------------------------------------------------------------|---------|
| InputObject | System.Object | A single counter value object (the leaf hashtable of a counter read). | $null   |

.OUTPUTS
System.Object — The counter value (typically System.Decimal), or the error message (System.String)
when the counter reported one. Returns $null when the input is not a counter value object.

.EXAMPLE
PS> $data = Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time' -StructureByInstance
PS> Get-IcingaPerformanceCounterValue -InputObject $data.'0'.'Processor'.'% Processor Time'

Returns the processor load of core 0, or the error text if that counter could not be read.

.NOTES
Pure helper; reads no global state and touches no counters. Intended for use by plugins after they
have selected a single counter from a `Get-IcingaPerformanceCounter` result.
#>
function Get-IcingaPerformanceCounterValue()
{
    param (
        $InputObject = $null
    );

    if ($null -eq $InputObject -or $InputObject -isnot [hashtable]) {
        return $null;
    }

    # An error always wins over the value so problems are never hidden behind a default 0.
    if (-not [string]::IsNullOrEmpty([string]$InputObject['error'])) {
        return $InputObject['error'];
    }

    return $InputObject['value'];
}

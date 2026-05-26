<#
.SYNOPSIS
Returns the current Unix time (epoch) from the local system in UTC.

.DESCRIPTION
Get-IcingaUnixTime returns the number of seconds (or, when requested, milliseconds) elapsed since the Unix epoch (1970-01-01T00:00:00Z).
The function obtains the current time in UTC and converts it to a numeric Unix timestamp.

.PARAMETER Milliseconds
| Name         | Type                                         | Description                                                          | Default |
|--------------|----------------------------------------------|----------------------------------------------------------------------|---------|
| Milliseconds | System.Management.Automation.SwitchParameter | When set, returns Unix time in milliseconds (Int64) instead of seconds (Int32). | $false |

.EXAMPLE
PS> Get-IcingaUnixTime
1609459200

Returns the current Unix time in seconds (int).

.EXAMPLE
PS> Get-IcingaUnixTime -Milliseconds
1609459200000

Intended to return the current Unix time in milliseconds (int64).

.OUTPUTS
System.Int32 — Unix time in seconds when called without -Milliseconds.
System.Int64 — Unix time in milliseconds when called with -Milliseconds.

.NOTES
The timestamp is calculated using UTC to represent the standard Unix epoch (1970-01-01T00:00:00Z).
Without -Milliseconds the function returns a System.Int32 via Get-Date -UFormat %s.
With -Milliseconds the function divides TotalMilliseconds by 1000 and casts to Int64;
callers requiring sub-second precision should verify the returned value before use.

#>
function Get-IcingaUnixTime()
{
    param (
        [switch]$Milliseconds = $FALSE
    );

    # Return the current Unix time in milliseconds
    if ($Milliseconds) {
        return ([int64](([DateTime]::UtcNow) - (Get-Date '1/1/1970')).TotalMilliseconds / 1000);
    }

    # Return the current Unix time in seconds
    return [int][double]::Parse(
        (Get-Date -UFormat %s -Date (Get-Date).ToUniversalTime())
    );
}

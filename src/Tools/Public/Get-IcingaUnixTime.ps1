<#
.SYNOPSIS
Return the current Unix epoch timestamp in UTC

.DESCRIPTION
Get-IcingaUnixTime returns the current UTC Unix timestamp relative to
1970-01-01T00:00:00Z using DateTimeOffset.UtcNow so local system timezones or
culture formats never skew the result. Without -Milliseconds it returns whole
seconds as an Int32; with -Milliseconds it returns fractional seconds with
millisecond precision as a Double, matching the timestamp format expected by
Icinga 2 check result payloads (execution_start and execution_end).

.PARAMETER Milliseconds
| Name         | Type                                         | Description                                                                    | Default |
|--------------|----------------------------------------------|--------------------------------------------------------------------------------|---------|
| Milliseconds | System.Management.Automation.SwitchParameter | When set, returns fractional Unix seconds with millisecond precision (Double). | $false  |

.OUTPUTS
System.ValueType -- System.Int32 whole Unix seconds by default, or System.Double
fractional Unix seconds when -Milliseconds is set.

.EXAMPLE
PS> Get-IcingaUnixTime
1731750000

Returns the current UTC Unix time in whole seconds.

.EXAMPLE
PS> Get-IcingaUnixTime -Milliseconds
1731750000.123

Returns the current UTC Unix time in seconds with millisecond precision.

.NOTES
Uses System.DateTimeOffset.UtcNow across Windows PowerShell 5.1 and PowerShell 7+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-IcingaUnixTime()
{
    param (
        [switch]$Milliseconds = $false
    );

    if ($Milliseconds) {
        return [double]([System.DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0);
    }

    return [int][System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds();
}

<#
.SYNOPSIS
Return seconds since the thread was last seen (heartbeat).

.DESCRIPTION
`Get-ThreadLastSeen` reads a thread's `LastSeen` timestamp from the global
thread registry and returns the elapsed seconds (rounded) since that timestamp.
If the thread or timestamp is missing, `$null` is returned.

.PARAMETER ThreadId
| Name     | Type          | Description                                         | Default        |
|----------|---------------|-----------------------------------------------------|----------------|
| ThreadId | System.String | The thread id to query. Defaults to current thread. | (Get-ThreadId) |

.OUTPUTS
System.Double -- Seconds since the last heartbeat, or $null if the thread is unknown.

.EXAMPLE
PS> Get-ThreadLastSeen -ThreadId $tid

.NOTES
Used by health checks and thread state transitions in the housekeeper.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-ThreadLastSeen()
{
    param (
        [string]$ThreadId = (Get-ThreadId)
    );

    # Return null if no ThreadId is provided
    if ([string]::IsNullOrEmpty($ThreadId)) {
        return $null;
    }

    $ThreadObj = (Get-GlobalRuntimeVariable).Public.Threading.Threads.$threadId;

    if ($null -ne $ThreadObj.Stopwatch) {
        return ([Math]::Round($ThreadObj.Stopwatch.Elapsed.TotalSeconds, 2));
    }

    # Fallback to LastSeen timestamp if no Stopwatch is present
    $LastSeen = $ThreadObj.LastSeen;

    # If LastSeen is null, return null
    if ($null -eq $LastSeen) {
        return $null;
    }

    # Get the time difference in seconds
    $TimeDiff = (Get-Date) - $LastSeen;

    # Return the total seconds since last seen
    return ([Math]::Round($TimeDiff.TotalSeconds, 2));
}

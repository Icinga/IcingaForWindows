<#
.SYNOPSIS
Mark a thread as FROZEN if it appears unresponsive.

.DESCRIPTION
`Set-ThreadFrozen` checks the last-seen timestamp for a given thread and, if
it exceeds the configured keep-alive threshold, sets the thread state to
`FROZEN` and emits a warning log entry.

.PARAMETER ThreadId
| Name     | Type          | Description                                           | Default        |
|----------|---------------|-------------------------------------------------------|----------------|
| ThreadId | System.String | The thread id to inspect. Defaults to current thread. | (Get-ThreadId) |

.OUTPUTS
None -- Updates the thread state in the global registry and emits a warning log entry when frozen.

.EXAMPLE
PS> Set-ThreadFrozen -ThreadId $tid

.NOTES
This helper is used by the housekeeper loop to detect and flag unresponsive threads.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Set-ThreadFrozen()
{
    param (
        [string]$ThreadId = (Get-ThreadId)
    );

    # Check if the thread ID is valid
    if ([string]::IsNullOrEmpty($ThreadId)) {
        return;
    }

    # First check if the thread is keept alive and we should keep an eye on it
    if (-not (Get-GlobalRuntimeVariable).Public.Threading.Threads.$threadId.KeepAlive) {
        # If the thread is not marked as KeepAlive, we skip monitoring it
        return;
    }

    # Check last seen timestamp to determine if the thread is still alive
    $LastSeenInSeconds = Get-ThreadLastSeen -ThreadId $threadId;

    if ($null -ne $LastSeenInSeconds -And $LastSeenInSeconds -gt (Get-GlobalRuntimeVariable).Public.Threading.KeepAlive) {
        # If the thread has not been seen for more than the threshold seconds, mark it as FROZEN
        Write-LoggingEntry -Message 'Housekeeper: Detected unresponsive thread, marking as FROZEN' -Level 'Warning' -Data @{ 'ThreadId' = $ThreadId };
        (Get-GlobalRuntimeVariable).Public.Threading.Threads.$ThreadId.State = 'FROZEN';
    }
}

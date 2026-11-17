<#
.SYNOPSIS
Mark the current thread as processing and refresh its heartbeat.

.DESCRIPTION
`Set-ThreadProcessing` updates the current thread's state to `PROCESSING`
and records the current timestamp in `LastSeen` to indicate activity.

.OUTPUTS
None -- Modifies `(Get-GlobalRuntimeVariable).Public.Threading.Threads` for the current thread.

.EXAMPLE
PS> Set-ThreadProcessing

.NOTES
Typically called by worker loops when they start handling a job.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Set-ThreadProcessing()
{
    # Get the current thread ID
    $ThreadId = Get-ThreadId;

    if ([string]::IsNullOrEmpty($ThreadId)) {
        return;
    }

    # Set the thread state to PROCESSING
    (Get-GlobalRuntimeVariable).Public.Threading.Threads.$ThreadId.State    = 'PROCESSING';
    # Update the last seen timestamp to now
    (Get-GlobalRuntimeVariable).Public.Threading.Threads.$ThreadId.LastSeen = (Get-Date);
}

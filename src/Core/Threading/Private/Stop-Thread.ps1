<#
.SYNOPSIS
Request termination for a registered thread.

.DESCRIPTION
`Stop-Thread` marks a thread's state as `TERMINATED` in the global thread
registry. It validates the provided thread id and returns structured results
using `Write-FunctionReturnValue` when errors occur.

.PARAMETER ThreadId
| Name     | Type          | Description                  | Default |
|----------|---------------|------------------------------|---------|
| ThreadId | System.String | The id of the thread to stop | $null   |

.OUTPUTS
System.Management.Automation.PSCustomObject -- Strukturierter Rueckgabewert bei Fehler (via Write-FunctionReturnValue); None bei Erfolg.

.EXAMPLE
PS> Stop-Thread -ThreadId $tid

.NOTES
The actual runspace shutdown and cleanup is handled by the housekeeper loop.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Stop-Thread()
{
    param (
        [string]$ThreadId = $null
    );

    # Stops a specified Thread by setting its state to TERMINATED

    # Validate the ThreadId parameter
    if ([string]::IsNullOrEmpty($ThreadId)) {
        return (Write-FunctionReturnValue -ReturnValue 'ThreadIdEmpty');
    }

    # Check if the specified thread exists
    if ($null -eq (Get-GlobalRuntimeVariable).Public.Threading.Threads.$ThreadId) {
        return (Write-FunctionReturnValue -ReturnValue 'ThreadNotFound' -Data @{ 'ThreadId' = $ThreadId });
    }

    # Set the thread state to TERMINATED
    (Get-GlobalRuntimeVariable).Public.Threading.Threads.$ThreadId.State  = 'TERMINATED';
}

<#
.SYNOPSIS
Forcibly terminate the current PowerShell process used by Icinga

.DESCRIPTION
`Exit-Icinga` stops the current PowerShell process immediately to avoid the
shell freezing due to background threads that do not terminate on a normal
exit.

.PARAMETER ExitCode
| Name     | Type         | Description                 | Default |
|----------|--------------|-----------------------------|---------|
| ExitCode | System.Int32 | Process exit code to return | 0       |

.OUTPUTS
None -- The process is terminated immediately; no value is returned.

.EXAMPLE
PS> Exit-Icinga

.NOTES
Uses `[System.Environment]::Exit($ExitCode)` to ensure the process exits cleanly with the desired exit code.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Exit-Icinga()
{
    param (
        [int]$ExitCode = 0
    );

    # Ensures we close the current PowerShell by forcing its termination
    # This is required as a simple "exit" would cause the shell to freeze,
    # waiting for the background threads to stop (which they won't)
    [System.Environment]::Exit($ExitCode);
}

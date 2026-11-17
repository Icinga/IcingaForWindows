<#
.SYNOPSIS
Set the global logging level for this module.

.DESCRIPTION
`Set-LoggingLogLevel` updates the runtime logging level in the global
runtime variable so subsequent log writes follow the desired verbosity.

.PARAMETER Level
| Name  | Type          | Description                                                       | Default |
|-------|---------------|-------------------------------------------------------------------|---------|
| Level | System.String | One of 'Debug','Audit','Info','Success','Warning','Error','Fatal' | 'Info'  |

.OUTPUTS
None -- Updates `(Get-GlobalRuntimeVariable).Public.Logging.Level`.

.EXAMPLE
PS> Set-LoggingLogLevel -Level 'Debug'

.NOTES
Use `Test-LoggingWriteLog` to determine whether a message at a given level will be emitted.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Set-LoggingLogLevel()
{
    param (
        [ValidateSet('Debug', 'Audit', 'Info', 'Success', 'Warning', 'Error', 'Fatal')]
        [string]$Level = 'Info'
    );

    (Get-GlobalRuntimeVariable).Public.Logging.Level = $Level;
}

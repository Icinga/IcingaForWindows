<#
.SYNOPSIS
Set the global logging level for Icinga

.DESCRIPTION
`Set-IcingaLogLevel` updates the module-wide logging threshold stored in
`$Global:Icinga.Public.Logging.Level`. The logging subsystem uses this value
to decide which messages should be enqueued and processed. Use one of the
predefined levels to control verbosity.

.PARAMETER Level
| Name  | Type          | Description                   | Default |
|-------|---------------|-------------------------------|---------|
| Level | System.String | Desired minimum logging level | 'Info'  |

.OUTPUTS
None -- This function sets a global variable and does not emit pipeline output.

.EXAMPLE
PS> Set-IcingaLogLevel -Level 'Warning'

.NOTES
Valid levels are `Debug`, `Audit`, `Info`, `Success`, `Warning`, `Error` and `Fatal`.
`Test-LoggingWriteLog` consults the global level to decide whether a message
at a given severity should be emitted.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Set-IcingaLogLevel()
{
    param (
        [ValidateSet('Debug', 'Audit', 'Info', 'Success', 'Warning', 'Error', 'Fatal')]
        [string]$Level = 'Info'
    );

    # Wrapper function to make the base functions private and easy replaceable
    Set-LoggingLogLevel -Level $Level;
}

<#
.SYNOPSIS
Return a formatted representation for null values in console output.

.DESCRIPTION
`Format-LoggingConsoleNullValue` returns a short, colored string representation
for null values used throughout logging output formatting helpers.

.PARAMETER Indent
| Name   | Type          | Description                                         | Default |
|--------|---------------|-----------------------------------------------------|---------|
| Indent | System.String | Optional prefix indentation for the returned string | ''      |

.OUTPUTS
System.String -- A one-line formatted representation of a null value.

.EXAMPLE
PS> Format-LoggingConsoleNullValue -Indent '  '

.NOTES
Used by multiple formatting helpers to ensure consistent null rendering.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Format-LoggingConsoleNullValue()
{
    param (
        [string]$Indent = ''
    );

    return (
        [string]::Format('{0} [Green]NULL[/Green]', $Indent)
    );
}

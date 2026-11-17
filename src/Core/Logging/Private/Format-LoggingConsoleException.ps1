<#
.SYNOPSIS
Format an exception object for console output.

.DESCRIPTION
`Format-LoggingConsoleException` returns a formatted representation of an exception
using `Format-LoggingConsoleObjectProperties` and a predefined set of properties.

.PARAMETER Exception
| Name      | Type             | Description             | Default |
|-----------|------------------|-------------------------|---------|
| Exception | System.Exception | The exception to format |         |

.PARAMETER Indent
| Name   | Type          | Description                                       | Default |
|--------|---------------|---------------------------------------------------|---------|
| Indent | System.String | Optional indentation string for nested formatting | ''      |

.OUTPUTS
System.String -- A formatted multiline string describing the exception.

.EXAMPLE
PS> Format-LoggingConsoleException -Exception $ex -Indent '  '

.NOTES
Uses `Format-LoggingConsoleObjectProperties` to extract common exception details.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Format-LoggingConsoleException()
{
    param (
        $Exception      = $null,
        [string]$Indent = ''
    );

    # If the exception is null, return the formatted null value
    if ($null -eq $Exception) {
        return (Format-LoggingConsoleNullValue -Indent $Indent);
    }

    return (
        Format-LoggingConsoleObjectProperties `
            -Object $Exception `
            -Properties @('Message', 'ErrorRecord.FullyQualifiedErrorId', 'InnerException.Message', 'InnerException.InnerException', 'WasThrownFromThrowStatement', 'Response.StatusCode.value__', 'Response.StatusDescription') `
            -Indent $Indent
    );
}

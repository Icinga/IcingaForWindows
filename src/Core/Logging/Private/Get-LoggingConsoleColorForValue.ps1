<#
.SYNOPSIS
Return the console color name for an arbitrary value.

.DESCRIPTION
`Get-LoggingConsoleColorForValue` inspects the input value and returns an
appropriate `System.ConsoleColor` name by delegating to
`Get-LoggingConsoleColorForObjectType` with the value's CLR type name.

.PARAMETER Value
| Name  | Type          | Description                     | Default |
|-------|---------------|---------------------------------|---------|
| Value | System.Object | The value to choose a color for |         |

.OUTPUTS
System.String -- The chosen console color name.

.EXAMPLE
PS> Get-LoggingConsoleColorForValue -Value 42

.NOTES
Returns a special color for `$null` values.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-LoggingConsoleColorForValue()
{
    param(
        $Value = $null
    );

    # If our value is null, return the null value color
    if ($null -eq $Value) {
        return (Get-LoggingConsoleColorForObjectType -IsNullValue);
    }

    # Return the color based on the object's type name
    return (Get-LoggingConsoleColorForObjectType -ObjectName $Value.GetType().Name);
}

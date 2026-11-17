<#
.SYNOPSIS
Select a console color name for a given object type or parameter.

.DESCRIPTION
`Get-LoggingConsoleColorForObjectType` returns a string matching a
`System.ConsoleColor` name appropriate for the provided object name or
for special cases like parameters and null values.

.PARAMETER ObjectName
| Name       | Type          | Description                                    | Default |
|------------|---------------|------------------------------------------------|---------|
| ObjectName | System.String | The CLR type name or friendly name to evaluate |         |

.PARAMETER IsParameter
| Name        | Type                   | Description                                         | Default |
|-------------|------------------------|-----------------------------------------------------|---------|
| IsParameter | System.SwitchParameter | When set returns the color used for parameter names | $false  |

.PARAMETER IsNullValue
| Name        | Type                   | Description                                     | Default |
|-------------|------------------------|-------------------------------------------------|---------|
| IsNullValue | System.SwitchParameter | When set returns the color used for null values | $false  |

.OUTPUTS
System.String -- The name of a `System.ConsoleColor` value.

.EXAMPLE
PS> Get-LoggingConsoleColorForObjectType -ObjectName 'String'

.NOTES
Color choices are mapped to common CLR type names and special flags.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-LoggingConsoleColorForObjectType()
{
    param(
        [string]$ObjectName  = $null,
        [switch]$IsParameter = $false,
        [switch]$IsNullValue = $false
    );

    # If this is a parameter, always return dark gray
    if ($IsParameter) {
        return 'DarkGray';
    }

    # Return dark gray for null values
    if ($IsNullValue) {
        return 'Green';
    }

    # Return gray for null or empty of the object name
    if ([string]::IsNullOrEmpty($ObjectName)) {
        return 'Gray';
    }

    # Determine color based on object type
    switch ($ObjectName.ToLower()) {
        'string' {
            # Strings are shown in dark cyan
            return 'DarkCyan';
        };
        default {
            # Check for all numeric types and return white
            if ($ObjectName -in @('Int32', 'Int64', 'Double', 'Decimal', 'Single', 'Byte', 'UInt32', 'UInt64')) {
                return 'White';
            } else {
                # All other types are shown in green, for example True or custom objects
                return 'Green';
            }
        };
    }

    # Fallback color, shouldn't be reached anyway
    return 'Gray';
}

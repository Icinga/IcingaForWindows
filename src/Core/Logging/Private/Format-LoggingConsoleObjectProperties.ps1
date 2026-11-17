<#
.SYNOPSIS
Format selected properties of an object for console logging.

.DESCRIPTION
`Format-LoggingConsoleObjectProperties` extracts named properties (including nested)
from an object and returns a colorized string suitable for console logging.

.PARAMETER Object
| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Object | System.Object | The input object to inspect |         |

.PARAMETER Properties
| Name       | Type         | Description                                               | Default |
|------------|--------------|-----------------------------------------------------------|---------|
| Properties | System.Array | List of property paths to extract (e.g. 'Client.Address') | @()     |

.PARAMETER Indent
| Name   | Type          | Description                                | Default |
|--------|---------------|--------------------------------------------|---------|
| Indent | System.String | Indentation prefix for each formatted line | ''      |

.OUTPUTS
System.String -- A multi-line formatted string with property:value pairs.

.EXAMPLE
PS> Format-LoggingConsoleObjectProperties -Object $resp -Properties @('Status','Body')

.NOTES
Relies on `Get-LoggingConsoleNestedProperty`, `Get-LoggingConsoleColorForObjectType`,
and `Get-LoggingConsoleColorForValue` for nested access and color selection.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Format-LoggingConsoleObjectProperties()
{
    param (
        $Object            = $null,
        [array]$Properties = @(),
        [string]$Indent    = ''
    )

    $StringBuilder = New-Object System.Text.StringBuilder

    foreach ($prop in $Properties) {
        # Resolve nested property like 'Client.Address'
        $value = Get-LoggingConsoleNestedProperty -InputObject $Object -PropertyPath $prop

        # Skip if property cannot be resolved at all
        if ($null -eq $value -and $prop -notin $Object.PSObject.Properties.Name) {
            continue
        }

        # Get colors for key and value
        $keyColor   = Get-LoggingConsoleColorForObjectType -IsParameter
        $valueColor = Get-LoggingConsoleColorForValue -Value $value

        # Append the formatted line to the string builder
        $StringBuilder.AppendLine(
            [string]::Format(
                '{0} [{1}]{2}[/{1}]: [{3}]{4}[/{3}]',
                $Indent,
                $keyColor,
                $prop,
                $valueColor,
                $value
            )
        ) | Out-Null;
    }

    # Return the built string
    return $StringBuilder.ToString();
}

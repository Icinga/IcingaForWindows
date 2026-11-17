<#
.SYNOPSIS
Resolve a nested property path on an object safely.

.DESCRIPTION
`Get-LoggingConsoleNestedProperty` walks a dot-separated property path (for example
'Client.Address') on an input object and returns the resolved value or `$null` if
any segment cannot be resolved.

.PARAMETER InputObject
| Name        | Type          | Description         | Default |
|-------------|---------------|---------------------|---------|
| InputObject | System.Object | The object to query |         |

.PARAMETER PropertyPath
| Name         | Type          | Description                            | Default |
|--------------|---------------|----------------------------------------|---------|
| PropertyPath | System.String | Dot-separated property path to resolve |         |

.OUTPUTS
System.Object -- The resolved property value or `$null` when not found.

.EXAMPLE
PS> Get-LoggingConsoleNestedProperty -InputObject $resp -PropertyPath 'Client.Address'

.NOTES
This helper intentionally swallows property access errors and returns `$null` on failure.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-LoggingConsoleNestedProperty()
{
    param(
        $InputObject          = $null,
        [string]$PropertyPath = $null
    );

    # If the input object or property path is null/empty, return null
    if ($null -eq $InputObject -or [string]::IsNullOrEmpty($PropertyPath)) {
        return $null;
    }

    # Simple case: no dot -> normal property access
    if ($PropertyPath -notlike '*.*') {
        try {
            return $InputObject.$PropertyPath;
        } catch {
            return $null;
        }
    }

    # Split on dots and walk the object graph
    $CurrentObject = $InputObject;
    $Segments      = $PropertyPath.Split('.');

    # Walk through each segment and access the property, updating the current object
    foreach ($segment in $Segments) {
        if ($null -eq $CurrentObject) {
            return $null;
        }

        try {
            $CurrentObject = $CurrentObject.$segment;
        } catch {
            return $null;
        }
    }

    # Return the final resolved object
    return $CurrentObject;
}

<#
.SYNOPSIS
Test a value against include and exclude wildcard lists

.DESCRIPTION
Test-IcingaArrayFilter decides whether a value passes the usual plugin filters
-Include and -Exclude, without any script block. Both lists hold wildcard
patterns ('*', '?', '[a-z]') that are compared case-insensitively against the
value converted to a string. An exclude match always wins; with an empty include
list every value that is not excluded passes, otherwise at least one include
pattern has to match.

A single value returns a boolean. An array returns a new array with every
element that passes, so a whole list can be filtered in one call. An invalid
wildcard pattern is logged through Write-FunctionReturnValue
(ArrayFilterInvalidPattern) and the value is treated as not matching that
pattern.

.PARAMETER InputObject
| Name        | Type          | Description                         | Default |
|-------------|---------------|-------------------------------------|---------|
| InputObject | System.Object | Value, or array of values, to test. | $null   |

.PARAMETER Include
| Name    | Type         | Description                                           | Default |
|---------|--------------|-------------------------------------------------------|---------|
| Include | System.Array | Wildcard patterns of which at least one has to match. | @()     |

.PARAMETER Exclude
| Name    | Type         | Description                                | Default |
|---------|--------------|--------------------------------------------|---------|
| Exclude | System.Array | Wildcard patterns of which none may match. | @()     |

.OUTPUTS
System.Boolean -- For a single value, whether it passes the filters.
System.Object[] -- For an array, the elements that pass the filters.

.EXAMPLE
PS> Test-IcingaArrayFilter -InputObject 'Spooler' -Include 'Spo*' -Exclude 'WinRM'

Returns $true.

.EXAMPLE
PS> Test-IcingaArrayFilter -InputObject @('C', 'D', 'E') -Exclude 'D'

Returns the array @('C', 'E').

.NOTES
No external dependencies. A $null value never passes. Used by the plugins for
their -Include/-Exclude parameters, which must not rely on script blocks so the
plugins stay usable in JEA sessions.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Test-IcingaArrayFilter()
{
    param (
        [object]$InputObject = $null,
        [array]$Include      = @(),
        [array]$Exclude      = @()
    );

    if ($InputObject -is [array]) {
        [array]$Filtered = @();

        foreach ($Entry in $InputObject) {
            if (Test-IcingaArrayFilter -InputObject $Entry -Include $Include -Exclude $Exclude) {
                $Filtered += $Entry;
            }
        }

        return ,$Filtered;
    }

    if ($null -eq $InputObject) {
        return $false;
    }

    [string]$Value = [string]$InputObject;

    foreach ($Pattern in $Exclude) {
        if (Test-ModuleWildcardMatch -Value $Value -Pattern ([string]$Pattern)) {
            return $false;
        }
    }

    if ($Include.Count -eq 0) {
        return $true;
    }

    foreach ($Pattern in $Include) {
        if (Test-ModuleWildcardMatch -Value $Value -Pattern ([string]$Pattern)) {
            return $true;
        }
    }

    return $false;
}

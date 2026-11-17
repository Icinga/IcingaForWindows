<#
.SYNOPSIS
Test a string against a single wildcard pattern without throwing

.DESCRIPTION
Compares the value case-insensitively with a wildcard pattern ('*', '?',
'[a-z]'). An invalid pattern, such as an unclosed '[', is logged through
Write-FunctionReturnValue (ArrayFilterInvalidPattern) and counts as no match, so
a broken filter argument never aborts a plugin.

.PARAMETER Value
| Name  | Type          | Description        | Default |
|-------|---------------|--------------------|---------|
| Value | System.String | The value to test. |         |

.PARAMETER Pattern
| Name    | Type          | Description                | Default |
|---------|---------------|----------------------------|---------|
| Pattern | System.String | Wildcard pattern to match. |         |

.OUTPUTS
System.Boolean -- True when the value matches the pattern.

.EXAMPLE
PS> Test-ModuleWildcardMatch -Value 'Spooler' -Pattern 'spo*'

Returns $true.

.NOTES
Internal helper of Test-IcingaArrayFilter.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Test-ModuleWildcardMatch()
{
    param (
        [string]$Value   = '',
        [string]$Pattern = ''
    );

    try {
        return ($Value -like $Pattern);
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'ArrayFilterInvalidPattern' -Data @{ 'Value' = $Value; 'Pattern' = $Pattern; 'Error' = $_.Exception.Message; } -OverrideReturn $false);
    }
}

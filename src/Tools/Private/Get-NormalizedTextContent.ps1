<#
.SYNOPSIS
Normalize a string by re-serializing it when it contains valid JSON

.DESCRIPTION
Get-NormalizedTextContent attempts to parse the input string as JSON via
ConvertFrom-Json. When parsing succeeds the object is immediately re-serialized
with ConvertTo-Json at depth 20, producing a consistently formatted JSON string
free of whitespace artifacts. When parsing fails the original string is returned
unchanged, making this function safe to call on plain-text content. A null or
empty input returns an empty string without attempting any conversion.

.PARAMETER Content
| Name    | Type          | Description              | Default |
|---------|---------------|--------------------------|---------|
| Content | System.String | The string to normalize. | $null   |

.OUTPUTS
System.String -- Re-serialized JSON string when the input is valid JSON, the
original input string when it is not, or an empty string for null or empty input.

.EXAMPLE
PS> Get-NormalizedTextContent -Content '{"b":2,"a":1}'

Returns the JSON re-serialized with ConvertTo-Json formatting.

.NOTES
Used by Compare-IcingaTextContent to ensure both sides of a diff use identical
formatting before line-level comparison. Relies only on ConvertFrom-Json and
ConvertTo-Json from the PowerShell standard library; no external dependencies.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-NormalizedTextContent()
{
    param (
        [string]$Content = $null
    );

    if ([string]::IsNullOrEmpty($Content)) {
        return '';
    }

    try {
        # Attempt JSON normalization; return the original string when the input is
        # not valid JSON so that plain-text inputs pass through unchanged.
        $Parsed = ConvertFrom-ModuleJson -InputObject $Content;

        # If the function returns $null, simply return the content
        if ($null -eq $Parsed) {
            return $Content;
        }

        return (ConvertTo-Json -InputObject $Parsed -Depth 20);
    } catch {
        return $Content;
    }
}

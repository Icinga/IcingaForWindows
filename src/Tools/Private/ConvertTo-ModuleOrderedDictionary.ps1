<#
.SYNOPSIS
Convert a dictionary or object into a case-sensitive OrderedDictionary

.DESCRIPTION
ConvertTo-ModuleOrderedDictionary normalizes any IDictionary (Hashtable,
Dictionary[string, object], OrderedDictionary) or PSCustomObject into a
System.Collections.Specialized.OrderedDictionary configured with
StringComparer.Ordinal so key order and case-distinct CLI flags (such as '-p'
and '-P') are preserved across Windows PowerShell 5.1 and PowerShell 7+. When
SkipEmptyKeys is enabled, null, empty and whitespace-only keys (such as Icinga
placeholder macros) are omitted.

.PARAMETER InputObject
| Name        | Type          | Description                                | Default |
|-------------|---------------|--------------------------------------------|---------|
| InputObject | System.Object | Dictionary or object to copy entries from. | $null   |

.PARAMETER SkipEmptyKeys
| Name          | Type                                         | Description                                        | Default |
|---------------|----------------------------------------------|----------------------------------------------------|---------|
| SkipEmptyKeys | System.Management.Automation.SwitchParameter | Omit null, empty or whitespace-only keys when set. | $false  |

.OUTPUTS
System.Collections.Specialized.OrderedDictionary -- Case-sensitive ordered
dictionary containing the normalized entries.

.EXAMPLE
PS> $map = ConvertTo-ModuleOrderedDictionary -InputObject @{ '-p' = '8080' } -SkipEmptyKeys

Creates an ordinal OrderedDictionary preserving exact key casing.

.NOTES
Compatible with Windows PowerShell 5.1 and PowerShell 7+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function ConvertTo-ModuleOrderedDictionary()
{
    param (
        [object]$InputObject   = $null,
        [switch]$SkipEmptyKeys = $false
    );

    # Use Ordinal key comparison so case-distinct CLI flags (such as '-p' vs '-P' or '-c' vs '-C')
    # remain separate keys instead of overwriting each other in PowerShell's default case-insensitive maps
    $Ordered = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::Ordinal);

    if ($null -eq $InputObject) {
        return $Ordered;
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($Key in $InputObject.Keys) {
            [string]$KeyText = [string]$Key;

            if ($SkipEmptyKeys -and [string]::IsNullOrWhiteSpace($KeyText)) {
                continue;
            }

            $Ordered[$KeyText] = $InputObject[$Key];
        }
    } else {
        foreach ($Prop in $InputObject.PSObject.Properties) {
            [string]$PropText = [string]$Prop.Name;

            if ($SkipEmptyKeys -and [string]::IsNullOrWhiteSpace($PropText)) {
                continue;
            }

            $Ordered[$PropText] = $Prop.Value;
        }
    }

    return $Ordered;
}

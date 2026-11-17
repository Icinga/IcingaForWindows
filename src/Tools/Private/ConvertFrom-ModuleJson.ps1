<#
.SYNOPSIS
Converts a JSON formatted string to a hashtable or dictionary safely across PowerShell versions.

.DESCRIPTION
ConvertFrom-ModuleJson provides a cross-platform, cross-version safe way to parse JSON
strings into hashtables. It addresses the well-known memory leak (ETS cache bloat) in
Windows PowerShell 5.1 by falling back to System.Web.Script.Serialization.JavaScriptSerializer,
which natively returns dictionaries instead of PSCustomObjects. In PowerShell 6 and higher,
it uses the native ConvertFrom-Json cmdlet with the -AsHashtable switch.

.PARAMETER InputObject
| Name        | Type          | Description                     | Default |
|-------------|---------------|---------------------------------|---------|
| InputObject | System.String | The JSON string to deserialize. | ''      |

.OUTPUTS
System.Collections.Hashtable -- Returns a hashtable (or dictionary) representation of the JSON string.
Returns `$null` if the input is empty or parsing fails.

.EXAMPLE
PS> $hashtable = ConvertFrom-ModuleJson -InputObject '{"key": "value"}'

.NOTES
In Windows PowerShell 5.1, this function dynamically loads the System.Web.Extensions
assembly if it is not already loaded in the current runspace.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function ConvertFrom-ModuleJson()
{
    param (
        [string]$InputObject = ''
    );

    if ([string]::IsNullOrWhiteSpace($InputObject)) {
        return $null;
    }

    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            return (ConvertFrom-Json -InputObject $InputObject -AsHashtable);
        } else {
            if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
                Add-Type -AssemblyName System.Web.Extensions;
            }

            $Serializer               = New-Object System.Web.Script.Serialization.JavaScriptSerializer;
            $Serializer.MaxJsonLength = 2147483647;

            return $Serializer.DeserializeObject($InputObject);
        }
    } catch {
        Write-LoggingEntry -Message 'Failed to parse JSON string' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; 'InputObject' = $InputObject; };
    }

    return $null;
}

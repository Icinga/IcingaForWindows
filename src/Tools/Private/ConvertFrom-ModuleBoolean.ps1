<#
.SYNOPSIS
Convert boolean, numeric or string macro values into a PowerShell Boolean

.DESCRIPTION
ConvertFrom-ModuleBoolean converts JSON and Icinga 2 macro values into a strict
System.Boolean so PowerShell switch and bool parameters never misinterpret
strings such as 'False' or '0' as truthy. Recognizes booleans, SwitchParameter
values, numeric 1/0, and case-insensitive strings ('true', '1', 'yes', '$true'
for $true; 'false', '0', 'no', '$false', '' and $null for $false). Unknown values
are logged through Write-FunctionReturnValue using StringToBoolConversionInvalidValue
and evaluate to $false.

.PARAMETER Value
| Name  | Type          | Description                                               | Default |
|-------|---------------|-----------------------------------------------------------|---------|
| Value | System.Object | Input value from JSON or Icinga macros to convert.        | $null   |

.OUTPUTS
System.Boolean -- Resolved boolean value ($true or $false).

.EXAMPLE
PS> ConvertFrom-ModuleBoolean -Value 'False'
False

Converts the string 'False' into boolean $false instead of PowerShell's non-empty
string truthiness.

.NOTES
Uses Write-FunctionReturnValue with key StringToBoolConversionInvalidValue when
an unrecognized value is supplied.
#>
function ConvertFrom-ModuleBoolean()
{
    param (
        [object]$Value = $null
    );

    if ($null -eq $Value) {
        return $false;
    }

    if ($Value -is [bool]) {
        return [bool]$Value;
    }

    if ($Value -is [System.Management.Automation.SwitchParameter]) {
        return [bool]$Value.IsPresent;
    }

    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        if ($Value -eq 1) {
            return $true;
        }
        if ($Value -eq 0) {
            return $false;
        }

        return (Write-FunctionReturnValue -ReturnValue 'StringToBoolConversionInvalidValue' -Data @{ 'Value' = $Value; } -OverrideReturn $false);
    }

    [string]$Normalized = ([string]$Value).Trim().ToLowerInvariant();

    if ($Normalized.Length -eq 0) {
        return $false;
    }

    switch ($Normalized) {
        'true'   { return $true; }
        '1'      { return $true; }
        'yes'    { return $true; }
        '$true'  { return $true; }
        'false'  { return $false; }
        '0'      { return $false; }
        'no'     { return $false; }
        '$false' { return $false; }
    }

    return (Write-FunctionReturnValue -ReturnValue 'StringToBoolConversionInvalidValue' -Data @{ 'Value' = $Value; } -OverrideReturn $false);
}

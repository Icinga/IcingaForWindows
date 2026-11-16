<#
.SYNOPSIS
Retrieve a property or key value case-insensitively from a dictionary or object

.DESCRIPTION
Get-ModuleObjectValue performs a uniform, null-safe lookup across PowerShell
hashtables, Windows PowerShell 5.1 Dictionary[string, object] instances,
OrderedDictionary collections and PSCustomObject payloads. Exact-case keys are
checked first on IDictionary instances before falling back to an
OrdinalIgnoreCase scan so case-distinct keys remain deterministic while
deserialized JSON payloads remain accessible regardless of casing. Collection
values (such as arrays and ArrayLists) are returned without PowerShell pipeline
unrolling.

.PARAMETER InputObject
| Name        | Type          | Description                                        | Default |
|-------------|---------------|----------------------------------------------------|---------|
| InputObject | System.Object | Dictionary or object to read the named value from. | $null   |

.PARAMETER Name
| Name | Type          | Description                                     | Default |
|------|---------------|-------------------------------------------------|---------|
| Name | System.String | Key or property name to look up on InputObject. | ''      |

.PARAMETER DefaultValue
| Name         | Type          | Description                                              | Default |
|--------------|---------------|----------------------------------------------------------|---------|
| DefaultValue | System.Object | Fallback value returned when the key is missing or null. | $null   |

.OUTPUTS
System.Object -- Matched property or dictionary value, or DefaultValue when
missing or null.

.EXAMPLE
PS> Get-ModuleObjectValue -InputObject @{ 'Check_Timeout' = 30 } -Name 'check_timeout' -DefaultValue 60
30

Reads the value of 'Check_Timeout' case-insensitively from the dictionary.

.NOTES
Compatible with Windows PowerShell 5.1 and PowerShell 7+. Does not mutate global
state.
#>
function Get-ModuleObjectValue()
{
    param (
        [object]$InputObject  = $null,
        [string]$Name         = '',
        [object]$DefaultValue = $null
    );

    if ($null -eq $InputObject -or [string]::IsNullOrEmpty($Name)) {
        if ($DefaultValue -is [System.Collections.IEnumerable] -and $DefaultValue -isnot [string] -and $DefaultValue -isnot [System.Collections.IDictionary]) {
            return ,$DefaultValue;
        }

        return $DefaultValue;
    }

    [bool]$Found     = $false;
    [object]$Matched = $null;

    if ($InputObject -is [System.Collections.IDictionary]) {
        # Exact-case fast path first: note that on Windows PowerShell 5.1, JavaScriptSerializer returns
        # generic Dictionary[string, object] where IDictionary.Contains() is implemented explicitly and
        # only ContainsKey() is exposed directly on the concrete type.
        if ($InputObject -is [hashtable] -or $InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
            if ($InputObject.Contains($Name) -and $null -ne $InputObject[$Name]) {
                $Found   = $true;
                $Matched = $InputObject[$Name];
            }
        } else {
            try {
                if ($InputObject.ContainsKey($Name) -and $null -ne $InputObject[$Name]) {
                    $Found   = $true;
                    $Matched = $InputObject[$Name];
                }
            } catch {
                try {
                    if ($InputObject.Contains($Name) -and $null -ne $InputObject[$Name]) {
                        $Found   = $true;
                        $Matched = $InputObject[$Name];
                    }
                } catch {
                    $Found = $false;
                }
            }
        }

        # Case-insensitive fallback scan across dictionary keys when exact-case lookup missed
        if (-not $Found) {
            foreach ($Key in $InputObject.Keys) {
                if ([string]::Equals([string]$Key, $Name, [System.StringComparison]::OrdinalIgnoreCase) -and $null -ne $InputObject[$Key]) {
                    $Found   = $true;
                    $Matched = $InputObject[$Key];
                    break;
                }
            }
        }
    } else {
        # PSCustomObject / .NET object property lookup (exact match first, case-insensitive scan second)
        $DirectProp = $InputObject.PSObject.Properties[$Name];

        if ($null -ne $DirectProp -and $null -ne $DirectProp.Value) {
            $Found   = $true;
            $Matched = $DirectProp.Value;
        } else {
            foreach ($Prop in $InputObject.PSObject.Properties) {
                if ([string]::Equals([string]$Prop.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) -and $null -ne $Prop.Value) {
                    $Found   = $true;
                    $Matched = $Prop.Value;
                    break;
                }
            }
        }
    }

    if (-not $Found) {
        $Matched = $DefaultValue;
    }

    # Wrap non-string/non-dictionary enumerables with the unary comma operator so PowerShell does not
    # unroll empty (@() -> $null) or single-element (@('x') -> 'x') arrays on pipeline return
    if ($Matched -is [System.Collections.IEnumerable] -and $Matched -isnot [string] -and $Matched -isnot [System.Collections.IDictionary]) {
        return ,$Matched;
    }

    return $Matched;
}

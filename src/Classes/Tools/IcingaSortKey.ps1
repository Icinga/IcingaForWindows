<#
.SYNOPSIS
Build ordinal sort keys that reproduce a natural, multi-property sort order

.DESCRIPTION
IcingaSortKey turns objects into strings whose plain ordinal order equals the
natural order of their properties, so ConvertTo-IcingaSortedArray can sort with
the native [Array]::Sort and StringComparer.Ordinal instead of running
PowerShell code (or a script block) for every comparison.

A string value becomes its upper-case form with every digit run replaced by its
length (three digits) followed by the digits without leading zeros, so '0,2'
sorts before '0,10' and 'Core 9' before 'Core 10'; non-digit characters such as
'_' sort after digits, which puts instance names like '_Total' behind the
numbered ones. A numeric value becomes a fixed-point string, so numbers sort
numerically, including decimals and negative values. $null becomes an empty key
and sorts first. Several properties are joined with a separator that sorts below
every other character, so the next property only breaks ties of the previous one.

.OUTPUTS
IcingaSortKey — Static helper class, not meant to be instantiated.

.EXAMPLE
PS> [IcingaSortKey]::FromObject($Volume, [string[]]@('Name'))

Returns the sort key of the volume's Name property.

.NOTES
Pure helper without state or external dependencies. Numbers are supported
within +/- 1E20.
#>
class IcingaSortKey
{
    static [string]$Separator = [string][char]1;

    <#
    .SYNOPSIS
    Build the sort key of an object for the given properties

    .DESCRIPTION
    Joins the keys of the given properties in order of precedence, or returns
    the key of the object itself when no property is given. Hashtables are read
    by key, every other object (including CIM instances) by member name.

    .PARAMETER InputObject
    | Name        | Type          | Description               | Default |
    |-------------|---------------|---------------------------|---------|
    | InputObject | System.Object | The object to build for.  |         |

    .PARAMETER Property
    | Name     | Type            | Description                                       | Default |
    |----------|-----------------|---------------------------------------------------|---------|
    | Property | System.String[] | Properties in order of precedence; empty uses the object. |  |

    .OUTPUTS
    System.String — The sort key.

    .EXAMPLE
    PS> [IcingaSortKey]::FromObject($Partition, [string[]]@('DiskNumber', 'PartitionNumber'))

    .NOTES
    Missing members read as $null and therefore sort first.
    #>
    static [string] FromObject([object]$InputObject, [string[]]$Property)
    {
        if ($null -eq $Property -or $Property.Count -eq 0) {
            return [IcingaSortKey]::FromValue($InputObject);
        }

        [string[]]$Keys = @();

        foreach ($Name in $Property) {
            $Keys += [IcingaSortKey]::FromValue([IcingaSortKey]::GetMemberValue($InputObject, $Name));
        }

        return ($Keys -join [IcingaSortKey]::Separator);
    }

    <#
    .SYNOPSIS
    Build the sort key of a single value

    .DESCRIPTION
    Returns an empty key for $null, a fixed-point key for numeric types and the
    natural string key for everything else.

    .PARAMETER Value
    | Name  | Type          | Description             | Default |
    |-------|---------------|-------------------------|---------|
    | Value | System.Object | The value to build for. |         |

    .OUTPUTS
    System.String — The sort key.

    .EXAMPLE
    PS> [IcingaSortKey]::FromValue('0,10')

    .NOTES
    Numeric means a .NET numeric type; numeric strings use the natural string key.
    #>
    static [string] FromValue([object]$Value)
    {
        if ($null -eq $Value) {
            return '';
        }

        if ($Value -is [int] -or $Value -is [long] -or $Value -is [uint32] -or $Value -is [uint64] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [byte] -or $Value -is [sbyte] -or $Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
            # Shifting by 1E20 makes every supported number positive, so a fixed
            # width keeps the ordinal order numeric for negative values as well.
            return ([decimal]$Value + [decimal]100000000000000000000).ToString('000000000000000000000.0000000000', [System.Globalization.CultureInfo]::InvariantCulture);
        }

        [string]$Text = ([string]$Value).ToUpperInvariant();
        [string]$Key  = '';

        foreach ($Part in [regex]::Matches($Text, '\d+|\D+')) {
            [string]$Chunk = $Part.Value;

            if ([char]::IsDigit($Chunk[0])) {
                [string]$Digits = $Chunk.TrimStart('0');
                $Key += $Digits.Length.ToString('000') + $Digits;
            } else {
                $Key += $Chunk;
            }
        }

        return $Key;
    }

    <#
    .SYNOPSIS
    Read a property from a hashtable or an object

    .DESCRIPTION
    Returns the value stored under the key for dictionaries and the member value
    for every other object, or $null when the object itself is $null.

    .PARAMETER InputObject
    | Name        | Type          | Description          | Default |
    |-------------|---------------|----------------------|---------|
    | InputObject | System.Object | Object to read from. |         |

    .PARAMETER Name
    | Name | Type          | Description         | Default |
    |------|---------------|---------------------|---------|
    | Name | System.String | Key or member name. |         |

    .OUTPUTS
    System.Object — The property value or $null.

    .EXAMPLE
    PS> [IcingaSortKey]::GetMemberValue($Volume, 'Name')

    .NOTES
    Internal helper of FromObject.
    #>
    static [object] GetMemberValue([object]$InputObject, [string]$Name)
    {
        if ($null -eq $InputObject) {
            return $null;
        }

        if ($InputObject -is [System.Collections.IDictionary]) {
            return $InputObject[$Name];
        }

        return $InputObject.$Name;
    }
}

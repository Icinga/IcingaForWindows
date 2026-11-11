<#
.SYNOPSIS
Sort objects by one or more properties in natural order without a script block

.DESCRIPTION
ConvertTo-IcingaSortedArray sorts an array without Sort-Object and without any
script block, so the plugins stay usable in JEA sessions. Every element gets a
sort key from IcingaSortKey once, then the native [Array]::Sort orders keys and
elements with an ordinal string comparison, which keeps the sort fast for large
inputs such as all Windows services.

The objects are compared by the given properties in order of precedence, or by
themselves when no property is given. Values sort in natural order: numbers
numerically and strings case-insensitively with digit runs compared by value,
so '0,2' comes before '0,10' and '_Total' after every numbered instance. The
sort is stable, equal elements keep their input order in both directions.
Hashtables are read by key, every other object (including CIM instances) by
member name.

.PARAMETER InputObject
| Name        | Type         | Description            | Default |
|-------------|--------------|------------------------|---------|
| InputObject | System.Array | The elements to sort.  | @()     |

.PARAMETER Property
| Name     | Type         | Description                                                              | Default |
|----------|--------------|--------------------------------------------------------------------------|---------|
| Property | System.Array | Properties to sort by, in order of precedence; empty sorts the elements. | @()     |

.PARAMETER Descending
| Name       | Type                                         | Description               | Default |
|------------|----------------------------------------------|---------------------------|---------|
| Descending | System.Management.Automation.SwitchParameter | Sort in descending order. | False   |

.OUTPUTS
System.Object[] -- A new array with the sorted elements; the input stays unchanged.

.EXAMPLE
PS> ConvertTo-IcingaSortedArray -InputObject @('0,10', '_Total', '0,2', '0,_Total')

Returns @('0,2', '0,10', '0,_Total', '_Total').

.EXAMPLE
PS> ConvertTo-IcingaSortedArray -InputObject $Services -Property 'Name'

Sorts Win32_Service instances by their name.

.NOTES
No external dependencies. Replaces 'Sort-Object -Property { ... }' in plugin
code. The verb follows the approved PowerShell verbs; 'Sort' is not one of them.
#>
function ConvertTo-IcingaSortedArray()
{
    param (
        [array]$InputObject = @(),
        [array]$Property    = @(),
        [switch]$Descending = $false
    );

    if ($null -eq $InputObject -or $InputObject.Count -eq 0) {
        return ,@();
    }

    [int]$Count      = $InputObject.Count;
    [string[]]$Keys  = [string[]]::new($Count);
    [object[]]$Items = [object[]]::new($Count);
    $SortKeyType     = 'IcingaSortKey' -as [type];

    for ($i = 0; $i -lt $Count; $i++) {
        # The position breaks ties and keeps the sort stable. A descending sort runs
        # ascending and is reversed afterwards, so it needs the mirrored position.
        [int]$Position = $i;

        if ($Descending) {
            $Position = $Count - 1 - $i;
        }

        $Keys[$i]  = $SortKeyType::FromObject($InputObject[$i], [string[]]$Property) + $SortKeyType::Separator + $Position.ToString('0000000000');
        $Items[$i] = $InputObject[$i];
    }

    # The explicit casts select the non-generic overload; with the generic one
    # PowerShell sorts a converted copy of the elements and leaves $Items unsorted.
    [System.Array]::Sort([System.Array]$Keys, [System.Array]$Items, [System.Collections.IComparer][System.StringComparer]::Ordinal);

    if ($Descending) {
        [System.Array]::Reverse($Items);
    }

    return ,$Items;
}

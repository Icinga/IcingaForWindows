<#
.SYNOPSIS
Normalize string elements of an array to lower- or upper-case.

.DESCRIPTION
`ConvertTo-StringNormalizedArray` returns a new array where string elements
are converted to a normalized case (lower-case by default or upper-case when
`-UpperCase` is specified). Non-string elements are preserved unchanged.
This helper is useful for normalizing user lists for case-insensitive or
consistent comparisons.

.PARAMETER InputArray
| Name | Type | Description | Default |
|------|------|-------------|---------|
| InputArray | System.Object[] | Array of items to normalize; string items will be case-normalized | @() |

.PARAMETER UpperCase
| Name | Type | Description | Default |
|------|------|-------------|---------|
| UpperCase | Switch | When set, convert string items to upper-case instead of lower-case | $false |

.OUTPUTS
Array of the same length with string items converted to the selected case.

.EXAMPLE
$norm = ConvertTo-StringNormalizedArray -InputArray @('Alice','BOB', 123)

.EXAMPLE
$normUpper = ConvertTo-StringNormalizedArray -InputArray @('Alice','BOB') -UpperCase

.NOTES
- Non-string items are returned unchanged.
#>
function ConvertTo-StringNormalizedArray()
{
    param (
        $InputArray        = @(),
        [switch]$UpperCase = $false
    );

    # Create a new array to hold normalized strings
    $NormalizedArray = @();

    # Convert each string to normalized case, but keep non-string items unchanged
    foreach ($Item in $InputArray) {
        if ($Item -isnot [string]) {
            $NormalizedArray += $Item;
            continue;
        };

        if ($UpperCase) {
            $NormalizedArray += $Item.ToUpper();
            continue;
        };

        $NormalizedArray += $Item.ToLower();
    };

    # Return the new normalized-case array
    return $NormalizedArray;
}

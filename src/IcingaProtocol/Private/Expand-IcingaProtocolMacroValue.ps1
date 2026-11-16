<#
.SYNOPSIS
Expand single and embedded Icinga 2 macro references against a macro dictionary

.DESCRIPTION
Expand-IcingaProtocolMacroValue evaluates a single Icinga 2 argument value or
set_if expression against an ordinal MacroMap and case-insensitive fallback
table:
- Non-string values (booleans, numbers, arrays, dictionaries) preserve their
  native type directly when non-null.
- Exact single-token '$macro$' strings resolve directly to the native macro
  object (preserving arrays, booleans and numbers without stringifying).
- Strings containing embedded '$macro$' tokens or escaped '$$' literals are
  interpolated in a single left-to-right pass so macro values containing '$'
  characters (such as Windows administrative shares '\\host\C$\MSSQL$INST') are
  never re-expanded. If any referenced token is unset or null, IsSet returns
  $false so optional Icinga arguments are cleanly skipped.

.PARAMETER Expression
| Name       | Type          | Description                                               | Default |
|------------|---------------|-----------------------------------------------------------|---------|
| Expression | System.Object | Raw 'value' or 'set_if' expression from ifw_api_arguments.| $null   |

.PARAMETER MacroMap
| Name     | Type          | Description                                              | Default |
|----------|---------------|----------------------------------------------------------|---------|
| MacroMap | System.Object | Case-sensitive OrderedDictionary of macro key/values.    | $null   |

.PARAMETER MacroIgnoreCase
| Name            | Type                         | Description                                       | Default |
|-----------------|------------------------------|---------------------------------------------------|---------|
| MacroIgnoreCase | System.Collections.Hashtable | Case-insensitive fallback hashtable for macros.   | @{}     |

.OUTPUTS
System.Collections.Hashtable -- Hashtable with keys IsSet (System.Boolean) and
Value (System.Object).

.EXAMPLE
PS> Expand-IcingaProtocolMacroValue -Expression 'http://$address$:$port$/health' -MacroMap $map -MacroIgnoreCase $ci

Interpolates the '$address$' and '$port$' tokens in a single pass.

.NOTES
Pure macro evaluator with no side effects or global state dependencies.
#>
function Expand-IcingaProtocolMacroValue()
{
    param (
        [object]$Expression         = $null,
        [object]$MacroMap           = $null,
        [hashtable]$MacroIgnoreCase = @{ }
    );

    # 1. Non-string values (native booleans, numbers, arrays) pass through unchanged
    if ($Expression -isnot [string]) {
        return @{
            'IsSet' = ($null -ne $Expression);
            'Value' = $Expression;
        };
    }

    # 2. Exact single-macro reference ($MacroName$) preserves the underlying native type (e.g. array/bool/int)
    if ($Expression -match '^\$([A-Za-z0-9_.:-]+)\$$') {
        [string]$MacroRef = $Matches[1];

        if ($null -ne $MacroMap -and $MacroMap.Contains($MacroRef) -and $null -ne $MacroMap[$MacroRef]) {
            return @{
                'IsSet' = $true;
                'Value' = $MacroMap[$MacroRef];
            };
        }

        if ($null -ne $MacroIgnoreCase -and $MacroIgnoreCase.ContainsKey($MacroRef) -and $null -ne $MacroIgnoreCase[$MacroRef]) {
            return @{
                'IsSet' = $true;
                'Value' = $MacroIgnoreCase[$MacroRef];
            };
        }

        return @{
            'IsSet' = $false;
            'Value' = $null;
        };
    }

    # 3. Single-pass interpolation for embedded $macro$ tokens and escaped $$ literals
    #    (single-dollar Windows identifiers such as C$ or MSSQL$SQLEXPRESS remain untouched)
    $TokenMatches = [regex]::Matches($Expression, '\$\$|\$([A-Za-z0-9_.:-]+)\$');

    if ($TokenMatches.Count -eq 0) {
        return @{
            'IsSet' = $true;
            'Value' = $Expression;
        };
    }

    $Builder     = New-Object System.Text.StringBuilder;
    [int]$Cursor = 0;

    foreach ($TokenMatch in $TokenMatches) {
        if ($TokenMatch.Index -gt $Cursor) {
            [void]$Builder.Append($Expression.Substring($Cursor, ($TokenMatch.Index - $Cursor)));
        }

        if ($TokenMatch.Value -eq '$$') {
            [void]$Builder.Append('$');
        } else {
            [string]$TokenName = $TokenMatch.Groups[1].Value;
            [object]$TokenVal  = $null;

            if ($null -ne $MacroMap -and $MacroMap.Contains($TokenName)) {
                $TokenVal = $MacroMap[$TokenName];
            } elseif ($null -ne $MacroIgnoreCase -and $MacroIgnoreCase.ContainsKey($TokenName)) {
                $TokenVal = $MacroIgnoreCase[$TokenName];
            }

            if ($null -eq $TokenVal) {
                return @{
                    'IsSet' = $false;
                    'Value' = $null;
                };
            }

            [void]$Builder.Append([string]$TokenVal);
        }

        $Cursor = $TokenMatch.Index + $TokenMatch.Length;
    }

    if ($Cursor -lt $Expression.Length) {
        [void]$Builder.Append($Expression.Substring($Cursor));
    }

    return @{
        'IsSet' = $true;
        'Value' = $Builder.ToString();
    };
}

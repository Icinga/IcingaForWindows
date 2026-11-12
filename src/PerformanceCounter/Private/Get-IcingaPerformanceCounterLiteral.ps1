<#
.SYNOPSIS
Extract literal counter path strings from an AST argument node

.DESCRIPTION
`Get-IcingaPerformanceCounterLiteral` walks an argument's abstract syntax tree and
collects the value of every string constant it contains. It is used by the startup
discovery step to read the literal counter list passed to a `New-IcingaPerformanceCounter`
call without executing any component code. Non-literal arguments (variables, expressions)
contribute no values, which is intentional -- only statically declarable counters are
discovered.

.PARAMETER Argument
| Name     | Type                                      | Description                              | Default |
|----------|-------------------------------------------|------------------------------------------|---------|
| Argument | System.Management.Automation.Language.Ast | The AST node of the `-Counter` argument. | $null   |

.OUTPUTS
System.Array -- The literal string values found in the argument, or an empty array.

.EXAMPLE
PS> Get-IcingaPerformanceCounterLiteral -Argument $argumentAst

.NOTES
Called by `Register-IcingaPerformanceCounterFromComponents`. Returns an empty array when
the argument is null or contains no string literals.
#>
function Get-IcingaPerformanceCounterLiteral()
{
    param (
        [System.Management.Automation.Language.Ast]$Argument = $null
    );

    [array]$Values = @();

    if ($null -eq $Argument) {
        return $Values;
    }

    $Strings = $Argument.FindAll(
        {
            param ($Node)
            $Node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        },
        $true
    );

    foreach ($String in $Strings) {
        $Values += $String.Value;
    }

    return $Values;
}

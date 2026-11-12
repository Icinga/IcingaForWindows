<#
.SYNOPSIS
Reshape a flat performance counter result into an instance/category/counter structure

.DESCRIPTION
`ConvertTo-IcingaPerformanceCounterInstanceStructure` transforms the default result of
`Get-IcingaPerformanceCounter` (a hashtable keyed by the requested counter path) into a nested
structure that is easier to consume when writing plugins.

Counters that carry an instance are keyed instance-first, then category, then counter name:
`$out[Instance][Category][Counter]`. Counters without an instance are keyed category-first, then
counter name: `$out[Category][Counter]`. In both cases the leaf is the uniform value hashtable
(`value`, `sample`, `help`, `type`, `error`), so `$out['0']['Processor']['% Processor Time'].value`
and `$out['Memory']['Pages/sec'].value` both work. Wildcard requests are expanded so each live
instance becomes its own top-level key (for example CPU cores `0`, `1`, `_Total`).

The requested paths are re-parsed to decide the shape, so the transform never has to guess whether a
nested value is a value hashtable or an instance group.

.PARAMETER Result
| Name   | Type                         | Description                                                  | Default |
|--------|------------------------------|--------------------------------------------------------------|---------|
| Result | System.Collections.Hashtable | The result returned by the manager, keyed by requested path. | @{ }    |

.PARAMETER Counter
| Name    | Type         | Description                                                        | Default |
|---------|--------------|--------------------------------------------------------------------|---------|
| Counter | System.Array | The originally requested counter paths, used to drive the reshape. | @()     |

.OUTPUTS
System.Collections.Hashtable -- Nested structure keyed by instance/category or category, with the
uniform value hashtable at the leaf.

.EXAMPLE
PS> ConvertTo-IcingaPerformanceCounterInstanceStructure -Result $raw -Counter '\Processor(*)\% Processor Time'

.NOTES
Called by `Get-IcingaPerformanceCounter` when `-StructureByInstance` is set. Pure transform; touches
no global state and reads no counters.
#>
function ConvertTo-IcingaPerformanceCounterInstanceStructure()
{
    param (
        [hashtable]$Result = @{ },
        [array]$Counter    = @()
    );

    [hashtable]$Structured = @{ };

    if ($null -eq $Result) {
        return $Structured;
    }

    $CounterType = 'IcingaPerformanceCounter' -as [type];

    foreach ($RequestedPath in $Counter) {
        if ([string]::IsNullOrEmpty($RequestedPath) -or -not $Result.ContainsKey($RequestedPath)) {
            continue;
        }

        $Entry               = $Result[$RequestedPath];
        $Parsed              = $CounterType::ParsePath($RequestedPath);

        # Normalize to a set of concrete "counter path -> value hashtable" pairs. A wildcard result
        # is already keyed by each expanded path; a concrete request maps to a single pair.
        [hashtable]$Concrete = @{ };

        if ($Parsed.Instance -eq '*') {
            $Concrete = $Entry;
        } else {
            $Concrete[$RequestedPath] = $Entry;
        }

        foreach ($ConcretePath in $Concrete.Keys) {
            $Path  = $CounterType::ParsePath($ConcretePath);
            $Value = $Concrete[$ConcretePath];

            if (-not [string]::IsNullOrEmpty($Path.Instance)) {
                if (-not $Structured.ContainsKey($Path.Instance)) {
                    $Structured[$Path.Instance] = @{ };
                }
                if (-not $Structured[$Path.Instance].ContainsKey($Path.Category)) {
                    $Structured[$Path.Instance][$Path.Category] = @{ };
                }
                $Structured[$Path.Instance][$Path.Category][$Path.Counter] = $Value;
            } else {
                if (-not $Structured.ContainsKey($Path.Category)) {
                    $Structured[$Path.Category] = @{ };
                }
                $Structured[$Path.Category][$Path.Counter] = $Value;
            }
        }
    }

    return $Structured;
}

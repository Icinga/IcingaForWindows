<#
.SYNOPSIS
Show live values for the registered performance counters, or a filtered subset

.DESCRIPTION
`Show-IcingaPerformanceCounterDetails` returns the current values of performance counters
through `Get-IcingaPerformanceCounter`. Called without arguments it dumps every counter
currently registered in the global store. Passing `-Counter` narrows the output to the given
paths. The result keeps the uniform shape: a hashtable keyed by counter path with flat value
hashtables for concrete paths and nested hashtables for wildcard paths.

.PARAMETER Counter
| Name    | Type         | Description                                                        | Default |
|---------|--------------|--------------------------------------------------------------------|---------|
| Counter | System.Array | Counter paths to show. Empty shows all registered counters.        | @()     |

.PARAMETER StructureByInstance
| Name                | Type                                         | Description                                                              | Default |
|---------------------|----------------------------------------------|--------------------------------------------------------------------------|---------|
| StructureByInstance | System.Management.Automation.SwitchParameter | Reshape the result to instance/category/counter, forwarded to Get-IcingaPerformanceCounter. | $false |

.OUTPUTS
System.Collections.Hashtable — Keyed by counter path; values as returned by
`Get-IcingaPerformanceCounter`. With `-StructureByInstance`, keyed by instance/category/counter.
Empty when nothing is registered and nothing is requested.

.EXAMPLE
PS> Show-IcingaPerformanceCounterDetails

Shows live values for every registered counter.

.EXAMPLE
PS> Show-IcingaPerformanceCounterDetails -Counter '\Processor(_Total)\% Processor Time'

Shows the live value for a single specified counter.

.NOTES
This is a thin convenience layer over `Get-IcingaPerformanceCounter`; the same daemon/inline
behavior and return shape apply. No external services are used.
#>
function Show-IcingaPerformanceCounterDetails()
{
    param (
        [array]$Counter              = @(),
        [switch]$StructureByInstance = $false
    );

    [array]$Requested = $Counter;

    if ($null -eq $Requested -or $Requested.Count -eq 0) {
        $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;

        if ($null -ne $Store) {
            $Requested = @($Store.Registered.Keys);
        }
    }

    if ($null -eq $Requested -or $Requested.Count -eq 0) {
        return @{ };
    }

    return (Get-IcingaPerformanceCounter -Counter $Requested -StructureByInstance:$StructureByInstance);
}

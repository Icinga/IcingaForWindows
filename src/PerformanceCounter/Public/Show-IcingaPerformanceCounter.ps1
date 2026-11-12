<#
.SYNOPSIS
Browse performance counter categories, counters and live instances

.DESCRIPTION
`Show-IcingaPerformanceCounter` is a stateless introspection helper that queries Windows
performance counter metadata directly. It has three modes selected by the parameters passed:

- With no arguments it lists all counter categories, optionally filtered by `-Filter` using
  wildcard matching.
- With `-Category` it lists the counter paths inside that category, emitting '\Category(*)\Counter'
  for multi-instance categories and '\Category\Counter' for single-instance categories.
- With `-Counter` (a wildcard path) it lists the concrete counter paths for every live instance.

Because it only reads metadata it is safe to call from any thread and does not require the
daemon. Errors are logged and yield an empty result rather than throwing.

.PARAMETER Category
| Name     | Type          | Description                             | Default |
|----------|---------------|-----------------------------------------|---------|
| Category | System.String | List the counters within this category. | $null   |

.PARAMETER Counter
| Name    | Type          | Description                                                  | Default |
|---------|---------------|--------------------------------------------------------------|---------|
| Counter | System.String | Wildcard counter path whose live instances should be listed. | $null   |

.PARAMETER Filter
| Name   | Type          | Description                                      | Default |
|--------|---------------|--------------------------------------------------|---------|
| Filter | System.String | Wildcard filter applied when listing categories. | $null   |

.OUTPUTS
System.Array -- Category names, counter paths, or instance paths depending on the mode.

.EXAMPLE
PS> Show-IcingaPerformanceCounter

Lists all performance counter categories.

.EXAMPLE
PS> Show-IcingaPerformanceCounter -Category 'Processor'

Lists the counter paths available in the Processor category.

.EXAMPLE
PS> Show-IcingaPerformanceCounter -Counter '\PhysicalDisk(*)\Disk Reads/sec'

Lists the concrete per-instance paths that currently exist for the wildcard counter.

.NOTES
Uses `System.Diagnostics.PerformanceCounterCategory` directly. No global state is read or
written, and no external services are used.
#>
function Show-IcingaPerformanceCounter()
{
    param (
        [string]$Category = $null,
        [string]$Counter  = $null,
        [string]$Filter   = $null
    );

    # Mode: list live instance paths for a wildcard counter.
    if (-not [string]::IsNullOrEmpty($Counter)) {
        [array]$Instances = @();
        $Parsed           = ('IcingaPerformanceCounter' -as [type])::ParsePath($Counter);

        if (-not $Parsed.Valid) {
            return $Instances;
        }

        try {
            $CategoryObject = [System.Diagnostics.PerformanceCounterCategory]::new($Parsed.Category);

            foreach ($InstanceName in $CategoryObject.GetInstanceNames()) {
                $Instances += ('\{0}({1})\{2}' -f $Parsed.Category, $InstanceName, $Parsed.Counter);
            }
        } catch {
            Write-LoggingEntry -Message 'Show-IcingaPerformanceCounter: Failed to read counter instances' -Level 'Warning' -Data @{
                'Counter'   = $Counter;
                'Exception' = $_.Exception.Message;
            };
        }

        return ($Instances | Sort-Object);
    }

    # Mode: list counter paths inside a category.
    if (-not [string]::IsNullOrEmpty($Category)) {
        [array]$Counters = @();

        try {
            $CategoryObject = [System.Diagnostics.PerformanceCounterCategory]::new($Category);
            $InstanceNames  = $CategoryObject.GetInstanceNames();

            if ($null -ne $InstanceNames -and $InstanceNames.Count -gt 0) {
                foreach ($CounterObject in $CategoryObject.GetCounters($InstanceNames[0])) {
                    $Counters += ('\{0}(*)\{1}' -f $Category, $CounterObject.CounterName);
                    $CounterObject.Dispose();
                }
            } else {
                foreach ($CounterObject in $CategoryObject.GetCounters()) {
                    $Counters += ('\{0}\{1}' -f $Category, $CounterObject.CounterName);
                    $CounterObject.Dispose();
                }
            }
        } catch {
            Write-LoggingEntry -Message 'Show-IcingaPerformanceCounter: Failed to read category counters' -Level 'Warning' -Data @{
                'Category'  = $Category;
                'Exception' = $_.Exception.Message;
            };
        }

        return ($Counters | Sort-Object -Unique);
    }

    # Mode: list categories, optionally filtered.
    [array]$Categories = @();

    try {
        foreach ($CategoryObject in [System.Diagnostics.PerformanceCounterCategory]::GetCategories()) {
            if ([string]::IsNullOrEmpty($Filter) -or $CategoryObject.CategoryName -like $Filter) {
                $Categories += $CategoryObject.CategoryName;
            }
        }
    } catch {
        Write-LoggingEntry -Message 'Show-IcingaPerformanceCounter: Failed to read counter categories' -Level 'Warning' -Data @{
            'Exception' = $_.Exception.Message;
        };
    }

    return ($Categories | Sort-Object);
}

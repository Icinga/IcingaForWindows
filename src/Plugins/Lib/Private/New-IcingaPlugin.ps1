<#
.SYNOPSIS
Create an IcingaPlugin node with the class type of the current runspace

.DESCRIPTION
New-IcingaPlugin is the factory every plugin and function uses instead of
[IcingaPlugin]::new(). It resolves the IcingaPlugin type at runtime in the
calling runspace and calls the matching constructor: with a name only it creates
a container that aggregates child checks, with a value it creates a check, and
with a unit the value and the thresholds of the check use that unit.

The returned node exposes the full fluent surface of IcingaPlugin. Wrap the call
in parentheses to chain methods directly, for example
(New-IcingaPlugin 'C:' 55 '%').Warning('80').CheckRange(). The parameters are
positional in the order Name, Value, Unit.

.PARAMETER Name
| Name | Type          | Description                          | Default |
|------|---------------|--------------------------------------|---------|
| Name | System.String | Display name of the plugin node.     | $null   |

.PARAMETER Value
| Name  | Type          | Description                                                           | Default |
|-------|---------------|-----------------------------------------------------------------------|---------|
| Value | System.Object | Measured value, a number or '<number><unit>'. Makes the node a check. | $null   |

.PARAMETER Unit
| Name | Type          | Description                                                  | Default |
|------|---------------|--------------------------------------------------------------|---------|
| Unit | System.String | Icinga unit of the value and thresholds, e.g. '%', 'B', 's'. |         |

.OUTPUTS
IcingaPlugin -- The new plugin node, an instance of the IcingaPlugin type loaded by
the current runspace.

.EXAMPLE
PS> $CheckPackage = New-IcingaPlugin 'Disks';
PS> $CheckPackage.AddCheck((New-IcingaPlugin 'C:' 55 '%').Warning('80').Critical('90').CheckRange()).Commit();

Creates a container and adds a disk check that is evaluated immediately.

.EXAMPLE
PS> (New-IcingaPlugin 'System Uptime' 93784 's').Warning('1d:').CheckRange()

Creates a time check whose output renders the value as '1d 2h 3m 4s'.

.NOTES
Every runspace shares the compiled kernel, so a class literal such as
[IcingaPlugin]::new() inside a function resolves to the type of the main
runspace. On Windows PowerShell 5.1 a method call on such an instance from a
background thread waits until the main runspace is idle, which stalls daemons and
workers. The runtime lookup returns the type the current runspace loaded itself.
Keep the node inside the runspace that created it and hand only its rendered
output, exit code and performance data to other threads.
#>
function New-IcingaPlugin()
{
    param (
        [string]$Name  = $null,
        [object]$Value = $null,
        [string]$Unit  = ''
    );

    $PluginType = 'IcingaPlugin' -as [type];

    if ($PSBoundParameters.ContainsKey('Value') -or $PSBoundParameters.ContainsKey('Unit')) {
        return $PluginType::new($Name, $Value, $Unit);
    }

    return $PluginType::new($Name);
}

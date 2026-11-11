<#
.SYNOPSIS
Test whether a value is an IcingaError returned by a data collection function

.DESCRIPTION
Data collection functions such as Get-IcingaWindowsInformation return an
IcingaError in place of their data when they fail. Test-IcingaError checks a
result against the IcingaError type of the current runspace, so a plugin or
provider can stop with a single check before it uses the data. It returns $false
for $null, for collections and for every other value.

.PARAMETER InputObject
| Name        | Type          | Description                                    | Default |
|-------------|---------------|------------------------------------------------|---------|
| InputObject | System.Object | Result of a data collection function to test.  | $null   |

.OUTPUTS
System.Boolean -- $true when InputObject is an IcingaError, otherwise $false.

.EXAMPLE
PS> $Services = Get-IcingaWindowsInformation -ClassName 'Win32_Service';
PS> if (Test-IcingaError -InputObject $Services) { return $CheckPackage.SetError($Services).Compile(); }

Stops the plugin with the error message when the query failed.

.NOTES
Use it instead of '-is [IcingaError]'. Every runspace shares the compiled kernel,
so the literal resolves to the type of the main runspace and does not match an
error created inside a background thread. No external dependencies.
#>
function Test-IcingaError()
{
    param (
        [object]$InputObject = $null
    );

    return ($InputObject -is ('IcingaError' -as [type]));
}

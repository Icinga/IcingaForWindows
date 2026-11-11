<#
.SYNOPSIS
Startup type of a Windows service

.DESCRIPTION
IcingaServiceStartupType lists the ways a Windows service can be started. The
numeric values 0 to 4 match System.ServiceProcess.ServiceStartMode (Boot,
System, Automatic, Manual, Disabled); Unknown (5) covers services whose start
mode cannot be determined.

The enum is used directly as a parameter type, so a plugin parameter such as
[IcingaServiceStartupType[]]$FilterStartupType accepts 'Automatic', 'manual' or
3 and rejects anything else with the list of valid names.

.OUTPUTS
IcingaServiceStartupType -- Enum value of the service startup type.

.EXAMPLE
PS> [IcingaServiceStartupType]'Manual'

Converts the name into IcingaServiceStartupType::Manual.

.NOTES
Defined in the kernel ahead of every function, so functions may use it as a
parameter type. Not visible outside the module scope; callers pass the name or
code as a string.
#>
enum IcingaServiceStartupType
{
    Boot      = 0;
    System    = 1;
    Automatic = 2;
    Manual    = 3;
    Disabled  = 4;
    Unknown   = 5;
}

<#
.SYNOPSIS
Map external service start mode values onto IcingaServiceStartupType

.DESCRIPTION
IcingaServiceStartupTypeMap converts the start mode representations of the
different Windows service sources into an IcingaServiceStartupType: the
Win32_Service 'StartMode' strings (which report automatic services as 'Auto'),
the ServiceStartMode values of Get-Service, enum names in any casing and numeric
codes. Every value that cannot be mapped resolves to Unknown instead of
throwing.

.OUTPUTS
IcingaServiceStartupTypeMap -- Static helper class, not meant to be instantiated.

.EXAMPLE
PS> [IcingaServiceStartupTypeMap]::Resolve('Auto')

Returns IcingaServiceStartupType::Automatic.

.NOTES
Pure conversion helper without state or external dependencies.
#>
class IcingaServiceStartupTypeMap
{
    <#
    .SYNOPSIS
    Resolve a service start mode value into an IcingaServiceStartupType

    .DESCRIPTION
    Removes blanks from the value, translates the Win32_Service 'Auto' start mode
    to Automatic and converts the rest by name (case-insensitive) or numeric code.
    Returns Unknown for $null, empty, unknown names and undefined codes.

    .PARAMETER Value
    | Name  | Type          | Description                                                            | Default |
    |-------|---------------|------------------------------------------------------------------------|---------|
    | Value | System.Object | Startup type name, Win32_Service start mode, ServiceStartMode or code. |         |

    .OUTPUTS
    IcingaServiceStartupType -- The resolved startup type, Unknown when it cannot be mapped.

    .EXAMPLE
    PS> [IcingaServiceStartupTypeMap]::Resolve('Disabled')

    .NOTES
    PowerShell enum conversion rejects undefined codes, so '-as' returns $null for
    them and they fall back to Unknown like unknown names.
    #>
    static [IcingaServiceStartupType] Resolve([object]$Value)
    {
        if ($null -eq $Value) {
            return [IcingaServiceStartupType]::Unknown;
        }

        [string]$Name = ([string]$Value).Replace(' ', '');

        if ($Name -eq 'Auto') {
            return [IcingaServiceStartupType]::Automatic;
        }

        $StartupType = $Name -as [IcingaServiceStartupType];

        if ($null -eq $StartupType) {
            return [IcingaServiceStartupType]::Unknown;
        }

        return $StartupType;
    }
}

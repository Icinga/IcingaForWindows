<#
.SYNOPSIS
Query a CIM class and return its instances or an IcingaError

.DESCRIPTION
Get-IcingaWindowsInformation is the single entry point for reading Windows
management data. It runs Get-CimInstance with -ErrorAction Stop and never
throws: on success it returns the instances as an array (empty when nothing
matches), on failure it returns an IcingaError that names the class, the
namespace and the reason, so a plugin can stop with one check:

    if (Test-IcingaError -InputObject $Data) { return $CheckPackage.SetError($Data).Compile(); }

Every exit goes through Write-FunctionReturnValue with its own return code, so
the log shows exactly which query succeeded or failed and why: a successful
query (WindowsInformationQueried), a missing class name
(WindowsInformationClassNameMissing), an unknown class
(WindowsInformationClassUnknown), an unknown namespace
(WindowsInformationNamespaceInvalid), missing permissions
(WindowsInformationAccessDenied), an invalid filter or property list
(WindowsInformationInvalidQuery) and every other error
(WindowsInformationQueryFailed). The return code of a failure is also stored in
the ReturnCode of the IcingaError.

OperationOption passes provider-specific custom options with the query, such as
@{ 'PolicyStore' = 'ActiveStore' } for the NetSecurity classes in
root/StandardCimv2. Get-CimInstance cannot carry them, so such a query runs as
WQL ('SELECT <Property> FROM <ClassName> WHERE <Filter>') through a local
CimSession, which is disposed afterwards. Errors map to the same return codes.

.PARAMETER ClassName
| Name      | Type          | Description                     | Default |
|-----------|---------------|---------------------------------|---------|
| ClassName | System.String | Name of the CIM class to query. |         |

.PARAMETER Namespace
| Name      | Type          | Description                 | Default    |
|-----------|---------------|-----------------------------|------------|
| Namespace | System.String | CIM namespace of the class. | root/cimv2 |

.PARAMETER Filter
| Name   | Type          | Description                                   | Default |
|--------|---------------|-----------------------------------------------|---------|
| Filter | System.String | WQL filter, e.g. 'DriveType = 3'; '' for all. |         |

.PARAMETER Property
| Name     | Type         | Description                                     | Default |
|----------|--------------|-------------------------------------------------|---------|
| Property | System.Array | Properties to fetch; empty fetches all of them. | @()     |

.PARAMETER OperationOption
| Name            | Type                         | Description                                                           | Default |
|-----------------|------------------------------|-----------------------------------------------------------------------|---------|
| OperationOption | System.Collections.Hashtable | CIM custom options for the provider, e.g. @{ PolicyStore = 'RSOP' }.  | @{ }    |

.OUTPUTS
System.Object[] -- The CIM instances on success (an empty array when nothing
matches), or an IcingaError when the query failed.

.EXAMPLE
PS> Get-IcingaWindowsInformation -ClassName 'Win32_Volume' -Filter 'DriveType = 3' -Property 'Name', 'Capacity', 'FreeSpace'

Returns the local disk volumes with the three requested properties.

.EXAMPLE
PS> Get-IcingaWindowsInformation -ClassName 'MSFT_NetFirewallProfile' -Namespace 'root/StandardCimv2' -OperationOption @{ 'PolicyStore' = 'ActiveStore'; }

Returns the effective firewall profiles, merged from local settings and Group
Policy.

.EXAMPLE
PS> $Mpio =Get-IcingaWindowsInformation -ClassName 'MPIO_DISK_INFO' -Namespace 'root/wmi'

Returns an IcingaError with the return code WindowsInformationClassUnknown on
hosts without the MPIO feature.

.NOTES
Windows-only, uses the local CIM provider. The required permissions depend on
the class; standard users can read most root/cimv2 classes. Unknown classes and
namespaces are logged at Debug level only, because optional classes are probed
on purpose.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-IcingaWindowsInformation()
{
    param (
        [string]$ClassName          = '',
        [string]$Namespace          = 'root/cimv2',
        [string]$Filter             = '',
        [array]$Property            = @(),
        [hashtable]$OperationOption = @{ }
    );

    if ([string]::IsNullOrEmpty($ClassName)) {
        return (Write-FunctionReturnValue -ReturnValue 'WindowsInformationClassNameMissing' -Data @{ 'Namespace' = $Namespace; } -OverrideReturn (('IcingaError' -as [type])::new('WindowsInformationClassNameMissing', 'No CIM class name was provided for the query', @{ 'Namespace' = $Namespace; })));
    }

    [hashtable]$QueryArguments = @{
        'ClassName'   = $ClassName;
        'Namespace'   = $Namespace;
        'ErrorAction' = 'Stop';
    };

    if ([string]::IsNullOrEmpty($Filter) -eq $false) {
        $QueryArguments.Add('Filter', $Filter);
    }

    if ($Property.Count -ne 0) {
        $QueryArguments.Add('Property', [string[]]$Property);
    }

    [bool]$UseCimSession = ($null -ne $OperationOption -and $OperationOption.Count -ne 0);
    $CimSession          = $null;
    $CimOptions          = $null;

    try {
        if ($UseCimSession) {
            # Get-CimInstance cannot pass provider-specific custom options such as the
            # NetSecurity 'PolicyStore', so the query runs as WQL through a local
            # CimSession with CimOperationOptions instead.
            [string]$SelectList = '*';

            if ($Property.Count -ne 0) {
                $SelectList = [string]::Join(', ', [string[]]$Property);
            }

            [string]$Query = [string]::Format('SELECT {0} FROM {1}', $SelectList, $ClassName);

            if ([string]::IsNullOrEmpty($Filter) -eq $false) {
                $Query = [string]::Format('{0} WHERE {1}', $Query, $Filter);
            }

            $CimOptions = New-Object -TypeName 'Microsoft.Management.Infrastructure.Options.CimOperationOptions';

            foreach ($OptionName in $OperationOption.Keys) {
                $CimOptions.SetCustomOption([string]$OptionName, $OperationOption[$OptionName], $false);
            }

            $CimSession       = New-CimSession -ErrorAction Stop;
            [array]$Instances = @($CimSession.QueryInstances($Namespace, 'WQL', $Query, $CimOptions));
        } else {
            [array]$Instances = @(Get-CimInstance @QueryArguments);
        }
    } catch {
        # A CimSession method call wraps the CimException into a RuntimeException;
        # unwrap it so the native error code maps the same way as for Get-CimInstance.
        $CimError = $_.Exception;

        while ($null -ne $CimError.InnerException -and $null -eq $CimError.PSObject.Properties['NativeErrorCode']) {
            $CimError = $CimError.InnerException;
        }

        [hashtable]$NativeErrorCodes = @{
            'InvalidClass'     = 'WindowsInformationClassUnknown';
            'InvalidNamespace' = 'WindowsInformationNamespaceInvalid';
            'AccessDenied'     = 'WindowsInformationAccessDenied';
            'InvalidQuery'     = 'WindowsInformationInvalidQuery';
            'NoSuchProperty'   = 'WindowsInformationInvalidQuery';
            'InvalidParameter' = 'WindowsInformationInvalidQuery';
        };

        [string]$NativeErrorCode     = [string]$CimError.NativeErrorCode;
        [string]$ReturnCode          = 'WindowsInformationQueryFailed';

        if ($NativeErrorCodes.ContainsKey($NativeErrorCode)) {
            $ReturnCode = $NativeErrorCodes[$NativeErrorCode];
        }

        [hashtable]$ErrorData = @{
            'ClassName'       = $ClassName;
            'Namespace'       = $Namespace;
            'Filter'          = $Filter;
            'OperationOption' = $OperationOption;
            'Error'           = $CimError.Message;
        };

        Set-InternalExitCodes;

        [string]$CodeMessage  = (Get-GlobalRuntimeVariable).Public.ReturnCodes[$ReturnCode].Message;
        [string]$ErrorMessage = [string]::Format('{0}: Class "{1}", Namespace "{2}": {3}', $CodeMessage, $ClassName, $Namespace, ([string]$CimError.Message).Trim());

        return (Write-FunctionReturnValue -ReturnValue $ReturnCode -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new($ReturnCode, $ErrorMessage, $ErrorData)));
    } finally {
        if ($null -ne $CimSession) {
            $CimSession.Dispose();
        }

        if ($null -ne $CimOptions) {
            $CimOptions.Dispose();
        }
    }

    # The leading comma keeps the instances an array, even for one or no instance.
    return ,(Write-FunctionReturnValue -ReturnValue 'WindowsInformationQueried' -Data @{ 'ClassName' = $ClassName; 'Namespace' = $Namespace; 'Count' = $Instances.Count; } -OverrideReturn $Instances);
}

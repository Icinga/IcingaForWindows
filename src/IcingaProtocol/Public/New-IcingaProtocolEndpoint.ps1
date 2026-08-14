<#
.SYNOPSIS
Creates a new Icinga Protocol endpoint configuration object.

.DESCRIPTION
Creates a hashtable representing an Icinga Protocol endpoint with the specified Name, Address, and Port.
This object is typically passed into New-IcingaProtocolEnvironment.

.PARAMETER Name
| Name | Type          | Description                                | Default |
|------|---------------|--------------------------------------------|---------|
| Name | System.String | The human-readable name of the endpoint.   |         |

.PARAMETER Address
| Name    | Type          | Description                                | Default |
|---------|---------------|--------------------------------------------|---------|
| Address | System.String | The IP address or FQDN of the endpoint.    |         |

.PARAMETER Port
| Name | Type         | Description                                | Default |
|------|--------------|--------------------------------------------|---------|
| Port | System.Int32 | The TCP port to connect to.                |         |

.OUTPUTS
System.Collections.Hashtable — Returns a hashtable with the endpoint configuration.

.EXAMPLE
PS> New-IcingaProtocolEndpoint -Name 'Master1' -Address '192.168.1.10' -Port 5665

Creates a new endpoint object for Master1.

.NOTES
This object is required for configuring the Icinga environment structure.
#>
function New-IcingaProtocolEndpoint()
{
    param (
        [string]$Name,
        [string]$Address,
        [int]$Port
    );

    return @{
        'Name'    = $Name;
        'Address' = $Address;
        'Port'    = $Port;
    };
}

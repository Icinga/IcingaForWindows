<#
.SYNOPSIS
Adds or updates a TcpClient entry in the global IcingaProtocol connections table.

.DESCRIPTION
Add-IcingaProtocolClient inserts a System.Net.Sockets.TcpClient into the global
$Global:IcingaForWindows.Public.IcingaProtocol.Connections hashtable keyed by
the provided Address. If the Address already exists, the function replaces the
existing entry with the supplied TcpClient. If the Address does not exist, a new
entry is added.

The function performs basic parameter validation and uses Write-FunctionReturnValue
to emit a standardized operation result object indicating success or failure.

.PARAMETER Address
| Name    | Type          | Description                                                                                | Default |
|---------|---------------|--------------------------------------------------------------------------------------------|---------|
| Address | System.String | String key (typically an IP address) used to index the TcpClient in the connections table. | $null   |

.PARAMETER TcpClient
| Name      | Type                         | Description                                                  | Default |
|-----------|------------------------------|--------------------------------------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Active TcpClient instance to store in the connections table. | $null   |

.EXAMPLE
PS> $tcp = New-Object System.Net.Sockets.TcpClient
PS> $tcp.Connect('10.0.0.5', 5665)
PS> Add-IcingaProtocolClient -Address '10.0.0.5' -TcpClient $tcp

.EXAMPLE
PS> Add-IcingaProtocolClient -Address '10.0.0.5' -TcpClient $newTcp

Replaces an existing connection entry for the same address with a new TcpClient.

.OUTPUTS
PSCustomObject -- Return value produced by Write-FunctionReturnValue.
Possible tokens: IcingaClientAddingFailed (validation failed) or IcingaClientAdded (success).

.NOTES
This function modifies $Global:IcingaForWindows.Public.IcingaProtocol.Connections directly.
The caller is responsible for the lifetime and disposal of the TcpClient objects.
No additional connectivity checks are performed; the function only stores the provided instance.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Add-IcingaProtocolClient()
{
    param (
        [string]$Address                         = $null,
        [System.Net.Sockets.TcpClient]$TcpClient = $null
    );

    # Validate parameters
    if ([string]::IsNullOrEmpty($Address) -or $null -eq $TcpClient) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaClientAddingFailed' -Data @{ 'Address' = $Address; 'TcpClient' = $TcpClient });
    }

    if ($Global:IcingaForWindows.Public.IcingaProtocol.Connections.ContainsKey($Address)) {
        # Remove the stale entry
        $Global:IcingaForWindows.Public.IcingaProtocol.Connections[$Address] = $null;
        # Update the entry with the new client
        $Global:IcingaForWindows.Public.IcingaProtocol.Connections[$Address] = $TcpClient;
    } else {
        # Add new entry
        $Global:IcingaForWindows.Public.IcingaProtocol.Connections.Add($Address, $TcpClient);
    }

    # Log the new client addition
    return (Write-FunctionReturnValue -ReturnValue 'IcingaClientAdded' -Data @{ 'Address' = $Address; 'TcpClient' = $TcpClient });
}

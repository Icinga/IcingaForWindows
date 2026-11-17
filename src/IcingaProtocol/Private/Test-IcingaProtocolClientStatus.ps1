<#
.SYNOPSIS
Validates the status of an Icinga protocol TCP client for the specified address and optionally registers a new connection.

.DESCRIPTION
Test-IcingaProtocolClientStatus examines the global Icinga for Windows protocol connection table to determine whether a TCP client for the provided Address is present and connected. If Address is null or empty, the function returns an invalid-address result. If a connection entry exists, the function checks the client object and its Connected property and returns a corresponding status. If no entry exists, the function attempts to add a new entry to the global connection table using the $TcpClient variable from the current scope and returns a created status.

.PARAMETER Address
| Name    | Type          | Description                                                                   | Default |
|---------|---------------|-------------------------------------------------------------------------------|---------|
| Address | System.String | IP address string used to look up the client in the global connections table. | $null   |

.OUTPUTS
PSCustomObject -- Standardized result object from Write-FunctionReturnValue.
Possible tokens: IcingaAddressInvalid, IcingaClientReplaced, IcingaClientConnected, IcingaClientCreated.

.EXAMPLE
PS> Test-IcingaProtocolClientStatus -Address '10.0.0.5'

Checks the connection table for the given address and returns the appropriate status token.

.EXAMPLE
PS> Test-IcingaProtocolClientStatus

Returns IcingaAddressInvalid when no Address is provided.

.NOTES
- Side effects: when no existing connection entry is found the function adds a new entry to
    $Global:IcingaForWindows.Public.IcingaProtocol.Connections using the $TcpClient variable from the caller's scope.
- Precondition: $Global:IcingaForWindows.Public.IcingaProtocol.Connections must be an initialized hashtable or dictionary-like object that supports ContainsKey(), indexing, and Add().
- The function relies on client objects exposing a Connected property to determine connectivity.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Test-IcingaProtocolClientStatus()
{
    param (
        [string]$Address = $null
    );

    # If no client is provided, return true - we cannot use this object
    if ([string]::IsNullOrEmpty($Address)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaAddressInvalid');
    }

    # Check if we have an existing connection entry for this client
    if ($Global:IcingaForWindows.Public.IcingaProtocol.Connections.ContainsKey($Address)) {
        # Check if the client object is still valid and present
        $KnownTcpClient    = $Global:IcingaForWindows.Public.IcingaProtocol.Connections[$Address];

        [bool]$IsConnected = $false;
        if ($null -ne $KnownTcpClient -and $null -ne $KnownTcpClient.Client -and $KnownTcpClient.Connected) {
            try {
                # In .NET, TcpClient.Connected only reflects the state of the last I/O operation.
                # Check Poll for SelectRead with Available == 0 to detect if remote socket was closed/disconnected.
                if (-not ($KnownTcpClient.Client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $KnownTcpClient.Client.Available -eq 0)) {
                    $IsConnected = $true;
                }
            } catch {
                $IsConnected = $false;
            }
        }

        if (-not $IsConnected) {
            return (Write-FunctionReturnValue -ReturnValue 'IcingaClientReplaced' -Data @{ 'Address' = $Address; });
        } else {
            # Client is still valid
            return (Write-FunctionReturnValue -ReturnValue 'IcingaClientConnected' -Data @{ 'Address' = $Address; });
        }
    }

    # No existing entry, add new one
    $Global:IcingaForWindows.Public.IcingaProtocol.Connections.Add($Address, $TcpClient);
    return (Write-FunctionReturnValue -ReturnValue 'IcingaClientCreated' -Data @{ 'Address' = $Address; });
}

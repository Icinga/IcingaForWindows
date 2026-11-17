<#
.SYNOPSIS
Register a new TcpClient and open its SSL stream.

.DESCRIPTION
`Update-TCPConnection` sets the provided `TcpClient` into the runtime private
TCP container and calls `Open-SSLStream` to wrap and authenticate the connection
as client or server depending on the `IsClient` flag.

.PARAMETER Client
| Name   | Type                         | Description                               | Default |
|--------|------------------------------|-------------------------------------------|---------|
| Client | System.Net.Sockets.TcpClient | Connected TCP client instance to register | $null   |

.PARAMETER Endpoint
| Name     | Type          | Description                                     | Default |
|----------|---------------|-------------------------------------------------|---------|
| Endpoint | System.String | Remote endpoint name (used for client SSL auth) | $null   |

.PARAMETER IsClient
| Name     | Type                   | Description                                     | Default |
|----------|------------------------|-------------------------------------------------|---------|
| IsClient | System.SwitchParameter | When set perform client-side SSL authentication | $false  |

.OUTPUTS
None -- Result codes from `Open-SSLStream` are forwarded via `Write-FunctionReturnValue`.

.EXAMPLE
PS> Update-TCPConnection -Client $c -Endpoint 'example.com' -IsClient

.NOTES
Validates `$Client` and returns `UpdateTcpClientInvalid` when missing.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Update-TCPConnection()
{
    param (
        [System.Net.Sockets.TcpClient]$Client = $null,
        [string]$Endpoint                     = $null,
        [switch]$IsClient                     = $false
    );

    if ($null -eq $Client) {
        return (Write-FunctionReturnValue -ReturnValue 'UpdateTcpClientInvalid' -Data @{ 'Endpoint' = $Endpoint; 'IsClient' = $IsClient });
    }

    # Our Tcp client is valid, set it globally
    (Get-GlobalRuntimeVariable).Private.TCP.Client = $Client;

    # Open an SslStream for this connection and share the setting if we are a client and the name of the endpoint
    # We connected to. This is needed for Ssl authentication with the server certificate for the TCP Protocol.
    return (Open-SSLStream -IsClient:$IsClient -Endpoint $Endpoint);
}

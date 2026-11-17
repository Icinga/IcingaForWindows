<#
.SYNOPSIS
Format a `TcpClient` for console logging.

.DESCRIPTION
`Format-LoggingConsoleTcpClient` returns a formatted representation of a
`System.Net.Sockets.TcpClient`, including connection status and endpoints.

.PARAMETER Client
| Name   | Type                         | Description                       | Default |
|--------|------------------------------|-----------------------------------|---------|
| Client | System.Net.Sockets.TcpClient | The TCP client instance to format |         |

.PARAMETER Indent
| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | ''      |

.OUTPUTS
System.String -- A formatted multi-line description of the `TcpClient`.

.EXAMPLE
PS> Format-LoggingConsoleTcpClient -Client $client

.NOTES
This helper uses `Format-LoggingConsoleObjectProperties` for property extraction.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Format-LoggingConsoleTcpClient()
{
    param (
        [System.Net.Sockets.TcpClient]$Client = $null,
        [string]$Indent                       = ''
    );

    # If the client is null, return the formatted null value
    if ($null -eq $Client) {
        return (Format-LoggingConsoleNullValue -Indent $Indent);
    }

    return (
        Format-LoggingConsoleObjectProperties `
            -Object $Client `
            -Properties @('Connected', 'Client.LocalEndPoint', 'Client.RemoteEndPoint') `
            -Indent $Indent
    );
}

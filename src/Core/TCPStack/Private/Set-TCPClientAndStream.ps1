<#
.SYNOPSIS
Set the global TCP client and SSL stream references

.DESCRIPTION
`Set-TCPClientAndStream` assigns the provided `TcpClient` and `SslStream`
instances into the runtime private TCP container so other helpers can access them.

.PARAMETER TcpClient
| Name      | Type                         | Description                       | Default |
|-----------|------------------------------|-----------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | The connected TCP client instance | $null   |

.PARAMETER SslStream
| Name      | Type                          | Description                                         | Default |
|-----------|-------------------------------|-----------------------------------------------------|---------|
| SslStream | System.Net.Security.SslStream | The SSL stream wrapping the client's network stream | $null   |

.OUTPUTS
None -- Updates the `TcpClient` and `SslStream` references in `(Get-GlobalRuntimeVariable).Private.TCP`.

.EXAMPLE
PS> Set-TCPClientAndStream -TcpClient $c -SslStream $s

.NOTES
This is a trivial assignment helper used after connection establishment.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Set-TCPClientAndStream()
{
    param (
        [System.Net.Sockets.TcpClient]$TcpClient  = $null,
        [System.Net.Security.SslStream]$SslStream = $null
    );

    $GlobalVariable                    = Get-GlobalRuntimeVariable;

    $GlobalVariable.Private.TCP.Client = $TcpClient;
    $GlobalVariable.Private.TCP.Stream = $SslStream;
}

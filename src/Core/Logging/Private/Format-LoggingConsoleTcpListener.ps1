<#
.SYNOPSIS
Format a `TcpListener` object for console logging.

.DESCRIPTION
`Format-LoggingConsoleTcpListener` extracts and formats selected properties of a
`System.Net.Sockets.TcpListener` and returns a colorized string for logging.

.PARAMETER TcpListener
| Name        | Type                           | Description            | Default |
|-------------|--------------------------------|------------------------|---------|
| TcpListener | System.Net.Sockets.TcpListener | The listener to format |         |

.PARAMETER Indent
| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | ''      |

.OUTPUTS
System.String -- A formatted string describing listener properties.

.EXAMPLE
PS> Format-LoggingConsoleTcpListener -TcpListener $listener

.NOTES
Used to present network listener details consistently in logs.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Format-LoggingConsoleTcpListener()
{
    param (
        [System.Net.Sockets.TcpListener]$TcpListener = $null,
        [string]$Indent                              = ''
    );

    # If the socket is null, return the formatted null value
    if ($null -eq $TcpListener) {
        return (Format-LoggingConsoleNullValue -Indent $Indent);
    }

    return (
        Format-LoggingConsoleObjectProperties `
            -Object $TcpListener `
            -Properties @('LocalEndpoint', 'ExclusiveAddressUse') `
            -Indent $Indent
    );
}

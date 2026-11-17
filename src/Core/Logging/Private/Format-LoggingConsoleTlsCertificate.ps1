<#
.SYNOPSIS
Format an X509 certificate for console logging.

.DESCRIPTION
`Format-LoggingConsoleTlsCertificate` extracts a set of useful properties from a
`System.Security.Cryptography.X509Certificates.X509Certificate2` and returns
them as a colorized multi-line string for inclusion in logs.

.PARAMETER Certificate
| Name        | Type                                                           | Description           | Default |
|-------------|----------------------------------------------------------------|-----------------------|---------|
| Certificate | System.Security.Cryptography.X509Certificates.X509Certificate2 | Certificate to format |         |

.PARAMETER Indent
| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | ''      |

.OUTPUTS
System.String -- A formatted representation of the certificate.

.EXAMPLE
PS> Format-LoggingConsoleTlsCertificate -Certificate $cert

.NOTES
Useful when logging TLS connection metadata.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Format-LoggingConsoleTlsCertificate()
{
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate = $null,
        [string]$Indent                                                              = ''
    );

    # If the certificate is null, return the formatted null value
    if ($null -eq $Certificate) {
        return (Format-LoggingConsoleNullValue -Indent $Indent);
    }

    return (
        Format-LoggingConsoleObjectProperties `
            -Object $Certificate `
            -Properties @('Archived', 'FriendlyName', 'HasPrivateKey', 'Issuer', 'Subject', 'NotBefore', 'NotAfter', 'Thumbprint') `
            -Indent $Indent
    );
}

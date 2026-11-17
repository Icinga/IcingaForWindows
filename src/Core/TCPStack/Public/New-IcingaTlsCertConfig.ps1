<#
.SYNOPSIS
Create an Icinga TLS certificate configuration object

.DESCRIPTION
Returns a standardized TLS certificate configuration object by delegating to
`New-TlsCertConfig`. This wrapper supplies Icinga-specific defaults for the
certificate store and store location while allowing callers to specify a
certificate file, thumbprint, CN, issuer, or alternative store settings.

.PARAMETER CertPath
| Name     | Type          | Description                                     | Default |
|----------|---------------|-------------------------------------------------|---------|
| CertPath | System.String | Path to a PKCS#12/PFX certificate file to load. |         |

.PARAMETER CertThumbprint
| Name           | Type          | Description                                                   | Default |
|----------------|---------------|---------------------------------------------------------------|---------|
| CertThumbprint | System.String | Thumbprint of a certificate to locate in a certificate store. |         |

.PARAMETER CertCN
| Name   | Type          | Description                                                  | Default |
|--------|---------------|--------------------------------------------------------------|---------|
| CertCN | System.String | Common Name (CN) to match when searching certificate stores. |         |

.PARAMETER CertStore
| Name      | Type          | Description                                     | Default |
|-----------|---------------|-------------------------------------------------|---------|
| CertStore | System.String | Certificate store name (for example: My, Root). | My      |

.PARAMETER CertStoreLocation
| Name              | Type          | Description                                                          | Default      |
|-------------------|---------------|----------------------------------------------------------------------|--------------|
| CertStoreLocation | System.String | Certificate store location (for example: LocalMachine, CurrentUser). | LocalMachine |

.PARAMETER CertIssuer
| Name       | Type         | Description                                                       | Default |
|------------|--------------|-------------------------------------------------------------------|---------|
| CertIssuer | System.Array | Array of issuer names to match when searching certificate stores. |         |

.OUTPUTS
System.Object -- TLS certificate configuration object for the TCP stack, returned from `New-TlsCertConfig`.

.EXAMPLE
PS> New-IcingaTlsCertConfig -CertPath 'C:\certs\icinga.pfx'

.NOTES
This function is a thin Icinga-specific wrapper around `New-TlsCertConfig`. Refer to
`New-TlsCertConfig` for full validation rules and additional options. At least one of
CertPath, CertThumbprint, CertCN or CertIssuer must be supplied.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-IcingaTlsCertConfig()
{
    param (
        [string]$CertPath          = $null,
        [string]$CertThumbprint    = $null,
        [string]$CertCN            = $null,
        [string]$CertStore         = 'My',
        [string]$CertStoreLocation = 'LocalMachine',
        [array]$CertIssuer         = $null
    );

    return (
        New-TlsCertConfig `
            -CertPath $CertPath `
            -CertThumbprint $CertThumbprint `
            -CertCN $CertCN `
            -CertStore $CertStore `
            -CertStoreLocation $CertStoreLocation `
            -CertIssuer $CertIssuer
    );
}

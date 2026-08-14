<#
.SYNOPSIS
Create a TLS certificate configuration object

.DESCRIPTION
`New-TlsCertConfig` builds a PSCustomObject that describes how to locate a
TLS certificate, either by file path, thumbprint or search filters (CN/Issuer).
It validates that at least one selector is provided.

.PARAMETER CertPath
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CertPath | System.String | Optional filesystem path to a certificate file | $null |

.PARAMETER CertThumbprint
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CertThumbprint | System.String | Thumbprint to locate certificate in store | $null |

.PARAMETER CertCN
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CertCN | System.String | Common Name filter for certificate store search | $null |

.PARAMETER CertStore
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CertStore | System.String | Certificate store name (e.g. 'My') | 'My' |

.PARAMETER CertStoreLocation
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CertStoreLocation | System.String | Store location (e.g. 'LocalMachine') | 'LocalMachine' |

.PARAMETER CertIssuer
| Name | Type | Description | Default |
|------|------|-------------|---------|
| CertIssuer | System.Array | Array of issuer names to match when searching certificate stores | $null |

.OUTPUTS
System.Management.Automation.PSCustomObject — Constructed TLS configuration object, returned via `Write-FunctionReturnValue`.

.EXAMPLE
PS> New-TlsCertConfig -CertThumbprint 'ABCDEF...'

.NOTES
At least one of `CertPath`, `CertThumbprint`, `CertCN` or `CertIssuer` must be provided.
#>
function New-TlsCertConfig()
{
    param (
        [string]$CertPath          = $null,
        [string]$CertThumbprint    = $null,
        [string]$CertCN            = $null,
        [string]$CertStore         = 'My',
        [string]$CertStoreLocation = 'LocalMachine',
        [array]$CertIssuer         = $null
    );

    # Now check if required parameters are provided. We either need a path or thumbprint or use the filter for Issuer and CN.
    # For anything but CertPath, we also need to provide Store and StoreLocation.
    if ([string]::IsNullOrEmpty($CertPath) -and [string]::IsNullOrEmpty($CertThumbprint) -and [string]::IsNullOrEmpty($CertCN) -and [string]::IsNullOrEmpty($CertIssuer)) {
        return (Write-FunctionReturnValue -ReturnValue 'NoTlsCertConfigProvided');
    }

    $TlsCertConfig = [PSCustomObject]@{
        'CertPath'          = $CertPath;
        'CertThumbprint'    = $CertThumbprint;
        'CertCN'            = $CertCN;
        'CertStore'         = $CertStore;
        'CertStoreLocation' = $CertStoreLocation;
        'CertIssuer'        = $CertIssuer;
    };

    return (Write-FunctionReturnValue -ReturnValue 'TlsCertConfigCreated' -Data @{ 'TlsCertConfig' = $TlsCertConfig } -OverrideReturn $TlsCertConfig);
}

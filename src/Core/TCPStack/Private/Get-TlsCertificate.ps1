<#
.SYNOPSIS
Load a TLS certificate from path or certificate store according to config.

.DESCRIPTION
`Get-TlsCertificate` attempts to load a certificate based on the provided
TLS configuration object. It supports loading from a file path or by searching
the specified certificate store using thumbprint, common name or issuer filters.

.PARAMETER TlsCertConfig
| Name | Type | Description | Default |
|------|------|-------------|---------|
| TlsCertConfig | System.PSCustomObject | Configuration describing how to locate the certificate | |

.OUTPUTS
System.Security.Cryptography.X509Certificates.X509Certificate2 — The loaded certificate, or $null on failure.

.EXAMPLE
PS> Get-TlsCertificate -TlsCertConfig $cfg

.NOTES
Uses `Write-FunctionReturnValue` to report detailed result codes for callers.
#>
function Get-TlsCertificate()
{
    param (
        [PSCustomObject]$TlsCertConfig = $null
    );

    if ($null -eq $TlsCertConfig) {
        return (Write-FunctionReturnValue -ReturnValue 'NoTlsCertConfigProvidedForLoader' -OverrideReturn $null);
    }

    # If a CertPath is provided, load the certificate from there.
    if (-not [string]::IsNullOrEmpty($TlsCertConfig.CertPath) -and (Test-Path -Path $TlsCertConfig.CertPath)) {
        try {
            $Cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList $TlsCertConfig.CertPath;
        } catch {
            return (Write-FunctionReturnValue -ReturnValue 'TlsCertLoadFromPathFailed' -Data @{ 'CertPath' = $TlsCertConfig.CertPath; 'Exception' = $_.Exception } -OverrideReturn $null);
        }

        return (Write-FunctionReturnValue -ReturnValue 'TlsCertLoadedFromPath' -Data @{ 'Certificate' = $Cert } -OverrideReturn $Cert);
    }

    # Otherwise, try to load from the certificate store using the provided parameters.
    try {
        $Store = New-Object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $TlsCertConfig.CertStore, $TlsCertConfig.CertStoreLocation;
        $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly);

        try {
            $Certs = $Store.Certificates;

            if (-not [string]::IsNullOrEmpty($TlsCertConfig.CertThumbprint)) {
                $FilteredCerts = $Certs | Where-Object { $_.Thumbprint -eq $TlsCertConfig.CertThumbprint };
            } else {
                $FilteredCerts = $Certs | Where-Object {
                    ($_.Subject -like "*CN=$($TlsCertConfig.CertCN)*") -and
                    ($_.Issuer -like "*$($TlsCertConfig.CertIssuer)*")
                };
            }

            if ($FilteredCerts.Count -eq 0) {
                return (Write-FunctionReturnValue -ReturnValue 'TlsCertNotFoundInStore' -Data @{ 'TlsCertConfig' = $TlsCertConfig } -OverrideReturn $null);
            }

            # Return the first matching certificate.
            $Cert = $FilteredCerts[0];
            return (Write-FunctionReturnValue -ReturnValue 'TlsCertLoadedFromStore' -Data @{ 'Certificate' = $Cert } -OverrideReturn $Cert);
        } finally {
            $Store.Close();
        }
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'TlsCertLoadFromStoreFailed' -Data @{ 'TlsCertConfig' = $TlsCertConfig; 'Exception' = $_.Exception } -OverrideReturn $null);
    }

    # If we reach here, something went wrong. Shouldn't happen
    return (Write-FunctionReturnValue -ReturnValue 'TlsCertLoadFailedUnknownReason' -Data @{ 'TlsCertConfig' = $TlsCertConfig } -OverrideReturn $null);
}

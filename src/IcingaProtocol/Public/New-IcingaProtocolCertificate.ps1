<#
.SYNOPSIS
Generate a self-signed certificate or merge an existing private key with a signed certificate

.DESCRIPTION
New-IcingaProtocolCertificate generates a 4096-bit RSA self-signed TLS
certificate valid for 3 months for the specified Common Name (CN). If the
SignedCert parameter is provided, it instead extracts the existing RSA private
key and merges it with the signed PEM certificate.

Depending on the operating system, the certificate is either stored exclusively
in Cert:\CurrentUser\My on Windows (automatically replacing any previous
self-signed or Icinga-issued certificate for the same CN) or written to disk as
a passwordless PKCS#12 (.pfx) file under Get-ModuleCertificateDirectory on
Linux and macOS.

.PARAMETER CommonName
| Name       | Type          | Description                               | Default |
|------------|---------------|-------------------------------------------|---------|
| CommonName | System.String | The common name (CN) for the certificate. | $null   |

.PARAMETER SignedCert
| Name       | Type          | Description                           | Default |
|------------|---------------|---------------------------------------|---------|
| SignedCert | System.String | The PEM-formatted signed certificate. | $null   |

.OUTPUTS
System.Int32 -- Standardized return code from Write-FunctionReturnValue (50011
when stored in Cert:\CurrentUser\My on Windows, 50010 when stored locally as a
.pfx file on Linux/macOS, 50009 when -CommonName is missing or whitespace, or
50012 when the existing certificate cannot be found during a -SignedCert merge).

.EXAMPLE
PS> New-IcingaProtocolCertificate -CommonName 'win-srv01.example.com'

Generates a new self-signed certificate for 'win-srv01.example.com' and stores
it in Cert:\CurrentUser\My on Windows or as a local .pfx file on Linux/macOS.

.EXAMPLE
PS> New-IcingaProtocolCertificate -CommonName 'win-srv01.example.com' -SignedCert '-----BEGIN CERTIFICATE-----...'

Merges the signed PEM certificate with the existing private key for
'win-srv01.example.com' and replaces the stored certificate.

.NOTES
Stores Windows certificates in Cert:\CurrentUser\My of the executing user
account (does not require LocalMachine store elevation; ensure certificate
provisioning and the Icinga for Windows runtime execute under the same Windows
user account). On non-Windows platforms, Get-ModuleCertificateDirectory is
created automatically before writing <CommonName>.pfx.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-IcingaProtocolCertificate()
{
    param (
        [string]$CommonName = $null,
        [string]$SignedCert = $null
    );

    if ([string]::IsNullOrWhiteSpace($CommonName)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaCertCommonNameMissing' -Data @{ 'CommonName' = $CommonName; });
    }

    $CommonName            = $CommonName.Trim();
    [string]$CertDirectory = Get-ModuleCertificateDirectory;
    [string]$PfxPath       = Join-Path -Path $CertDirectory -ChildPath ([string]::Format('{0}.pfx', $CommonName));
    [byte[]]$pfxBytes      = $null;

    if ([string]::IsNullOrEmpty($SignedCert)) {
        # Generate a new 4096-bit RSA private key
        $rsa      = [System.Security.Cryptography.RSA]::Create(4096);

        # Create a new certificate request for the given Common Name
        $req      = [System.Security.Cryptography.X509Certificates.CertificateRequest]::New(
            [string]::Format('CN={0}', $CommonName),
            $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        );

        # Create the self-signed certificate, valid for 3 months
        $cert     = $req.CreateSelfSigned([System.DateTimeOffset]::Now, [System.DateTimeOffset]::Now.AddMonths(3));

        # Export the certificate as a PFX/PKCS#12 payload.
        # By not providing a password string, the PFX is generated without password encryption.
        $pfxBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx);

        $cert.Dispose();
        $rsa.Dispose();
    } else {
        $oldCert = $null;

        if ((Get-GlobalRuntimeVariable).Protected.OSType -eq 'Windows') {
            # On Windows, the old certificate is never written to disk, so we load it from the store
            $tempStore = [System.Security.Cryptography.X509Certificates.X509Store]::new(
                [System.Security.Cryptography.X509Certificates.StoreName]::My,
                [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
            );
            $tempStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly);

            foreach ($c in $tempStore.Certificates) {
                if ($c.Subject -eq [string]::Format('CN={0}', $CommonName) -and $c.HasPrivateKey -and ($c.Issuer -eq $c.Subject -or $c.Issuer -match 'Icinga')) {
                    $oldCert = $c;
                    break;
                }
            }
            $tempStore.Close();
            $tempStore.Dispose();

            if ($null -eq $oldCert) {
                return (Write-FunctionReturnValue -ReturnValue 'IcingaCertMissingForMerge' -Data @{ 'Path' = 'Cert:/CurrentUser/My'; });
            }
        } else {
            # On Linux/macOS, we load the old certificate from the locally stored PFX file
            if (-not (Test-Path -Path $PfxPath)) {
                return (Write-FunctionReturnValue -ReturnValue 'IcingaCertMissingForMerge' -Data @{ 'Path' = $PfxPath; });
            }

            $oldCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $PfxPath,
                [string]::Empty,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
            );
        }

        # Extract the private key
        $privKey       = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($oldCert);

        # Load the newly received CRT/PEM certificate from Icinga
        $newCertBytes  = [System.Text.Encoding]::UTF8.GetBytes($SignedCert);
        $newPublicCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($newCertBytes);

        # Merge the extracted private key into the new, signed certificate
        $mergedCert    = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($newPublicCert, $privKey);

        # Export the merged certificate as PFX (without password)
        $pfxBytes      = $mergedCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx);

        $oldCert.Dispose();
        $newPublicCert.Dispose();
        $mergedCert.Dispose();
        $privKey.Dispose();
    }

    # Handle storage based on OS
    if ((Get-GlobalRuntimeVariable).Protected.OSType -ne 'Windows') {
        if (-not (Test-Path -Path $CertDirectory)) {
            New-Item -Path $CertDirectory -ItemType Directory -Force | Out-Null;
        }

        # Store the certificate on the filesystem for non-Windows OS
        [System.IO.File]::WriteAllBytes($PfxPath, $pfxBytes);

        return (Write-FunctionReturnValue -ReturnValue 'IcingaCertStoredLocally' -Data @{ 'CommonName' = $CommonName; 'Path' = $PfxPath; });
    } else {
        # Open the Windows certificate store
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
            [System.Security.Cryptography.X509Certificates.StoreName]::My,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser
        );
        $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite);

        # Remove existing certificates with matching Subject to avoid duplicates.
        # We check that the Issuer is either the same as the Subject (self-signed)
        # or contains 'Icinga' to avoid deleting unrelated certificates (like CA certs).
        foreach ($existingCert in $store.Certificates) {
            if ($existingCert.Subject -eq [string]::Format('CN={0}', $CommonName)) {
                if ($existingCert.Issuer -eq $existingCert.Subject -or $existingCert.Issuer -match 'Icinga') {
                    $store.Remove($existingCert);
                }
            }
        }

        # Load the certificate from the generated PFX bytes using an empty string as password.
        # PersistKeySet is required to ensure the private key is permanently stored in the cert store.
        $storeCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $pfxBytes,
            [string]::Empty,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
        );

        $store.Add($storeCert);
        $store.Close();
        $store.Dispose();
        $storeCert.Dispose();

        return (Write-FunctionReturnValue -ReturnValue 'IcingaCertStoredCertStore' -Data @{ 'CommonName' = $CommonName; 'Path' = 'Cert:/CurrentUser'; });
    }
}

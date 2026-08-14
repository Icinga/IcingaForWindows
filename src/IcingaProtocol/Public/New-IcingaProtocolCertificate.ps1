<#
.SYNOPSIS
Generate a self-signed certificate or merge an existing private key with a signed certificate.

.DESCRIPTION
New-IcingaProtocolCertificate generates a new self-signed RSA certificate
for the specified Common Name (CN). If the SignedCert parameter is provided,
it instead merges the signed PEM certificate with the existing private key.
Depending on the operating system, the certificate is either saved exclusively
to the Windows certificate store (on Windows) or written to the filesystem as
a passwordless PFX file (on Linux/macOS). When merging on Windows, the old
certificate is removed from the store automatically.

.PARAMETER CommonName
| Name       | Type          | Description                                | Default |
|------------|---------------|--------------------------------------------|---------|
| CommonName | System.String | The common name (CN) for the certificate.  | $null   |

.PARAMETER SignedCert
| Name       | Type          | Description                                | Default |
|------------|---------------|--------------------------------------------|---------|
| SignedCert | System.String | The PEM-formatted signed certificate.      | $null   |

.OUTPUTS
System.Object — Returns a structured result via Write-FunctionReturnValue containing the storage path.

.EXAMPLE
PS> New-IcingaProtocolCertificate -CommonName 'IcingaNode'

Generates a new self-signed certificate for 'IcingaNode' and saves it to the local store or filesystem.

.EXAMPLE
PS> New-IcingaProtocolCertificate -CommonName 'IcingaNode' -SignedCert '-----BEGIN CERTIFICATE-----...'

Merges the signed certificate with the existing private key for 'IcingaNode'.

.NOTES
Requires administrative privileges on Windows to access the LocalMachine certificate store.
Cross-platform compatible; relies on .NET cryptography classes.
#>
function New-IcingaProtocolCertificate()
{
    param (
        [string]$CommonName = $null,
        [string]$SignedCert = $null
    );

    if ([string]::IsNullOrEmpty($CommonName)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaCertCommonNameMissing' -Data @{ 'CommonName' = $CommonName; });
    }

    [string]$PfxPath  = Join-Path -Path (Get-ModuleCertificateDirectory) -ChildPath ([string]::Format('{0}.pfx', $CommonName));
    [byte[]]$pfxBytes = $null;

    if ([string]::IsNullOrEmpty($SignedCert)) {
        # Generate a new 4096-bit RSA private key
        $rsa  = [System.Security.Cryptography.RSA]::Create(4096);

        # Create a new certificate request for the given Common Name
        $req  = [System.Security.Cryptography.X509Certificates.CertificateRequest]::New(
            [string]::Format('CN={0}', $CommonName), 
            $rsa, 
            [System.Security.Cryptography.HashAlgorithmName]::SHA256, 
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        );

        # Create the self-signed certificate, valid for 3 months
        $cert = $req.CreateSelfSigned([System.DateTimeOffset]::Now, [System.DateTimeOffset]::Now.AddMonths(3));

        # Export the certificate as a PFX/PKCS#12 payload.
        # By not providing a password string, the PFX is generated without password encryption.
        $pfxBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx);
    } else {
        $oldCert = $null;

        if ($Global:IcingaForWindows.Protected.OSType -eq 'Windows') {
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
                return (Write-FunctionReturnValue -ReturnValue 'IcingaCertMissingForMerge' -Data @{ 'Path' = 'Cert:/CurrentUser/My' });
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
    if ($Global:IcingaForWindows.Protected.OSType -ne 'Windows') {
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

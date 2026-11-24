<#
.SYNOPSIS
Import the Icinga 2 CA certificate into the Windows LocalMachine Root store or local directory

.DESCRIPTION
Import-IcingaCertAuthority accepts an Icinga 2 CA certificate either as a
direct PEM string (-Certificate) or via a local file or HTTP/HTTPS URL (-Path).
On Windows, it imports the certificate into Cert:\LocalMachine\Root
(StoreName::Root, StoreLocation::LocalMachine), skipping import if a
certificate with the same thumbprint already exists. On Linux and macOS, it
writes the PEM certificate to ca.crt inside Get-ModuleCertificateDirectory.

.PARAMETER Certificate
| Name        | Type          | Description                               | Default |
|-------------|---------------|-------------------------------------------|---------|
| Certificate | System.String | The PEM-formatted CA certificate payload. |         |

.PARAMETER Path
| Name | Type          | Description                                       | Default |
|------|---------------|---------------------------------------------------|---------|
| Path | System.String | Local file path or HTTP/HTTPS URL to the CA cert. |         |

.OUTPUTS
System.Object -- Returns nothing ($null) when the CA certificate is imported or
written to disk, or a standardized System.Int32 error code from
Write-FunctionReturnValue (50013 IcingaCAImportPathNotfound when a local -Path
does not exist, or 50014 IcingaCAContentIsEmpty when the certificate payload is
empty or whitespace).

.EXAMPLE
PS> Import-IcingaCertAuthority -Path 'C:\Temp\ca.crt'

Imports the Icinga 2 CA certificate from a local file into Cert:\LocalMachine\Root
on Windows (or saves ca.crt locally on Linux/macOS).

.EXAMPLE
PS> Import-IcingaCertAuthority -Path 'https://icinga-master01.example.com/ca.crt'

Downloads and imports the Icinga 2 CA certificate from an HTTPS endpoint.

.NOTES
Requires administrative privileges on Windows to open Cert:\LocalMachine\Root
for read/write access.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Import-IcingaCertAuthority()
{
    param (
        [string]$Certificate,
        [string]$Path
    );

    # Resolve certificate content if a path was provided
    if (-not [string]::IsNullOrEmpty($Path)) {
        if ($Path -match '^https?://') {
            # Download from web path
            $Certificate = (Invoke-RestMethod -Uri $Path -UseBasicParsing).ToString();
        } else {
            # Read from local file
            if (-not (Test-Path -Path $Path)) {
                return (Write-FunctionReturnValue -ReturnValue 'IcingaCAImportPathNotfound' -Data @{ 'Path' = $Path; });
            }
            $Certificate = Get-Content -Path $Path -Raw;
        }
    }

    if ([string]::IsNullOrWhiteSpace($Certificate)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaCAContentIsEmpty');
    }

    if ($Global:IcingaForWindows.Protected.OSType -eq 'Windows') {
        # On Windows, import directly into the LocalMachine Root store
        $CertBytes = [System.Text.Encoding]::UTF8.GetBytes($Certificate);
        $CertObj   = [System.Security.Cryptography.X509Certificates.X509Certificate2]::New($CertBytes);

        $Store     = [System.Security.Cryptography.X509Certificates.X509Store]::New(
            [System.Security.Cryptography.X509Certificates.StoreName]::Root,
            [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
        );
        $Store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite);

        # Only add if it's not already in the store
        $Exists    = $false;
        foreach ($Existing in $Store.Certificates) {
            if ($Existing.Thumbprint -eq $CertObj.Thumbprint) {
                $Exists = $true;
                break;
            }
        }

        if (-not $Exists) {
            Write-LoggingEntry -Level 'Info' -Message 'Icinga CA does not exist in store, importing now.'
            $Store.Add($CertObj);
        }

        $Store.Close();
        $Store.Dispose();
        $CertObj.Dispose();
    } else {
        # On Linux/macOS, save it to the certificate directory
        $CertPath = Join-Path -Path (Get-ModuleCertificateDirectory) -ChildPath 'ca.crt';

        [void](New-Item -ItemType File -Path $CertPath -Force);
        [System.IO.File]::WriteAllText($CertPath, $Certificate, [System.Text.Encoding]::UTF8);

        Write-LoggingEntry -Level 'Info' -Message 'Saving Icinga CA to disk.'
    }
}

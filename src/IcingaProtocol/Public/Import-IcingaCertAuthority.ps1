<#
.SYNOPSIS
Import the Icinga CA certificate into the Windows CertificateAuthority store or local directory.

.DESCRIPTION
Import-IcingaCertAuthority accepts an Icinga CA certificate either as a direct
PEM string (-Certificate) or via a local/web path (-Path). Depending on the
operating system, it imports the certificate directly into the CurrentUser
CertificateAuthority store (on Windows) or saves it to the module's certificate
directory as 'ca.crt' (on Linux/macOS).

.PARAMETER Certificate
| Name        | Type          | Description                               | Default |
|-------------|---------------|-------------------------------------------|---------|
| Certificate | System.String | The PEM-formatted CA certificate payload. |         |

.PARAMETER Path
| Name | Type          | Description                                       | Default |
|------|---------------|---------------------------------------------------|---------|
| Path | System.String | Local file path or HTTP/HTTPS URL to the CA cert. |         |

.OUTPUTS
None -- Performs the import or file write without returning a value.

.EXAMPLE
PS> Import-IcingaCertAuthority -Certificate '-----BEGIN CERTIFICATE-----...'

Imports the CA certificate from a direct string payload.

.EXAMPLE
PS> Import-IcingaCertAuthority -Path 'https://icinga.example.com/ca.crt'

Downloads and imports the CA certificate from a web server.

.NOTES
Operates on the CurrentUser CertificateAuthority store to avoid Windows security prompts.
Does not require administrative elevation.

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

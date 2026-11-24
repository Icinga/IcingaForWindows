<#
.SYNOPSIS
Perform the base installation of Icinga for Windows on the local host

.DESCRIPTION
Install-IcingaForWindows trims -Hostname, initializes the internal return-code
table via Set-InternalExitCodes, creates the base Config and Binaries
directories under ProgramData (New-ModuleConfigEnvironment), registers all
IcingaForWindows::<Area> Windows Event Log sources with a 100 MiB maximum log
size (Register-LoggingWindowsEventLog), and generates an initial 4096-bit RSA
self-signed TLS certificate via New-IcingaProtocolCertificate.

The -Hostname value becomes the certificate Common Name (CN) and must match the
exact Endpoint and Host Object Name configured for this node in Icinga 2. The
-Hostname parameter is intentionally non-mandatory so automated callers receive
a standardized numeric return value (7000 InstallerHostnameMissing) via
Write-FunctionReturnValue instead of an interactive PowerShell parameter prompt
when -Hostname is omitted, empty, or whitespace.

.PARAMETER Hostname
| Name     | Type          | Description                                                                      | Default |
|----------|---------------|----------------------------------------------------------------------------------|---------|
| Hostname | System.String | Node Object Name (certificate Common Name) used to generate the TLS certificate. | $null   |

.OUTPUTS
System.Int32 -- Standardized return code from Write-FunctionReturnValue (7001 on
success, 7000 when -Hostname is missing or whitespace, or the certificate error
code such as 50009 on failure).

.EXAMPLE
PS> Install-IcingaForWindows -Hostname 'win-srv01.example.com'

Initializes the Icinga for Windows directories, registers Windows Event Log
sources, and generates a self-signed TLS certificate for 'win-srv01.example.com'
in Cert:\CurrentUser\My (or locally under Certificates on Linux/macOS).

.NOTES
Requires administrative privileges on Windows to register Windows Event Log
sources and configure the 100 MiB log size under the IcingaForWindows log. On
Windows, the node TLS certificate is stored in Cert:\CurrentUser\My of the
executing user account.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Install-IcingaForWindows()
{
    param (
        [string]$Hostname = $null
    );

    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        return (Write-FunctionReturnValue -ReturnValue 'InstallerHostnameMissing' -Data @{ 'Hostname' = $Hostname; });
    }

    $Hostname    = $Hostname.Trim();

    Set-InternalExitCodes;

    # Ensure base Config and Binaries directories exist under ProgramData
    New-ModuleConfigEnvironment | Out-Null;

    # Register Windows Event Log sources and configure the 100 MiB log size
    Register-LoggingWindowsEventLog;

    # Generate initial self-signed protocol certificate for the specified hostname
    $CertResult  = New-IcingaProtocolCertificate -CommonName $Hostname;
    $ReturnCodes = (Get-GlobalRuntimeVariable).Public.ReturnCodes;

    if ($CertResult -ne $ReturnCodes.IcingaCertStoredCertStore.Code -and $CertResult -ne $ReturnCodes.IcingaCertStoredLocally.Code) {
        return $CertResult;
    }

    return (Write-FunctionReturnValue -ReturnValue 'InstallerCompleted' -Data @{ 'Hostname' = $Hostname; 'CertificateResult' = $CertResult; });
}

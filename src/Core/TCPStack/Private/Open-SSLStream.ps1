<#
.SYNOPSIS
Create and authenticate an SSL stream for the active TCP client.

.DESCRIPTION
`Open-SSLStream` wraps the active TCP client's network stream in an
`SslStream`, configures timeouts, and performs client or server authentication
using the thread-local TLS certificate. On failure it closes the TCP connection.

.PARAMETER Endpoint
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Endpoint | System.String | Expected remote endpoint name (required for client auth) | $null |

.PARAMETER IsClient
| Name | Type | Description | Default |
|------|------|-------------|---------|
| IsClient | System.SwitchParameter | When set perform client-side authentication | $false |

.OUTPUTS
None — Stores the opened SslStream in the global state; result codes are reported via `Write-FunctionReturnValue`.

.EXAMPLE
PS> Open-SSLStream -Endpoint 'example.com' -IsClient

.NOTES
Requires a valid certificate in `(Get-GlobalRuntimeVariable).Private.TCP.Certificate`.
#>
function Open-SSLStream()
{
    param (
        [string]$Endpoint = $null,
        [switch]$IsClient = $false
    );

    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($null -eq $GlobalVariable.Private.TCP.Client -Or $GlobalVariable.Private.TCP.Client.Connected -eq $false) {
        return (Write-FunctionReturnValue -ReturnValue 'SslStreamClientInvalid' -Data @{ 'Endpoint' = $Endpoint; 'IsClient' = $IsClient });
    }

    if ($null -ne $GlobalVariable.Private.TCP.Stream) {
        return (Write-FunctionReturnValue -ReturnValue 'SslStreamAlreadyOpened' -Data @{ 'Endpoint' = $Endpoint; 'IsClient' = $IsClient });
    }

    $sslStream              = New-Object System.Net.Security.SslStream($GlobalVariable.Private.TCP.Client.GetStream(), $false);
    Write-LoggingEntry -Message 'Successfully created TLS stream for endpoint' -Data @{
        'Endpoint' = $Endpoint;
        'Client'   = $GlobalVariable.Private.TCP.Client;
    } -Level 'Debug';

    # Set read timeout to prevent hanging
    $sslStream.ReadTimeout  = $GlobalVariable.Public.Config.TCP.ReadTimeout;
    $sslStream.WriteTimeout = $GlobalVariable.Public.Config.TCP.WriteTimeout;

    # Read the TLS certificate from the workers private storage
    $SSLCert                = $GlobalVariable.Private.TCP.Certificate;

    if (-not $SSLCert) {
        return (Write-FunctionReturnValue -ReturnValue 'TlsCertNotFound' -Data @{ 'Endpoint' = $Endpoint; 'IsClient' = $IsClient });
    }

    if ($IsClient) {
        # The client must provide the endpoint name for Ssl authentication, to ensure the server certificate matches
        # Only required if we are acting as a client
        if ([string]::IsNullOrEmpty($Endpoint)) {
            Close-TCPConnection;
            return (Write-FunctionReturnValue -ReturnValue 'ProtocolMissingEndpoint' -Data @{ 'Endpoint' = $Endpoint; 'IsClient' = $IsClient });
        }

        try {
            $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection;
            $certCollection.Add($SSLCert) | Out-Null;

            $sslStream.AuthenticateAsClient($Endpoint, $certCollection, $GlobalVariable.Public.Config.TCP.TLS.Protocols, $false);
        } catch {
            Close-TCPConnection;
            return (Write-FunctionReturnValue -ReturnValue 'TlsHandshakeAsClientFailed' -Data @{ 'ExceptionMessage' = $_.Exception.Message; 'Endpoint' = $Endpoint; 'IsClient' = $IsClient; 'CertificateCollection' = $certCollection });
        }
    } else {
        try {
            $sslStream.AuthenticateAsServer($SSLCert, $false, $GlobalVariable.Public.Config.TCP.TLS.Protocols, $false);
        } catch {
            Close-TCPConnection;
            return (Write-FunctionReturnValue -ReturnValue 'TlsHandshakeAsServerFailed' -Data @{ 'ExceptionMessage' = $_.Exception.Message; 'Endpoint' = $Endpoint; 'IsClient' = $IsClient });
        }
    }

    Write-LoggingEntry `
        -Message 'Successfully created TLS handshake for endpoint' `
        -Data @{
            'Endpoint'        = $Endpoint;
            'SslProtocol'     = $sslStream.SslProtocol;
            'CipherAlgorithm' = $sslStream.CipherAlgorithm;
            'CipherStrength'  = $sslStream.CipherStrength;
            'HashAlgorithm'   = $sslStream.HashAlgorithm;
        } -Level 'Debug';

    $GlobalVariable.Private.TCP.Stream = $sslStream;

    return (Write-FunctionReturnValue -ReturnValue 'TlsHandshakeSuccessful' -Data @{ 'Endpoint' = $Endpoint; 'IsClient' = $IsClient });
}

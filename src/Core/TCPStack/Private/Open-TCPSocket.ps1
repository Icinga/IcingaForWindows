<#
.SYNOPSIS
Create and (optionally) start a TCP listener socket

.DESCRIPTION
`Open-TCPSocket` creates a `TcpListener` bound to the provided address and
port, stores it in the global runtime variable and optionally starts listening.
An optional TLS certificate can be associated for incoming connections.

.PARAMETER Address
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Address | System.String | IP address to bind or empty for loopback | '' |

.PARAMETER Port
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Port | System.Int32 | TCP port to bind | 0 |

.PARAMETER Start
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Start | System.SwitchParameter | When set, immediately start the listener | $false |

.PARAMETER TlsCertificate
| Name | Type | Description | Default |
|------|------|-------------|---------|
| TlsCertificate | System.Security.Cryptography.X509Certificates.X509Certificate2 | Optional server certificate to attach | $null |

.OUTPUTS
None. Stores listener and certificate in global runtime state.

.EXAMPLE
PS> Open-TCPSocket -Port 8080 -Start

.NOTES
Use `Close-TCPSocket` to stop and clear the listener.
#>
function Open-TCPSocket()
{
    param (
        [string]$Address                                                                = '',
        [int]$Port                                                                      = 0,
        [switch]$Start                                                                  = $false,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$TlsCertificate = $null
    );

    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($Port -eq 0) {
        Write-LoggingEntry -Message 'Please specify a valid port to open a TCP socket for' -Level 'Error';
        return;
    }

    if ($null -ne $GlobalVariable.Private.TCP.Listener) {
        Write-LoggingEntry -Message 'A TCP socket is already opened, please close it before opening a new one' -Level 'Warning';
        return;
    }

    $ListenAddress = $null;

    if ([string]::IsNullOrEmpty($Address) -eq $false) {
        # Use the specified address
        $ListenAddress = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Parse($Address), $Port);
    } else {
        # Default to loopback if no address is specified
        $ListenAddress = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Loopback, $Port);
    }

    $TCPSocket = New-Object 'System.Net.Sockets.TcpListener' $ListenAddress;

    Write-LoggingEntry -Message 'Creating new TCP socket' -Level 'Debug' -Data @{ 'Address' = $Address; 'Port' = $Port; 'TCPSocket' = $TCPSocket };

    if ($Start) {
        Write-LoggingEntry -Message 'Starting TCP socket' -Data @{ 'TCPSocket' = $TCPSocket } -Level 'Debug';
        $TCPSocket.Start();
    }

    $GlobalVariable.Private.TCP.Listener    = $TCPSocket;
    $GlobalVariable.Private.TCP.Certificate = $TlsCertificate;
}

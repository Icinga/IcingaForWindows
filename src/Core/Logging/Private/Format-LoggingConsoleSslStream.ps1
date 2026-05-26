<#
.SYNOPSIS
Format `SslStream` properties for console output.

.DESCRIPTION
`Format-LoggingConsoleSslStream` extracts and formats commonly useful properties
from a `System.Net.Security.SslStream` and returns a colorized string.

.PARAMETER Stream
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Stream | System.Net.Security.SslStream | The SSL stream to inspect | |

.PARAMETER Indent
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Indent | System.String | Optional indentation prefix | $null |

.OUTPUTS
System.String — A multi-line formatted representation of the stream properties.

.EXAMPLE
PS> Format-LoggingConsoleSslStream -Stream $sslStream -Indent '  '

.NOTES
Delegates property extraction to `Format-LoggingConsoleObjectProperties`.
#>
function Format-LoggingConsoleSslStream()
{
    param (
        [System.Net.Security.SslStream]$Stream = $null,
        [string]$Indent                        = $null
    );

    # If the client is null, return the formatted null value
    if ($null -eq $Stream) {
        return (Format-LoggingConsoleNullValue -Indent $Indent);
    }

    # Format the SslStream properties
    return (
        Format-LoggingConsoleObjectProperties `
            -Object $Stream `
            -Properties @(
                'IsAuthenticated',
                'IsEncrypted',
                'IsSigned',
                'IsMutuallyAuthenticated',
                'SslProtocol',
                'CipherAlgorithm',
                'CipherStrength',
                'HashAlgorithm',
                'HashStrength',
                'KeyExchangeAlgorithm',
                'KeyExchangeStrength',
                'CheckCertRevocationStatus'
            ) `
            -Indent $Indent
    );
}

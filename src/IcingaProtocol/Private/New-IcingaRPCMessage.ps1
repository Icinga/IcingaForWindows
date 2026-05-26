<#
.SYNOPSIS
Creates a length-prefixed JSON-RPC 2.0 message for the Icinga protocol.

.DESCRIPTION
New-IcingaRPCMessage builds a JSON-RPC 2.0 message hashtable with the keys
jsonrpc, method and params, serializes it to compact JSON and prefixes it with
the UTF-8 byte length followed by a colon (Icinga framing). The result is a
hashtable with the keys message (byte array) and length (integer) ready to be
passed to Send-TCPMessage or Add-IcingaRPCMessageToWriterQueue.

.PARAMETER Method
| Name   | Type          | Description                                         | Default |
|--------|---------------|-----------------------------------------------------|---------|
| Method | System.String | JSON-RPC method name (for example icinga::Hello).   |         |

.PARAMETER Parameters
| Name       | Type                          | Description                                    | Default |
|------------|-------------------------------|------------------------------------------------|---------|
| Parameters | System.Collections.Hashtable  | Parameters to include in the RPC params field. | @{}     |

.OUTPUTS
System.Collections.Hashtable — Hashtable with keys message (System.Byte[]) and length (System.Int32).

.EXAMPLE
PS> New-IcingaRPCMessage -Method 'icinga::Hello'

Returns a length-prefixed encoded message hashtable for the Hello handshake.

.NOTES
The method call is logged at Debug level via Write-LoggingEntry before the byte
encoding step.
#>
function New-IcingaRPCMessage()
{
    param (
        $Method,
        $Parameters = @{}
    );

    [hashtable]$MessageHash = @{
        'jsonrpc' = '2.0';
        'method'  = $Method;
        'params'  = $Parameters;
    };

    $JsonMessage = (ConvertTo-Json -InputObject $MessageHash -Depth 100 -Compress);
    $JsonMessage = [string]::Format(
        '{0}:{1},',
        [System.Text.Encoding]::UTF8.GetBytes(
            $JsonMessage
        ).Length,
        $JsonMessage
    );

    Write-LoggingEntry -Message 'Creating Icinga RPC Message' -Level 'Debug' -Data @{ 'JsonMessage' = $JsonMessage; };

    $EncodedMessage = [System.Text.Encoding]::UTF8.GetBytes(
        $JsonMessage
    );

    return @{
        'message' = $EncodedMessage;
        'length'  = $EncodedMessage.Length;
    };
}

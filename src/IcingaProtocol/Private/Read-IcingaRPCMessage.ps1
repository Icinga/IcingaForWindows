<#
.SYNOPSIS
Parses one or more length-prefixed JSON-RPC frames from a string buffer.

.DESCRIPTION
Read-IcingaRPCMessage processes the accumulated string buffer JSONRPCMessage in a
loop. For each iteration it strips a leading comma if present, reads the numeric
length prefix before the first colon, extracts exactly that many characters as the
RPC payload and passes the payload to Add-IcingaRPCMessageToWorker for worker
dispatch. The consumed portion is removed from the buffer and the loop continues
until the buffer is empty, the size prefix is invalid or insufficient data remains
for a complete frame. The function returns the remaining (possibly partial) buffer
string so the caller can append the next chunk of data and call again.

.PARAMETER JSONRPCMessage
| Name           | Type          | Description                                                                 | Default |
|----------------|---------------|-----------------------------------------------------------------------------|---------|
| JSONRPCMessage | System.String | Accumulated string buffer containing one or more length-prefixed RPC frames. | ''      |

.OUTPUTS
System.String — Remaining buffer content after all complete frames have been consumed.

.EXAMPLE
PS> $remaining = Read-IcingaRPCMessage -JSONRPCMessage $buffer

.NOTES
Each call may process multiple complete frames in a single pass. Partial frames at
the end of the buffer are preserved in the returned string for the next read cycle.
Complete messages are dispatched via Add-IcingaRPCMessageToWorker.
#>
function Read-IcingaRPCMessage()
{
    param (
        [string]$JSONRPCMessage = ''
    );

    # Once we have some data, we will have to split the message by the framing delimiter (':') to determine the RPC size
    # Afterwards, we read this RPCSize from the message and check before if we have enough data to read the entire message.
    # If not, we simply break the loop and wait for more data, as the JSONRPG message object will be extended with new data on the next read.
    # For every completed message, we remove this part from the JSONRPCMessage, and continue reading for as long as we have data in the buffer and the RPC size is valid.
    while ($true) {
        # If the message is empty, we can't parse anything and do nothing
        if ([string]::IsNullOrEmpty($JSONRPCMessage)) {
            break;
        }
        # If the message starts with a comma, we remove it to avoid issues with parsing the RPC size
        if ($JSONRPCMessage[0] -eq ',') {
            $JSONRPCMessage = $JSONRPCMessage.Substring(1);
        }

        # First read the RPC size
        [decimal]$RPCSize       = [decimal]($JSONRPCMessage.Split(':')[0]);
        [decimal]$RPCSizeDigits = $RPCSize.ToString().Length;
        [decimal]$TotalSize     = $RPCSizeDigits + 1 + $RPCSize; # Digits for size + framing delimiter (:) + actual message size

        if ($RPCSize -le 0) {
            # If the RPC size is not valid, we break the loop and wait for more data to be read in the next iteration, as the JSONRPCMessage will be extended with new data on the next read.
            break;
        }

        # Now check if the remaining string is long enough to contain the entire RPC message based on the determined size
        if ($JSONRPCMessage.Length -lt $TotalSize) {
            # If not, we break the loop and wait for more data to be read in the next iteration, as the JSONRPCMessage will be extended with new data on the next read.
            break;
        }

        # Extract the RPC message based on the determined size
        [string]$RPCMessage = $JSONRPCMessage.Substring($RPCSizeDigits + 1, $RPCSize);

        Write-LoggingEntry -Message 'Extracted RPC message from buffer' -Level 'Debug' -Data @{ 'RPCSize' = $RPCSize; 'RPCMessage' = $RPCMessage; };
        if (-not [string]::IsNullOrEmpty($RPCMessage)) {
            # Add the complete RPC message to the worker queue for processing
            Add-IcingaRPCMessageToWorker -Message $RPCMessage | Out-Null;
        }

        # Finally, we remove the processed message from the JSONRPCMessage to check if we have more messages in the buffer
        # We add the digit length of the RPC size, the framing delimiter and the RPC message size to determine the correct substring index for the next message
        $JSONRPCMessage = $JSONRPCMessage.Substring($TotalSize);
        Write-LoggingEntry -Message 'Updated JSONRPCMessage after processing RPC message' -Level 'Debug' -Data @{ 'RemainingMessage' = $JSONRPCMessage; };
    }

    return $JSONRPCMessage;
}

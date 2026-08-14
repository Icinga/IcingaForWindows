<#
.SYNOPSIS
Parses one or more length-prefixed JSON-RPC frames from a StringBuilder buffer.

.DESCRIPTION
Read-IcingaRPCMessage processes the accumulated StringBuilder buffer in a
loop. For each iteration it strips a leading comma if present, reads the numeric
length prefix before the first colon, extracts exactly that many characters as the
RPC payload and passes the payload to Add-IcingaRPCMessageToWorker for worker
dispatch. The consumed portion is removed from the buffer and the loop continues
until the buffer is empty, the size prefix is invalid or insufficient data remains
for a complete frame.

.PARAMETER Buffer
| Name   | Type                      | Description                                                                 | Default |
|--------|---------------------------|-----------------------------------------------------------------------------|---------|
| Buffer | System.Text.StringBuilder | Accumulated StringBuilder buffer containing one or more length-prefixed RPC frames. | $null   |

.OUTPUTS
None — The buffer is modified in place.

.EXAMPLE
PS> Read-IcingaRPCMessage -Buffer $buffer

.NOTES
Each call may process multiple complete frames in a single pass. Partial frames at
the end of the buffer are preserved for the next read cycle.
Complete messages are dispatched via Add-IcingaRPCMessageToWorker.
#>
function Read-IcingaRPCMessage()
{
    param (
        [System.Text.StringBuilder]$Buffer
    );

    if ($null -eq $Buffer) {
        return;
    }

    # Once we have some data, we will have to split the message by the framing delimiter (':') to determine the RPC size
    # Afterwards, we read this RPCSize from the message and check before if we have enough data to read the entire message.
    # If not, we simply break the loop and wait for more data, as the JSONRPG message object will be extended with new data on the next read.
    # For every completed message, we remove this part from the Buffer, and continue reading for as long as we have data.
    while ($true) {
        # If the message is empty, we can't parse anything and do nothing
        if ($Buffer.Length -eq 0) {
            break;
        }

        # If the message starts with a comma, we remove it to avoid issues with parsing the RPC size
        if ($Buffer[0] -eq ',') {
            [void]$Buffer.Remove(0, 1);
        }

        if ($Buffer.Length -eq 0) {
            break;
        }

        # Find the index of the framing delimiter (':') to determine the RPC size
        # We only check up to 32 chars to avoid searching the entire payload if it's huge
        [int]$ColonIndex = -1;
        $SearchLimit     = [math]::Min($Buffer.Length, 32);
        for ($i = 0; $i -lt $SearchLimit; $i++) {
            if ($Buffer[$i] -eq ':') {
                $ColonIndex = $i;
                break;
            }
        }

        if ($ColonIndex -le 0) {
            break;
        }

        # Parse the RPC message size prefix without array allocations or Split()
        [string]$SizeString = $Buffer.ToString(0, $ColonIndex);
        [int]$RPCSize = 0;
        if (-not [int]::TryParse($SizeString, [ref]$RPCSize) -or $RPCSize -le 0) {
            break;
        }

        [int]$TotalSize = $ColonIndex + 1 + $RPCSize; # Digits for size + framing delimiter (:) + actual message size

        # Check if the remaining string is long enough to contain the entire RPC message based on the determined size
        if ($Buffer.Length -lt $TotalSize) {
            break;
        }

        # Extract the RPC message based on the determined size
        [string]$RPCMessage = $Buffer.ToString($ColonIndex + 1, $RPCSize);
        
        if (-not [string]::IsNullOrEmpty($RPCMessage)) {
            # Add the complete RPC message to the worker queue for processing
            Add-IcingaRPCMessageToWorker -Message $RPCMessage | Out-Null;
        }

        # Remove the processed message from the buffer
        [void]$Buffer.Remove(0, $TotalSize);
    }
}

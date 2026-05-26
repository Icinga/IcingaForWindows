<#
.SYNOPSIS
Adds a pre-built RPC message object to the per-endpoint writer queue.

.DESCRIPTION
Add-IcingaRPCMessageToWriterQueue enqueues a message object created by
New-IcingaRPCMessage into the appropriate per-endpoint BlockingCollection
inside $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue. If the
writer queue has not yet been initialized, or if no entry exists for the
current remote endpoint, the message is sent directly via Send-TCPMessage
as a fallback (for example during the early handshake phase). Null or
empty message objects are silently discarded. The function reads the
current TCP client and writer queue through Get-GlobalRuntimeVariable so
that it works correctly inside worker thread runspaces.

.PARAMETER MsgObj
| Name   | Type          | Description                                                           | Default |
|--------|---------------|-----------------------------------------------------------------------|---------|
| MsgObj | System.Object | Message object as returned by New-IcingaRPCMessage (@{message;length}). | $null   |

.OUTPUTS
None — The function enqueues the message or sends it directly; no pipeline output is produced.

.EXAMPLE
PS> Add-IcingaRPCMessageToWriterQueue -MsgObj (New-IcingaRPCMessage -Method 'icinga::Hello')

.NOTES
This function uses Get-GlobalRuntimeVariable to access global state, making it safe to
call from within thread runspaces. The writer queue is keyed by the string representation
of the remote endpoint IP address.
#>
function Add-IcingaRPCMessageToWriterQueue()
{
    param (
        $MsgObj = $null
    );

    if ($null -eq $MsgObj -Or $MsgObj.Count -eq 0 -Or $MsgObj.length -eq 0) {
        $MsgObj = $null;

        return;
    }

    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($null -eq $GlobalVariable.Private.TCP.Client) {
        $MsgObj = $null;

        return;
    }

    # If the writer queue is not initialized, send the message directly to the stream (e.g. for early messages like Hello)
    if ($null -eq $GlobalVariable.Public.IcingaProtocol.WriterQueue) {
        Send-TCPMessage -MsgObj $MsgObj;
        return;
    }

    # Add the message to the writer queue for the current endpoint
    $Endpoint = $GlobalVariable.Private.TCP.Client.Client.RemoteEndPoint.Address.ToString();

    # Check if the writer queue for this endpoint exists, if not send it directly to the stream
    if ($null -eq $GlobalVariable.Public.IcingaProtocol.WriterQueue.$Endpoint) {
        Send-TCPMessage -MsgObj $MsgObj;
        return;
    }

    $GlobalVariable.Public.IcingaProtocol.WriterQueue.$Endpoint.Add($MsgObj) | Out-Null;
}

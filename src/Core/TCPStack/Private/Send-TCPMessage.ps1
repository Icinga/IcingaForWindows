<#
.SYNOPSIS
Write a prepared message buffer to the active TCP/SSL stream

.DESCRIPTION
`Send-TCPMessage` takes a message object containing the buffer and length
and writes it to the active SSL stream of the current TCP client. It logs
an error if no valid stream is available.

.PARAMETER MsgObj
| Name | Type | Description | Default |
|------|------|-------------|---------|
| MsgObj | System.Object | Object with `message` (buffer) and `length` properties | $null |

.OUTPUTS
None — Writes the message buffer to the SSL stream and flushes it; logs an error if no valid stream is available.

.EXAMPLE
PS> Send-TCPMessage -MsgObj $msg

.NOTES
This helper assumes the active stream is an `SslStream` exposing `Write` and `Flush`.
#>
function Send-TCPMessage()
{
    param(
        $MsgObj = $null
    );

    if ($null -eq $MsgObj -Or $MsgObj.Count -eq 0 -Or $MsgObj.length -eq 0) {
        $MsgObj = $null;
        return;
    }

    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($null -eq $GlobalVariable.Private.TCP.Stream) {
        $MsgObj = $null;
        Write-LoggingEntry -Message 'No valid TCP stream available to send TCP message' -Level 'Error' -Data @{ 'MsgObj' = $MsgObj };
        return;
    }

    $GlobalVariable.Private.TCP.Stream.Write($MsgObj.message, 0, $MsgObj.length);
    $GlobalVariable.Private.TCP.Stream.Flush();
}

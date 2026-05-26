<#
.SYNOPSIS
Sends an Icinga protocol Hello message on the active connection.

.DESCRIPTION
Send-IcingaProtocolHello constructs a minimal JSON-RPC hello message using
New-IcingaRPCMessage with method icinga::Hello and sends it directly via
Send-TCPMessage. Use this to initiate the protocol handshake where required
by the remote endpoint, typically before the writer queue is active.

.OUTPUTS
None — Sends the Hello frame directly via Send-TCPMessage; no pipeline output.

.EXAMPLE
PS> Send-IcingaProtocolHello

Sends the Hello message over the current TCP/SSL stream.

.NOTES
This function bypasses the writer queue and calls Send-TCPMessage directly,
making it suitable for early handshake messages before the queue is initialized.
#>
function Send-IcingaProtocolHello()
{
    Send-TCPMessage -MsgObj (New-IcingaRPCMessage -Method 'icinga::Hello');
}

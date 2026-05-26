<#
.SYNOPSIS
Sends a periodic Icinga protocol heartbeat over the established TCP connection.

.DESCRIPTION
Checks the module's global heartbeat timer and, if the configured interval has elapsed
(or no previous heartbeat time exists), constructs and transmits an Icinga RPC heartbeat
message. The function logs the activity, creates an RPC message with method 'event::Heartbeat'
and a timeout parameter of 120 seconds, sends it via the module's TCP send routine, and
updates the global heartbeat timestamp.

.OUTPUTS
None — Performs side effects: sends a TCP heartbeat message, writes log entries and updates the global heartbeat timestamp.

.EXAMPLE
PS> Send-IcingaProtocolHeartbeat

Sends a heartbeat now if the configured interval has elapsed, otherwise does nothing.

.NOTES
Relies on $Global:IcingaForWindows.Private.TCP.HeartbeatTimer and HeartbeatInterval
being present and correctly configured. Requires Write-LoggingEntry, New-IcingaRPCMessage
and Send-TCPMessage. The heartbeat message includes a parameter timeout set to 120 seconds.
Time comparisons use Get-Date and TotalSeconds to determine interval expiry.
#>
function Send-IcingaProtocolHeartbeat()
{
    # Update our time variables for the heartbeat
    $TimeNow       = Get-Date;
    $LastHeartbeat = $Global:IcingaForWindows.Private.TCP.HeartbeatTimer;

    # Check if we need to send a heartbeat based on the configured interval
    if ($null -eq $LastHeartbeat -or ($TimeNow - $LastHeartbeat).TotalSeconds -ge $Global:IcingaForWindows.Private.TCP.HeartbeatInterval) {
        # Send the heartbeat message
        Write-LoggingEntry -Message '  → Sending IcingaProtocol Heartbeat' -Level 'Debug';
        $MsgObj = New-IcingaRPCMessage -Method 'event::Heartbeat' -Parameters @{ 'timeout' = 120 };
        Send-TCPMessage -MsgObj $MsgObj;
        # Update the last heartbeat time
        $Global:IcingaForWindows.Private.TCP.HeartbeatTimer = $TimeNow;
    }
}

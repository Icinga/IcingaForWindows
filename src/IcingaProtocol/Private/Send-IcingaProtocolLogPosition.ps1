<#
.SYNOPSIS
Send a log position update message over the Icinga protocol

.DESCRIPTION
Sends an Icinga RPC message with the method 'log::SetLogPosition'
to update the current log position on the connected endpoint. The
log position is automatically set to the current Unix timestamp
using Get-IcingaUnixTime.

.OUTPUTS
None -- Does not return any value.

.EXAMPLE
PS> Send-IcingaProtocolLogPosition

Sends the log position update to the connected Icinga endpoint.

.NOTES
Requires an active TCP connection to the Icinga endpoint.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Send-IcingaProtocolLogPosition()
{
    Add-IcingaRPCMessageToWriterQueue -MsgObj (
        New-IcingaRPCMessage -Method 'log::SetLogPosition' -Parameters @{
            'log_position' = Get-IcingaUnixTime;
        }
    );
}

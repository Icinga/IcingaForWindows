<#
.SYNOPSIS
Sends a check result as a JSON-RPC event to the remote Icinga endpoint.

.DESCRIPTION
Send-IcingaProtocolCheckResult takes a hashtable describing a plugin check
result and packages it into an RPC message with method event::CheckResult via
New-IcingaRPCMessage and enqueues it through Add-IcingaRPCMessageToWriterQueue.
The function validates the provided hashtable and logs an error if it is empty
or null.

.PARAMETER CheckResult
| Name        | Type                         | Description                                                 | Default |
|-------------|------------------------------|-------------------------------------------------------------|---------|
| CheckResult | System.Collections.Hashtable | Check result fields expected by Icinga (host, service, cr). | @{}     |

.OUTPUTS
None -- Logs errors via Write-LoggingEntry and enqueues the message through the writer queue.

.EXAMPLE
PS> Send-IcingaProtocolCheckResult -CheckResult @{ host = 'myhost'; service = 'ping'; cr = @{ exit_status = 0; output = 'OK' } }

.NOTES
Requires New-IcingaRPCMessage and Add-IcingaRPCMessageToWriterQueue to be available.
The check result is sent asynchronously via the per-endpoint writer queue.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Send-IcingaProtocolCheckResult()
{
    param (
        [hashtable]$CheckResult = @{ }
    );

    if ($null -eq $CheckResult -or $CheckResult.Count -eq 0) {
        Write-LoggingEntry -Message 'Please provide a valid CheckResult hashtable to send' -Level 'Error';
        return;
    }

    $MsgObj = New-IcingaRPCMessage -Method 'event::CheckResult' -Parameters $CheckResult;

    Add-IcingaRPCMessageToWriterQueue -MsgObj $MsgObj;
}

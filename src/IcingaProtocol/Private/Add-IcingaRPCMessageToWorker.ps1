<#
.SYNOPSIS
Add a serialized Icinga 2 JSON-RPC message to a worker queue in round-robin order

.DESCRIPTION
Add-IcingaRPCMessageToWorker accepts a serialized JSON-RPC message string,
strips Icinga empty-key placeholder entries ('"":"$"') for Windows PowerShell
5.1 JavaScriptSerializer compatibility, deserializes the payload via
ConvertFrom-ModuleJson, and enqueues the parsed message together with the
current socket client and TLS stream into the next worker queue via round-robin
selection. Null, empty or malformed JSON payloads emit structured return values
and are dropped without throwing.

.PARAMETER Message
| Name    | Type          | Description                                                                 | Default |
|---------|---------------|-----------------------------------------------------------------------------|---------|
| Message | System.String | Serialized JSON-RPC message payload to enqueue. Ignored when null or empty. | $null   |

.OUTPUTS
None -- Enqueues the parsed message object into WorkerQueue and returns nothing.

.EXAMPLE
PS> Add-IcingaRPCMessageToWorker -Message '{"jsonrpc":"2.0","method":"event::ExecuteCommand","params":{}}'

Parses the JSON-RPC message and dispatches it to the next protocol worker queue.

.NOTES
Caller must ensure WorkerCount and WorkerQueue are initialized in
Public.IcingaProtocol before invoking this helper.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Add-IcingaRPCMessageToWorker()
{
    param (
        [string]$Message = $null
    );

    if ([string]::IsNullOrEmpty($Message)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaClientRPCMessageNull');
    }

    $RPCMessage = $null;

    # Parse the JSON-RPC frame while stripping empty-key placeholder pairs ("":"$") sent by Icinga 2
    try {
        $RPCMessage = ConvertFrom-ModuleJson -InputObject $Message.Replace('"":"$",', '').Replace(',"":"$"', '');
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaClientRPCMessageParseError' -Data @{ 'Message' = $Message; 'Exception' = $_.Exception; } -OverrideReturn $null);
    }

    if ($null -eq $RPCMessage) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaClientRPCMessageParseError' -Data @{ 'Message' = $Message; } -OverrideReturn $null);
    }

    # Determine which worker should receive this message based on a round-robin approach
    $GlobalVariable = Get-GlobalRuntimeVariable;
    $GlobalVariable.Private.TCP.LastWorkerId++;

    if ($GlobalVariable.Private.TCP.LastWorkerId -ge $GlobalVariable.Public.IcingaProtocol.Config.WorkerCount) {
        $GlobalVariable.Private.TCP.LastWorkerId = 0;
    }

    # Create the message object with socket context to hand over to the worker
    $MessageObject = [PSCustomObject]@{
        'Message' = $RPCMessage;
        'Client'  = $GlobalVariable.Private.TCP.Client;
        'Stream'  = $GlobalVariable.Private.TCP.Stream;
    };

    # Add the message to the appropriate worker queue
    $GlobalVariable.Public.IcingaProtocol.WorkerQueue[$GlobalVariable.Private.TCP.LastWorkerId].Add($MessageObject) | Out-Null;
}

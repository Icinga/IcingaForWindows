<#
.SYNOPSIS
Adds a serialized RPC message to a worker queue using a round-robin assignment.

.DESCRIPTION
Add-IcingaRPCMessageToWorker accepts a serialized JSON-RPC message string and enqueues
a message object for processing by one of the module's worker threads. The function
performs round-robin worker selection by incrementing the global LastWorkerId and
wrapping it when it reaches the configured WorkerCount. If the message is null or empty,
the function returns immediately via Write-FunctionReturnValue. The message is first
deserialized with ConvertFrom-Json and only forwarded when its method is icinga::Hello
or event::ExecuteCommand; all other methods are dropped. The enqueued object contains
the parsed message, the current global TCP client and the global stream. This function
mutates $Global:IcingaForWindows.Private.TCP.LastWorkerId as a side effect.

.PARAMETER Message
| Name    | Type          | Description                                                                      | Default |
|---------|---------------|----------------------------------------------------------------------------------|---------|
| Message | System.String | Serialized JSON-RPC message payload to enqueue. Ignored when null or empty.      | $null   |

.EXAMPLE
PS> Add-IcingaRPCMessageToWorker -Message '{"jsonrpc":"2.0","method":"event::ExecuteCommand","params":{}}'

.OUTPUTS
None — The function enqueues the message object and returns no pipeline output.

.NOTES
Caller must ensure the module-global WorkerCount and WorkerQueue are initialized before
use. The function is not explicitly synchronized; the caller must ensure appropriate
concurrency guarantees. Only messages with methods icinga::Hello and event::ExecuteCommand
are forwarded; all other methods are silently dropped.

#>
function Add-IcingaRPCMessageToWorker()
{
    param (
        [string]$Message = $null
    );

    if ([string]::IsNullOrEmpty($Message)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaClientRPCMessageNull');
    }

    # Get the real JSON message object and check the content, to only send messages
    # we actually care about
    try {
        $RPCMessage = ConvertFrom-Json -InputObject $Message.Replace('"macros":{"":"$",', '"macros":{');
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaClientRPCMessageParseError' -Data @{ 'Message' = $Message; 'Exception' = $_.Exception; } -OverrideReturn $null);
    }

    switch ($RPCMessage.method) {
        'icinga::Hello' {
            # Forward icinga:hello
            break;
        };
        'event::ExecuteCommand' {
            # Forward command execution
            break;
        };
        default {
            # For other methods, just drop the message
            return;
        };
    }

    # Determine which worker should receive this message based on a round-robin approach
    $Global:IcingaForWindows.Private.TCP.LastWorkerId++;

    if ($Global:IcingaForWindows.Private.TCP.LastWorkerId -ge $Global:IcingaForWindows.Public.IcingaProtocol.Config.WorkerCount) {
        $Global:IcingaForWindows.Private.TCP.LastWorkerId = 0;
    }

    # Create the message object to send to the worker
    $MessageObject = [PSCustomObject]@{
        'Message'  = $RPCMessage;
        'Client'   = $Global:IcingaForWindows.Private.TCP.Client;
        'Stream'   = $Global:IcingaForWindows.Private.TCP.Stream;
    };

    # Add the message to the appropriate worker queue
    $Global:IcingaForWindows.Public.IcingaProtocol.WorkerQueue[$Global:IcingaForWindows.Private.TCP.LastWorkerId].Add($MessageObject) | Out-Null;
}

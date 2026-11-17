<#
.SYNOPSIS
Enqueue a message for a WebSocket writer worker.

.DESCRIPTION
`Add-ModuleWebSocketMessageToQueue` places a message into the configured
WebSocket writer queue. It validates the WebSocket name (allowing an
override) and the message payload, logs the enqueue operation and returns a
structured module return on error conditions.

.PARAMETER Message
| Name    | Type          | Description                 | Default |
|---------|---------------|-----------------------------|---------|
| Message | System.String | Message payload to enqueue. |         |

.PARAMETER OverrideWebSocketName
| Name                  | Type          | Description                               | Default |
|-----------------------|---------------|-------------------------------------------|---------|
| OverrideWebSocketName | System.String | Optional runtime websocket name override. |         |

.OUTPUTS
System.Object -- Emits module structured return values on error; otherwise the
message is placed in the BlockingCollection and the function returns without
an explicit value.

.EXAMPLE
PS> Add-ModuleWebSocketMessageToQueue -Message $payload

.NOTES
The message is written directly to the `WriterWorker` BlockingCollection stored
in `$Global:ModuleName.Public.WebSocket.<Name>.WriterWorker`. This collection is
consumed by `Write-ModuleWebSocket` running in a separate worker thread. The
function must be called from within a worker context where
`Get-GlobalRuntimeVariable` provides a valid WebSocket name via
`Private.WebSocket.Name`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Add-ModuleWebSocketMessageToQueue()
{
    param (
        [string]$Message               = $null,
        [string]$OverrideWebSocketName = $null
    );

    $GlobalVariable        = Get-GlobalRuntimeVariable;
    [string]$WebSocketName = $GlobalVariable.Private.WebSocket.Name;

    if (-not [string]::IsNullOrEmpty($OverrideWebSocketName)) {
        $WebSocketName = $OverrideWebSocketName;
    }

    if ([string]::IsNullOrEmpty($WebSocketName)) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketMessageAddQueueWebSocketNameMissing');
    }

    if ([string]::IsNullOrEmpty($Message)) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketMessageAddQueueMessageMissing' -Data @{ 'WebSocketName' = $WebSocketName; });
    }

    $GlobalVariable.Public.WebSocket.$WebSocketName.WriterWorker.Add($Message) | Out-Null;

    Write-LoggingEntry -Message 'Add-ModuleWebSocketMessageToQueue: Message added to WebSocket write queue' -Level 'Debug' -Data @{ 'WebSocketName' = $WebSocketName; 'MessageLength' = $Message.Length; 'Message' = $Message; };
}

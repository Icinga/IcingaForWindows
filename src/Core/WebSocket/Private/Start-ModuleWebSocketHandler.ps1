<#
.SYNOPSIS
Manage a persistent WebSocket connection and spawn worker threads.

.DESCRIPTION
`Start-ModuleWebSocketHandler` drives the lifecycle for a named WebSocket
connection. It attempts to establish the connection, performs any type-
specific authentication steps (for example MyWebSocket), and
spawns reader, writer and processing worker threads. The handler runs in a
loop and is responsible for reconnection and keep-alive handling.

.PARAMETER Name
| Name | Type          | Description                                   | Default |
|------|---------------|-----------------------------------------------|---------|
| Name | System.String | Name of the WebSocket configuration to manage |         |

.OUTPUTS
System.Object -- Emits structured return codes for validation failures; otherwise
the function runs until the thread manager requests termination.

.EXAMPLE
PS> Start-ModuleWebSocketHandler -Name 'MySocket'

.NOTES
The function expects a corresponding configuration entry in
`$Global:ModuleName.Public.WebSocket.Config` for the provided `Name`. It runs
inside a dedicated thread spawned by `New-ModuleWebSocketEnvironment` and drives
connection, reconnection, keep-alive handling, as well as spawning of reader,
writer and processing worker threads.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Start-ModuleWebSocketHandler()
{
    param (
        [string]$Name = ''
    );

    # We only require the name, as we can fetch the rest from the global config
    if ([string]::IsNullOrEmpty($Name)) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketHandlerNoNameProvided');
    };

    $GlobalVariable           = Get-GlobalRuntimeVariable;
    [string]$WebSocketAddress = $GlobalVariable.Public.WebSocket.Config.$Name.Address;
    [string]$WebSocketType    = $GlobalVariable.Public.WebSocket.Config.$Name.Type;

    # Only test for the thread itself here, as WebSockets will be handled inside the loop
    # We need to keep this thread active, as it will handle the re-connections and keep-alive events
    # While it will start read and write threads as needed
    while (Test-ThreadRunning) {
        # If the WebSocket is already connected, we can just continue
        # TODO: We should make this dynamic with a configuration instead of hardcoding
        if (Test-ModuleWebSocket) {
            switch ($WebSocketType) {
                <#'ExampleWebSocketType' {
                    Invoke-ExampleWebSocket -HandlerEvents | Out-Null;
                    break;
                };#>
                default {
                    break;
                }
            }
            continue;
        }

        # Try to connect the WebSocket
        Connect-ModuleWebSocket -Name $Name -Address $WebSocketAddress | Out-Null;

        # TODO: We should make this dynamic with a configuration instead of hardcoding
        switch ($WebSocketType) {
            <#'ExampleWebSocketType' {
                Invoke-ExampleWebSocket -HandlerEvents | Out-Null;
                break;
            };#>
            default {
                Write-LoggingEntry -Message 'Start-ModuleWebSocketHandler: Unknown WebSocket type, cannot send authentication message' -Level 'Warning' -Data @{ 'WebSocketType' = $WebSocketType; 'Name' = $Name; };
                break;
            };
        }

        # Start the background read and write threads only if the connection was successful
        if (Test-ModuleWebSocket) {
            $GlobalVariable.Public.WebSocket.$Name.WriterWorker.Add('WebSocket::CoreTestWriteObject') | Out-Null;
            $GlobalVariable.Public.WebSocket.$Name.ReaderWorker.Add('WebSocket::CoreTestWriteObject') | Out-Null;
            # Now we need to start a thread for reading the WebSocket messages and writing into the socket
            # Read messages from the WebSocket
            New-Thread `
                -Command 'Read-ModuleWebSocket' `
                -Parameters @{
                    'Name'                    = $Name;
                    'ClientWebSocket'         = $GlobalVariable.Private.WebSocket.ClientWebSocket;
                    'CancellationTokenSource' = $GlobalVariable.Private.WebSocket.CancellationTokenSource;
                } `
                -Start `
                -WaitForJobs | Out-Null;

            # Write messages to the WebSocket
            New-Thread `
                -Command 'Write-ModuleWebSocket' `
                -Parameters @{
                    'Name'                    = $Name;
                    'ClientWebSocket'         = $GlobalVariable.Private.WebSocket.ClientWebSocket;
                    'CancellationTokenSource' = $GlobalVariable.Private.WebSocket.CancellationTokenSource;
                } `
                -Start `
                -WaitForJobs | Out-Null;

            # Start the worker which will actually handle the messages read from the WebSocket
            New-Thread `
                -Command 'Start-ModuleWebSocketReaderWorker' `
                -Parameters @{
                    'Name'                    = $Name;
                    'ClientWebSocket'         = $GlobalVariable.Private.WebSocket.ClientWebSocket;
                    'CancellationTokenSource' = $GlobalVariable.Private.WebSocket.CancellationTokenSource;
                } `
                -Start `
                -WaitForJobs | Out-Null;
        }
    }

    Disconnect-ModuleWebSocket;
}

<#
.SYNOPSIS
Start the WebSocket environment background thread.

.DESCRIPTION
`Start-ModuleWebSocketDaemon` starts the WebSocket environment by creating a
background thread that initializes the WebSocket runtime (`New-ModuleWebSocketEnvironment`).
The function returns immediately after the management thread is started.

.OUTPUTS
None — Starts a background thread and returns immediately without a return value.

.EXAMPLE
PS> Start-ModuleWebSocketDaemon

.NOTES
This helper wraps `New-Thread` to ensure the WebSocket environment is
initialized on a separate thread. The background thread executes
`New-ModuleWebSocketEnvironment`, which loads all persisted WebSocket
configurations and spawns per-instance handler threads.
#>
function Start-ModuleWebSocketDaemon()
{
    New-Thread -Command 'New-ModuleWebSocketEnvironment' -Start;
}

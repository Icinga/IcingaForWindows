<#
.SYNOPSIS
Starts the Icinga protocol agent environment in a background thread.

.DESCRIPTION
Start-IcingaAgent spawns a background thread via New-Thread that calls
New-IcingaAgentEnvironment to initialize the full Icinga protocol stack.
Use this function to activate the protocol listener, connector and worker
threads for Icinga JSON-RPC communication.

.OUTPUTS
None — Starts a background thread; no pipeline output.

.EXAMPLE
PS> Start-IcingaAgent

.NOTES
This function requires New-IcingaAgentEnvironment and New-Thread to be available.
The agent environment is initialized asynchronously in the spawned thread.
Call this once during module startup after global configuration is in place.
#>
function Start-IcingaAgent()
{
    New-Thread -Command 'New-IcingaAgentEnvironment' -Start;
}

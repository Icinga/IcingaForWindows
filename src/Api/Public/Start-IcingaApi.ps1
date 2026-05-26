<#
.SYNOPSIS
Start the API subsystem by spawning the API environment background thread

.DESCRIPTION
Start-IcingaApi is a convenience wrapper that spawns a background thread
running New-IcingaApiEnvironment. The background thread initializes the TLS
certificate, creates the worker queue, starts the configured number of API
worker threads and finally starts the TCP listener thread. Use this function
from interactive sessions or module startup to activate the full API stack.

.OUTPUTS
None — The API subsystem is activated as a side effect via background threads.

.EXAMPLE
PS> Start-IcingaApi

Spawns the API environment thread which brings up the listener and workers.

.NOTES
Delegates all initialization to New-IcingaApiEnvironment running inside a
New-Thread background thread. Requires IcingaForWindows.Public.Api.Config to
be populated before calling. No return value is emitted.
#>
function Start-IcingaApi()
{
    New-Thread -Command 'New-IcingaApiEnvironment' -Start;
}

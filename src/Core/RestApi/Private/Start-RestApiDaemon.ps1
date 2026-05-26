<#
.SYNOPSIS
Start the RestApi daemon by initializing the RestApi environment.

.DESCRIPTION
Creates a background thread that initializes the RestApi runtime
environment. This is a lightweight helper that delegates to
`New-RestApiEnvironment` on a new thread.

.OUTPUTS
None — starts a background thread and returns immediately.

.EXAMPLE
PS> Start-RestApiDaemon

.NOTES
This function starts a thread but does not wait for the environment to be
fully initialized. Use `New-RestApiEnvironment` directly when synchronous
initialization is required.
#>
function Start-RestApiDaemon()
{
    New-Thread -Command 'New-RestApiEnvironment' -Start;
}

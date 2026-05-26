<#
.SYNOPSIS
Return the current thread identifier used by our runtime.

.DESCRIPTION
`Get-ThreadId` returns the thread id stored in the runtime private threading
container. It is a convenience helper to avoid repeating the global variable path.

.OUTPUTS
System.String — The current thread GUID string, or $null if not set.

.EXAMPLE
PS> Get-ThreadId

.NOTES
The value is read from `(Get-GlobalRuntimeVariable).Private.Threading.ThreadId`.
#>
function Get-ThreadId()
{
    # Return the ID of the current thread
    # Easier, as we don't have to remember the global variable name everywhere
    return (Get-GlobalRuntimeVariable).Private.Threading.ThreadId;
}

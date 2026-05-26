<#
.SYNOPSIS
Forcibly terminate the current PowerShell process used by Icinga

.DESCRIPTION
`Exit-Icinga` stops the current PowerShell process immediately to avoid the
shell freezing due to background threads that do not terminate on a normal
exit. It forcibly kills the process identified by $PID.

.OUTPUTS
None — The process is terminated immediately; no value is returned.

.EXAMPLE
PS> Exit-Icinga

.NOTES
Implementation uses Stop-Process -Force -Id $PID. Intended for scenarios where
a graceful shutdown cannot be achieved. Use with caution: cleanup routines and
background jobs will not complete and state may be lost or inconsistent.
#>
function Exit-Icinga()
{
    # Ensures we close the current PowerShell by forcing it's termination
    # This is required as a simple "exit" would cause the shell to freeze,
    # waiting for the background threads to stop (which they won't)
    Stop-Process -Force -Id $PID;
}

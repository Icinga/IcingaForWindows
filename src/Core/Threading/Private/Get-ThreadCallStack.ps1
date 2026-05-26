<#
.SYNOPSIS
Get a readable breadcrumb-style name for the current thread call stack.

.DESCRIPTION
`Get-ThreadCallStack` inspects the PowerShell call stack to construct a compact,
human-readable thread name by joining function names with '`::`'. It normalizes
scriptblock entries and removes internal `Set-ThreadData` frames.

.OUTPUTS
System.String — A single-line thread name derived from the call stack.

.EXAMPLE
PS> Get-ThreadCallStack

.NOTES
Used for naming threads created with `New-Thread` to aid diagnostics and tracing.
#>
function Get-ThreadCallStack()
{
    # Get our current call stack
    [array]$CallStack = (Get-PSCallStack).FunctionName;

    # Remove the first two entries
    $RealCallStack    = $CallStack[2..($CallStack.Count - 1)]

    # Reverse the order
    $ActualBreadcrumb = [System.Collections.ArrayList]::new($RealCallStack)
    $ActualBreadcrumb.Reverse()

    # Join into a string with '::' separator
    # We remove "Set-ThreadData::" as this would apply to all threads we start as this function is in the
    # callstack for actually creating the thread. To keep the naming and later displaying as limited as possible,
    # just remove it
    $ThreadName       = ($ActualBreadcrumb -join '::').Replace('<ScriptBlock>', 'Main').Replace('Set-ThreadData::', '');
   
    # Return the thread name
    return $ThreadName;
}

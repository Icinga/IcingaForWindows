<#
.SYNOPSIS
Initialize thread-local runtime state inside a new runspace.

.DESCRIPTION
`Set-ThreadData` is invoked inside threads created by `New-Thread`. It sets up
the base environment, configures the public and protected runtime containers,
registers the thread id, validates the requested command and finally invokes it
with the supplied parameters.

.PARAMETER PublicSpace
| Name | Type | Description | Default |
|------|------|-------------|---------|
| PublicSpace | System.Object | Shared public runtime object to attach to the thread | $null |

.PARAMETER AccessControl
| Name | Type | Description | Default |
|------|------|-------------|---------|
| AccessControl | System.Object | Access control descriptor to attach to protected runtime area | $null |

.PARAMETER ThreadId
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ThreadId | System.String | The thread id assigned by the creator | $null |

.PARAMETER Command
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Command | System.String | The command/function name to execute in the thread | $null |

.PARAMETER Parameters
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Parameters | System.Hashtable | Named parameters to pass to `Command` | @{} |

.OUTPUTS
Varies. The invoked `Command` determines output; error conditions return structured cmdlet returns.

.EXAMPLE
PS> Set-ThreadData -PublicSpace $GlobalPublic -AccessControl $ac -ThreadId $tid -Command 'RunWorker' -Parameters @{ 'Queue' = $q }

.NOTES
Called exclusively by New-Thread; do not invoke directly. Calls New-ModuleBaseEnvironment to set
up the runspace and sets (Get-GlobalRuntimeVariable).Protected.IsBackgroundDaemon to $true so
that downstream functions know they are executing in a background context. Thread identity is
tracked via Update-LoggingThreadLoggingId for log correlation.
#>
function Set-ThreadData()
{
    param (
        $PublicSpace           = $null,
        $AccessControl         = $null,
        [string]$ThreadId      = $null,
        [string]$Command       = $null,
        [hashtable]$Parameters = @{ }
    );

    # Always ensure no progress is shown in sessions
    $ProgressPreference = 'SilentlyContinue';

    # As this is a new thread instance, we will run this function to load our base environment
    New-ModuleBaseEnvironment;

    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Update the logging ID for this thread to ensure logs are properly tagged an traceable
    # Set it to the provided ThreadId to ensure we can track all logs from the start of the thread
    Update-LoggingThreadLoggingId -ThreadId $ThreadId;
    # Mark this as a background daemon, because we might fetch certain
    # information what should be handled as objects
    # Example: Write-LoggingEntry will return the LogMessage object if the type is 'Object'
    $GlobalVariable.Protected.IsBackgroundDaemon = $true;

    # Now after our base environment is ready, we can check if we have both parameters
    if ($null -eq $PublicSpace -or [string]::IsNullOrEmpty($ThreadId)) {
        return (Write-FunctionReturnValue -ReturnValue 'ThreadDataMissing' -Data @{ 'PublicSpace' = $PublicSpace; 'ThreadId' = $ThreadId } -OverrideReturn $null);
    }

    # Set the current thread ID for this thread
    $GlobalVariable.Private.Threading.ThreadId = $ThreadId;

    # Update the public space if provided to share data between threads
    $GlobalVariable.Public                     = $PublicSpace;

    # Mark the environment as initialized, because we skipped the proper entry point and are sharing the public space
    $GlobalVariable.Protected.Initialized      = $true;
    $GlobalVariable.Protected.AccessControl    = $AccessControl;
    # TODO: We need to properly set colorized output setting here

    # Check if the command is directly available in the session or in the script module
    $CommandExists = ($null -ne (Get-Command -Name $Command -ErrorAction SilentlyContinue));
    $ScriptModule  = $null;

    if (-not $CommandExists) {
        $ScriptModule = Get-Module -Name 'IcingaForWindows' -All | Where-Object { $_.ModuleType -eq 'Script' } | Select-Object -First 1;
    }

    if (-not $CommandExists -and $null -eq $ScriptModule) {
        Stop-Thread -ThreadId $ThreadId;
        return (Write-FunctionReturnValue -ReturnValue 'ThreadCommandNotFound' -Data @{ 'Command' = $Command } -OverrideReturn $null);
    }

    # Once everything is initialized, call the command with the arguments
    if ($null -ne $ScriptModule) {
        & $ScriptModule $Command @Parameters;
    } else {
        & $Command @Parameters;
    }
}

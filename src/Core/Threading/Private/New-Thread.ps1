<#
.SYNOPSIS
Create and (optionally) start a managed background PowerShell thread.

.DESCRIPTION
`New-Thread` creates a PowerShell runspace with a thread-local environment,
registers the thread in the global threading registry and optionally starts it.
The function supports keep-alive semantics and parent/child relationships.

.PARAMETER Command
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Command | System.String | The command (function) name to execute in the thread | |

.PARAMETER Parameters
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Parameters | System.Hashtable | Named parameters passed to the command | @{} |

.PARAMETER ParentThread
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ParentThread | System.String | Optional parent thread id (defaults to current thread) | $null |

.PARAMETER OverrideName
| Name | Type | Description | Default |
|------|------|-------------|---------|
| OverrideName | System.String | Optional explicit display name for the created thread | $null |

.PARAMETER Start
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Start | System.SwitchParameter | When set, start the thread immediately after creation | $false |

.PARAMETER KeepAlive
| Name | Type | Description | Default |
|------|------|-------------|---------|
| KeepAlive | System.SwitchParameter | When set, the housekeeper may restart the thread on failure | $false |

.PARAMETER WaitForJobs
| Name | Type | Description | Default |
|------|------|-------------|---------|
| WaitForJobs | System.SwitchParameter | When set the thread is expected to wait for queued jobs | $false |

.OUTPUTS
System.String. The newly created thread id.

.EXAMPLE
PS> New-Thread -Command 'Start-Worker' -Parameters @{ 'Queue' = $q } -Start

.NOTES
This helper uses `Set-ThreadData` in the created runspace to initialize thread-local state.
#>
function New-Thread()
{
    param (
        [string]$Command       = $null,
        [hashtable]$Parameters = @{ },
        [string]$ParentThread  = $null,
        [string]$OverrideName  = $null,
        [switch]$Start         = $false,
        [switch]$KeepAlive     = $false,
        [switch]$WaitForJobs   = $false
    );

    # Get the current call stack to name the thread appropriately
    [string]$CallStack  = (Get-ThreadCallStack);
    [string]$ThreadName = $CallStack;

    # If the call stack differs from the command, append the command for clarity
    if ($CallStack.ToLower() -ne $Command.ToLower()) {
        $ThreadName = [string]::Format('{0}::{1}', $CallStack, $Command);
    }

    # If the call stack does only contain one '::', this means we are being called by another thread
    # As we display the thread later on with a proper parent/child relationship, we can just use the command name here
    if ($CallStack.Split('::').Count -eq 1) {
        $ThreadName = $Command;
    }

    [string]$ThreadId   = (New-Guid);
    $Shell              = [PowerShell]::Create();
    $Shell.RunSpacePool = New-ThreadPool;

    Write-LoggingEntry -Message 'Creating new thread' -Level 'Debug' -Data @{
        'ThreadId'   = $ThreadId;
        'CallStack'  = $CallStack;
        'Command'    = $Command;
        'Parameters' = $Parameters;
        'Start'      = $Start;
    };

    # Initialize the thread for Windows environment in each thread and share the public data
    [void]$Shell.AddCommand('Set-ThreadData');
    [void]$Shell.AddParameter('PublicSpace', (Get-GlobalRuntimeVariable).Public);
    [void]$Shell.AddParameter('AccessControl', (Get-GlobalRuntimeVariable).Protected.AccessControl);
    [void]$Shell.AddParameter('ThreadId', $ThreadId);
    # To ensure we have a proper "Private" and "Public" space, we will use the "Set-ThreadData" function
    # to actually call all our thread functions with the given parameters
    # This ensures the function we try to call is always inside the scope of the specific thread module
    # and will never fail.
    [void]$Shell.AddParameter('Command', $Command);
    [void]$Shell.AddParameter('Parameters', $Parameters);

    # Determine the parent thread if not provided
    if ([string]::IsNullOrEmpty($ParentThread)) {
        $ParentThread = (Get-ThreadId);
    } elseif ($ParentThread -eq 'MAIN') {
        # In case our parent thread is MAIN, we set it to null, as this would be added to the main root
        # For displaying the thread tree later on
        $ParentThread = $null;
    }

    # OverrideName does only apply for the Housekeeper and similar supervisory threads
    # In case the thread which we try to keepalive is part of MAIN, we want to keep the original name
    # to ensure the thread tree display remains correct
    if (-not [string]::IsNullOrEmpty($OverrideName)) {
        $ThreadName = $OverrideName;
    }

    # Create the thread object to track this thread and add the current configuration in case we
    # use KeepAlive functionality later on to track alive states and restart the thread if needed
    $ThreadObj = New-Object PSObject;
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'Name'         -Value $ThreadName;
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'Shell'        -Value $Shell;
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'Command'      -Value $Command;
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'Parameters'   -Value $Parameters;
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'KeepAlive'    -Value ([bool]$KeepAlive);
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'WaitForJobs'  -Value ([bool]$WaitForJobs);
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'ParentThread' -Value $ParentThread;
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'LastSeen'     -Value (Get-Date);
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'Stopwatch'    -Value ([System.Diagnostics.Stopwatch]::StartNew());
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'Handle'       -Value $null;
    Add-Member -InputObject $ThreadObj -MemberType NoteProperty -Name 'State'        -Value 'STOPPED';

    # Add the thread to the global thread list for tracking
    (Get-GlobalRuntimeVariable).Public.Threading.Threads | Add-Member -MemberType NoteProperty -Name $ThreadId -Value $ThreadObj;

    # Start the thread if requested
    if ($Start) {
        try {
            $ShellData        = $ThreadObj.Shell.BeginInvoke();
            $ThreadObj.Handle = $ShellData;

            # If we wait for jobs, we set the initial state to PROCESSING, indicating the thread is doing something (it is still starting), otherwise to RUNNING
            # This will ensure we have the correct state tracking from the beginning of the thread lifecycle
            if ($WaitForJobs) {
                $ThreadObj.State = 'PROCESSING';
            } else {
                $ThreadObj.State = 'RUNNING';
            }
        } catch {
            return (Write-FunctionReturnValue -ReturnValue 'ThreadCreationFailed' -Data @{ 'Command' = $Command; 'Exception' = $_.Exception } -OverrideReturn $null);
        }

        Start-Sleep -Milliseconds 500; # Allow some time for the thread to start properly
    }
}

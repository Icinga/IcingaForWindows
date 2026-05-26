<#
.SYNOPSIS
Initialize the IcingaForWindows runtime environment in the current session

.DESCRIPTION
`Use-IcingaForWindows` performs the necessary startup tasks for the Icinga
PowerShell module. When called without `-NoNewShell` it spawns a new
PowerShell process (preferring pwsh over powershell.exe) and re-invokes
itself with `-NoNewShell` in that child process. When called with
`-NoNewShell` it initializes the base environment, applies the log level,
loads configuration and access control, and starts the standard background
daemon threads (logging, garbage collector, housekeeper, REST API, WebSocket
and Icinga agent). The function is idempotent; repeated calls while already
initialized return immediately.

.PARAMETER LogLevel
| Name | Type | Description | Default |
|------|------|-------------|---------|
| LogLevel | System.String | Minimum log level for the session. Accepted values: Debug, Audit, Info, Success, Warning, Error, Fatal. | Warning |

.PARAMETER NoBackgroundDaemons
| Name | Type | Description | Default |
|------|------|-------------|---------|
| NoBackgroundDaemons | System.Management.Automation.SwitchParameter | Reserved for future use; currently has no effect on daemon startup. | $false |

.PARAMETER NoNewShell
| Name | Type | Description | Default |
|------|------|-------------|---------|
| NoNewShell | System.Management.Automation.SwitchParameter | When set, initialize directly in the current shell instead of spawning a new process. | $false |

.OUTPUTS
None — Side effects only: starts background threads and configures global runtime state.

.EXAMPLE
PS> Use-IcingaForWindows

.NOTES
Depends on New-ModuleBaseEnvironment, New-ModuleConfigEnvironment,
Read-ModuleAccessControl and the daemon functions being available in scope.
The alias `ifw` maps to this function. When running without `-NoNewShell`
the function blocks until the spawned child process exits.
#>

function Use-IcingaForWindows()
{
    param (
        [ValidateSet('Debug', 'Audit', 'Info', 'Success', 'Warning', 'Error', 'Fatal')]
        [string]$LogLevel            = 'Warning',
        [switch]$NoBackgroundDaemons = $false,
        [switch]$NoNewShell          = $false
    );

    if ($null -ne $Global:IcingaForWindows) {
        if ($Global:IcingaForWindows.Protected.Initialized) {
            return;
        }
    }

    if ($NoNewShell) {
        # Initialize the base environment
        New-ModuleBaseEnvironment;

        # Apply te log level to our environment
        Set-LoggingLogLevel -Level $LogLevel;

        # Only apply this for the main, initial call.
        New-ModuleConfigEnvironment | Out-Null;

        # Read and apply access control settings
        Read-ModuleAccessControl | Out-Null;

        # Create our default background threads
        New-Thread -Command 'Start-LoggingDaemon' -KeepAlive -WaitForJobs -Start;
        New-Thread -Command 'Start-ModuleGarbageCollector' -KeepAlive -Start;
        New-Thread -Command 'Start-ThreadHouseKeeper' -Start;
        New-Thread -Command 'Start-RestApiDaemon' -Start;
        New-Thread -Command 'Start-ModuleWebSocketDaemon' -Start;
        New-Thread -Command 'Start-IcingaAgent' -Start;

        # Ensure we set our environment initialized flag to avoid re-initialization
        $Global:IcingaForWindows.Protected.Initialized = $true;
    } else {
        $PSBinary = 'powershell.exe';

        # Prefer PowerShell 7 over PowerShell 5
        if ($null -ne (Get-Command 'pwsh' -ErrorAction SilentlyContinue)) {
            $PSBinary = 'pwsh';
        }

        & $PSBinary -NoProfile -NoExit -ExecutionPolicy 'ByPass' -Command {
            [string]$LogLevel = $args[0];

            # To prevent code duplication, just let this PowerShell session call
            # IcingaForWindows, but do not start a new shell. This will ensure we
            # have a proper call stack and can manage everything way easier
            Use-IcingaForWindows -NoNewShell -LogLevel $LogLevel;

            function prompt {
                Write-Host -Object 'icinga' -NoNewline;
                return '> '
            }
        } -Args $LogLevel;
    }
}

# Create an alias for us, which allows to simply use 'icinga' in the shell
Set-Alias -Name 'ifw' -Value 'Use-IcingaForWindows';

<#
.SYNOPSIS
Initializes the global IcingaForWindows runtime environment and default configuration.

.DESCRIPTION
New-ModuleBaseEnvironment creates and assigns a thread-safe, synchronized hashtable to the global variable $Global:IcingaForWindows.
This hashtable contains pre-populated nested sections for Public, Private, and Protected data. The Public section includes
default configuration settings (file root, theme, color palette, TLS protocol flags), placeholders for REST API and Icinga
protocol internals (worker queues, endpoints, connections), and empty registries for active threads, external integrations,
and return codes.

This function is intended to be called once at module initialization to ensure a known runtime state for other module
components to read from and modify. It purposely uses a synchronized hashtable for safe concurrent access from multiple
threads or background jobs.

.PARAMETER None
This function does not accept parameters.

.OUTPUTS
System.Collections.Hashtable
The function populates $Global:IcingaForWindows and does not return a value. Consumers should read and manipulate the
global hashtable directly (for example: $Global:IcingaForWindows['Public']['Config']).

.NOTES
- Global variable: $Global:IcingaForWindows
- The configuration root is set to Join-Path -Path $env:ProgramData -ChildPath 'IcingaForWindows'.
- Default theme: 'DefaultDark'.
- Colors are represented as string names intended for console/ANSI color use (Font, Info, Success, Warning, Error, Text).
- TLS protocols: combines SslProtocols.Tls12 and SslProtocols.Tls13 using bitwise OR. Availability of Tls13 depends on
    the underlying .NET/Windows runtime; on platforms without Tls13 support you may need to adjust this setting.
- The function overwrites any existing $Global:IcingaForWindows value.

.EXAMPLE
# Initialize the base environment (run during module import/initialization)
New-ModuleBaseEnvironment

# Access configuration root path
$root = $Global:IcingaForWindows['Public']['Config']['Root']

# Register an Icinga protocol endpoint
$Global:IcingaForWindows['Public']['IcingaProtocol']['Endpoints']['Default'] = @{
        Host = '127.0.0.1'
        Port = 5665
        Secure = $true
}

# Check TLS protocols configured
$Global:IcingaForWindows['Public']['Config']['TLS']['Protocol']

# Note: This function is safe to call multiple times but will reinitialize the global structure,
# so call carefully if other components hold references into the hashtable.
#>

function New-ModuleBaseEnvironment()
{
    if ($null -ne $Global:IcingaForWindows) {
        return;
    }

    [string]$OSType = 'Windows';

    # Fix for Linux and MacOS where ProgramData is not set by default, using a .ProgramData folder in the user's home directory as fallback
    if ($null -eq $env:ProgramData) {
        $OSType          = 'Linux';
        $env:ProgramData = Join-Path -Path $env:HOME -ChildPath 'ProgramData';
        New-Item -Path $env:ProgramData -ItemType Directory -ErrorAction Ignore | Out-Null;
    }

    $Global:IcingaForWindows = @{
        'Public'    = [hashtable]::Synchronized(
            @{
                'Config'         = [PSCustomObject]@{
                    'Root'     = (Join-Path -Path $env:ProgramData -ChildPath (Get-ModuleProjectName));
                    'Theme'    = 'DefaultDark';
                    'Colors'   = [PSCustomObject]@{
                        'Debug'   = 'Magenta';
                        'Audit'   = 'DarkGreen';
                        'Info'    = 'Cyan';
                        'Success' = 'Green';
                        'Warning' = 'Yellow';
                        'Error'   = 'Red';
                        'Fatal'   = 'Red';
                        'Text'    = 'White';
                        'Output'  = 'White';
                    };
                    'TCP'      = [PSCustomObject]@{
                        'TLS'          = [PSCustomObject]@{
                            'Protocols' = [System.Security.Authentication.SslProtocols]::Tls12;
                        };
                        'ReadTimeout'  = 5000;
                        'WriteTimeout' = 5000;
                    };
                };
                'RestApi'       = [PSCustomObject]@{
                    'Config'      = [PSCustomObject]@{
                        'ListenAddress' = $null;
                        'ListenPort'    = $null;
                        'TlsCertConfig' = $null;
                        'WorkerCount'   = 5;
                    };
                    'Certificate' = $null;
                    'WorkerQueue' = $null;
                };
                'WebSocket'    = [PSCustomObject]@{
                    'Config'      = New-Object PSCustomObject; # Global config, containing all endpoints being loaded
                <#
                    WebSocket example structure:
                    $WebSocketName = [PSCustomObject]@{
                    'Config'      = [PSCustomObject]@{
                            'Type'             = $null;
                            'AuthPayload'      = $null;
                            'KeepAlivePayload' = $null;
                            'KeepAliveTimer'   = $null;
                        };
                        'ReaderWorker' = (New-Object System.Collections.Concurrent.BlockingCollection[string] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[string]));
                        'WriterWorker' = (New-Object System.Collections.Concurrent.BlockingCollection[string] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[string]));
                    };
                #>
                };
                'IcingaProtocol' = [PSCustomObject]@{
                    'Config'        = [PSCustomObject]@{
                        'ListenAddress' = $null;
                        'ListenPort'    = $null;
                        'Endpoints'     = $null;
                        'Zone'          = $null;
                        'Hostname'      = $null;
                        'TlsCertConfig' = $null;
                        'WorkerCount'   = 5;
                    };
                    'Certificate' = $null;
                    'Connections' = $null;
                    'WorkerQueue' = $null;
                    'WriterQueue' = (New-Object PSCustomObject);
                };
                'Threading'     = [PSCustomObject]@{
                    'ThreadPool' = $null;
                    'Threads'    = (New-Object PSCustomObject);
                    'IdleTime'   = 30;
                    'KeepAlive'  = 180;
                    'MaxThreads' = 200;
                };
                'Logging'       = [PSCustomObject]@{
                    'Queue' = (New-Object System.Collections.Concurrent.BlockingCollection[PSObject] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[PSObject]));
                    'Level' = 'Info';
                };
                'External'       = $null;
                'ReturnCodes'    = $null;
            }
        );
        'Private'   = [PSCustomObject]@{
            'TCP' = [PSCustomObject]@{
                'Listener'               = $null;
                'Certificate'            = $null;
                'Client'                 = $null;
                'Stream'                 = $null;
                'LastWorkerId'           = $null;
                'SocketTimeoutInSeconds' = 20;
                'HeartbeatTimer'         = $null;
                'HeartbeatInterval'      = 6;
            };
            'WebSocket' = [PSCustomObject]@{
                'Name'                    = $null;
                'ClientWebSocket'         = $null;
                'CancellationTokenSource' = $null;
            };
            'RestApi' = [PSCustomObject]@{
                'Header'        = $null;
                'Body'          = $null;
                'WebPath'       = $null;
                'ContentLength' = 0;
                'Spaces'        = $null;
            };
            'Threading' = [PSCustomObject]@{
                'ThreadId' = $null;
            };
            'Logging' = [PSCustomObject]@{
                'CurrentLoggingId' = (New-Guid);
            };
        };
        'Protected' = [PSCustomObject]@{
            'Initialized'        = $false;
            'AccessControl'      = $null;
            'IsBackgroundDaemon' = $false;
            'ModulesImported'    = $false;
            'IsAutomationRun'    = $false;
            'NoColorizedOutput'  = $false;
            'OSType'             = $OSType;
            'Version'            = '27.0.0.0';
        };
    };
}

function Get-ModuleRootDirectory()
{
    return $PSScriptRoot;
}

function Get-ModuleConfigDirectory()
{
    return (Join-Path -Path $env:ProgramData -ChildPath (Join-Path -Path (Get-ModuleProjectName) -ChildPath 'Config'));
}

function Get-ModuleCacheDirectory()
{
    return (Join-Path -Path $env:ProgramData -ChildPath (Join-Path -Path (Get-ModuleProjectName) -ChildPath 'Cache'));
}

function Get-ModuleCertificateDirectory()
{
    return (Join-Path -Path $env:ProgramData -ChildPath (Join-Path -Path (Get-ModuleProjectName) -ChildPath 'Certificates'));
}

function Build-ModuleProject()
{
    param (
        [string]$BuildModule = 'core',
        [switch]$SkipTests   = $false
    );

    & (Join-Path -Path $PSScriptRoot -ChildPath 'build\Build-ModuleProject.ps1');
}

function Get-GlobalRuntimeVariable()
{
    return $Global:IcingaForWindows;
}

function Get-ModuleProjectName()
{
    return 'IcingaForWindows';
}

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

<#
DO NOT place any code below this line.
This section is reserved for module initialization and is fully managed by the build system.
All custom declarations must be added above this comment block.
#>
New-ModuleBaseEnvironment;

[string]$KernelPath = Join-Path -Path (Get-ModuleRootDirectory) -ChildPath (Join-Path -Path 'lib' -ChildPath 'IcingaForWindows.Kernel.ps1');

if (Test-Path -Path $KernelPath) {
    . $KernelPath;
} else {
    Write-Warning "Icinga for Windows kernel file not found at '$KernelPath'. Run Build-ModuleProject first.";
}

# Export alias and all public functions
Export-ModuleMember -Alias @( 'ifw' ) -Function @( 'Use-IcingaForWindows' );
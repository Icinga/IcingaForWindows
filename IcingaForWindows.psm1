<#
.SYNOPSIS
Initialize the global Icinga for Windows runtime environment and default configuration

.DESCRIPTION
New-ModuleBaseEnvironment creates and assigns a thread-safe, synchronized hashtable to the global variable $Global:IcingaForWindows.
This hashtable contains pre-populated nested sections for Public, Private, and Protected data. The Public section includes
default configuration settings (file root, theme, color palette, TLS protocol flags), placeholders for REST API and Icinga
protocol internals (worker queues, endpoints, connections), and empty registries for active threads, external integrations,
and return codes.

This function is intended to be called once at module initialization to ensure a known runtime state for other module
components to read from and modify. It purposely uses a synchronized hashtable for safe concurrent access from multiple
threads or background jobs.

.OUTPUTS
None -- Populates $Global:IcingaForWindows in place and does not return a pipeline value.

.EXAMPLE
PS> New-ModuleBaseEnvironment
PS> $Root = $Global:IcingaForWindows['Public']['Config']['Root']

Initializes the base runtime state and reads the configured Icinga for Windows ProgramData root path.

.NOTES
- Global variable: $Global:IcingaForWindows
- The configuration root is set to Join-Path -Path $env:ProgramData -ChildPath 'IcingaForWindows'.
- Default theme: 'DefaultDark'.
- Colors are represented as string names intended for console/ANSI color use (Debug, Audit, Info, Success, Warning, Error, Fatal, Text, Output).
- Function is idempotent when $Global:IcingaForWindows is already initialized.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-ModuleBaseEnvironment()
{
    if ($null -ne $Global:IcingaForWindows) {
        return;
    }

    [string]$OSType = 'Windows';

    # Fix for Linux and macOS where ProgramData is not set by default, using a ProgramData folder in the user's home directory as fallback
    if ($null -eq $env:ProgramData) {
        $OSType          = 'Linux';
        $env:ProgramData = Join-Path -Path $env:HOME -ChildPath 'ProgramData';
        New-Item -Path $env:ProgramData -ItemType Directory -ErrorAction Ignore | Out-Null;
    }

    $Global:IcingaForWindows = @{
        'Public'    = [hashtable]::Synchronized(
            @{
                'Config'         = [PSCustomObject]@{
                    'ModuleRoot' = $PSScriptRoot;
                    'Root'       = (Join-Path -Path $env:ProgramData -ChildPath (Get-ModuleProjectName));
                    'Theme'      = 'DefaultDark';
                    'Colors'     = [PSCustomObject]@{
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
                    'Config' = New-Object PSCustomObject; # Global config, containing all endpoints being loaded
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
                'PerformanceCounter' = [PSCustomObject]@{
                    # Thread-safe transport only. The counter manager class is created lazily
                    # by the daemon once the kernel (and thus the class type) is dot-sourced.
                    'RequestQueue'    = (New-Object System.Collections.Concurrent.BlockingCollection[PSObject] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[PSObject]));
                    'PendingRequests' = (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, System.Collections.Concurrent.BlockingCollection[PSObject]]');
                    'Registered'      = (New-Object 'System.Collections.Concurrent.ConcurrentDictionary[string, datetime]');
                    'Manager'         = $null;
                    'Heartbeat'       = $null;
                    'LastRefresh'     = $null;
                    'Config'          = [PSCustomObject]@{
                        'WarmupMilliseconds' = 250;
                        'RefreshIntervalMs'  = 1000;
                        'EvictionMinutes'    = 60;
                    };
                };
                'External'    = $null;
                'ReturnCodes' = $null;
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
            'Icinga' = [PSCustomObject]@{
                'CheckResult'        = $null;
                'ActiveCheckCommand' = $null;
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
    if ($null -ne $Global:IcingaForWindows -and $null -ne $Global:IcingaForWindows.Public -and $null -ne $Global:IcingaForWindows.Public.Config -and -not [string]::IsNullOrEmpty($Global:IcingaForWindows.Public.Config.ModuleRoot)) {
        return $Global:IcingaForWindows.Public.Config.ModuleRoot;
    }

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

<#
.SYNOPSIS
Return the approved directory path for external check binaries and scripts

.DESCRIPTION
Get-ModuleBinaryDirectory resolves the dedicated Binaries subdirectory inside
the Icinga for Windows ProgramData root ($env:ProgramData\IcingaForWindows\Binaries
on Windows, or $env:HOME\ProgramData\IcingaForWindows\Binaries on Linux and
macOS). Resolve-IcingaProtocolCommand and Invoke-IcingaProtocolCheckCommand
restrict external binary and .ps1 script execution exclusively to this folder.

.OUTPUTS
System.String -- Full path to the Icinga for Windows Binaries directory.

.EXAMPLE
PS> Get-ModuleBinaryDirectory
C:\ProgramData\IcingaForWindows\Binaries

Returns the approved Icinga for Windows binaries directory path.

.NOTES
Created automatically during startup by New-ModuleConfigEnvironment and
whitelisted in Get-SecureChildItem.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-ModuleBinaryDirectory()
{
    return (Join-Path -Path $env:ProgramData -ChildPath (Join-Path -Path (Get-ModuleProjectName) -ChildPath 'Binaries'));
}

<#
.SYNOPSIS
Build and compile the Icinga for Windows module project

.DESCRIPTION
`Build-ModuleProject` is the entry point to compile the Icinga for Windows
module. It consolidates all source files into the classes and kernel artifacts
under `lib/`, reloads the module manifest, and optionally generates API
documentation or executes memory-leak and code-styling checks.

.PARAMETER SkipTests
| Name      | Type                                         | Description                                              | Default |
|-----------|----------------------------------------------|----------------------------------------------------------|---------|
| SkipTests | System.Management.Automation.SwitchParameter | When set, skip running automated tests during the build. | $false  |

.PARAMETER GenerateDocs
| Name         | Type                                         | Description                                                        | Default |
|--------------|----------------------------------------------|--------------------------------------------------------------------|---------|
| GenerateDocs | System.Management.Automation.SwitchParameter | When set, regenerate API Markdown documentation from comment help. | $false  |

.PARAMETER TestDaemonMemoryLeaks
| Name                  | Type                                         | Description                                    | Default |
|-----------------------|----------------------------------------------|------------------------------------------------|---------|
| TestDaemonMemoryLeaks | System.Management.Automation.SwitchParameter | When set, run daemon memory leak AST checks.   | $false  |

.PARAMETER TestCodeStyling
| Name            | Type                                         | Description                                               | Default |
|-----------------|----------------------------------------------|-----------------------------------------------------------|---------|
| TestCodeStyling | System.Management.Automation.SwitchParameter | When set, run repository code-styling and SPDX checks.    | $false  |

.OUTPUTS
None -- Side effects only: generates module artifacts under lib/ and docs/.

.EXAMPLE
PS> Build-ModuleProject -GenerateDocs

Compiles the module and generates API documentation.

.NOTES
Invokes build/Build-ModuleProject.ps1 in the module directory.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Build-ModuleProject()
{
    param (
        [switch]$SkipTests             = $false,
        [switch]$GenerateDocs          = $false,
        [switch]$TestDaemonMemoryLeaks = $false,
        [switch]$TestCodeStyling       = $false
    );

    & (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path 'build' -ChildPath 'Build-ModuleProject.ps1')) -SkipTests:$SkipTests -GenerateDocs:$GenerateDocs -TestDaemonMemoryLeaks:$TestDaemonMemoryLeaks -TestCodeStyling:$TestCodeStyling;
}

<#
.SYNOPSIS
Execute Pester tests for the Icinga for Windows module

.DESCRIPTION
`Invoke-IcingaModuleTests` runs the Pester test suite against the local module.
It executes all test suites under the specified path or the default `Tests/`
directory using `build/Invoke-ModuleTests.ps1`.

.PARAMETER Path
| Name | Type          | Description                                                                          | Default |
|------|---------------|--------------------------------------------------------------------------------------|---------|
| Path | System.String | Path to a specific test file or directory containing Pester test suites to execute.  | $null   |

.OUTPUTS
System.Object -- Pester test result summary object and test execution output.

.EXAMPLE
PS> Invoke-IcingaModuleTests

Executes all test suites in the default Tests/ directory.

.EXAMPLE
PS> Invoke-IcingaModuleTests -Path 'Tests/MemoryLeak.Tests.ps1'

Executes only the memory leak test suite.

.NOTES
Requires the Pester module (5.0 or newer) to be installed and available in the session.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaModuleTests()
{
    param (
        [string]$Path = $null
    );

    & (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path 'build' -ChildPath 'Invoke-ModuleTests.ps1')) -Path $Path;
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
Initialize the Icinga for Windows runtime environment in the current session

.DESCRIPTION
`Use-IcingaForWindows` performs the necessary startup tasks for the Icinga for
Windows PowerShell module. When called without `-NoNewShell` it spawns a new
PowerShell process (preferring pwsh over powershell.exe) and re-invokes
itself with `-NoNewShell` in that child process. When called with
`-NoNewShell` it initializes the base environment, applies the log level,
loads configuration and access control, and starts the standard background
daemon threads (logging, garbage collector, housekeeper, performance counter,
REST API, WebSocket and Icinga agent). The function is idempotent; repeated
calls while already initialized return immediately.

.PARAMETER LogLevel
| Name     | Type          | Description                                                                                             | Default |
|----------|---------------|---------------------------------------------------------------------------------------------------------|---------|
| LogLevel | System.String | Minimum log level for the session. Accepted values: Debug, Audit, Info, Success, Warning, Error, Fatal. | Warning |

.PARAMETER RunBackgroundDaemons
| Name                 | Type                                         | Description                                                                                                                                            | Default |
|----------------------|----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| RunBackgroundDaemons | System.Management.Automation.SwitchParameter | When set, start the standard background daemon threads (logging, garbage collector, housekeeper, REST API, WebSocket, Icinga agent). Default is false. | $false  |

.PARAMETER NoNewShell
| Name       | Type                                         | Description                                                                                     | Default |
|------------|----------------------------------------------|-------------------------------------------------------------------------------------------------|---------|
| NoNewShell | System.Management.Automation.SwitchParameter | When set, initialize directly in the current shell instead of spawning a new process.           | $false  |

.OUTPUTS
None -- Side effects only: configures global runtime state and optionally starts background threads.

.EXAMPLE
PS> Use-IcingaForWindows
PS> Use-IcingaForWindows -RunBackgroundDaemons

.NOTES
Depends on New-ModuleBaseEnvironment, New-ModuleConfigEnvironment,
Read-ModuleAccessControl and the daemon functions being available in scope.
The alias `ifw` maps to this function. When running without `-NoNewShell`
the function blocks until the spawned child process exits.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Use-IcingaForWindows()
{
    param (
        [ValidateSet('Debug', 'Audit', 'Info', 'Success', 'Warning', 'Error', 'Fatal')]
        [string]$LogLevel             = 'Warning',
        [switch]$RunBackgroundDaemons = $false,
        [switch]$NoNewShell           = $false
    );

    if ($null -ne $Global:IcingaForWindows) {
        if ($Global:IcingaForWindows.Protected.Initialized) {
            return;
        }
    }

    if ($NoNewShell) {
        # Initialize the base environment
        New-ModuleBaseEnvironment;

        # Apply the log level to our environment
        Set-LoggingLogLevel -Level $LogLevel;

        # Only apply this for the main, initial call.
        New-ModuleConfigEnvironment | Out-Null;

        # Read and apply access control settings
        Read-ModuleAccessControl | Out-Null;

        if ($RunBackgroundDaemons) {
            # Create our default background threads
            New-Thread -Command 'Start-LoggingDaemon' -KeepAlive -WaitForJobs -Start;
            New-Thread -Command 'Start-ModuleGarbageCollector' -KeepAlive -Start;
            New-Thread -Command 'Start-ThreadHouseKeeper' -Start;
            New-Thread -Command 'Start-IcingaPerformanceCounterDaemon' -KeepAlive -WaitForJobs -Start;
            New-Thread -Command 'Start-RestApiDaemon' -Start;
            New-Thread -Command 'Start-ModuleWebSocketDaemon' -Start;
            New-Thread -Command 'Start-IcingaAgent' -Start;
        }

        # Ensure we set our environment initialized flag to avoid re-initialization
        $Global:IcingaForWindows.Protected.Initialized = $true;
    } else {
        $PSBinary = 'powershell.exe';

        # Prefer PowerShell 7 over PowerShell 5
        if ($null -ne (Get-Command 'pwsh' -ErrorAction SilentlyContinue)) {
            $PSBinary = 'pwsh';
        }

        & $PSBinary -NoProfile -NoExit -ExecutionPolicy 'ByPass' -Command {
            [string]$LogLevel           = $args[0];
            [bool]$RunBackgroundDaemons = [bool]$args[1];

            # To prevent code duplication, let this PowerShell session invoke
            # Use-IcingaForWindows directly without spawning another child shell
            # so the call stack and runtime state stay cleanly isolated.
            Use-IcingaForWindows -NoNewShell -LogLevel $LogLevel -RunBackgroundDaemons:$RunBackgroundDaemons;

            function prompt()
            {
                Write-Host -Object 'icinga' -NoNewline;
                return '> ';
            }
        } -Args $LogLevel, $RunBackgroundDaemons;
    }
}

# Create an alias for us, which allows to simply use 'ifw' in the shell
Set-Alias -Name 'ifw' -Value 'Use-IcingaForWindows';

<#
DO NOT place any code below this line.
This section is reserved for module initialization and is fully managed by the build system.
All custom declarations must be added above this comment block.
#>
New-ModuleBaseEnvironment;

[string]$ClassesPath = Join-Path -Path (Get-ModuleRootDirectory) -ChildPath (Join-Path -Path 'lib' -ChildPath 'IcingaForWindows.Classes.ps1');
[string]$KernelPath  = Join-Path -Path (Get-ModuleRootDirectory) -ChildPath (Join-Path -Path 'lib' -ChildPath 'IcingaForWindows.Kernel.ps1');

if (Test-Path -Path $ClassesPath) {
    # Windows PowerShell 5.1 reuses the compiled class types when the same class
    # content is loaded again by a thread runspace and binds their methods to the
    # runspace that loaded it last. Class methods called on the main thread then run
    # inside a busy daemon runspace, which hangs or corrupts the call. A unique copy
    # of the class content per runspace gives every runspace its own class types.
    # In PowerShell Core (PS 7+), class method dispatch is runspace-independent.
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        . ([ScriptBlock]::Create([System.IO.File]::ReadAllText($ClassesPath) + [System.Environment]::NewLine + '# ' + [System.Guid]::NewGuid().ToString()));
    } else {
        . $ClassesPath;
    }
} else {
    Write-Warning "Icinga for Windows classes file not found at '$ClassesPath'. Run Build-ModuleProject first.";
}

if (Test-Path -Path $KernelPath) {
    . $KernelPath;
} else {
    Write-Warning "Icinga for Windows kernel file not found at '$KernelPath'. Run Build-ModuleProject first.";
}

# Export alias and all public functions
Export-ModuleMember -Alias @( 'ifw' ) -Function @( 'Use-IcingaForWindows', 'Invoke-IcingaModuleTests' );

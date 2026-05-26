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
function Global:New-ModuleBaseEnvironment()
{
    if ($null -ne $Global:IcingaForWindows) {
        return;
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
        };
    };
}

function Global:Get-ModuleRootDirectory()
{
    return $PSScriptRoot;
}

function Global:Get-ModuleConfigDirectory()
{
    return (Join-Path -Path $env:ProgramData -ChildPath (Join-Path -Path (Get-ModuleProjectName) -ChildPath 'Config'));
}

function Global:Get-ModuleCacheDirectory()
{
    return (Join-Path -Path $env:ProgramData -ChildPath (Join-Path -Path (Get-ModuleProjectName) -ChildPath 'Cache'));
}

function Global:Get-ModuleCertificateDirectory()
{
    return (Join-Path -Path $env:ProgramData -ChildPath (Join-Path -Path (Get-ModuleProjectName) -ChildPath 'Certificates'));
}

function Global:Build-ModuleProject()
{
    param (
        [string]$BuildModule = 'core',
        [switch]$SkipTests   = $false
    );

    & (Join-Path -Path $PSScriptRoot -ChildPath 'build\Build-ModuleProject.ps1');
}

function Global:Get-GlobalRuntimeVariable()
{
    return $Global:IcingaForWindows;
}

function Global:Get-ModuleProjectName()
{
    return 'IcingaForWindows';
}

New-ModuleBaseEnvironment;

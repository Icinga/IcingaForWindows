<#
.SYNOPSIS
Initialize WebSocket runtime environments and start handler threads.

.DESCRIPTION
`New-ModuleWebSocketEnvironment` loads WebSocket configuration files,
creates per-instance runtime containers (reader/writer queues) and starts
handler threads for each configured WebSocket instance. The function ensures
that the public runtime structure is populated for subsequent operations.

.OUTPUTS
System.Object -- Returns a structured `Write-FunctionReturnValue` indicating
success or the absence of any configurations to initialize.

.EXAMPLE
PS> New-ModuleWebSocketEnvironment

.NOTES
Uses `Read-ModuleWebSocketConfig` to load persisted configurations and
`New-Thread` to spawn a `Start-ModuleWebSocketHandler` thread per instance.
Each instance receives its own `ReaderWorker` and `WriterWorker`
`BlockingCollection` stored in `$Global:ModuleName.Public.WebSocket`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-ModuleWebSocketEnvironment()
{
    # Load WebSocket configurations
    Read-ModuleWebSocketConfig;

    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Ensure we have at least one configuration to process
    if ($null -eq $GlobalVariable.Public.WebSocket.Config) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketNoConfigsFound');
    }

    # Start new WebSocket threads for each configuration
    foreach ($WebSocket in $GlobalVariable.Public.WebSocket.Config.PSObject.Properties.Name) {
        # Setup our public space for each WebSocket

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
        $WebSocketConfig = [PSCustomObject]@{
            'Config'      = [PSCustomObject]@{
                'Type'             = $GlobalVariable.Public.WebSocket.Config.$WebSocket.Type;
                'AuthPayload'      = $null;
                'KeepAlivePayload' = $null;
                'KeepAliveTimer'   = $null;
            };
            'ReaderWorker' = (New-Object System.Collections.Concurrent.BlockingCollection[string] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[string]));
            'WriterWorker' = (New-Object System.Collections.Concurrent.BlockingCollection[string] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[string]));
        };

        # Store the WebSocket configuration in the global public space and use Force to overwrite any existing one
        # Names are already sanitized during Add-ModuleWebSocketConfig and are unique anyway
        $GlobalVariable.Public.WebSocket | Add-Member -MemberType NoteProperty -Name $WebSocket -Value $WebSocketConfig -Force;

        # Start a new WebSocket handler thread
        New-Thread `
            -Command 'Start-ModuleWebSocketHandler' `
            -Parameters @{
                'Name' = $WebSocket;
            } `
            -Start `
            -KeepAlive | Out-Null;
    }

    return (Write-FunctionReturnValue -ReturnValue 'WebSocketEnvironmentInitializedSuccessfully');
}

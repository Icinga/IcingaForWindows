<#
.SYNOPSIS
Initialize RestApi runtime environment structures

.DESCRIPTION
Loads the RestApi configuration from disk via `Read-RestApiConfig`, reads
all space definitions via `Read-RestApiSpacesConfig`, loads the TLS
certificate and then creates the blocking worker queues and spawns one
`Start-RestApiWorker` thread per configured worker. Finally, it starts the
`Start-RestApiListener` thread. The function reads worker count from
`(Get-GlobalRuntimeVariable).Public.RestApi.Config.WorkerCount` which must
be populated before this function runs.

.OUTPUTS
None — populates `(Get-GlobalRuntimeVariable).Public.RestApi.WorkerQueue`
and starts all worker and listener threads.

.EXAMPLE
PS> New-RestApiEnvironment

.NOTES
Must be called after `Set-RestApiConfig` has been executed so that a valid
`restapi.json` configuration file exists. All threads started here rely on
the global runtime variable rather than parameters, so thread-safety
depends on the blocking collections used for the worker queues.
#>
function New-RestApiEnvironment()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Initialize RestApi Environment
    if ((Read-RestApiConfig) -ne $GlobalVariable.Public.ReturnCodes.RestApiConfigLoaded.Code) {
        return;
    }

    # Read the configuration for Spaces if available
    Read-RestApiSpacesConfig | Out-Null;

    # Load TLS Certificate
    $GlobalVariable.Public.RestApi.Certificate = Get-TlsCertificate -TlsCertConfig $GlobalVariable.Public.RestApi.Config.TlsCertConfig;
    # Initialize Worker Queue
    $GlobalVariable.Public.RestApi.WorkerQueue = [System.Collections.ArrayList]@();

    for ($index = 0; $index -lt $GlobalVariable.Public.RestApi.Config.WorkerCount; $index++) {
        $GlobalVariable.Public.RestApi.WorkerQueue.Add(
            (New-Object System.Collections.Concurrent.BlockingCollection[[System.Net.Sockets.TcpClient]] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[[System.Net.Sockets.TcpClient]]))
        ) | Out-Null;

        # Start the worker thread to process incoming connections
        New-Thread -Command 'Start-RestApiWorker' -Parameters @{ 'WorkerId' = $index; 'Spaces' = $GlobalVariable.Private.RestApi.Spaces; } -KeepAlive -WaitForJobs -Start;

        Write-LoggingEntry -Message 'Remaining workers' -Level 'Debug' -Data @{
            'RemainingWorkers' = ($GlobalVariable.Public.RestApi.Config.WorkerCount - $index - 1);
        };
    }

    Write-LoggingEntry -Message 'All worker threads created' -Level 'Debug';

    New-Thread -Command 'Start-RestApiListener' -KeepAlive -WaitForJobs -Start;
}

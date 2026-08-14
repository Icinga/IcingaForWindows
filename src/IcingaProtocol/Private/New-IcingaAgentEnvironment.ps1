<#
.SYNOPSIS
Initializes the Icinga Protocol runtime environment and starts worker, listener and connector threads.

.DESCRIPTION
New-IcingaAgentEnvironment prepares $Global:IcingaForWindows.Public.IcingaProtocol for
accepting and initiating Icinga 2 protocol connections. It reads connection configuration
via Read-IcingaProtocolConnection and certificate directory via Get-ModuleCertificateDirectory.
When a connection configuration is present, it applies Zone, Hostname, Endpoints,
ListenAddress and ListenPort to the global config. If no connection configuration is
returned, the function assumes the remote master or satellite will initiate connections
to this host. Default values of 0.0.0.0 and port 5665 are applied when not provided.
The function then loads a PFX certificate named after the configured hostname from the
certificate directory. If the certificate file is not found, the function returns early
via Write-FunctionReturnValue. After certificate loading, it initializes the Connections
hashtable and WorkerQueue, creates one BlockingCollection-backed queue per worker and
spawns the corresponding Start-IcingaProtocolWorker threads via New-Thread. Finally, it
starts the listener and connector threads. This function must be called once during
process initialization and must not be called again while threads are running.

.OUTPUTS
None — Performs initialization and starts background threads. Returns early via
Write-FunctionReturnValue when the certificate file is missing.

.EXAMPLE
PS> New-IcingaAgentEnvironment

Reads module configuration, loads the PFX certificate, initializes global runtime
structures and starts all protocol worker, listener and connector threads.

.NOTES
Requires read access to the PFX certificate file under the module certificate directory.
The PFX is loaded without an explicit password; ensure it is not password-protected.
Global state modified: $Global:IcingaForWindows.Public.IcingaProtocol.Config,
Certificate, Connections and WorkerQueue. Config.WorkerCount must be a positive integer
before this function is called.
#>
function New-IcingaAgentEnvironment()
{
    # Read connection configuration
    $ConnectionConfig     = Read-IcingaProtocolConnection;
    $CertificateDirectory = Get-ModuleCertificateDirectory;

    # If we do not provide any connection configuration, it means the master/satellite will connect to us instead
    if ($null -ne $ConnectionConfig) {
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.Zone          = $ConnectionConfig.Zone;
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.Hostname      = $ConnectionConfig.Hostname;
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints     = $ConnectionConfig.Endpoints;
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenAddress = $ConnectionConfig.ListenAddress;
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenPort    = $ConnectionConfig.ListenPort;
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.TlsCertConfig = $ConnectionConfig.TlsCertConfig;
    }

    # Set default listen address if not provided
    if ($null -eq $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenAddress) {
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenAddress = '0.0.0.0';
    }

    # Set default listen port if not provided
    if ($null -eq $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenPort) {
        $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenPort = 5665;
    }

    Write-LoggingEntry -Message 'Icinga Protocol Environment initialized' -Level 'Debug' -Data @{ 'IcingaProtocol' = $Global:IcingaForWindows.Public.IcingaProtocol; };

    # Setup our worker queue list
    $Global:IcingaForWindows.Public.IcingaProtocol.Connections = @{ };
    $Global:IcingaForWindows.Public.IcingaProtocol.WorkerQueue = [System.Collections.ArrayList]@();

    # Now create a blocking worker queue which will receive a client object from the main thread
    # Each worker thread we start will then read from the queue with the assigned index and use the TCP client to read data
    for ($index = 0; $index -lt $Global:IcingaForWindows.Public.IcingaProtocol.Config.WorkerCount; $index++) {
        $Global:IcingaForWindows.Public.IcingaProtocol.WorkerQueue.Add(
            (New-Object System.Collections.Concurrent.BlockingCollection[[PSObject]] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[[PSObject]]))
        ) | Out-Null;

        # Start the worker thread to process incoming connections
        New-Thread -Command 'Start-IcingaProtocolWorker' -Parameters @{ 'WorkerId' = $index } -KeepAlive -WaitForJobs -Start;

        Write-LoggingEntry -Message 'Remaining workers' -Level 'Debug' -Data @{ 'RemainingWorkers' = ($Global:IcingaForWindows.Public.IcingaProtocol.Config.WorkerCount - $index - 1); };
    }

    Write-LoggingEntry -Message 'All worker threads created' -Level 'Debug';

    New-Thread -Command 'Start-IcingaProtocolListener' -KeepAlive -WaitForJobs -Start;
    New-Thread -Command 'Start-IcingaProtocolConnector' -KeepAlive -Start;
}

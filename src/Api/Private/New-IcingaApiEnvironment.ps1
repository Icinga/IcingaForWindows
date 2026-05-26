<#
.SYNOPSIS
Initialize the API environment and default configuration for the API listener

.DESCRIPTION
New-IcingaApiEnvironment prepares runtime globals used by the API subsystem.
It ensures default values for ListenAddress and ListenPort, loads the TLS
certificate from the configured path, initializes the worker queue list in
IcingaForWindows.Public.Api.WorkerQueue and spawns the configured number of
API worker threads via New-Thread. The listener thread is started last. This
function mutates global state and is intended to be invoked once during
process initialization inside a dedicated background thread.

.OUTPUTS
None — Performs initialization side effects only; returns nothing.

.EXAMPLE
PS> New-IcingaApiEnvironment

Creates the API environment and initializes all worker queues and threads.

.NOTES
Depends on the global config entries IcingaForWindows.Public.Api.Config
(ListenAddress, ListenPort, WorkerCount) and the certificate path derived
from $CertificateDirectory. Runs inside a background thread spawned by
Start-IcingaApi; do not call directly from the main thread.
#>
function New-IcingaApiEnvironment()
{
    # Set default listen address if not provided
    if ($null -eq $Global:IcingaForWindows.Public.Api.Config.ListenAddress) {
        $Global:IcingaForWindows.Public.Api.Config.ListenAddress = '127.0.0.1';
    }

    # Set default listen port if not provided
    if ($null -eq $Global:IcingaForWindows.Public.Api.Config.ListenPort) {
        $Global:IcingaForWindows.Public.Api.Config.ListenPort = 5668;
    }

    $CertificateFilePath = Join-Path -Path $CertificateDirectory -ChildPath ([string]::Format('{0}.pfx', 'IcingaForWindows'));

    if (-not (Test-Path -Path $CertificateFilePath)) {
        Write-LoggingEntry -Message 'Icinga Api certificate file not found' -Level 'Error' -Data @{ 'CertificateFilePath' = $CertificateFilePath; };
        return;
    }

    $Global:IcingaForWindows.Public.IcingaProtocol.Certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 $CertificateFilePath;

    Write-LoggingEntry -Message 'Icinga Api Environment initialized' -Level 'Debug' -Data @{ 'Api' = $Global:IcingaForWindows.Public.Api; 'Certificate' = $Global:IcingaForWindows.Public.IcingaProtocol.Certificate; };

    # Setup our worker queue list
    $Global:IcingaForWindows.Public.Api.WorkerQueue = [System.Collections.ArrayList]@();

    # Now create a blocking worker queue which will receive a client object from the main thread
    # Each worker thread we start will then read from the queue with the assigned index and use the TCP client to read data
    for ($index = 0; $index -lt $Global:IcingaForWindows.Public.Api.Config.WorkerCount; $index++) {
        $Global:IcingaForWindows.Public.Api.WorkerQueue.Add(
            (New-Object System.Collections.Concurrent.BlockingCollection[[PSObject]] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[[PSObject]]))
        ) | Out-Null;

        # Start the worker thread to process incoming connections
        New-Thread -Command 'Start-IcingaApiWorker' -Parameters @{ 'WorkerId' = $index } -KeepAlive -WaitForJobs -Start;

        Write-LoggingEntry -Message 'Remaining workers' -Level 'Debug' -Data @{ 'RemainingWorkers' = ($Global:IcingaForWindows.Public.Api.Config.WorkerCount - $index - 1); };
    }

    Write-LoggingEntry -Message 'All worker threads created' -Level 'Debug'

    New-Thread -Command 'Start-IcingaApiListener' -KeepAlive -WaitForJobs -Start;
}

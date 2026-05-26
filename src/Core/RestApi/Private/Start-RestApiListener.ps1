<#
.SYNOPSIS
Start the RestApi TCP listener and accept incoming connections.

.DESCRIPTION
Opens a TCP socket according to the RestApi configuration, then accepts
incoming connections and assigns them to worker queues via
`Add-RestApiClientToWorker`.

.OUTPUTS
None

.EXAMPLE
PS> Start-RestApiListener

.NOTES
This function runs on a dedicated thread and uses global runtime state
for configuration and worker management.
#>
function Start-RestApiListener()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Start RestApi Listener
    Open-TCPSocket `
        -Address $GlobalVariable.Public.RestApi.Config.ListenAddress `
        -Port $GlobalVariable.Public.RestApi.Config.ListenPort `
        -TlsCertificate $GlobalVariable.Public.RestApi.Certificate `
        -Start;

    Write-LoggingEntry -Message 'RestApi Listener started' -Level 'Info' -Data @{
        'Address' = $GlobalVariable.Public.RestApi.Config.ListenAddress;
        'Port'    = $GlobalVariable.Public.RestApi.Config.ListenPort;
        'TlsCert' = $GlobalVariable.Public.RestApi.Certificate;
    };

    while (Test-ThreadRunning) {
        try {
            [System.Net.Sockets.TcpClient]$TcpClient = $GlobalVariable.Private.TCP.Listener.AcceptTcpClient();
            Set-ThreadProcessing;

            # Validate the accepted client
            if ($null -eq $TcpClient) {
                Write-LoggingEntry -Message 'Failed to accept incoming TCP connection' -Level 'Error';
                continue;
            }

            Write-LoggingEntry -Message 'Accepted new TCP connection' -Level 'Debug' -Data @{ 'TcpClient' = $TcpClient };
            # Assign the connection to a worker
            Add-RestApiClientToWorker -TcpClient $TcpClient | Out-Null;
        } catch {
            Write-LoggingEntry -Message 'Error accepting TCP connection' -Level 'Error' -Data @{ 'Exception' = $_.Exception };
        }
    }
}

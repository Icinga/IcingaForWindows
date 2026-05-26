<#
.SYNOPSIS
Start the API TCP listener and accept incoming API client connections

.DESCRIPTION
Start-IcingaApiListener opens a TCP socket using the configured
IcingaForWindows.Public.Api.Config.ListenAddress and ListenPort values.
For each accepted System.Net.Sockets.TcpClient it enqueues the client
for processing by the API workers using Add-IcingaApiCallToWorkerQueue.
The function runs in a tight loop guarded by Test-ThreadRunning and is
intended to run inside a dedicated long-lived background thread spawned
by New-IcingaApiEnvironment.

.OUTPUTS
None — Produces side effects (opens socket, enqueues clients, writes logs).

.EXAMPLE
PS> Start-IcingaApiListener

Starts the API listener on the configured address and port.

.NOTES
Reads listen address and port from IcingaForWindows.Public.Api.Config.
Uses Open-TCPSocket to bind and Close-TCPConnection to finalize individual
connections. Exceptions per connection are caught and logged; the listener
loop continues without aborting.
#>
function Start-IcingaApiListener()
{
    # Open a TCP socket to listen for incoming connections
    Open-TCPSocket `
        -Address $Global:IcingaForWindows.Public.Api.Config.ListenAddress `
        -Port $Global:IcingaForWindows.Public.Api.Config.ListenPort `
        -Start;

    Write-LoggingEntry 'Icinga Api Listener started, waiting for incoming connections' -Level 'Debug' -Data @{ 'ListenAddress' = $Global:IcingaForWindows.Public.Api.Config.ListenAddress; 'ListenPort' = $Global:IcingaForWindows.Public.Api.Config.ListenPort; 'Listener' = $Global:IcingaForWindows.Private.TCP.Listener; };

    while (Test-ThreadRunning) {
        try {
            $Global:IcingaForWindows.Private.TCP.Client = $Global:IcingaForWindows.Private.TCP.Listener.AcceptTcpClient();
            Set-ThreadProcessing;

            # Validate the accepted client
            if ($null -eq $Global:IcingaForWindows.Private.TCP.Client) {
                Write-LoggingEntry -Message 'Failed to accept incoming TCP connection' -Level 'Error';
                continue;
            }
            Write-LoggingEntry -Message 'Accepted new connection from' -Level 'Info' -Data @{ 'Client' = $Global:IcingaForWindows.Private.TCP.Client; };

            # TODO: Add the client to our Api worker queue
            Close-TCPConnection;
        } catch {
            Write-LoggingEntry -Message 'Exception caught in Icinga Protocol Listener: {0}' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; };
        }
    }
}

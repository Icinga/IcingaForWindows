<#
.SYNOPSIS
Starts the Icinga protocol TCP listener and accepts incoming client connections.

.DESCRIPTION
Start-IcingaProtocolListener opens a TCP listener on the configured ListenAddress and
ListenPort via Open-TCPSocket and enters a continuous loop to accept and validate
incoming TCP clients. For each accepted connection it validates the client via
Test-IcingaProtocolClientStatus, closes duplicate or invalid connections, registers
the new client via Add-IcingaProtocolClient and spawns a dedicated socket reader
thread with Start-IcingaProtocolSocketReader via New-Thread. Exceptions per iteration
are caught and logged to keep the listener loop alive. The function runs until the
hosting process is stopped and must always be started in a background thread.

.OUTPUTS
None — Side-effect driven: opens a network listener, updates global state, writes log entries and spawns threads.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolListener' -Start

Starts the TCP listener in a dedicated background thread using the module thread helper.

.NOTES
Configuration is read from $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenAddress
and ListenPort. The function is intentionally long-running and blocking; always run it in a
background thread. Requires Open-TCPSocket, Close-TCPConnection, Test-IcingaProtocolClientStatus,
Add-IcingaProtocolClient, New-Thread, Start-IcingaProtocolSocketReader and Write-LoggingEntry.
Exceptions are caught per iteration to keep the listener loop alive.
#>
function Start-IcingaProtocolListener()
{
    # Open a TCP socket to listen for incoming connections
    Open-TCPSocket `
        -Address $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenAddress `
        -Port $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenPort `
        -TlsCertificate $Global:IcingaForWindows.Public.IcingaProtocol.Certificate `
        -Start;

    Write-LoggingEntry -Message 'Icinga Protocol Listener started, waiting for incoming connections' -Level 'Debug' -Data @{ 'ListenAddress' = $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenAddress; 'ListenPort' = $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenPort; 'Listener' = $Global:IcingaForWindows.Private.TCP.Listener; };

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

            # Check the client connection status and validate if we are maybe already connected
            $TestStatus = Test-IcingaProtocolClientStatus -Address $Global:IcingaForWindows.Private.TCP.Client.Client.RemoteEndPoint.Address.ToString();

            # Only connect and create a new connection if we do not have a valid existing one
            if ($TestStatus -ne $Global:IcingaForWindows.Public.ReturnCodes.IcingaClientCreated.Code -and $TestStatus -ne $Global:IcingaForWindows.Public.ReturnCodes.IcingaClientReplaced.Code) {
                Close-TCPConnection;
                continue;
            }

            # Register the new client
            Add-IcingaProtocolClient -Address $Global:IcingaForWindows.Private.TCP.Client.Client.RemoteEndPoint.Address.ToString() -TcpClient $Global:IcingaForWindows.Private.TCP.Client;

            # Start the socket reader in a new thread
            New-Thread -Command 'Start-IcingaProtocolSocketReader' -Parameters @{ '-Client' =  $Global:IcingaForWindows.Private.TCP.Client } -Start;
        } catch {
            Write-LoggingEntry -Message 'Exception caught in Icinga Protocol Listener: {0}' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; };
        }
    }
}

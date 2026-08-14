<#
.SYNOPSIS
Starts a continuous connector loop that attempts to establish and maintain TCP connections to configured Icinga endpoints.

.DESCRIPTION
Start-IcingaProtocolConnector runs an infinite loop that iterates through the configured
endpoints stored in $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints. For
each endpoint it logs a connection attempt, resolves the address via Resolve-IcingaIPAddress,
checks the current connection status with Test-IcingaProtocolClientStatus and, when a new
connection is required, creates a System.Net.Sockets.TcpClient, connects to the configured
address and port, registers the client via Add-IcingaProtocolClient and spawns a socket
reader thread with Start-IcingaProtocolSocketReader. Exceptions per endpoint are caught,
logged and do not stop the overall loop. The loop pauses for 5 seconds between full endpoint
scans. Because the function runs indefinitely, it must always be started in a background thread.

.OUTPUTS
None — Manages connections, global state and log entries; no pipeline output.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolConnector' -Start

Starts the connector loop in a dedicated background thread via the module thread helper.

.NOTES
Reads endpoints from $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints.
Uses return-code constants from $Global:IcingaForWindows.Public.ReturnCodes.
The function is intentionally long-running and blocking; always run it in a background
thread. Exceptions during individual connection attempts are logged and do not stop the
overall loop. The loop pauses for 5 seconds between full endpoint scans to avoid tight
reconnect cycles.
#>
function Start-IcingaProtocolConnector()
{
    while (Test-ThreadRunning) {
        # Attempt to connect to each configured endpoint
        foreach ($key in $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints.PSObject.Properties) {
            $EndpointName   = $key.Name;
            $EndpointConfig = $key.Value;
            $TcpClient      = $null;

            try {
                Write-LoggingEntry -Message 'Attempting to connect to Icinga endpoint' -Level 'Info' -Data @{ 'EndpointName' = $EndpointName; 'EndpointAddress' = "$($EndpointConfig.Address):$($EndpointConfig.Port)"; };

                # Resolve the endpoint address to an IPv4 address
                $ResolvedAddress = Resolve-IcingaIPAddress -Address $EndpointConfig.Address;
                if ($null -eq $ResolvedAddress) {
                    continue;
                }

                # Check the client connection status and validate if we are maybe already connected
                $TestStatus = Test-IcingaProtocolClientStatus -Address $ResolvedAddress;

                # Only connect and create a new connection if we do not have a valid existing one
                if ($TestStatus -ne $Global:IcingaForWindows.Public.ReturnCodes.IcingaClientCreated.Code -and $TestStatus -ne $Global:IcingaForWindows.Public.ReturnCodes.IcingaClientReplaced.Code) {
                    continue;
                }

                # Create new TcpClient and connect to the endpoint with a 10-second timeout
                $TcpClient   = New-Object System.Net.Sockets.TcpClient;
                $ConnectTask = $TcpClient.ConnectAsync($EndpointConfig.Address, $EndpointConfig.Port);
                if (-not $ConnectTask.Wait(10000)) {
                    $TcpClient.Dispose();
                    Write-LoggingEntry -Message 'Failed to connect to Icinga endpoint' -Level 'Warning' -Data @{ 'Timeout' = 'Socket connection timeout after 10 seconds'; 'Endpoint' = $EndpointConfig.Address; 'Endpoints' = $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints; };
                    continue;
                }

                Add-IcingaProtocolClient -Address $ResolvedAddress -TcpClient $TcpClient;

                Write-LoggingEntry -Message 'Successfully connected to Icinga endpoint' -Level 'Info' -Data @{ 'EndpointAddress' = "$($EndpointConfig.Address):$($EndpointConfig.Port)"; };

                # Start the socket reader in a new thread
                New-Thread -Command 'Start-IcingaProtocolSocketReader' -Parameters @{ '-Client' =  $TcpClient; 'IsClient' = $true; 'Endpoint' = $EndpointName } -Start;
            } catch {
                if ($null -ne $TcpClient) {
                    $TcpClient.Dispose();
                }
                Write-LoggingEntry -Message 'Failed to connect to Icinga endpoint' -Level 'Warning' -Data @{ 'ExceptionMessage' = $_.Exception.Message; 'Endpoint' = $EndpointConfig.Address; 'Endpoints' = $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints; };
            } finally {
                $TcpClient       = $null;
                $EndpointName    = $null;
                $EndpointConfig  = $null;
                $ResolvedAddress = $null;
                $TestStatus      = $null;
                $ConnectTask     = $null;
            }
        }

        # Wait before attempting to reconnect
        Start-Sleep -Seconds 5;
    }
}

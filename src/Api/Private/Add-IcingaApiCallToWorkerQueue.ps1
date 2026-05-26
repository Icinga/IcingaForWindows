<#
.SYNOPSIS
Add a TcpClient API call to the appropriate worker queue using a round-robin policy

.DESCRIPTION
Assigns the provided System.Net.TcpClient to one of the API worker queues.
The function increments the global counter at IcingaForWindows.Private.TCP.LastWorkerId
and wraps it modulo IcingaForWindows.Public.Api.Config.WorkerCount. If the parameter
is $null the function returns a cmdlet-style object via Write-FunctionReturnValue and
does not enqueue the connection.

.PARAMETER TcpClient
| Name      | Type                 | Description                                                  | Default |
|-----------|----------------------|--------------------------------------------------------------|---------|
| TcpClient | System.Net.TcpClient | The incoming API connection to queue (a TcpClient instance). | $null   |

.OUTPUTS
System.Object — Structured return object from Write-FunctionReturnValue on error; nothing on success.

.EXAMPLE
PS> Add-IcingaApiCallToWorkerQueue -TcpClient $client

Queues the provided TcpClient to the next worker according to the module's round-robin policy.

.NOTES
Relies on the global state entries IcingaForWindows.Private.TCP.LastWorkerId,
IcingaForWindows.Public.Api.Config.WorkerCount and IcingaForWindows.Public.Api.WorkerQueue.
Uses Write-FunctionReturnValue for standardized error return objects.
#>
function Add-IcingaApiCallToWorkerQueue()
{
    param (
        [System.Net.TcpClient]$TcpClient = $null
    );

    # Do nothing if the TcpClient is null
    if ($null -eq $TcpClient) {
        return (Write-FunctionReturnValue -ReturnValue 'ApiTcpClientNull' -OverrideReturn $null);
    }

    # Determine which worker should receive this message based on a round-robin approach
    $Global:IcingaForWindows.Private.TCP.LastWorkerId++;

    if ($Global:IcingaForWindows.Private.TCP.LastWorkerId -ge $Global:IcingaForWindows.Public.Api.Config.WorkerCount) {
        $Global:IcingaForWindows.Private.TCP.LastWorkerId = 0;
    }

    # Add the TcpClient to the appropriate worker queue
    $Global:IcingaForWindows.Public.Api.WorkerQueue[$Global:IcingaForWindows.Private.TCP.LastWorkerId].Add($TcpClient) | Out-Null;
}

<#
.SYNOPSIS
Assign a new TCP client to a RestApi worker queue.

.DESCRIPTION
Performs a simple round-robin assignment of an accepted `TcpClient` to one
of the RestApi worker queues managed in the global runtime state. Logs the
assignment and validates the input client.

.PARAMETER TcpClient
| Name      | Type                         | Description                                      | Default |
|-----------|------------------------------|--------------------------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Accepted TCP client to assign to a worker queue. |         |

.OUTPUTS
None

.EXAMPLE
PS> Add-RestApiClientToWorker -TcpClient $acceptedClient

.NOTES
This helper expects RestApi worker queues to be initialized under
`(Get-GlobalRuntimeVariable).Public.RestApi.WorkerQueue` and a
`WorkerCount` value in the RestApi configuration.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Add-RestApiClientToWorker()
{
    param (
        [System.Net.Sockets.TcpClient]$TcpClient = $null
    );

    if ($null -eq $TcpClient) {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiClientInvalid');
    }

    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Determine which worker should receive this message based on a round-robin approach
    $GlobalVariable.Private.TCP.LastWorkerId++;

    if ($GlobalVariable.Private.TCP.LastWorkerId -ge $GlobalVariable.Public.RestApi.Config.WorkerCount) {
        $GlobalVariable.Private.TCP.LastWorkerId = 0;
    }

    # Add the TcpClient to the appropriate worker queue
    Write-LoggingEntry -Message 'Assigning Rest-Api connection to worker {0}' -Data @{
        'LastWorkerId' = $GlobalVariable.Private.TCP.LastWorkerId
    } -Level 'Debug';
    $GlobalVariable.Public.RestApi.WorkerQueue[$GlobalVariable.Private.TCP.LastWorkerId].Add($TcpClient) | Out-Null;
}

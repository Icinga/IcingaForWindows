<#
.SYNOPSIS
Check whether the current TCP client and stream are connected.

.DESCRIPTION
`Test-TCPConnection` validates that both the TCP client and its associated
stream are present and returns the client's `Connected` state.

.OUTPUTS
System.Boolean — $true when connected and a valid client and stream are present; $false otherwise.

.EXAMPLE
PS> Test-TCPConnection

.NOTES
Used by thread health checks and higher-level network monitors.
#>
function Test-TCPConnection()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;

    $Client = $GlobalVariable.Private.TCP.Client;
    $Stream = $GlobalVariable.Private.TCP.Stream;

    if ($null -eq $Stream -or $null -eq $Client -or $null -eq $Client.Client) {
        return $false;
    }

    if (-not $Client.Connected) {
        return $false;
    }

    # In .NET, TcpClient.Connected only reflects the state of the last I/O operation.
    # Check Poll for SelectRead with Available == 0 to detect if remote socket was closed/disconnected.
    try {
        if ($Client.Client.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $Client.Client.Available -eq 0) {
            return $false;
        }
    } catch {
        return $false;
    }

    return $true;
}

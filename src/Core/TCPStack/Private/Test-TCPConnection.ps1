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

    if ($null -eq $GlobalVariable.Private.TCP.Stream -Or $null -eq $GlobalVariable.Private.TCP.Client) {
        return $false;
    }

    return $GlobalVariable.Private.TCP.Client.Connected;
}

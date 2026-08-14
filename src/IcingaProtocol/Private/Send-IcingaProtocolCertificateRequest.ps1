<#
.SYNOPSIS
Send a certificate request message over the Icinga protocol

.DESCRIPTION
Sends an Icinga RPC message with the method 'pki::RequestCertificate'
to request a new certificate. This is typically part of the initial node
setup and certificate signing request (CSR) workflow. If a ticket is
provided it is included in the RPC parameters for auto-signing.

.PARAMETER Ticket
| Name   | Type          | Description                                | Default |
|--------|---------------|--------------------------------------------|---------|
| Ticket | System.String | The ticket to use for auto-signing.        | $null   |

.OUTPUTS
None — Does not return any value.

.EXAMPLE
PS> Send-IcingaProtocolCertificateRequest -Ticket '1234567890abcdef'

Sends a certificate request to the connected Icinga endpoint.

.NOTES
Requires an active TCP connection to the Icinga endpoint.
#>
function Send-IcingaProtocolCertificateRequest()
{
    param (
        [string]$Ticket = $null
    );

    [hashtable]$RPCParameters = @{};

    if (-not [string]::IsNullOrEmpty($Ticket)) {
        $RPCParameters['ticket'] = $Ticket;
    }

    Add-IcingaRPCMessageToWriterQueue -MsgObj (
        New-IcingaRPCMessage -Method 'pki::RequestCertificate' -Parameters $RPCParameters
    );
}

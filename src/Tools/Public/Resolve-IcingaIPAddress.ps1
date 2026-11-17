<#
.SYNOPSIS
Resolves a hostname or returns a validated IP address string.

.DESCRIPTION
Resolve-IcingaIPAddress accepts a hostname or IP address string and attempts to
return a canonical IP address string. If the input is already a valid IPv4 or
IPv6 literal, it is returned unchanged. Otherwise the function performs DNS
resolution and prefers an IPv4 address when multiple addresses are returned.
On failure or exception, the function uses the module's Write-FunctionReturnValue
mechanism to emit a standardized return value and typically returns $null.

.PARAMETER Address
| Name    | Type          | Description                                                                     | Default |
|---------|---------------|---------------------------------------------------------------------------------|---------|
| Address | System.String | Hostname or IP address to resolve. Empty or null triggers IPAddressLookupEmpty. | $null   |

.EXAMPLE
PS> Resolve-IcingaIPAddress -Address 'icinga-master.example.local'

Resolves the hostname and returns the first IPv4 address found, or the first IPv6
address if no IPv4 is available.

.EXAMPLE
PS> Resolve-IcingaIPAddress -Address '192.0.2.1'

Returns '192.0.2.1' unchanged since the input is already a valid IPv4 literal.

.OUTPUTS
System.String -- IPv4 or IPv6 address string on success.
Returns $null via Write-FunctionReturnValue on failure with tokens
IPAddressLookupEmpty, IPAddressLookupFailure, IPAddressLookupFailedForV4AndV6
or IPAddressLookupException.

.NOTES
DNS resolution is performed via [System.Net.Dns]::GetHostAddresses. IPv4 addresses
are preferred; the function returns the first IPv4 found, otherwise the first IPv6.
Simple regex literal checks are performed before DNS resolution to avoid unnecessary
lookups. Error conditions are surfaced via Write-FunctionReturnValue.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Resolve-IcingaIPAddress()
{
    param (
        [string]$Address = $null
    );

    if ([string]::IsNullOrEmpty($Address)) {
        return (Write-FunctionReturnValue -ReturnValue 'IPAddressLookupEmpty' -Data @{ 'Address' = $Address; } -OverrideReturn $null);
    }

    # Check if we already have an IP address
    if ($Address -match '^(?:\d{1,3}\.){3}\d{1,3}$' -or $Address -match '^([a-fA-F0-9:]+)$') {
        return $Address
    }

    try {
        # If not, try to resolve it to an IP address
        [array]$IPAddresses = [System.Net.Dns]::GetHostAddresses($Address);

        # If we have no addresses, return null with an error
        if ($IPAddresses.Count -eq 0) {
            return (Write-FunctionReturnValue -ReturnValue 'IPAddressLookupFailure' -Data @{ 'Address' = $Address; } -OverrideReturn $null);
        }

        # We should prefer IPv4 addresses over IPv6, so return the first IPv4 if available
        foreach ($entry in $IPAddresses) {
            if ($entry.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                return $entry.IPAddressToString;
            }
        }

        # If no IPv4 found, return the first IPv6 address
        foreach ($entry in $IPAddresses) {
            if ($entry.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
                return $entry.IPAddressToString;
            }
        }

        # This shouldn't happen anymore, but just in case
        return (Write-FunctionReturnValue -ReturnValue 'IPAddressLookupFailedForV4AndV6' -Data @{ 'Address' = $Address; 'IPAddresses' = $IPAddresses; } -OverrideReturn $null);
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'IPAddressLookupException' -Data @{ 'Address' = $Address; 'ExceptionMessage' = $_.Exception.Message; } -OverrideReturn $null);
    }
}

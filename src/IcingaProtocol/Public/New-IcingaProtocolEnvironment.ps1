<#
.SYNOPSIS
Generate and save the Icinga Protocol environment configuration

.DESCRIPTION
New-IcingaProtocolEnvironment validates and writes the Icinga 2 cluster
connection settings (Endpoints, Zone, Hostname, and TlsCertConfig) to
Config\IcingaProtocol\Connection.json. Single-quoted '$fqdn' and '$hostname'
placeholders in -Hostname, -CertCN, and -CertIssuer are preserved verbatim in
Connection.json and resolved dynamically when Read-IcingaProtocolConnection
loads the file.

When -DryRun is specified, the function computes a unified diff against any
existing Connection.json via Compare-IcingaTextContent and returns @{ ExitCode;
Output } without creating directories or saving changes to disk. Call
New-IcingaProtocolEnvironment again without -DryRun and without .Output to
persist the configuration.

.PARAMETER Endpoints
| Name      | Type         | Description                      | Default |
|-----------|--------------|----------------------------------|---------|
| Endpoints | System.Array | An array of endpoint hashtables. | @()     |

.PARAMETER Zone
| Name | Type          | Description                  | Default  |
|------|---------------|------------------------------|----------|
| Zone | System.String | The name of the Icinga zone. | 'master' |

.PARAMETER Hostname
| Name     | Type          | Description                                                        | Default     |
|----------|---------------|--------------------------------------------------------------------|-------------|
| Hostname | System.String | Icinga 2 Endpoint/Host Object Name (supports '$fqdn'/'$hostname'). | '$hostname' |

.PARAMETER TlsCertConfig
| Name          | Type                                          | Description                               | Default |
|---------------|-----------------------------------------------|-------------------------------------------|---------|
| TlsCertConfig | System.Management.Automation.PSCustomObject   | The TLS certificate configuration object. | $null   |

.PARAMETER DryRun
| Name   | Type                                         | Description                                                 | Default |
|--------|----------------------------------------------|-------------------------------------------------------------|---------|
| DryRun | System.Management.Automation.SwitchParameter | Return a unified diff hashtable without saving to disk.     | $false  |

.OUTPUTS
System.Object -- Returns System.Int32 from Write-FunctionReturnValue when
persisting configuration or failing validation (50019 IcingaProtoclConfigWritten
on write, or 50015-50018 on missing required inputs), or
System.Collections.Hashtable (@{ ExitCode = System.Int32; Output = System.String })
from Compare-IcingaTextContent when -DryRun is specified.

.EXAMPLE
PS> $Endpoints = @(New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665)
PS> $CertConfig = New-IcingaTlsCertConfig -CertCN '$fqdn' -CertStore 'My' -CertStoreLocation 'CurrentUser' -CertIssuer @( 'Icinga CA', '$fqdn' )
PS> (New-IcingaProtocolEnvironment -Endpoints $Endpoints -Zone 'master' -Hostname '$fqdn' -TlsCertConfig $CertConfig -DryRun).Output
PS> New-IcingaProtocolEnvironment -Endpoints $Endpoints -Zone 'master' -Hostname '$fqdn' -TlsCertConfig $CertConfig

Previews the unified diff via -DryRun without modifying disk state, then writes
Config\IcingaProtocol\Connection.json (returning 50019).

.NOTES
Writes configuration data to Config\IcingaProtocol\Connection.json via
Write-SecureFile. The -Hostname and certificate CN must match the exact
Endpoint and Host Object Name configured in Icinga 2. Always single-quote
'$fqdn' and '$hostname' so PowerShell does not expand them before invocation.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-IcingaProtocolEnvironment()
{
    param (
        [array]$Endpoints              = @(),
        [string]$Zone                  = 'master',
        [string]$Hostname              = '$hostname',
        [PSCustomObject]$TlsCertConfig = $null, # Tls cert config object created via New-TlsCertConfig
        [switch]$DryRun                = $false
    );

    # Validate that we have at least one endpoint
    if ($null -eq $Endpoints -or 0 -eq $Endpoints.Count) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaEndpointsEmpty');
    }

    if ([string]::IsNullOrEmpty($Zone)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaZoneNameNotDefined');
    }

    if ([string]::IsNullOrEmpty($Hostname)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaHostnameNotDefined');
    }

    if ($null -eq $TlsCertConfig) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaTlsCertConfigMissing');
    }

    [hashtable]$EndpointConfig = @{ };

    foreach ($entry in $Endpoints) {
        $EndpointConfig[$entry.Name] = @{
            'Address' = $entry.Address;
            'Port'    = $entry.Port;
        };
    }

    $IcingaProtocolConfig       = [PSCustomObject]@{
        'Endpoints'     = $EndpointConfig;
        'Zone'          = $Zone;
        'Hostname'      = $Hostname;
        'TlsCertConfig' = $TlsCertConfig;
    };

    [string]$ProtocolConfigDir  = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath 'IcingaProtocol';
    [string]$ProtocolConfigFile = Join-Path -Path $ProtocolConfigDir -ChildPath 'Connection.json';

    if ($DryRun) {
        return (
            Compare-IcingaTextContent `
                -NewConfig (ConvertTo-Json -InputObject $IcingaProtocolConfig -Depth 5) `
                -OldFile $ProtocolConfigFile `
                -Colorized:(-not $Global:IcingaForWindows.Protected.NoColorizedOutput)
        );
    }

    New-SecureItem -ItemType 'Directory' -Path $ProtocolConfigDir -Force | Out-Null;

    Write-SecureFile `
        -File $ProtocolConfigFile `
        -Value ($IcingaProtocolConfig) | Out-Null;

    # All endpoints validated; persist or return success
    return (Write-FunctionReturnValue -ReturnValue 'IcingaProtoclConfigWritten' -Data @{ 'Config' = $IcingaProtocolConfig; });
}

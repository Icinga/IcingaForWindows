<#
.SYNOPSIS
Generates and saves the Icinga Protocol environment configuration.

.DESCRIPTION
This function configures the Icinga Protocol connection settings, including endpoints, zone name, hostname,
and TLS certificate configuration. It either saves the configuration to 'IcingaProtocol\Connection.json'
or returns a diff against the current configuration if -DryRun is used.

.PARAMETER Endpoints
| Name      | Type         | Description                      | Default |
|-----------|--------------|----------------------------------|---------|
| Endpoints | System.Array | An array of endpoint hashtables. | @()     |

.PARAMETER Zone
| Name | Type          | Description                  | Default  |
|------|---------------|------------------------------|----------|
| Zone | System.String | The name of the Icinga zone. | 'master' |

.PARAMETER Hostname
| Name     | Type          | Description                       | Default     |
|----------|---------------|-----------------------------------|-------------|
| Hostname | System.String | The local hostname for this node. | '$hostname' |

.PARAMETER TlsCertConfig
| Name          | Type           | Description                               | Default |
|---------------|----------------|-------------------------------------------|---------|
| TlsCertConfig | PSCustomObject | The TLS certificate configuration object. | $null   |

.PARAMETER DryRun
| Name   | Type   | Description                             | Default |
|--------|--------|-----------------------------------------|---------|
| DryRun | switch | Outputs a diff without saving the file. | $false  |

.OUTPUTS
System.Object -- Returns a status object from Write-FunctionReturnValue or a diff string.

.EXAMPLE
PS> $Endpoints = @(New-IcingaProtocolEndpoint -Name 'master' -Address '10.0.0.1' -Port 5665)
PS> New-IcingaProtocolEnvironment -Endpoints $Endpoints -Zone 'master' -Hostname 'agent01' -TlsCertConfig $CertConfig

Generates the protocol configuration and writes it to disk.

.NOTES
Writes configuration data to the internal Icinga Protocol connection JSON file.

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

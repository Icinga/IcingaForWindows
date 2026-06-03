<#
.SYNOPSIS
Public wrapper to configure the Icinga RestApi settings.

.DESCRIPTION
Public function that validates and applies RestApi configuration by delegating
to the private `Set-RestApiConfig` function. This is the supported public API
for module consumers to update the RestApi listen address, port, TLS
configuration and worker count. The function returns the same standardized
return objects as the underlying private implementation.

.PARAMETER ListenAddress
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ListenAddress | System.String | IP address or hostname to bind the RestApi listener. Use '0.0.0.0' to bind all interfaces. | '0.0.0.0' |

.PARAMETER ListenPort
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ListenPort | System.Int32 | TCP port to listen on (1-65535). | 5668 |

.PARAMETER TlsCertConfig
| Name | Type | Description | Default |
|------|------|-------------|---------|
| TlsCertConfig | System.PSCustomObject | TLS certificate configuration created by `New-IcingaTlsCertConfig`. | $null |

.PARAMETER WorkerCount
| Name | Type | Description | Default |
|------|------|-------------|---------|
| WorkerCount | System.Int32 | Number of worker threads to spawn for handling connections. | 5 |

.PARAMETER DryRun
| Name   | Type                                         | Description                                                                                       | Default |
|--------|----------------------------------------------|---------------------------------------------------------------------------------------------------|---------|
| DryRun | System.Management.Automation.SwitchParameter | When set, returns a unified diff of the pending configuration versus the persisted restapi.json instead of writing the change. | $false |

.OUTPUTS
PSCustomObject — Function return value forwarded from `Set-RestApiConfig`.

.EXAMPLE
PS> Set-IcingaRestApiConfig -ListenAddress '127.0.0.1' -ListenPort 10443 -WorkerCount 8

.NOTES
This public wrapper exists to expose a stable module API while keeping the
implementation in `Set-RestApiConfig` (private) where validation and persistence
logic is implemented.
#>
function Set-IcingaRestApiConfig()
{
    param (
        [string]$ListenAddress         = '0.0.0.0',
        [int]$ListenPort               = 5668,
        [PSCustomObject]$TlsCertConfig = $null, # Tls cert config object created via New-IcingaTlsCertConfig
        [int]$WorkerCount              = 5,
        [switch]$DryRun                = $false
    );

    return (
        Set-RestApiConfig `
            -ListenAddress $ListenAddress `
            -ListenPort $ListenPort `
            -TlsCertConfig $TlsCertConfig `
            -WorkerCount $WorkerCount `
            -DryRun:$DryRun
    );
}

<#
.SYNOPSIS
Configure RestApi listener, TLS and worker count and persist to restapi.json.

.DESCRIPTION
Validates listen address, port and worker count, updates the global RestApi
configuration and writes the configuration to the module config directory as
`restapi.json`. Returns standardized function return values via
`Write-FunctionReturnValue`.

.PARAMETER ListenAddress
| Name          | Type          | Description                                                                                | Default   |
|---------------|---------------|--------------------------------------------------------------------------------------------|-----------|
| ListenAddress | System.String | IP address or hostname to bind the RestApi listener. Use '0.0.0.0' to bind all interfaces. | '0.0.0.0' |

.PARAMETER ListenPort
| Name       | Type         | Description                      | Default |
|------------|--------------|----------------------------------|---------|
| ListenPort | System.Int32 | TCP port to listen on (1-65535). | 10000   |

.PARAMETER TlsCertConfig
| Name          | Type                  | Description                                                   | Default |
|---------------|-----------------------|---------------------------------------------------------------|---------|
| TlsCertConfig | System.PSCustomObject | TLS certificate configuration created by `New-TlsCertConfig`. | $null   |

.PARAMETER WorkerCount
| Name        | Type         | Description                                                 | Default |
|-------------|--------------|-------------------------------------------------------------|---------|
| WorkerCount | System.Int32 | Number of worker threads to spawn for handling connections. | 5       |

.PARAMETER DryRun
| Name   | Type                                         | Description                                                                                                                    | Default |
|--------|----------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|---------|
| DryRun | System.Management.Automation.SwitchParameter | When set, returns a unified diff of the pending configuration versus the persisted restapi.json instead of writing the change. | $false  |

.OUTPUTS
PSCustomObject -- Function return value via `Write-FunctionReturnValue`.
- `RestApiConfigConfigured`: Data contains `Config`.
- `NoRestApiListenAddressProvided`: invalid listen address.
- `NoRestApiListenPortProvided`: invalid port.
- `InvalidRestApiWorkerCountProvided`: invalid worker count (Data contains `WorkerCount` and `MaxThreads`).

.EXAMPLE
PS> Set-RestApiConfig -ListenAddress '127.0.0.1' -ListenPort 10443 -WorkerCount 8

.NOTES
Persists the configuration to `restapi.json` under the module config directory
using `Write-SecureFile` and `Get-ModuleConfigDirectory`. `WorkerCount` is
bounded by the global `Threading.MaxThreads` setting.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Set-RestApiConfig()
{
    param (
        [string]$ListenAddress         = '0.0.0.0',
        [int]$ListenPort               = 10000,
        [PSCustomObject]$TlsCertConfig = $null, # Tls cert config object created via New-TlsCertConfig
        [int]$WorkerCount              = 5,
        [switch]$DryRun                = $false
    );

    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Validate that we have at least one endpoint
    if ([string]::IsNullOrEmpty($ListenAddress)) {
        return (Write-FunctionReturnValue -ReturnValue 'NoRestApiListenAddressProvided' -AutomationRun:($Global:IcingaForWindows.Protected.IsAutomationRun));
    }

    if ($ListenPort -lt 1 -or $ListenPort -gt 65535) {
        return (Write-FunctionReturnValue -ReturnValue 'NoRestApiListenPortProvided' -AutomationRun:($Global:IcingaForWindows.Protected.IsAutomationRun));
    }

    if ($WorkerCount -lt 1 -or $WorkerCount -gt $GlobalVariable.Public.Threading.MaxThreads) {
        return (Write-FunctionReturnValue -ReturnValue 'InvalidRestApiWorkerCountProvided' -Data @{ 'WorkerCount' = $WorkerCount; 'MaxThreads' = $GlobalVariable.Public.Threading.MaxThreads } -AutomationRun:($Global:IcingaForWindows.Protected.IsAutomationRun));
    }

    $RestApiConfig = [PSCustomObject]@{
        'ListenAddress' = $ListenAddress;
        'ListenPort'    = $ListenPort;
        'TlsCertConfig' = $TlsCertConfig;
        'WorkerCount'   = $WorkerCount;
    };

    if ($DryRun) {
        return (
            Compare-IcingaTextContent `
                -NewConfig (ConvertTo-Json -InputObject $RestApiConfig -Depth 5) `
                -OldFile (Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath 'restapi.json') `
                -Colorized:(-not $Global:IcingaForWindows.Protected.NoColorizedOutput)
        );
    }

    $GlobalVariable.Public.RestApi.Config = $RestApiConfig;

    Write-SecureFile `
        -File (Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath 'restapi.json') `
        -Value ($GlobalVariable.Public.RestApi.Config | ConvertTo-Json -Depth 3) | Out-Null;

    # All endpoints validated; persist or return success
    return (Write-FunctionReturnValue -ReturnValue 'RestApiConfigConfigured' -Data @{ 'Config' = $GlobalVariable.Public.RestApi.Config } -AutomationRun:($Global:IcingaForWindows.Protected.IsAutomationRun));
}

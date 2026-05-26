<#
.SYNOPSIS
Register and persist a WebSocket configuration.

.DESCRIPTION
`Add-ModuleWebSocketConfig` validates a WebSocket configuration payload,
stores it in the runtime configuration (`$Global:ModuleName.Public.WebSocket.Config`),
and persists a pointer file under the module config directory. The function
reads the referenced type-specific config via `Read-ModuleConfigFile` and
only writes a path pointer to disk.

.PARAMETER Name
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Name | System.String | Logical name for the WebSocket config | |

.PARAMETER Address
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Address | System.String | Remote WebSocket URI (wss://...) | |

.PARAMETER Config
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Config | System.String | Path or pointer to the type-specific config | |

.PARAMETER Type
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Type | System.String | Logical type for the WebSocket config | |

.PARAMETER Force
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.SwitchParameter | Overwrite an existing config with the same name | false |

.OUTPUTS
System.Object — Returns a structured module return indicating success or the validation failure.

.EXAMPLE
PS> Add-ModuleWebSocketConfig -Name 'MyWebSocket' -Address 'wss://example.com' -Config 'configs\mywebsocket.json' -Type MyWebSocket

.NOTES
The persisted file under the config directory contains only the path pointer to
the type-specific config (not the full in-memory object). The configuration is
stored in `$Global:ModuleName.Public.WebSocket.Config` and accessed via
`Get-GlobalRuntimeVariable`.
#>
function Add-ModuleWebSocketConfig()
{
    param (
        [string]$Name    = $null,
        [string]$Address = $null,
        [string]$Config  = $null,
        [string]$Type    = $null,
        [switch]$Force   = $false
    );

    if ([string]::IsNullOrEmpty($Name)) {
        return (Write-FunctionReturnValue -ReturnValue 'NoWebSocketConfigNameProvided');
    }

    # Validate that we have at least one endpoint
    if ([string]::IsNullOrEmpty($Address)) {
        return (Write-FunctionReturnValue -ReturnValue 'NoWebSocketConfigAddressProvided');
    }

    # We have to provide the top-level config file for this WebSocket connection and type
    if ([string]::IsNullOrEmpty($Config)) {
        return (Write-FunctionReturnValue -ReturnValue 'NoWebSocketConfigProvided');
    }

    # Try to read and validate the provided config
    $ConfigObj = Read-ModuleConfigFile -Config $Config -IncludeSubConfig;

    if ($null -eq $ConfigObj) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketConfigReadFailed');
    }

    $GlobalVariable   = Get-GlobalRuntimeVariable;
    [string]$SafeName = Remove-ModuleAmbitiousCharacters -InputString $Name -RemoveSpaces;

    if ($null -ne $GlobalVariable.Public.WebSocket.Config.$SafeName -and -not $Force) {
        return (Write-FunctionReturnValue -ReturnValue 'WebSocketConfigNameAlreadyExists' -Data @{ 'Name' = $SafeName; } );
    }

    $WebSocketConfig = [PSCustomObject]@{
        'Name'    = $SafeName;
        'Address' = $Address;
        'Type'    = $Type;
        'Config'  = $ConfigObj;
    };

    $GlobalVariable.Public.WebSocket.Config | Add-Member -MemberType NoteProperty -Name $SafeName -Value $WebSocketConfig -Force;

    New-SecureItem -ItemType 'Directory' -Path (Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath 'WebSocket') -Force | Out-Null;

    # Ensure we only write the path pointing to the config, not the full config object
    $WebSocketConfig.Config = $Config;

    # Write the WebSocket config to file
    Write-SecureFile `
        -File (Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath ([string]::Format('WebSocket\{0}.json', $SafeName.ToLower()))) `
        -Value $WebSocketConfig | Out-Null;

    # Re-assign the parsed config object back to the in-memory config
    $WebSocketConfig.Config = $ConfigObj;

    # All endpoints validated; persist or return success
    return (Write-FunctionReturnValue -ReturnValue 'WebSocketConfigConfiguredSuccessfully' -Data @{ 'Config' = $GlobalVariable.Public.WebSocket.Config.$SafeName });
}

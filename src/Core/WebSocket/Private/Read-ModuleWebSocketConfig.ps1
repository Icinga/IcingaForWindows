<#
.SYNOPSIS
Load WebSocket configuration files into the runtime config store.

.DESCRIPTION
`Read-ModuleWebSocketConfig` scans the module configuration directory for
WebSocket JSON files, validates and parses each file, then loads the
referenced type-specific configuration using `Read-ModuleConfigFile`.
Parsed configurations are stored in `$Global:ModuleName.Public.WebSocket.Config`.

.OUTPUTS
System.Object -- Emits structured `Write-FunctionReturnValue` values indicating
load results and returns the populated config object on success.

.EXAMPLE
PS> Read-ModuleWebSocketConfig

.NOTES
Each WebSocket configuration file must include a `Name` property and a `Config`
pointer referencing the type-specific configuration file. Parsed configurations
are stored in `$Global:ModuleName.Public.WebSocket.Config` and accessed via
`Get-GlobalRuntimeVariable`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Read-ModuleWebSocketConfig()
{
    # Load all WebSocket configuration files from the config directory
    $ConfigDirectory = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath 'WebSocket';
    $WebSocketFiles  = Get-SecureChildItem -Path $ConfigDirectory -Filter '*.json' -ErrorAction SilentlyContinue;
    $GlobalVariable  = Get-GlobalRuntimeVariable;

    foreach ($WsFile in $WebSocketFiles) {
        $FileContent = Read-SecureFile -File $WsFile.FullName;

        # Validate file content
        if ($null -eq $FileContent) {
            Write-FunctionReturnValue -ReturnValue 'WebSocketConfigNotFoundOrEmpty' -Data @{ 'ConfigFile' = $WsFile.FullName } | Out-Null;
            continue;
        }

        try {
            # Parse JSON content
            $ConfigObject = $FileContent | ConvertFrom-Json -ErrorAction Stop;
        } catch {
            Write-FunctionReturnValue -ReturnValue 'WebSocketConfigCorrupted' -Data @{ 'ConfigFile' = $WsFile.FullName; 'Exception' = $_.Exception } | Out-Null;
            continue;
        }

        # Validate required properties
        if ([string]::IsNullOrEmpty($ConfigObject.Name)) {
            Write-FunctionReturnValue -ReturnValue 'WebSocketConfigMissingName' -Data @{ 'ConfigFile' = $WsFile.FullName } | Out-Null;
            continue;
        }

        # Read and parse the type-specific config, which is always stored as path pointer reference
        $ConfigObject | Add-Member -MemberType NoteProperty -Name 'Config' -Value (Read-ModuleConfigFile -Config $ConfigObject.Config -IncludeSubConfig) -Force;

        # Store the configuration object in the global config PSObject
        $GlobalVariable.Public.WebSocket.Config | Add-Member -MemberType NoteProperty -Name $ConfigObject.Name -Value $ConfigObject -Force;
    }

    # Return success
    return (Write-FunctionReturnValue -ReturnValue 'WebSocketConfigLoadedSuccessfully' -Data @{ 'Config' = $GlobalVariable.Public.WebSocket.Config });
}

<#
.SYNOPSIS
Read and parse a module JSON configuration file

.DESCRIPTION
Read-ModuleConfigFile loads a configuration file from the module config
directory, parses it as JSON and returns the resulting object. If
-IncludeSubConfig is supplied and the top-level JSON object contains a Config
property, that sub-config will be read recursively and attached as a Config
property on the returned object. On error the function returns a structured
error object via Write-FunctionReturnValue with -OverrideReturn $null so that
callers receive $null on failure.

.PARAMETER Config
| Name   | Type          | Description                     | Default |
|--------|---------------|---------------------------------|---------|
| Config | System.String | Filename of the config to read. | $null   |

.PARAMETER IncludeSubConfig
| Name             | Type                                         | Description                                                   | Default |
|------------------|----------------------------------------------|---------------------------------------------------------------|---------|
| IncludeSubConfig | System.Management.Automation.SwitchParameter | When set, recursively reads sub-configs referenced by Config. | $false  |

.OUTPUTS
System.Object -- Parsed JSON object on success, or $null on error.

.EXAMPLE
PS> Read-ModuleConfigFile -Config 'module.json' -IncludeSubConfig

Reads module.json from the module config directory and recursively attaches
any referenced sub-config.

.NOTES
Relies on Get-ModuleConfigDirectory and Read-SecureFile for file I/O.
Returns $null via -OverrideReturn $null on error to match calling conventions
elsewhere in the module.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Read-ModuleConfigFile()
{
    param (
        [string]$Config           = $null,
        [switch]$IncludeSubConfig = $false
    );

    if ([string]::IsNullOrEmpty($Config)) {
        return (Write-FunctionReturnValue -ReturnValue 'ConfigFileNotProvided' -OverrideReturn $null);
    }

    [string]$ConfigPath = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath $Config;

    if (-not (Test-Path $ConfigPath)) {
        return (Write-FunctionReturnValue -ReturnValue 'ConfigFileNotFound' -Data @{ 'Path' = $ConfigPath } -OverrideReturn $null);
    }

    $ConfigJson = Read-SecureFile -File $ConfigPath;

    if ([string]::IsNullOrEmpty($ConfigJson)) {
        return (Write-FunctionReturnValue -ReturnValue 'ConfigFileReadFailed' -Data @{ 'Path' = $ConfigPath } -OverrideReturn $null);
    }

    try {
        $ConfigObj = $ConfigJson | ConvertFrom-Json;

        # If we read sub-configs, check for a 'Config' property and read it recursively
        if ($null -ne $ConfigObj.Config -and $IncludeSubConfig) {
            # Recursively read sub-config
            $ConfigObj | Add-Member -MemberType NoteProperty -Name 'Config' -Value (Read-ModuleConfigFile -Config $ConfigObj.Config -IncludeSubConfig) -Force;
        }

        return $ConfigObj;
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'ConfigFileInvalidJson' -Data @{ 'Path' = $ConfigPath } -OverrideReturn $null);
    }
}

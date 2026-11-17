<#
.SYNOPSIS
Ensure the module configuration and binaries directories exist

.DESCRIPTION
New-ModuleConfigEnvironment checks whether the module binaries directory
(Get-ModuleBinaryDirectory) and module configuration directory
(Get-ModuleConfigDirectory) exist. Missing directories are created automatically
with New-Item. If the configuration directory was already present, the function
emits ConfigPresent via Write-FunctionReturnValue and returns its mapped numeric
return code; otherwise it creates the directory, emits ConfigMissing and returns
its mapped numeric return code.

.OUTPUTS
System.Int32 -- Mapped numeric return code from Write-FunctionReturnValue for
ConfigPresent or ConfigMissing.

.EXAMPLE
PS> New-ModuleConfigEnvironment

Ensures both the binaries directory and the config directory are present,
creating them if necessary, and returns the mapped numeric return code.

.NOTES
Uses Get-ModuleConfigDirectory and Get-ModuleBinaryDirectory to resolve target
paths. Missing directories are created with -Force.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-ModuleConfigEnvironment()
{
    [string]$ConfigDirectory = Get-ModuleConfigDirectory;
    [string]$BinaryDirectory = Get-ModuleBinaryDirectory;

    if (-not (Test-Path -Path $BinaryDirectory)) {
        New-Item -Path $BinaryDirectory -ItemType Directory -Force | Out-Null;
    }

    if ((Test-Path -Path $ConfigDirectory)) {
        return (Write-FunctionReturnValue -ReturnValue 'ConfigPresent' -Data @{ 'ConfigDirectory' = $ConfigDirectory; 'BinaryDirectory' = $BinaryDirectory; });
    }

    New-Item -Path $ConfigDirectory -ItemType Directory -Force | Out-Null;

    return (Write-FunctionReturnValue -ReturnValue 'ConfigMissing' -Data @{ 'ConfigDirectory' = $ConfigDirectory; 'BinaryDirectory' = $BinaryDirectory; });
}

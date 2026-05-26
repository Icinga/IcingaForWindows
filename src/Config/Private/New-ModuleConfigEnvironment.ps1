<#
.SYNOPSIS
Ensure the module configuration directory exists

.DESCRIPTION
New-ModuleConfigEnvironment checks whether the module configuration directory
exists via Get-ModuleConfigDirectory. If the directory is already present the
function returns a structured Write-FunctionReturnValue result with ReturnValue
set to ConfigPresent. If the directory is missing it creates it with New-Item
and returns ConfigMissing.

.OUTPUTS
System.Object — Structured return object from Write-FunctionReturnValue with
ReturnValue set to either ConfigPresent or ConfigMissing.

.EXAMPLE
PS> New-ModuleConfigEnvironment

Ensures the config directory is present, creating it if necessary, and returns
a structured result indicating whether the directory was already there.

.NOTES
Uses Get-ModuleConfigDirectory to resolve the target path. The directory is
created with -Force when it is missing.
#>
function New-ModuleConfigEnvironment()
{
    [string]$ConfigDirectory = Get-ModuleConfigDirectory;

    if ((Test-Path -Path $ConfigDirectory)) {
        return (Write-FunctionReturnValue -ReturnValue 'ConfigPresent' -Data @{ 'ConfigDirectory' = $ConfigDirectory });
    }

    New-Item -Path $ConfigDirectory -ItemType Directory -Force | Out-Null;

    return (Write-FunctionReturnValue -ReturnValue 'ConfigMissing' -Data @{ 'ConfigDirectory' = $ConfigDirectory });
}

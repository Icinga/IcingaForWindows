<#
.SYNOPSIS
Create a filesystem item (file or directory) only in approved locations.

.DESCRIPTION
Creates a new file or directory using `New-Item` but first verifies that the
target path is within approved config directories using `Test-SecureApprovedPath`.
Returns standardized return values via `Write-FunctionReturnValue` and logs
unauthorized attempts.

.PARAMETER Path
| Name | Type          | Description                         | Default |
|------|---------------|-------------------------------------|---------|
| Path | System.String | Path to create (file or directory). | $null   |

.PARAMETER ItemType
| Name     | Type          | Description            | Default |
|----------|---------------|------------------------|---------|
| ItemType | System.String | 'File' or 'Directory'. | 'File'  |

.PARAMETER Force
| Name  | Type                                         | Description                                              | Default |
|-------|----------------------------------------------|----------------------------------------------------------|---------|
| Force | System.Management.Automation.SwitchParameter | Pass `-Force` to `New-Item` to overwrite existing items. | $false  |

.OUTPUTS
PSCustomObject -- Function return value via Write-FunctionReturnValue.
ObjectCreationSucceeded on success (Data contains Path, ItemType and Item).
ObjectCreationFailed, AccessViolation or DirectoryArgumentEmpty on errors.

.EXAMPLE
PS> New-SecureItem -Path (Join-Path (Get-ModuleConfigDirectory) 'my.conf') -ItemType File

.NOTES
Intended for use when module code must create config files; restricts creation
to module config directories only.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-SecureItem()
{
    param (
        [string]$Path     = $null,
        [ValidateSet('File', 'Directory')]
        [string]$ItemType = 'File',
        [switch]$Force    = $false
    );

    if ([string]::IsNullOrEmpty($Path)) {
        return (Write-FunctionReturnValue -ReturnValue 'DirectoryArgumentEmpty' -Data @{ 'Path' = $Path } -OverrideReturn $null);
    }

    # Define approved paths (config directories)
    [array]$ApprovedPathList = @(
        (Get-ModuleConfigDirectory)
    );

    if ((Test-SecureApprovedPath -Path $Path -ApprovedPath $ApprovedPathList) -ne (Get-GlobalRuntimeVariable).Public.ReturnCodes.AccessGranted.Code) {
        Write-LoggingEntry -Message 'Attempt to create item at unapproved path {0}' -Level 'Debug' -Data @{
            'Path'        = $Path;
            'AccessCheck' = (Test-SecureApprovedPath -Path $Path -ApprovedPath $ApprovedPathList);
        };
        return (Write-FunctionReturnValue -ReturnValue 'AccessViolation' -Data @{ 'Path' = $Path } -OverrideReturn $null);
    }

    $Result = $null;

    try {
        $Result = New-Item -Path $Path -ItemType $ItemType -Force:$Force -ErrorAction Stop;
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'ObjectCreationFailed' -Data @{ 'Path' = $Path; 'ItemType' = $ItemType; 'Exception' = $_.Exception } -OverrideReturn $null);
    }

    return (Write-FunctionReturnValue -ReturnValue 'ObjectCreationSucceeded' -Data @{ 'Path' = $Path; 'ItemType' = $ItemType; 'Item' = $Result } -OverrideReturn $Result);
}

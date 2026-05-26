<#
.SYNOPSIS
Safely remove files or directories within approved module locations.

.DESCRIPTION
Removes filesystem items after verifying the target path is within approved
directories. Logs unauthorized attempts and returns structured return values
using `Write-FunctionReturnValue`.

.PARAMETER Path
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Path to remove. | '' |

.PARAMETER Recurse
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Remove child items recursively. | $false |

.PARAMETER Force
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.Management.Automation.SwitchParameter | Force deletion (pass `-Force` to `Remove-Item`). | $false |

.OUTPUTS
PSCustomObject — Function return value via Write-FunctionReturnValue.
RemoveItemSuccess on success (Data contains Path).
RemoveItemFailed, AccessViolation, RemoveItemNoPathProvided or RemoveItemPathNotFound on errors.

.EXAMPLE
PS> Remove-SecureItem -Path (Join-Path (Get-ModuleCacheDirectory) 'temp.log') -Force

.NOTES
Intended to limit deletion operations to module-managed directories only.
#>
function Remove-SecureItem()
{
    param (
        [string]$Path    = '',
        [switch]$Recurse = $false,
        [switch]$Force   = $false
    );

    # Ensure we specify a path
    if ([string]::IsNullOrEmpty($Path)) {
        return (Write-FunctionReturnValue -ReturnValue 'RemoveItemNoPathProvided');
    };

    # Check if the item exists
    if (-not (Test-Path $Path)) {
        return (Write-FunctionReturnValue -ReturnValue 'RemoveItemPathNotFound' -Data @{ 'Path' = $Path });
    };

    # Define approved paths (config directories)
    [array]$ApprovedPathList = @(
        (Get-ModuleConfigDirectory),
        (Get-ModuleCacheDirectory)
    );

    if ((Test-SecureApprovedPath -Path $Path -ApprovedPath $ApprovedPathList) -ne (Get-GlobalRuntimeVariable).Public.ReturnCodes.AccessGranted.Code) {
        Write-LoggingEntry -Message 'Attempt to remove item at unapproved path' -Level 'Debug' -Data @{
            'Path'        = $Path;
            'AccessCheck' = (Test-SecureApprovedPath -Path $Path -ApprovedPath $ApprovedPathList)
        };
        return (Write-FunctionReturnValue -ReturnValue 'AccessViolation' -Data @{ 'Path' = $Path });
    }

    try {
        # Remove the item
        Remove-Item -Path $Path -Recurse:$Recurse -Force:$Force -ErrorAction Stop | Out-Null;

        # Return success
        return (Write-FunctionReturnValue -ReturnValue 'RemoveItemSuccess' -Data @{ 'Path' = $Path });
    } catch {
        # Return failure
        return (Write-FunctionReturnValue -ReturnValue 'RemoveItemFailed' -Data @{ 'Path' = $Path; 'Exception' = $_.Exception });
    };
}

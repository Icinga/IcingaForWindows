<#
.SYNOPSIS
Check whether a path is within an approved set of directories.

.DESCRIPTION
Normalizes the provided approved paths and the target path, then verifies
whether the target path starts with any approved path prefix. Logs an audit
entry for each check and returns standardized return values.

.PARAMETER Path
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Path to validate. | $null |

.PARAMETER ApprovedPath
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ApprovedPath | System.Array | Array of allowed directory paths (strings). | @() |

.OUTPUTS
PSCustomObject — Function return value via Write-FunctionReturnValue.
AccessGranted when the path is within an approved directory.
AccessViolation or DirectoryArgumentEmpty otherwise.

.EXAMPLE
PS> Test-SecureApprovedPath -Path (Join-Path (Get-ModuleConfigDirectory) 'x') -ApprovedPath @(Get-ModuleConfigDirectory)

.NOTES
Uses `Resolve-Path` to normalize paths; callers should ensure ApprovedPath entries exist.
#>
function Test-SecureApprovedPath()
{
    param (
        [string]$Path        = $null,
        [array]$ApprovedPath = @()
    );

    if ([string]::IsNullOrEmpty($Path)) {
        return (Write-FunctionReturnValue -ReturnValue 'DirectoryArgumentEmpty' -Data @{ 'Path' = $Path; });
    }

    [array]$NormalizedApprovedPaths = (Resolve-Path -Path $ApprovedPath -ErrorAction SilentlyContinue).Path;
    [string]$NormalizedPath         = $Path;
    if (Test-Path -Path $Path) {
        $NormalizedPath = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue).Path;
    }

    Write-LoggingEntry -Message 'Attempting to access filesystem' -Level 'Audit' -Data @{
        'Path'                    = $Path;
        'ApprovedPath'            = $ApprovedPath;
        'NormalizedApprovedPaths' = $NormalizedApprovedPaths;
        'NormalizedPath'          = $NormalizedPath;
    };

    foreach ($allowedPath in $NormalizedApprovedPaths) {
        if ($NormalizedPath.StartsWith($allowedPath)) {
            return (Write-FunctionReturnValue -ReturnValue 'AccessGranted' -Data @{ 'Path' = $Path; });
        }
    }

    return (Write-FunctionReturnValue -ReturnValue 'AccessViolation' -Data @{ 'Path' = $Path; });
}

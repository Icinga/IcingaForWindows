<#
.SYNOPSIS
Secure wrapper around `Get-ChildItem` that restricts access to approved paths.

.DESCRIPTION
Fetches child items from the filesystem while enforcing approved-path checks
via `Test-SecureApprovedPath`. This prevents access to arbitrary filesystem
locations. Returns standardized return values with `Write-FunctionReturnValue`.

.PARAMETER Path
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Directory path to enumerate. | '' |

.PARAMETER Filter
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Filter | System.String | File name filter (for example '*.json'). | '*' |

.PARAMETER Include
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Include | System.Array | Additional include patterns for `Get-ChildItem`. | @() |

.PARAMETER File
| Name | Type | Description | Default |
|------|------|-------------|---------|
| File | System.Management.Automation.SwitchParameter | If set, only return files. | $false |

.PARAMETER Directory
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Directory | System.Management.Automation.SwitchParameter | If set, only return directories. | $false |

.PARAMETER Recurse
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Recurse into subdirectories. | $false |

.OUTPUTS
PSCustomObject — Function return value via Write-FunctionReturnValue.
ChildItemFetchSucceeded on success (Data contains Path and Items).
ChildItemFetchFailed, AccessViolation or ChildItemPathArgumentEmpty on errors.

.EXAMPLE
PS> Get-SecureChildItem -Path (Get-ModuleConfigDirectory) -File

.NOTES
This helper logs attempted access to unapproved paths and returns `AccessViolation`.
#>
function Get-SecureChildItem()
{
    param (
        [string]$Path      = '',
        [string]$Filter    = '*',
        [array]$Include    = @(),
        [switch]$File      = $false,
        [switch]$Directory = $false,
        [switch]$Recurse   = $false
    )

    # Validate the Path parameter
    if ([string]::IsNullOrEmpty($Path)) {
        return (Write-FunctionReturnValue -ReturnValue 'ChildItemPathArgumentEmpty' -Data @{ 'Path' = $Path } -OverrideReturn $null);
    }

    # Define approved paths (root and config directories)
    [array]$ApprovedPathList = @(
        (Get-ModuleRootDirectory),
        (Get-ModuleConfigDirectory),
        (Get-ModuleCacheDirectory)
    );

    # Validate access to the specified path
    if ((Test-SecureApprovedPath -Path $Path -ApprovedPath $ApprovedPathList) -ne (Get-GlobalRuntimeVariable).Public.ReturnCodes.AccessGranted.Code) {
        Write-LoggingEntry -Message 'Attempt to fetch items at unapproved path {0}' -Level 'Debug' -Data @{
            'Path'        = $Path;
            'AccessCheck' = (Test-SecureApprovedPath -Path $Path -ApprovedPath $ApprovedPathList);
        };
        return (Write-FunctionReturnValue -ReturnValue 'AccessViolation' -Data @{ 'Path' = $Path } -OverrideReturn $null);
    }

    # Fetch the child items
    try {
        $Result = Get-ChildItem -Path $Path -Filter $Filter -Include $Include -File:$File -Directory:$Directory -Recurse:$Recurse -ErrorAction Stop;
    } catch {
        # Return error if fetching failed
        return (Write-FunctionReturnValue -ReturnValue 'ChildItemFetchFailed' -Data @{ 'Path' = $Path; 'Exception' = $_.Exception } -OverrideReturn $null);
    }

    # Return the fetched items
    return (Write-FunctionReturnValue -ReturnValue 'ChildItemFetchSucceeded' -Data @{ 'Path' = $Path; 'Items' = $Result } -OverrideReturn $Result);
}

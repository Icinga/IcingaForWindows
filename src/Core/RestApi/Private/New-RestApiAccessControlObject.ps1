<#
.SYNOPSIS
Create a RestApi access control object describing allowed methods and resources.

.DESCRIPTION
Helps construct a reusable access control object for RestApi spaces. The
object contains allowed HTTP methods, allowed/blocked resources, allowed
client origins, credentials requirement and a request body size limit.
It is intended to be embedded in system access roles or used directly by
the RestApi access control evaluation routines.

.PARAMETER AllowedMethods
| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedMethods | System.String[] | List of allowed HTTP methods (case-insensitive). Use `*` to allow all. | @('GET') |

.PARAMETER AllowedResources
| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedResources | System.String[] | Glob-style patterns of resources that are explicitly allowed. Use `*` to allow all. | @() |

.PARAMETER BlockedResources
| Name | Type | Description | Default |
|------|------|-------------|---------|
| BlockedResources | System.String[] | Glob-style patterns of resources that are explicitly blocked. Use `*` to block all. | @('*') |

.PARAMETER AllowedOrigins
| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedOrigins | System.String[] | Client IP/hostname patterns that are allowed to access the API. Use `*` to allow all origins. | @('*') |

.PARAMETER RequireCredentials
| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequireCredentials | System.Boolean | When true, the ACL requires credentials (not implemented in this helper). | $false |

.PARAMETER RequestBodySizeLimitKB
| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequestBodySizeLimitKB | System.Int32 | Maximum allowed request body size in kilobytes. Negative values are normalized to 0. | 1024 |

.OUTPUTS
PSCustomObject — access control object ready for inclusion in role definitions.

.EXAMPLE
PS> New-RestApiAccessControlObject -AllowedMethods @('GET','POST') -AllowedResources @('/v1/*') -RequestBodySizeLimitKB 512

.NOTES
The returned object converts KB limit to bytes and normalizes string
arrays. The `RequireCredentials` flag is informational — credential
enforcement must be implemented in the request handling logic.
#>
function New-RestApiAccessControlObject()
{
    param (
        [ValidateSet('POST', 'GET', 'PUT', 'DELETE', 'PATCH', 'OPTIONS', 'HEAD', '*')]
        [string[]]$AllowedMethods    = @('GET'),
        [string[]]$AllowedResources  = @(),
        [string[]]$BlockedResources  = @('*'),
        [string[]]$AllowedOrigins    = @('*'),
        [bool]$RequireCredentials    = $false,
        [int]$RequestBodySizeLimitKB = 1024
    );

    # Ensure we have at least one allowed method specified
    if ($AllowedMethods.Count -eq 0) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessControlNoAllowedRestApiMethodsSpecified' -OverrideReturn $null);
    };

    # Validate RequestBodySizeLimitKB and set to 0 if negative
    if ($RequestBodySizeLimitKB -lt 0) {
        $RequestBodySizeLimitKB = 0;
    };

    # If all resources are blocked and no allowed resources, write a warning to the user
    if ($BlockedResources -contains('*') -and $AllowedResources.Count -eq 0) {
        Write-FunctionReturnValue -ReturnValue 'AccessControlAllRestApiResourcesBlocked' | Out-Null;
    };

    # If all resources are allowed, log this information as warning as well
    if ($AllowedResources -contains('*')) {
        Write-FunctionReturnValue -ReturnValue 'AccessControlAllRestApiResourcesAllowed' | Out-Null;
    };

    # Create the access control object
    $AccessControlObject = [PSCustomObject]@{
        'AllowedMethods'       = ConvertTo-StringNormalizedArray -InputArray $AllowedMethods -UpperCase;
        'AllowedResources'     = ConvertTo-StringNormalizedArray -InputArray $AllowedResources;
        'BlockedResources'     = ConvertTo-StringNormalizedArray -InputArray $BlockedResources;
        'AllowedOrigins'       = ConvertTo-StringNormalizedArray -InputArray $AllowedOrigins;
        'RequireCredentials'   = $RequireCredentials;
        'RequestBodySizeLimit' = $RequestBodySizeLimitKB * 1024; # Convert KB to Bytes
        'Scope'                = 'RestApi';
    };

    # Return the created object. It now can be assigned to New-AccessRole
    return (Write-FunctionReturnValue -ReturnValue 'AccessControlObjectCreated' -Data @{ 'AccessControlObject' = $AccessControlObject } -OverrideReturn $AccessControlObject);
}

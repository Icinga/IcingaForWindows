<#
.SYNOPSIS
Create a RestApi access control object for use in Icinga role definitions

.DESCRIPTION
Public wrapper around `New-RestApiAccessControlObject` that constructs a
reusable access control descriptor for the RestApi subsystem. The returned
object specifies which HTTP methods, resources and client origins are
permitted for a role, whether credentials are required and the maximum
allowed request body size. Pass the returned object to `New-AccessRole`
to attach it to a user or group.

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
| AllowedOrigins | System.String[] | Client IP or hostname patterns that may access the API. Use `*` to allow all origins. | @('*') |

.PARAMETER RequireCredentials
| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequireCredentials | System.Boolean | When true, the access control entry requires credentials. | $false |

.PARAMETER RequestBodySizeLimitKB
| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequestBodySizeLimitKB | System.Int32 | Maximum allowed request body size in kilobytes. Negative values are normalized to 0. | 1024 |

.OUTPUTS
PSCustomObject — access control object with `AllowedMethods`, `AllowedResources`,
`BlockedResources`, `AllowedOrigins`, `RequireCredentials`,
`RequestBodySizeLimit` (bytes) and `Scope` set to `RestApi`.

.EXAMPLE
PS> New-IcingaRestApiAccessControlObject -AllowedMethods @('GET','POST') -AllowedResources @('/v1/*') -RequestBodySizeLimitKB 512

.NOTES
The `RequireCredentials` flag is informational in the current implementation;
credential enforcement must be added in the request handling logic.
The KB limit is converted to bytes internally. At least one allowed method
must be specified; passing an empty array causes the function to return `$null`.
#>
function New-IcingaRestApiAccessControlObject()
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

    return (
        New-RestApiAccessControlObject `
            -AllowedMethods $AllowedMethods `
            -AllowedResources $AllowedResources `
            -BlockedResources $BlockedResources `
            -AllowedOrigins $AllowedOrigins `
            -RequireCredentials $RequireCredentials `
            -RequestBodySizeLimitKB $RequestBodySizeLimitKB
    );
}

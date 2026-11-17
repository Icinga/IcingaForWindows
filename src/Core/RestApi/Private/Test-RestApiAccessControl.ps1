<#
.SYNOPSIS
Evaluate access control rules for an incoming RestApi request.

.DESCRIPTION
Checks configured access control entries for the RestApi subsystem and
determines whether the current request is permitted. Supports checking
origins (client IP) and request body size limits.

.PARAMETER TestOrigins
| Name        | Type            | Description                                               | Default |
|-------------|-----------------|-----------------------------------------------------------|---------|
| TestOrigins | SwitchParameter | If set, evaluates allowed client origins for the request. | $false  |

.PARAMETER TestContentLength
| Name              | Type            | Description                                           | Default |
|-------------------|-----------------|-------------------------------------------------------|---------|
| TestContentLength | SwitchParameter | If set, enforces configured request body size limits. | $false  |

.OUTPUTS
System.Int32 -- structured return code from `Write-FunctionReturnValue` indicating
permission granted, denied, origin blocked or content length exceeded.

.EXAMPLE
PS> Test-RestApiAccessControl -TestOrigins

.NOTES
This function uses the protected `AccessControl` configuration stored in
the global runtime variable and the current RestApi context.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Test-RestApiAccessControl()
{
    param (
        [switch]$TestOrigins       = $false,
        [switch]$TestContentLength = $false
    );

    $GlobalVariable                  = Get-GlobalRuntimeVariable;
    # Retrieve the current access control settings
    [PSCustomObject[]]$AccessControl = $GlobalVariable.Protected.AccessControl;

    # If no access control is defined, allow all access
    if ($null -eq $AccessControl -or $AccessControl.Count -eq 0) {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlNotDefined');
    }

    [string]$WebPath        = Join-WebPath -Path $GlobalVariable.Private.RestApi.WebPath.WebPath -ChildPath '/';
    [PSCustomObject]$Header = $GlobalVariable.Private.RestApi.Header;

    # Get the current user's identity
    # TODO: This is just for testing purposes. We actually need to use basic auth or something, to get the user information form the user requesting the service and not the user running the PowerShell process
    [string]$CurrentUser    = [System.Environment]::UserName.ToLower();
    # Check if the current user has access based on the defined access control settings
    foreach ($AclEntry in $AccessControl) {
        [PSCustomObject]$AclObj = $AclEntry.AccessControlObject;
        [bool]$PathAllowed      = $false;

        # Only check entries that apply to the REST API
        if ($AclObj.Scope.ToLower() -ne 'restapi') {
            continue;
        }

        # Check if the current user is listed in the ACL entry or if a wildcard is used
        if ($AclEntry.Users -notcontains $CurrentUser -and $AclEntry.Users -notcontains '*') {
            continue;
        }

        # Now we found a matching ACL entry for the current user, check the permissions

        # First check if the connected TcpClient is actually allowed to access the API
        # AllowedOrigins is a list of allowed client IPs or hostnames and all our client data is
        # stored in $GlobalVariable.Private.TCP.Client
        if ($TestOrigins) {
            if ($AclObj.AllowedOrigins -notcontains '*') {
                [string]$ClientEndpoint = $GlobalVariable.Private.TCP.Client.Client.RemoteEndPoint.Address.ToString();

                foreach ($AllowedOrigin in $AclObj.AllowedOrigins) {
                    if ($ClientEndpoint -like $AllowedOrigin) {
                        return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlPermissionGranted' -Data @{ 'User' = $CurrentUser; 'Role' = $AclEntry.RoleName });
                    }
                }

                return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlOriginNotAllowed' -Data @{ 'User' = $CurrentUser; 'ClientEndpoint' = $ClientEndpoint; 'WebPath' = $WebPath });
            }

            return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlPermissionGranted' -Data @{ 'User' = $CurrentUser; 'Role' = $AclEntry.RoleName });
        }

        # Check if there is a request body size limit and if the current request exceeds it
        if ($TestContentLength) {
            if ($GlobalVariable.Private.RestApi.ContentLength -gt $AclObj.RequestBodySizeLimit) {
                return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlContentLengthExceeded' -Data @{ 'User' = $CurrentUser; 'WebPath' = $WebPath; 'ContentLength' = $GlobalVariable.Private.RestApi.ContentLength; 'RequestBodySizeLimit' = $AclObj.RequestBodySizeLimit });
            }

            return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlPermissionGranted' -Data @{ 'User' = $CurrentUser; 'Role' = $AclEntry.RoleName });
        }

        # First check if our Method is allowed
        if ($AclObj.AllowedMethods.Count -gt 0 -and $AclObj.AllowedMethods -notcontains '*' -and $AclObj.AllowedMethods -notcontains $Header.Method.ToUpper()) {
            return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlMethodNotAllowed' -Data @{ 'User' = $CurrentUser; 'Method' = $Header.Method; 'WebPath' = $WebPath });
        }

        # Now we need to determine if the requested resource is allowed or blocked
        # By default, assume it's blocked unless explicitly allowed. Which means, if BlockedResources is '*', we block everything except what is explicitly allowed.
        # Otherwise, if BlockedResources contains single entries we just block access to those and grant access to everything else.
        if ($AclObj.BlockedResources -contains '*') {
            # If BlockedResources contains '*', we need to find an explicit allow entry
            if ($AclObj.AllowedResources -contains '*') {
                $PathAllowed = $true; # Everything is allowed
            } else {
                foreach ($AllowedResource in $AclObj.AllowedResources) {
                    if ($WebPath.ToLower() -like $AllowedResource.ToLower()) {
                        $PathAllowed = $true;
                        break;
                    }
                }
            }
        } else {
            # If BlockedResources contains specific entries, we block only those
            if ($AclObj.BlockedResources.ToLower() -contains $WebPath.ToLower()) {
                $PathAllowed = $false;
                break;
            } else {
                # If we are not blocked, check if we are explicitly allowed
                if ($AclObj.AllowedResources -contains '*') {
                    $PathAllowed = $true; # Everything except blocked is allowed
                } else {
                    foreach ($AllowedResource in $AclObj.AllowedResources) {
                        if ($WebPath.ToLower() -like $AllowedResource.ToLower()) {
                            $PathAllowed = $true;
                            break;
                        }
                    }
                }
            }
        }

        # If the path is not allowed, continue to the next ACL entry
        if (-not $PathAllowed) {
            continue;
        }

        # If we reach here, the user has permission for this request
        return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlPermissionGranted' -Data @{ 'User' = $CurrentUser; 'Role' = $AclEntry.RoleName; 'WebPath' = $WebPath });
    }

    return (Write-FunctionReturnValue -ReturnValue 'RestApiAccessControlPermissionDenied' -Data @{ 'User' = $CurrentUser; 'WebPath' = $WebPath });
}

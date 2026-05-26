<#
.SYNOPSIS
Create and persist a module access role with allowed users and ACLs

.DESCRIPTION
Constructs an access role object that contains the role name, users,
access control objects and inherited roles. Persists the role as a JSON
file under the module config `AccessRoles` directory using secure file helpers
and reloads the module access control definitions.

.PARAMETER RoleName
| Name | Type | Description | Default |
|------|------|-------------|---------|
| RoleName | System.String | Friendly name for the access role. | '' |

.PARAMETER Users
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Users | System.String[] | List of usernames (or identifiers) assigned to the role. | @() |

.PARAMETER AccessControlObject
| Name | Type | Description | Default |
|------|------|-------------|---------|
| AccessControlObject | System.PSCustomObject[] | Array of access control objects (ACLs) to attach to the role. | @() |

.PARAMETER InheritedRoles
| Name | Type | Description | Default |
|------|------|-------------|---------|
| InheritedRoles | System.String[] | Roles whose permissions are inherited by this role. | @() |

.PARAMETER Force
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.Management.Automation.SwitchParameter | Overwrite existing role file if present. | $false |

.OUTPUTS
System.Object — Structured return object from Write-FunctionReturnValue. Returns
AccessRoleCreated on success (Data contains RoleName and AccessRole) or one of
several error return codes for validation or file errors.

.EXAMPLE
PS> New-ModuleAccessRole -RoleName 'admin' -Users @('alice','bob') -AccessControlObject $acl

Creates the access role named admin, assigns it to alice and bob, and
persists the role file under the AccessRoles config directory.

.NOTES
Role files are saved under the AccessRoles subfolder of Get-ModuleConfigDirectory.
Write-SecureFile and New-SecureItem are used to persist files securely.
Read-ModuleAccessControl is called after writing to reload the in-memory
access control definitions for the current session.
#>
function New-ModuleAccessRole()
{
    param (
        [string]$RoleName                      = '',
        [string[]]$Users                       = @(),
        [PSCustomObject[]]$AccessControlObject = @(),
        [string[]]$InheritedRoles              = @(),
        [switch]$Force                         = $false
    );

    # Ensure we specify a name for the role
    if ([string]::IsNullOrEmpty($RoleName)) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessRoleNoRoleNameProvided');
    };

    # Ensure we have at least one access control object
    if ($AccessControlObject.Count -eq 0) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessRoleNoAccessControlObjectsProvided');
    };

    # Ensure we have at least one user
    if ($Users.Count -eq 0) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessRoleNoUsersProvided' -Data @{ 'RoleName' = $RoleName });
    };

    # Create the access role object
    [PSCustomObject]$AccessRole = [PSCustomObject]@{
        'RoleName'            = $RoleName;
        'Users'               = ConvertTo-StringNormalizedArray -InputArray $Users;
        'AccessControlObject' = $AccessControlObject;
        'InheritedRoles'      = $InheritedRoles;
    };

    # Remove invalid filename characters from the role name for file saving
    [string]$SafeRoleName     = Remove-ModuleAmbitiousCharacters -InputString $RoleName -RemoveSpaces;
    [string]$AccessRoleFile   = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath ([string]::Format('AccessRoles\{0}.json', $SafeRoleName.ToLower()));

    # Test if the access role file already exists; return error if it does and Force is not specified
    if ((Test-Path $AccessRoleFile) -and -not $Force) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessRoleAlreadyExists' -Data @{ 'RoleName' = $SafeRoleName; 'File' = $AccessRoleFile });
    };

    # Ensure the AccessRoles directory exists by creating it if necessary
    if ($null -eq (New-SecureItem -Path $AccessRoleFile -ItemType File -Force)) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessRoleFileCreationFailed' -Data @{ 'File' = $AccessRoleFile });
    }

    # Write the access role to file
    $WriteStatus = Write-SecureFile -File $AccessRoleFile -Value $AccessRole;

    # Check if writing was successful
    if ($WriteStatus -ne (Get-GlobalRuntimeVariable).Public.ReturnCodes.WriteFileSuccess) {
        return $WriteStatus;
    };

    # Reload access control definitions to include the new role for the current session
    # This will not updated the current active thread's access role assignments
    Read-ModuleAccessControl;

    # Return success
    return (Write-FunctionReturnValue -ReturnValue 'AccessRoleCreated' -Data @{ 'RoleName' = $RoleName; 'AccessRole' = $AccessRole });
}

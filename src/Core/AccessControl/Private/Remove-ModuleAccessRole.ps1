<#
.SYNOPSIS
Remove a persisted module access role by name

.DESCRIPTION
Deletes the role JSON file from the module `AccessRoles` folder after
sanitizing the role name into a safe filename. Reloads module access control
definitions to reflect the deletion in the current runtime.

.PARAMETER RoleName
| Name | Type | Description | Default |
|------|------|-------------|---------|
| RoleName | System.String | Name of the role to remove. | '' |

.OUTPUTS
System.Object — Structured return object from Write-FunctionReturnValue when the
role name is empty; otherwise None.

.EXAMPLE
PS> Remove-ModuleAccessRole -RoleName 'admin'

Removes the persisted access role file for admin and reloads the in-memory
access control definitions.

.NOTES
Uses Remove-SecureItem to safely delete the role file and then calls
Read-ModuleAccessControl to refresh the in-memory role list for the current
session.
#>
function Remove-ModuleAccessRole()
{
    param (
        [string]$RoleName = ''
    );

    # Ensure we specify a name for the role
    if ([string]::IsNullOrEmpty($RoleName)) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessRoleNoRoleNameProvided');
    };

    # Remove invalid filename characters from the role name for file saving
    [string]$SafeRoleName   = Remove-ModuleAmbitiousCharacters -InputString $RoleName -RemoveSpaces;
    [string]$AccessRoleFile = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath ([string]::Format('AccessRoles\{0}.json', $SafeRoleName.ToLower()));

    # Remove the access role file
    Remove-SecureItem -Path $AccessRoleFile | Out-Null;
    # Reload access control definitions to include the new role for the current session
    # This will not updated the current active thread's access role assignments
    Read-ModuleAccessControl;
}

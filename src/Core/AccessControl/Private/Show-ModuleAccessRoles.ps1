<#
.SYNOPSIS
Output loaded module access roles to the logging system

.DESCRIPTION
Writes a formatted access role summary to the module logging system at the
`Output` level. The function reads the in-memory access control objects from
the global runtime variable and emits them as structured log data.

.OUTPUTS
None — Emits structured log output at the Output level as a side effect.

.EXAMPLE
PS> Show-ModuleAccessRoles

Writes the currently loaded access roles to the logging system at Output level.

.NOTES
This helper does not modify state; it only emits the current
(Get-GlobalRuntimeVariable).Protected.AccessControl via Write-LoggingEntry.
Read-ModuleAccessControl must have been called previously to populate the list.
#>
function Show-ModuleAccessRoles()
{
    Write-LoggingEntry -Message "`r`n=== $(Get-ModuleProjectName) Access Roles ===" -Level 'Output' -Data @{ 'AccessControl' = (Get-GlobalRuntimeVariable).Protected.AccessControl };
}

<#
.SYNOPSIS
Load and parse module access role files from the config directory

.DESCRIPTION
Scans the module `AccessRoles` configuration folder for JSON role files, reads
them using secure file helpers and parses them into PSCustomObjects which are
stored in the global runtime variable `Protected.AccessControl` for runtime use.
Parsing and IO errors are logged and reported via `Write-FunctionReturnValue`.

.OUTPUTS
System.Object — Structured return object from Write-FunctionReturnValue when the
AccessRoles folder is not found; otherwise None (populates
(Get-GlobalRuntimeVariable).Protected.AccessControl as a side effect).

.EXAMPLE
PS> Read-ModuleAccessControl

Scans the AccessRoles config folder, parses all role JSON files and stores the
resulting objects in the global runtime variable.

.NOTES
Role files are expected to be valid JSON and are read with Read-SecureFile.
Parsing errors for individual files do not abort the overall loading process;
they are logged and the loader continues with the remaining files.
#>
function Read-ModuleAccessControl()
{
    # Load all access control role files from the AccessRoles directory
    [string]$AccessControlFolder = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath 'AccessRoles';

    # Test if the path exists before trying to read files.
    if (-not (Test-Path -Path $AccessControlFolder)) {
        return Write-FunctionReturnValue -ReturnValue 'AccessRoleFolderNotFound' -Data @{ 'Folder' = $AccessControlFolder };
    }

    $AccessControlFiles                     = Get-SecureChildItem -Path $AccessControlFolder -Filter '*.json' -File;
    [PSCustomObject[]]$AccessControlObjects = @();

    # Read each access control file and parse its content
    foreach ($AcFile in $AccessControlFiles) {
        $FileContent = Read-SecureFile -File $AcFile.FullName;

        # Check if we could read the file
        if ($null -eq $FileContent) {
            Write-FunctionReturnValue -ReturnValue 'AccessRoleFileEmptyContent' -Data @{ 'File' = $AcFile.FullName } | Out-Null;
            continue;
        }

        try {
            # Parse the access control object
            $AcObject              = $FileContent | ConvertFrom-Json -ErrorAction Stop;
            $AccessControlObjects += $AcObject;

            # Log successful read as audit event
            Write-FunctionReturnValue -ReturnValue 'AccessRoleFileReadSuccess' -Data @{ 'File' = $AcFile.FullName } | Out-Null;
        } catch {
            # Log parsing error and continue
            Write-FunctionReturnValue -ReturnValue 'AccessRoleFileParseError' -Data @{ 'File' = $AcFile.FullName; 'Exception' = $_.Exception } | Out-Null;
            continue;
        }
    }

    # Store the loaded access control objects in the global environment
    (Get-GlobalRuntimeVariable).Protected.AccessControl = $AccessControlObjects;
}

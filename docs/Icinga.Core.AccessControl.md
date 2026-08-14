# Icinga.Core.AccessControl

*Auto-generated from `src/Core/AccessControl/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [New-IcingaAccessRole](#new-icingaaccessrole)
- [Remove-IcingaAccessRole](#remove-icingaaccessrole)
- [Show-IcingaAccessRoles](#show-icingaaccessroles)

## Private helpers

- [New-ModuleAccessRole](#new-moduleaccessrole)
- [Read-ModuleAccessControl](#read-moduleaccesscontrol)
- [Remove-ModuleAccessRole](#remove-moduleaccessrole)
- [Show-ModuleAccessRoles](#show-moduleaccessroles)

---

### New-IcingaAccessRole

*Public function*

**Synopsis:** Public wrapper to create an Icinga access role

#### Description

Exposes a stable public API that delegates to `New-ModuleAccessRole` to create
and persist an access role. Validates parameters are handled by the underlying
implementation; this wrapper simply forwards arguments and returns the same
standardized return values.

#### Parameters

**`$RoleName`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RoleName | System.String | Friendly name for the access role. | '' |

**`$Users`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Users | System.String[] | List of usernames (or identifiers) assigned to the role. | @() |

**`$AccessControlObject`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AccessControlObject | System.PSCustomObject[] | Array of access control objects (ACLs) to attach to the role. | @() |

**`$InheritedRoles`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| InheritedRoles | System.String[] | Roles whose permissions are inherited by this role. | @() |

**`$Force`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.Management.Automation.SwitchParameter | Overwrite existing role file if present. | $false |

#### Outputs

PSCustomObject — Forwarded return value from `New-ModuleAccessRole`.

#### Examples

```powershell
PS> New-IcingaAccessRole -RoleName 'admin' -Users @('alice') -AccessControlObject $acl

Creates the access role named admin for user alice using the provided access
control object and persists it via the private implementation.
```

#### Notes

This function is intentionally thin and exists to expose a public command
surface while the implementation and persistence logic remain in the module
private helper.

*Source: [src/Core/AccessControl/Public/New-IcingaAccessRole.ps1](../../src/Core/AccessControl/Public/New-IcingaAccessRole.ps1)*

---

### Remove-IcingaAccessRole

*Public function*

**Synopsis:** Public wrapper to remove a persisted Icinga access role

#### Description

Deletes a persisted access role by delegating to the private
`Remove-ModuleAccessRole` implementation. Returns the underlying function's
return value or status codes in case of error.

#### Parameters

**`$RoleName`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RoleName | System.String | Name of the role to remove. | '' |

#### Outputs

PSCustomObject — Forwarded return value from `Remove-ModuleAccessRole`.

#### Examples

```powershell
PS> Remove-IcingaAccessRole -RoleName 'admin'

Removes the persisted access role named admin and refreshes the in-memory
access control definitions via the private implementation.
```

#### Notes

This wrapper keeps the public module API distinct from the private
implementation which performs the file deletion and reloads access control data.

*Source: [src/Core/AccessControl/Public/Remove-IcingaAccessRole.ps1](../../src/Core/AccessControl/Public/Remove-IcingaAccessRole.ps1)*

---

### Show-IcingaAccessRoles

*Public function*

**Synopsis:** Show loaded Icinga access roles

#### Description

Public wrapper that emits the current in-memory access role definitions via
the module logging system by delegating to `Show-ModuleAccessRoles`.

#### Outputs

None — Emits the current access role list to the logging system at Output level.

#### Examples

```powershell
PS> Show-IcingaAccessRoles

Writes all currently loaded Icinga access roles to the logging output channel.
```

#### Notes

This command does not modify state; it is purely informational and relies on
Read-ModuleAccessControl having been run previously to populate the in-memory list.

*Source: [src/Core/AccessControl/Public/Show-IcingaAccessRoles.ps1](../../src/Core/AccessControl/Public/Show-IcingaAccessRoles.ps1)*

---

### New-ModuleAccessRole

*Private function*

**Synopsis:** Create and persist a module access role with allowed users and ACLs

#### Description

Constructs an access role object that contains the role name, users,
access control objects and inherited roles. Persists the role as a JSON
file under the module config `AccessRoles` directory using secure file helpers
and reloads the module access control definitions.

#### Parameters

**`$RoleName`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RoleName | System.String | Friendly name for the access role. | '' |

**`$Users`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Users | System.String[] | List of usernames (or identifiers) assigned to the role. | @() |

**`$AccessControlObject`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AccessControlObject | System.PSCustomObject[] | Array of access control objects (ACLs) to attach to the role. | @() |

**`$InheritedRoles`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| InheritedRoles | System.String[] | Roles whose permissions are inherited by this role. | @() |

**`$Force`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.Management.Automation.SwitchParameter | Overwrite existing role file if present. | $false |

#### Outputs

System.Object — Structured return object from Write-FunctionReturnValue. Returns
AccessRoleCreated on success (Data contains RoleName and AccessRole) or one of
several error return codes for validation or file errors.

#### Examples

```powershell
PS> New-ModuleAccessRole -RoleName 'admin' -Users @('alice','bob') -AccessControlObject $acl

Creates the access role named admin, assigns it to alice and bob, and
persists the role file under the AccessRoles config directory.
```

#### Notes

Role files are saved under the AccessRoles subfolder of Get-ModuleConfigDirectory.
Write-SecureFile and New-SecureItem are used to persist files securely.
Read-ModuleAccessControl is called after writing to reload the in-memory
access control definitions for the current session.

*Source: [src/Core/AccessControl/Private/New-ModuleAccessRole.ps1](../../src/Core/AccessControl/Private/New-ModuleAccessRole.ps1)*

---

### Read-ModuleAccessControl

*Private function*

**Synopsis:** Load and parse module access role files from the config directory

#### Description

Scans the module `AccessRoles` configuration folder for JSON role files, reads
them using secure file helpers and parses them into PSCustomObjects which are
stored in the global runtime variable `Protected.AccessControl` for runtime use.
Parsing and IO errors are logged and reported via `Write-FunctionReturnValue`.

#### Outputs

System.Object — Structured return object from Write-FunctionReturnValue when the
AccessRoles folder is not found; otherwise None (populates
(Get-GlobalRuntimeVariable).Protected.AccessControl as a side effect).

#### Examples

```powershell
PS> Read-ModuleAccessControl

Scans the AccessRoles config folder, parses all role JSON files and stores the
resulting objects in the global runtime variable.
```

#### Notes

Role files are expected to be valid JSON and are read with Read-SecureFile.
Parsing errors for individual files do not abort the overall loading process;
they are logged and the loader continues with the remaining files.

*Source: [src/Core/AccessControl/Private/Read-ModuleAccessControl.ps1](../../src/Core/AccessControl/Private/Read-ModuleAccessControl.ps1)*

---

### Remove-ModuleAccessRole

*Private function*

**Synopsis:** Remove a persisted module access role by name

#### Description

Deletes the role JSON file from the module `AccessRoles` folder after
sanitizing the role name into a safe filename. Reloads module access control
definitions to reflect the deletion in the current runtime.

#### Parameters

**`$RoleName`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RoleName | System.String | Name of the role to remove. | '' |

#### Outputs

System.Object — Structured return object from Write-FunctionReturnValue when the
role name is empty; otherwise None.

#### Examples

```powershell
PS> Remove-ModuleAccessRole -RoleName 'admin'

Removes the persisted access role file for admin and reloads the in-memory
access control definitions.
```

#### Notes

Uses Remove-SecureItem to safely delete the role file and then calls
Read-ModuleAccessControl to refresh the in-memory role list for the current
session.

*Source: [src/Core/AccessControl/Private/Remove-ModuleAccessRole.ps1](../../src/Core/AccessControl/Private/Remove-ModuleAccessRole.ps1)*

---

### Show-ModuleAccessRoles

*Private function*

**Synopsis:** Output loaded module access roles to the logging system

#### Description

Writes a formatted access role summary to the module logging system at the
`Output` level. The function reads the in-memory access control objects from
the global runtime variable and emits them as structured log data.

#### Outputs

None — Emits structured log output at the Output level as a side effect.

#### Examples

```powershell
PS> Show-ModuleAccessRoles

Writes the currently loaded access roles to the logging system at Output level.
```

#### Notes

This helper does not modify state; it only emits the current
(Get-GlobalRuntimeVariable).Protected.AccessControl via Write-LoggingEntry.
Read-ModuleAccessControl must have been called previously to populate the list.

*Source: [src/Core/AccessControl/Private/Show-ModuleAccessRoles.ps1](../../src/Core/AccessControl/Private/Show-ModuleAccessRoles.ps1)*



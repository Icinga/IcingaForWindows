<#
.SYNOPSIS
Public wrapper to create an Icinga access role

.DESCRIPTION
Exposes a stable public API that delegates to `New-ModuleAccessRole` to create
and persist an access role. Validates parameters are handled by the underlying
implementation; this wrapper simply forwards arguments and returns the same
standardized return values.

.PARAMETER RoleName
| Name     | Type          | Description                        | Default |
|----------|---------------|------------------------------------|---------|
| RoleName | System.String | Friendly name for the access role. | ''      |

.PARAMETER Users
| Name  | Type            | Description                                              | Default |
|-------|-----------------|----------------------------------------------------------|---------|
| Users | System.String[] | List of usernames (or identifiers) assigned to the role. | @()     |

.PARAMETER AccessControlObject
| Name                | Type                    | Description                                                   | Default |
|---------------------|-------------------------|---------------------------------------------------------------|---------|
| AccessControlObject | System.PSCustomObject[] | Array of access control objects (ACLs) to attach to the role. | @()     |

.PARAMETER InheritedRoles
| Name           | Type            | Description                                         | Default |
|----------------|-----------------|-----------------------------------------------------|---------|
| InheritedRoles | System.String[] | Roles whose permissions are inherited by this role. | @()     |

.PARAMETER Force
| Name  | Type                                         | Description                              | Default |
|-------|----------------------------------------------|------------------------------------------|---------|
| Force | System.Management.Automation.SwitchParameter | Overwrite existing role file if present. | $false  |

.OUTPUTS
PSCustomObject -- Forwarded return value from `New-ModuleAccessRole`.

.EXAMPLE
PS> New-IcingaAccessRole -RoleName 'admin' -Users @('alice') -AccessControlObject $acl

Creates the access role named admin for user alice using the provided access
control object and persists it via the private implementation.

.NOTES
This function is intentionally thin and exists to expose a public command
surface while the implementation and persistence logic remain in the module
private helper.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-IcingaAccessRole()
{
    param (
        [string]$RoleName                      = '',
        [string[]]$Users                       = @(),
        [PSCustomObject[]]$AccessControlObject = @(),
        [string[]]$InheritedRoles              = @(),
        [switch]$Force                         = $false
    );

    return (
        New-ModuleAccessRole -RoleName $RoleName -Users $Users -AccessControlObject $AccessControlObject -InheritedRoles $InheritedRoles -Force:$Force
    );
}

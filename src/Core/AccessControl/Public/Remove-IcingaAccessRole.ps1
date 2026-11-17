<#
.SYNOPSIS
Public wrapper to remove a persisted Icinga access role

.DESCRIPTION
Deletes a persisted access role by delegating to the private
`Remove-ModuleAccessRole` implementation. Returns the underlying function's
return value or status codes in case of error.

.PARAMETER RoleName
| Name     | Type          | Description                 | Default |
|----------|---------------|-----------------------------|---------|
| RoleName | System.String | Name of the role to remove. | ''      |

.OUTPUTS
PSCustomObject -- Forwarded return value from `Remove-ModuleAccessRole`.

.EXAMPLE
PS> Remove-IcingaAccessRole -RoleName 'admin'

Removes the persisted access role named admin and refreshes the in-memory
access control definitions via the private implementation.

.NOTES
This wrapper keeps the public module API distinct from the private
implementation which performs the file deletion and reloads access control data.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Remove-IcingaAccessRole()
{
    param (
        [string]$RoleName = ''
    );

    return (
        Remove-ModuleAccessRole -RoleName $RoleName
    );
}

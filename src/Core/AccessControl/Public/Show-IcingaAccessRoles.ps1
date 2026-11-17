<#
.SYNOPSIS
Show loaded Icinga access roles

.DESCRIPTION
Public wrapper that emits the current in-memory access role definitions via
the module logging system by delegating to `Show-ModuleAccessRoles`.

.OUTPUTS
None -- Emits the current access role list to the logging system at Output level.

.EXAMPLE
PS> Show-IcingaAccessRoles

Writes all currently loaded Icinga access roles to the logging output channel.

.NOTES
This command does not modify state; it is purely informational and relies on
Read-ModuleAccessControl having been run previously to populate the in-memory list.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Show-IcingaAccessRoles()
{
    Show-ModuleAccessRoles;
}

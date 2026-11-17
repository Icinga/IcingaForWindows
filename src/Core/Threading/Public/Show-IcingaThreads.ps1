<#
.SYNOPSIS
Display the Icinga thread hierarchy.

.DESCRIPTION
`Show-IcingaThreads` is a small public wrapper that renders the current
thread hierarchy for the Icinga application by delegating to `Show-Threads`.

.PARAMETER AsObject
| Name     | Type                   | Description                                       | Default |
|----------|------------------------|---------------------------------------------------|---------|
| AsObject | System.SwitchParameter | Return the tree as PSObjects instead of rendering | $false  |

.OUTPUTS
System.Array when `-AsObject` is set. Returns the root-level thread nodes
with a nested `Children` array representing the full hierarchy.

None otherwise. Writes a formatted thread tree to the logging system.

.EXAMPLE
PS> Show-IcingaThreads

.EXAMPLE
PS> $tree = Show-IcingaThreads -AsObject
PS> $tree | Select-Object Name, State, LastSeen

.NOTES
This wrapper calls `Show-Threads` and exists to provide a user-facing
command name for convenience.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Show-IcingaThreads()
{
    param (
        [switch]$AsObject = $false
    );

    Show-Threads -AsObject:$AsObject;
}

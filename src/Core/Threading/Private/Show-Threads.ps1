<#
.SYNOPSIS
Render or return the current thread hierarchy and status.

.DESCRIPTION
`Show-Threads` builds a complete thread tree via `Get-ThreadTree` and either
returns the structured tree objects or renders them as a formatted hierarchy
string and emits it to the logging system -- depending on the `-AsObject`
switch.

.PARAMETER AsObject
| Name     | Type                   | Description                                       | Default |
|----------|------------------------|---------------------------------------------------|---------|
| AsObject | System.SwitchParameter | Return the tree as PSObjects instead of rendering | $false  |

.OUTPUTS
System.Array when `-AsObject` is set. Returns the root-level thread nodes
produced by `Get-ThreadTree`, each with a `Children` array for the full
hierarchy.

None otherwise. Writes a formatted thread hierarchy string to the logging
queue.

.EXAMPLE
PS> Show-Threads

.EXAMPLE
PS> $tree = Show-Threads -AsObject
PS> $tree[0].Children

.NOTES
Relies on `Get-ThreadTree` to build the hierarchy and `Write-ThreadTree` to
render individual branches.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Show-Threads()
{
    param (
        [switch]$AsObject = $false
    );

    [array]$Tree         = Get-ThreadTree;
    [array]$ThreadIdList = (Get-GlobalRuntimeVariable).Public.Threading.Threads.PSobject.Properties.Name;

    if ($AsObject) {
        return $Tree;
    }

    $StringBuilder = New-Object System.Text.StringBuilder;

    # Add a blank line for better readability at the beginning
    $StringBuilder.AppendLine('') | Out-Null;
    $StringBuilder.AppendLine('=== THREAD HIERARCHY ===') | Out-Null;

    foreach ($node in $Tree) {
        Write-ThreadTree -Node $node -StringBuilder $StringBuilder;
        $StringBuilder.AppendLine('') | Out-Null;
    }

    $StringBuilder.AppendLine("Total Threads: $($ThreadIdList.Count)") | Out-Null;
    $StringBuilder.AppendLine("==================") | Out-Null;
    Write-LoggingEntry -Message $StringBuilder.ToString() -Level 'Output';
}

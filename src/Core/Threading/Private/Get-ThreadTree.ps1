<#
.SYNOPSIS
Build a hierarchical tree of all registered threads as PSObjects.

.DESCRIPTION
`Get-ThreadTree` collects every thread from the global thread registry and
assembles it into a list of root-level tree nodes. Each node holds the
resolved thread state, last-seen age, parameters and a `Children` array that
contains the child nodes in the same format -- forming a complete, self-contained
representation of the thread hierarchy without requiring further registry
lookups.

.OUTPUTS
System.Array. Sorted array of root-level thread nodes. Each node is a
PSObject with the following properties:

| Property   | Type             | Description                          |
|------------|------------------|--------------------------------------|
| Id         | System.String    | Unique thread GUID                   |
| Name       | System.String    | Display name of the thread           |
| Command    | System.String    | Entry-point command name             |
| State      | System.String    | Resolved state (RUNNING, IDLE, ...)  |
| LastSeen   | System.Double    | Seconds since last heartbeat         |
| KeepAlive  | System.Boolean   | Whether the thread is kept alive     |
| Parameters | System.Hashtable | Parameters passed to the command     |
| ParentId   | System.String    | Parent thread GUID or $null          |
| Children   | System.Array     | Ordered child nodes (same structure) |

.EXAMPLE
PS> $tree = Get-ThreadTree
PS> $tree[0].Children

.NOTES
The function resolves state and last-seen values at call time via
`Get-ThreadState` and `Get-ThreadLastSeen`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-ThreadTree()
{
    [array]$ThreadIdList = (Get-GlobalRuntimeVariable).Public.Threading.Threads.PSobject.Properties.Name;
    $NodeHash            = @{ };
    [array]$Roots        = @( );

    # First pass: create a flat node for every thread
    foreach ($threadId in $ThreadIdList) {
        $thread = (Get-GlobalRuntimeVariable).Public.Threading.Threads.$threadId;

        if ($NodeHash.ContainsKey($threadId)) {
            continue;
        }

        $node = New-Object PSObject;
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'Id'         -Value $threadId;
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'Name'       -Value $thread.Name;
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'Command'    -Value $thread.Command;
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'State'      -Value (Get-ThreadState -ThreadId $threadId);
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'LastSeen'   -Value (Get-ThreadLastSeen -ThreadId $threadId);
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'KeepAlive'  -Value ([bool]$thread.KeepAlive);
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'Parameters' -Value $thread.Parameters;
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'ParentId'   -Value $thread.ParentThread;
        Add-Member -InputObject $node -MemberType NoteProperty -Name 'Children'   -Value @();

        $NodeHash.Add($threadId, $node);
    }

    # Second pass: wire up parent/child relationships
    foreach ($threadId in $NodeHash.Keys) {
        $node     = $NodeHash[$threadId];
        $parentId = $node.ParentId;

        if (-not [string]::IsNullOrEmpty($parentId) -and $parentId -ne $threadId -and $NodeHash.ContainsKey($parentId)) {
            $NodeHash[$parentId].Children += $node;
        } else {
            $Roots += $node;
        }
    }

    return ($Roots | Sort-Object -Property Name);
}

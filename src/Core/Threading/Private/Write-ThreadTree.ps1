<#
.SYNOPSIS
Append a formatted tree entry for a thread node to a StringBuilder.

.DESCRIPTION
`Write-ThreadTree` renders a single thread line (with name, id, state, age,
and parameters) into a supplied `System.Text.StringBuilder` and recursively
renders child nodes from the pre-built tree to produce the full hierarchical
view. The node is a PSObject as returned by `Get-ThreadTree`.

.PARAMETER Node
| Name | Type          | Description                              | Default |
|------|---------------|------------------------------------------|---------|
| Node | PSObject      | Tree node as returned by `Get-ThreadTree` | $null   |

.PARAMETER StringBuilder
| Name          | Type                        | Description                     | Default |
|---------------|-----------------------------|---------------------------------|---------|
| StringBuilder | System.Text.StringBuilder   | The builder to append lines to  | $null   |

.PARAMETER Level
| Name  | Type          | Description                         | Default |
|-------|---------------|-------------------------------------|---------|
| Level | System.Int32  | Nesting level for indentation       | 0       |

.OUTPUTS
None. Appends formatted lines to the provided `StringBuilder` instance.

.EXAMPLE
$sb = [System.Text.StringBuilder]::new()
Get-ThreadTree | ForEach-Object { Write-ThreadTree -Node $_ -StringBuilder $sb }

.NOTES
This function does not return a value; it operates by side-effects on the
supplied builder. Child nodes are read directly from `$Node.Children` — no
additional registry lookups are performed.
#>
function Write-ThreadTree()
{
    param (
        [PSObject]$Node                           = $null,
        [System.Text.StringBuilder]$StringBuilder = $null,
        [int]$Level                               = 0
    );

    $indent = ' ' * ($Level * 4);
    $prefix = if ($Level -eq 0) { '' } else { '└── ' };

    # Show thread parameters if any present
    $params = '';
    if ($Node.Parameters -and $Node.Parameters.Count -gt 0) {
        $paramList = @();
        foreach ($param in $Node.Parameters.GetEnumerator()) {
            [string]$paramKey      = $param.Key;
            [string]$ArgumentColor = Get-LoggingConsoleColorForObjectType -Object $param.Value.GetType().Name;

            if ($paramKey.StartsWith('-')) {
                $paramKey = $paramKey.Substring(1);
            }

            $paramList += [string]::Format('[DarkGray]-{0}[/DarkGray] [{2}]{1}[/{2}]', $paramKey, $param.Value, $ArgumentColor);
        }
        $params = " | Params: @{ $($paramList -join '; ') }";
    }

    $ThreadStateColor = 'Gray';
    switch ($Node.State) {
        'RUNNING'    { $ThreadStateColor = 'Green';      break; }
        'ALIVE'      { $ThreadStateColor = 'Green';      break; }
        'PROCESSING' { $ThreadStateColor = 'Green';      break; }
        'WAITING'    { $ThreadStateColor = 'Green';      break; }
        'IDLE'       { $ThreadStateColor = 'Yellow';     break; }
        'BLOCKED'    { $ThreadStateColor = 'Magenta';    break; }
        'FROZEN'     { $ThreadStateColor = 'Blue';       break; }
        'ZOMBIE'     { $ThreadStateColor = 'DarkYellow'; break; }
        'DEAD'       { $ThreadStateColor = 'Red';        break; }
        'TERMINATED' { $ThreadStateColor = 'Red';        break; }
    }

    $keepAlive = '';
    if ($Node.KeepAlive) {
        $keepAlive = '[DarkGreen][KEEPALIVE][/DarkGreen]';
    }

    $StringBuilder.AppendLine(
        [string]::Format(
            '{0}{1} [Yellow]{2}[/Yellow] [{3}] [{5}]{4}[/{5}] [{6}s] {7}{8}',
            $indent,
            $prefix,
            $Node.Name,
            $Node.Id,
            $Node.State,
            $ThreadStateColor,
            $Node.LastSeen,
            $keepAlive,
            $params
        )
    ) | Out-Null;

    # Recursively render each child node
    foreach ($child in ($Node.Children | Sort-Object -Property Name)) {
        Write-ThreadTree -Node $child -Level ($Level + 1) -StringBuilder $StringBuilder;
    }
}

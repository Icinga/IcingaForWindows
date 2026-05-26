<#
.SYNOPSIS
Joins path segments into a single well-formed web path.

.DESCRIPTION
Combines a base path and additional child path segments, handling trailing and leading slashes,
URL query parameters and avoiding duplicate slashes. Preserves scheme endings like '://'.

.PARAMETER Path
| Name | Type          | Description                  | Default |
|------|---------------|------------------------------|---------|
| Path | System.String | Base path or URL to start from. | $null   |

.PARAMETER ChildPath
| Name      | Type         | Description                                                                          | Default |
|-----------|--------------|--------------------------------------------------------------------------------------|---------|
| ChildPath | System.Array | Child path segments to append. Segments may start with /, ? or & for query strings. | $null   |

.EXAMPLE
PS> Join-WebPath -Path 'http://example.com/' -ChildPath @('api', 'v1', 'items')

Returns 'http://example.com/api/v1/items'.

.EXAMPLE
PS> Join-WebPath -Path 'http://example.com' -ChildPath @('search', '?q=test', '&page=2')

Returns 'http://example.com/search?q=test&page=2'.

.OUTPUTS
System.String — The assembled web path or URL.

.NOTES
No external dependencies.
#>
function Join-WebPath()
{
    param (
        [string]$Path     = $null,
        [array]$ChildPath = $null
    );

    # Validate input
    if ([string]::IsNullOrEmpty($Path) -Or $null -eq $ChildPath -Or $ChildPath.Count -eq 0) {
        return $Path;
    }

    # Remove trailing slash from base path if present
    [int]$Length = $Path.Length;
    [int]$Slash  = $Path.LastIndexOf('/') + 1;

    # If the last character is a slash, remove it — but preserve scheme endings like '://'
    if ($Length -eq $Slash -and -not $Path.EndsWith('://')) {
        $Path = $Path.Substring(0, $Path.Length - 1);
    }

    # Start joining the paths
    [string]$JoinedChildPath = $Path;

    # Iterate through each child path segment
    foreach ($childElement in $ChildPath) {
        $child = [string]$childElement;

        # Skip empty segments
        if ([string]::IsNullOrEmpty($child)) {
            continue;
        }

        # Trim whitespace
        $child = $child.Trim();

        # If the child starts with a query ('?'), append it directly
        if ($child.StartsWith('?')) {
            $JoinedChildPath = [string]::Format('{0}{1}', $JoinedChildPath, $child);
            continue;
        }

        # If the joined path currently ends with '?', append the next segment directly
        if ($JoinedChildPath.EndsWith('?')) {
            $JoinedChildPath = [string]::Format('{0}{1}', $JoinedChildPath, $child);
            continue;
        }

        # If a query has already started in the joined path, append additional params with '&' unless one is provided
        if ($JoinedChildPath.Contains('?')) {
            if ($child.StartsWith('&') -or $child.StartsWith('?')) {
                $JoinedChildPath = [string]::Format('{0}{1}', $JoinedChildPath, $child);
            } elseif ($JoinedChildPath.EndsWith('=') -or $JoinedChildPath.EndsWith('?') -or $JoinedChildPath.EndsWith('&')) {
                # existing query key expects value, append directly
                $JoinedChildPath = [string]::Format('{0}{1}', $JoinedChildPath, $child);
            } else {
                $JoinedChildPath = [string]::Format('{0}&{1}', $JoinedChildPath, $child);
            }
            continue;
        }

        $leftEndsWithSlash    = $JoinedChildPath.EndsWith('/');
        $rightStartsWithSlash = $child.StartsWith('/');

        if ($leftEndsWithSlash -and $rightStartsWithSlash) {
            # avoid double slash
            $JoinedChildPath = [string]::Format('{0}{1}', $JoinedChildPath, $child.Substring(1));
        } elseif (-not $leftEndsWithSlash -and -not $rightStartsWithSlash) {
            # need single slash between
            $JoinedChildPath = [string]::Format('{0}/{1}', $JoinedChildPath, $child);
        } else {
            # exactly one slash already present (or child begins with '/', which is fine)
            $JoinedChildPath = [string]::Format('{0}{1}', $JoinedChildPath, $child);
        }
    }

    return $JoinedChildPath;
}

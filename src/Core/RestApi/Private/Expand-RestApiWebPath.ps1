<#
.SYNOPSIS
Normalize and split an HTTP path into segments.

.DESCRIPTION
Normalizes a web path by collapsing consecutive slashes, trimming trailing
slashes (except for root) and returning an object with the normalized path
and an array of path segments.

.PARAMETER WebPath
| Name    | Type          | Description                                            | Default |
|---------|---------------|--------------------------------------------------------|---------|
| WebPath | System.String | The HTTP path to normalize (e.g. '/api/v1/resource/'). |         |

.OUTPUTS
System.Collections.Hashtable -- parsed path object with keys `Segments`, `QueryParams`, `WebPath`,
`HasQuery`, `SegmentCount` and optional `Version`, `Space`, `Action`, `Resource`.

.EXAMPLE
PS> Expand-RestApiWebPath -Path '/api//v1/resource/'

.NOTES
This helper is used when routing incoming requests to configured RestApi
spaces and handlers.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Expand-RestApiWebPath()
{
    param (
        [string]$WebPath = $null
    );

    <#
        Returns a hashtable with the following structure:
        {
            'Segments'     = [string[]] Array of path segments (0-based index)
            'QueryParams'  = [hashtable] Key-value pairs of query parameters
            'WebPath'      = [string] Original web path
            'HasQuery'     = [bool] Indicates if query parameters are present
            'SegmentCount' = [int] Number of path segments
            'Version'      = [string] First path segment (if present)
            'Space'        = [string] Second path segment (if present)
            'Action'       = [string] Third path segment (if present)
            'Resource'     = [string] Fourth path segment (if present)
        }
    #>

    [hashtable]$ParsedPath = @{
        'Segments'     = @();
        'QueryParams'  = @{ };
        'WebPath'      = $WebPath;
        'HasQuery'     = $false;
        'SegmentCount' = 0;
    };

    try {
        # Split path into path part and query string
        [string[]]$PathParts = $WebPath -split '\?', 2;
        [string]$PathOnly    = $PathParts[0];
        [string]$QueryString = $null;

        if ($PathParts.Count -gt 1) {
            $QueryString = $PathParts[1];
        } else {
            $QueryString = '';
        };

        # Parse path segments (split by /, ignore empty segments and leading/trailing /)
        [string[]]$PathSegments = @();

        foreach ($seg in ($PathOnly -split '/')) {
            if ([string]::IsNullOrWhiteSpace($seg)) {
                continue;
            };

            $PathSegments += $seg.Trim();
        };

        # Store segments as array (0-based index access)
        $ParsedPath['Segments']     = $PathSegments;
        $ParsedPath['SegmentCount'] = $PathSegments.Count;

        if ($PathSegments.Count -gt 0) {
            $ParsedPath['Version'] = $PathSegments[0]
        };
        if ($PathSegments.Count -gt 1) {
            $ParsedPath['Space'] = $PathSegments[1]
        };
        if ($PathSegments.Count -gt 2) {
            $ParsedPath['Action'] = $PathSegments[2]
        };
        if ($PathSegments.Count -gt 3) {
            $ParsedPath['Resource'] = $PathSegments[3]
        };

        # Parse query parameters if present
        if (-not [string]::IsNullOrEmpty($QueryString)) {
            $ParsedPath['HasQuery'] = $true;
            Expand-RestApiQueryString -QueryString $QueryString -QueryParams ($ParsedPath['QueryParams']) | Out-Null;
        };

        return (Write-FunctionReturnValue -ReturnValue 'RestApiWebPathExpandSuccess' -Data @{ 'ParsedPath' = $ParsedPath } -OverrideReturn $ParsedPath);
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiWebPathExpandError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
}

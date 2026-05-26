<#
.SYNOPSIS
Parse a URL query string into a hashtable of parameters.

.DESCRIPTION
Parses a query string into key/value pairs while respecting quoted
values and percent-encoding. Multiple occurrences of the same key
are converted into arrays.

.PARAMETER QueryString
| Name | Type | Description | Default |
|------|------|-------------|---------|
| QueryString | System.String | Raw query string (may include leading '?'). | |

.PARAMETER QueryParams
| Name | Type | Description | Default |
|------|------|-------------|---------|
| QueryParams | System.Collections.Hashtable | Hashtable to populate with parsed parameters. | @{} |

.OUTPUTS
None — modifies the provided `QueryParams` hashtable in place.

.EXAMPLE
PS> Expand-RestApiQueryString -QueryString '?q=hello%20world&tags=one&tags=two' -QueryParams $params

.NOTES
This function is tolerant to quoted parameter values and retains array
semantics for repeated keys.
#>
function Expand-RestApiQueryString()
{
    param (
        [string]$QueryString    = $null,
        [hashtable]$QueryParams = @{ }
    );

    try {
        [string[]]$ParamPairs = @();

        # Split query parameters by &, but ensure we keep possible string values intact, like "Hello & welcome";
        if (-not [string]::IsNullOrEmpty($QueryString)) {
            # Remove leading ? if present;
            if ($QueryString.StartsWith('?')) {
                $QueryString = $QueryString.Substring(1);
            };

            [string]$CurrentString = '';
            [bool]$InQuotes        = $false;
            # Convert percent-encoded quotes (%22) to literal quotes for splitting purposes (case-insensitive)
            [string]$SplitInput    = [regex]::Replace($QueryString, '(?i)%22', '"');

            # Now loop through each character and split on & if not in quotes
            for ($i = 0; $i -lt $SplitInput.Length; $i++) {
                $ch = $SplitInput[$i];

                # We found a quote, toggle InQuotes state and add it, as required
                # for the Api parser to ensure we don't split , within quotes for example
                if ($ch -eq '"') {
                    $InQuotes       = -not $InQuotes;
                    $CurrentString += $ch;
                } elseif ($ch -eq '&' -and -not $InQuotes) {
                    # Split here if not in quotes
                    $ParamPairs   += $CurrentString;
                    $CurrentString = '';
                } else {
                    # Regular character, add to current string
                    $CurrentString += $ch;
                };
            };

            # If we have a remaining string, add it
            if ($CurrentString -ne '') {
                $ParamPairs += $CurrentString;
            }
        };

        foreach ($ParamPair in $ParamPairs) {
            if ([string]::IsNullOrWhiteSpace($ParamPair)) {
                continue;
            };

            # Split key=value
            [string[]]$KeyValue = $ParamPair -split '=', 2;

            if ($KeyValue.Count -eq 2) {
                [string]$Key   = [System.Web.HttpUtility]::UrlDecode($KeyValue[0]);
                [string]$Value = [System.Web.HttpUtility]::UrlDecode($KeyValue[1]);

                # Store as hashtable. If a key exists multiple times, we should assume its an array
                if ($QueryParams.ContainsKey($Key)) {
                    $CurrentValue = $QueryParams[$Key];
                    if ($CurrentValue -is [array]) {
                        # Append to existing array
                        $QueryParams[$Key] += $Value;
                    } else {
                        # Convert to array
                        $NewArray = @($CurrentValue, $Value);
                        $QueryParams[$Key] = $NewArray;
                    };
                } else {
                    $QueryParams[$Key] = $Value;
                };
            };
        };
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiQueryStringExpandError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
}

<#
.SYNOPSIS
Parse raw HTTP header text into structured header data.

.DESCRIPTION
Parses a raw HTTP request header string into a hashtable containing the
request method, path, HTTP version and a dictionary of headers. Returns
the parsed structure or logs an error and returns `$null` on parse failure.

.PARAMETER HeaderString
| Name | Type | Description | Default |
|------|------|-------------|---------|
| HeaderString | System.String | Raw HTTP header string including request line and headers. | |

.OUTPUTS
System.Collections.Hashtable — parsed header hashtable with `Method`, `Path`, `HttpVersion` and `Headers`.

.EXAMPLE
PS> Expand-RestApiHeader -HeaderString $rawHeader

.NOTES
Used by RestApi worker processing to interpret incoming HTTP requests.
#>
function Expand-RestApiHeader()
{
    param (
        [string]$HeaderString = $null
    );

    if ([string]::IsNullOrEmpty($HeaderString)) {
        return (Write-FunctionReturnValue -ReturnValue 'NoRestApiHeaderStringProvided' -OverrideReturn $null);
    };

    [hashtable]$ParsedHeader = @{ };
    [string[]]$HeaderLines   = $HeaderString -split "`r`n";
    [string]$RequestLine     = '';
    [string]$Method          = '';
    [string]$Path            = '';
    [string]$HttpVersion     = '';
    [string]$HeaderLine      = '';
    [string[]]$HeaderParts   = @();
    [string]$HeaderName      = '';
    [string]$HeaderValue     = '';

    try {
        # Parse request line (first line)
        $RequestLine = $HeaderLines[0];
        $HeaderParts = $RequestLine -split '\s+';

        if ($HeaderParts.Count -lt 3) {
            return (Write-FunctionReturnValue -ReturnValue 'InvalidRestApiHeaderRequestLine' -Data @{ 'RequestLine' = $RequestLine } -OverrideReturn $null);
        };

        $Method                      = $HeaderParts[0].ToUpper();
        $Path                        = $HeaderParts[1];
        $HttpVersion                 = $HeaderParts[2];
        $ParsedHeader['Method']      = $Method;
        $ParsedHeader['Path']        = $Path;
        $ParsedHeader['HttpVersion'] = $HttpVersion;
        $ParsedHeader['Headers']     = @{};

        # Parse remaining header lines
        for ([int]$i = 1; $i -lt $HeaderLines.Count; $i++) {
            $HeaderLine = $HeaderLines[$i].Trim();

            # Stop at empty line (end of headers)
            if ([string]::IsNullOrEmpty($HeaderLine)) {
                break;
            };

            # Split header by colon
            if ($HeaderLine -match '^([^:]+):\s*(.*)$') {
                $HeaderName  = $matches[1].Trim();
                $HeaderValue = $matches[2].Trim();

                # Store header (case-insensitive key, but preserve original case for reference)
                $ParsedHeader['Headers'][$HeaderName.ToLower()] = @{
                    'Name'  = $HeaderName;
                    'Value' = $HeaderValue;
                };
            };
        };

        return (Write-FunctionReturnValue -ReturnValue 'RestApiHeaderParseSuccess' -Data @{ 'ParsedHeader' = $ParsedHeader } -OverrideReturn $ParsedHeader);
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiHeaderParseError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
}

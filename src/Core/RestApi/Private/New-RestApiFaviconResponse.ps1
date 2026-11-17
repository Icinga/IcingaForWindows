<#
.SYNOPSIS
Build an HTTP response object for a favicon.ico request.

.DESCRIPTION
Constructs a simple response object containing the provided icon bytes
and correct `Content-Type` header for `image/x-icon`. Returns the response
structure or logs an error when no data is supplied.

.OUTPUTS
System.Collections.Hashtable -- response object with `Message` (byte[]) and
`Length` (int), ready to pass to `Send-TCPMessage`.

.EXAMPLE
PS> New-RestApiFaviconResponse

.NOTES
The favicon is read from `assets\restapi\favicon.png` under the module root
directory. The function selects the correct MIME type (`image/x-icon` or
`image/png`) based on the file extension found at that path.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-RestApiFaviconResponse()
{
    [string]$FaviconPath      = Join-Path -Path (Get-ModuleRootDirectory) -ChildPath 'assets\restapi\favicon.png';
    [hashtable]$MessageObject = @{ };
    [byte[]]$FaviconBytes     = @();
    [byte[]]$ResponseBytes    = @();
    [string]$ResponseString   = '';
    [string]$CurrentDateTime  = (Get-Date -Format 'ddd, dd MMM yyyy HH:mm:ss GMT');
    [int]$ContentLength       = 0;

    try {
        # Read favicon file into byte array
        if (-not (Test-Path $FaviconPath)) {
            return (Write-FunctionReturnValue -ReturnValue 'FaviconFileNotFound' -Data @{ 'FaviconPath' = $FaviconPath } -OverrideReturn $null);
        };

        [byte[]]$FaviconBytes = [System.IO.File]::ReadAllBytes($FaviconPath);
        $ContentLength        = $FaviconBytes.Count;

        # Build HTTP response with image/png MIME type (or image/x-icon for .ico)
        [string]$ContentType  = $null;

        if ($FaviconPath -match '\.ico$') {
            $ContentType = 'image/x-icon';
        } else {
            $ContentType = 'image/png';
        };

        $ResponseString           = "HTTP/1.1 200 OK`r`n";
        $ResponseString          += "Date: $CurrentDateTime`r`n";
        $ResponseString          += "Server: $(Get-ModuleProjectName)/2.0`r`n";
        $ResponseString          += "Content-Type: $ContentType`r`n";
        $ResponseString          += "Content-Length: $ContentLength`r`n";
        $ResponseString          += "Cache-Control: public, max-age=86400`r`n";  # Cache for 1 day
        $ResponseString          += "Connection: close`r`n";
        $ResponseString          += "`r`n";

        # Convert headers to bytes and append favicon bytes
        [byte[]]$HeaderBytes      = [System.Text.Encoding]::UTF8.GetBytes($ResponseString);
        [byte[]]$ResponseBytes    = New-Object byte[]($HeaderBytes.Count + $ContentLength);

        # Copy header bytes
        [Array]::Copy($HeaderBytes, 0, $ResponseBytes, 0, $HeaderBytes.Count);
        # Copy favicon bytes
        [Array]::Copy($FaviconBytes, 0, $ResponseBytes, $HeaderBytes.Count, $ContentLength);

        # Convert response to bytes
        $MessageObject['Message'] = $ResponseBytes;
        $MessageObject['Length']  = $ResponseBytes.Length

        return (Write-FunctionReturnValue -ReturnValue 'RestApiFaviconResponseBuildSuccess' -Data @{ 'ResponseString' = $ResponseString } -OverrideReturn $MessageObject);
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiFaviconResponseBuildError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
};

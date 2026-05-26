<#
.SYNOPSIS
Build a full HTTP response byte array from status and body.

.DESCRIPTION
Converts a status code, status message, content type and response body
into a single byte array suitable for sending over a TCP socket. When the
`Content-Type` is JSON the body is serialized with `ConvertTo-Json`.

.PARAMETER StatusCode
| Name | Type | Description | Default |
|------|------|-------------|---------|
| StatusCode | System.Int32 | HTTP status code to send (e.g. 200). | 200 |

.PARAMETER StatusMessage
| Name | Type | Description | Default |
|------|------|-------------|---------|
| StatusMessage | System.String | Short HTTP status message (e.g. 'OK'). | 'OK' |

.PARAMETER ContentType
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ContentType | System.String | MIME type for the response body. | 'application/json; charset=utf-8' |

.PARAMETER ResponseBody
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ResponseBody | Object | Body payload; may be byte[], string or object (serialized to JSON). | |

.OUTPUTS
System.Collections.Hashtable — response object with `Message` (byte[]) and `Length` (int) keys.

.EXAMPLE
PS> New-RestApiResponse -StatusCode 200 -ResponseBody @{ success = $true }

.NOTES
The returned `Message` is ready to be written to a TCP stream.
#>
function New-RestApiResponse()
{
    param (
        [int]$StatusCode       = 200,
        [string]$StatusMessage = 'OK',
        [string]$ContentType   = 'application/json; charset=utf-8',
        $ResponseBody          = $null
    );

    [hashtable]$MessageObject       = @{ };
    [string]$HeaderString           = '';
    [byte[]]$HeaderBytes            = @();
    [byte[]]$BodyBytes              = @();
    [int]$ContentLength             = 0;
    [string]$CurrentDateTime        = (Get-Date).ToUniversalTime().ToString('ddd, dd MMM yyyy HH:mm:ss GMT');
    [System.Text.Encoding]$Encoding = [System.Text.Encoding]::UTF8;

    try {
        if ($null -eq $ResponseBody) {
            $BodyBytes = @();
        } elseif ($ResponseBody -is [byte[]]) {
            $BodyBytes = $ResponseBody;
        } elseif ($ContentType -like 'application/json*') {
            $json = $ResponseBody | ConvertTo-Json -Depth 10 -Compress;
            $BodyBytes = $Encoding.GetBytes($json);
        } elseif ($ResponseBody -is [string]) {
            $BodyBytes = $Encoding.GetBytes($ResponseBody);
        } else {
            $BodyBytes = $Encoding.GetBytes(([string]$ResponseBody));
        }

        $ContentLength = $BodyBytes.Length;

        # Build response string
        $HeaderString  = "HTTP/1.1 $StatusCode $StatusMessage`r`n";
        $HeaderString += "Date: $CurrentDateTime`r`n";
        $HeaderString += "Server: $(Get-ModuleProjectName)/2.0`r`n";
        $HeaderString += "Content-Type: $ContentType`r`n";
        $HeaderString += "Content-Length: $ContentLength`r`n";
        $HeaderString += "Connection: close`r`n";
        $HeaderString += "`r`n";

        $HeaderBytes = $Encoding.GetBytes($HeaderString);

        [byte[]]$FullResponse = New-Object byte[] ($HeaderBytes.Length + $BodyBytes.Length);
        [System.Buffer]::BlockCopy($HeaderBytes, 0, $FullResponse, 0, $HeaderBytes.Length);

        if ($BodyBytes.Length -gt 0) {
            [System.Buffer]::BlockCopy($BodyBytes, 0, $FullResponse, $HeaderBytes.Length, $BodyBytes.Length);
        }

        # Convert response to bytes
        $MessageObject['Message'] = $FullResponse;
        $MessageObject['Length']  = $FullResponse.Length;

        return (Write-FunctionReturnValue -ReturnValue 'RestApiResponseBuildSuccess' -Data @{ 'HeaderString' = $HeaderString } -OverrideReturn $MessageObject);
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiResponseBuildError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
}

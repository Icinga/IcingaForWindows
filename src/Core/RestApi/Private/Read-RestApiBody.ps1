<#
.SYNOPSIS
Read the HTTP request body from the TCP stream based on Content-Length.

.DESCRIPTION
Reads the request body for an HTTP request already parsed into headers.
Honors `Content-Length`, enforces access control via
`Test-RestApiAccessControl` and returns a structured object with raw
bytes, string and parsed JSON (if applicable).

.PARAMETER ParsedHeaders
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ParsedHeaders | System.Collections.Hashtable | Parsed header object produced by `Expand-RestApiHeader`. | @{ } |

.PARAMETER PreReadBodyBytes
| Name | Type | Description | Default |
|------|------|-------------|---------|
| PreReadBodyBytes | byte[] | Any body bytes that were read along with the headers. | @() |

.OUTPUTS
Hashtable with keys `RawBytes`, `RawString`, `JsonObj`, `ContentLength`.

.EXAMPLE
PS> Read-RestApiBody -ParsedHeaders $parsed -PreReadBodyBytes $extraBytes

.NOTES
Closes the TCP connection and returns `$null` if access control denies
the request or a timeout occurs while reading.
#>
function Read-RestApiBody()
{
    param (
        [hashtable]$ParsedHeaders = @{ },
        [byte[]]$PreReadBodyBytes = @()
    );

    if ($null -eq $ParsedHeaders -or $ParsedHeaders.Count -eq 0) {
        return (Write-FunctionReturnValue -ReturnValue 'NoParsedHeadersProvided' -OverrideReturn $null);
    };

    $GlobalVariable                           = Get-GlobalRuntimeVariable;
    [System.IO.MemoryStream]$BodyBufferStream = [System.IO.MemoryStream]::new();
    [byte[]]$ReadBuffer                       = New-Object byte[] 65534;
    [int]$ContentLength                       = 0;
    [int]$BytesRead                           = 0;
    [int]$TotalBytesRead                      = 0;
    [bool]$ContentLengthExists                = $false;
    [System.Diagnostics.Stopwatch]$Stopwatch  = [System.Diagnostics.Stopwatch]::StartNew();

    try {
        # Check if Content-Length header exists
        if ($ParsedHeaders['Headers'].ContainsKey('content-length')) {
            [string]$ContentLengthValue = $ParsedHeaders['Headers']['content-length']['Value'];
            $ContentLengthExists        = [int]::TryParse($ContentLengthValue, [ref]$ContentLength);
        };

        # If no Content-Length, return empty body
        if (-not $ContentLengthExists -or $ContentLength -eq 0) {
            $BodyBufferStream.Dispose();

            return (
                Write-FunctionReturnValue -ReturnValue 'RestApiNoBodyToRead' -OverrideReturn @{
                    'RawBytes'      = @();
                    'RawString'     = '';
                    'JsonObj'       = $null;
                    'ContentLength' = 0;
                }
            );
        };

        $GlobalVariable.Private.RestApi.ContentLength = $ContentLength;
        $AclTest                                      = Test-RestApiAccessControl -TestContentLength;

        # Check access control for content length
        if ($AclTest -ne $GlobalVariable.Public.ReturnCodes.RestApiAccessControlPermissionGranted.Code -and $AclTest -ne $GlobalVariable.Public.ReturnCodes.RestApiAccessControlNotDefined.Code) {
            # Reset the content length again, as no longer needed
            $GlobalVariable.Private.RestApi.ContentLength = 0;
            # Enforce maximum content length for non-privileged users
            Send-TCPMessage -MsgObj (New-RestApiResponse -StatusCode 413 -StatusMessage 'Payload Too Large' -ResponseBody @{ 'error' = "Content length $ContentLength exceeds allowed limit for your user"} ) | Out-Null;
            # Close the connection
            Close-TCPConnection;
            $BodyBufferStream.Dispose();
            # Return null to indicate failure
            return $null;
        };

        # Initialize body buffer with pre-read bytes (from header reading phase)
        if ($PreReadBodyBytes.Count -gt 0) {
            $BodyBufferStream.Write($PreReadBodyBytes, 0, $PreReadBodyBytes.Count);
            $TotalBytesRead = $PreReadBodyBytes.Count;
        };

        # Read body data until Content-Length is reached
        while ($TotalBytesRead -lt $ContentLength -and $Stopwatch.Elapsed.TotalSeconds -lt $GlobalVariable.Private.TCP.SocketTimeoutInSeconds) {

            [int]$RemainingBytes = $ContentLength - $TotalBytesRead;
            [int]$ReadSize       = [Math]::Min($ReadBuffer.Length, $RemainingBytes);
            $BytesRead           = $GlobalVariable.Private.TCP.Stream.Read($ReadBuffer, 0, $ReadSize);

            if ($BytesRead -gt 0) {
                # Append read bytes to body buffer
                $BodyBufferStream.Write($ReadBuffer, 0, $BytesRead);
                $TotalBytesRead     += $BytesRead;
            } else {
                Start-Sleep -Milliseconds 10;
            };
        };

        if ($TotalBytesRead -ne $ContentLength) {
            return (Write-FunctionReturnValue -ReturnValue 'RestApiBodyReadTimeout' -Data @{ 'TotalBytesRead' = $TotalBytesRead } -OverrideReturn $null);
        };

        # Convert body to string (for JSON)
        [byte[]]$BodyBuffer  = $BodyBufferStream.ToArray();
        [string]$BodyString  = [System.Text.Encoding]::UTF8.GetString($BodyBuffer);
        [hashtable]$BodyData = @{
            'RawBytes'      = $BodyBuffer;
            'RawString'     = $BodyString;
            'JsonObj'       = $BodyString | ConvertFrom-Json -ErrorAction Stop;
            'ContentLength' = $TotalBytesRead;
        };

        $BodyBufferStream.Dispose();

        return (Write-FunctionReturnValue -ReturnValue 'RestApiBodyReadSuccess' -Data @{ 'BodyData' = $BodyData } -OverrideReturn $BodyData);
    } catch {
        if ($null -ne $BodyBufferStream) {
            $BodyBufferStream.Dispose();
        }

        return (Write-FunctionReturnValue -ReturnValue 'RestApiBodyReadError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
}

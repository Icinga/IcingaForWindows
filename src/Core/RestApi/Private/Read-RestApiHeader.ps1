<#
.SYNOPSIS
Read raw HTTP header bytes from the TCP stream and return parsed header data.

.DESCRIPTION
Reads from the TCP stream until the HTTP header terminator (`\r\n\r\n`) is
encountered or a timeout occurs. Returns a hashtable with raw header string,
raw bytes and any extra body bytes that were read alongside the headers.

.OUTPUTS
System.Collections.Hashtable — object with `RawString`, `RawBytes` and `ExtraBodyBytes`.

.EXAMPLE
PS> Read-RestApiHeader

.NOTES
This function reads directly from `(Get-GlobalRuntimeVariable).Private.TCP.Stream`.
#>
function Read-RestApiHeader()
{
    [byte[]]$HeaderBuffer                    = @();
    [byte[]]$ReadBuffer                      = New-Object byte[] 1024;
    [int]$BytesRead                          = 0;
    [string]$HeaderString                    = '';
    [bool]$HeaderComplete                    = $false;
    [System.Diagnostics.Stopwatch]$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew();
    $GlobalVariable                          = Get-GlobalRuntimeVariable;
    
    try {
        while (-not $HeaderComplete -and $Stopwatch.Elapsed.TotalSeconds -lt $GlobalVariable.Private.TCP.SocketTimeoutInSeconds) {
            $BytesRead = $GlobalVariable.Private.TCP.Stream.Read($ReadBuffer, 0, $ReadBuffer.Length);

            if ($BytesRead -gt 0) {
                # Append newly read bytes to header buffer
                [byte[]]$HeaderBuffer += $ReadBuffer[0..($BytesRead - 1)];
                $HeaderString = [System.Text.Encoding]::UTF8.GetString($HeaderBuffer);

                # Check for double newline (HTTP header terminator)
                if ($HeaderString -match "`r`n`r`n") {
                    # Find the position of double newline in bytes
                    [string]$DoubleNewline      = "`r`n`r`n";
                    # Search for header terminator pattern
                    $HeaderEndIndex             = $HeaderString.IndexOf($DoubleNewline);

                    if ($HeaderEndIndex -ge 0) {
                        # Calculate actual byte position accounting for potential multi-byte UTF8 characters
                        [string]$HeaderOnlyString = $HeaderString.Substring(0, $HeaderEndIndex + 4);
                        [byte[]]$HeaderOnlyBytes  = [System.Text.Encoding]::UTF8.GetBytes($HeaderOnlyString);

                        # Extract any extra body bytes that were read along with headers
                        if ($HeaderOnlyBytes.Count -lt $HeaderBuffer.Count) {
                            $ExtraBodyBytes = $HeaderBuffer[$HeaderOnlyBytes.Count..($HeaderBuffer.Count - 1)];
                        };

                        # Trim header buffer to only include headers
                        [byte[]]$HeaderBuffer = $HeaderOnlyBytes;
                        $HeaderString         = $HeaderOnlyString;
                        $HeaderComplete       = $true;
                    };
                };
            } else {
                Start-Sleep -Milliseconds 10;
            };
        };

        if (-not $HeaderComplete) {
            return (Write-FunctionReturnValue -ReturnValue 'RestApiHeaderReadTimeout' -Data @{ 'ElapsedSeconds' = $Stopwatch.Elapsed.TotalSeconds } -OverrideReturn $null);
        };

        [hashtable]$HeaderData = @{
            'RawString'      = $HeaderString;
            'RawBytes'       = $HeaderBuffer;
            'ExtraBodyBytes' = $ExtraBodyBytes;
        };

        # Return header buffer and string
        return (Write-FunctionReturnValue -ReturnValue 'RestApiHeaderReadSuccess' -Data @{ 'RawString' = $HeaderString; 'ExtraBodyBytes' = $ExtraBodyBytes.Count } -OverrideReturn $HeaderData);
    } catch {
        Write-LoggingEntry -Message $_.Exception.GetType() -Level 'Error';
        return (Write-FunctionReturnValue -ReturnValue 'RestApiHeaderReadError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
};

<#
.SYNOPSIS
Read raw HTTP header bytes from the TCP stream and return parsed header data.

.DESCRIPTION
Reads from the TCP stream until the HTTP header terminator (`\r\n\r\n`) is
encountered or a timeout occurs. Returns a hashtable with raw header string,
raw bytes and any extra body bytes that were read alongside the headers.

.OUTPUTS
Hashtable with `RawString`, `RawBytes`, and `ExtraBodyBytes`.

.EXAMPLE
PS> Read-RestApiHeader

.NOTES
This function reads directly from `(Get-GlobalRuntimeVariable).Private.TCP.Stream`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Read-RestApiHeader()
{
    [System.IO.MemoryStream]$HeaderBufferStream = [System.IO.MemoryStream]::new();
    [byte[]]$HeaderBuffer                       = @();
    [byte[]]$ReadBuffer                         = New-Object byte[] 1024;
    [int]$BytesRead                             = 0;
    [string]$HeaderString                       = '';
    [bool]$HeaderComplete                       = $false;
    [System.Diagnostics.Stopwatch]$Stopwatch    = [System.Diagnostics.Stopwatch]::StartNew();
    $GlobalVariable                             = Get-GlobalRuntimeVariable;

    try {
        while (-not $HeaderComplete -and $Stopwatch.Elapsed.TotalSeconds -lt $GlobalVariable.Private.TCP.SocketTimeoutInSeconds) {
            $BytesRead = $GlobalVariable.Private.TCP.Stream.Read($ReadBuffer, 0, $ReadBuffer.Length);

            if ($BytesRead -gt 0) {
                # Append newly read bytes to header buffer
                $HeaderBufferStream.Write($ReadBuffer, 0, $BytesRead);
                $HeaderString = [System.Text.Encoding]::UTF8.GetString($HeaderBufferStream.GetBuffer(), 0, [int]$HeaderBufferStream.Length);

                # Check for double newline (HTTP header terminator)
                if ($HeaderString -match "`r`n`r`n") {
                    # Find the position of double newline in bytes
                    [string]$DoubleNewline = "`r`n`r`n";
                    # Search for header terminator pattern
                    $HeaderEndIndex        = $HeaderString.IndexOf($DoubleNewline);

                    if ($HeaderEndIndex -ge 0) {
                        # Calculate actual byte position accounting for potential multi-byte UTF8 characters
                        [string]$HeaderOnlyString = $HeaderString.Substring(0, $HeaderEndIndex + 4);
                        [byte[]]$HeaderOnlyBytes  = [System.Text.Encoding]::UTF8.GetBytes($HeaderOnlyString);
                        [byte[]]$FullBuffer       = $HeaderBufferStream.ToArray();

                        # Extract any extra body bytes that were read along with headers
                        if ($HeaderOnlyBytes.Count -lt $FullBuffer.Count) {
                            $ExtraBodyBytes = $FullBuffer[$HeaderOnlyBytes.Count..($FullBuffer.Count - 1)];
                        };

                        # Trim header buffer to only include headers
                        $HeaderBufferStream.SetLength(0);
                        $HeaderBufferStream.Write($HeaderOnlyBytes, 0, $HeaderOnlyBytes.Count);
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
        $HeaderBufferStream.Dispose();
        return (Write-FunctionReturnValue -ReturnValue 'RestApiHeaderReadSuccess' -Data @{ 'RawString' = $HeaderString; 'ExtraBodyBytes' = $ExtraBodyBytes.Count } -OverrideReturn $HeaderData);
    } catch {
        if ($null -ne $HeaderBufferStream) {
            $HeaderBufferStream.Dispose();
        }

        Write-LoggingEntry -Message $_.Exception.GetType() -Level 'Error';
        return (Write-FunctionReturnValue -ReturnValue 'RestApiHeaderReadError' -Data @{ 'Exception' = $_.Exception } -OverrideReturn $null);
    };
};

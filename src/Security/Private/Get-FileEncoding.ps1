<#
.SYNOPSIS
Detect the most likely file encoding for a given file.

.DESCRIPTION
`Get-FileEncoding` examines the first bytes of a file to detect common byte-order
marks (BOM) and falls back to heuristics to distinguish ASCII and UTF8 when no BOM
is present. Returns a short encoding identifier string.

.PARAMETER Path
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Path to the file to inspect | '' |

.OUTPUTS
System.String — One of: UTF8-BOM, UTF8, Unicode, BigEndianUnicode, UTF7, UTF32, ASCII.

.EXAMPLE
Get-FileEncoding -Path (Join-Path (Get-ModuleConfigDirectory) 'settings.json')

.NOTES
- Returns a cmdlet-style error via `Write-FunctionReturnValue` when the file is not found.
#>
function Get-FileEncoding()
{
    param (
        [string]$Path = ''
    );

    if ([string]::IsNullOrEmpty($Path) -Or (Test-Path -Path $Path) -eq $FALSE) {
        return (Write-FunctionReturnValue -ReturnValue 'FileNotFound' -Data @{ 'Path' = $Path } -OverrideReturn $null);
    }

    $FileStream = [System.IO.File]::OpenRead($Path);
    $Bytes      = New-Object Byte[] 4;
    $FileStream.Read($Bytes, 0, 4) | Out-Null;
    $FileStream.Close();

    if ($Bytes[0] -eq 0xef -and $Bytes[1] -eq 0xbb -and $Bytes[2] -eq 0xbf) {
        return 'UTF8-BOM';
    } elseif ($Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe) {
        return 'Unicode';
    } elseif ($Bytes[0] -eq 0xfe -and $Bytes[1] -eq 0xff) {
        return 'BigEndianUnicode';
    } elseif ($Bytes[0] -eq 0x2b -and $Bytes[1] -eq 0x2f -and $Bytes[2] -eq 0x76) {
        return 'UTF7';
    } elseif ($Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe -and $Bytes[2] -eq 0x00 -and $Bytes[3] -eq 0x00) {
        return 'UTF32';
    } else {
        # Check if the file is ASCII or UTF8 without BOM
        $Content = Get-Content -Encoding String -Path $Path -ErrorAction SilentlyContinue;

        # In case the file is empty, we assume it's UTF8
        if ([string]::IsNullOrEmpty($Content)) {
            return 'UTF8';
        }

        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($content);

        # Check each byte to see if it's outside the ASCII range
        foreach ($byte in $Bytes) {
            if ($byte -gt 127) {
                return 'UTF8';
            }
        }
    }

    # This is the default encoding, as UTF8 without BOM could be valid ASCII
    return 'ASCII';
}

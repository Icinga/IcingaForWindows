<#
.SYNOPSIS
Write content to a file in approved locations with retry-on-lock semantics.

.DESCRIPTION
Writes content to disk after ensuring the target path exists and is within an
approved location. Handles several input types (hashtable, PSCustomObject,
arrays) by serializing them appropriately. Attempts to open the file for write
and retries on lock for a short period. Returns structured return values via
`Write-FunctionReturnValue`.

.PARAMETER File
| Name | Type | Description | Default |
|------|------|-------------|---------|
| File | System.String | Target file path to write. | $null |

.PARAMETER Value
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Value | System.Object | Content to write. Can be hashtable, PSCustomObject, array or string. | (none) |

.OUTPUTS
PSCustomObject — Function return value via Write-FunctionReturnValue.
WriteFileSuccess on success (Data contains Path and Content), WriteFileLockException
when the file cannot be opened within the retry window.

.EXAMPLE
PS> Write-SecureFile -File (Join-Path (Get-ModuleConfigDirectory) 'settings.json') -Value @{ key = 'value' }

.NOTES
Creates the file if it does not exist by delegating to `New-SecureItem`. Uses UTF8
without BOM when writing bytes. Caller receives the content in the return data.
#>
function Write-SecureFile()
{
    param (
        [string]$File = $null,
        $Value
    );

    # First check if we have a valid file path
    if ([string]::IsNullOrEmpty($File)) {
        return $null;
    }

    # Prepare the content to write by checking its type
    if ($null -eq $Value) {
        $Value = '';
    } elseif ($Value.GetType().Name.ToLower() -eq 'hashtable') {
        $Value = ConvertTo-Json -InputObject $Value -Depth 100;
    } elseif (([string]($Value.GetType().BaseType)).ToLower() -eq 'array') {
        $Value = $Value | Out-String;
    } elseif ($Value.GetType().Name.ToLower() -eq 'pscustomobject') {
        $Value = ConvertTo-Json -InputObject $Value -Depth 100;
    } else {
        $Value = $Value | Out-String;
    }

    # Check if the file exists, if not create it
    if ((Test-Path $File) -eq $FALSE) {
        if ($null -eq (New-SecureItem -ItemType File -Path $File)) {
            return $null;
        }
    }

    [int]$WaitTicks    = 0;
    [bool]$FileUpdated = $FALSE;

    # Lets wait 5 seconds before cancelling writing
    while ($WaitTicks -lt 50) {
        try {
            [System.IO.FileStream]$FileStream = [System.IO.File]::Open(
                $File,
                [System.IO.FileMode]::Truncate,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::Read
            );

            try {
                $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($Value);
                $FileStream.Write($ContentBytes, 0, $ContentBytes.Length);
            } finally {
                $FileStream.Dispose();
            }

            $FileUpdated = $TRUE;
            break;
        } catch {
            Write-LoggingEntry -Message 'File {0} is not writable. Trying again...' -Level 'Warning' -EventId 22 -Data @{
                'File'      = $File;
                'Value'     = $Value;
                'Exception' = $_.Exception;
            };
        }

        $WaitTicks += 1;
        Start-Sleep -Milliseconds 100;
    }

    if ($FileUpdated -eq $FALSE) {
        return (Write-FunctionReturnValue -ReturnValue 'WriteFileLockException' -Data @{ 'Path' = $File });
    }

    return (Write-FunctionReturnValue -ReturnValue 'WriteFileSuccess' -Data @{ 'Path' = $File; 'Content' = $Value });
}

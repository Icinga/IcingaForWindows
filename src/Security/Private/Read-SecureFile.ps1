<#
.SYNOPSIS
Read a file from approved locations with retry handling for locks.

.DESCRIPTION
Reads a file from disk only if the path is approved via `Test-SecureApprovedPath`.
Implements a retry loop to handle temporary file locks and detects UTF8 BOM when
assembling the file content. Returns standardized return values via
`Write-FunctionReturnValue`.

.PARAMETER File
| Name | Type | Description | Default |
|------|------|-------------|---------|
| File | System.String | Path to the file to read. | $null |

.OUTPUTS
System.String — File content on success (returned as raw override via Write-FunctionReturnValue).
ObjectReadSucceeded on success (Data contains Path and Content).
FileNotFound, AccessViolation or FileLockException on errors.

.EXAMPLE
PS> Read-SecureFile -File (Join-Path (Get-ModuleConfigDirectory) 'settings.json')

.NOTES
This helper attempts to open the file for up to ~5 seconds before failing with
`FileLockException`. Use for reading module configuration files safely.
#>
function Read-SecureFile()
{
    param (
        [string]$File = $null
    );

    if ([string]::IsNullOrEmpty($File) -Or (Test-Path $File) -eq $FALSE) {
        return (Write-FunctionReturnValue -ReturnValue 'FileNotFound' -Data @{ 'Path' = $File } -OverrideReturn $null);
    }

    # Define approved paths (root and config directories)
    [array]$ApprovedPathList = @(
        (Get-ModuleRootDirectory),
        (Get-ModuleConfigDirectory)
    );

    if ((Test-SecureApprovedPath -Path $File -ApprovedPath $ApprovedPathList) -ne (Get-GlobalRuntimeVariable).Public.ReturnCodes.AccessGranted.Code) {
        return (Write-FunctionReturnValue -ReturnValue 'AccessViolation' -Data @{ 'Path' = $File } -OverrideReturn $null);
    }

    [int]$WaitTicks   = 0;
    [bool]$ConfigRead = $FALSE;

    # Lets wait 5 seconds before cancelling reading
    while ($WaitTicks -lt (($WaitTicks + 1) * 50)) {
        try {
            [System.IO.FileStream]$FileStream = [System.IO.File]::Open(
                $File,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            );

            try {
                $ReadArray     = New-Object Byte[] $FileStream.Length;
                [bool]$UTF8BOM = $FALSE;

                if ((Get-FileEncoding -Path $File) -eq 'UTF8-BOM') {
                    $UTF8BOM = $TRUE;
                }

                $UTF8Encoding  = New-Object System.Text.UTF8Encoding $UTF8BOM;
                $FileContent   = '';

                while ($FileStream.Read($ReadArray, 0 , $ReadArray.Length)) {
                    $FileContent = [System.String]::Concat($FileContent, $UTF8Encoding.GetString($ReadArray));
                }
            } finally {
                $FileStream.Dispose();
            }

            $ConfigRead = $TRUE;
            break;
        } catch {
            Write-LoggingEntry -Message 'File is not accessible. Trying again...' -Level 'Warning' -EventId 23 -Data @{
                'File'      = $File;
                'Exception' = $_.Exception;
            };
        }

        $WaitTicks += 1;
        Start-Sleep -Milliseconds 100;
    }

    if ($ConfigRead -eq $FALSE) {
        return (Write-FunctionReturnValue -ReturnValue 'FileLockException' -Data @{ 'Path' = $File } -OverrideReturn $null);
    }

    return (Write-FunctionReturnValue -ReturnValue 'ObjectReadSucceeded' -Data @{ 'Path' = $File; 'Content' = $FileContent } -OverrideReturn $FileContent);
}

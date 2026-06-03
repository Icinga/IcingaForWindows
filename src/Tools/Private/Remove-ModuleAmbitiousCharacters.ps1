<#
.SYNOPSIS
Remove characters that are invalid in Windows filenames.

.DESCRIPTION
Cleans an input string by removing characters that are not allowed in
Windows filenames. Optionally removes whitespace as well. Useful when
deriving filenames from user-supplied role names or identifiers.

.PARAMETER InputString
| Name | Type | Description | Default |
|------|------|-------------|---------|
| InputString | System.String | Input string to sanitize. | $null |

.PARAMETER RemoveSpaces
| Name | Type | Description | Default |
|------|------|-------------|---------|
| RemoveSpaces | System.Management.Automation.SwitchParameter | Remove all whitespace characters when set. | $false |

.OUTPUTS
System.String — The sanitized string suitable for use as a filename.

.EXAMPLE
PS> Remove-ModuleAmbitiousCharacters -InputString 'Admin Role #1' -RemoveSpaces

.NOTES
Only removes a restricted set of characters; callers may perform additional
normalization (lowercasing, trimming) if needed.
#>
function Remove-ModuleAmbitiousCharacters()
{
    param (
        [string]$InputString  = $null,
        [switch]$RemoveSpaces = $false
    );

    if ([string]::IsNullOrEmpty($InputString)) {
        return $InputString;
    }

    # Remove characters that are not allowed in filenames on Windows
    [string]$SafeName = $InputString -replace '[<>:"/\\|?*]', '';

    if ($RemoveSpaces) {
        $SafeName = $SafeName -replace '\s+', '';
    }

    return $SafeName;
}

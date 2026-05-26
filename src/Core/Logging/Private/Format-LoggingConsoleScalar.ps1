<#
.SYNOPSIS
Format a scalar value with color for console logging.

.DESCRIPTION
`Format-LoggingConsoleScalar` returns a one-line colored string for scalar values
using `Get-LoggingConsoleColorForValue` to determine an appropriate color.

.PARAMETER Object
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Object | System.Object | The value to format | |

.PARAMETER Indent
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Indent | System.String | Optional indentation prefix | '' |

.OUTPUTS
System.String — A formatted single-line representation of the scalar value.

.EXAMPLE
PS> Format-LoggingConsoleScalar -Object 123 -Indent '  '

.NOTES
Used internally by `Format-LoggingConsoleObjects` for fallback scalar formatting.
#>
function Format-LoggingConsoleScalar()
{
    param (
        $Object         = $null,
        [string]$Indent = ''
    );

    # Return the formatted object with proper indentation
    return [string]::Format(
        '{0} [{1}]{2}[/{1}]',
        $Indent,
        (Get-LoggingConsoleColorForValue -Value $Object),
        $Object
    )
}

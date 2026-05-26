<#
.SYNOPSIS
Decide if a message at a given level should be emitted by the logger.

.DESCRIPTION
`Test-LoggingWriteLog` compares the requested message level against the
currently configured global logging level and returns `$true` when the message
should be written.

.PARAMETER Level
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Level | System.String | The severity of the message to evaluate | 'Info' |

.OUTPUTS
System.Boolean — `$true` if the message should be written given the current logging level.

.EXAMPLE
PS> Test-LoggingWriteLog -Level 'Debug'

.NOTES
Logging level hierarchy is implemented by explicit membership checks per level.
#>
function Test-LoggingWriteLog()
{
    param (
        [ValidateSet('Debug', 'Output', 'Audit', 'Info', 'Success', 'Warning', 'Error', 'Fatal')]
        [string]$Level = 'Info'
    );

    switch ((Get-GlobalRuntimeVariable).Public.Logging.Level) {
        'Debug' {
            # Log everything
            break;
        };
        'Info' {
            if ($Level -in @('Debug')) {
                return $false;
            }
            break;
        };
        'Success' {
            if ($Level -in @('Debug')) {
                return $false;
            }
            break;
        };
        'Audit' {
            if ($Level -in @('Debug', 'Info')) {
                return $false;
            }
            break;
        };
        'Warning' {
            if ($Level -in @('Debug', 'Info', 'Success', 'Audit')) {
                return $false;
            }
            break;
        };
        'Error' {
            if ($Level -in @('Debug', 'Info', 'Success', 'Audit', 'Warning')) {
                return $false;
            }
            break;
        };
        'Fatal' {
            if ($Level -in @('Debug', 'Info', 'Success', 'Audit', 'Warning', 'Error')) {
                return $false;
            }
            break;
        };
        default {
            # Unknown logging level, do not log anything.
            return $false;
        };
    }

    return $true;
}
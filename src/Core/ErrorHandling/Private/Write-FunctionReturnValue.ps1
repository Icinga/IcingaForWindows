<#
.SYNOPSIS
Emit a standardized numeric return value and optional log entry.

.DESCRIPTION
Looks up the semantic return identifier in the internal return-code table
and emits the mapped numeric code. If the entry's severity is enabled in
the current logging configuration, a structured log entry is enqueued.
Supports returning an override value instead of the mapped code.

.PARAMETER ReturnValue
| Name | Type | Description | Default |
|------|------|-------------|---------|
| ReturnValue | System.String | Semantic key of the return-code entry to emit (for example: 'TlsHandshakeSuccessful'). | |

.PARAMETER Data
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Data | System.Collections.Hashtable | Additional contextual data to attach to the log entry. | @{} |

.PARAMETER OverrideReturn
| Name | Type | Description | Default |
|------|------|-------------|---------|
| OverrideReturn | System.Object | If provided (not 'Core::IgnoreOverride'), this value is returned instead of the mapped numeric code. Booleans are returned via explicit cast to preserve type. | Core::IgnoreOverride |

.PARAMETER AutomationRun
| Name | Type | Description | Default |
|------|------|-------------|---------|
| AutomationRun | System.Management.Automation.SwitchParameter | When set, returns @{ ExitCode; Output } instead of the numeric code. ExitCode is 0 for Info/Audit/Debug severities, 2 for all others. | $false |

.OUTPUTS
System.Int32 — Numeric code from the return-code table when neither -OverrideReturn nor -AutomationRun is active.
System.Collections.Hashtable — @{ ExitCode = System.Int32; Output = System.String } when -AutomationRun is set.
System.Object — The -OverrideReturn value as-is when provided, taking precedence over both the numeric code and -AutomationRun.

.EXAMPLE
PS> Write-FunctionReturnValue -ReturnValue 'TlsHandshakeSuccessful'

.NOTES
Calls Set-InternalExitCodes to ensure the return-code table is populated before the first lookup.
Enqueues a log entry via Write-LoggingEntry only when the entry's severity is enabled in the
current logging configuration and is not 'Audit'. Must be called from the main thread or via
Get-GlobalRuntimeVariable in daemon context.
#>
function Write-FunctionReturnValue()
{
    param (
        [string]$ReturnValue   = $null,
        [hashtable]$Data       = @{ },
        $OverrideReturn        = 'Core::IgnoreOverride',
        [switch]$AutomationRun = $false
    );

    # Ensure return codes are loaded once
    Set-InternalExitCodes;

    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Lookup return code entry
    if ($GlobalVariable.Public.ReturnCodes.ContainsKey($ReturnValue)) {
        $codeEntry = $GlobalVariable.Public.ReturnCodes[$ReturnValue];

        # Assign a unique message ID for tracking
        $Data['LoggingMessageId'] = $GlobalVariable.Private.Logging.CurrentLoggingId.ToString();

        # Only queue the log entry if the severity level is enabled in the current logging configuration
        # TODO: Fix Audit log to make it configurable for printing only access violations or try some different handling
        if ($codeEntry.Severity -ne 'Audit') {
            # Enqueue log entry via the central function
            Write-LoggingEntry -Message $codeEntry.Message -Level $codeEntry.Severity -EventId $codeEntry.Code -Area $codeEntry.Area -Data $Data;
        }

        # Fixes OverrideReturn on bool states, as PowerShell would compare "string" to "bool" and therefore the result would be fales
        # string -eq $true as example would return false, but we actually wanted to return true in this case, as the override is set to true
        if ($OverrideReturn -is [bool]) {
            return [bool]$OverrideReturn;
        }

        # If we used an override, return that safely using comma operator to prevent unrolling
        if (-not ($OverrideReturn -is [string] -and $OverrideReturn -eq 'Core::IgnoreOverride')) {
            return ,$OverrideReturn;
        }
    
        # If we use automation like Ansible, we need to report properly mapped exit status
        # codes for success and failure
        if ($AutomationRun) {
            [int]$AutomationExitCode = 0;
            switch ($codeEntry.Severity) {
                'Info' {
                    # Return success on info
                    break;
                };
                'Audit' {
                    # Return success on audit
                    break;
                };
                'Debug' {
                    # Return success on debug
                    break;
                };
                # TODO: Should Warning be Ok or Failure?
                default {
                    # Return failure on anything else
                    $AutomationExitCode = 2;
                };
            }

            return @{
                'ExitCode' = $AutomationExitCode;
                'Output'   = $codeEntry.Message;
            };
        }

        # Return mapped code
        return $codeEntry.Code;
    }

    # Return error for undefined return value
    Write-LoggingEntry -Message 'Undefined error message return value {0}' -Level 'Error' -Data @{
        'ReturnValue' = $ReturnValue;
    };

    # If we used an override, return that safely using comma operator to prevent unrolling
    if (-not ($OverrideReturn -is [string] -and $OverrideReturn -eq 'Core::IgnoreOverride')) {
        return ,$OverrideReturn;
    }

    # Fallback return code for undefined return values
    return 8000;
}

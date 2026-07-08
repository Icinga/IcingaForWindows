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
| OverrideReturn | System.Object | If provided (not 'Core::IgnoreOverride'), this value is returned instead of the mapped numeric code. Can be a boolean or numeric value. | Core::IgnoreOverride |

.OUTPUTS
System.Int32
Numeric return code mapped from the semantic `ReturnValue`, or the provided `OverrideReturn`.

.EXAMPLE
PS> Write-FunctionReturnValue -ReturnValue 'TlsHandshakeSuccessful'

.NOTES
This helper depends on `Set-InternalExitCodes` and `Write-LoggingEntry`.
#>
function Write-FunctionReturnValue()
{
    param (
        [string]$ReturnValue = $null,
        [hashtable]$Data     = @{ },
        $OverrideReturn      = 'Core::IgnoreOverride'
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
        if ((Test-LoggingWriteLog -Level $codeEntry.Severity) -and $codeEntry.Severity -ne 'Audit') {
            # Enqueue log entry
            $GlobalVariable.Public.Logging.Queue.Add(
                [PSCustomObject]@{
                    'Message'   = $codeEntry.Message;
                    'Level'     = $codeEntry.Severity;
                    'EventId'   = $codeEntry.Code;
                    'Area'      = $codeEntry.Area;
                    'Data'      = $Data;
                    'TimeStamp' = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss:ffff');
                }
            );
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

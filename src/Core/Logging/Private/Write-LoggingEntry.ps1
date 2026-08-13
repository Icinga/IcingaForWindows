<#
.SYNOPSIS
Queue a structured log entry for asynchronous processing.

.DESCRIPTION
`Write-LoggingEntry` constructs a logging object (message, level, event id, area,
and additional data) and enqueues it into the global logging queue for processing
by the logging daemon. It also assigns a per-message logging id for correlation.

.PARAMETER Message
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Message | System.String | The log message text | |

.PARAMETER Level
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Level | System.String | Severity (Debug,Output,Audit,Info,Success,Warning,Error,Fatal) | 'Info' |

.PARAMETER EventId
| Name | Type | Description | Default |
|------|------|-------------|---------|
| EventId | System.Int32 | Numeric event identifier for the log entry | 15 |

.PARAMETER Data
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Data | System.Hashtable | Additional structured data to include with the log entry | @{} |

.OUTPUTS
System.Management.Automation.PSCustomObject — The enqueued log object when called from a background daemon with Level 'Output'; None otherwise.

.EXAMPLE
PS> Write-LoggingEntry -Message 'Started processing' -Level 'Info' -EventId 100

.NOTES
This function is intentionally non-blocking: it enqueues messages for a background
consumer. It uses `(Get-GlobalRuntimeVariable).Private.Logging.CurrentLoggingId` to tag messages.
#>
function Write-LoggingEntry()
{
    param (
        [string]$Message = $null,
        [ValidateSet('Debug', 'Output', 'Audit', 'Info', 'Success', 'Warning', 'Error', 'Fatal')]
        [string]$Level   = 'Info',
        [int]$EventId    = 15,
        [hashtable]$Data = @{ }
    );

    # TODO: Fix Audit log to make it configurable for printing only access violations or try some different handling
    if ($Level -eq 'Audit') {
        $Data = $null;
        return;
    }

    if ([string]::IsNullOrEmpty($Message)) {
        Write-LoggingEntry 'Failed to write log message: Message is null or empty' -Level 'Error';
        $Data = $null;
        return;
    }

    if (-not (Test-LoggingWriteLog -Level $Level)) {
        $Data = $null;
        return;
    }

    # Assign a unique message ID for tracking
    $Data['LoggingMessageId'] = (Get-GlobalRuntimeVariable).Private.Logging.CurrentLoggingId.ToString();

    # If we reached this point, we should log the message
    # Move everything to the logging queue for processing, to not block the current thread
    # As the message queue will be processed by a dedicated logging thread and we simply add
    # new events, the order of log messages should be preserved
    # All we need to do is add a timestamp here for later processing
    [PSCustomObject]$LogMessage = @{
        'Message'   = $Message;
        'Level'     = $Level;
        'EventId'   = $EventId;
        'Area'      = $codeEntry.Area;
        'Data'      = $Data;
        'TimeStamp' = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss:ffff');
    };

    (Get-GlobalRuntimeVariable).Public.Logging.Queue.Add($LogMessage) | Out-Null;

    # In case we are logging an Output level message, return the formatted object
    # in case we are set as internal daemon in our protected space
    if ($Level -eq 'Output' -and (Get-GlobalRuntimeVariable).Protected.IsBackgroundDaemon) {
        return $LogMessage;
    }
}

<#
.SYNOPSIS
Background logging daemon that consumes the logging queue.

.DESCRIPTION
`Start-LoggingDaemon` runs in a loop while `Test-ThreadRunning` is true
and processes objects from the global logging queue. It formats messages,
writes Windows EventLog entries and prints colorized output to the console.

.OUTPUTS
None — Operates for side effects (writes logs and event entries).

.EXAMPLE
PS> Start-LoggingDaemon

.NOTES
This function must be executed inside a dedicated background runspace. It blocks
indefinitely by calling `BlockingCollection.Take()` on the logging queue, so it
must never run on the main thread. All access to shared state goes through
`Get-GlobalRuntimeVariable` because the runspace receives only a snapshot of
`$Global:Icinga` at startup. The daemon exits cleanly when `Test-ThreadRunning`
returns `$false`.
#>
function Start-LoggingDaemon()
{
    $ModuleName = Get-ModuleProjectName;

    while (Test-ThreadRunning) {
        # Definition
        <#
            [PSCustomObject]@{
                'Message'   = $Message;
                'Level'     = $Level;
                'EventId'   = $EventId;
                'Data'      = $Data;
                'TimeStamp' = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss:ffff');
            }
        #>
        $LogObject          =  (Get-GlobalRuntimeVariable).Public.Logging.Queue.Take();
        [string]$DataDump   = '';
        [string]$LogMessage = '';
        [string]$LogColor   = (Get-GlobalRuntimeVariable).Public.Config.Colors.$($LogObject.Level);

        Set-ThreadProcessing;

        # Check if we should log this message based on the current logging level
        # In case we have a huge backlog of log messages, we want to skip unnecessary ones
        if (-not (Test-LoggingWriteLog -Level $LogObject.Level)) {
            continue;
        }

        if ($null -ne $LogObject.Data) {
            $DataDump = Format-LoggingConsoleObjects -Object $LogObject.Data -Level 0;
        }

        if ($LogObject.Level -ne 'Output') {
            $LogMessage = [string]::Format(
                '{0} [{4}][{1}][/{4}] {2}{3}',
                $LogObject.TimeStamp, $LogObject.Level, $LogObject.Message, $DataDump, $LogColor
            );
        } else {
            $LogMessage = [string]::Format('{0}{1}', $LogObject.Message, $DataDump);
        }

        [string]$LogArea   = $LogObject.Area;
        [string]$EntryType = $LogObject.Level;

        # Set a default in case no area is set
        if ([string]::IsNullOrEmpty($LogArea)) {
            $LogArea = 'Logging';
        }

        # Map our log levels to EventLog entry types
        $EntryType               = Get-LoggingEventLogSeverity -Severity $LogObject.Level;
        [string]$EventLogMessage = Format-LoggingConsoleMessage -Message $LogMessage -GetMsgObj;

        $EventLogMessage += "`r`n" + '============================' + "`r`n" + $LogMessage;

        Write-EventLog `
            -LogName $ModuleName `
            -Source ([string]::Format('{0}::{1}', $ModuleName, $LogArea)) `
            -EntryType $EntryType `
            -EventId $LogObject.EventId `
            -Message $EventLogMessage;

        Format-LoggingConsoleMessage -Message $LogMessage;

        $DataDump   = $null;
        $LogObject  = $null;
        $LogMessage = $null;
    }
}

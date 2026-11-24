<#
.SYNOPSIS
Background logging daemon that consumes the logging queue

.DESCRIPTION
`Start-LoggingDaemon` runs in a loop while `Test-ThreadRunning` is true
and processes objects from the global logging queue. It formats messages,
writes Windows Event Log entries on Windows hosts, and prints colorized output
to the console.

.OUTPUTS
None -- Operates for side effects (writes logs and event entries).

.EXAMPLE
PS> Start-LoggingDaemon

Starts the blocking logging queue consumer loop inside a background runspace.

.NOTES
This function must be executed inside a dedicated background runspace. It blocks
while polling `BlockingCollection.TryTake()` on the logging queue, so it must
never run on the main thread. All access to shared state goes through
`Get-GlobalRuntimeVariable` because the runspace receives only a snapshot of
`$Global:IcingaForWindows` at startup. The daemon exits cleanly when
`Test-ThreadRunning` returns `$false`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
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
                'Area'      = $Area;
                'Data'      = $Data;
                'TimeStamp' = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss:ffff');
            }
        #>
        $LogObject               = $null;
        $EventLog                = $null;
        [int]$EventId            = 15;
        [string]$DataDump        = '';
        [string]$LogMessage      = '';
        [string]$LogColor        = '';
        [string]$LogArea         = '';
        [string]$EntryType       = '';
        [string]$EventLogMessage = '';
        [string]$EventLogSource  = '';

        try {
            if (-not (Get-GlobalRuntimeVariable).Public.Logging.Queue.TryTake([ref]$LogObject, 10000)) {
                Set-ThreadProcessing;
                continue;
            }

            Set-ThreadProcessing;

            # Check if we should log this message based on the current logging level
            # In case we have a huge backlog of log messages, we want to skip unnecessary ones
            if (-not (Test-LoggingWriteLog -Level $LogObject.Level)) {
                continue;
            }

            $LogColor = (Get-GlobalRuntimeVariable).Public.Config.Colors.$($LogObject.Level);

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

            if ((Get-GlobalRuntimeVariable).Protected.OSType -eq 'Windows') {
                $LogArea = [string](Get-ModuleObjectValue -InputObject $LogObject -Name 'Area');

                # Set a default in case no area is set
                if ([string]::IsNullOrWhiteSpace($LogArea)) {
                    $LogArea = 'Logging';
                } else {
                    $LogArea = $LogArea.Trim();
                }

                # Map our log levels to EventLog entry types
                $EntryType        = Get-LoggingEventLogSeverity -Severity $LogObject.Level;
                $EventLogMessage  = Format-LoggingConsoleMessage -Message $LogMessage -GetMsgObj;
                $EventLogMessage += "`r`n" + '============================' + "`r`n" + $LogMessage;

                # Classic Windows Event Log entries reject payloads exceeding 31839 characters
                if ($EventLogMessage.Length -gt 31839) {
                    $EventLogMessage = $EventLogMessage.Substring(0, 31839);
                }

                # Classic Windows Event Log requires UInt16 event identifiers (0..65535)
                [int]$CandidateEventId = 0;
                if ($null -ne $LogObject.EventId -and [int]::TryParse([string]$LogObject.EventId, [ref]$CandidateEventId)) {
                    if ($CandidateEventId -ge 0 -and $CandidateEventId -le 65535) {
                        [int]$EventId = $CandidateEventId;
                    }
                }

                $EventLogSource = [string]::Format('{0}::{1}', $ModuleName, $LogArea);
                try {
                    $EventLog        = New-Object System.Diagnostics.EventLog;
                    $EventLog.Log    = $ModuleName;
                    $EventLog.Source = $EventLogSource;
                    $EventLog.WriteEntry($EventLogMessage, $EntryType, $EventId);
                } catch {
                    # Keep the logging daemon alive if Event Log sources are unregistered or inaccessible
                    [void]$_;
                }
            }

            Format-LoggingConsoleMessage -Message $LogMessage;
        } finally {
            if ($null -ne $EventLog) {
                $EventLog.Dispose();
            }
            if ($null -ne $LogObject) {
                $LogObject.Data = $null;
            }
            $DataDump        = $null;
            $LogObject       = $null;
            $LogMessage      = $null;
            $EventLog        = $null;
            $EventLogSource  = $null;
            $EventLogMessage = $null;
            $EntryType       = $null;
            $LogArea         = $null;
            $LogColor        = $null;
        }
    }
}

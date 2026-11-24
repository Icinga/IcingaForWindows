<#
.SYNOPSIS
Create and configure Windows Event Log sources for Icinga for Windows

.DESCRIPTION
Register-LoggingWindowsEventLog registers every unique IcingaForWindows::<Area>
Windows Event Log source from (Get-GlobalRuntimeVariable).Public.ReturnCodes
(always seeding IcingaForWindows::Logging) and configures the maximum log size
to 100 MiB (104857600 bytes). On non-Windows platforms the function returns
immediately without side effects.

.OUTPUTS
None -- Registers event sources under the module name and configures the maximum log size.

.EXAMPLE
PS> Set-InternalExitCodes
PS> Register-LoggingWindowsEventLog

Populates the internal return-code registry, registers all Icinga for Windows
Event Log sources, and configures the 100 MiB maximum log size.

.NOTES
Requires administrative privileges on Windows to create Windows Event Log
sources and modify log settings. Callers (such as Install-IcingaForWindows)
must invoke Set-InternalExitCodes beforehand so
(Get-GlobalRuntimeVariable).Public.ReturnCodes is populated with all subsystem
Area definitions prior to source enumeration. The module name is resolved via
Get-ModuleProjectName, and sources are checked and registered in-process via
[System.Diagnostics.EventLog]::SourceExists and
[System.Diagnostics.EventLog]::CreateEventSource on both Windows PowerShell 5.1
and PowerShell 7+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Register-LoggingWindowsEventLog()
{
    if ((Get-GlobalRuntimeVariable).Protected.OSType -ne 'Windows') {
        return;
    }

    $ModuleName                   = Get-ModuleProjectName;
    [hashtable]$ReturnCodes       = (Get-GlobalRuntimeVariable).Public.ReturnCodes;
    [string]$DefaultLoggingSource = [string]::Format('{0}::Logging', $ModuleName);
    [array]$AreaList              = @( $DefaultLoggingSource );
    [array]$FailedSources         = @();
    [string]$LastRegError         = '';

    foreach ($entry in $ReturnCodes.Keys) {
        $Value = $ReturnCodes[$entry];

        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace($Value['Area'])) {
            continue;
        }

        [string]$SourceName = ([string]::Format('{0}::{1}', $ModuleName, $Value['Area'].Trim()));

        if ($AreaList -notcontains $SourceName) {
            $AreaList += $SourceName;
        }
    }

    foreach ($entry in $AreaList) {
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists($entry)) {
                [System.Diagnostics.EventLog]::CreateEventSource($entry, $ModuleName);
            }
        } catch {
            [bool]$AlreadyRegistered = $false;
            try {
                $AlreadyRegistered = [System.Diagnostics.EventLog]::SourceExists($entry);
            } catch {
                $AlreadyRegistered = $false;
            }

            if (-not $AlreadyRegistered) {
                $FailedSources += $entry;
                if ([string]::IsNullOrEmpty($LastRegError) -and $null -ne $_.Exception) {
                    $LastRegError = $_.Exception.Message;
                }
            }
        }
    }

    if ($FailedSources.Count -gt 0) {
        Write-LoggingEntry -Message 'Failed to register one or more Windows Event Log sources; ensure the session runs with administrative privileges' -Level 'Warning' -Area 'Logging' -Data @{
            'LogName'       = $ModuleName;
            'FailedSources' = $FailedSources;
            'Error'         = $LastRegError;
        };
    }

    $LogLocation = $null;
    try {
        try {
            $LogLocation = Get-WinEvent -ListLog $ModuleName -ErrorAction Stop;
        } catch {
            return;
        }

        if ($null -eq $LogLocation) {
            return;
        }

        # In case the value is already set, nothing to do
        if ($LogLocation.MaximumSizeInBytes -eq 104857600) {
            return;
        }

        # Set the size to 100 MiB
        try {
            $LogLocation.MaximumSizeInBytes = 104857600;
            $LogLocation.SaveChanges();
        } catch {
            Write-LoggingEntry -Message 'Failed to update maximum size for Windows Event Log; ensure the session runs with administrative privileges' -Level 'Warning' -Area 'Logging' -Data @{
                'LogName'            = $ModuleName;
                'MaximumSizeInBytes' = 104857600;
                'Error'              = $_.Exception.Message;
            };
        }
    } finally {
        if ($LogLocation -is [System.IDisposable]) {
            $LogLocation.Dispose();
        }
    }
}

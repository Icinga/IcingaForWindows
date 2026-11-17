<#
.SYNOPSIS
Map internal log severity to Windows EventLog entry types.

.DESCRIPTION
`Get-LoggingEventLogSeverity` converts module logging severity labels to
Windows EventLog entry types such as 'Information' or 'Error'.

.PARAMETER Severity
| Name     | Type          | Description                                     | Default |
|----------|---------------|-------------------------------------------------|---------|
| Severity | System.String | Internal severity string (e.g. 'Debug', 'Info') |         |

.OUTPUTS
System.String -- The Windows EventLog entry type name.

.EXAMPLE
PS> Get-LoggingEventLogSeverity -Severity 'Error'

.NOTES
Unknown severities default to 'Information'.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-LoggingEventLogSeverity()
{
    param (
        [string]$Severity = $null
    );

    if ([string]::IsNullOrEmpty($Severity)) {
        return 'Information';
    }

    switch ($Severity) {
        'Info' {
            return 'Information';
        };
        'Success' {
            return 'Information';
        };
        'Debug' {
            return 'Information';
        };
        'Warning' {
            return 'Warning';
        };
        'Error' {
            return 'Error';
        };
        'Audit' {
            return 'Information';
        };
        'Output' {
            return 'Information';
        };
        'Fatal' {
            return 'Error';
        };
        default {
            return 'Information';
        };
    }

    return 'Information';
}

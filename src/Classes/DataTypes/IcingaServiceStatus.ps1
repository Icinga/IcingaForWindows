<#
.SYNOPSIS
Status of a Windows service with its numeric status code

.DESCRIPTION
IcingaServiceStatus lists every state a Windows service can be in. The numeric
values match System.ServiceProcess.ServiceControllerStatus (1 Stopped to 7
Paused) and are written as the service state performance data. Unknown (0)
covers services whose state cannot be determined, which Win32_Service reports
as 'Unknown'.

The enum is used directly as a parameter type, so a plugin parameter such as
[IcingaServiceStatus]$Status accepts 'Running', 'running' or 4 and rejects
anything else with the list of valid names. A value converts to its code with
[int] and to its name with [string].

.OUTPUTS
IcingaServiceStatus -- Enum value of the service status.

.EXAMPLE
PS> [int][IcingaServiceStatus]::Running

Returns 4, the code used for the service state performance data.

.NOTES
Defined in the kernel ahead of every function, so functions may use it as a
parameter type. Not visible outside the module scope; callers pass the name or
code as a string.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
enum IcingaServiceStatus
{
    Unknown         = 0;
    Stopped         = 1;
    StartPending    = 2;
    StopPending     = 3;
    Running         = 4;
    ContinuePending = 5;
    PausePending    = 6;
    Paused          = 7;
}

<#
.SYNOPSIS
Map external service status values onto IcingaServiceStatus

.DESCRIPTION
IcingaServiceStatusMap converts the status representations of the different
Windows service sources into an IcingaServiceStatus: the Win32_Service 'State'
strings with blanks ('Start Pending'), the ServiceControllerStatus values of
Get-Service, enum names in any casing and numeric status codes. Every value that
cannot be mapped resolves to Unknown instead of throwing, so a plugin can always
report a state.

.OUTPUTS
IcingaServiceStatusMap -- Static helper class, not meant to be instantiated.

.EXAMPLE
PS> [IcingaServiceStatusMap]::Resolve('Start Pending')

Returns IcingaServiceStatus::StartPending.

.NOTES
Pure conversion helper without state or external dependencies.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
class IcingaServiceStatusMap
{
    <#
    .SYNOPSIS
    Resolve a service status value into an IcingaServiceStatus

    .DESCRIPTION
    Removes blanks from the value and converts it into an IcingaServiceStatus by
    name (case-insensitive) or by numeric code. Returns Unknown for $null, empty,
    unknown names and undefined codes.

    .PARAMETER Value
    | Name  | Type          | Description                                                        | Default |
    |-------|---------------|--------------------------------------------------------------------|---------|
    | Value | System.Object | Status name, Win32_Service state, ServiceControllerStatus or code. |         |

    .OUTPUTS
    IcingaServiceStatus -- The resolved status, Unknown when it cannot be mapped.

    .EXAMPLE
    PS> [IcingaServiceStatusMap]::Resolve('Running')

    .NOTES
    PowerShell enum conversion rejects undefined codes, so '-as' returns $null for
    them and they fall back to Unknown like unknown names.
    #>
    static [IcingaServiceStatus] Resolve([object]$Value)
    {
        if ($null -eq $Value) {
            return [IcingaServiceStatus]::Unknown;
        }

        $Status = ([string]$Value).Replace(' ', '') -as [IcingaServiceStatus];

        if ($null -eq $Status) {
            return [IcingaServiceStatus]::Unknown;
        }

        return $Status;
    }
}

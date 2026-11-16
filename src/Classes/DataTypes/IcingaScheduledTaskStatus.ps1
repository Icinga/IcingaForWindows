<#
.SYNOPSIS
Status of a Windows scheduled task with its numeric status code

.DESCRIPTION
IcingaScheduledTaskStatus lists every state a Windows scheduled task can be in.
The numeric values (0 Unknown, 1 Disabled, 2 Queued, 3 Ready, 4 Running) match
the Windows Task Scheduler StateEnum and are written as the task state
performance data.

The enum is used directly as a parameter type, so a plugin parameter such as
[IcingaScheduledTaskStatus[]]$State accepts 'Ready', 'Running' or 3 and rejects
invalid values with the list of valid names. A value converts to its numeric
code with [int] and to its display name with [string].

.OUTPUTS
IcingaScheduledTaskStatus -- Enum value of the scheduled task status.

.EXAMPLE
PS> [int][IcingaScheduledTaskStatus]::Ready

Returns 3, the code used for the scheduled task state performance data.

.NOTES
Defined in the kernel ahead of every function, so functions may use it as a
parameter type. Not visible outside the module scope; callers pass the name or
code as a string.
#>
enum IcingaScheduledTaskStatus
{
    Unknown  = 0;
    Disabled = 1;
    Queued   = 2;
    Ready    = 3;
    Running  = 4;
}

<#
.SYNOPSIS
Map external scheduled task status values onto IcingaScheduledTaskStatus

.DESCRIPTION
IcingaScheduledTaskStatusMap converts the status representations returned by
Get-ScheduledTask (CimInstance StateEnum, strings or numeric codes) into an
IcingaScheduledTaskStatus. Any value that cannot be mapped resolves to Unknown
instead of throwing, so a plugin can always report a state.

.OUTPUTS
IcingaScheduledTaskStatusMap -- Static helper class, not meant to be instantiated.

.EXAMPLE
PS> [IcingaScheduledTaskStatusMap]::Resolve('Ready')

Returns IcingaScheduledTaskStatus::Ready.

.NOTES
Pure conversion helper without state or external dependencies.
#>
class IcingaScheduledTaskStatusMap
{
    <#
    .SYNOPSIS
    Resolve a scheduled task status value into an IcingaScheduledTaskStatus

    .DESCRIPTION
    Removes blanks from the value and converts it into an
    IcingaScheduledTaskStatus by name (case-insensitive) or by numeric code.
    Returns Unknown for $null, empty strings, unknown names and undefined codes.

    .PARAMETER Value
    | Name  | Type          | Description                                               | Default |
    |-------|---------------|-----------------------------------------------------------|---------|
    | Value | System.Object | Status name, ScheduledTask StateEnum or numeric code.     |         |

    .OUTPUTS
    IcingaScheduledTaskStatus -- The resolved status, Unknown when it cannot be mapped.

    .EXAMPLE
    PS> [IcingaScheduledTaskStatusMap]::Resolve('Running')

    .NOTES
    PowerShell enum conversion rejects undefined codes, so '-as' returns $null for
    them and they fall back to Unknown like unknown names.
    #>
    static [IcingaScheduledTaskStatus] Resolve([object]$Value)
    {
        if ($null -eq $Value) {
            return [IcingaScheduledTaskStatus]::Unknown;
        }

        $Status = ([string]$Value).Replace(' ', '') -as [IcingaScheduledTaskStatus];

        if ($null -eq $Status) {
            return [IcingaScheduledTaskStatus]::Unknown;
        }

        return $Status;
    }
}

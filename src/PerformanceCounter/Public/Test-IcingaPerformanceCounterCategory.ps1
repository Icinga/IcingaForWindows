<#
.SYNOPSIS
Check whether a Windows performance counter category exists on the local system

.DESCRIPTION
`Test-IcingaPerformanceCounterCategory` checks whether the given performance counter category
is present and accessible on the local system. It accepts either a plain category name
(such as 'Processor' or 'Memory') or a full counter path (such as
'\Processor(*)\% Processor Time' or '\\.\Processor(_Total)\% Processor Time').

Because it only queries category metadata and never throws, it is safe to call from any
thread or provider before reading optional role counters (such as Hyper-V, IIS or MSSQL).

.PARAMETER Category
| Name     | Type          | Description                                               | Default |
|----------|---------------|-----------------------------------------------------------|---------|
| Category | System.String | The category name or counter path to check for existence. |         |

.OUTPUTS
System.Boolean -- $true when the category exists and is accessible on this system; $false otherwise.

.EXAMPLE
PS> Test-IcingaPerformanceCounterCategory -Category 'Processor'

Returns $true when the 'Processor' performance counter category exists on the system.

.EXAMPLE
PS> Test-IcingaPerformanceCounterCategory -Category '\Hyper-V Virtual Machine Health Summary(*)\Health Critical'

Extracts the category name from the counter path and returns $true when the category exists.

.NOTES
Delegates to `IcingaPerformanceCounter::CategoryExists`. Never throws and reads no global state.
#>
function Test-IcingaPerformanceCounterCategory()
{
    param (
        [string]$Category = ''
    );

    $CounterType = 'IcingaPerformanceCounter' -as [type];

    return $CounterType::CategoryExists($Category);
}

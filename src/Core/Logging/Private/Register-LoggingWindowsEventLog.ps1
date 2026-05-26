<#
.SYNOPSIS
Create and configure Windows Event Log sources for this module.

.DESCRIPTION
`Register-LoggingWindowsEventLog` registers event sources under the provided
namespace and ensures the log maximum size is configured.

.OUTPUTS
None — Registers event sources under the module name and configures the maximum log size.

.EXAMPLE
PS> Register-LoggingWindowsEventLog

.NOTES
Requires administrative privileges to create Windows EventLog sources and modify log settings.
The module name is resolved via `Get-ModuleProjectName`. Return codes are read from
`(Get-GlobalRuntimeVariable).Public.ReturnCodes` to derive the full list of source names.
#>
function Register-LoggingWindowsEventLog()
{
    $ModuleName             = Get-ModuleProjectName;
    [hashtable]$ReturnCodes = (Get-GlobalRuntimeVariable).Public.ReturnCodes;
    [array]$AreaList        = @();

    foreach ($entry in $ReturnCodes.Keys) {
        $Value = $ReturnCodes[$entry];

        if ($null -eq $Value.Area) {
            continue;
        }

        [string]$SourceName = ([string]::Format('{0}::{1}', $ModuleName, $Value.Area));

        if (-not $AreaList.Contains($SourceName)) {
            $AreaList += $SourceName;
        }
    }

    foreach ($entry in $AreaList) {
        New-EventLog -LogName $ModuleName -Source $entry -ErrorAction SilentlyContinue;
    }

    $LogLocation = Get-WinEvent -ListLog $ModuleName;

    # In case the value is already set, nothing to do
    if ($LogLocation.MaximumSizeInBytes -eq 104857600) {
        return;
    }

    # Set the size to 100MiB
    $LogLocation.MaximumSizeInBytes = 104857600;
    $LogLocation.SaveChanges();
}

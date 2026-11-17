<#
.SYNOPSIS
Create or return a shared PowerShell runspace pool for threads.

.DESCRIPTION
`New-ThreadPool` creates a `RunspacePool` with the given minimum and maximum
instances and caches it on the global runtime variable. If a pool already
exists, the cached instance is returned.

.PARAMETER MinInstances
| Name         | Type         | Description                             | Default |
|--------------|--------------|-----------------------------------------|---------|
| MinInstances | System.Int32 | Minimum number of runspaces in the pool | 1       |

.PARAMETER MaxInstances
| Name         | Type         | Description                             | Default                                                   |
|--------------|--------------|-----------------------------------------|-----------------------------------------------------------|
| MaxInstances | System.Int32 | Maximum number of runspaces in the pool | `(Get-GlobalRuntimeVariable).Public.Threading.MaxThreads` |

.OUTPUTS
System.Management.Automation.Runspaces.RunspacePool -- The newly created or cached runspace pool.

.EXAMPLE
PS> New-ThreadPool -MinInstances 2 -MaxInstances 8

.NOTES
The function currently uses the default `InitialSessionState`. Future work may enable JEA.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function New-ThreadPool()
{
    param(
        [int]$MinInstances = 1,
        [int]$MaxInstances = ((Get-GlobalRuntimeVariable).Public.Threading.MaxThreads)
    );

    if ($null -ne (Get-GlobalRuntimeVariable).Public.Threading.ThreadPool) {
        return (Get-GlobalRuntimeVariable).Public.Threading.ThreadPool;
    }

    Write-LoggingEntry 'Creating new Thread Pool' -Level 'Debug';

    $SessionConfiguration = $null;
    <# TODO: Enable JEA support in the future
    $SessionFile          = Get-JEASessionFile;

    if ([string]::IsNullOrEmpty((Get-JEAContext))) {
        $SessionConfiguration = [System.Management.Automation.RunSpaces.InitialSessionState]::CreateDefault();
    } else {
        if ([string]::IsNullOrEmpty($SessionFile)) {
            Write-LoggingEntry -Message 'Failed to create Thread Pool: JEA session file not found' -Level 'Error';
            return $null;
        }
        $SessionConfiguration = [System.Management.Automation.Runspaces.InitialSessionState]::CreateFromSessionConfigurationFile($SessionFile);
    }
    #>
    $SessionConfiguration = [System.Management.Automation.RunSpaces.InitialSessionState]::CreateDefault2();

    [string]$ManifestPath = Join-Path -Path (Get-ModuleRootDirectory) -ChildPath 'IcingaForWindows.psd1';
    if (Test-Path -Path $ManifestPath) {
        $SessionConfiguration.ImportPSModule(@($ManifestPath));
    }

    $RunSpaces = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
        $MinInstances,
        $MaxInstances,
        $SessionConfiguration,
        $host
    );

    $RunSpaces.Open();

    (Get-GlobalRuntimeVariable).Public.Threading.ThreadPool = $RunSpaces;

    return (Get-GlobalRuntimeVariable).Public.Threading.ThreadPool;
}

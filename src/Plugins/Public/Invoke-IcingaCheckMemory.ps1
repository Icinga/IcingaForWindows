<#
.SYNOPSIS
Check the used physical memory, the memory paging rate and the page files against thresholds

.DESCRIPTION
Builds a single IcingaPlugin container named 'Memory Usage' with the checks
'Used Memory' (installed physical memory minus the available memory, in bytes),
'Memory pages/sec' (hard page faults per second) and a 'PageFile Usage' package
with one check per page file (current usage in bytes). Every check is evaluated
immediately against its own warning and critical thresholds. The memory and page
file thresholds accept percentages of the respective size ('80%'), absolute sizes
('4GiB', '500MB') and the full Icinga range grammar.

The available memory and the paging rate are read in one request from the
'\Memory\Available Bytes' and '\Memory\Pages/sec' performance counters, which the
performance-counter daemon keeps warm. The installed memory comes from
Win32_ComputerSystem and the page files from Win32_PageFileUsage. A page file
with a configured maximum size (Win32_PageFileSetting, only read when Windows does
not manage the page files automatically) is measured against that maximum,
otherwise against its currently allocated size. IncludePageFile and
ExcludePageFile filter the page files by name (wildcards allowed); the package is
left out when no page file remains.

Performance data uses the labels 'memory::ifw_memory::used',
'memory::ifw_memory::pagessec' and '<pagefile>::ifw_pagefile::used' (for example
'cpagefilesys::ifw_pagefile::used'). A failed query or counter read is reported
as UNKNOWN with its reason.

.PARAMETER Warning
| Name    | Type          | Description                                                         | Default |
|---------|---------------|---------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold for the used memory, e.g. '80%' or '12GiB'.       |         |

.PARAMETER Critical
| Name     | Type          | Description                                                         | Default |
|----------|---------------|---------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold for the used memory, e.g. '90%' or '14GiB'.      |         |

.PARAMETER PageFileWarning
| Name            | Type          | Description                                                  | Default |
|-----------------|---------------|--------------------------------------------------------------|---------|
| PageFileWarning | System.String | Warning threshold for every page file, e.g. '80%' or '2GiB'. |         |

.PARAMETER PageFileCritical
| Name             | Type          | Description                                                   | Default |
|------------------|---------------|---------------------------------------------------------------|---------|
| PageFileCritical | System.String | Critical threshold for every page file, e.g. '90%' or '3GiB'. |         |

.PARAMETER MemoryPagesSecWarning
| Name                  | Type          | Description                                   | Default |
|-----------------------|---------------|-----------------------------------------------|---------|
| MemoryPagesSecWarning | System.String | Warning threshold for the memory pages/sec.   |         |

.PARAMETER MemoryPagesSecCritical
| Name                   | Type          | Description                                   | Default |
|------------------------|---------------|-----------------------------------------------|---------|
| MemoryPagesSecCritical | System.String | Critical threshold for the memory pages/sec.  |         |

.PARAMETER IncludePageFile
| Name            | Type         | Description                                              | Default |
|-----------------|--------------|----------------------------------------------------------|---------|
| IncludePageFile | System.Array | Only check page files matching these names (wildcards).  | @()     |

.PARAMETER ExcludePageFile
| Name            | Type         | Description                                          | Default |
|-----------------|--------------|------------------------------------------------------|---------|
| ExcludePageFile | System.Array | Skip page files matching these names (wildcards).    | @()     |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                        | Default |
|-----------|--------------|------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config.| 0       |

.PARAMETER NoPerfData
| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

.OUTPUTS
System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

.EXAMPLE
PS> Invoke-IcingaCheckMemory -Warning '80%' -Critical '90%'

Warns at 80% and goes critical at 90% used physical memory.

.EXAMPLE
PS> Invoke-IcingaCheckMemory -Warning '12GiB' -Critical '14GiB' -PageFileWarning '75%' -Verbosity 2

Uses absolute memory thresholds, checks the page files against 75% and lists every check.

.NOTES
Windows-only. Reads the '\Memory\Available Bytes' and '\Memory\Pages/sec'
performance counters ('Performance Monitor Users') and the Win32_ComputerSystem,
Win32_PageFileUsage and Win32_PageFileSetting CIM classes. The integer exit code
is the return value; an Icinga command wrapper is expected to exit with it.
#>
function Invoke-IcingaCheckMemory()
{
    param (
        [string]$Warning                = '',
        [string]$Critical               = '',
        [string]$PageFileWarning        = '',
        [string]$PageFileCritical       = '',
        [string]$MemoryPagesSecWarning  = '',
        [string]$MemoryPagesSecCritical = '',
        [array]$IncludePageFile         = @(),
        [array]$ExcludePageFile         = @(),
        [int]$Verbosity                 = 0,
        [switch]$NoPerfData             = $false
    );

    # Literal declaration, so the counter discovery at module start finds and warms them.
    New-IcingaPerformanceCounter -Counter @('\Memory\Available Bytes', '\Memory\Pages/sec');

    $CheckPackage            = New-IcingaPlugin 'Memory Usage';
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    $ComputerSystem          = Get-IcingaWindowsInformation -ClassName 'Win32_ComputerSystem' -Property 'TotalPhysicalMemory', 'AutomaticManagedPagefile';

    if (Test-IcingaError -InputObject $ComputerSystem) {
        return $CheckPackage.SetError($ComputerSystem).Compile();
    }

    $PageFiles = Get-IcingaWindowsInformation -ClassName 'Win32_PageFileUsage' -Property 'Name', 'AllocatedBaseSize', 'CurrentUsage';

    if (Test-IcingaError -InputObject $PageFiles) {
        return $CheckPackage.SetError($PageFiles).Compile();
    }

    $Counters       = Get-IcingaPerformanceCounter -Counter @('\Memory\Available Bytes', '\Memory\Pages/sec') -StructureByInstance;
    $MemoryCounters = $null;

    if ($null -ne $Counters) {
        $MemoryCounters = $Counters['Memory'];
    }

    if ($null -eq $MemoryCounters) {
        return $CheckPackage.SetError('Failed to read the performance counters of the category Memory').Compile();
    }

    [uint64]$TotalMemory = $ComputerSystem[0].TotalPhysicalMemory;
    $Available           = Get-IcingaPerformanceCounterValue -InputObject $MemoryCounters['Available Bytes'];

    if ($null -eq $Available -or $Available -is [string]) {
        $CheckPackage.AddCheck(
            (New-IcingaPlugin 'Used Memory').SetError('Failed to read the performance counter \Memory\Available Bytes: {0}', $Available)
        ).Commit();
    } else {
        [uint64]$UsedMemory = [System.Math]::Max([double]0, [double]$TotalMemory - [double]$Available);

        $CheckPackage.AddCheck(
            (New-IcingaPlugin 'Used Memory' $UsedMemory 'B').
                MetricIndex('memory').
                MetricLabel('used').
                Warning($Warning).
                Critical($Critical).
                BaseValue($TotalMemory).
                Minimum('0').
                Maximum([string]$TotalMemory).
                CheckRange()
        ).Commit();
    }

    $PagesSec = Get-IcingaPerformanceCounterValue -InputObject $MemoryCounters['Pages/sec'];

    if ($null -eq $PagesSec -or $PagesSec -is [string]) {
        $CheckPackage.AddCheck(
            (New-IcingaPlugin 'Memory pages/sec').SetError('Failed to read the performance counter \Memory\Pages/sec: {0}', $PagesSec)
        ).Commit();
    } else {
        $CheckPackage.AddCheck(
            (New-IcingaPlugin 'Memory pages/sec' ([System.Math]::Round([double]$PagesSec, 2))).
                MetricIndex('memory').
                MetricLabel('pagessec').
                Warning($MemoryPagesSecWarning).
                Critical($MemoryPagesSecCritical).
                CheckRange()
        ).Commit();
    }

    # Configured maximum page file sizes in MB. A failed query only leaves the
    # page files on their allocated size, it is no reason to fail the check.
    [hashtable]$MaximumSizes = @{ };

    if ($ComputerSystem[0].AutomaticManagedPagefile -eq $false) {
        $PageFileSettings = Get-IcingaWindowsInformation -ClassName 'Win32_PageFileSetting' -Property 'Name', 'MaximumSize';

        if ((Test-IcingaError -InputObject $PageFileSettings) -eq $false) {
            foreach ($Setting in $PageFileSettings) {
                $MaximumSizes[[string]$Setting.Name] = [uint64]$Setting.MaximumSize;
            }
        }
    }

    $PageFilePackage = New-IcingaPlugin 'PageFile Usage';

    foreach ($PageFile in (ConvertTo-IcingaSortedArray -InputObject @($PageFiles) -Property 'Name')) {
        [string]$PageFileName = $PageFile.Name;

        if ((Test-IcingaArrayFilter -InputObject $PageFileName -Include $IncludePageFile -Exclude $ExcludePageFile) -eq $false) {
            continue;
        }

        # A maximum of 0 means the size of this page file is managed by Windows.
        [uint64]$SizeMB = $PageFile.AllocatedBaseSize;

        if ($MaximumSizes.ContainsKey($PageFileName) -and $MaximumSizes[$PageFileName] -gt 0) {
            $SizeMB = $MaximumSizes[$PageFileName];
        }

        [uint64]$Size  = $SizeMB * 1MB;
        [uint64]$Usage = [uint64]$PageFile.CurrentUsage * 1MB;

        # Perfdata label: <pagefile>::ifw_pagefile::used (own template instead of ifw_memory).
        $PageFilePackage.AddCheck(
            (New-IcingaPlugin $PageFileName $Usage 'B').
                MetricIndex($PageFileName).
                MetricName('pagefile').
                MetricLabel('used').
                Warning($PageFileWarning).
                Critical($PageFileCritical).
                BaseValue($Size).
                Minimum('0').
                Maximum([string]$Size).
                CheckRange()
        ).Commit();
    }

    if ($PageFilePackage.HasChecks()) {
        $CheckPackage.AddCheck($PageFilePackage).Commit();
    }

    return $CheckPackage.Compile();
}

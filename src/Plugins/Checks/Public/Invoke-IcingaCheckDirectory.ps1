<#
.SYNOPSIS
Check the number and the sizes of the files in a directory against thresholds

.DESCRIPTION
Reads the directory through Get-IcingaDirectoryInformation, which scans it once
and applies every name, time and size filter while reading, and builds a single
IcingaPlugin container named 'Directory Check: "<Path>"'. It holds the checks
'File Count', 'Folder Count', 'Total Size', 'Smallest File Size', 'Largest File
Size' and 'Average File Size' of the entries matching the filters, each evaluated
immediately against its own warning and critical thresholds, plus the
informational 'File Found' check.

Warning and Critical apply to the file count (with CountFolderAsFile the matching
folders are counted as well); the size thresholds accept sizes ('2GiB', '500MB')
and the full Icinga range grammar. Without OverrideNotFound a missing directory
is reported as UNKNOWN and 'File Found' only informs whether anything matched.
With OverrideNotFound a missing directory counts as an empty one and 'File Found'
takes the given state when nothing matches, so a missing backup file can be
reported as CRITICAL.

ShowFileList adds an informational 'File List' package with every matching entry
and its size; it raises the verbosity to at least 2 so the list is part of the
output. The list entries are not counted in the summary header.

Performance data uses the label '<path>::ifw_directory::<metric>' with the
metrics files, folders, totalsize, smallestfile, largestfile and averagefile,
sizes in bytes. A directory that cannot be read or an invalid filter value is
reported as UNKNOWN with its reason.

.PARAMETER Path
| Name | Type          | Description                                     | Default |
|------|---------------|-------------------------------------------------|---------|
| Path | System.String | Directory to check, e.g. 'C:\ProgramData\Logs'. |         |

.PARAMETER FileNames
| Name      | Type         | Description                                          | Default |
|-----------|--------------|------------------------------------------------------|---------|
| FileNames | System.Array | Wildcard patterns for the entry names, e.g. '*.log'. | @('*')  |

.PARAMETER Recurse
| Name    | Type                                         | Description                       | Default |
|---------|----------------------------------------------|-----------------------------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Check every subdirectory as well. | False   |

.PARAMETER Warning
| Name    | Type          | Description                                         | Default |
|---------|---------------|-----------------------------------------------------|---------|
| Warning | System.String | Warning threshold for the number of matching files. |         |

.PARAMETER Critical
| Name     | Type          | Description                                          | Default |
|----------|---------------|------------------------------------------------------|---------|
| Critical | System.String | Critical threshold for the number of matching files. |         |

.PARAMETER WarningTotalSize
| Name             | Type          | Description                                        | Default |
|------------------|---------------|----------------------------------------------------|---------|
| WarningTotalSize | System.String | Warning threshold for the total size, e.g. '2GiB'. |         |

.PARAMETER CriticalTotalSize
| Name              | Type          | Description                                         | Default |
|-------------------|---------------|-----------------------------------------------------|---------|
| CriticalTotalSize | System.String | Critical threshold for the total size, e.g. '4GiB'. |         |

.PARAMETER WarningSmallestFile
| Name                | Type          | Description                                   | Default |
|---------------------|---------------|-----------------------------------------------|---------|
| WarningSmallestFile | System.String | Warning threshold for the smallest file size. |         |

.PARAMETER CriticalSmallestFile
| Name                 | Type          | Description                                    | Default |
|----------------------|---------------|------------------------------------------------|---------|
| CriticalSmallestFile | System.String | Critical threshold for the smallest file size. |         |

.PARAMETER WarningLargestFile
| Name               | Type          | Description                                  | Default |
|--------------------|---------------|----------------------------------------------|---------|
| WarningLargestFile | System.String | Warning threshold for the largest file size. |         |

.PARAMETER CriticalLargestFile
| Name                | Type          | Description                                   | Default |
|---------------------|---------------|-----------------------------------------------|---------|
| CriticalLargestFile | System.String | Critical threshold for the largest file size. |         |

.PARAMETER WarningAverageFile
| Name               | Type          | Description                                  | Default |
|--------------------|---------------|----------------------------------------------|---------|
| WarningAverageFile | System.String | Warning threshold for the average file size. |         |

.PARAMETER CriticalAverageFile
| Name                | Type          | Description                                   | Default |
|---------------------|---------------|-----------------------------------------------|---------|
| CriticalAverageFile | System.String | Critical threshold for the average file size. |         |

.PARAMETER CountFolderAsFile
| Name              | Type                                         | Description                                 | Default |
|-------------------|----------------------------------------------|---------------------------------------------|---------|
| CountFolderAsFile | System.Management.Automation.SwitchParameter | Add the matching folders to the file count. | False   |

.PARAMETER ShowFileList
| Name         | Type                                         | Description                                                | Default |
|--------------|----------------------------------------------|------------------------------------------------------------|---------|
| ShowFileList | System.Management.Automation.SwitchParameter | List every matching entry; can make the output very large. | False   |

.PARAMETER ChangeTimeEqual
| Name            | Type          | Description                                                    | Default |
|-----------------|---------------|----------------------------------------------------------------|---------|
| ChangeTimeEqual | System.String | Only entries last written on the day this long ago, e.g. '1d'. |         |

.PARAMETER ChangeYoungerThan
| Name              | Type          | Description                                                | Default |
|-------------------|---------------|------------------------------------------------------------|---------|
| ChangeYoungerThan | System.String | Only entries last written within this duration, e.g. '5d'. |         |

.PARAMETER ChangeOlderThan
| Name            | Type          | Description                                                 | Default |
|-----------------|---------------|-------------------------------------------------------------|---------|
| ChangeOlderThan | System.String | Only entries last written longer ago than this, e.g. '10d'. |         |

.PARAMETER CreationTimeEqual
| Name              | Type          | Description                                               | Default |
|-------------------|---------------|-----------------------------------------------------------|---------|
| CreationTimeEqual | System.String | Only entries created on the day this long ago, e.g. '1d'. |         |

.PARAMETER CreationOlderThan
| Name              | Type          | Description                                            | Default |
|-------------------|---------------|--------------------------------------------------------|---------|
| CreationOlderThan | System.String | Only entries created longer ago than this, e.g. '10d'. |         |

.PARAMETER CreationYoungerThan
| Name                | Type          | Description                                           | Default |
|---------------------|---------------|-------------------------------------------------------|---------|
| CreationYoungerThan | System.String | Only entries created within this duration, e.g. '5d'. |         |

.PARAMETER AccessYoungerThan
| Name              | Type          | Description                                                 | Default |
|-------------------|---------------|-------------------------------------------------------------|---------|
| AccessYoungerThan | System.String | Only entries last accessed within this duration, e.g. '5d'. |         |

.PARAMETER AccessOlderThan
| Name            | Type          | Description                                                  | Default |
|-----------------|---------------|--------------------------------------------------------------|---------|
| AccessOlderThan | System.String | Only entries last accessed longer ago than this, e.g. '10d'. |         |

.PARAMETER FileSizeGreaterThan
| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeGreaterThan | System.String | Only files larger than this size, e.g. '20MB'. |         |

.PARAMETER FileSizeSmallerThan
| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeSmallerThan | System.String | Only files smaller than this size, e.g. '5MB'. |         |

.PARAMETER OverrideNotFound
| Name             | Type          | Description                                                                                 | Default |
|------------------|---------------|---------------------------------------------------------------------------------------------|---------|
| OverrideNotFound | System.String | State when nothing matches: Ok, Warning, Critical, Unknown; a missing path counts as empty. |         |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                         | Default |
|-----------|--------------|-------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config. | 0       |

.PARAMETER NoPerfData
| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

.OUTPUTS
System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

.EXAMPLE
PS> Invoke-IcingaCheckDirectory -Path 'C:\Users\Icinga\Downloads' -Warning 20 -Critical 30

Warns when the directory holds more than 20 and goes critical with more than 30 files.

.EXAMPLE
PS> Invoke-IcingaCheckDirectory -Path 'D:\Logs' -Recurse -FileNames '*.log' -ChangeOlderThan '30d' -Critical 0

Goes critical as soon as any log file below D:\Logs is older than 30 days.

.EXAMPLE
PS> Invoke-IcingaCheckDirectory -Path 'C:\Backup' -FileNames '*.bak' -ChangeYoungerThan '1d' -OverrideNotFound 'Critical'

Goes critical when no backup file was written within the last day.

.NOTES
Windows-only. Reads the file system through Get-IcingaDirectoryInformation; the
user needs list permission on every checked directory. The integer exit code is
the return value; an Icinga command wrapper is expected to exit with it.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaCheckDirectory()
{
    param (
        [string]$Path                 = '',
        [array]$FileNames             = @( '*' ),
        [switch]$Recurse              = $false,
        [string]$Warning              = '',
        [string]$Critical             = '',
        [string]$WarningTotalSize     = '',
        [string]$CriticalTotalSize    = '',
        [string]$WarningSmallestFile  = '',
        [string]$CriticalSmallestFile = '',
        [string]$WarningLargestFile   = '',
        [string]$CriticalLargestFile  = '',
        [string]$WarningAverageFile   = '',
        [string]$CriticalAverageFile  = '',
        [switch]$CountFolderAsFile    = $false,
        [switch]$ShowFileList         = $false,
        [string]$ChangeTimeEqual      = '',
        [string]$ChangeYoungerThan    = '',
        [string]$ChangeOlderThan      = '',
        [string]$CreationTimeEqual    = '',
        [string]$CreationOlderThan    = '',
        [string]$CreationYoungerThan  = '',
        [string]$AccessYoungerThan    = '',
        [string]$AccessOlderThan      = '',
        [string]$FileSizeGreaterThan  = '',
        [string]$FileSizeSmallerThan  = '',
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotFound     = '',
        [int]$Verbosity               = 0,
        [switch]$NoPerfData           = $false
    );

    # The file list is informational and would stay hidden at lower verbosity.
    if ($ShowFileList -and $Verbosity -lt 2) {
        $Verbosity = 2;
    }

    $CheckPackage                  = New-IcingaPlugin ([string]::Format('Directory Check: "{0}"', $Path));
    $CheckPackage.Verbose          = $Verbosity;
    $CheckPackage.NoPerfData       = $NoPerfData;

    [hashtable]$DirectoryArguments = @{
        'Path'                = $Path;
        'FileNames'           = $FileNames;
        'Recurse'             = $Recurse;
        'ChangeTimeEqual'     = $ChangeTimeEqual;
        'ChangeYoungerThan'   = $ChangeYoungerThan;
        'ChangeOlderThan'     = $ChangeOlderThan;
        'CreationTimeEqual'   = $CreationTimeEqual;
        'CreationYoungerThan' = $CreationYoungerThan;
        'CreationOlderThan'   = $CreationOlderThan;
        'AccessYoungerThan'   = $AccessYoungerThan;
        'AccessOlderThan'     = $AccessOlderThan;
        'FileSizeGreaterThan' = $FileSizeGreaterThan;
        'FileSizeSmallerThan' = $FileSizeSmallerThan;
        'IncludeFileList'     = $ShowFileList;
        'IgnoreMissingPath'   = ([string]::IsNullOrEmpty($OverrideNotFound) -eq $false);
    };

    $Directory                     = Get-IcingaDirectoryInformation @DirectoryArguments;

    if (Test-IcingaError -InputObject $Directory) {
        return $CheckPackage.SetError($Directory).Compile();
    }

    [int]$FileCount = $Directory.FileCount;

    if ($CountFolderAsFile) {
        $FileCount += $Directory.FolderCount;
    }

    # Name, value, unit, metric label, warning and critical threshold of every check.
    [array]$Metrics = @(
        @('File Count', $FileCount, '', 'files', $Warning, $Critical),
        @('Folder Count', $Directory.FolderCount, '', 'folders', '', ''),
        @('Total Size', $Directory.TotalSize, 'B', 'totalsize', $WarningTotalSize, $CriticalTotalSize),
        @('Smallest File Size', $Directory.SmallestFile, 'B', 'smallestfile', $WarningSmallestFile, $CriticalSmallestFile),
        @('Largest File Size', $Directory.LargestFile, 'B', 'largestfile', $WarningLargestFile, $CriticalLargestFile),
        @('Average File Size', [System.Math]::Round([double]$Directory.AverageSize, 0), 'B', 'averagefile', $WarningAverageFile, $CriticalAverageFile)
    );

    foreach ($Metric in $Metrics) {
        # Perfdata label: <path>::ifw_directory::<metric> (template auto-derived from the command).
        $CheckPackage.AddCheck(
            (New-IcingaPlugin $Metric[0] $Metric[1] $Metric[2]).
                MetricIndex($Path).
                MetricLabel($Metric[3]).
                Warning($Metric[4]).
                Critical($Metric[5]).
                CheckRange()
        ).Commit();
    }

    [string]$FileFound = 'No';

    if ($FileCount -ne 0) {
        $FileFound = 'Yes';
    }

    $FoundCheck = (New-IcingaPlugin 'File Found' $FileFound).SetNoPerfData($true);

    if ([string]::IsNullOrEmpty($OverrideNotFound)) {
        $FoundCheck.SetNotice($FileFound).Commit();
    } elseif ($FileCount -ne 0) {
        $FoundCheck.SetOk($FileFound, $true).Commit();
    } else {
        $FoundCheck.SetState($OverrideNotFound, $FileFound, $true).Commit();
    }

    $CheckPackage.AddCheck($FoundCheck).Commit();

    if ($ShowFileList) {
        $FileListPackage = (New-IcingaPlugin 'File List').SetNotice();
        $UnitType        = 'IcingaUnit' -as [type];

        foreach ($Entry in (ConvertTo-IcingaSortedArray -InputObject @($Directory.FileList) -Property 'FullName')) {
            [string]$Details = 'Folder';

            if ($Entry -is [System.IO.FileInfo]) {
                $Details = $UnitType::new([string]$Entry.Length, 'B', '', $false).OutputString;
            }

            $FileListPackage.AddCheck(
                (New-IcingaPlugin $Entry.FullName).SetNotice($Details)
            ).Commit();
        }

        $CheckPackage.AddCheck($FileListPackage).Commit();
    }

    return $CheckPackage.Compile();
}

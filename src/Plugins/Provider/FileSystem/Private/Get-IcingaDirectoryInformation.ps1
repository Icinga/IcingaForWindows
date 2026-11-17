<#
.SYNOPSIS
Collect file and folder statistics of a directory in a single pass

.DESCRIPTION
Get-IcingaDirectoryInformation is the data source of the directory plugin. It
reads the directory exactly once and evaluates every entry while it is read: the
name filter, the time and size filters and the statistics (counts, total,
smallest, largest and average size) are all handled in the same loop, without a
pipeline, without script blocks and without a second lookup per entry.

All filter values are converted once before the scan. Time filters accept a
duration with an Icinga time unit ('20d', '12h', '30m', a plain number counts as
seconds) and compare against the moment of the call: ChangeOlderThan '20d' keeps
entries last written more than 20 days ago, ChangeYoungerThan keeps the ones
written within the last 20 days and ChangeTimeEqual keeps the ones written on
the calendar day 20 days ago. The Creation* and Access* filters do the same for
the creation and last access time. Size filters accept a size ('20MB', '1.5GiB',
a plain number counts as bytes) and only ever match files. Every given filter must
match (they are combined with AND).

FileNames are wildcard patterns matched case-insensitively against the entry
name; an entry is kept when any pattern matches. With Recurse the scan descends
into every subdirectory, whether its name matches or not. Hidden and system
entries are skipped like Get-ChildItem without -Force does, and reparse points
(junctions, symbolic links) are counted but never followed, so the scan cannot
loop.

Every exit goes through Write-FunctionReturnValue with its own return code
(DirectoryInformationCollected, DirectoryPathMissing, DirectoryPathNotFound,
DirectoryAccessDenied, DirectoryFilterInvalid, DirectoryReadFailed). A failure
returns an IcingaError that names the directory or filter, so a plugin can stop
with one check. A directory that cannot be read, including a subdirectory during
a recursive scan, ends the scan with DirectoryAccessDenied or DirectoryReadFailed.

.PARAMETER Path
| Name | Type          | Description                                    | Default |
|------|---------------|------------------------------------------------|---------|
| Path | System.String | Directory to scan, e.g. 'C:\ProgramData\Logs'. |         |

.PARAMETER FileNames
| Name      | Type         | Description                                          | Default |
|-----------|--------------|------------------------------------------------------|---------|
| FileNames | System.Array | Wildcard patterns for the entry names, e.g. '*.log'. | @('*')  |

.PARAMETER Recurse
| Name    | Type                                         | Description                      | Default |
|---------|----------------------------------------------|----------------------------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Scan every subdirectory as well. | False   |

.PARAMETER ChangeTimeEqual
| Name            | Type          | Description                                                    | Default |
|-----------------|---------------|----------------------------------------------------------------|---------|
| ChangeTimeEqual | System.String | Keep entries last written on the day this long ago, e.g. '1d'. |         |

.PARAMETER ChangeYoungerThan
| Name              | Type          | Description                                                | Default |
|-------------------|---------------|------------------------------------------------------------|---------|
| ChangeYoungerThan | System.String | Keep entries last written within this duration, e.g. '5d'. |         |

.PARAMETER ChangeOlderThan
| Name            | Type          | Description                                                 | Default |
|-----------------|---------------|-------------------------------------------------------------|---------|
| ChangeOlderThan | System.String | Keep entries last written longer ago than this, e.g. '10d'. |         |

.PARAMETER CreationTimeEqual
| Name              | Type          | Description                                               | Default |
|-------------------|---------------|-----------------------------------------------------------|---------|
| CreationTimeEqual | System.String | Keep entries created on the day this long ago, e.g. '1d'. |         |

.PARAMETER CreationYoungerThan
| Name                | Type          | Description                                           | Default |
|---------------------|---------------|-------------------------------------------------------|---------|
| CreationYoungerThan | System.String | Keep entries created within this duration, e.g. '5d'. |         |

.PARAMETER CreationOlderThan
| Name              | Type          | Description                                            | Default |
|-------------------|---------------|--------------------------------------------------------|---------|
| CreationOlderThan | System.String | Keep entries created longer ago than this, e.g. '10d'. |         |

.PARAMETER AccessYoungerThan
| Name              | Type          | Description                                                 | Default |
|-------------------|---------------|-------------------------------------------------------------|---------|
| AccessYoungerThan | System.String | Keep entries last accessed within this duration, e.g. '5d'. |         |

.PARAMETER AccessOlderThan
| Name            | Type          | Description                                                  | Default |
|-----------------|---------------|--------------------------------------------------------------|---------|
| AccessOlderThan | System.String | Keep entries last accessed longer ago than this, e.g. '10d'. |         |

.PARAMETER FileSizeGreaterThan
| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeGreaterThan | System.String | Keep files larger than this size, e.g. '20MB'. |         |

.PARAMETER FileSizeSmallerThan
| Name                | Type          | Description                                    | Default |
|---------------------|---------------|------------------------------------------------|---------|
| FileSizeSmallerThan | System.String | Keep files smaller than this size, e.g. '5MB'. |         |

.PARAMETER IncludeFileList
| Name            | Type                                         | Description                               | Default |
|-----------------|----------------------------------------------|-------------------------------------------|---------|
| IncludeFileList | System.Management.Automation.SwitchParameter | Also return every kept entry in FileList. | False   |

.PARAMETER IgnoreMissingPath
| Name              | Type                                         | Description                                                    | Default |
|-------------------|----------------------------------------------|----------------------------------------------------------------|---------|
| IgnoreMissingPath | System.Management.Automation.SwitchParameter | Return an empty result instead of an error for a missing path. | False   |

.OUTPUTS
System.Collections.Hashtable -- Path, Exists, FileCount, FolderCount, TotalCount,
TotalSize, LargestFile, SmallestFile and AverageSize (sizes in bytes, the smallest
file is 0 when no file was kept) and FileList (the kept System.IO.FileSystemInfo
entries, empty unless IncludeFileList is set). Returns an IcingaError on failure.

.EXAMPLE
PS> Get-IcingaDirectoryInformation -Path 'C:\Backup' -FileNames '*.bak' -ChangeYoungerThan '1d'

Counts the backup files written within the last day.

.EXAMPLE
PS> Get-IcingaDirectoryInformation -Path 'D:\Logs' -Recurse -FileSizeGreaterThan '100MB' -IncludeFileList

Returns every log file larger than 100MB below D:\Logs together with the statistics.

.NOTES
Reads the file system through System.IO.DirectoryInfo; the user needs list
permission on every scanned directory. Relative paths are resolved against the
current PowerShell file system location. No external services are used.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-IcingaDirectoryInformation()
{
    param (
        [string]$Path                = '',
        [array]$FileNames            = @( '*' ),
        [switch]$Recurse             = $false,
        [string]$ChangeTimeEqual     = '',
        [string]$ChangeYoungerThan   = '',
        [string]$ChangeOlderThan     = '',
        [string]$CreationTimeEqual   = '',
        [string]$CreationYoungerThan = '',
        [string]$CreationOlderThan   = '',
        [string]$AccessYoungerThan   = '',
        [string]$AccessOlderThan     = '',
        [string]$FileSizeGreaterThan = '',
        [string]$FileSizeSmallerThan = '',
        [switch]$IncludeFileList     = $false,
        [switch]$IgnoreMissingPath   = $false
    );

    if ([string]::IsNullOrEmpty($Path)) {
        return (Write-FunctionReturnValue -ReturnValue 'DirectoryPathMissing' -Data @{ } -OverrideReturn (('IcingaError' -as [type])::new('DirectoryPathMissing', 'No directory path was provided', @{ })));
    }

    # Every filter value is converted once, so the scan only compares against fixed limits.
    [hashtable]$Limits = @{ };

    foreach ($Filter in @(
            @('ChangeTimeEqual', $ChangeTimeEqual, 'Time'),
            @('ChangeYoungerThan', $ChangeYoungerThan, 'Time'),
            @('ChangeOlderThan', $ChangeOlderThan, 'Time'),
            @('CreationTimeEqual', $CreationTimeEqual, 'Time'),
            @('CreationYoungerThan', $CreationYoungerThan, 'Time'),
            @('CreationOlderThan', $CreationOlderThan, 'Time'),
            @('AccessYoungerThan', $AccessYoungerThan, 'Time'),
            @('AccessOlderThan', $AccessOlderThan, 'Time'),
            @('FileSizeGreaterThan', $FileSizeGreaterThan, 'Data'),
            @('FileSizeSmallerThan', $FileSizeSmallerThan, 'Data')
        )) {
        if ([string]::IsNullOrEmpty($Filter[1])) {
            continue;
        }

        [string]$DefaultUnit = 's';

        if ($Filter[2] -eq 'Data') {
            $DefaultUnit = 'B';
        }

        $Unit = ConvertTo-IcingaUnit -InputValue $Filter[1] -InputUnit $DefaultUnit;

        if ($null -eq $Unit -or $Unit.Family -ne $Filter[2]) {
            [string]$Expected = 'duration such as 20d, 12h or 30m';

            if ($Filter[2] -eq 'Data') {
                $Expected = 'size such as 20MB or 1.5GiB';
            }

            [hashtable]$ErrorData = @{ 'Path' = $Path; 'Filter' = $Filter[0]; 'Value' = $Filter[1]; };

            return (Write-FunctionReturnValue -ReturnValue 'DirectoryFilterInvalid' -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new('DirectoryFilterInvalid', [string]::Format('The value "{0}" of -{1} is not a valid {2}', $Filter[1], $Filter[0], $Expected), $ErrorData)));
        }

        $Limits[$Filter[0]] = [System.Math]::Abs([double]$Unit.BaseValue);
    }

    [datetime]$Now  = [datetime]::Now;
    $ChangeDay      = $null;
    $ChangeAfter    = $null;
    $ChangeBefore   = $null;
    $CreationDay    = $null;
    $CreationAfter  = $null;
    $CreationBefore = $null;
    $AccessAfter    = $null;
    $AccessBefore   = $null;
    $SizeAbove      = $null;
    $SizeBelow      = $null;

    if ($Limits.ContainsKey('ChangeTimeEqual')) {
        $ChangeDay = $Now.AddSeconds(-$Limits['ChangeTimeEqual']).Date;
    }
    if ($Limits.ContainsKey('ChangeYoungerThan')) {
        $ChangeAfter = $Now.AddSeconds(-$Limits['ChangeYoungerThan']);
    }
    if ($Limits.ContainsKey('ChangeOlderThan')) {
        $ChangeBefore = $Now.AddSeconds(-$Limits['ChangeOlderThan']);
    }
    if ($Limits.ContainsKey('CreationTimeEqual')) {
        $CreationDay = $Now.AddSeconds(-$Limits['CreationTimeEqual']).Date;
    }
    if ($Limits.ContainsKey('CreationYoungerThan')) {
        $CreationAfter = $Now.AddSeconds(-$Limits['CreationYoungerThan']);
    }
    if ($Limits.ContainsKey('CreationOlderThan')) {
        $CreationBefore = $Now.AddSeconds(-$Limits['CreationOlderThan']);
    }
    if ($Limits.ContainsKey('AccessYoungerThan')) {
        $AccessAfter = $Now.AddSeconds(-$Limits['AccessYoungerThan']);
    }
    if ($Limits.ContainsKey('AccessOlderThan')) {
        $AccessBefore = $Now.AddSeconds(-$Limits['AccessOlderThan']);
    }
    if ($Limits.ContainsKey('FileSizeGreaterThan')) {
        $SizeAbove = [long]$Limits['FileSizeGreaterThan'];
    }
    if ($Limits.ContainsKey('FileSizeSmallerThan')) {
        $SizeBelow = [long]$Limits['FileSizeSmallerThan'];
    }

    [bool]$HasChangeFilter   = ($null -ne $ChangeDay -or $null -ne $ChangeAfter -or $null -ne $ChangeBefore);
    [bool]$HasCreationFilter = ($null -ne $CreationDay -or $null -ne $CreationAfter -or $null -ne $CreationBefore);
    [bool]$HasAccessFilter   = ($null -ne $AccessAfter -or $null -ne $AccessBefore);
    [bool]$HasSizeFilter     = ($null -ne $SizeAbove -or $null -ne $SizeBelow);

    [bool]$MatchAll          = ($FileNames.Count -eq 0);
    [array]$Patterns         = @();

    foreach ($Name in $FileNames) {
        if ([string]$Name -eq '*') {
            $MatchAll = $true;
            break;
        }

        # Eagerly evaluate IsMatch('') so malformed bracket patterns (such as '[unclosed') trigger
        # WildcardPatternException immediately and return a structured DirectoryFilterInvalid IcingaError
        try {
            $CompiledPattern = [System.Management.Automation.WildcardPattern]::new([string]$Name, [System.Management.Automation.WildcardOptions]::IgnoreCase);
            [void]$CompiledPattern.IsMatch('');
            $Patterns       += $CompiledPattern;
        } catch {
            [hashtable]$PatternErrorData = @{ 'Path' = $Path; 'Filter' = 'FileNames'; 'Value' = [string]$Name; 'Error' = $_.Exception.Message; };
            return (Write-FunctionReturnValue -ReturnValue 'DirectoryFilterInvalid' -Data $PatternErrorData -OverrideReturn (('IcingaError' -as [type])::new('DirectoryFilterInvalid', [string]::Format('The value "{0}" of -FileNames is not a valid wildcard pattern', $Name), $PatternErrorData)));
        }
    }

    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path -Path (Get-Location -PSProvider 'FileSystem').ProviderPath -ChildPath $Path;
    }

    [hashtable]$Result = @{
        'Path'         = $Path;
        'Exists'       = $false;
        'FileCount'    = 0;
        'FolderCount'  = 0;
        'TotalCount'   = 0;
        'TotalSize'    = [long]0;
        'LargestFile'  = [long]0;
        'SmallestFile' = [long]0;
        'AverageSize'  = [double]0;
        'FileList'     = @();
    };

    try {
        $Root             = [System.IO.DirectoryInfo]::new($Path);
        [bool]$RootExists = $Root.Exists;
    } catch {
        [hashtable]$ErrorData = @{ 'Path' = $Path; 'Error' = $_.Exception.Message; };

        return (Write-FunctionReturnValue -ReturnValue 'DirectoryReadFailed' -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new('DirectoryReadFailed', [string]::Format('The directory "{0}" could not be read: {1}', $Path, $_.Exception.Message), $ErrorData)));
    }

    if (-not $RootExists) {
        if ($IgnoreMissingPath) {
            return (Write-FunctionReturnValue -ReturnValue 'DirectoryInformationCollected' -Data @{ 'Path' = $Path; 'Exists' = $false; } -OverrideReturn $Result);
        }

        [hashtable]$ErrorData = @{ 'Path' = $Path; };

        return (Write-FunctionReturnValue -ReturnValue 'DirectoryPathNotFound' -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new('DirectoryPathNotFound', [string]::Format('The directory "{0}" does not exist on this system', $Path), $ErrorData)));
    }

    [System.IO.FileAttributes]$SkipAttributes = [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System;
    [System.IO.FileAttributes]$ReparsePoint   = [System.IO.FileAttributes]::ReparsePoint;

    $Pending                                  = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]';
    $FileList                                 = New-Object 'System.Collections.Generic.List[System.IO.FileSystemInfo]';

    [int]$FileCount                           = 0;
    [int]$FolderCount                         = 0;
    [long]$TotalSize                          = 0;
    [long]$LargestFile                        = 0;
    [long]$SmallestFile                       = -1;

    $Pending.Push($Root);

    while ($Pending.Count -ne 0) {
        $Directory = $Pending.Pop();

        try {
            foreach ($Entry in $Directory.EnumerateFileSystemInfos()) {
                if (($Entry.Attributes -band $SkipAttributes) -ne 0) {
                    continue;
                }

                [bool]$IsDirectory = ($Entry -is [System.IO.DirectoryInfo]);

                # Subdirectories are scanned whether their own name matches or not.
                if ($IsDirectory -and $Recurse -and ($Entry.Attributes -band $ReparsePoint) -eq 0) {
                    $Pending.Push($Entry);
                }

                if (-not $MatchAll) {
                    [bool]$Matched = $false;

                    foreach ($Pattern in $Patterns) {
                        if ($Pattern.IsMatch($Entry.Name)) {
                            $Matched = $true;
                            break;
                        }
                    }

                    if (-not $Matched) {
                        continue;
                    }
                }

                if ($HasChangeFilter) {
                    [datetime]$Changed = $Entry.LastWriteTime;

                    if (($null -ne $ChangeDay -and $Changed.Date -ne $ChangeDay) -or ($null -ne $ChangeAfter -and $Changed -le $ChangeAfter) -or ($null -ne $ChangeBefore -and $Changed -ge $ChangeBefore)) {
                        continue;
                    }
                }

                if ($HasCreationFilter) {
                    [datetime]$Created = $Entry.CreationTime;

                    if (($null -ne $CreationDay -and $Created.Date -ne $CreationDay) -or ($null -ne $CreationAfter -and $Created -le $CreationAfter) -or ($null -ne $CreationBefore -and $Created -ge $CreationBefore)) {
                        continue;
                    }
                }

                if ($HasAccessFilter) {
                    [datetime]$Accessed = $Entry.LastAccessTime;

                    if (($null -ne $AccessAfter -and $Accessed -le $AccessAfter) -or ($null -ne $AccessBefore -and $Accessed -ge $AccessBefore)) {
                        continue;
                    }
                }

                if ($IsDirectory) {
                    # A size filter only ever matches files.
                    if ($HasSizeFilter) {
                        continue;
                    }

                    $FolderCount += 1;
                } else {
                    [long]$Length = $Entry.Length;

                    if ($HasSizeFilter -and (($null -ne $SizeAbove -and $Length -le $SizeAbove) -or ($null -ne $SizeBelow -and $Length -ge $SizeBelow))) {
                        continue;
                    }

                    $FileCount += 1;
                    $TotalSize += $Length;

                    if ($Length -gt $LargestFile) {
                        $LargestFile = $Length;
                    }

                    if ($SmallestFile -lt 0 -or $Length -lt $SmallestFile) {
                        $SmallestFile = $Length;
                    }
                }

                if ($IncludeFileList) {
                    $FileList.Add($Entry);
                }
            }
        } catch {
            # PowerShell may wrap an exception thrown while enumerating, so the cause is
            # searched in the whole exception chain.
            [string]$ReturnCode = 'DirectoryReadFailed';
            [string]$Message    = [string]::Format('The directory "{0}" could not be read: {1}', $Directory.FullName, $_.Exception.Message);
            $Exception          = $_.Exception;

            while ($null -ne $Exception) {
                if ($Exception -is [System.UnauthorizedAccessException] -or $Exception -is [System.Security.SecurityException]) {
                    $ReturnCode = 'DirectoryAccessDenied';
                    $Message    = [string]::Format('Access to the directory "{0}" was denied', $Directory.FullName);
                    break;
                }

                $Exception = $Exception.InnerException;
            }

            [hashtable]$ErrorData = @{ 'Path' = $Path; 'Directory' = $Directory.FullName; 'Error' = $_.Exception.Message; };

            return (Write-FunctionReturnValue -ReturnValue $ReturnCode -Data $ErrorData -OverrideReturn (('IcingaError' -as [type])::new($ReturnCode, $Message, $ErrorData)));
        }
    }

    if ($SmallestFile -lt 0) {
        $SmallestFile = 0;
    }

    $Result['Exists']       = $true;
    $Result['FileCount']    = $FileCount;
    $Result['FolderCount']  = $FolderCount;
    $Result['TotalCount']   = $FileCount + $FolderCount;
    $Result['TotalSize']    = $TotalSize;
    $Result['LargestFile']  = $LargestFile;
    $Result['SmallestFile'] = $SmallestFile;
    $Result['FileList']     = $FileList.ToArray();

    if ($FileCount -ne 0) {
        $Result['AverageSize'] = [System.Math]::Round($TotalSize / $FileCount, 2);
    }

    return (Write-FunctionReturnValue -ReturnValue 'DirectoryInformationCollected' -Data @{ 'Path' = $Path; 'FileCount' = $FileCount; 'FolderCount' = $FolderCount; } -OverrideReturn $Result);
}

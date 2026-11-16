<#
.SYNOPSIS
Check the used or free space of the local partitions against thresholds

.DESCRIPTION
Reads every local disk volume through Get-IcingaDiskInformation (Volume
entrypoint) and builds a single IcingaPlugin container named 'Used Partition
Space' (or 'Free Partition
Space' with CheckFreeSpace). Every volume becomes a child check whose value is
the used (or free) space in bytes, evaluated immediately against the warning and
critical thresholds with the volume size as base value. Thresholds therefore
accept percentages ('80%'), absolute sizes ('400GB', '1.5TiB') and the full Icinga
range grammar ('10%:' raises an alert below 10 percent).

Volumes with a drive letter are named after the letter ('C'), volumes without
one after their label, or their volume path when they have no label. Include,
Exclude and RequiredPartition match that name (wildcards allowed; 'C', 'C:' and
'C:\' all select drive C). Every RequiredPartition that does not exist on the
host is reported CRITICAL.

Performance data uses the label '<partition>::ifw_partitionspace::used' (or
'::free') in bytes, with the resolved thresholds in bytes and the volume size as
maximum.

A failed volume query is reported as UNKNOWN with its reason. This plugin is
Windows-only because it relies on the Win32_Volume CIM class.

.PARAMETER Warning
| Name    | Type          | Description                                                                   | Default |
|---------|---------------|-------------------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold as percentage, size or Icinga range, e.g. '80%' or '400GB'. |         |

.PARAMETER Critical
| Name     | Type          | Description                                                                    | Default |
|----------|---------------|--------------------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold as percentage, size or Icinga range, e.g. '90%' or '450GB'. |         |

.PARAMETER Include
| Name    | Type         | Description                                                         | Default |
|---------|--------------|---------------------------------------------------------------------|---------|
| Include | System.Array | Only check partitions matching these letters or labels (wildcards). | @()     |

.PARAMETER Exclude
| Name    | Type         | Description                                                   | Default |
|---------|--------------|---------------------------------------------------------------|---------|
| Exclude | System.Array | Skip partitions matching these letters or labels (wildcards). | @()     |

.PARAMETER RequiredPartition
| Name              | Type         | Description                                                     | Default |
|-------------------|--------------|-----------------------------------------------------------------|---------|
| RequiredPartition | System.Array | Partitions that must exist; a missing one is reported CRITICAL. | @()     |

.PARAMETER CheckFreeSpace
| Name           | Type                                         | Description                                  | Default |
|----------------|----------------------------------------------|----------------------------------------------|---------|
| CheckFreeSpace | System.Management.Automation.SwitchParameter | Evaluate the free instead of the used space. | False   |

.PARAMETER IgnoreEmptyChecks
| Name              | Type                                         | Description                                                    | Default |
|-------------------|----------------------------------------------|----------------------------------------------------------------|---------|
| IgnoreEmptyChecks | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no partition matches at all. | False   |

.PARAMETER SkipUnknown
| Name        | Type                                         | Description                                                  | Default |
|-------------|----------------------------------------------|--------------------------------------------------------------|---------|
| SkipUnknown | System.Management.Automation.SwitchParameter | Report OK instead of UNKNOWN for a volume without size data. | False   |

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
PS> Invoke-IcingaCheckPartitionSpace -Warning '80%' -Critical '90%'

Warns at 80% and goes critical at 90% used space on any local partition.

.EXAMPLE
PS> Invoke-IcingaCheckPartitionSpace -CheckFreeSpace -Warning '50GB:' -Critical '10%:' -Include 'C', 'D'

Warns when less than 50GB and goes critical when less than 10% are free on C: or D:.

.EXAMPLE
PS> Invoke-IcingaCheckPartitionSpace -Warning '80%' -Critical '90%' -RequiredPartition 'E:' -Verbosity 2

Also reports CRITICAL when E: is missing and lists every partition in the output.

.NOTES
Windows-only. Reads Win32_Volume and MSFT_Partition through
Get-IcingaDiskInformation. The integer exit code is the
return value; an Icinga command wrapper is expected to exit with it.
#>
function Invoke-IcingaCheckPartitionSpace()
{
    param (
        [string]$Warning           = '',
        [string]$Critical          = '',
        [array]$Include            = @(),
        [array]$Exclude            = @(),
        [array]$RequiredPartition  = @(),
        [switch]$CheckFreeSpace    = $false,
        [Alias('MitigateUnknown')]
        [switch]$IgnoreEmptyChecks = $false,
        [switch]$SkipUnknown       = $false,
        [int]$Verbosity            = 0,
        [switch]$NoPerfData        = $false
    );

    [string]$PackageName = 'Used Partition Space';
    [string]$MetricLabel = 'used';

    if ($CheckFreeSpace) {
        $PackageName = 'Free Partition Space';
        $MetricLabel = 'free';
    }

    $CheckPackage            = New-IcingaPlugin $PackageName;
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    # Skip MSFT_Partition mapping because partition space checks only read Win32_Volume capacity and free space
    $Volumes                 = Get-IcingaDiskInformation -Entrypoint 'Volume' -SkipPartitionMapping;

    if (Test-IcingaError -InputObject $Volumes) {
        return $CheckPackage.SetError($Volumes).Compile();
    }

    # Normalize forward slashes to '\' and strip trailing ':', '\' and '/' on both filters and partition names
    # so 'C', 'C:', 'C:\' and NTFS mount points ('C:\Mount\Vol1', 'C:\Mount\Vol1\', 'C:/Mount/Vol1/') match cleanly.
    [array]$IncludeFilter      = @();
    [array]$ExcludeFilter      = @();
    [array]$RequiredNormalized = @();

    foreach ($Pattern in $Include) {
        $IncludeFilter += ([string]$Pattern).Replace('/', '\').TrimEnd(':', '\', '/');
    }

    foreach ($Pattern in $Exclude) {
        $ExcludeFilter += ([string]$Pattern).Replace('/', '\').TrimEnd(':', '\', '/');
    }

    foreach ($ReqEntry in $RequiredPartition) {
        $RequiredNormalized += ([string]$ReqEntry).Replace('/', '\');
    }

    [array]$KnownPartitions = @();

    foreach ($Volume in (ConvertTo-IcingaSortedArray -InputObject @($Volumes.Values) -Property 'Name')) {
        # Prefer the drive letter (without ':'), fall back to the volume label, or use the Win32_Volume Name
        # (such as 'C:\ClusterStorage\Volume1\' for NTFS folder mount points without a drive letter)
        [string]$PartitionName = $Volume.Name;

        if ([string]::IsNullOrEmpty($Volume.DriveLetter) -eq $false) {
            $PartitionName = ([string]$Volume.DriveLetter).Replace(':', '');
        } elseif ([string]::IsNullOrEmpty($Volume.Label) -eq $false) {
            $PartitionName = $Volume.Label;
        }

        [string]$FilterName = $PartitionName.TrimEnd(':', '\', '/');
        $KnownPartitions   += $FilterName;

        if ((Test-IcingaArrayFilter -InputObject $FilterName -Include $IncludeFilter -Exclude $ExcludeFilter) -eq $false) {
            continue;
        }

        [string]$CheckName = [string]::Format('Partition {0}', $PartitionName);

        if ($null -eq $Volume.Size -or $null -eq $Volume.FreeSpace -or $null -eq $Volume.UsedSpace -or $Volume.Size -eq 0) {
            $PartitionCheck = New-IcingaPlugin $CheckName;

            if ($SkipUnknown) {
                $PartitionCheck.SetOk('No partition size available', $true).Commit();
            } else {
                $PartitionCheck.SetError('No partition size available').Commit();
            }

            $CheckPackage.AddCheck($PartitionCheck).Commit();
            continue;
        }

        [uint64]$Value = $Volume.UsedSpace;

        if ($CheckFreeSpace) {
            $Value = $Volume.FreeSpace;
        }

        # Perfdata label: <partition>::ifw_partitionspace::used|free (template auto-derived from the command).
        $CheckPackage.AddCheck(
            (New-IcingaPlugin $CheckName $Value 'B').
                MetricIndex($PartitionName).
                MetricLabel($MetricLabel).
                Warning($Warning).
                Critical($Critical).
                BaseValue($Volume.Size).
                Minimum('0').
                Maximum([string]$Volume.Size).
                CheckRange()
        ).Commit();
    }

    $CheckPackage.AddMissingChecks($RequiredNormalized, $KnownPartitions, 'Partition {0}', 'Mandatory partition not found on host', 'Critical', '[:\\/]+$').Commit();

    if ($CheckPackage.HasChecks() -eq $false) {
        if ($IgnoreEmptyChecks) {
            return $CheckPackage.SetOk('No partition matches the given filter', $true).Compile();
        }

        return $CheckPackage.SetError('No partition matches the given filter').Compile();
    }

    return $CheckPackage.Compile();
}

<#
.SYNOPSIS
Check the used or free space of the local partitions against thresholds

.DESCRIPTION
Queries every local disk volume (Win32_Volume with DriveType 3) once and builds a
single IcingaPlugin container named 'Used Partition Space' (or 'Free Partition
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

This plugin is Windows-only because it relies on the Win32_Volume CIM class.

.PARAMETER Warning
| Name    | Type          | Description                                                                 | Default |
|---------|---------------|-----------------------------------------------------------------------------|---------|
| Warning | System.String | Warning threshold as percentage, size or Icinga range, e.g. '80%' or '400GB'. |       |

.PARAMETER Critical
| Name     | Type          | Description                                                                 | Default |
|----------|---------------|-----------------------------------------------------------------------------|---------|
| Critical | System.String | Critical threshold as percentage, size or Icinga range, e.g. '90%' or '450GB'. |      |

.PARAMETER Include
| Name    | Type         | Description                                                         | Default |
|---------|--------------|---------------------------------------------------------------------|---------|
| Include | System.Array | Only check partitions matching these letters or labels (wildcards). | @()     |

.PARAMETER Exclude
| Name    | Type         | Description                                                  | Default |
|---------|--------------|--------------------------------------------------------------|---------|
| Exclude | System.Array | Skip partitions matching these letters or labels (wildcards). | @()    |

.PARAMETER RequiredPartition
| Name              | Type         | Description                                                     | Default |
|-------------------|--------------|-----------------------------------------------------------------|---------|
| RequiredPartition | System.Array | Partitions that must exist; a missing one is reported CRITICAL. | @()     |

.PARAMETER CheckFreeSpace
| Name           | Type                                         | Description                                       | Default |
|----------------|----------------------------------------------|---------------------------------------------------|---------|
| CheckFreeSpace | System.Management.Automation.SwitchParameter | Evaluate the free instead of the used space.      | False   |

.PARAMETER IgnoreEmptyChecks
| Name              | Type                                         | Description                                                    | Default |
|-------------------|----------------------------------------------|----------------------------------------------------------------|---------|
| IgnoreEmptyChecks | System.Management.Automation.SwitchParameter | Return OK instead of UNKNOWN when no partition matches at all. | False   |

.PARAMETER SkipUnknown
| Name        | Type                                         | Description                                                  | Default |
|-------------|----------------------------------------------|--------------------------------------------------------------|---------|
| SkipUnknown | System.Management.Automation.SwitchParameter | Report OK instead of UNKNOWN for a volume without size data. | False   |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                 | Default |
|-----------|--------------|-----------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config. | 0 |

.PARAMETER NoPerfData
| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

.OUTPUTS
System.Int32 — The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

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
Windows-only. Reads the Win32_Volume CIM class. The integer exit code is the
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

    $CheckPackage         = [IcingaPlugin]::new($PackageName);
    $CheckPackage.Verbose = $Verbosity;

    try {
        [array]$Volumes = Get-CimInstance -ClassName 'Win32_Volume' -Filter 'DriveType = 3' -Property 'Name', 'DriveLetter', 'Label', 'Capacity', 'FreeSpace' -ErrorAction Stop;
    } catch {
        $CheckPackage.SetUnknown([string]::Format('Failed to query the partition information: {0}', $_.Exception.Message), $true).Commit();
        return $CheckPackage.Compile();
    }

    [array]$KnownPartitions = @();
    [int]$CheckCount        = 0;

    foreach ($Volume in ($Volumes | Sort-Object -Property 'Name')) {
        [string]$PartitionName = $Volume.Name;

        # Drive letters are used without their ':' so 'C', 'C:' and 'C:\' all select C.
        if ([string]::IsNullOrEmpty($Volume.DriveLetter) -eq $false) {
            $PartitionName = ([string]$Volume.DriveLetter).Replace(':', '');
        } elseif ([string]::IsNullOrEmpty($Volume.Label) -eq $false) {
            $PartitionName = $Volume.Label;
        }

        $KnownPartitions += $PartitionName;

        if ($Include.Count -ne 0 -and @($Include | Where-Object { $PartitionName -like $_ -or $PartitionName -like ([string]$_ -replace '[:\\/]', '') }).Count -eq 0) {
            continue;
        }

        if (@($Exclude | Where-Object { $PartitionName -like $_ -or $PartitionName -like ([string]$_ -replace '[:\\/]', '') }).Count -ne 0) {
            continue;
        }

        [string]$CheckName = [string]::Format('Partition {0}', $PartitionName);
        $CheckCount++;

        if ($null -eq $Volume.Capacity -or $null -eq $Volume.FreeSpace -or [uint64]$Volume.Capacity -eq 0) {
            $PartitionCheck = [IcingaPlugin]::new($CheckName);

            if ($SkipUnknown) {
                $PartitionCheck.SetOk('No partition size available', $true).Commit();
            } else {
                $PartitionCheck.SetUnknown('No partition size available', $true).Commit();
            }

            $CheckPackage.AddCheck($PartitionCheck).Commit();
            continue;
        }

        [uint64]$Capacity  = $Volume.Capacity;
        [uint64]$FreeSpace = $Volume.FreeSpace;
        [uint64]$Value     = $Capacity - $FreeSpace;

        if ($CheckFreeSpace) {
            $Value = $FreeSpace;
        }

        $PartitionCheck            = [IcingaPlugin]::new($CheckName, $Value, 'B');
        $PartitionCheck.NoPerfData = $NoPerfData;

        # Perfdata label: <partition>::ifw_partitionspace::used|free (template auto-derived from the command).
        $CheckPackage.AddCheck(
            $PartitionCheck.MetricIndex($PartitionName).MetricLabel($MetricLabel).Warning($Warning).Critical($Critical).BaseValue($Capacity).Minimum('0').Maximum([string]$Capacity).CheckRange()
        ).Commit();
    }

    foreach ($Required in $RequiredPartition) {
        if (@($KnownPartitions | Where-Object { $_ -like $Required -or $_ -like ([string]$Required -replace '[:\\/]', '') }).Count -ne 0) {
            continue;
        }

        $CheckPackage.AddCheck(
            [IcingaPlugin]::new([string]::Format('Partition {0}', ([string]$Required -replace '[:\\/]+$', ''))).SetCritical('Mandatory partition not found on host', $true)
        ).Commit();
        $CheckCount++;
    }

    if ($CheckCount -eq 0) {
        if ($IgnoreEmptyChecks) {
            $CheckPackage.SetOk('No partition matches the given filter', $true).Commit();
        } else {
            $CheckPackage.SetUnknown('No partition matches the given filter', $true).Commit();
        }
    }

    return $CheckPackage.Compile();
}

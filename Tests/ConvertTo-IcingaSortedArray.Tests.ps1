<#
.SYNOPSIS
Pester unit test suite for ConvertTo-IcingaSortedArray in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for ConvertTo-IcingaSortedArray
as part of the Icinga for Windows automated Pester test suite.

.NOTES
Executed via build/Invoke-ModuleTests.ps1 using Pester 5.0+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'ConvertTo-IcingaSortedArray' {
    Context 'Natural order' {
        It 'sorts processor instances numerically with the totals last' {
            $Sorted = ConvertTo-IcingaSortedArray -InputObject @('0,10', '_Total', '1,0', '0,2', '0,_Total', '0,0');
            $Sorted | Should -Be @('0,0', '0,2', '0,10', '0,_Total', '1,0', '_Total');
        }

        It 'compares digit runs by value and text case-insensitively' {
            $Sorted = ConvertTo-IcingaSortedArray -InputObject @('core 10', 'Core 9', 'CORE 1', 'Core 01a');
            $Sorted | Should -Be @('CORE 1', 'Core 01a', 'Core 9', 'core 10');
        }

        It 'compares numbers numerically and puts $null first' {
            $Sorted = ConvertTo-IcingaSortedArray -InputObject @(10, 9, $null, 100);
            $Sorted | Should -Be @($null, 9, 10, 100);
        }

        It 'sorts in descending order' {
            $Sorted = ConvertTo-IcingaSortedArray -InputObject @('b', 'c', 'a') -Descending;
            $Sorted | Should -Be @('c', 'b', 'a');
        }
    }

    Context 'Properties' {
        It 'sorts objects and hashtables by a property' {
            $Objects = @([PSCustomObject]@{ 'Name' = 'Spooler'; }, [PSCustomObject]@{ 'Name' = 'AppInfo'; });
            (ConvertTo-IcingaSortedArray -InputObject $Objects -Property 'Name').Name | Should -Be @('AppInfo', 'Spooler');

            $Tables  = @(@{ 'Name' = 'D:\'; }, @{ 'Name' = 'C:\'; });
            (ConvertTo-IcingaSortedArray -InputObject $Tables -Property 'Name') | ForEach-Object { $_['Name'] } | Should -Be @('C:\', 'D:\');
        }

        It 'breaks ties with the next property' {
            $Partitions = @(
                @{ 'Disk' = 1; 'Partition' = 1; },
                @{ 'Disk' = 0; 'Partition' = 2; },
                @{ 'Disk' = 0; 'Partition' = 1; }
            );
            $Sorted     = ConvertTo-IcingaSortedArray -InputObject $Partitions -Property 'Disk', 'Partition';
            ($Sorted | ForEach-Object { '{0}:{1}' -f $_['Disk'], $_['Partition'] }) | Should -Be @('0:1', '0:2', '1:1');
        }

        It 'keeps equal elements in input order' {
            $Objects = @(
                [PSCustomObject]@{ 'Key' = 'a'; 'Order' = 1; },
                [PSCustomObject]@{ 'Key' = 'b'; 'Order' = 2; },
                [PSCustomObject]@{ 'Key' = 'a'; 'Order' = 3; },
                [PSCustomObject]@{ 'Key' = 'a'; 'Order' = 4; }
            );
            (ConvertTo-IcingaSortedArray -InputObject $Objects -Property 'Key').Order | Should -Be @(1, 3, 4, 2);
            (ConvertTo-IcingaSortedArray -InputObject $Objects -Property 'Key' -Descending).Order | Should -Be @(2, 1, 3, 4);
        }
    }

    Context 'Result shape' {
        It 'returns a new array and leaves the input unchanged' {
            $Input1 = @('b', 'a');
            $Sorted = ConvertTo-IcingaSortedArray -InputObject $Input1;
            $Sorted | Should -Be @('a', 'b');
            $Input1 | Should -Be @('b', 'a');
        }

        It 'returns an array for a single element and an empty array for no element' {
            $Single = ConvertTo-IcingaSortedArray -InputObject @('a');
            ($Single -is [array]) | Should -BeTrue;
            $Single.Count         | Should -Be 1;

            $Empty  = ConvertTo-IcingaSortedArray -InputObject @();
            ($Empty -is [array]) | Should -BeTrue;
            $Empty.Count         | Should -Be 0;
        }
    }
}

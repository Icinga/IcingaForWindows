<#
.SYNOPSIS
Pester unit test suite for Get-IcingaPerformanceCounter in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for Get-IcingaPerformanceCounter
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

Describe 'Get-IcingaPerformanceCounter' {
    BeforeAll {
        # The IcingaPerformanceCounter class is compiled into the module-scoped kernel and is
        # not visible in the test scope. Grab the Script module so we can construct it and call
        # private functions in their own scope (see the testing-module-scoped-classes pattern).
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } | Select-Object -First 1;
    }

    Context 'Uniform result contract' {
        It 'Returns the five-key result hashtable for a stable counter' {
            $result = Get-IcingaPerformanceCounter -Counter '\Memory\Available Bytes';
            $entry  = $result['\Memory\Available Bytes'];
            ($entry.Keys | Sort-Object) -join ',' | Should -Be 'error,help,sample,type,value';
        }

        It 'Reports a plausible value and no error for a valid counter' {
            $result = Get-IcingaPerformanceCounter -Counter '\Memory\Available Bytes';
            $entry  = $result['\Memory\Available Bytes'];
            $entry.error                | Should -BeNullOrEmpty;
            [decimal]$entry.value       | Should -BeGreaterThan 0;
        }

        It 'Returns a nested hashtable keyed by instance for a wildcard counter' {
            $result = Get-IcingaPerformanceCounter -Counter '\PhysicalDisk(*)\Disk Reads/sec';
            $group  = $result['\PhysicalDisk(*)\Disk Reads/sec'];
            $group                  | Should -BeOfType 'System.Collections.Hashtable';
            $group.Keys.Count       | Should -BeGreaterThan 0;
        }

        It 'Returns an empty hashtable when no counter is requested' {
            (Get-IcingaPerformanceCounter -Counter @()).Count | Should -Be 0;
        }
    }

    Context 'Error handling never throws' {
        It 'Surfaces an unknown counter through the error key instead of throwing' {
            $result = Get-IcingaPerformanceCounter -Counter '\ThisCategoryDoesNotExist\Nope';
            $entry  = $result['\ThisCategoryDoesNotExist\Nope'];
            $entry           | Should -Not -BeNullOrEmpty;
            $entry.error     | Should -Not -BeNullOrEmpty;
        }
    }

    Context 'Path parsing' {
        It 'Parses a category, instance and counter' {
            $parsed = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\PhysicalDisk(0 C:)\Disk Reads/sec') };
            $parsed.Category | Should -Be 'PhysicalDisk';
            $parsed.Instance | Should -Be '0 C:';
            $parsed.Counter  | Should -Be 'Disk Reads/sec';
            $parsed.Valid    | Should -Be $true;
        }

        It 'Parses a single-instance counter' {
            $parsed = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\Memory\Available Bytes') };
            $parsed.Category | Should -Be 'Memory';
            $parsed.Instance | Should -Be '';
            $parsed.Valid    | Should -Be $true;
        }

        It 'Marks a malformed path as invalid without throwing' {
            $parsed = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('not a counter path') };
            $parsed.Valid | Should -Be $false;
        }

        It 'Marks paths with unclosed or misplaced parentheses as invalid' {
            $unclosed = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\Processor(\% Processor Time') };
            $unclosed.Valid | Should -Be $false;

            $unopened = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\Processor)\% Processor Time') };
            $unopened.Valid | Should -Be $false;

            $noCat    = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\(_Total)\% Processor Time') };
            $noCat.Valid | Should -Be $false;
        }

        It 'Accepts and normalizes local machine prefixes (\\.\, \\localhost\, \\<MachineName>\)' {
            $dot         = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\\.\Memory\Available Bytes') };
            $dot.Valid    | Should -Be $true;
            $dot.Category | Should -Be 'Memory';
            $dot.Instance | Should -Be '';
            $dot.Counter  | Should -Be 'Available Bytes';

            $localhost   = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\\localhost\Processor(_Total)\% Processor Time') };
            $localhost.Valid    | Should -Be $true;
            $localhost.Category | Should -Be 'Processor';
            $localhost.Instance | Should -Be '_Total';
            $localhost.Counter  | Should -Be '% Processor Time';

            $machinePath = ('\\{0}\PhysicalDisk(*)\Disk Reads/sec' -f [System.Environment]::MachineName);
            $machine     = & $script:IcingaModule { param($p) [IcingaPerformanceCounter]::ParsePath($p) } $machinePath;
            $machine.Valid    | Should -Be $true;
            $machine.Category | Should -Be 'PhysicalDisk';
            $machine.Instance | Should -Be '*';
            $machine.Counter  | Should -Be 'Disk Reads/sec';

            $normalized  = & $script:IcingaModule { [IcingaPerformanceCounter]::NormalizePath('\\.\Processor(_Total)\% Processor Time') };
            $normalized | Should -Be '\Processor(_Total)\% Processor Time';
        }

        It 'Rejects remote machine prefixes and extra path segments' {
            $remote       = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\\REMOTE-SERVER-99\Memory\Available Bytes') };
            $remote.Valid | Should -Be $false;

            $emptyMachine = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\\\Memory\Available Bytes') };
            $emptyMachine.Valid | Should -Be $false;

            $extraSegment = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\Memory\Available Bytes\Extra') };
            $extraSegment.Valid | Should -Be $false;
        }
    }

    Context 'Registration keeps counters warm' {
        It 'New-IcingaPerformanceCounter registers the requested paths' {
            $registered = & $script:IcingaModule {
                New-IcingaPerformanceCounter -Counter @('\Processor(_Total)\% Processor Time');
                (Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered.ContainsKey('\Processor(_Total)\% Processor Time');
            };
            $registered | Should -Be $true;
        }

        It 'Get-IcingaPerformanceCounter refreshes the last-seen timestamp' {
            $seen = & $script:IcingaModule {
                Get-IcingaPerformanceCounter -Counter '\Memory\Available Bytes' | Out-Null;
                (Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered.ContainsKey('\Memory\Available Bytes');
            };
            $seen | Should -Be $true;
        }
    }

    Context 'Show-IcingaPerformanceCounter browse' {
        It 'Lists performance counter categories' {
            (Show-IcingaPerformanceCounter).Count | Should -BeGreaterThan 5;
        }

        It 'Lists counter paths within a category' {
            (Show-IcingaPerformanceCounter -Category 'Memory').Count | Should -BeGreaterThan 1;
        }

        It 'Lists live instances for a wildcard counter' {
            (Show-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time').Count | Should -BeGreaterThan 0;
        }
    }

    Context 'StructureByInstance reshaping' {
        It 'Keys instanced counters by instance, category then counter' {
            $result = Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time' -StructureByInstance;
            $result.ContainsKey('_Total')                                             | Should -Be $true;
            $result['_Total']['Processor']['% Processor Time'].ContainsKey('value')   | Should -Be $true;
        }

        It 'Keys non-instanced counters by category then counter' {
            $result = Get-IcingaPerformanceCounter -Counter '\Memory\Available Bytes' -StructureByInstance;
            $result.ContainsKey('Memory')                                 | Should -Be $true;
            [decimal]$result['Memory']['Available Bytes'].value           | Should -BeGreaterThan 0;
        }

        It 'Combines instanced and non-instanced counters in one structure' {
            $result = Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time', '\Memory\Available Bytes' -StructureByInstance;
            $result['_Total']['Processor']['% Processor Time'].ContainsKey('value')   | Should -Be $true;
            [decimal]$result['Memory']['Available Bytes'].value                       | Should -BeGreaterThan 0;
        }

        It 'Keeps accurate values when wildcard and individual instance paths are mixed' {
            $result = Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time', '\Processor(_Total)\% Processor Time' -StructureByInstance;
            $result.ContainsKey('_Total')                                           | Should -Be $true;
            $result['_Total']['Processor']['% Processor Time'].ContainsKey('value') | Should -Be $true;
        }
    }

    Context 'Category snapshots for wildcard paths' {
        It 'Reads every process instance, including the own process' {
            $group      = (Get-IcingaPerformanceCounter -Counter '\Process(*)\ID Process')['\Process(*)\ID Process'];
            [int[]]$Ids = @($group.Values | ForEach-Object { [int]$_.value });
            $Ids | Should -Contain $PID;
        }

        It 'Reports plausible memory and thread values for the own process' {
            $result = Get-IcingaPerformanceCounter -Counter '\Process(*)\ID Process', '\Process(*)\Working Set - Private', '\Process(*)\Thread Count' -StructureByInstance;
            $own    = @($result.Values | Where-Object { $null -ne $_['Process'] -and [int]$_['Process']['ID Process'].value -eq $PID })[0];
            [decimal]$own['Process']['Working Set - Private'].value | Should -BeGreaterThan 0;
            [decimal]$own['Process']['Thread Count'].value          | Should -BeGreaterThan 0;
            $own['Process']['Thread Count'].help                    | Should -Not -BeNullOrEmpty;
        }

        It 'Returns the live instances of the category' {
            $group    = (Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time')['\Processor(*)\% Processor Time'];
            $expected = @((New-Object System.Diagnostics.PerformanceCounterCategory('Processor')).GetInstanceNames() | ForEach-Object { '\Processor({0})\% Processor Time' -f $_ } | Sort-Object);
            @($group.Keys | Sort-Object) | Should -Be $expected;
        }

        It 'Calculates rate counters between two snapshots' {
            $group = (Get-IcingaPerformanceCounter -Counter '\Processor(*)\% Processor Time')['\Processor(*)\% Processor Time'];
            foreach ($entry in $group.Values) {
                $entry.error          | Should -BeNullOrEmpty;
                [decimal]$entry.value | Should -BeGreaterOrEqual 0;
                [decimal]$entry.value | Should -BeLessOrEqual 100;
            }
        }

        It 'Reports an error for every instance of an unknown counter' {
            $group = (Get-IcingaPerformanceCounter -Counter '\Processor(*)\No Such Counter')['\Processor(*)\No Such Counter'];
            $group.Count | Should -BeGreaterThan 0;
            foreach ($entry in $group.Values) {
                $entry.error | Should -Match 'does not exist';
            }
        }

        It 'Returns no instances for an unknown category' {
            (Get-IcingaPerformanceCounter -Counter '\IcingaNoSuchCategory(*)\Counter')['\IcingaNoSuchCategory(*)\Counter'].Count | Should -Be 0;
        }

        It 'Returns no instances for a single-instance category' {
            (Get-IcingaPerformanceCounter -Counter '\Memory(*)\Available Bytes')['\Memory(*)\Available Bytes'].Count | Should -Be 0;
        }
    }

    Context 'Get-IcingaPerformanceCounterValue' {
        It 'Returns the numeric value for a healthy counter' {
            $data  = Get-IcingaPerformanceCounter -Counter '\Memory\Available Bytes' -StructureByInstance;
            $value = & $script:IcingaModule { param($o) Get-IcingaPerformanceCounterValue -InputObject $o } $data['Memory']['Available Bytes'];
            $value | Should -BeOfType 'System.Decimal';
            $value | Should -BeGreaterThan 0;
        }

        It 'Returns the error string when the counter reported an error' {
            $data  = Get-IcingaPerformanceCounter -Counter '\Processor(999)\% Processor Time' -StructureByInstance;
            $value = & $script:IcingaModule { param($o) Get-IcingaPerformanceCounterValue -InputObject $o } $data['999']['Processor']['% Processor Time'];
            $value | Should -BeOfType 'System.String';
            $value | Should -Not -BeNullOrEmpty;
        }

        It 'Returns $null for input that is not a counter value object' {
            $value = & $script:IcingaModule { Get-IcingaPerformanceCounterValue -InputObject 42 };
            $value | Should -BeNullOrEmpty;
        }
    }

    Context 'Show-IcingaPerformanceCounterDetails' {
        It 'Returns the value for a specific counter' {
            $result = Show-IcingaPerformanceCounterDetails -Counter '\Memory\Available Bytes';
            [decimal]$result['\Memory\Available Bytes'].value | Should -BeGreaterThan 0;
        }
    }

    Context 'Test-IcingaPerformanceCounterCategory and category error inspection' {
        It 'Returns false for empty, malformed or non-existent categories' {
            (Test-IcingaPerformanceCounterCategory -Category '')                                   | Should -Be $false;
            (Test-IcingaPerformanceCounterCategory -Category 'IcingaNoSuchCategory')               | Should -Be $false;
            (Test-IcingaPerformanceCounterCategory -Category '\IcingaNoSuchCategory(*)\Counter')   | Should -Be $false;
            (Test-IcingaPerformanceCounterCategory -Category '\\REMOTE-HOST\Processor\Counter')    | Should -Be $false;
        }

        It 'Records the category error on a failed wildcard category snapshot' {
            $err = & $script:IcingaModule {
                $manager = [IcingaPerformanceCounter]::new();
                $manager.WarmupMilliseconds = 0;
                $manager.Resolve([string[]]@('\IcingaNoSuchCategory(*)\Counter')) | Out-Null;
                $msg = $manager.GetCategoryError('IcingaNoSuchCategory');
                $manager.Dispose();
                return $msg;
            };
            $err | Should -Not -BeNullOrEmpty;
        }

        It 'skips registering malformed counter paths, writes BOM-less UTF-8 cache files, and survives daemon timeout disposal races' {
            $MockCacheDir            = Join-Path -Path $TestDrive -ChildPath ('PerfCache_' + [System.Guid]::NewGuid().ToString('N'));
            New-Item -Path $MockCacheDir -ItemType Directory -Force | Out-Null;

            [hashtable]$DaemonSafety = & $script:IcingaModule {
                param ($CacheDir);

                $Store                = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;
                [datetime]$RemovedAt  = [datetime]::MinValue;
                [void]$Store.Registered.TryRemove('not_a_valid_counter', [ref]$RemovedAt);
                Get-IcingaPerformanceCounter -Counter 'not_a_valid_counter' | Out-Null;
                [bool]$InvalidRegistered = $Store.Registered.ContainsKey('not_a_valid_counter');

                $Store.Registered['\Memory\Available Bytes'] = (Get-Date);

                function Get-ModuleCacheDirectory()
                {
                    return $CacheDir;
                }

                Write-IcingaPerformanceCounterCache;
                [string]$CacheFile = Join-Path -Path $CacheDir -ChildPath 'PerformanceCounter.json';
                [byte[]]$RawBytes  = [System.IO.File]::ReadAllBytes($CacheFile);
                [bool]$HasUtf8Bom  = ($RawBytes.Length -ge 3 -and $RawBytes[0] -eq 0xEF -and $RawBytes[1] -eq 0xBB -and $RawBytes[2] -eq 0xBF);

                # Simulate a timed-out caller whose response BlockingCollection was already disposed
                [string]$StaleId   = [System.Guid]::NewGuid().ToString();
                $DisposedQueue     = [System.Collections.Concurrent.BlockingCollection[PSObject]]::new(1);
                $DisposedQueue.Dispose();
                $Store.PendingRequests[$StaleId] = $DisposedQueue;
                $Store.RequestQueue.Add([PSCustomObject]@{
                    'RequestId' = $StaleId;
                    'Counter'   = [string[]]@( '\Memory\Available Bytes' );
                });

                $script:LoopCount  = 0;
                function Test-ThreadRunning()
                {
                    $script:LoopCount++;
                    return ($script:LoopCount -le 1);
                }
                function Set-ThreadProcessing()
                {
                }
                function Update-IcingaPerformanceCounterState()
                {
                    param ($Store = $null);
                }

                Start-IcingaPerformanceCounterDaemon;
                [bool]$StaleRemoved = (-not $Store.PendingRequests.ContainsKey($StaleId));

                return @{
                    'InvalidRegistered' = $InvalidRegistered;
                    'CacheExists'       = (Test-Path -Path $CacheFile);
                    'HasUtf8Bom'        = $HasUtf8Bom;
                    'StaleRemoved'      = $StaleRemoved;
                };
            } $MockCacheDir;

            $DaemonSafety['InvalidRegistered'] | Should -BeFalse;
            $DaemonSafety['CacheExists']       | Should -BeTrue;
            $DaemonSafety['HasUtf8Bom']        | Should -BeFalse;
            $DaemonSafety['StaleRemoved']      | Should -BeTrue;
        }
    }
}

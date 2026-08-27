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

            $noCat = & $script:IcingaModule { [IcingaPerformanceCounter]::ParsePath('\(_Total)\% Processor Time') };
            $noCat.Valid | Should -Be $false;
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
            $group = (Get-IcingaPerformanceCounter -Counter '\Process(*)\ID Process')['\Process(*)\ID Process'];
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
}

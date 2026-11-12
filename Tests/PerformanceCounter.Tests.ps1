$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Performance counter subsystem performance' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } | Select-Object -First 1;
    }

    Context 'Batch warm-up uses a single shared sleep' {
        It 'Warms eight counters in far less than eight warm-up windows' {
            # The manager must prime a batch of new counters and then sleep once, not once per
            # counter. With a 250 ms window, eight counters warmed serially would cost ~2000 ms;
            # the batched implementation must stay well under that.
            $elapsed = & $script:IcingaModule {
                $counters = @(
                    '\Processor(_Total)\% Processor Time',
                    '\Processor(_Total)\% Idle Time',
                    '\Processor(_Total)\% User Time',
                    '\Processor(_Total)\% Privileged Time',
                    '\Memory\Available Bytes',
                    '\Memory\Committed Bytes',
                    '\Memory\Cache Bytes',
                    '\System\Processor Queue Length'
                );

                # Pre-initialize the perflib for these categories in a throwaway manager (no sleep) so
                # the measurement below is not dominated by the one-time first-access cost, which is
                # large on Windows PowerShell 5.1 and would otherwise mask the batching behavior.
                $warm = [IcingaPerformanceCounter]::new();
                $warm.WarmupMilliseconds = 0;
                $warm.Warmup([string[]]$counters);
                $warm.Dispose();

                $manager = [IcingaPerformanceCounter]::new();
                $manager.WarmupMilliseconds = 250;
                $ms = (Measure-Command { $manager.Warmup([string[]]$counters) }).TotalMilliseconds;
                $manager.Dispose();
                $ms;
            };

            # Eight counters warmed serially would cost ~2000 ms (8 x 250 ms). With one shared sleep
            # and the perflib already initialized, the batch stays comfortably under a single second.
            $elapsed | Should -BeLessThan 1000;
        }
    }

    Context 'Warm reads are fast' {
        It 'Reads an already-warm counter without an extra warm-up sleep' {
            $elapsed = & $script:IcingaModule {
                $manager = [IcingaPerformanceCounter]::new();
                $manager.WarmupMilliseconds = 250;
                $manager.Warmup([string[]]@('\Memory\Available Bytes'));
                # Do one throwaway read first to absorb first-access perflib init and JIT, so the
                # measurement isolates the warm-read cost and proves no warm-up sleep is paid again.
                $manager.Resolve([string[]]@('\Memory\Available Bytes')) | Out-Null;
                $ms = (Measure-Command { $manager.Resolve([string[]]@('\Memory\Available Bytes')) }).TotalMilliseconds;
                $manager.Dispose();
                $ms;
            };

            # Comfortably below the 250 ms warm-up window: a warm read must not sleep.
            $elapsed | Should -BeLessThan 150;
        }
    }

    Context 'Category snapshots' {
        It 'Reads wildcard paths through one snapshot per category without counter handles' {
            $state = & $script:IcingaModule {
                $manager = [IcingaPerformanceCounter]::new();
                $manager.WarmupMilliseconds = 250;
                $manager.Warmup([string[]]@('\Process(*)\ID Process', '\Process(*)\Thread Count', '\Memory\Available Bytes'));
                $state = @{ 'Categories' = @($manager.Categories.Keys); 'Counters' = @($manager.Counters.Keys); };
                $manager.Dispose();
                $state;
            };

            $state['Categories'] | Should -Be @('Process');
            $state['Counters']   | Should -Be @('\Memory\Available Bytes');
        }

        It 'Reads five counters of every process quickly once warm' {
            $elapsed = & $script:IcingaModule {
                [string[]]$counters = @(
                    '\Process(*)\ID Process',
                    '\Process(*)\% Processor Time',
                    '\Process(*)\Working Set - Private',
                    '\Process(*)\Page File Bytes',
                    '\Process(*)\Thread Count'
                );
                $manager = [IcingaPerformanceCounter]::new();
                $manager.WarmupMilliseconds = 250;
                $manager.Resolve($counters) | Out-Null;
                $ms = (Measure-Command { $manager.Resolve($counters) }).TotalMilliseconds;
                $manager.Dispose();
                $ms;
            };

            $elapsed | Should -BeLessThan 300;
        }

        It 'Drops the snapshot of a category that is no longer registered' {
            $counts = & $script:IcingaModule {
                $manager = [IcingaPerformanceCounter]::new();
                $manager.WarmupMilliseconds = 0;
                $manager.Reconcile([string[]]@('\Processor(*)\% Processor Time'));
                $before = $manager.Categories.Count;
                $manager.Reconcile([string[]]@());
                $after = $manager.Categories.Count;
                $manager.Dispose();
                @($before, $after);
            };

            $counts | Should -Be @(1, 0);
        }
    }

    Context 'Handle lifecycle does not leak' {
        It 'Keeps the OS handle count bounded across many transient reads' {
            $isSafe = & $script:IcingaModule {
                [System.GC]::Collect();
                Start-Sleep -Milliseconds 500;
                $handlesBefore = (Get-Process -Id $PID).HandleCount;

                for ($i = 0; $i -lt 30; $i++) {
                    [IcingaPerformanceCounter]::ResolveOnce([string[]]@('\Memory\Available Bytes', '\Processor(_Total)\% Processor Time'), 20) | Out-Null;
                }

                [System.GC]::Collect();
                Start-Sleep -Milliseconds 500;
                $handlesAfter = (Get-Process -Id $PID).HandleCount;

                Write-Host ([string]::Format('PerformanceCounter Handles Before: {0}, After: {1}', $handlesBefore, $handlesAfter));

                ($handlesAfter -le ($handlesBefore + 100));
            };

            $isSafe | Should -Be $true;
        }
    }
}

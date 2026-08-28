$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'IcingaPlugin' {
    BeforeAll {
        # Class types defined in the dot-sourced kernel are not visible in the test
        # scope, so grab the script module and construct plugins in its scope. This
        # must live in BeforeAll (run phase) so it survives Pester's discovery phase.
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        # Remember the daemon switch so the shared runtime state is restored after the
        # suite; otherwise a test run would leave the session in daemon mode and later
        # interactive checks would print nothing.
        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        # Run every check in daemon mode so Compile writes NO console output during
        # the test run (System.Console output cannot be swallowed with | Out-Null).
        # The result is still stored in Private.Icinga.CheckResult, which every
        # assertion reads. The CLI console path is covered separately with a captured
        # System.Console redirect so it, too, prints nothing.
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    Context 'Leaf checks' {
        It 'evaluates a value inside the thresholds as OK and returns exit code 0' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 5, '%').Warning('80').Critical('90').CheckRange().Compile()
            };
            $ExitCode | Should -Be 0;
        }

        It 'raises WARNING when the warning threshold is exceeded' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 85, '%').Warning('80').Critical('90').CheckRange().Compile()
            };
            $ExitCode | Should -Be 1;
        }

        It 'raises CRITICAL when the critical threshold is exceeded' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 95, '%').Warning('80').Critical('90').CheckRange().Compile()
            };
            $ExitCode | Should -Be 2;
        }

        It 'renders the leaf output as "[STATE] Name: message"' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 95, '%').Warning('80').Critical('90').CheckRange().Compile()
            } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match '^\[CRITICAL\] Load: ';
        }

        It 'appends the display unit to the value and thresholds in the message' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 95, '%').Warning('80').Critical('90').CheckRange().Compile()
            } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[CRITICAL] Load: 95% is greater than threshold 90%';
        }

        It 'produces a single perfdata metric in the check_multi index::ifw_template::label format' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 95, '%').Warning('80').Critical('90').Minimum('0').Maximum('100').CheckRange().Compile()
            } | Out-Null;
            $Perf = $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData;
            $Perf.Count | Should -Be 1;
            # No metric parts set and no command on the stack -> fallbacks default / ifw_check / <name>.
            $Perf[0]    | Should -Be 'default::ifw_check::load=95%;80;90;0;100';
        }

        It 'builds the check_multi label from explicit MetricIndex/MetricName/MetricLabel' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Free Partition Space').
                    AddCheck([IcingaPlugin]::new('C', 41.28, 'GiB').MetricIndex('c').MetricName('partitionspace').MetricLabel('free').Warning('80').Critical('90').Maximum('254').CheckRange()).
                    AddCheck([IcingaPlugin]::new('D', 95.67, 'MiB').MetricIndex('d').MetricName('partitionspace').MetricLabel('free').Warning('80').Critical('90').Maximum('786').CheckRange()).
                    Compile()
            } | Out-Null;
            $Perf = $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData;
            $Perf.Count | Should -Be 2;
            $Perf[0]    | Should -Be 'c::ifw_partitionspace::free=41.28GiB;80;90;;254';
            ($Perf -join ' ') | Should -Be 'c::ifw_partitionspace::free=41.28GiB;80;90;;254 d::ifw_partitionspace::free=95.67MiB;80;90;;786';
        }

        It 'sanitizes metric segments and does not double the ifw_ namespace' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('X', 5, '%').MetricIndex('Core #0').MetricName('ifw_cpu').MetricLabel('Load %').CheckRange().Compile()
            } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'core0::ifw_cpu::load=5%;;;;';
        }

        It 'derives the template from the calling Invoke-IcingaCheck* command' {
            & $script:IcingaModule {
                function Invoke-IcingaCheckFoo { [IcingaPlugin]::new('bar', 5, '%').MetricLabel('load').CheckRange().Compile() | Out-Null; }
                Invoke-IcingaCheckFoo
            };
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'default::ifw_foo::load=5%;;;;';
        }

        It 'evaluates greater/lower comparison modes' {
            (& $script:IcingaModule { [IcingaPlugin]::new('X', 95).Critical('90').CheckGreater().Compile() }) | Should -Be 2;
            (& $script:IcingaModule { [IcingaPlugin]::new('X', 5).Critical('10').CheckLower().Compile() })    | Should -Be 2;
        }
    }

    Context 'State overrides' {
        It 'forces the state through SetCritical' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Svc', 5, '%').Warning('80').Critical('90').CheckRange().SetCritical('Service is stopped').Compile()
            };
            $ExitCode | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[CRITICAL] Svc: Service is stopped';
        }

        It 'freezes state and message when locked, ignoring later evaluation' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Svc', 5, '%').Warning('80').Critical('90').CheckRange().SetCritical('forced', $true).CheckRange().Compile()
            } | Out-Null;
            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result.ExitCode | Should -Be 2;
            $Result.Output   | Should -Be '[CRITICAL] Svc: forced';
        }
    }

    Context 'Container aggregation' {
        It 'is OK when all children are OK (default And operator)' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Disks').
                    AddCheck([IcingaPlugin]::new('C:', 55, '%').Warning('80').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('D:', 60, '%').Warning('80').Critical('90').CheckRange()).
                    Compile()
            };
            $ExitCode | Should -Be 0;
        }

        It 'takes the worst child state with the And operator' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Disks').
                    AddCheck([IcingaPlugin]::new('C:', 55, '%').Warning('80').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('D:', 95, '%').Warning('80').Critical('90').CheckRange()).
                    CheckAnd().Compile()
            };
            $ExitCode | Should -Be 2;
        }

        It 'is OK with the Or operator when at least one child is OK' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Any').
                    AddCheck([IcingaPlugin]::new('A', 95, '%').Warning('80').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('B', 5, '%').Warning('80').Critical('90').CheckRange()).
                    CheckOr().Compile()
            };
            $ExitCode | Should -Be 0;
        }

        It 'honours CheckMinimum independently of the And rule' {
            # Enough OK children -> OK, even though one child is CRITICAL (no And leak).
            (& $script:IcingaModule {
                [IcingaPlugin]::new('Grp').
                    AddCheck([IcingaPlugin]::new('a', 5, '%').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('b', 5, '%').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('c', 5, '%').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('d', 95, '%').Critical('90').CheckRange()).
                    CheckMinimum(3).Compile()
            }) | Should -Be 0;

            # Fewer than the minimum OK -> escalate to the worst child state.
            (& $script:IcingaModule {
                [IcingaPlugin]::new('Grp').
                    AddCheck([IcingaPlugin]::new('a', 5, '%').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('b', 95, '%').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('c', 95, '%').Critical('90').CheckRange()).
                    CheckMinimum(3).Compile()
            }) | Should -Be 2;
        }

        It 'renders the summary header and the indented child tree at the root' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Disks').
                    AddCheck([IcingaPlugin]::new('C:', 55, '%').Warning('80').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('D:', 95, '%').Warning('80').Critical('90').CheckRange()).
                    CheckAnd().Compile()
            } | Out-Null;
            $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
            $Output | Should -Match '^\[CRITICAL\] Disks: 1 Critical 1 Ok \[CRITICAL\] D:';
            $Output | Should -Match "\n\\_ \[CRITICAL\] D:";
        }

        It 'collects perfdata from all children' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Disks').
                    AddCheck([IcingaPlugin]::new('C:', 55, '%').Warning('80').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('D:', 95, '%').Warning('80').Critical('90').CheckRange()).
                    Compile()
            } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData.Count | Should -Be 2;
        }
    }

    Context 'Hybrid node (own value and children)' {
        It 'lets the container own check escalate the aggregate state' {
            $ExitCode = & $script:IcingaModule {
                $Cpu = [IcingaPlugin]::new('CPU', 99, '%').Warning('80').Critical('90').CheckRange();
                [void]$Cpu.AddCheck([IcingaPlugin]::new('Core0', 10, '%').Critical('95').CheckRange());
                $Cpu.CheckAnd().Compile()
            };
            $ExitCode | Should -Be 2;
        }
    }

    Context 'Compile output targets' {
        It 'always stores an IcingaCheckResult in the thread-local Private state' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 95, '%').Warning('80').Critical('90').CheckRange().Compile()
            } | Out-Null;
            $Result = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            $Result           | Should -Not -BeNullOrEmpty;
            $Result.ExitCode  | Should -Be 2;
            $Result.Output    | Should -Not -BeNullOrEmpty;
        }

        It 'writes the result to Private without console output in daemon mode' {
            $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Load', 95, '%').Warning('80').Critical('90').CheckRange().Compile()
            };
            $ExitCode | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.ExitCode | Should -Be 2;
        }

        It 'writes output and space-joined perfdata to the console on the CLI path' {
            # Capture the CLI (non-daemon) console write via a StringWriter so the
            # assertion runs without printing anything during the test.
            $Captured = & $script:IcingaModule {
                $Original = [System.Console]::Out;
                $Writer   = [System.IO.StringWriter]::new();
                $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $false;
                [System.Console]::SetOut($Writer);
                try {
                    [IcingaPlugin]::new('Disks').
                        AddCheck([IcingaPlugin]::new('C:', 95, '%').Warning('80').Critical('90').CheckRange()).
                        Compile() | Out-Null;
                } finally {
                    [System.Console]::SetOut($Original);
                }
                return $Writer.ToString();
            };
            $Captured | Should -Match "\| default::ifw_check::c=95%;80;90;;";
        }
    }

    Context 'Verbosity and summary header' {
        It 'counts every leaf check in the header recursively, including OK, excluding containers' {
            & $script:IcingaModule {
                $Sub = [IcingaPlugin]::new('Cores').
                    AddCheck([IcingaPlugin]::new('Core0', 99, '%').Critical('95').CheckRange()).
                    AddCheck([IcingaPlugin]::new('Core1', 10, '%').Critical('95').CheckRange());
                [IcingaPlugin]::new('CPU').AddCheck($Sub).Compile()
            } | Out-Null;
            $Header = ($Global:IcingaForWindows.Private.Icinga.CheckResult.Output -split "`n")[0];
            $Header | Should -Match '^\[CRITICAL\] CPU: 1 Critical 1 Ok \[CRITICAL\] Core0';
            $Header | Should -Not -Match 'Cores';
        }

        It 'prunes OK leaves from the tree at verbosity 0 but still counts them in the header' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('Disks').
                    AddCheck([IcingaPlugin]::new('C:', 55, '%').Warning('80').Critical('90').CheckRange()).
                    AddCheck([IcingaPlugin]::new('D:', 95, '%').Warning('80').Critical('90').CheckRange()).
                    Compile()
            } | Out-Null;
            $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
            $Output | Should -Match '1 Critical 1 Ok';
            ($Output -split "`n" | Where-Object { $_ -match '\\_ .*C:' }) | Should -BeNullOrEmpty;
        }

        It 'appends the operator configuration at verbosity 3, even when set after building' {
            & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('Disks').
                    AddCheck([IcingaPlugin]::new('C:', 95, '%').Warning('80').Critical('90').CheckRange());
                $Package.Verbose = 3;
                $Package.Compile()
            } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match '\(All must be \[OK\]\)';
        }

        It 'shows no operator configuration for None or notice packages at verbosity 3' {
            $None = & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('Grp').AddCheck([IcingaPlugin]::new('a', 5, '%').Critical('90').CheckRange());
                $Package.CheckNone();
                $Package.Verbose = 3;
                $Package.Compile() | Out-Null;
                return $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
            };
            $None | Should -Not -Match 'must be';

            $Notice = & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('Grp');
                $Package.IsNotice = $true;
                [void]$Package.AddCheck([IcingaPlugin]::new('a', 5, '%').Critical('90').CheckRange());
                $Package.Verbose = 3;
                $Package.Compile() | Out-Null;
                return $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
            };
            $Notice | Should -Not -Match 'must be';
        }
    }

    Context 'Fluent surface' {
        It 'Commit terminates a chain without leaking the node to the pipeline' {
            $Leak = & $script:IcingaModule {
                [IcingaPlugin]::new('X', 5, '%').Warning('80').Critical('90').CheckRange().Commit()
            };
            $Leak | Should -BeNullOrEmpty;
        }
    }
}

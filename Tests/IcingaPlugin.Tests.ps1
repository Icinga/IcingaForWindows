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

        It 'does not count the entries of a notice package in the header' {
            & $script:IcingaModule {
                $List          = [IcingaPlugin]::new('File List');
                $List.IsNotice = $true;
                [void]$List.AddCheck([IcingaPlugin]::new('a.log').SetNotice('1KiB'));
                [void]$List.AddCheck([IcingaPlugin]::new('b.log').SetNotice('2KiB'));

                $Package         = [IcingaPlugin]::new('Directory');
                $Package.Verbose = 2;
                [void]$Package.AddCheck([IcingaPlugin]::new('File Count', 2).Critical('1').CheckRange());
                [void]$Package.AddCheck($List);
                $Package.Compile()
            } | Out-Null;
            $Output = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output;
            ($Output -split "`n")[0] | Should -Be '[CRITICAL] Directory: 1 Critical [CRITICAL] File Count';
            $Output | Should -Match ([regex]::Escape('[INFO] a.log: 1KiB'));
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

    Context 'Byte values' {
        It 'compares bytes against percent thresholds of the base value and renders human-readable sizes' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('C', 442692000000, 'B').Warning('80%').Critical('90%').BaseValue(512000000000).CheckRange().Compile()
            };
            $ExitCode | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[WARNING] C: 412.29GiB (86.46%) is greater than threshold 381.47GiB (80%)';
        }

        It 'writes the resolved percent thresholds in bytes into the perfdata' {
            & $script:IcingaModule {
                [IcingaPlugin]::new('C', 442692000000, 'B').MetricIndex('c').MetricLabel('used').Warning('80%').Critical('90%').BaseValue(512000000000).Minimum('0').Maximum('512000000000').CheckRange().Compile()
            } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'c::ifw_check::used=442692000000B;409600000000;460800000000;0;512000000000';
        }

        It 'keeps absolute size thresholds in their own unit in the message' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('C', 442692000000, 'B').MetricLabel('used').Warning('400GB').Critical('450GB').CheckRange().Compile()
            };
            $ExitCode | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[WARNING] C: 412.29GiB is greater than threshold 400GB';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'default::ifw_check::used=442692000000B;400000000000;450000000000;;';
        }

        It 'resolves percent range thresholds into byte ranges for the perfdata' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('C', 30000000000, 'B').MetricLabel('free').Warning('10%:').Critical('5%:').BaseValue(512000000000).CheckRange().Compile()
            };
            $ExitCode | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[WARNING] C: 27.94GiB (5.86%) is lower than threshold 47.68GiB (10%)';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'default::ifw_check::free=30000000000B;51200000000:;25600000000:;;';
        }

        It 'treats plain-number thresholds of a byte node as bytes' {
            (& $script:IcingaModule { [IcingaPlugin]::new('X', 2048, 'B').Critical('1024').CheckRange().Compile() }) | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[CRITICAL] X: 2KiB is greater than threshold 1024';
        }

        It 'leaves larger data units on the plain display-unit behaviour' {
            (& $script:IcingaModule { [IcingaPlugin]::new('X', 41.28, 'GiB').Warning('80').Critical('90').CheckRange().Compile() }) | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[OK] X: 41.28GiB is ok';
        }
    }

    Context 'Time values' {
        It 'compares seconds against duration thresholds and renders human-readable durations' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Uptime', 3600, 's').MetricLabel('uptime').Warning('30m').Critical('2h').CheckRange().Compile()
            };
            $ExitCode | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[WARNING] Uptime: 1h is greater than threshold 30m';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'default::ifw_check::uptime=3600s;1800;7200;;';
        }

        It 'resolves duration range thresholds into seconds for the perfdata' {
            $ExitCode = & $script:IcingaModule {
                [IcingaPlugin]::new('Uptime', 3600, 's').MetricLabel('uptime').Warning('1d:').CheckRange().Compile()
            };
            $ExitCode | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[WARNING] Uptime: 1h is lower than threshold 1d';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'default::ifw_check::uptime=3600s;86400:;;;';
        }

        It 'decomposes the value into every non-zero unit' {
            (& $script:IcingaModule { [IcingaPlugin]::new('Uptime', 93784, 's').CheckRange().Compile() }) | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[OK] Uptime: 1d 2h 3m 4s is ok';
        }

        It 'renders sub-second durations in milli- and microseconds and keeps seconds in the perfdata' {
            (& $script:IcingaModule { [IcingaPlugin]::new('Latency', 0.004, 's').MetricLabel('read').Warning('0.002').CheckRange().Compile() }) | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[WARNING] Latency: 4ms is greater than threshold 0.002';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData[0] | Should -Be 'default::ifw_check::read=0.004s;0.002;;;';

            (& $script:IcingaModule { [IcingaPlugin]::new('Latency', 0.000412, 's').CheckRange().Compile() }) | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[OK] Latency: 412us is ok';
        }

        It 'treats plain-number thresholds of a time node as seconds' {
            (& $script:IcingaModule { [IcingaPlugin]::new('X', 3600, 's').Critical('1800').CheckRange().Compile() }) | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[CRITICAL] X: 1h is greater than threshold 1800';
        }

        It 'leaves other time units on the plain display-unit behaviour' {
            (& $script:IcingaModule { [IcingaPlugin]::new('X', 250, 'ms').Warning('100').CheckRange().Compile() }) | Should -Be 1;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[WARNING] X: 250ms is greater than threshold 100ms';
        }
    }

    Context 'Error state' {
        It 'reports a formatted error message as UNKNOWN' {
            (& $script:IcingaModule { [IcingaPlugin]::new('CPU Load').SetError('Failed to read {0}', '\Processor(*)').Compile() }) | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] CPU Load: Failed to read \Processor(*)';
        }

        It 'formats up to three comma-separated arguments and an argument array' {
            & $script:IcingaModule { [IcingaPlugin]::new('X').SetError('{0}-{1}', 'a', 'b').Compile() } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] X: a-b';

            & $script:IcingaModule { [IcingaPlugin]::new('X').SetError('{0}-{1}-{2}', 'a', 'b', 'c').Compile() } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] X: a-b-c';

            & $script:IcingaModule { [IcingaPlugin]::new('X').SetError('{0}-{1}-{2}-{3}', @('a', 'b', 'c', 'd')).Compile() } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] X: a-b-c-d';
        }

        It 'keeps a message without arguments verbatim' {
            & $script:IcingaModule { [IcingaPlugin]::new('X').SetError('Volume {1234} is offline').Compile() } | Out-Null;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] X: Volume {1234} is offline';
        }

        It 'reports an IcingaError returned by a data function' {
            $ExitCode = & $script:IcingaModule {
                $Data = [IcingaError]::new('Failed to query {0}', @('Win32_Service'));
                if ($Data -is [IcingaError]) {
                    return [IcingaPlugin]::new('Services').SetError($Data).Compile();
                }
                return 0;
            };
            $ExitCode | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Services: Failed to query Win32_Service';
        }

        It 'shows the error on a container with children instead of the summary header' {
            & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('Disks');
                $Package.Verbose = 2;
                $Package.AddCheck([IcingaPlugin]::new('C', 5, '%').Critical('90').CheckRange()).SetError('Volume data is incomplete').Compile() | Out-Null;
            };
            [array]$Lines = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output -split "`n";
            $Lines[0] | Should -Be '[UNKNOWN] Disks: Volume data is incomplete';
            $Lines[1] | Should -Match '^\\_ \[OK\] C: ';
            $Global:IcingaForWindows.Private.Icinga.CheckResult.ExitCode | Should -Be 3;
        }

        It 'locks the error state against later comparisons' {
            (& $script:IcingaModule { [IcingaPlugin]::new('X', 95, '%').SetError('broken').Critical('90').CheckRange().Compile() }) | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] X: broken';
        }
    }

    Context 'Missing required entries' {
        It 'adds a locked check in the given state for every missing entry' {
            $ExitCode = & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('Services');
                $Package.Verbose = 2;
                $Package.AddMissingChecks(@('Spooler', 'DoesNotExist', 'Other'), @('Spooler', 'WinRM'), '{0}', 'Service not found', 3).Compile();
            };
            $ExitCode | Should -Be 3;

            [array]$Lines = $Global:IcingaForWindows.Private.Icinga.CheckResult.Output -split "`n";
            $Lines.Count | Should -Be 3;
            $Lines[1]    | Should -Be '\_ [UNKNOWN] DoesNotExist: Service not found';
            $Lines[2]    | Should -Be '\_ [UNKNOWN] Other: Service not found';
        }

        It 'matches case-insensitively and with wildcards' {
            $HasChecks = & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('Services');
                $Package.AddMissingChecks(@('spooler', 'Win*'), @('Spooler', 'WinRM'), '{0}', 'Service not found', 3).Commit();
                return $Package.HasChecks();
            };
            $HasChecks | Should -BeFalse;
        }

        It 'compares the normalized entry and uses it in the check name' {
            & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('Used Partition Space');
                $Package.AddMissingChecks(@('C:', 'C:\', 'E:'), @('C', 'D'), 'Partition {0}', 'Mandatory partition not found on host', 2, '[:\\/]+$').Compile() | Out-Null;
            };
            $Global:IcingaForWindows.Private.Icinga.CheckResult.ExitCode | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output   | Should -Match ([regex]::Escape('[CRITICAL] Partition E: Mandatory partition not found on host'));
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output   | Should -Not -Match 'Partition C';
        }

        It 'skips empty entries and survives an invalid pattern' {
            $Names = & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('X');
                $Package.AddMissingChecks(@('', $null, '[abc'), @('abc'), '{0}', 'missing', 2, '(').Commit();
                return @($Package.Checks | ForEach-Object { $_.Name });
            };
            $Names | Should -Be @('[abc');
        }
    }

    Context 'HasChecks' {
        It 'reports whether the node has children' {
            $Result = & $script:IcingaModule {
                $Package = [IcingaPlugin]::new('X');
                $Before  = $Package.HasChecks();
                $Package.AddCheck([IcingaPlugin]::new('a', 5).CheckRange()).Commit();
                return @($Before, $Package.HasChecks());
            };
            $Result | Should -Be @($false, $true);
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

<#
.SYNOPSIS
Pester unit test suite for Install-IcingaForWindows and Event Log wiring in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, Event Log source registration and
100 MiB log sizing, local self-signed PFX certificate creation, Start-LoggingDaemon
resilience, and dynamic -Area propagation across Install-IcingaForWindows,
New-IcingaProtocolCertificate, Register-LoggingWindowsEventLog, Start-LoggingDaemon,
Write-FunctionReturnValue, and Write-LoggingEntry as part of the Icinga for Windows
automated Pester test suite.

.NOTES
Executed via build/Invoke-ModuleTests.ps1 using Pester 5.0+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
$ModulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

class TestDisposableEventLogRecord : System.IDisposable
{
    [long]$MaximumSizeInBytes = 1048576;
    [bool]$SaveCalled         = $false;
    [bool]$DisposeCalled      = $false;
    [bool]$ThrowOnSave        = $false;

    TestDisposableEventLogRecord([long]$InitialSize, [bool]$ShouldThrow)
    {
        $this.MaximumSizeInBytes = $InitialSize;
        $this.ThrowOnSave        = $ShouldThrow;
    }

    [void] SaveChanges()
    {
        if ($this.ThrowOnSave) {
            throw ([System.UnauthorizedAccessException]::new('Access denied saving log configuration'));
        }
        $this.SaveCalled = $true;
    }

    [void] Dispose()
    {
        $this.DisposeCalled = $true;
    }
}

Describe 'Install-IcingaForWindows and Event Log Wiring' {
    BeforeAll {
        $script:IcingaModule        = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalProgramData = $env:ProgramData;
        $script:OriginalOsType      = $Global:IcingaForWindows.Protected.OSType;
        $script:OriginalLogLevel    = $Global:IcingaForWindows.Public.Logging.Level;

        function Clear-TestLoggingQueue()
        {
            $QueuedItem = $null;
            while ($Global:IcingaForWindows.Public.Logging.Queue.TryTake([ref]$QueuedItem, 0)) {
                $QueuedItem = $null;
            }
        }

        function Get-TestLoggingQueueItems()
        {
            [array]$Items = @();
            $QueuedItem   = $null;
            while ($Global:IcingaForWindows.Public.Logging.Queue.TryTake([ref]$QueuedItem, 0)) {
                $Items     += $QueuedItem;
                $QueuedItem = $null;
            }
            return $Items;
        }
    }

    BeforeEach {
        $RawTestProgramData                           = Join-Path -Path $TestDrive -ChildPath ('ProgramData_' + [System.Guid]::NewGuid().ToString('N'));
        New-Item -Path $RawTestProgramData -ItemType Directory -Force | Out-Null;
        $script:TestProgramData                       = (Resolve-Path -Path $RawTestProgramData).ProviderPath;
        $env:ProgramData                              = $script:TestProgramData;
        $Global:IcingaForWindows.Protected.OSType     = $script:OriginalOsType;
        $Global:IcingaForWindows.Public.Logging.Level = 'Debug';
        & $script:IcingaModule { Set-InternalExitCodes; };
        Clear-TestLoggingQueue;
    }

    AfterAll {
        $env:ProgramData                              = $script:OriginalProgramData;
        $Global:IcingaForWindows.Protected.OSType     = $script:OriginalOsType;
        $Global:IcingaForWindows.Public.Logging.Level = $script:OriginalLogLevel;
        & $script:IcingaModule { Set-InternalExitCodes; };
        Clear-TestLoggingQueue;
    }

    Context 'Public Cmdlet Export and Parameter Contract' {
        It 'exports Install-IcingaForWindows publicly with a non-mandatory -Hostname parameter' {
            $ExportedCmd           = Get-Command -Name 'Install-IcingaForWindows' -Module 'IcingaForWindows' -ErrorAction Stop;
            $HostnameParam         = $ExportedCmd.Parameters['Hostname'];
            [array]$MandatoryAttrs = @(
                $HostnameParam.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }
            );

            $ExportedCmd.Name            | Should -Be 'Install-IcingaForWindows';
            $HostnameParam               | Should -Not -BeNullOrEmpty;
            $HostnameParam.ParameterType | Should -Be ([string]);
            $MandatoryAttrs.Count        | Should -Be 0;
        }
    }

    Context 'Missing or Blank -Hostname Validation' {
        It 'aborts with InstallerHostnameMissing (7000) and skips provisioning when -Hostname is omitted, empty, or whitespace' {
            foreach ($InvalidHost in @( $null, '', '   ' )) {
                Clear-TestLoggingQueue;

                [hashtable]$CallState = & $script:IcingaModule {
                    param ($HostArg);

                    $Tracker = @{
                        'ConfigCalled'   = $false;
                        'EventLogCalled' = $false;
                        'CertCalled'     = $false;
                        'ExitCode'       = -1;
                    };

                    function New-ModuleConfigEnvironment()
                    {
                        $Tracker['ConfigCalled'] = $true;
                        return 0;
                    }

                    function Register-LoggingWindowsEventLog()
                    {
                        $Tracker['EventLogCalled'] = $true;
                    }

                    function New-IcingaProtocolCertificate()
                    {
                        param (
                            [string]$CommonName = $null
                        );
                        $null                  = $CommonName;
                        $Tracker['CertCalled'] = $true;
                        return 50011;
                    }

                    if ($null -eq $HostArg) {
                        $Tracker['ExitCode'] = Install-IcingaForWindows;
                    } else {
                        $Tracker['ExitCode'] = Install-IcingaForWindows -Hostname $HostArg;
                    }

                    return $Tracker;
                } $InvalidHost;

                [array]$QueuedLogs    = @(Get-TestLoggingQueueItems);

                $CallState['ExitCode']       | Should -Be 7000;
                $CallState['ConfigCalled']   | Should -BeFalse;
                $CallState['EventLogCalled'] | Should -BeFalse;
                $CallState['CertCalled']     | Should -BeFalse;
                $QueuedLogs.Count            | Should -Be 1;
                $QueuedLogs[0].EventId       | Should -Be 7000;
                $QueuedLogs[0].Level         | Should -Be 'Error';
                $QueuedLogs[0].Area          | Should -Be 'Installer';
            }
        }
    }

    Context 'Provisioning Orchestration and Return-Code Handling' {
        It 'runs config setup, Event Log registration, and certificate creation and returns 7001 for Windows and local cert codes' {
            foreach ($CertCode in @( 50010, 50011 )) {
                Clear-TestLoggingQueue;

                [hashtable]$RunState = & $script:IcingaModule {
                    param ($SimulatedCertCode);

                    $Steps = New-Object System.Collections.ArrayList;
                    $State = @{
                        'Steps'      = $Steps;
                        'CommonName' = '';
                        'ExitCode'   = -1;
                    };

                    function New-ModuleConfigEnvironment()
                    {
                        [void]$Steps.Add('Config');
                        return 0;
                    }

                    function Register-LoggingWindowsEventLog()
                    {
                        [void]$Steps.Add('EventLog');
                    }

                    function New-IcingaProtocolCertificate()
                    {
                        param (
                            [string]$CommonName = $null
                        );
                        [void]$Steps.Add('Certificate');
                        $State['CommonName'] = $CommonName;
                        return $SimulatedCertCode;
                    }

                    $State['ExitCode'] = Install-IcingaForWindows -Hostname '  agent01.local  ';
                    return $State;
                } $CertCode;

                [array]$QueuedLogs   = @(Get-TestLoggingQueueItems);

                $RunState['ExitCode']                    | Should -Be 7001;
                $RunState['CommonName']                  | Should -Be 'agent01.local';
                @($RunState['Steps'])                    | Should -Be @( 'Config', 'EventLog', 'Certificate' );
                $QueuedLogs.Count                        | Should -Be 1;
                $QueuedLogs[0].EventId                   | Should -Be 7001;
                $QueuedLogs[0].Level                     | Should -Be 'Info';
                $QueuedLogs[0].Area                      | Should -Be 'Installer';
                $QueuedLogs[0].Data['Hostname']          | Should -Be 'agent01.local';
                $QueuedLogs[0].Data['CertificateResult'] | Should -Be $CertCode;
            }
        }

        It 'propagates certificate failure codes without emitting InstallerCompleted (7001)' {
            [int]$ExitCode     = & $script:IcingaModule {
                function New-ModuleConfigEnvironment()
                {
                    return 0;
                }

                function Register-LoggingWindowsEventLog()
                {
                    return;
                }

                function New-IcingaProtocolCertificate()
                {
                    param (
                        [string]$CommonName = $null
                    );
                    $null = $CommonName;
                    return 50009;
                }

                return (Install-IcingaForWindows -Hostname 'broken-node.local');
            };

            [array]$QueuedLogs = @(Get-TestLoggingQueueItems);

            $ExitCode         | Should -Be 50009;
            $QueuedLogs.Count | Should -Be 0;
        }

        It 'initializes Public.ReturnCodes from a cold null state before New-ModuleConfigEnvironment and Register-LoggingWindowsEventLog execute' {
            $Global:IcingaForWindows.Public.ReturnCodes = $null;
            Clear-TestLoggingQueue;

            [hashtable]$ColdRunState                    = & $script:IcingaModule {
                $State = @{
                    'CodesReadyAtConfig'   = $false;
                    'CodesReadyAtEventLog' = $false;
                    'HasInstallerCode'     = $false;
                    'ExitCode'             = -1;
                };

                function New-ModuleConfigEnvironment()
                {
                    $CurrentCodes                = (Get-GlobalRuntimeVariable).Public.ReturnCodes;
                    $State['CodesReadyAtConfig'] = ($null -ne $CurrentCodes);
                    return 0;
                }

                function Register-LoggingWindowsEventLog()
                {
                    $CurrentCodes                  = (Get-GlobalRuntimeVariable).Public.ReturnCodes;
                    $State['CodesReadyAtEventLog'] = ($null -ne $CurrentCodes);
                    if ($null -ne $CurrentCodes) {
                        $State['HasInstallerCode'] = $CurrentCodes.ContainsKey('InstallerCompleted');
                    }
                }

                function New-IcingaProtocolCertificate()
                {
                    param (
                        [string]$CommonName = $null
                    );
                    $null = $CommonName;
                    return 50011;
                }

                $State['ExitCode'] = Install-IcingaForWindows -Hostname 'agent01.local';
                return $State;
            };

            $ColdRunState['CodesReadyAtConfig']                     | Should -BeTrue;
            $ColdRunState['CodesReadyAtEventLog']                   | Should -BeTrue;
            $ColdRunState['HasInstallerCode']                       | Should -BeTrue;
            $ColdRunState['ExitCode']                               | Should -Be 7001;
            ($null -ne $Global:IcingaForWindows.Public.ReturnCodes) | Should -BeTrue;
        }

        It 'provisions Config, Binaries, and a valid trimmed self-signed PFX certificate end-to-end in an isolated ProgramData directory' {
            $Global:IcingaForWindows.Protected.OSType = 'Linux';

            [int]$InstallCode                         = Install-IcingaForWindows -Hostname '  node01.local  ';
            [string]$ConfigDir                        = & $script:IcingaModule { Get-ModuleConfigDirectory; };
            [string]$BinaryDir                        = & $script:IcingaModule { Get-ModuleBinaryDirectory; };
            [string]$CertFile                         = Join-Path -Path (& $script:IcingaModule { Get-ModuleCertificateDirectory; }) -ChildPath 'node01.local.pfx';

            $InstallCode                 | Should -Be 7001;
            (Test-Path -Path $ConfigDir) | Should -BeTrue;
            (Test-Path -Path $BinaryDir) | Should -BeTrue;
            (Test-Path -Path $CertFile)  | Should -BeTrue;

            $LoadedCert                               = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertFile);
            try {
                $LoadedCert.Subject       | Should -Be 'CN=node01.local';
                $LoadedCert.HasPrivateKey | Should -BeTrue;
            } finally {
                $LoadedCert.Dispose();
            }
        }

        It 'returns IcingaCertCommonNameMissing (50009) when New-IcingaProtocolCertificate receives null, empty, or whitespace -CommonName' {
            foreach ($InvalidCommonName in @( $null, '', '   ' )) {
                if ($null -eq $InvalidCommonName) {
                    [int]$CertCode = New-IcingaProtocolCertificate;
                } else {
                    [int]$CertCode = New-IcingaProtocolCertificate -CommonName $InvalidCommonName;
                }

                $CertCode | Should -Be 50009;
            }
        }
    }

    Context 'Register-LoggingWindowsEventLog Behavior' {
        It 'returns immediately without invoking Event Log operations on non-Windows platforms' {
            $Global:IcingaForWindows.Protected.OSType = 'Linux';
            Clear-TestLoggingQueue;

            [bool]$Invoked                            = & $script:IcingaModule {
                $script:WasCalled = $false;

                function Get-WinEvent()
                {
                    $script:WasCalled = $true;
                }

                Register-LoggingWindowsEventLog;
                return $script:WasCalled;
            };

            [array]$QueuedLogs                        = @(Get-TestLoggingQueueItems);

            $Invoked          | Should -BeFalse;
            $QueuedLogs.Count | Should -Be 0;
        }

        It 'filters blank Area entries, deduplicates IcingaForWindows::Area sources, and configures 100 MiB log size' {
            $Global:IcingaForWindows.Protected.OSType = 'Windows';
            Clear-TestLoggingQueue;

            $ResizeLogRecord                          = [TestDisposableEventLogRecord]::new(1048576, $false);
            [hashtable]$RegResult                     = & $script:IcingaModule {
                param ($LogRecord);

                Set-InternalExitCodes;
                (Get-GlobalRuntimeVariable).Public.ReturnCodes['SyntheticBlankArea'] = @{
                    'Code'     = 64998;
                    'Message'  = 'Synthetic blank area entry';
                    'Severity' = 'Info';
                    'Area'     = '   ';
                };
                (Get-GlobalRuntimeVariable).Public.ReturnCodes['SyntheticDuplicateInstaller'] = @{
                    'Code'     = 64999;
                    'Message'  = 'Synthetic padded duplicate area entry';
                    'Severity' = 'Info';
                    'Area'     = ' Installer ';
                };
                (Get-GlobalRuntimeVariable).Public.ReturnCodes['SyntheticCaseVariantInstaller'] = @{
                    'Code'     = 64997;
                    'Message'  = 'Synthetic lowercase duplicate area entry';
                    'Severity' = 'Info';
                    'Area'     = ' installer ';
                };

                function Get-WinEvent()
                {
                    param (
                        [string]$ListLog     = $null,
                        [object]$ErrorAction = $null
                    );
                    $null = $ListLog;
                    $null = $ErrorAction;
                    return $LogRecord;
                }

                try {
                    Register-LoggingWindowsEventLog;
                } finally {
                    (Get-GlobalRuntimeVariable).Public.ReturnCodes.Remove('SyntheticBlankArea');
                    (Get-GlobalRuntimeVariable).Public.ReturnCodes.Remove('SyntheticDuplicateInstaller');
                    (Get-GlobalRuntimeVariable).Public.ReturnCodes.Remove('SyntheticCaseVariantInstaller');
                }

                return @{
                    'MaxSize'       = $LogRecord.MaximumSizeInBytes;
                    'SaveCalled'    = $LogRecord.SaveCalled;
                    'DisposeCalled' = $LogRecord.DisposeCalled;
                };
            } $ResizeLogRecord;

            [array]$QueuedLogs                        = @(Get-TestLoggingQueueItems);

            $RegResult['MaxSize']       | Should -Be 104857600;
            $RegResult['SaveCalled']    | Should -BeTrue;
            $RegResult['DisposeCalled'] | Should -BeTrue;

            if ($script:OriginalOsType -ne 'Windows') {
                $QueuedLogs.Count               | Should -Be 1;
                $QueuedLogs[0].Level            | Should -Be 'Warning';
                $QueuedLogs[0].Area             | Should -Be 'Logging';
                $QueuedLogs[0].Data['Error']    | Should -Not -BeNullOrEmpty;

                [array]$FailedSources    = @($QueuedLogs[0].Data['FailedSources']);
                [array]$UniqueSources    = @($QueuedLogs[0].Data['FailedSources'] | Select-Object -Unique);
                [array]$InstallerMatches = @($FailedSources | Where-Object { $_ -ieq 'IcingaForWindows::Installer' });

                $FailedSources.Count                                        | Should -Be $UniqueSources.Count;
                $InstallerMatches.Count                                     | Should -Be 1;
                ($FailedSources -contains 'IcingaForWindows::Installer')    | Should -BeTrue;
                ($FailedSources -contains 'IcingaForWindows::Logging')      | Should -BeTrue;
                ($FailedSources -contains 'IcingaForWindows::')             | Should -BeFalse;
                ($FailedSources -contains 'IcingaForWindows:: Installer ')  | Should -BeFalse;
            } else {
                [bool]$IsElevatedAdmin = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator);

                if ($IsElevatedAdmin) {
                    $QueuedLogs.Count                                                          | Should -Be 0;
                    [System.Diagnostics.EventLog]::SourceExists('IcingaForWindows::Installer') | Should -BeTrue;
                    [System.Diagnostics.EventLog]::SourceExists('IcingaForWindows::Logging')   | Should -BeTrue;
                    [System.Diagnostics.EventLog]::SourceExists('IcingaForWindows::')          | Should -BeFalse;

                    # Re-run immediately on Windows to prove already-existing sources do not emit false warnings on PowerShell 7 or 5.1
                    Clear-TestLoggingQueue;
                    & $script:IcingaModule {
                        function Get-WinEvent()
                        {
                            param (
                                [string]$ListLog     = $null,
                                [object]$ErrorAction = $null
                            );
                            $null = $ListLog;
                            $null = $ErrorAction;
                            return $null;
                        }

                        Register-LoggingWindowsEventLog;
                    };

                    [array]$SecondRunLogs = @(Get-TestLoggingQueueItems);
                    $SecondRunLogs.Count | Should -Be 0;
                } else {
                    $QueuedLogs.Count | Should -BeLessOrEqual 1;

                    if ($QueuedLogs.Count -eq 1) {
                        [array]$FailedSources = @($QueuedLogs[0].Data['FailedSources']);
                        [array]$UniqueSources = @($FailedSources | Select-Object -Unique);

                        $QueuedLogs[0].Level                         | Should -Be 'Warning';
                        $QueuedLogs[0].Area                          | Should -Be 'Logging';
                        $FailedSources.Count                         | Should -Be $UniqueSources.Count;
                        ($FailedSources -contains 'IcingaForWindows::') | Should -BeFalse;
                    }
                }
            }
        }

        It 'always includes IcingaForWindows::Logging even when ReturnCodes contains no explicit Logging area entries' {
            $Global:IcingaForWindows.Protected.OSType = 'Windows';
            Clear-TestLoggingQueue;

            & $script:IcingaModule {
                $GlobalVar                    = Get-GlobalRuntimeVariable;
                $SavedCodes                   = $GlobalVar.Public.ReturnCodes;
                $GlobalVar.Public.ReturnCodes = @{
                    'OnlyInstaller' = @{
                        'Code'     = 7001;
                        'Message'  = 'Installer only';
                        'Severity' = 'Info';
                        'Area'     = 'Installer';
                    };
                };

                function Get-WinEvent()
                {
                    param (
                        [string]$ListLog     = $null,
                        [object]$ErrorAction = $null
                    );
                    $null = $ListLog;
                    $null = $ErrorAction;
                    return $null;
                }

                try {
                    Register-LoggingWindowsEventLog;
                } finally {
                    $GlobalVar.Public.ReturnCodes = $SavedCodes;
                }
            };

            [array]$QueuedLogs = @(Get-TestLoggingQueueItems);

            if ($script:OriginalOsType -ne 'Windows') {
                $QueuedLogs.Count                                           | Should -Be 1;
                ($QueuedLogs[0].Data['FailedSources'] -contains 'IcingaForWindows::Logging')   | Should -BeTrue;
                ($QueuedLogs[0].Data['FailedSources'] -contains 'IcingaForWindows::Installer') | Should -BeTrue;
            } else {
                [bool]$IsElevatedAdmin = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator);
                if ($IsElevatedAdmin) {
                    [System.Diagnostics.EventLog]::SourceExists('IcingaForWindows::Logging') | Should -BeTrue;
                }
            }
        }

        It 'skips SaveChanges when log is already 100 MiB, disposes EventLogConfiguration handles across all paths, and logs a Warning when SaveChanges fails' {
            $Global:IcingaForWindows.Protected.OSType = 'Windows';

            $AlreadySizedRecord                       = [TestDisposableEventLogRecord]::new(104857600, $false);
            [hashtable]$AlreadySizedState             = & $script:IcingaModule {
                param ($LogRecord);

                function Get-WinEvent()
                {
                    param (
                        [string]$ListLog     = $null,
                        [object]$ErrorAction = $null
                    );
                    $null = $ListLog;
                    $null = $ErrorAction;
                    return $LogRecord;
                }

                Register-LoggingWindowsEventLog;
                return @{
                    'SaveCalled'    = $LogRecord.SaveCalled;
                    'DisposeCalled' = $LogRecord.DisposeCalled;
                };
            } $AlreadySizedRecord;

            $AlreadySizedState['SaveCalled']    | Should -BeFalse;
            $AlreadySizedState['DisposeCalled'] | Should -BeTrue;

            {
                & $script:IcingaModule {
                    function Get-WinEvent()
                    {
                        param (
                            [string]$ListLog     = $null,
                            [object]$ErrorAction = $null
                        );
                        $null = $ListLog;
                        $null = $ErrorAction;
                        throw ([System.InvalidOperationException]::new('Log not found'));
                    }

                    Register-LoggingWindowsEventLog;
                };
            } | Should -Not -Throw;

            Clear-TestLoggingQueue;

            $BrokenRecord = [TestDisposableEventLogRecord]::new(1048576, $true);
            {
                & $script:IcingaModule {
                    param ($BrokenLogRecord);

                    function Get-WinEvent()
                    {
                        param (
                            [string]$ListLog     = $null,
                            [object]$ErrorAction = $null
                        );
                        $null = $ListLog;
                        $null = $ErrorAction;
                        return $BrokenLogRecord;
                    }

                    Register-LoggingWindowsEventLog;
                } $BrokenRecord;
            } | Should -Not -Throw;

            [array]$ResizeWarnings = @(
                Get-TestLoggingQueueItems |
                    Where-Object { $_.Message -match 'Failed to update maximum size for Windows Event Log' }
            );

            $BrokenRecord.DisposeCalled                    | Should -BeTrue;
            $ResizeWarnings.Count                          | Should -Be 1;
            $ResizeWarnings[0].Level                       | Should -Be 'Warning';
            $ResizeWarnings[0].Area                        | Should -Be 'Logging';
            $ResizeWarnings[0].Data['MaximumSizeInBytes']  | Should -Be 104857600;
        }
    }

    Context 'Start-LoggingDaemon Cross-Platform and Unregistered-Source Resilience' {
        It 'consumes queued log entries cleanly on non-Windows and survives Windows EventLog exceptions and out-of-range EventIds without terminating the loop' {
            foreach ($SimulatedOs in @( 'Linux', 'Windows' )) {
                $Global:IcingaForWindows.Protected.OSType = $SimulatedOs;
                Clear-TestLoggingQueue;

                [array]$FormattedMessages                 = & $script:IcingaModule {
                    $Captured = New-Object System.Collections.ArrayList;
                    Write-LoggingEntry -Message ('Daemon test on ' + (Get-GlobalRuntimeVariable).Protected.OSType) -Level 'Info' -Area 'Installer';
                    Write-LoggingEntry -Message 'Negative EventId entry' -Level 'Warning' -EventId -5 -Area 'Installer';
                    Write-LoggingEntry -Message 'Overflow EventId entry' -Level 'Warning' -EventId 70000 -Area 'Installer';

                    $script:LoopCount = 0;

                    function Test-ThreadRunning()
                    {
                        $script:LoopCount++;
                        return ($script:LoopCount -le 3);
                    }

                    function Set-ThreadProcessing()
                    {
                        return;
                    }

                    function Format-LoggingConsoleMessage()
                    {
                        param (
                            [string]$Message   = $null,
                            [switch]$GetMsgObj = $false
                        );
                        if ($GetMsgObj) {
                            return $Message;
                        }
                        [void]$Captured.Add($Message);
                    }

                    Start-LoggingDaemon;
                    return @($Captured);
                };

                $FormattedMessages.Count                             | Should -Be 3;
                $FormattedMessages[0]                                | Should -Match ('Daemon test on ' + $SimulatedOs);
                $FormattedMessages[1]                                | Should -Match 'Negative EventId entry';
                $FormattedMessages[2]                                | Should -Match 'Overflow EventId entry';
                $Global:IcingaForWindows.Public.Logging.Queue.Count  | Should -Be 0;
            }
        }
    }

    Context 'Write-LoggingEntry and Write-FunctionReturnValue -Area Resolution' {
        It 'propagates explicit ReturnCodes Area values and falls back to Logging when Area is missing' {
            Clear-TestLoggingQueue;

            [int]$InstallerCode   = & $script:IcingaModule {
                return (Write-FunctionReturnValue -ReturnValue 'InstallerCompleted' -Data @{ 'Hostname' = 'host01.local'; });
            };
            [int]$MissingAreaCode = & $script:IcingaModule {
                return (Write-FunctionReturnValue -ReturnValue 'CommandNotFound');
            };

            [array]$QueuedLogs    = @(Get-TestLoggingQueueItems);

            $InstallerCode         | Should -Be 7001;
            $MissingAreaCode       | Should -Be 40;
            $QueuedLogs.Count      | Should -Be 2;
            $QueuedLogs[0].Area    | Should -Be 'Installer';
            $QueuedLogs[0].EventId | Should -Be 7001;
            $QueuedLogs[1].Area    | Should -Be 'Logging';
            $QueuedLogs[1].EventId | Should -Be 40;
        }

        It 'handles direct Write-LoggingEntry calls with explicit Area, padded Area, omitted/blank Area, uninitialized ReturnCodes, and null Data' {
            Clear-TestLoggingQueue;

            & $script:IcingaModule {
                Write-LoggingEntry -Message 'Explicit area entry' -Level 'Info' -Area 'CustomSubsystem' -Data $null;
                Write-LoggingEntry -Message 'Padded area entry' -Level 'Info' -Area '  Installer  ';
                Write-LoggingEntry -Message 'Default area entry' -Level 'Warning';
                Write-LoggingEntry -Message 'Whitespace area entry' -Level 'Error' -Area '   ';
            };

            $Global:IcingaForWindows.Public.ReturnCodes = $null;
            & $script:IcingaModule {
                Write-LoggingEntry -Message 'Pre-bootstrap fallback entry' -Level 'Info';
            };

            $OriginalGenericArea = $Global:IcingaForWindows.Public.ReturnCodes['EventLogGenericLog']['Area'];
            try {
                $Global:IcingaForWindows.Public.ReturnCodes['EventLogGenericLog']['Area'] = 'GenericOverride';
                & $script:IcingaModule {
                    Write-LoggingEntry -Message 'Dynamic EventLogGenericLog fallback entry' -Level 'Info';
                };

                $Global:IcingaForWindows.Public.ReturnCodes['EventLogGenericLog']['Area'] = '   ';
                & $script:IcingaModule {
                    Write-LoggingEntry -Message 'Blank EventLogGenericLog fallback entry' -Level 'Info';
                };
            } finally {
                $Global:IcingaForWindows.Public.ReturnCodes['EventLogGenericLog']['Area'] = $OriginalGenericArea;
            }

            [array]$QueuedLogs = @(Get-TestLoggingQueueItems);

            ($null -ne $Global:IcingaForWindows.Public.ReturnCodes) | Should -BeTrue;
            $QueuedLogs.Count                                       | Should -Be 7;
            $QueuedLogs[0].Area                                     | Should -Be 'CustomSubsystem';
            $QueuedLogs[0].Data.ContainsKey('LoggingMessageId')     | Should -BeTrue;
            $QueuedLogs[1].Area                                     | Should -Be 'Installer';
            $QueuedLogs[2].Area                                     | Should -Be 'Logging';
            $QueuedLogs[3].Area                                     | Should -Be 'Logging';
            $QueuedLogs[4].Area                                     | Should -Be 'Logging';
            $QueuedLogs[5].Area                                     | Should -Be 'GenericOverride';
            $QueuedLogs[6].Area                                     | Should -Be 'Logging';
        }

        It 'executes Install-IcingaForWindows, Write-FunctionReturnValue, Register-LoggingWindowsEventLog, Write-LoggingEntry, and Start-LoggingDaemon cleanly under Set-StrictMode -Version Latest' {
            [hashtable]$StrictState = @{ 'Result' = $null; };
            {
                $StrictState['Result'] = & $script:IcingaModule {
                    $ErrorActionPreference = 'Stop';
                    Set-StrictMode -Version Latest;
                    $GlobalVar = Get-GlobalRuntimeVariable;

                    function Get-WinEvent()
                    {
                        param (
                            [string]$ListLog     = $null,
                            [object]$ErrorAction = $null
                        );
                        $null = $ListLog;
                        $null = $ErrorAction;
                        return $null;
                    }

                    $GlobalVar.Protected.OSType = 'Linux';
                    [int]$StrictInstallCode     = Install-IcingaForWindows -Hostname 'strict-node.local';
                    [int]$MissingAreaReturnCode = Write-FunctionReturnValue -ReturnValue 'CommandNotFound';

                    $DrainItem                  = $null;
                    [string]$MissingKeyArea     = '';
                    while ($GlobalVar.Public.Logging.Queue.TryTake([ref]$DrainItem, 0)) {
                        if ($DrainItem.EventId -eq 40) {
                            $MissingKeyArea = $DrainItem.Area;
                        }
                        $DrainItem = $null;
                    }

                    $GlobalVar.Protected.OSType = 'Windows';
                    Set-InternalExitCodes;
                    Register-LoggingWindowsEventLog;

                    while ($GlobalVar.Public.Logging.Queue.TryTake([ref]$DrainItem, 0)) {
                        $DrainItem = $null;
                    }

                    $SavedGenericEntry = $GlobalVar.Public.ReturnCodes['EventLogGenericLog'];
                    try {
                        $GlobalVar.Public.ReturnCodes['EventLogGenericLog'] = @{
                            'Code'     = 15;
                            'Message'  = 'Entry with EventLogGenericLog missing Area key';
                            'Severity' = 'Info';
                        };
                        Write-LoggingEntry -Message 'Strict fallback test' -Level 'Info';
                    } finally {
                        $GlobalVar.Public.ReturnCodes['EventLogGenericLog'] = $SavedGenericEntry;
                    }

                    [string]$FallbackArea = '';
                    while ($GlobalVar.Public.Logging.Queue.TryTake([ref]$DrainItem, 0)) {
                        if ($DrainItem.Message -eq 'Strict fallback test') {
                            $FallbackArea = $DrainItem.Area;
                        }
                        $DrainItem = $null;
                    }

                    $GlobalVar.Public.Logging.Queue.Add([PSCustomObject]@{
                        'Message'   = 'Object without Area property';
                        'Level'     = 'Info';
                        'EventId'   = 15;
                        'Data'      = $null;
                        'TimeStamp' = '2026-11-24 14:00:00:0000';
                    });

                    $script:StrictLoop = 0;

                    function Test-ThreadRunning()
                    {
                        $script:StrictLoop++;
                        return ($script:StrictLoop -le 1);
                    }

                    function Set-ThreadProcessing()
                    {
                        return;
                    }

                    function Format-LoggingConsoleMessage()
                    {
                        param (
                            [string]$Message   = $null,
                            [switch]$GetMsgObj = $false
                        );
                        if ($GetMsgObj) {
                            return $Message;
                        }
                    }

                    Start-LoggingDaemon;
                    return @{
                        'InstallCode'       = $StrictInstallCode;
                        'MissingReturnCode' = $MissingAreaReturnCode;
                        'MissingKeyArea'    = $MissingKeyArea;
                        'FallbackArea'      = $FallbackArea;
                    };
                };
            } | Should -Not -Throw;

            $StrictState['Result']['InstallCode']       | Should -Be 7001;
            $StrictState['Result']['MissingReturnCode'] | Should -Be 40;
            $StrictState['Result']['MissingKeyArea']    | Should -Be 'Logging';
            $StrictState['Result']['FallbackArea']      | Should -Be 'Logging';
        }
    }

    Context 'Documented TLS Provisioning Workflow (CA Import, Certificate Merge, and DryRun vs. Save)' {
        It 'validates Import-IcingaCertAuthority error codes (50013, 50014) and writes ca.crt on non-Windows hosts' {
            $Global:IcingaForWindows.Protected.OSType = 'Linux';

            [string]$MissingCaPath                    = Join-Path -Path $script:TestProgramData -ChildPath 'missing-ca.crt';
            [int]$MissingCode                         = Import-IcingaCertAuthority -Path $MissingCaPath;
            [int]$EmptyCode                           = Import-IcingaCertAuthority -Certificate '   ';

            $MissingCode | Should -Be 50013;
            $EmptyCode   | Should -Be 50014;

            $CaKey                                    = [System.Security.Cryptography.RSA]::Create(2048);
            $CaCert                                   = $null;
            try {
                $CaReq         = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                    'CN=Icinga CA',
                    $CaKey,
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
                );
                $CaCert        = $CaReq.CreateSelfSigned([System.DateTimeOffset]::Now, [System.DateTimeOffset]::Now.AddDays(30));
                [string]$CaPem = "-----BEGIN CERTIFICATE-----`n" + [System.Convert]::ToBase64String($CaCert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert), [System.Base64FormattingOptions]::InsertLineBreaks) + "`n-----END CERTIFICATE-----";

                $ImportResult  = Import-IcingaCertAuthority -Certificate $CaPem;
                [string]$CaOut = Join-Path -Path (& $script:IcingaModule { Get-ModuleCertificateDirectory; }) -ChildPath 'ca.crt';

                $ImportResult                       | Should -BeNullOrEmpty;
                (Test-Path -Path $CaOut)            | Should -BeTrue;
                (Get-Content -Path $CaOut -Raw)     | Should -Match 'BEGIN CERTIFICATE';
            } finally {
                if ($null -ne $CaCert) {
                    $CaCert.Dispose();
                }
                $CaKey.Dispose();
            }
        }

        It 'merges a CA-signed PEM certificate with the existing private key (50010) and returns 50012 when missing' {
            $Global:IcingaForWindows.Protected.OSType = 'Linux';

            [int]$MissingMergeCode                    = New-IcingaProtocolCertificate -CommonName 'nonexistent.example.com' -SignedCert '-----BEGIN CERTIFICATE-----';
            $MissingMergeCode | Should -Be 50012;

            [int]$InitialCode                         = Install-IcingaForWindows -Hostname 'win-srv01.example.com';
            [string]$PfxFile                          = Join-Path -Path (& $script:IcingaModule { Get-ModuleCertificateDirectory; }) -ChildPath 'win-srv01.example.com.pfx';
            $InitialCode | Should -Be 7001;

            $InitialCert                              = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PfxFile);
            $CaKey                                    = [System.Security.Cryptography.RSA]::Create(2048);
            $CaCert                                   = $null;
            $SignedLeaf                               = $null;
            $MergedCert                               = $null;
            try {
                $NodePubKey        = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($InitialCert);
                $CaReq             = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                    'CN=Icinga CA',
                    $CaKey,
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
                );
                $CaReq.CertificateExtensions.Add(
                    [System.Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true, $false, 0, $true)
                );
                $CaCert            = $CaReq.CreateSelfSigned([System.DateTimeOffset]::Now.AddMinutes(-5), [System.DateTimeOffset]::Now.AddDays(30));

                $LeafReq           = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                    'CN=win-srv01.example.com',
                    $NodePubKey,
                    [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                    [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
                );
                [byte[]]$Serial    = @( 1, 2, 3, 4, 5, 6, 7, 8 );
                $SignedLeaf        = $LeafReq.Create($CaCert, [System.DateTimeOffset]::Now, [System.DateTimeOffset]::Now.AddDays(20), $Serial);
                [string]$SignedPem = "-----BEGIN CERTIFICATE-----`n" + [System.Convert]::ToBase64String($SignedLeaf.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert), [System.Base64FormattingOptions]::InsertLineBreaks) + "`n-----END CERTIFICATE-----";

                [int]$MergeCode    = New-IcingaProtocolCertificate -CommonName 'win-srv01.example.com' -SignedCert $SignedPem;
                $MergeCode | Should -Be 50010;

                $MergedCert        = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($PfxFile);
                $MergedCert.Subject       | Should -Be 'CN=win-srv01.example.com';
                $MergedCert.Issuer        | Should -Be 'CN=Icinga CA';
                $MergedCert.HasPrivateKey | Should -BeTrue;
                $MergedCert.Thumbprint    | Should -Be $SignedLeaf.Thumbprint;
            } finally {
                if ($null -ne $MergedCert) {
                    $MergedCert.Dispose();
                }
                if ($null -ne $SignedLeaf) {
                    $SignedLeaf.Dispose();
                }
                if ($null -ne $CaCert) {
                    $CaCert.Dispose();
                }
                $CaKey.Dispose();
                $InitialCert.Dispose();
            }
        }

        It 'previews unified diff via -DryRun without saving Connection.json, rejects empty Hostname (50017), and persists Connection.json (50019) without -DryRun' {
            $Global:IcingaForWindows.Protected.OSType = 'Linux';
            Install-IcingaForWindows -Hostname 'win-srv01.example.com' | Should -Be 7001;

            [string]$ConnectionFile                   = Join-Path -Path (Join-Path -Path (& $script:IcingaModule { Get-ModuleConfigDirectory; }) -ChildPath 'IcingaProtocol') -ChildPath 'Connection.json';
            [array]$Endpoints                         = @(
                (New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665),
                (New-IcingaProtocolEndpoint -Name 'icinga-master02.example.com' -Address 'icinga-master02.example.com' -Port 5665)
            );
            $CertConfig                               = New-IcingaTlsCertConfig `
                -CertCN '$fqdn' `
                -CertStore 'My' `
                -CertStoreLocation 'CurrentUser' `
                -CertIssuer @( 'Icinga CA', '$fqdn' );

            [int]$EmptyHostCode                       = New-IcingaProtocolEnvironment `
                -Endpoints $Endpoints `
                -Zone 'master' `
                -Hostname '' `
                -TlsCertConfig $CertConfig;
            $EmptyHostCode | Should -Be 50017;

            [hashtable]$DryRunPreview                 = New-IcingaProtocolEnvironment `
                -Endpoints $Endpoints `
                -Zone 'master' `
                -Hostname '$fqdn' `
                -TlsCertConfig $CertConfig `
                -DryRun;

            $DryRunPreview['ExitCode']        | Should -Be 1;
            $DryRunPreview['Output']          | Should -Match '\+  "Hostname": "\$fqdn"';
            (Test-Path -Path $ConnectionFile) | Should -BeFalse;

            [int]$SaveCode                            = New-IcingaProtocolEnvironment `
                -Endpoints $Endpoints `
                -Zone 'master' `
                -Hostname '$fqdn' `
                -TlsCertConfig $CertConfig;

            $SaveCode                         | Should -Be 50019;
            (Test-Path -Path $ConnectionFile) | Should -BeTrue;
            (Get-Content -Path $ConnectionFile -Raw) | Should -Match '"Hostname":\s*"\$fqdn"';

            [hashtable]$DryRunAfterSave               = New-IcingaProtocolEnvironment `
                -Endpoints $Endpoints `
                -Zone 'master' `
                -Hostname '$fqdn' `
                -TlsCertConfig $CertConfig `
                -DryRun;

            $DryRunAfterSave['ExitCode'] | Should -Be 0;
            $DryRunAfterSave['Output']   | Should -Be '';
        }
    }
}

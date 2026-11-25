<#
.SYNOPSIS
Pester unit test suite for Invoke-IcingaCheckFirewall in Icinga for Windows

.DESCRIPTION
Validates functional behavior, edge cases, and runtime contracts for
Invoke-IcingaCheckFirewall as part of the Icinga for Windows automated Pester
test suite, using stubbed MSFT_NetFirewallProfile CIM instances.

.NOTES
Executed via build/Invoke-ModuleTests.ps1 using Pester 5.0+.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Invoke-IcingaCheckFirewall' {
    BeforeAll {
        $script:IcingaModule       = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;

        $script:OriginalDaemonFlag = $Global:IcingaForWindows.Protected.IsBackgroundDaemon;

        # Builds MSFT_NetFirewallProfile-like objects; Enabled is the raw GpoBoolean
        # (0 False, 1 True, 2 NotConfigured).
        function New-TestFirewallProfile()
        {
            param (
                [string]$Name = '',
                [int]$Enabled = 1
            );

            return [PSCustomObject]@{
                'Name'    = $Name;
                'Enabled' = [uint16]$Enabled;
            };
        }

        # Runs the plugin inside the module scope with Get-IcingaWindowsInformation
        # shadowed by a function. StubData answers the ActiveStore query, PolicyData
        # the RSOP query; any other policy store is answered with an IcingaError, so
        # the tests also prove which stores the plugin reads.
        function Invoke-TestFirewallCheck()
        {
            param (
                [array]$StubData      = @(),
                [array]$PolicyData    = @(),
                [hashtable]$Arguments = @{ },
                [switch]$Fail         = $false,
                [switch]$PolicyFail   = $false
            );

            return (& $script:IcingaModule {
                param ($StubData, $PolicyData, $Arguments, $Fail, $PolicyFail);

                function Get-IcingaWindowsInformation()
                {
                    param (
                        [string]$ClassName          = '',
                        [string]$Namespace          = '',
                        [string]$Filter             = '',
                        [array]$Property            = @(),
                        [hashtable]$OperationOption = @{ }
                    );

                    [string]$Store = [string]$OperationOption['PolicyStore'];
                    $ErrorType     = 'IcingaError' -as [type];

                    if ($Store -eq 'ActiveStore' -and -not $Fail) {
                        return ,@($StubData);
                    }

                    if ($Store -eq 'RSOP' -and -not $PolicyFail) {
                        return ,@($PolicyData);
                    }

                    return $ErrorType::new('WindowsInformationAccessDenied', ([string]::Format('Access is denied for policy store "{0}"', $Store)), @{ });
                }

                Invoke-IcingaCheckFirewall @Arguments;
            } $StubData $PolicyData $Arguments $Fail $PolicyFail);
        }

        # Deliberately unsorted to prove the plugin orders the profiles by name.
        $script:AllEnabled = @(
            (New-TestFirewallProfile -Name 'Public'),
            (New-TestFirewallProfile -Name 'Domain'),
            (New-TestFirewallProfile -Name 'Private')
        );
    }

    AfterAll {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $script:OriginalDaemonFlag;
    }

    BeforeEach {
        $Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;
    }

    Context 'Expected profile state' {
        It 'returns OK and writes sorted perfdata when all profiles are enabled as expected' {
            Invoke-TestFirewallCheck -StubData $script:AllEnabled -Arguments @{ 'Enabled' = $true; 'Verbosity' = 2; } | Should -Be 0;

            $Result       = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            [array]$Lines = $Result.Output -split "`n";
            $Lines[0] | Should -Be '[OK] Firewall Profiles: 3 Ok';
            $Lines[1] | Should -Be "\_ [OK] Firewall Profile Domain: 'Enabled' is ok";
            $Lines[2] | Should -Be "\_ [OK] Firewall Profile Private: 'Enabled' is ok";
            $Lines[3] | Should -Be "\_ [OK] Firewall Profile Public: 'Enabled' is ok";

            $Result.PerformanceData | Should -Be @(
                'domain::ifw_firewall::enabled=1;;1;;',
                'private::ifw_firewall::enabled=1;;1;;',
                'public::ifw_firewall::enabled=1;;1;;'
            );
        }

        It 'expects disabled profiles without Enabled, like the legacy plugin' {
            Invoke-TestFirewallCheck -StubData $script:AllEnabled | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape("[CRITICAL] Firewall Profile Domain: 'Enabled' does not equal pattern 'Disabled'"));

            $Disabled = @( (New-TestFirewallProfile -Name 'Domain' -Enabled 0) );
            Invoke-TestFirewallCheck -StubData $Disabled | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @( 'domain::ifw_firewall::enabled=0;;0;;' );
        }

        It 'raises CRITICAL for a disabled profile when Enabled is set' {
            $Mixed = @( (New-TestFirewallProfile -Name 'Domain'), (New-TestFirewallProfile -Name 'Public' -Enabled 0) );

            Invoke-TestFirewallCheck -StubData $Mixed -Arguments @{ 'Enabled' = $true; } | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape("[CRITICAL] Firewall Profile Public: 'Disabled' does not equal pattern 'Enabled'"));
        }

        It 'never accepts NotConfigured, regardless of Enabled' {
            $NotConfigured = @( (New-TestFirewallProfile -Name 'Domain' -Enabled 2) );

            Invoke-TestFirewallCheck -StubData $NotConfigured -Arguments @{ 'Enabled' = $true; } | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape("'NotConfigured' does not equal pattern 'Enabled'"));

            Invoke-TestFirewallCheck -StubData $NotConfigured | Should -Be 2;
        }
    }

    Context 'Profile selection' {
        It 'checks only the given profiles and accepts the legacy Profile alias and wildcards' {
            Invoke-TestFirewallCheck -StubData $script:AllEnabled -Arguments @{ 'FirewallProfile' = @( 'Domain' ); 'Enabled' = $true; } | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @( 'domain::ifw_firewall::enabled=1;;1;;' );

            Invoke-TestFirewallCheck -StubData $script:AllEnabled -Arguments @{ 'Profile' = @( 'P*' ); 'Enabled' = $true; } | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData | Should -Be @(
                'private::ifw_firewall::enabled=1;;1;;',
                'public::ifw_firewall::enabled=1;;1;;'
            );

            Invoke-TestFirewallCheck -StubData $script:AllEnabled -Arguments @{ 'FirewallProfile' = @( 'domain' ); 'Enabled' = $true; } | Should -Be 0;
        }

        It 'reports a given profile that does not exist as UNKNOWN' {
            Invoke-TestFirewallCheck -StubData $script:AllEnabled -Arguments @{ 'FirewallProfile' = @( 'Domain', 'Foo' ); 'Enabled' = $true; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape('[UNKNOWN] Firewall Profile Foo: Firewall profile not found'));
        }

        It 'returns UNKNOWN when the host reports no firewall profile' {
            Invoke-TestFirewallCheck -StubData @() -Arguments @{ 'Enabled' = $true; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Firewall Profiles: No firewall profile matches the given filter';
        }
    }

    Context 'Errors and perfdata switches' {
        It 'suppresses all performance data with NoPerfData' {
            Invoke-TestFirewallCheck -StubData $script:AllEnabled -Arguments @{ 'Enabled' = $true; 'NoPerfData' = $true; } | Should -Be 0;
            @($Global:IcingaForWindows.Private.Icinga.CheckResult.PerformanceData).Count | Should -Be 0;
        }

        It 'returns UNKNOWN when the firewall profile query fails' {
            Invoke-TestFirewallCheck -Fail -Arguments @{ 'Enabled' = $true; } | Should -Be 3;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Be '[UNKNOWN] Firewall Profiles: Access is denied for policy store "ActiveStore"';
        }
    }

    Context 'Group Policy' {
        It 'evaluates the effective ActiveStore state, also when it differs from the policy value' {
            # The RSOP value is only used for the marker; the ActiveStore decides the state.
            $Disabled = @( (New-TestFirewallProfile -Name 'Domain' -Enabled 0) );
            $Policy   = @( (New-TestFirewallProfile -Name 'Domain' -Enabled 1) );

            Invoke-TestFirewallCheck -StubData $Disabled -PolicyData $Policy -Arguments @{ 'Enabled' = $true; } | Should -Be 2;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Match ([regex]::Escape("[CRITICAL] Firewall Profile Domain (Group Policy): 'Disabled' does not equal pattern 'Enabled'"));
        }

        It 'marks profiles set by Group Policy and keeps the perfdata labels' {
            $Policy = @(
                (New-TestFirewallProfile -Name 'Domain' -Enabled 1),
                (New-TestFirewallProfile -Name 'Public' -Enabled 2)
            );

            Invoke-TestFirewallCheck -StubData $script:AllEnabled -PolicyData $Policy -Arguments @{ 'Enabled' = $true; 'Verbosity' = 2; } | Should -Be 0;

            $Result       = $Global:IcingaForWindows.Private.Icinga.CheckResult;
            [array]$Lines = $Result.Output -split "`n";
            $Lines[1] | Should -Be "\_ [OK] Firewall Profile Domain (Group Policy): 'Enabled' is ok";
            $Lines[2] | Should -Be "\_ [OK] Firewall Profile Private: 'Enabled' is ok";
            $Lines[3] | Should -Be "\_ [OK] Firewall Profile Public: 'Enabled' is ok";

            $Result.PerformanceData | Should -Contain 'domain::ifw_firewall::enabled=1;;1;;';
        }

        It 'continues without the marker when the RSOP query fails' {
            Invoke-TestFirewallCheck -StubData $script:AllEnabled -PolicyFail -Arguments @{ 'Enabled' = $true; 'Verbosity' = 2; } | Should -Be 0;
            $Global:IcingaForWindows.Private.Icinga.CheckResult.Output | Should -Not -Match 'Group Policy';
        }
    }
}

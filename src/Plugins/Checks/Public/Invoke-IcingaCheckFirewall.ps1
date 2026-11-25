<#
.SYNOPSIS
Check whether the Windows Firewall profiles are enabled or disabled

.DESCRIPTION
Queries the MSFT_NetFirewallProfile CIM class (namespace root/StandardCimv2)
once and builds a single IcingaPlugin container named 'Firewall Profiles'.
Every selected profile (Domain, Private, Public) becomes a child check named
'Firewall Profile <name>' that compares the profile state with the expected
state and turns CRITICAL on a mismatch.

The expected state follows the legacy icinga-powershell-plugins check: with
Enabled set every profile must be enabled, without it every profile must be
disabled. FirewallProfile (aliased to Profile) selects the profiles to check,
wildcards allowed; without it all profiles of the host are checked, while the
legacy check silently checked none. Every given name without a match on the
host is reported as UNKNOWN.

The state is read from the ActiveStore policy store, which holds the effective
state merged from the local settings and every applied Group Policy. The legacy
check read the local store only and missed profiles enforced by an Active
Directory policy. A second query against the RSOP store finds the profiles whose
state a Group Policy sets; their check name ends with ' (Group Policy)', so the
output shows that the state cannot be changed locally. If the RSOP query fails,
the check continues without that marker.

The CIM property is a GpoBoolean (0 False, 1 True, 2 NotConfigured): the output
shows 'Disabled', 'Enabled' or 'NotConfigured', and NotConfigured never matches
the expected state.

This plugin is Windows-only because it relies on the MSFT_NetFirewallProfile
CIM class.

.PARAMETER FirewallProfile
| Name            | Type         | Description                                                                         | Default |
|-----------------|--------------|-------------------------------------------------------------------------------------|---------|
| FirewallProfile | System.Array | Profiles to check (Domain, Private, Public), wildcards allowed. Empty checks all.   | @()     |

.PARAMETER Enabled
| Name    | Type                                         | Description                                                           | Default |
|---------|----------------------------------------------|-----------------------------------------------------------------------|---------|
| Enabled | System.Management.Automation.SwitchParameter | Expect the profiles to be enabled; without it they must be disabled.  | False   |

.PARAMETER Verbosity
| Name      | Type         | Description                                                                         | Default |
|-----------|--------------|-------------------------------------------------------------------------------------|---------|
| Verbosity | System.Int32 | Output detail: 0 problems only, 1 plus affected siblings, 2 all, 3 all plus config. | 0       |

.PARAMETER NoPerfData
| Name       | Type                                         | Description                           | Default |
|------------|----------------------------------------------|---------------------------------------|---------|
| NoPerfData | System.Management.Automation.SwitchParameter | Suppress the performance data output. | False   |

.OUTPUTS
System.Int32 -- The Icinga plugin exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

.EXAMPLE
PS> Invoke-IcingaCheckFirewall -Enabled

Goes critical when any firewall profile of the host is not enabled.

.EXAMPLE
PS> Invoke-IcingaCheckFirewall -FirewallProfile 'Domain', 'Private' -Enabled -Verbosity 2

Expects the Domain and Private profiles to be enabled and lists both in the
output.

.NOTES
Windows-only. Reads the MSFT_NetFirewallProfile CIM class through
Get-IcingaWindowsInformation with the PolicyStore options 'ActiveStore' and
'RSOP'; standard users can read both. A failed ActiveStore query is reported as
UNKNOWN with its reason. Perfdata labels are '<profile>::ifw_firewall::enabled' with the raw
GpoBoolean value (0, 1 or 2). The integer exit code is the return value; an
Icinga command wrapper is expected to exit with it.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaCheckFirewall()
{
    param (
        [Alias('Profile')]
        [array]$FirewallProfile = @(),
        [switch]$Enabled        = $false,
        [int]$Verbosity         = 0,
        [switch]$NoPerfData     = $false
    );

    # MSFT_NetFirewallProfile.Enabled is a GpoBoolean: 0 False, 1 True, 2 NotConfigured.
    [hashtable]$StateText    = @{
        0 = 'Disabled';
        1 = 'Enabled';
        2 = 'NotConfigured';
    };
    [int]$ExpectedState      = [int][bool]$Enabled;

    $CheckPackage            = New-IcingaPlugin 'Firewall Profiles';
    $CheckPackage.Verbose    = $Verbosity;
    $CheckPackage.NoPerfData = $NoPerfData;

    # The ActiveStore holds the effective state, merged from the local settings and
    # every applied Group Policy; the local PersistentStore alone misses GPO values.
    $Profiles                = Get-IcingaWindowsInformation -ClassName 'MSFT_NetFirewallProfile' -Namespace 'root/StandardCimv2' -Property 'Name', 'Enabled' -OperationOption @{ 'PolicyStore' = 'ActiveStore'; };

    if (Test-IcingaError -InputObject $Profiles) {
        return $CheckPackage.SetError($Profiles).Compile();
    }

    # The RSOP store only contains values set by Group Policy. It only marks the
    # output, so a failed query is logged by Get-IcingaWindowsInformation and the
    # check continues without the marker.
    $PolicyProfiles           = Get-IcingaWindowsInformation -ClassName 'MSFT_NetFirewallProfile' -Namespace 'root/StandardCimv2' -Property 'Name', 'Enabled' -OperationOption @{ 'PolicyStore' = 'RSOP'; };
    [hashtable]$PolicyManaged = @{ };

    if ((Test-IcingaError -InputObject $PolicyProfiles) -eq $false) {
        foreach ($PolicyEntry in $PolicyProfiles) {
            # GpoBoolean 2 (NotConfigured) means the policy leaves the profile state to the host.
            if ([int]$PolicyEntry.Enabled -ne 2) {
                $PolicyManaged[[string]$PolicyEntry.Name] = $true;
            }
        }
    }

    [array]$KnownProfiles = @();

    foreach ($ProfileEntry in (ConvertTo-IcingaSortedArray -InputObject $Profiles -Property 'Name')) {
        [string]$ProfileName = $ProfileEntry.Name;
        $KnownProfiles      += $ProfileName;

        # Without FirewallProfile every profile is checked; the legacy check silently checked none.
        if ($FirewallProfile.Count -ne 0 -and (Test-IcingaArrayFilter -InputObject $ProfileName -Include $FirewallProfile) -eq $false) {
            continue;
        }

        [string]$CheckName = [string]::Format('Firewall Profile {0}', $ProfileName);

        # Tells the admin that the state is enforced centrally and cannot be changed locally.
        if ($PolicyManaged.ContainsKey($ProfileName)) {
            $CheckName = [string]::Format('{0} (Group Policy)', $CheckName);
        }

        $CheckPackage.AddCheck(
            (New-IcingaPlugin $CheckName ([int]$ProfileEntry.Enabled)).
                Translate($StateText).
                MetricIndex($ProfileName).
                MetricLabel('enabled').
                Critical($ExpectedState).
                CheckNotEqual()
        ).Commit();
    }

    $CheckPackage.AddMissingChecks($FirewallProfile, $KnownProfiles, 'Firewall Profile {0}', 'Firewall profile not found', 'Unknown').Commit();

    if ($CheckPackage.HasChecks() -eq $false) {
        return $CheckPackage.SetError('No firewall profile matches the given filter').Compile();
    }

    return $CheckPackage.Compile();
}

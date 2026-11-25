# Walkthrough -- `plugins-firewall`

## Executive Summary

`Invoke-IcingaCheckFirewall` brings the legacy firewall profile check to **Icinga for Windows**. It reports whether the Domain, Private and Public profiles are in the expected state and, unlike the legacy check, evaluates the **effective** state including Active Directory Group Policies. Profiles whose state a GPO sets are marked with `(Group Policy)`. The legacy parameters are kept, the shared CIM helper gained provider custom options, and the output follows the `IcingaPlugin` SDK and the common perfdata schema.

## Under the Hood

### `Get-IcingaWindowsInformation -OperationOption`

1. Without `-OperationOption` nothing changes: `Get-CimInstance` runs as before.
2. With options, the function builds a WQL query (`SELECT <Property or *> FROM <ClassName>` plus `WHERE <Filter>`), creates `CimOperationOptions`, calls `SetCustomOption(<name>, <value>, $false)` for every entry, opens a local session with `New-CimSession -ErrorAction Stop` and runs `QueryInstances($Namespace, 'WQL', $Query, $Options)`.
3. Errors from the session call arrive as a `RuntimeException` wrapping the `CimException`. The catch block walks `InnerException` until it finds `NativeErrorCode`, so `InvalidClass`, `InvalidNamespace`, `AccessDenied`, `InvalidQuery` and the rest map to the same `WindowsInformation*` codes as before. An unknown policy store surfaces as `Failed` ("The network path was not found") -> `WindowsInformationQueryFailed`.
4. `finally` disposes the session and the options on success and failure.

### `Invoke-IcingaCheckFirewall`

1. **Effective state:** `MSFT_NetFirewallProfile` (`root/StandardCimv2`) with `PolicyStore = ActiveStore`. A failure returns an `IcingaError`, which `SetError` turns into `UNKNOWN`.
2. **Group Policy marker:** the same class with `PolicyStore = RSOP`. Every profile with a GPO value other than `2` (`NotConfigured`) is marked. A failed RSOP query is logged by the helper and only drops the marker.
3. **Expected state:** `[int][bool]$Enabled` -- `1` with `-Enabled`, otherwise `0` (legacy semantics).
4. **Selection:** profiles are sorted with `ConvertTo-IcingaSortedArray`. With `-FirewallProfile`, `Test-IcingaArrayFilter -Include` selects them case-insensitively with wildcard support; without it, every profile is checked.
5. **Check:** each profile becomes `New-IcingaPlugin 'Firewall Profile <name>[ (Group Policy)]' <GpoBoolean>` with `Translate(@{ 0 = 'Disabled'; 1 = 'Enabled'; 2 = 'NotConfigured' })`, `MetricIndex(<name>)`, `MetricLabel('enabled')` and `Critical(<expected>).CheckNotEqual()`. The translation applies to value and threshold, so the output reads `'Enabled' does not equal pattern 'Disabled'` while perfdata stays numeric. The marker only changes the check name; the metric index stays `<name>`.
6. **Missing profiles:** `AddMissingChecks($FirewallProfile, $KnownProfiles, 'Firewall Profile {0}', 'Firewall profile not found', 'Unknown')`.
7. **Empty result:** no profile on the host -> `UNKNOWN` `No firewall profile matches the given filter`.

## Runtime Flow

`Invoke-IcingaCheckFirewall` -> `Get-IcingaWindowsInformation` (ActiveStore) -> `Get-IcingaWindowsInformation` (RSOP) -> per-profile `IcingaPlugin` leaves -> `AddMissingChecks` -> `Compile()` (console output on the main thread, `Private.Icinga.CheckResult` inside daemons) -> integer exit code.

## Verification Results (2026-11-25, Windows 11)

| Command | Result |
| ------- | ------ |
| `.\build\Build-ModuleProject.ps1 -SkipTests` | Build completed |
| `.\build\Test-ModuleCodeStyling.ps1` | All checks passed (0 violations) |
| `.\build\Test-ModuleChangelog.ps1` | Governance checks passed |
| `.\build\Invoke-ScriptAnalysis.ps1 -FailOn 'Warning'` | 0 build-breaking findings (24 advisory `TypeNotFound`, pre-existing) |
| `.\build\Test-ModuleDaemonMemoryLeak.ps1` | No daemon memory leaks detected |
| `.\build\Build-ModuleDocs.ps1 -Strict $true` | 0 violations |
| `Tests/Invoke-IcingaCheckFirewall.Tests.ps1` | 12 passed, 0 failed |
| `Tests/Get-IcingaWindowsInformation.Tests.ps1` | 16 passed, 0 failed (5 new) |
| Live, Windows PowerShell 5.1.26100 and PowerShell 7.7.0 | `ActiveStore` 3 profiles, `RSOP` 0 rows (no firewall GPO on the notebook); plugin output identical on both |

## Practical Examples

```powershell
PS> Invoke-IcingaCheckFirewall -Enabled -Verbosity 2
[OK] Firewall Profiles: 3 Ok
\_ [OK] Firewall Profile Domain: 'Enabled' is ok
\_ [OK] Firewall Profile Private: 'Enabled' is ok
\_ [OK] Firewall Profile Public: 'Enabled' is ok
| domain::ifw_firewall::enabled=1;;1;; private::ifw_firewall::enabled=1;;1;; public::ifw_firewall::enabled=1;;1;;

PS> Invoke-IcingaCheckFirewall -FirewallProfile 'Domain', 'Foo' -Enabled -Verbosity 2
[UNKNOWN] Firewall Profiles: 1 Unknown 1 Ok [UNKNOWN] Firewall Profile Foo
\_ [OK] Firewall Profile Domain: 'Enabled' is ok
\_ [UNKNOWN] Firewall Profile Foo: Firewall profile not found
| domain::ifw_firewall::enabled=1;;1;;
```

On a host where a GPO enables the Domain profile (from the unit tests):

```text
\_ [OK] Firewall Profile Domain (Group Policy): 'Enabled' is ok
```

Reading another NetSecurity class with a policy store:

```powershell
PS> Get-IcingaWindowsInformation -ClassName 'MSFT_NetFirewallProfile' -Namespace 'root/StandardCimv2' -Property 'Name', 'Enabled' -OperationOption @{ 'PolicyStore' = 'RSOP'; }
```

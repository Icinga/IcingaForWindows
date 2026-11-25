# Task Checklist -- `plugins-firewall`

## Completed Tasks

- [x] Compared the legacy check (`analyze/icinga-powershell-plugins/plugins/Invoke-IcingaCheckFirewall.psm1`) with the current plugin conventions (`Invoke-IcingaCheckService.ps1`).
- [x] Added `src/Plugins/Checks/Public/Invoke-IcingaCheckFirewall.ps1` (`-FirewallProfile` / `-Profile`, `-Enabled`, `-Verbosity`, `-NoPerfData`).
- [x] Switched the plugin to the effective `ActiveStore` state and added the `(Group Policy)` marker from the `RSOP` store (maintainer request: firewall profiles enforced by Active Directory policies).
- [x] Added `-OperationOption` to `src/Tools/Public/Get-IcingaWindowsInformation.ps1` (WQL through a disposed local `CimSession`, unwrapped `CimException` codes).
- [x] Added `Tests/Invoke-IcingaCheckFirewall.Tests.ps1` (12 tests: expected states, legacy disabled default, `NotConfigured`, selection / alias / wildcards, unknown profiles, empty host, `NoPerfData`, query failure, ActiveStore vs. policy value, GPO marker, failed RSOP query).
- [x] Extended `Tests/Get-IcingaWindowsInformation.Tests.ps1` (5 tests: WQL query, select list and WHERE clause, unwrapped error codes, session disposal).
- [x] Verified the `ActiveStore` / `RSOP` queries live on Windows PowerShell 5.1 and PowerShell 7.
- [x] Regenerated `docs/Icinga.Plugins.Checks.md`, `docs/Icinga.Tools.md` and `docs/index.md`.
- [x] Added the changelog bullets and synchronized `docs/General/Roadmap.md`.

## Known Limitations & Technical Debt

- [ ] The `(Group Policy)` marker is covered by unit tests only. The development notebook has no firewall GPO (`RSOP` returns no rows); verify on a domain-joined host with a firewall GPO.
- [ ] Default inbound / outbound actions (`DefaultInboundAction`, `DefaultOutboundAction`) are not checked (out of scope for the 1:1 port).
- [ ] Perfdata labels changed from `firewall_profile_<name>` to `<name>::ifw_firewall::enabled`; existing graphs of the legacy plugin do not continue.

## Next Steps

- Run the plugin on a GPO-managed host (for example in the demo environment) and record the output in `walkthrough.md`.
- Open a Pull Request; the `changelog-link` job stamps the PR link onto the changelog bullets.

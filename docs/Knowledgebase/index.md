# Icinga for Windows Knowledgebase

Welcome to the Icinga for Windows Knowledgebase. Whenever Icinga for Windows encounters configuration mismatches, security boundary violations, or runtime check errors that require detailed remediation steps beyond a single status line, the check output includes a unique six-digit identifier prefixed with `IWKB` (starting at `IWKB001000` for Icinga for Windows v2+).

---

## Knowledgebase Index

| ID | Title | Summary |
|----|-------|---------|
| [IWKB001000](IWKB001000.md) | Unable to map Custom-Variables to Icinga for Windows Check | Custom variables on a PowerShell check command could not be mapped because `ifw-api` is not imported on the `CheckCommand` and variable names do not match plugin parameters. |
| [IWKB001001](IWKB001001.md) | Unknown Check-Command Parameter in `ifw_api_arguments` | `macros.ifw_api_arguments` supplied a non-empty value for a parameter name that does not exist on the target PowerShell check plugin. |
| [IWKB001002](IWKB001002.md) | Unable to map Custom-Variables to External Binary Check without `ifw-api` | Custom variables without a leading `-` or `/` flag prefix were passed to an external binary check without the `ifw-api` `CheckCommand` template. |
| [IWKB001003](IWKB001003.md) | Check Command Not Found, Missing `ifw_api_command`, or Binary Outside Approved Directory | `macros.ifw_api_command` is missing, contains invalid/NTFS ADS path characters, points outside `C:\ProgramData\IcingaForWindows\Binaries`, or matches neither an `Invoke-IcingaCheck*` plugin nor an approved binary. |

---
applyTo: "**/*.ps1, **/*.psm1"
---

# Icinga for Windows – AI Coding Agent Instructions

## Project Architecture
- **Modular PowerShell**: The project is organized into feature-based modules (e.g., `Api`, `Config`, `Core`, `Environment`, `IcingaProtocol`, `Security`, `Tools`). Each module has `Public` and `Private` subfolders for exported and internal functions.
- **Core Components**: Key logic is in `lib/` (core modules), with `src/` containing feature implementations. `IcingaForWindows.psm1` is the main entry point, importing all modules.
- **Threading & Async**: Threading is handled in `Core/Threading` and related docs. Use `$ThreadId` as a `System.String` (GUID format) for thread identification.
- **API & Protocol**: Communication with Icinga is managed via the `Api` and `IcingaProtocol` modules, using worker queues and message passing (see `Add-IcingaApiCallToWorkerQueue.ps1`, `Start-IcingaProtocolWorker.ps1`).

## Documentation & Code Patterns
- **Function Documentation**: Every function must use PowerShell comment-based help. Required sections:
	- `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` (with markdown table: Name, Type, Description, Default), `.EXAMPLE`, `.INPUTS`, `.OUTPUTS`, `.NOTES`
- **Parameter Types**: Use explicit types. For GUIDs, document as `System.String` in GUID format.
- **Consistent Naming**: Functions use `Verb-IcingaNoun` (e.g., `Start-IcingaApi`).
- **Public/Private Split**: Only export functions in `Public/`. Internal helpers go in `Private/`.
- **Error Handling**: Use `IcingaForWindows.Core.ErrorHandling` for all error and exit code logic.
- `.NOTES` Section: Include dependencies on other modules and all used functions from IcingaForWindows.
- The documentation must always start at the beginning of each new line, without any leading spaces.

## Developer Workflows
- **Build**: Use `build/build.ps1` or `build/Build-ModuleProject.ps1` to package or prepare the module.
- **Testing**: No standard test runner is present; manual testing is typical. Review `docs/Developer/` for guidance.
- **Debugging**: Use verbose output and logging via `IcingaForWindows.Core.Logging`.
- **Extending**: Add new features as modules under `src/`, following the existing structure. Update the main `.psm1` to import new modules.

## Conventions & Integration
- **Markdown Tables**: Always use markdown tables for parameter documentation.
- **External Integration**: Communicates with Icinga and Windows services via TCP, file I/O, and PowerShell remoting. See `IcingaProtocol` and `Api` modules for integration points.

## Key Files & Directories
- `IcingaForWindows.psm1` – Main module entry/import logic
- `lib/` – Core logic (logging, error handling, runtime, etc.)
- `src/` – Feature modules (Api, Config, Protocol, Security, Tools, etc.)
- `build/` – Build scripts
- `docs/Developer/` – Developer documentation

## Example: Function Documentation
```powershell
<#
.SYNOPSIS
Starts the Icinga API listener.

.DESCRIPTION
Initializes and starts the API listener for Icinga, handling incoming requests asynchronously.

.PARAMETER ThreadId
| Name      | Type         | Description                        | Default |
|-----------|--------------|------------------------------------|---------|
| ThreadId  | System.String| Unique thread identifier (GUID)    |         |

.EXAMPLE
PS> Start-IcingaApi -ThreadId "56449934-1cbf-4285-a04a-511825b6d919"

.INPUTS
System.String

.OUTPUTS
System.Object

.NOTES
Depends on IcingaForWindows.Core.Threading
#>
```

---
For questions or unclear conventions, review `docs/Developer/` or ask for clarification.
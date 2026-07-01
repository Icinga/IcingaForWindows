[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1-777BB4?logo=PowerSHell)](https://learn.microsoft.com/en-US/powershell/scripting/install/installing-powershell-on-windows?view=powershell-5.1)
[![GitHub Tag](https://img.shields.io/github/tag/Icinga/IcingaForWindows.svg)](https://github.com/Icinga/IcingaForWindows/releases/latest)
[![GitHub Issues](https://img.shields.io/github/issues-search?query=repo%3AIcinga%2FIcingaForWindows%20is%3Aopen%20is%3Aissue&label=Issues&color=red
)](https://github.com/Icinga/IcingaForWindows/issues)
[![GitHub Pull Requests](https://img.shields.io/github/issues-search?query=repo%3AIcinga%2FIcingaForWindows%20is%3Aopen%20is%3Apr&label=Pull%20Requests&color=green
)](https://github.com/Icinga/IcingaForWindows/pulls)

IcingaForWindows Documentation
==============

`IcingaForWindows` is a PowerShell monitoring stack for Windows hosts. Its runtime, configuration layout, threading model and public function surface are built around a single synchronized `$Global:IcingaForWindows` state object that is shared between the main session and every background daemon.

The module is built from small, single-purpose components under `src/`:

* **Core.Runtime / Core.Logging / Core.Threading** — the shared runtime, the structured logging queue and the runspace-based thread pool that powers every daemon.
* **Core.TCPStack / Core.RestApi / Core.WebSocket** — the TLS-aware TCP listener, the HTTP/REST worker pipeline and the WebSocket reader/writer pairs.
* **Core.AccessControl** — role-based access roles consumed by the REST API.
* **Core.ErrorHandling** — internal exit-code table and the `Write-FunctionReturnValue` helper used across the module.
* **Api** — the high-level Icinga API endpoint (`Start-IcingaApi`) layered on top of the REST stack.
* **IcingaProtocol** — the native Icinga 2 agent protocol implementation (`Start-IcingaAgent`).
* **Config / Security / Tools** — configuration loading, certificate/security helpers and small reusable utilities.

Compiled module files (`lib/`) and the API reference under `docs/` are **auto-generated** from `src/` by the scripts in `build/`; do not edit them by hand.

Getting started
-------------

Requirements: PowerShell 5.1+ (PowerShell 7.5 recommended) on Windows. The module also imports on Linux/macOS for development via the `$env:ProgramData` fallback.

```powershell
Import-Module IcingaForWindows -Force -Global;
Use-IcingaForWindows -LogLevel 'Info';   # alias: ifw
```

`Use-IcingaForWindows` initializes the base environment, loads the on-disk configuration and access control, and starts the standard background daemons (logging, housekeeper, REST API, WebSocket, Icinga agent). It is idempotent and can be re-run safely.

Documentation
-------------

The API reference and guides live under `docs/`. Start here:

* [API Reference Index](docs/index.md) — one page per component, lists every public and private function with synopsis, parameters, examples and a source link.
* [Icinga REST API](docs/Icinga.Core.RestApi.md) · [Icinga API endpoint](docs/Icinga.Api.md)
* [Icinga Protocol Stack](docs/Icinga.IcingaProtocol.md)
* [TCP Stack](docs/Icinga.Core.TCPStack.md) · [WebSocket Layer](docs/Icinga.Core.WebSocket.md)
* [Threading Runtime](docs/Icinga.Core.Threading.md) · [Logging](docs/Icinga.Core.Logging.md) · [Error Handling](docs/Icinga.Core.ErrorHandling.md)
* [Access Control](docs/Icinga.Core.AccessControl.md) · [Security Helpers](docs/Icinga.Security.md)
* [Runtime](docs/Icinga.Core.Runtime.md) · [Configuration](docs/Icinga.Config.md) · [Tools](docs/Icinga.Tools.md)

Developer Guide
------------

If you wish to extend the module or write custom integrations against the internal runtime, start with the [Developer Guide](docs/Developer/) — currently focused on the threading model:

* [Threading architecture](docs/Developer/Threading/01-Threading.md) — how `$Global:IcingaForWindows.Public.Threading`, the runspace pool and per-thread `Private` state fit together, and how to spawn your own background threads.

The contribution rules, code style and the binding comment-based help format are documented in [CLAUDE.md](CLAUDE.md). Rebuilding the module and regenerating the API reference is done via:

```powershell
Build-ModuleProject;                                 # compile src/ → lib/ and run tests
.\build\Build-ModuleDocs.ps1;                        # regenerate docs/*.md from comment-based help
Build-ModuleProject -GenerateDocs;                   # both in one shot
```

Contributing
------------

IcingaForWindows is an Open Source project (GPLv3) and lives from your contributions — feature requests, issues, documentation or code.

* Please check whether a related issue already exists on our [Issue Tracker](https://github.com/Icinga/IcingaForWindows/issues)
* Send a [Pull Request](https://github.com/Icinga/IcingaForWindows/pulls)
* The master branch shall never be corrupt!

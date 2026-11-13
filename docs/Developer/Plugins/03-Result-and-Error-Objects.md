# Result and Error Objects (`IcingaCheckResult` & `IcingaError`)

Alongside [`IcingaPlugin`](02-IcingaPlugin-Reference.md), two lightweight companion classes handle compiled check outputs and structured data-collection errors:

1. **[`IcingaCheckResult`](#1-icingacheckresult-class)**: Stores the compiled exit code, rendered output text, and performance-data array produced by `IcingaPlugin.Compile()`.
2. **[`IcingaError`](#2-icingaerror-class)** and **[`Test-IcingaError`](#3-test-icingaerror-cmdlet)**: Allow data providers and tool functions to return structured errors without throwing exceptions, which plugins can then hand directly to `$CheckPackage.SetError($ErrorObject).Compile()`.

* **[01 - Plugin Architecture and Core Concepts](01-Architecture-and-Concepts.md)**
* **[02 - IcingaPlugin Technical Reference](02-IcingaPlugin-Reference.md)**
* **[03 - Result and Error Objects (`IcingaCheckResult` & `IcingaError`)](03-Result-and-Error-Objects.md)** *(this page)*
* **[04 - Step-by-Step Developer Guide: Writing a Custom Plugin](04-Custom-Plugin-Developer-Guide.md)**

---

## 1. `IcingaCheckResult` Class

Defined in [`src/Classes/Icinga/IcingaCheckResult.ps1`](../../../src/Classes/Icinga/IcingaCheckResult.ps1). When `IcingaPlugin.Compile()` finishes evaluating a plugin tree, it stores an `IcingaCheckResult` instance in the current runspace's private runtime state:

```powershell
$Global:IcingaForWindows.Private.Icinga.CheckResult
```

* **Interactive / CLI mode (`$Global:IcingaForWindows.Protected.IsBackgroundDaemon -eq $false`):** `Compile()` writes the rendered output and `| <perfdata>` block directly to the console via `[System.Console]::WriteLine(...)`, stores the `IcingaCheckResult` in `Private.Icinga.CheckResult`, and returns the integer `ExitCode`.
* **Daemon / Worker mode (`$Global:IcingaForWindows.Protected.IsBackgroundDaemon -eq $true`):** `Compile()` skips console output and leaves the `IcingaCheckResult` in `Private.Icinga.CheckResult` so the background worker or REST API endpoint can read `ExitCode`, `Output`, and `PerformanceData` without capturing console streams.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `ExitCode` | `System.Int32` | `0` | Numeric Icinga plugin exit code (`0` OK, `1` WARNING, `2` CRITICAL, `3` UNKNOWN). |
| `Output` | `System.String` | `''` | Rendered, potentially multi-line plugin text output (without the `\|` performance-data line). |
| `PerformanceData` | `System.Array` | `@()` | Flat array of unique `check_multi` performance-data metric strings (`index::ifw_template::label=value...`). |

### Constructors

| Overload | Parameters | Description |
|----------|------------|-------------|
| `IcingaCheckResult()` | *(none)* | Creates an empty placeholder result (`ExitCode = 0`, `Output = ''`, `PerformanceData = @()`). |
| `IcingaCheckResult([int]$ExitCode, [string]$Output, [array]$PerformanceData)` | `ExitCode`: `0`..`3`<br>`Output`: rendered text<br>`PerformanceData`: metric array | Creates a populated check result. Called internally by `IcingaPlugin.Compile()`. |

### Methods

| Method | Return Type | Description |
|--------|-------------|-------------|
| `ToString()` | `System.String` | Returns `$this.Output` so converting the result to `[string]` yields the rendered plugin text output. |

### Reading the Result in Daemons and Pester Tests

```powershell
# Suppress console output during a unit test or daemon execution
$Global:IcingaForWindows.Protected.IsBackgroundDaemon = $true;

$ExitCode = Invoke-IcingaCheckScheduledTask -TaskName 'Renew Certificate';
$Result   = $Global:IcingaForWindows.Private.Icinga.CheckResult;

$Result.ExitCode        # e.g. 0
$Result.Output          # e.g. '[OK] Scheduled Tasks: 1 Ok'
$Result.PerformanceData # e.g. @('icingaicingaforwindowsrenewcertificate::ifw_scheduledtask::state=3;;3;;', ...)
```

---

## 2. `IcingaError` Class

Defined in [`src/Classes/Icinga/IcingaError.ps1`](../../../src/Classes/Icinga/IcingaError.ps1). Data collection functions (such as `Get-IcingaWindowsInformation` or provider functions like `Get-IcingaScheduledTask`) must **never** throw unhandled exceptions into a plugin. Instead, when an underlying query (CIM/WMI, Task Scheduler, Registry, Service Controller) fails, the provider returns an `IcingaError` object describing the failure.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `Message` | `System.String` | `''` | Final, human-readable error message displayed by the plugin when passed to `IcingaPlugin.SetError()`. |
| `ReturnCode` | `System.String` | `''` | Optional semantic key from `Set-InternalExitCodes` (for example `'WindowsInformationAccessDenied'` or `'ScheduledTaskQueryFailed'`). |
| `Data` | `System.Collections.Hashtable` | `@{}` | Optional context values associated with the failure (for example `@{ 'ClassName' = 'Win32_Service' }`). |

### Constructors

> **Runspace Safety Reminder:** Inside functions (outside `src/Classes`), always construct `IcingaError` via runtime type lookup: `('IcingaError' -as [type])::new(...)`.

| Overload | Parameters | Description |
|----------|------------|-------------|
| `IcingaError([string]$Message)` | `Message`: literal error text | Stores `$Message` verbatim without placeholder formatting (safe when `$Message` contains literal braces `{}` such as GUIDs). |
| `IcingaError([string]$Message, [object[]]$Arguments)` | `Message`: format string<br>`Arguments`: values for `{0}`, `{1}`, ... | Formats `$Message` with `$Arguments` via `IcingaError::FormatMessage()`. Never throws even if the format string is malformed. |
| `IcingaError([string]$ReturnCode, [string]$Message, [hashtable]$Data)` | `ReturnCode`: exit-code key<br>`Message`: final error text<br>`Data`: context hashtable | Creates an error linked to an internal return code and stores the context hashtable (a `$null` `$Data` leaves `Data` as `@{}`). |

### Methods

| Method | Kind | Return Type | Description |
|--------|------|-------------|-------------|
| `FormatMessage([string]$Message, [object[]]$Arguments)` | `static` | `System.String` | Replaces `{0}`-style placeholders with `$Arguments` using `[string]::Format()`. If `$Arguments` is `$null` or empty, returns `$Message` unchanged. If `[string]::Format()` fails, appends `' (' + ($Arguments -join ', ') + ')'` so formatting never throws. |
| `ToString()` | instance | `System.String` | Returns `$this.Message`. |

### Creating an `IcingaError` in a Provider Function

```powershell
$ErrorType = 'IcingaError' -as [type];

try {
    $Items = Get-ScheduledTask -ErrorAction Stop;
} catch {
    [string]$Reason = $_.Exception.Message;
    $Error.Clear();
    return $ErrorType::new(
        'ScheduledTaskQueryFailed',
        $ErrorType::FormatMessage('Failed to query scheduled tasks: {0}', @($Reason)),
        @{ 'Exception' = $Reason }
    );
}
```

---

## 3. `Test-IcingaError` Cmdlet

Defined in [`src/Core/ErrorHandling/Public/Test-IcingaError.ps1`](../../../src/Core/ErrorHandling/Public/Test-IcingaError.ps1), `Test-IcingaError` is the runspace-safe cmdlet used by plugins and providers to check whether a data collection call returned an `IcingaError`.

### Syntax

```powershell
Test-IcingaError [[-InputObject] <object>]
```

### Parameters

| Parameter | Position | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `InputObject` | `0` | `System.Object` | `$null` | Result returned by a data collection or provider function. |

### Return Value

* **`System.Boolean`** -- `$true` when `$InputObject` is an instance of the current runspace's `IcingaError` type (`$InputObject -is ('IcingaError' -as [type])`); `$false` for `$null`, arrays, hashtables, and all other objects.

### Usage Pattern in a Plugin

```powershell
$CheckPackage = New-IcingaPlugin 'Services';
$Services     = Get-IcingaWindowsInformation -ClassName 'Win32_Service';

if (Test-IcingaError -InputObject $Services) {
    return $CheckPackage.SetError($Services).Compile();
}
```

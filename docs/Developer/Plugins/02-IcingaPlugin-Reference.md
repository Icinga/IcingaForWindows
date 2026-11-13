# IcingaPlugin Technical Reference

This document is the complete technical reference for **[`New-IcingaPlugin`](#1-new-icingaplugin-factory-cmdlet)** and the **[`IcingaPlugin`](#2-icingaplugin-class-properties)** class, including every public property, hidden property, static property, constructor, public method (with all overload variants), and internal helper method.

* **[01 - Plugin Architecture and Core Concepts](01-Architecture-and-Concepts.md)**
* **[02 - IcingaPlugin Technical Reference](02-IcingaPlugin-Reference.md)** *(this page)*
* **[03 - Result and Error Objects (`IcingaCheckResult` & `IcingaError`)](03-Result-and-Error-Objects.md)**
* **[04 - Step-by-Step Developer Guide: Writing a Custom Plugin](04-Custom-Plugin-Developer-Guide.md)**

---

## 1. `New-IcingaPlugin` Factory Cmdlet

Defined in [`src/Plugins/Lib/Private/New-IcingaPlugin.ps1`](../../../src/Plugins/Lib/Private/New-IcingaPlugin.ps1), `New-IcingaPlugin` is the runspace-safe factory function that every plugin and helper function outside `src/Classes` must use instead of `[IcingaPlugin]::new()`. It resolves the `IcingaPlugin` class in the calling runspace (`'IcingaPlugin' -as [type]`) and invokes either `$PluginType::new($Name)` (when neither `-Value` nor `-Unit` is bound) or `$PluginType::new($Name, $Value, $Unit)`.

### Syntax

```powershell
New-IcingaPlugin [[-Name] <string>] [[-Value] <object>] [[-Unit] <string>]
```

### Parameters

| Parameter | Position | Type | Default | Description |
|-----------|----------|------|---------|-------------|
| `Name` | `0` | `System.String` | `$null` | Display name of the plugin node (container or leaf check). |
| `Value` | `1` | `System.Object` | `$null` | Measured value (number, string, enum, or `[TimeSpan]`). Passing `-Value` (or `-Unit`) makes the node a leaf check; omitting both creates a container package. |
| `Unit` | `2` | `System.String` | `''` | Icinga unit of the value and thresholds (e.g. `'%'`, `'B'`, `'s'`, `'c'`). |

### Return Value

* **`IcingaPlugin`** -- A new plugin node created with the `IcingaPlugin` type of the current runspace.

### Examples

```powershell
# 1. Create a container package (name only)
$CheckPackage = New-IcingaPlugin 'Disks';

# 2. Create a leaf check with positional arguments (Name, Value, Unit) and chain methods
$CheckPackage.AddCheck(
    (New-IcingaPlugin 'C:' 55 '%').Warning('80').Critical('90').CheckRange()
).Commit();

# 3. Create a leaf check with a TimeSpan value (automatically converted to seconds with Unit = 's')
$CheckPackage.AddCheck(
    (New-IcingaPlugin 'Last Run' ([TimeSpan]::FromMinutes(15))).Warning('30m').CheckRange()
).Commit();
```

---

## 2. `IcingaPlugin` Class Properties

The `IcingaPlugin` class is defined in [`src/Classes/Icinga/IcingaPlugin.ps1`](../../../src/Classes/Icinga/IcingaPlugin.ps1).

### Public Instance Properties (10)

These properties form the public state surface of an `IcingaPlugin` node. Each boolean/integer flag also has a corresponding fluent `Set*` method for method chaining.

| Property | Type | Default | Fluent Setter | Description |
|----------|------|---------|---------------|-------------|
| `Name` | `System.String` | `''` | *(constructor)* | Display name rendered in the output line (`[STATE] Name: message`) and used as the fallback for the `MetricLabel` performance-data segment. |
| `Value` | `System.Object` | `$null` | *(constructor)* | Measured value of a leaf check (`$null` for a pure container). When a `[TimeSpan]` is passed to the constructor, `Value` stores `.TotalSeconds` (`[double]`). |
| `Unit` | `System.String` | `''` | *(constructor)* | Unit of the check (`'B'` for base bytes, `'s'` for base seconds, `'%'`, `'c'`, or a display unit). Defaults to `'s'` when a `[TimeSpan]` value is passed with an empty unit. |
| `Verbose` | `System.Int32` | `0` | `SetVerbose([int])` | Verbosity level (`0`..`3`) controlling output pruning and package configuration suffixes. |
| `NoPerfData` | `System.Boolean` | `$false` | `SetNoPerfData()`<br>`SetNoPerfData([bool])` | When `$true`, suppresses performance-data generation and collection for this node and its entire subtree. |
| `IsHidden` | `System.Boolean` | `$false` | `SetHidden()`<br>`SetHidden([bool])` | When `$true`, hides the node from text output, state aggregation, and summary counts while still collecting its performance data. |
| `IsNotice` | `System.Boolean` | `$false` | `SetNotice()` | When `$true`, marks the package or leaf as an `[INFO]` notice that stays `OK` (`0`) and does not affect parent state aggregation or summary counts. |
| `IgnoreEmptyPackage` | `System.Boolean` | `$false` | `SetIgnoreEmptyPackage()`<br>`SetIgnoreEmptyPackage([bool])` | When `$true`, an empty container without visible checks resolves to `OK` (`0`) instead of `UNKNOWN` (`'No checks added to this object'`). |
| `AddSummaryHeader` | `System.Boolean` | `$false` | `SetSummaryHeader()`<br>`SetSummaryHeader([bool])` | When `$true`, renders the per-state leaf summary count header on a nested container (`Indention > 0`) just like on the root container. |
| `SkipSummary` | `System.Boolean` | `$false` | `SetSkipSummary()`<br>`SetSkipSummary([bool])` | When `$true`, excludes this leaf check from the container's summary header counts (`1 Critical 2 Ok`) while keeping its output line and state aggregation. |

### Hidden Instance Properties (30)

These properties hold the internal configuration, evaluation state, and tree pointers of the node. They are manipulated through the public fluent methods:

| Property | Type | Default | Controlled By | Description |
|----------|------|---------|---------------|-------------|
| `State` | `System.Int32` | `0` | `EscalateState()`, `SetState()`, `ResolveState()` | Numeric Icinga plugin state (`0` OK, `1` WARNING, `2` CRITICAL, `3` UNKNOWN). |
| `Locked` | `System.Boolean` | `$false` | `SetState(..., $true)`, `SetError()` | When `$true`, freezes `State` and `OutputMessage` against any later evaluation, escalation, or override. |
| `FixedState` | `System.Boolean` | `$false` | `SetState()`, `ResolveState()` | `$true` when `State` was explicitly set by an override (prevents unevaluated nodes from rendering as `[INFO]`). |
| `IsNoticeObject` | `System.Boolean` | `$false` | `SetNotice([string])`, `SetNotice([string], [bool])` | `$true` when a leaf node was marked as a notice with a message via `SetNotice([string])`. |
| `IgnoredEmpty` | `System.Boolean` | `$false` | `ResolveState()` | Set during `ResolveState()` when an empty container was ignored via `IgnoreEmptyPackage`, so parent containers skip it in counts. |
| `Evaluated` | `System.Boolean` | `$false` | `ApplyThresholdResult()` | `$true` once any comparison method (`CheckRange`, `CheckIn`, etc.) has evaluated the node. |
| `HasError` | `System.Boolean` | `$false` | `ApplyError()` / `SetError()` | `$true` when `.SetError(...)` was called; causes a container to print its error message instead of the summary header. |
| `OutputMessage` | `System.String` | `''` | Comparisons, `SetState()`, `EnsureLeafDefaults()` | Human-readable message rendered after `Name: ` on the node's output line. |
| `Indention` | `System.Int32` | `0` | `AddCheck()`, `PropagateIndention()` | Zero-based tree depth (`0` at root, incremented for each level of nesting). |
| `Parent` | `IcingaPlugin` | `$null` | `AddCheck()` | Reference to the parent container node (`$null` at root). |
| `Checks` | `System.Array` | `@()` | `AddCheck()` | Array of child `IcingaPlugin` nodes attached to this container. |
| `PerfData` | `System.Array` | `@()` | `BuildPerfData()` | Array holding this leaf node's formatted performance-data metric string. |
| `Operator` | `System.String` | `'And'` | `CheckAnd()`, `CheckOr()`, `CheckNone()`, `CheckDefault()` | Container aggregation operator: `'And'`, `'Or'`, or `'None'`. |
| `OperatorMin` | `System.Int32` | `-1` | `CheckMinimum([int])` | Minimum number of children that must be `OK` (`-1` when unset). Takes precedence over `Operator`. |
| `OperatorMax` | `System.Int32` | `-1` | `CheckMaximum([int])` | Maximum number of children that may be `OK` (`-1` when unset). Takes precedence over `Operator` and can be combined with `OperatorMin`. |
| `WarningThreshold` | `System.String` | `''` | `Warning()` | Configured warning threshold string (or comma-separated display string when a multi-value array of 2+ items was passed). |
| `CriticalThreshold` | `System.String` | `''` | `Critical()` | Configured critical threshold string (or comma-separated display string when a multi-value array of 2+ items was passed). |
| `WarningList` | `System.Array` | `@()` | `Warning([array])` | Cleaned string array of warning entries when 2 or more threshold items were passed to `.Warning([array])` (`@()` otherwise). |
| `CriticalList` | `System.Array` | `@()` | `Critical([array])` | Cleaned string array of critical entries when 2 or more threshold items were passed to `.Critical([array])` (`@()` otherwise). |
| `ResolvedWarning` | `System.String` | `''` | `ApplyThresholdResult()` | Warning threshold resolved to base units by the last numeric comparison, used for performance data. |
| `ResolvedCritical` | `System.String` | `''` | `ApplyThresholdResult()` | Critical threshold resolved to base units by the last numeric comparison, used for performance data. |
| `MinimumValue` | `System.String` | `''` | `Minimum([object])` | Formatted `min` bound emitted in the performance-data string. |
| `MaximumValue` | `System.String` | `''` | `Maximum([object])` | Formatted `max` bound emitted in the performance-data string. |
| `BaseValueSetting` | `System.Object` | `$null` | `BaseValue([object])` | Base/total value used to resolve percentage thresholds (e.g. `'80%'` of `'500GB'`) and `CheckMax()`. |
| `MetricIndexValue` | `System.String` | `''` | `MetricIndex([string])` | Custom `index` segment for the `check_multi` performance-data label. |
| `MetricNameValue` | `System.String` | `''` | `MetricName([string])` | Custom `template` segment for the `check_multi` performance-data label. |
| `MetricLabelValue` | `System.String` | `''` | `MetricLabel([string])` | Custom `label` segment for the `check_multi` performance-data label. |
| `CheckCommand` | `System.String` | `''` | `Initialize()` -> `DetectCheckCommand()` | Calling `Invoke-IcingaCheck*` command detected from the PowerShell call stack at construction time. |
| `Translation` | `System.Collections.Hashtable` | `@{}` | `Translate([hashtable])` | Lookup table mapping raw values (such as integer status codes) to human-readable strings. |
| `TranslatedText` | `System.String` | `''` | `Translate()`, `Translate([string])` | Explicit display string for `Value` set by `.Translate()` or `.Translate([string])`. |

### Static Hidden Properties (2)

| Property | Type | Value | Description |
|----------|------|-------|-------------|
| `StateText` | `System.Collections.Hashtable` | `@{ 0 = '[OK]'; 1 = '[WARNING]'; 2 = '[CRITICAL]'; 3 = '[UNKNOWN]' }` | Maps integer state codes (`0`..`3`) to their bracketed output status tags. |
| `StateMap` | `System.Collections.Hashtable` | `@{ 'ok' = 0; 'warning' = 1; 'critical' = 2; 'unknown' = 3; '0' = 0; '1' = 1; '2' = 2; '3' = 3 }` | Maps lower-cased state names and numeric strings to integer state codes in `ResolveStateCode()`. |

---

## 3. Constructors

> **Important:** Inside functions (outside `src/Classes/`), always use [`New-IcingaPlugin`](#1-new-icingaplugin-factory-cmdlet) rather than calling `[IcingaPlugin]::new(...)` directly.

### Overload Summary

| Signature | Purpose |
|-----------|---------|
| `IcingaPlugin([string]$Name)` | Creates a plugin node with a name only (`Value = $null`, `Unit = ''`), typically used as a container package. |
| `IcingaPlugin([string]$Name, [object]$Value)` | Creates a leaf check with a name and measured value, without a unit (`Unit = ''`, or `'s'` if `$Value` is a `[TimeSpan]`). |
| `IcingaPlugin([string]$Name, [object]$Value, [string]$Unit)` | Creates a leaf check with a name, measured value, and Icinga unit. |

### Overload Details

All three constructors delegate to `hidden [void] Initialize([string]$Name, [object]$Value, [string]$Unit)`:
* Stores `$this.Name = $Name`.
* If `$Value -is [TimeSpan]`, converts `$Value` to `([TimeSpan]$Value).TotalSeconds` and sets `$this.Unit = 's'` when `$Unit` is `''` (otherwise keeps `$Unit`).
* For all other values, stores `$this.Value = $Value` and `$this.Unit = $Unit` verbatim.
* Walks the PowerShell call stack via `DetectCheckCommand()` and stores the first `Invoke-IcingaCheck*` frame name in `$this.CheckCommand`.

---

## 4. Fluent Configuration & Metadata Methods

All methods in this section configure the node and return `[IcingaPlugin]` (`$this`) for fluent chaining.

---

### `Warning` -- Set the Warning Threshold

Configures the warning threshold for subsequent comparison methods (`CheckRange`, `CheckIn`, `CheckEqual`, etc.). Does not evaluate the threshold until a comparison method is called.

| Overload | Parameter Type | Description |
|----------|----------------|-------------|
| `Warning([string]$Warning)` | `System.String` | Stores `$Warning` verbatim in `WarningThreshold` and resets `WarningList = @()`. Pass `''` to clear. |
| `Warning([array]$Warning)` | `System.Array` | Filters out `$null` and empty entries and normalizes each item via `ConvertThresholdEntry()`.<ul><li>`0` cleaned items: sets `WarningList = @()` and `WarningThreshold = ''`.</li><li>`1` cleaned item: sets `WarningList = @()` and `WarningThreshold = [string]$Cleaned[0]`.</li><li>`2+` cleaned items: sets `WarningList = $Cleaned` and `WarningThreshold = ($Cleaned -join ', ')`.</li></ul> |
| `Warning([object]$Warning)` | `System.Object` | If `$Warning -is [array]`, delegates to `Warning([array]$Warning)`. Otherwise resets `WarningList = @()` and sets `WarningThreshold = $this.ConvertThresholdEntry($Warning)` (converting `[TimeSpan]` to `'<seconds>s'`, floating-point numbers to invariant fixed-point strings, and `$null` to `''`). |

```powershell
$Check.Warning('80%')
$Check.Warning(@('Paused', 'Pending'))
$Check.Warning([TimeSpan]::FromMinutes(30))
```

---

### `Critical` -- Set the Critical Threshold

Configures the critical threshold for subsequent comparison methods.

| Overload | Parameter Type | Description |
|----------|----------------|-------------|
| `Critical([string]$Critical)` | `System.String` | Stores `$Critical` verbatim in `CriticalThreshold` and resets `CriticalList = @()`. Pass `''` to clear. |
| `Critical([array]$Critical)` | `System.Array` | Filters and normalizes the array via `CleanThresholdList()`. Stores 0 items as `''`, 1 item in `CriticalThreshold` with `CriticalList = @()`, and 2+ items in both `CriticalList` and comma-joined `CriticalThreshold`. |
| `Critical([object]$Critical)` | `System.Object` | If `$Critical -is [array]`, delegates to `Critical([array]$Critical)`. Otherwise resets `CriticalList = @()` and sets `CriticalThreshold = $this.ConvertThresholdEntry($Critical)`. |

```powershell
$Check.Critical('90%')
$Check.Critical(@('Ready', 'Running'))
$Check.Critical([TimeSpan]::FromHours(1))
```

---

### `Minimum` & `Maximum` -- Set Performance-Data Bounds

Sets the `min` and `max` fields of the node's performance-data metric (`label=value;warn;crit;min;max`). Does not affect threshold evaluation. If the node was already evaluated (`$this.Evaluated -eq $true`), calls `$this.BuildPerfData()` immediately so the updated bound is reflected even when chained after `.CheckRange()`.

| Method | Parameter Type | Description |
|--------|----------------|-------------|
| `Minimum([object]$Minimum)` | `System.Object` | Sets `MinimumValue` via `$this.FormatNumber($Minimum)` (or `''` when `$null` or empty). Rebuilds `PerfData` if already evaluated. |
| `Maximum([object]$Maximum)` | `System.Object` | Sets `MaximumValue` via `$this.FormatNumber($Maximum)` (or `''` when `$null` or empty). Rebuilds `PerfData` if already evaluated. |

```powershell
(New-IcingaPlugin 'CPU Load' 42 '%').Minimum(0).Maximum(100).Warning('80').Critical('90').CheckRange().Commit();
```

---

### `BaseValue` -- Set the Reference Value for Percentage Thresholds and `CheckMax`

| Overload | Parameter Type | Description |
|----------|----------------|-------------|
| `BaseValue([object]$BaseValue)` | `System.Object` | Stores the reference/maximum value in `BaseValueSetting` for percentage thresholds (e.g. `'80%'` of `'500GB'`) and `CheckMax()`. If `$BaseValue -is [TimeSpan]`, stores `([TimeSpan]$BaseValue).TotalSeconds`. |

```powershell
(New-IcingaPlugin 'C: Used' 400000000000 'B').BaseValue('500GB').Warning('80%').Critical('90%').CheckRange().Commit();
```

---

### `MetricIndex`, `MetricName`, `MetricLabel` -- Customize Performance-Data Labels

Override individual segments of the `check_multi` performance-data label (`<index>::ifw_<template>::<label>`). During `.Compile()`, `EnsureLeafDefaults()` rebuilds `PerfData` so these settings take effect regardless of where they appear in the fluent chain.

| Method | Parameter Type | Default / Fallback | Description |
|--------|----------------|--------------------|-------------|
| `MetricIndex([string]$Index)` | `System.String` | `'default'` | Sets `MetricIndexValue` (`<index>`), grouping metrics of the same instance (e.g. partition letter `'c'` or task path). |
| `MetricName([string]$Name)` | `System.String` | Calling `Invoke-IcingaCheck*` suffix or `'check'` | Sets `MetricNameValue` (`ifw_<template>`). A leading `ifw_` is never doubled. |
| `MetricLabel([string]$Label)` | `System.String` | Node `Name` (or `'value'` if empty after sanitizing) | Sets `MetricLabelValue` (`<label>`). |

---

### `Translate` -- Map Raw or Enum Values to Human-Readable Text

Configures value and threshold translation so human-readable names appear in the plugin output while numeric values are preserved in performance data.

| Overload | Parameter Type | Description |
|----------|----------------|-------------|
| `Translate()` | *(none)* | Parameterless overload. When `$null -ne $this.Value`, sets `$this.TranslatedText = [string]$this.Value` (converting an enum such as `[IcingaScheduledTaskStatus]::Ready` or a boolean to its string name for display while keeping the numeric enum code for performance data). |
| `Translate([hashtable]$Translation)` | `System.Collections.Hashtable` | Stores `$Translation` in `$this.Translation` (or `@{}` when `$null`). Used by `ResolveTranslation()` to map raw values and threshold tokens (e.g. `@{ 0 = 'Never' }` or `@{ 1 = 'Stopped'; 4 = 'Running' }`) to display strings. |
| `Translate([string]$Text)` | `System.String` | Directly sets `$this.TranslatedText = $Text` to override the display representation of the node's current `Value`. |

```powershell
# Enum translation (displays 'Ready', emits 3 in perfdata)
(New-IcingaPlugin 'State' ([IcingaScheduledTaskStatus]::Ready)).Translate().Critical(@('Ready', 'Running')).CheckNotIn().Commit();

# Hashtable translation (displays 'Never' when value is 0, emits 0s in perfdata)
(New-IcingaPlugin 'Last Run Time [Never]' 0 's').Translate(@{ 0 = 'Never' }).Commit();
```

---

### Output & Package Behavior Setters (`SetVerbose`, `SetNoPerfData`, `SetHidden`, `SetIgnoreEmptyPackage`, `SetSummaryHeader`, `SetSkipSummary`)

Each boolean setter provides both a parameterless overload (enabling the flag with `$true`) and a `[bool]` overload so callers can either chain `.SetHidden()` or pass a switch parameter `.SetNoPerfData($NoPerfData)`:

| Method Overloads | Property Updated | Description |
|------------------|------------------|-------------|
| `SetVerbose([int]$Verbose)` | `Verbose` | Sets the verbosity level (`0`..`3`). Propagated from the root container to all descendants during `.Compile()`. |
| `SetNoPerfData()`<br>`SetNoPerfData([bool]$NoPerfData)` | `NoPerfData` | Disables performance-data generation and collection for this node and all of its descendants. |
| `SetHidden()`<br>`SetHidden([bool]$Hidden)` | `IsHidden` | Hides the node from text output, state aggregation, and summary counts at all verbosity levels while keeping its performance data. |
| `SetIgnoreEmptyPackage()`<br>`SetIgnoreEmptyPackage([bool]$Ignore)` | `IgnoreEmptyPackage` | When enabled on a container without visible checks, resolves the container to `OK` (`0`) instead of `UNKNOWN` (`'No checks added to this object'`). |
| `SetSummaryHeader()`<br>`SetSummaryHeader([bool]$AddHeader)` | `AddSummaryHeader` | Forces a nested container (`Indention > 0`) to render the per-state leaf summary header just like the root node. |
| `SetSkipSummary()`<br>`SetSkipSummary([bool]$Skip)` | `SkipSummary` | Excludes a leaf check from the container's summary header counts (`1 Critical 2 Ok`) while keeping its output line and state aggregation. |

---

## 5. Threshold & Comparison Methods

Every comparison method evaluates the node's `Value` against the configured `Warning` and `Critical` thresholds via `ApplyThresholdResult()`, marks `Evaluated = $true`, updates `State`, `OutputMessage`, `ResolvedWarning`, `ResolvedCritical`, and `PerfData`, and returns `[IcingaPlugin]` (`$this`).

### Numeric and Range Comparisons

All numeric comparison methods delegate to `IcingaThresholds` (created via `NewThresholds()`) and pass `$this.AttachBaseUnit($this.Value)` so byte (`'B'`) and time (`'s'`) nodes automatically resolve unit thresholds (`'400GB'`, `'30m'`) and percentage thresholds (`'80%'`).

| Method | Parameters | Alert Condition & Description |
|--------|------------|-------------------------------|
| `CheckRange()` | *(none)* | **Standard Icinga range check.** Evaluates `Value` against `WarningThreshold` and `CriticalThreshold` using Icinga range syntax (`10`, `10:`, `~:10`, `10:20`, `@10:20`). Supports unit conversions (`'500MB'`, `'30m'`) and percentage thresholds (`'80%'`). |
| `CheckGreater()` | *(none)* | Raises WARNING/CRITICAL when `Value > Threshold`. |
| `CheckGreaterEqual()` | *(none)* | Raises WARNING/CRITICAL when `Value >= Threshold`. |
| `CheckLower()` | *(none)* | Raises WARNING/CRITICAL when `Value < Threshold`. |
| `CheckLowerEqual()` | *(none)* | Raises WARNING/CRITICAL when `Value <= Threshold`. |
| `CheckMax()` | *(none)* | Requires `.BaseValue(...)`. Evaluates `Value` against thresholds relative to `BaseValueSetting` via `IcingaThresholds.CheckMax()` (returns `UNKNOWN` if no base value is set). |

### String, Pattern, and Multi-Value List Comparisons

All methods below support **both** a single threshold (`Warning([string])` / `Warning([object])`) and a multi-value threshold list (`Warning([array])` / `Critical([array])` with 2+ items). When a translation is active (`.Translate()`), both the node's value (`ResolveStringValue()`) and the threshold entries (`NewStringThresholds()` / `ResolveThresholdList()`) are resolved to their translated display strings before comparison, and `Critical` is always evaluated before `Warning`:

| Method | Single-Value Behaviour (`IcingaThresholds`) | Multi-Value Array Behaviour (`EvaluateListComparison`) |
|--------|---------------------------------------------|--------------------------------------------------------|
| `CheckMatch()` | Alerts when the string value matches the regex threshold (`IcingaThresholds.CheckMatch`). | Alerts when the string value matches **any** regex pattern in the list (`-match`). Invalid regex patterns return `UNKNOWN` (`3`). Output: `"'<Val>' matches pattern '<Matched>'"`. |
| `CheckNotMatch()` | Alerts when the string value does **not** match the regex threshold (`IcingaThresholds.CheckNotMatch`). | Alerts when the string value matches **none** of the regex patterns in the list. Invalid regex patterns return `UNKNOWN` (`3`). Output: `"'<Val>' does not match pattern '<List>'"`. |
| `CheckLike()` | Alerts when the string value matches the wildcard pattern (`-like`). | Alerts when the string value matches **any** wildcard pattern in the list (`-like`). Output: `"'<Val>' is like pattern '<Matched>'"`. |
| `CheckNotLike()` | Alerts when the string value does **not** match the wildcard pattern (`-notlike`). | Alerts when the string value matches **none** of the wildcard patterns in the list. Output: `"'<Val>' is not like pattern '<List>'"`. |
| `CheckEqual()` | Alerts when the string value equals the threshold (case-insensitive). | Alerts when the string value equals **any** entry in the list (case-insensitive `-eq`). Output: `"'<Val>' equals pattern '<Matched>'"`. |
| `CheckNotEqual()` | Alerts when the string value does **not** equal the threshold (case-insensitive). | Alerts when the string value does **not** equal any entry in the allowed list. Output: `"'<Val>' does not equal pattern '<List>'"`. |
| `CheckIn()` | Delegates to `CheckEqual()`. Alerts when the value equals the threshold. | Delegates to `CheckEqual()`. Alerts when the value is found in the forbidden list. |
| `CheckNotIn()` | Delegates to `CheckNotEqual()`. Alerts when the value does not equal the threshold. | Delegates to `CheckNotEqual()`. Alerts when the value is **not** found in the allowed list. |

---

## 6. State Override, Notice & Error Methods

Override methods force a node into a specific state regardless of prior threshold evaluations (unless the node is already `Locked`). When `$Lock` is `$true`, the node is frozen so no subsequent comparison, escalation, or override can alter its `State` or `OutputMessage`.

---

### `SetState` -- Force a State by Code or Name (6 Overloads)

| Overload | Parameters | Description |
|----------|------------|-------------|
| `SetState([int]$State)` | `State`: `0`..`3` | Delegates to `SetState($State, '', $false)`. Forces `State` without changing `OutputMessage` or locking. |
| `SetState([int]$State, [string]$Message)` | `State`: `0`..`3`<br>`Message`: output text (`''` keeps current) | Delegates to `SetState($State, $Message, $false)`. Forces `State` and updates `OutputMessage` when non-empty. |
| `SetState([int]$State, [string]$Message, [bool]$Lock)` | `State`: `0`..`3`<br>`Message`: output text<br>`Lock`: freeze node | Central state override. Unless `Locked`, sets `FixedState = $true`, `IsNoticeObject = $false`, `State = $State` (may also lower the state), and replaces `OutputMessage` when `'' -ne $Message`. When `$Lock` is `$true`, sets `Locked = $true`. |
| `SetState([string]$State)` | `State`: `'Ok'`, `'Warning'`, `'Critical'`, `'Unknown'` (or `'0'`..`'3'`) | Resolves the state name case-insensitively via `ResolveStateCode()` (unknown strings default to `3`) and delegates to `SetState([int], '', $false)`. |
| `SetState([string]$State, [string]$Message)` | `State`: state name<br>`Message`: output text | Resolves the state name and delegates to `SetState([int], $Message, $false)`. |
| `SetState([string]$State, [string]$Message, [bool]$Lock)` | `State`: state name<br>`Message`: output text<br>`Lock`: freeze node | Resolves the state name and delegates to `SetState([int], $Message, $Lock)`. Ideal for plugin parameters like `-OverrideNotOk`. |

---

### `SetOk`, `SetWarning`, `SetCritical`, `SetUnknown` -- State Convenience Wrappers (3 Overloads Each)

Each state has three overloads that delegate directly to `SetState([int], [string], [bool])`:

| Method Family | Overloads | Forced State |
|---------------|-----------|--------------|
| **`SetOk`** | `SetOk()` -> `SetState(0, '', $false)`<br>`SetOk([string]$Message)` -> `SetState(0, $Message, $false)`<br>`SetOk([string]$Message, [bool]$Lock)` -> `SetState(0, $Message, $Lock)` | `0` (`[OK]`) |
| **`SetWarning`** | `SetWarning()` -> `SetState(1, '', $false)`<br>`SetWarning([string]$Message)` -> `SetState(1, $Message, $false)`<br>`SetWarning([string]$Message, [bool]$Lock)` -> `SetState(1, $Message, $Lock)` | `1` (`[WARNING]`) |
| **`SetCritical`** | `SetCritical()` -> `SetState(2, '', $false)`<br>`SetCritical([string]$Message)` -> `SetState(2, $Message, $false)`<br>`SetCritical([string]$Message, [bool]$Lock)` -> `SetState(2, $Message, $Lock)` | `2` (`[CRITICAL]`) |
| **`SetUnknown`** | `SetUnknown()` -> `SetState(3, '', $false)`<br>`SetUnknown([string]$Message)` -> `SetState(3, $Message, $false)`<br>`SetUnknown([string]$Message, [bool]$Lock)` -> `SetState(3, $Message, $Lock)` | `3` (`[UNKNOWN]`) |

* The **parameterless overload** (e.g. `.SetCritical()`) keeps the node's existing or auto-formatted value message (for example `[CRITICAL] Last Task Result: 1`).
* The **1-argument overload** sets a custom message without locking.
* The **2-argument overload** sets a custom message and optionally locks the node.

---

### `SetNotice` -- Mark a Node or Container as Informational (`[INFO]`) (3 Overloads)

Marks the node as an informational notice that renders with `[INFO]`, keeps state `0` (`OK`), and is excluded from parent aggregation and summary counts.

| Overload | Parameters | Description |
|----------|------------|-------------|
| `SetNotice()` | *(none)* | Unless `Locked`, sets `State = 0` and `IsNotice = $true` without changing `OutputMessage`. When called on an empty container, `ResolveState()` sets `OutputMessage = 'Nothing to report'`. |
| `SetNotice([string]$Message)` | `Message`: notice text | Delegates to `SetNotice($Message, $false)`. |
| `SetNotice([string]$Message, [bool]$Lock)` | `Message`: notice text<br>`Lock`: freeze node | Unless `Locked`, sets `State = 0`, `IsNoticeObject = $true`, and updates `OutputMessage` when `'' -ne $Message`. Locks the node when `$Lock` is `$true`. |

---

### `SetError` -- Lock a Node or Container in `UNKNOWN` Due to a Collection Failure (6 Overloads)

All `SetError` overloads funnel through `hidden [IcingaPlugin] ApplyError([string]$Message)`, which sets `HasError = $true` (when not already locked) and calls `SetState(3, $Message, $true)` to lock the node in `UNKNOWN` (`3`). When called on a container, `BuildContainerLine()` prints `[UNKNOWN] Name: <Message>` instead of the summary header.

| Overload | Parameters | Description |
|----------|------------|-------------|
| `SetError([string]$Message)` | `Message`: literal error text | Locks the node in `UNKNOWN` with `$Message` verbatim (no placeholder formatting). |
| `SetError([string]$Message, [object]$Argument)` | `Message`: format string<br>`Argument`: `{0}` value | Formats `$Message` with `@($Argument)` via `[IcingaError]::FormatMessage()` (never throws) and locks in `UNKNOWN`. |
| `SetError([string]$Message, [object]$Argument1, [object]$Argument2)` | `Message`: format string<br>`Argument1`, `Argument2`: `{0}`, `{1}` | Formats `$Message` with `@($Argument1, $Argument2)` and locks in `UNKNOWN`. |
| `SetError([string]$Message, [object]$Argument1, [object]$Argument2, [object]$Argument3)` | `Message`: format string<br>`Argument1`..`3`: `{0}`..`{2}` | Formats `$Message` with `@($Argument1, $Argument2, $Argument3)` and locks in `UNKNOWN`. |
| `SetError([string]$Message, [object[]]$Arguments)` | `Message`: format string<br>`Arguments`: placeholder array | Formats `$Message` with `$Arguments` and locks in `UNKNOWN`. |
| `SetError([IcingaError]$IcingaError)` | `IcingaError`: error object from provider | Extracts `$IcingaError.Message` (or `'An unknown error occurred'` if `$null -eq $IcingaError`) and locks the node in `UNKNOWN`. |

```powershell
$Tasks = Get-IcingaScheduledTask -TaskName $TaskName;
if (Test-IcingaError -InputObject $Tasks) {
    return $CheckPackage.SetError($Tasks).Compile();
}
```

---

## 7. Container Aggregation & Tree Management Methods

### Aggregation Operator Methods

By default, a container uses `CheckAnd()` (`Operator = 'And'`, all children must be `OK`). Calling `CheckMinimum` or `CheckMaximum` (`OperatorMin` / `OperatorMax`) takes precedence over `And`/`Or`/`None` (and both may be combined). When a count rule or `CheckNone` is violated even though all children are `OK` (`$Worst -eq 0`), `ResolveState()` escalates the container to at least `CRITICAL` (`[System.Math]::Max($Worst, 2)`).

| Method | Parameters | Aggregation Rule & Verbosity 3 Config Text (`ShowPackageConfig()`) |
|--------|------------|--------------------------------------------------------------------|
| `CheckAnd()` | *(none)* | Sets `Operator = 'And'`. All visible non-notice children must be `OK`. Config text: `' (All must be [OK])'`. |
| `CheckDefault()` | *(none)* | Sets `Operator = 'And'` (identical to `CheckAnd()`). |
| `CheckOr()` | *(none)* | Sets `Operator = 'Or'`. At least one visible non-notice child must be `OK`. Config text: `' (Atleast one must be [OK])'`. |
| `CheckNone()` | *(none)* | Sets `Operator = 'None'`. No visible non-notice child may be `OK` (raises `CRITICAL` if any child is `OK`). Config text: `''`. |
| `CheckMinimum([int]$Count)` | `Count`: min OK children | Sets `OperatorMin = $Count`. At least `$Count` children must be `OK`. Config text: `' (Atleast {0} must be [OK])'` (or `' (Between {0} and {1} must be [OK])'` when combined with `CheckMaximum`). |
| `CheckMaximum([int]$Count)` | `Count`: max OK children | Sets `OperatorMax = $Count`. At most `$Count` children may be `OK`. Config text: `' (Not more than {0} must be [OK])'`. |

---

### `AddCheck` -- Attach Child Nodes to a Container (2 Overloads)

| Overload | Parameters | Description |
|----------|------------|-------------|
| `AddCheck([IcingaPlugin]$Check)` | `Check`: child node | Ignores `$null`. Sets `$Check.Parent = $this`, `$Check.Indention = $this.Indention + 1`, `$Check.Verbose = $this.Verbose`, calls `$Check.PropagateIndention()`, and appends `$Check` to `$this.Checks`. Returns `$this`. |
| `AddCheck([array]$Checks)` | `Checks`: array of child nodes | Iterates over `$Checks` and calls `$this.AddCheck($Check)` for each element. Returns `$this`. |

---

### `AddMissingChecks` -- Automatically Report Missing Required Objects (4 Overloads)

Compares an array of required object names/patterns (`$Required`) against the entries found on the host (`$Available`) using case-insensitive wildcard matching (`ContainsMatch()`). For every required entry without a match, adds a locked child check named via `[IcingaError]::FormatMessage($NameFormat, @($Normalized))` in the given `$State` with `$Message`.

| Overload | Parameters | Description |
|----------|------------|-------------|
| `AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [int]$State)` | `Required`: required names<br>`Available`: found names<br>`NameFormat`: e.g. `'Service {0}'`<br>`Message`: error text<br>`State`: `0`..`3` | Delegates to the 6-argument overload with `NormalizePattern = ''`. |
| `AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [int]$State, [string]$NormalizePattern)` | Same + `NormalizePattern`: regex stripped before matching/naming | Strips matches of `$NormalizePattern` (for example `'[:\\/]+$'` to normalize `'C:\'` to `'C'`) and checks both the raw and normalized entry against `$Available`. |
| `AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [string]$State)` | Same with `State` as string (`'Ok'`, `'Warning'`, `'Critical'`, `'Unknown'`) | Resolves `$State` via `ResolveStateCode()` and delegates with `NormalizePattern = ''`. Ideal for `-OverrideNotFound` parameters. |
| `AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [string]$State, [string]$NormalizePattern)` | Same with `State` as string + `NormalizePattern` | Resolves `$State` via `ResolveStateCode()` and delegates with `$NormalizePattern`. |

```powershell
$CheckPackage.AddMissingChecks(
    $RequiredServices,
    $FoundServiceNames,
    'Service {0}',
    'Service was not found on host',
    $OverrideNotFound
).Commit();
```

---

### `HasChecks` -- Test Whether Visible Child Checks Exist

| Signature | Return Type | Description |
|-----------|-------------|-------------|
| `HasChecks()` | `System.Boolean` | Returns `$true` as soon as at least one direct child in `$this.Checks` has `IsHidden -eq $false`; otherwise `$false`. |

---

## 8. Chain Terminators & Compilation (`Commit` and `Compile`)

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Commit()` | `void` | No-op method with `[void]` return type that consumes the fluent chain return value so nothing leaks to the PowerShell pipeline. |
| `Compile()` | `System.Int32` | Executes `$this.ResolveState()`, `$this.PropagateVerbose($this.Verbose)`, renders output via `$this.RenderOutput()`, collects deduplicated metrics via `$this.CollectPerfData()`, ensures `$GlobalVariable.Private.Icinga.CheckResult` exists via `EnsureResultSlot()`, stores `[IcingaCheckResult]::new($this.State, $Output, $Perf)` in `Private.Icinga.CheckResult`, calls `WriteConsoleOutput($Output, $Perf)` when `-not $GlobalVariable.Protected.IsBackgroundDaemon`, and returns `$this.State` (`0`..`3`). |

---

## 9. Internal (`hidden`) Helper Methods Reference

For framework maintainers extending `IcingaPlugin.ps1` itself, the table below lists all `hidden` methods on `IcingaPlugin`:

| Method Signature | Return Type | Purpose |
|------------------|-------------|---------|
| `Initialize([string]$Name, [object]$Value, [string]$Unit)` | `void` | Shared constructor initialization (`Name`, `Value`, `Unit`, `[TimeSpan]` conversion, and `DetectCheckCommand()`). |
| `ConvertThresholdEntry([object]$Entry)` | `System.String` | Normalizes a single threshold entry (`[TimeSpan]` -> `'<sec>s'`, floats/decimals -> `FormatNumber()`, `$null` -> `''`). |
| `CleanThresholdList([array]$Thresholds)` | `System.Array` | Filters out null/empty items and normalizes each entry through `ConvertThresholdEntry()`. |
| `ResolveThresholdList([array]$List, [string]$Fallback)` | `System.Array` | Returns the effective threshold array (from `$List` or `@($Fallback)`), mapping each entry through `ResolveTranslation()`. |
| `FindMatchingPattern([string]$InputValue, [array]$Patterns, [string]$Operator)` | `System.String` | Tests `$InputValue` against `$Patterns` using `'eq'`/`'ne'`, `'like'`/`'notlike'`, or `'match'`/`'notmatch'` and returns the first matching pattern (or `''`). |
| `EvaluateListComparison([string]$Operator, [string]$OperatorText)` | `System.Object` | Evaluates multi-value `WarningList` / `CriticalList` comparisons and returns an `IcingaThresholdResult`. |
| `NewThresholds()` | `System.Object` | Constructs an `IcingaThresholds` object for numeric comparisons, attaching base units to `BaseValueSetting` and stripping `%` on `'%'`-unit nodes when no base value is set. |
| `NewStringThresholds()` | `System.Object` | Constructs an `IcingaThresholds` object for single-value string comparisons with `WarningThreshold` and `CriticalThreshold` mapped through `ResolveTranslation()`. |
| `ResolveStringValue()` | `System.Object` | Returns the translated string representation of `$this.Value` when a translation applies, or `$this.Value` as-is. |
| `ResolveTranslation([object]$Item)` | `System.String` | Resolves `$Item` against `TranslatedText`, `Translation` (direct key, integer enum code, or case-insensitive string key), or `[System.Enum]` member name. |
| `HasBaseUnit()` | `System.Boolean` | Returns `$true` when `$this.Unit -eq 'B'` or `$this.Unit -ceq 's'`. |
| `AttachBaseUnit([object]$Value)` | `System.Object` | Appends `'B'` or `'s'` (or `'ms'`/`'us'` for sub-second durations) in fixed-point invariant format when `HasBaseUnit()` is `$true`. |
| `ApplyThresholdResult([object]$Result)` | `void` | Applies an `IcingaThresholdResult` (marks `Evaluated`, formats/humanizes `OutputMessage`, applies value translation, stores `ResolvedWarning`/`ResolvedCritical`, escalates `State`, and calls `BuildPerfData()`). |
| `ApplyValueTranslation([string]$Message)` | `System.String` | Replaces the leading numeric value token and `'threshold <num>'` token in a numeric comparison message with their translated names when configured. |
| `HumanizeByteValues([string]$Message)` | `System.String` | Converts `<number>B` tokens in an output message to their best-fit binary size via `IcingaUnit`. |
| `HumanizeTimeValues([string]$Message)` | `System.String` | Converts `<number>s` tokens in an output message to decomposed durations (`1d 2h 3m 4s`) via `IcingaUnit`. |
| `ApplyDisplayUnit([string]$Message)` | `System.String` | Appends `$this.Unit` to bare numbers in an output message (skipped when `Unit` is `''` or `'c'`). |
| `EscalateState([int]$State)` | `void` | Raises `$this.State` to `$State` when `$this.State -lt $State` and `-not $this.Locked`. |
| `ResolveStateCode([string]$State)` | `System.Int32` | Maps state names (`'Ok'`, `'Warning'`, `'Critical'`, `'Unknown'`) or `'0'`..`'3'` to `0`..`3` via `StateMap` (defaults to `3`). |
| `ApplyError([string]$Message)` | `IcingaPlugin` | Sets `HasError = $true` (unless locked) and calls `SetState(3, $Message, $true)`. |
| `ContainsMatch([array]$Entries, [string]$Pattern)` | `System.Boolean` | Tests whether any element in `$Entries` matches the wildcard `$Pattern` (`-like`), catching invalid wildcard exceptions. |
| `IsEmptyPackage()` | `System.Boolean` | Returns `$true` when the node has no visible checks, no `Value`, was not evaluated or forced into a fixed/error/notice state, and has no `OutputMessage`. |
| `IsNoticeNode()` | `System.Boolean` | Returns `$true` for notice packages (`IsNotice`), explicit notice leaves (`IsNoticeObject`), and unevaluated leaves without `FixedState` or `IgnoredEmpty`. |
| `EnsureLeafDefaults()` | `void` | Populates a default `OutputMessage` (translated, humanized, or unit-suffixed) for leaves with a `Value` and calls `BuildPerfData()`. |
| `PropagateIndention()` | `void` | Recursively updates `Indention` and `Verbose` across all descendants when a subtree is attached via `AddCheck()`. |
| `PropagateVerbose([int]$Verbose)` | `void` | Recursively applies `$Verbose` to this node and all descendants at `Compile()` time. |
| `ResolveState()` | `System.Int32` | Recursively resolves the state of the subtree, handles empty packages, counts OK vs. not-OK children, and applies `OperatorMin`/`OperatorMax` or `And`/`Or`/`None`. |
| `HasNotOkChecks()` | `System.Boolean` | Returns `$true` when any non-hidden direct child (or the node's own evaluated value) has `State -ne 0`. |
| `CanOutput()` | `System.Boolean` | Determines whether this node is included in the text output at the current `Verbose` level. |
| `IndentPrefix([int]$Indention)` | `System.String` | Builds the tree indentation prefix (`''` at level 0, `'\_ '` at level 1, `'   \_ '` at level 2, etc.). |
| `BuildLine()` | `System.String` | Dispatches to `BuildContainerLine()` when `HasChecks()` is `$true`, otherwise `BuildLeafLine()`. |
| `BuildLeafLine()` | `System.String` | Formats `'[STATE] Name: OutputMessage'` (or `'[INFO]'` for notice/unevaluated nodes). |
| `BuildContainerLine()` | `System.String` | Formats the container header line with per-state leaf counts, failing leaf name lists, and optional `ShowPackageConfig()` suffix. |
| `CollectLeafChecks()` | `System.Array` | Recursively collects active leaf checks in the subtree (skipping hidden, `SkipSummary`, notice, and `IgnoredEmpty` nodes). |
| `ShowPackageConfig()` | `System.String` | Returns the verbosity-3 operator description string (e.g. `' (All must be [OK])'`). |
| `RenderOutput()` | `System.String` | Recursively renders the indented multi-line plugin output string. |
| `ResolveNumericValue([object]$Item)` | `System.Object` | Converts enums to `[int]` and maps translated strings back to their numeric key in `Translation` for performance data. |
| `ResolvePerfDataThreshold([string]$Threshold, [string]$Resolved)` | `System.String` | Returns a valid numeric/range Icinga perfdata threshold string (mapping translated threshold names to numeric keys and omitting non-numeric regex/wildcard patterns). |
| `BuildPerfData()` | `void` | Formats `index::ifw_template::label=value<unit>;warn;crit;min;max` and stores it in `PerfData`. |
| `DetectCheckCommand()` | `System.String` | Walks `Get-PSCallStack` to find the first `Invoke-IcingaCheck*` command name. |
| `SanitizeMetric([string]$Value)` | `System.String` | Strips non-word characters (`[\W]`) and lower-cases a metric label segment. |
| `BuildPerfDataLabel()` | `System.String` | Builds the sanitized `index::ifw_template::label` identifier with `'default'`, `'ifw_check'`, and `'value'` fallbacks. |
| `CollectPerfData()` | `System.Array` | Recursively gathers and deduplicates performance-data metrics across the subtree (returning `@()` when `NoPerfData` is `$true`). |
| `IsNumeric([object]$Value)` | `System.Boolean` | Tests whether `$Value` is non-null, not a `[bool]`, and parses as a `[double]` under `InvariantCulture`. |
| `FormatNumber([object]$Value)` | `System.String` | Formats `[decimal]` / `[double]` values with `'0.##########'` under `InvariantCulture` without scientific notation. |
| `WriteConsoleOutput([string]$Output, [array]$Perf)` | `void` | Writes `$Output` and the `\| <perfdata>` line directly via `[System.Console]::WriteLine()`. |
| `EnsureResultSlot([object]$Private)` | `void` | Ensures `$Private.Icinga.CheckResult` exists on the thread-local runtime state before `Compile()` writes to it. |

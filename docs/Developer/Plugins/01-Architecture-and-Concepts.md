# Plugin Architecture and Core Concepts

Icinga for Windows provides a unified, fluent object model for building monitoring check plugins. Instead of splitting check items, check packages, and result compilation across three separate cmdlets (`New-IcingaCheck`, `New-IcingaCheckPackage`, and `New-IcingaCheckResult`), every check node, container package, and root plugin is represented by a single class: **`IcingaPlugin`**, instantiated through the runspace-safe factory cmdlet **[`New-IcingaPlugin`](02-IcingaPlugin-Reference.md#1-new-icingaplugin-factory-cmdlet)**.

This document explains how the plugin architecture works under the hood, how nodes are structured and evaluated, and which rules must be followed when developing plugins.

* **[01 - Plugin Architecture and Core Concepts](01-Architecture-and-Concepts.md)** *(this page)*
* **[02 - IcingaPlugin Technical Reference](02-IcingaPlugin-Reference.md)**
* **[03 - Result and Error Objects (`IcingaCheckResult` & `IcingaError`)](03-Result-and-Error-Objects.md)**
* **[04 - Step-by-Step Developer Guide: Writing a Custom Plugin](04-Custom-Plugin-Developer-Guide.md)**

---

## 1. Unified Node Model: Checks, Containers, and Hybrid Nodes

Every node created by `New-IcingaPlugin` is an instance of `IcingaPlugin` that can act in one of four roles depending on how it is constructed and used:

| Role | Construction | Behaviour |
|------|--------------|-----------|
| **Container (Check Package)** | `New-IcingaPlugin 'Disks'` | Holds no measured value of its own (`Value = $null`). Aggregates child nodes added via `.AddCheck()` according to its operator (`CheckAnd`, `CheckOr`, `CheckNone`, `CheckMinimum`, `CheckMaximum`). |
| **Leaf Check** | `New-IcingaPlugin 'C: Used' 75 '%'` | Holds a measured `Value` and an optional `Unit`. Evaluates the value against warning/critical thresholds and emits performance data. |
| **Hybrid Node** | `(New-IcingaPlugin 'Cluster' 1).Warning('1').CheckRange()` + `.AddCheck(...)` | Carries both its own evaluated `Value` and child checks. Its own evaluated state counts as one additional element alongside its children during aggregation. |
| **Informational Notice (`[INFO]`)** | `(New-IcingaPlugin 'Driver' 'v1.2').SetNotice()` or unevaluated leaf | Renders with an `[INFO]` prefix, always stays in state `OK` (`0`), and is excluded from parent state aggregation and root summary counts. |

Because containers and leaf checks share the same class, trees can be nested to arbitrary depth (for example: a root package `Scheduled Tasks` -> per-folder sub-packages `\Icinga\` -> per-task sub-packages `Renew Certificate` -> leaf checks `State`, `Missed Runs`, `Last Run Time`, `Last Task Result`).

---

## 2. Fluent Chaining: `.Commit()` vs. `.Compile()`

Every configuration setter, comparison method, state override, and tree operation on `IcingaPlugin` returns `$this` (the node itself) so calls can be chained fluently.

Because PowerShell sends any uncaptured return value to the output pipeline, **every fluent chain must be consumed** by an assignment, passed as an argument to `.AddCheck(...)`, or terminated with `.Commit()` or `.Compile()`:

* **`.Commit()`** has a `[void]` return type. Use it at the end of every non-returning configuration or `.AddCheck(...)` statement so the node is not leaked to the PowerShell pipeline (replacing `| Out-Null` or `[void]` casts).
* **`.Compile()`** resolves the entire check tree, writes the formatted plugin output and performance data to the console (when running on the main thread), stores an [`IcingaCheckResult`](03-Result-and-Error-Objects.md#1-icingacheckresult-class) in `$Global:IcingaForWindows.Private.Icinga.CheckResult`, and returns the numeric Icinga exit code (`0` OK, `1` WARNING, `2` CRITICAL, `3` UNKNOWN). Use `return $CheckPackage.Compile();` as the final return statement of your plugin.

```powershell
$CheckPackage = New-IcingaPlugin 'Partition Space';

$DiskCheck = (New-IcingaPlugin 'Partition C:' 442692000000 'B').BaseValue('500GiB').Minimum(0).Maximum(536870912000);
$DiskCheck.MetricIndex('c').MetricLabel('Used Space').Warning('80%').Critical('90%').CheckRange().Commit();

$CheckPackage.AddCheck($DiskCheck).Commit();

return $CheckPackage.Compile();
```

> **PowerShell Multiline Chaining Note:** If you split a fluent method chain across multiple lines in PowerShell, keep the dot `.` at the **end** of each line (not at the start of the next line), or assign the intermediate node to a variable as shown above.

---

## 3. Runspace and Threading Safety (No Class Literals in Functions)

Icinga for Windows loads its PowerShell classes (`lib/IcingaForWindows.Classes.ps1`) separately into each runspace, whereas all runspaces dot-source the shared compiled kernel (`lib/IcingaForWindows.Kernel.ps1`).

In Windows PowerShell 5.1, a class literal such as `[IcingaPlugin]::new()` or `-is [IcingaError]` inside a function is bound at parse time to the class type of the **main** runspace:

1. **Cross-thread stalls:** Calling a constructor or method on the main runspace's class type from a background worker thread blocks until the main runspace is idle, which stalls background daemons and API workers.
2. **Type mismatches:** An `IcingaError` created with a worker thread's own runspace type does not match `-is [IcingaError]` against the main runspace's type.

Therefore, **functions outside `src/Classes` must never use class literals**:

| Task | Forbidden (Class Literal) | Required (Runspace-Safe) |
|------|---------------------------|--------------------------|
| Create a plugin node | `[IcingaPlugin]::new('Disks')` | `New-IcingaPlugin 'Disks'` |
| Test for an `IcingaError` | `$Data -is [IcingaError]` | `Test-IcingaError -InputObject $Data` |
| Create an `IcingaError` | `[IcingaError]::new('Failed')` | `('IcingaError' -as [type])::new('Failed')` |

> **Note:** Native PowerShell `enum` types (such as `[IcingaServiceStatus]` or `[IcingaScheduledTaskStatus]`) contain no script methods and convert by value, so enum literals are safe to use in `param()` blocks and function bodies. This rule is enforced by `Tests/ClassLiteral.Tests.ps1`. For full background threading details, see [Icinga for Windows Threading](../Threading/01-Threading.md#classes-and-threads).

---

## 4. Units, Automatic Conversions, and Threshold Syntax

### Supported Units

When creating a leaf check via `New-IcingaPlugin -Name <Name> -Value <Value> -Unit <Unit>`, the `Unit` parameter controls both how the value is formatted in human-readable output and how thresholds and performance data are emitted.

Specifically, `IcingaPlugin` treats `'B'` (bytes) and `'s'` (seconds) as **base units** (`HasBaseUnit()`), which unlock automatic unit conversion in `IcingaThresholds` and human-readable output formatting via `IcingaUnit`:

| Unit | Category | Output Behaviour | Performance Data & Threshold Behaviour |
|------|----------|------------------|----------------------------------------|
| `''` *(empty)* | Dimensionless | Prints the raw number or string (`42`, `'Running'`). | Emits bare numeric value (`42;80;90;;`). |
| `'%'` | Percentage | Appends `%` to numeric values and thresholds (`75% is greater than threshold 70%`). | Emits `%` unit (`75%;70;85;0;100`). Thresholds passed as `'70%'` or `'70'` both work without requiring `.BaseValue(100)`. |
| `'B'` | Byte base unit | Converts `<number>B` figures in output messages to the best-fitting binary unit via `IcingaUnit` (e.g. `442692000000B` renders as `412.29GiB`). Supports negative byte values as well. | Emits base bytes (`442692000000B;400000000000;450000000000;0;500000000000`). Thresholds given in any byte unit (`'400GB'`, `'500MiB'`) or as a percentage (`'80%'` with `.BaseValue()`) are resolved to bytes. |
| `'s'` | Time base unit | Decomposes `<number>s` figures in output messages into readable durations via `IcingaUnit` (e.g. `93784s` renders as `1d 2h 3m 4s`; sub-second durations below `1s` are handed to the threshold engine as `ms` or `us` to preserve precision). | Emits base seconds (`93784s;86400;172800;;`). Thresholds given as `'30m'`, `'2h'`, `'7d'`, or `[TimeSpan]` objects are resolved to seconds. |
| `'c'` | Continuous counter | Suppresses `'c'` in the human-readable output message (`120 is greater than threshold 100`). | Appends `'c'` to the performance data value (`120c;100;200;;`) as required by Icinga 2 for continuous counters. |
| Any other unit (e.g. `'GiB'`, `'ms'`, `'rpm'`) | Display unit | Appends the unit string as a display suffix to bare numbers in the output message (`1500rpm is greater than threshold 1200rpm`). | Emits the unit string verbatim in performance data without unit-family conversion. |

### Automatic `[TimeSpan]` Handling

You can pass a `[TimeSpan]` directly as the node's `Value`, `BaseValue()`, `Warning()`, or `Critical()` threshold:

* In `New-IcingaPlugin 'Last Run' ([datetime]::Now - $LastRun)`: `Initialize()` automatically converts the `[TimeSpan]` to `.TotalSeconds` and defaults an empty `Unit` to `'s'`.
* In `.BaseValue([TimeSpan]::FromHours(24))`: converts the base value to `.TotalSeconds`.
* In `.Warning([TimeSpan]::FromMinutes(30))` or `.Warning(@([TimeSpan]::FromMinutes(30)))`: `ConvertThresholdEntry()` converts the `[TimeSpan]` to `'1800s'`.

### Icinga Range Threshold Syntax (`CheckRange`)

The primary numeric comparison method `.CheckRange()` evaluates Icinga / Nagios range expressions:

| Expression | Alert Condition (Outside Range) | Description |
|------------|---------------------------------|-------------|
| `'10'` | `< 0` or `> 10` | Alert when value is below `0` or above `10`. |
| `'10:'` | `< 10` | Alert when value is below `10`. |
| `'~:10'` | `> 10` | Alert when value is above `10` (negative values allowed). |
| `'10:20'` | `< 10` or `> 20` | Alert when value is outside `10..20`. |
| `'@10:20'` | `>= 10` and `<= 20` | Alert when value is **inside** `10..20` (inclusive). |

---

## 5. Value and Threshold Translations (`.Translate()`)

Many Windows APIs report status values as integers or enums (for example `Win32_Service` status `4` for `Running`, Task Scheduler state `3` for `Ready`, or sentinel timestamp `0` for `Never`).

Calling `.Translate()` on a leaf check separates the **human-readable display text** from the **numeric performance data**:

1. **Enum values (`.Translate()`):** When `Value` is an enum instance (e.g. `[IcingaScheduledTaskStatus]::Ready`), `.Translate()` caches the enum member name (`'Ready'`) in `TranslatedText` for display and string/list comparisons while `ResolveNumericValue()` emits `[int]$Value` (`3`) in performance data.
2. **Lookup hashtable (`.Translate([hashtable])`):** Stores a mapping table (e.g. `@{ 0 = 'Never' }` or `@{ 4 = 'Running'; 1 = 'Stopped' }`) in `Translation`. Both the node's `Value` and threshold tokens (e.g. `.Critical('Running')` or `.Critical(4)`) are resolved through this table for output messages (`[INFO] Next Run Time [Never]: Never` or `[CRITICAL] State: 'Stopped' does not equal pattern 'Running'`) while `ResolvePerfDataThreshold()` maps a single translated threshold name back to its numeric key (`4`) in performance data.
3. **Direct display string (`.Translate([string])`):** Overrides `TranslatedText` for the current `Value` directly while keeping the numeric `Value` for threshold evaluation and performance data.

---

## 6. Multi-Value Thresholds and List Comparisons

Plugins often accept an array of allowed or forbidden states/patterns (for example `-State @('Ready', 'Running')` or `-Status @('Running')`). `IcingaPlugin` natively supports array thresholds via `.Warning([array])` and `.Critical([array])`:

* **`.CheckIn()`** (alias for `.CheckEqual()`): Uses case-insensitive string equality and raises WARNING/CRITICAL when the value **equals any** entry in the threshold list (e.g. forbidden states). Output on match: `"'Paused' equals pattern 'Paused'"`.
* **`.CheckNotIn()`** (alias for `.CheckNotEqual()`): Uses case-insensitive string inequality and raises WARNING/CRITICAL when the value **does not equal any** entry in the allowed threshold list (e.g. required states such as `-State @('Ready', 'Running')`). Output on mismatch: `"'Disabled' does not equal pattern 'Ready, Running'"`.
* **`.CheckLike()` / `.CheckNotLike()`**: Evaluate the value against one or more PowerShell wildcard patterns (`-like`).
* **`.CheckMatch()` / `.CheckNotMatch()`**: Evaluate the value against one or more regular expressions. Invalid regex patterns in a list safely resolve the check to `UNKNOWN` (`3`) with an explanatory error message instead of throwing.

---

## 7. Performance Data Format (`check_multi`)

Every leaf check whose value is numeric (or resolves numerically via enum/translation) emits a performance-data metric in the Icinga for Windows `check_multi` format:

```text
<index>::ifw_<template>::<label>=<value><unit>;<warning>;<critical>;<min>;<max>
```

* **`<index>`** (set via `.MetricIndex([string])`, defaults to `'default'`): Groups metrics belonging to the same instance (for example `'c'` for partition `C:`, or `'icingarenewcertificate'` for a scheduled task).
* **`ifw_<template>`** (set via `.MetricName([string])`, defaults to the calling `Invoke-IcingaCheck<Name>` command suffix in lower case, or `'check'` outside a check command): Identifies the check template. Always prefixed with `ifw_` (never doubled).
* **`<label>`** (set via `.MetricLabel([string])`, defaults to the node's `Name`): Identifies the specific metric. If sanitizing strips all characters (for example a name consisting only of punctuation), it falls back to `'value'`.
* **Sanitization & Deduplication:** Every segment is sanitized (`[\W]` removed) and lower-cased; underscores `_` are preserved. When `.Compile()` collects performance data across the tree, duplicate `index::ifw_template::label` keys are automatically skipped, and any node or container with `.SetNoPerfData()` suppresses metrics for itself and its entire subtree.

---

## 8. Verbosity Levels and Output Pruning

The root container's `.SetVerbose([int])` setting is propagated to every descendant node during `.Compile()` and controls which nodes appear in the rendered text output:

| Verbosity | Root Line | Containers (Sub-Packages) | Leaf Checks | Package Config Suffix |
|-----------|-----------|---------------------------|-------------|-----------------------|
| **`0`** *(default)* | Always printed with summary counts and failing check names. | Printed only if the container has at least one not-OK child. | Printed only if the leaf check itself is not OK (`WARNING`, `CRITICAL`, `UNKNOWN`). | Hidden |
| **`1`** | Always printed. | Printed if the container has at least one not-OK child. | Printed if the leaf check is not OK **or** if its parent container has any not-OK child (shows all sibling checks of an affected object). | Hidden |
| **`2`** | Always printed. | All visible containers printed (including `[OK]` and `[INFO]`). | All visible leaf checks printed (including `[OK]` and `[INFO]`). | Hidden |
| **`3`** | Always printed with package operator config suffix. | All visible containers printed with their operator config suffix (e.g. `(All must be [OK])`). | All visible leaf checks printed. | Shown (`(All must be [OK])`, `(Atleast one must be [OK])`, `(Atleast 2 must be [OK])`, `(Not more than 5 must be [OK])`, `(Between 2 and 4 must be [OK])`) |

Additional output modifiers:
* **`.SetHidden()`**: Completely hides a node from text output at **all** verbosity levels and excludes it from state aggregation and summary counts, while still emitting its performance data (unless `.SetNoPerfData()` is also set).
* **`.SetSkipSummary()`**: Keeps the leaf check in the text output and state aggregation, but omits it from the root summary header counts (`1 Critical 2 Ok`).
* **`.SetSummaryHeader()`**: Renders a per-state summary header on a nested sub-package, just like the root container.
* **`.SetIgnoreEmptyPackage()`**: Prevents an empty container (no visible children and no value) from raising `UNKNOWN: No checks added to this object`, marking it `OK` instead.

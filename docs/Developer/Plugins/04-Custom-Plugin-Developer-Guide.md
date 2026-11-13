# Step-by-Step Developer Guide: Writing a Custom Plugin

This guide walks you step by step through building a complete check plugin for Icinga for Windows using [`New-IcingaPlugin`](02-IcingaPlugin-Reference.md#1-new-icingaplugin-factory-cmdlet), [`IcingaPlugin`](02-IcingaPlugin-Reference.md#2-icingaplugin-class-properties), [`IcingaError`](03-Result-and-Error-Objects.md#2-icingaerror-class), and [`Test-IcingaError`](03-Result-and-Error-Objects.md#3-test-icingaerror-cmdlet).

By the end of this tutorial, you will have built a realistic **Print Spooler Queue & Worker Plugin (`Invoke-IcingaCheckSpoolerTutorial`)** that demonstrates:

1. Separating **Data Collection (Provider)** from **Check Evaluation (Plugin)**
2. Propagating data-collection errors safely with `IcingaError` and `Test-IcingaError`
3. Evaluating **numeric range thresholds** (`CheckRange`) with units (`'%'`, `'B'`) and `Minimum`/`Maximum` bounds
4. Evaluating **multi-value state lists** (`CheckNotIn`) with **value translation** (`.Translate()`)
5. Evaluating **time durations** (`[TimeSpan]` values and `'30m'` / `'1h'` thresholds)
6. Organizing checks into **nested sub-packages**, reporting **missing required entries** (`AddMissingChecks`), and handling **empty packages** (`SetIgnoreEmptyPackage`)
7. Controlling **performance data (`check_multi`)** and **verbosity levels (`0`..`3`)**

* **[01 - Plugin Architecture and Core Concepts](01-Architecture-and-Concepts.md)**
* **[02 - IcingaPlugin Technical Reference](02-IcingaPlugin-Reference.md)**
* **[03 - Result and Error Objects (`IcingaCheckResult` & `IcingaError`)](03-Result-and-Error-Objects.md)**
* **[04 - Step-by-Step Developer Guide: Writing a Custom Plugin](04-Custom-Plugin-Developer-Guide.md)** *(this page)*

---

## 1. Repository Layout and Separation of Concerns

In Icinga for Windows, the plugin subsystem under `src/Plugins/` is organized into three areas:

* **Plugin Library (`src/Plugins/Lib/Private/`)**: Internal plugin helper functions such as [`New-IcingaPlugin`](02-IcingaPlugin-Reference.md#1-new-icingaplugin-factory-cmdlet) for creating runspace-safe `IcingaPlugin` nodes.
* **Provider (`src/Plugins/Provider/<Topic>/Private/Get-Icinga<Topic>.ps1`)**: Queries the operating system (CIM/WMI, Performance Counters, Services, Task Scheduler, Registry), filters the raw objects, and returns either a clean collection/hashtable of data objects or an [`IcingaError`](03-Result-and-Error-Objects.md#2-icingaerror-class) when collection fails.
* **Plugin (`src/Plugins/Checks/Public/Invoke-IcingaCheck<Topic>.ps1`)**: Accepts user threshold parameters (`-Warning`, `-Critical`, `-State`, `-NoPerfData`, `-Verbosity`), calls the provider, builds the `IcingaPlugin` check tree with `New-IcingaPlugin`, and returns `$CheckPackage.Compile()`.

```text
src
  |_ Classes
  |    |_ DataTypes
  |         |_ IcingaSpoolerState.ps1       # Optional enum for status codes
  |_ Plugins
       |_ Lib
       |    |_ Private
       |         |_ New-IcingaPlugin.ps1
       |_ Provider
       |    |_ Spooler
       |         |_ Private
       |              |_ Get-IcingaSpoolerQueue.ps1
       |_ Checks
            |_ Public
                 |_ Invoke-IcingaCheckSpoolerTutorial.ps1
```

> **Naming Rule:** Every check plugin function **must** begin with the prefix `Invoke-IcingaCheck`. `IcingaPlugin` inspects the call stack at construction time (`DetectCheckCommand()`) and uses the suffix after `Invoke-IcingaCheck` as the default `ifw_<template>` namespace in performance data (for example `Invoke-IcingaCheckSpoolerTutorial` -> `ifw_spoolertutorial`).

---

## 2. Step 1: Writing the Data Provider (`Get-IcingaSpoolerQueue`)

A provider function collects data and **never throws unhandled exceptions**. If querying the system fails, it constructs and returns an `IcingaError` using the current runspace's type (`'IcingaError' -as [type]`).

```powershell
function Get-IcingaSpoolerQueue()
{
    param (
        [array]$QueueName = @()
    );

    # Resolve IcingaError in the current runspace (never use [IcingaError]::new() in a function)
    $ErrorType = 'IcingaError' -as [type];

    try {
        # In a real provider this would call Get-IcingaWindowsInformation -ClassName 'Win32_PerfFormattedData_Spooler_PrintQueue'.
        # For this tutorial we return two sample print queues so you can run and test the code anywhere.
        [array]$RawQueues = @(
            [PSCustomObject]@{
                'Name'            = 'Invoice-Printer';
                'StatusCode'      = 3;
                'Jobs'            = 14;
                'MaxJobs'         = 50;
                'SpoolBytes'      = 157286400;
                'OldestJobAge'    = [TimeSpan]::FromMinutes(45);
                'DriverVersion'   = 'v4.12.0';
            },
            [PSCustomObject]@{
                'Name'            = 'Label-Printer';
                'StatusCode'      = 3;
                'Jobs'            = 2;
                'MaxJobs'         = 50;
                'SpoolBytes'      = 10485760;
                'OldestJobAge'    = [TimeSpan]::FromMinutes(3);
                'DriverVersion'   = 'v4.12.0';
            }
        );
    } catch {
        [string]$Reason = $_.Exception.Message;
        $Error.Clear();
        return $ErrorType::new('Failed to query print spooler queues: {0}', @($Reason));
    }

    # Filter queues when -QueueName is provided (supports wildcards like 'Invoice*')
    [array]$Filtered = @();
    foreach ($Queue in $RawQueues) {
        if ($QueueName.Count -eq 0) {
            $Filtered += $Queue;
            continue;
        }

        foreach ($Pattern in $QueueName) {
            if ($Queue.Name -like [string]$Pattern) {
                $Filtered += $Queue;
                break;
            }
        }
    }

    return ,$Filtered;
}
```

---

## 3. Step 2: Writing the Base Plugin Skeleton

We start `Invoke-IcingaCheckSpoolerTutorial` by defining the parameters, creating the root container with `New-IcingaPlugin`, applying `-NoPerfData` and `-Verbosity`, and checking the provider result with `Test-IcingaError`.

```powershell
function Invoke-IcingaCheckSpoolerTutorial()
{
    param (
        [array]$QueueName        = @(),
        $Warning                 = $null,
        $Critical                = $null,
        [switch]$NoPerfData      = $false,
        [ValidateSet(0, 1, 2, 3)]
        [int]$Verbosity          = 0
    );

    # 1. Create the root check package and apply global flags
    $CheckPackage = New-IcingaPlugin 'Spooler Queues';
    $CheckPackage.SetNoPerfData($NoPerfData).SetVerbose($Verbosity).Commit();

    # 2. Fetch data from the provider and stop immediately with UNKNOWN if collection failed
    $Queues = Get-IcingaSpoolerQueue -QueueName $QueueName;
    if (Test-IcingaError -InputObject $Queues) {
        return $CheckPackage.SetError($Queues).Compile();
    }

    # 3. Compile the root package and return the Icinga exit code (0..3)
    return $CheckPackage.Compile();
}
```

Wait -- what happens if we run this skeleton right now before adding any child checks to `$CheckPackage`?

```text
[UNKNOWN] Spooler Queues: No checks added to this object
3
```

By default, an empty container without any visible child checks automatically reports `UNKNOWN: No checks added to this object` so a filter typo (such as `-QueueName 'DoesNotExist'`) never silently passes as `OK`.

---

## 4. Step 3: Adding Numeric Range Checks with Units (`CheckRange`)

Now let's loop over `$Queues`, create a sub-package for each printer queue, and add two numeric checks:
1. **`Queued Jobs`**: A plain count with `.Minimum(0)` and `.Maximum($Queue.MaxJobs)`, evaluated against `$Warning` and `$Critical` via `.CheckRange()`.
2. **`Spool Size`**: A byte metric (`Unit = 'B'`) evaluated against `$WarningSpool` and `$CriticalSpool` (which can be passed as human-readable byte strings like `'100MB'` or `'200MiB'`).

Notice that we set `.MetricIndex($Queue.Name)` on every leaf check so the performance data is grouped per queue (`invoiceprinter::ifw_spoolertutorial::queuedjobs=...`), and we end every `.AddCheck(...)` statement with **`.Commit()`**.

```powershell
    foreach ($Queue in $Queues) {
        $QueuePackage = New-IcingaPlugin ([string]::Format('Queue "{0}"', $Queue.Name));

        # Numeric count check with min/max perfdata bounds
        $JobsCheck = (New-IcingaPlugin 'Queued Jobs' $Queue.Jobs).Minimum(0).Maximum($Queue.MaxJobs).MetricIndex($Queue.Name).MetricLabel('Queued Jobs');
        $JobsCheck.Warning($Warning).Critical($Critical).CheckRange().Commit();
        $QueuePackage.AddCheck($JobsCheck).Commit();

        # Byte check ('B'): humanizes bytes in output (150MiB) while keeping raw bytes in perfdata
        $SpoolCheck = (New-IcingaPlugin 'Spool Size' $Queue.SpoolBytes 'B').Minimum(0).MetricIndex($Queue.Name).MetricLabel('Spool Size');
        $SpoolCheck.Warning($WarningSpool).Critical($CriticalSpool).CheckRange().Commit();
        $QueuePackage.AddCheck($SpoolCheck).Commit();

        $CheckPackage.AddCheck($QueuePackage).Commit();
    }
```

When executed with `-Warning 10 -Critical 20 -WarningSpool '100MB' -CriticalSpool '200MB'`, `Invoice-Printer` (`14` jobs, `150MiB` spool size) raises `WARNING`:

```text
[WARNING] Spooler Queues: 2 Warning 2 Ok [WARNING] Queued Jobs, Spool Size
\_ [WARNING] Queue "Invoice-Printer"
   \_ [WARNING] Queued Jobs: 14 is greater than threshold 10
   \_ [WARNING] Spool Size: 150MiB is greater than threshold 100MB
| invoiceprinter::ifw_spoolertutorial::queuedjobs=14;10;20;0;50 invoiceprinter::ifw_spoolertutorial::spoolsize=157286400B;100000000;200000000;0; labelprinter::ifw_spoolertutorial::queuedjobs=2;10;20;0;50 labelprinter::ifw_spoolertutorial::spoolsize=10485760B;100000000;200000000;0;
1
```

---

## 5. Step 4: Adding Translated State Checks (`Translate` & `CheckNotIn`) and `[TimeSpan]` Checks

Next, let's add three more checks to each queue's sub-package:

1. **`State` (with `.Translate([hashtable])` and `.CheckNotIn()`)**:
   The provider reports `StatusCode` as an integer (`1 = 'Stopped'`, `2 = 'Paused'`, `3 = 'Ready'`, `4 = 'Printing'`). By calling `.Translate($StateMap)` and `.Critical($State).CheckNotIn()`, the user can pass `-State @('Ready', 'Printing')`:
   * The output displays the translated name (`[OK] State: 'Ready' is ok` or `[CRITICAL] State: 'Paused' does not equal pattern 'Ready, Printing'`).
   * The performance data emits the numeric status code (`state=3;;;;` when a multi-value state list is passed, or `state=3;;3;;` when a single state `-State @('Ready')` is passed).
2. **`Oldest Job Age` (`[TimeSpan]` value)**:
   `$Queue.OldestJobAge` is a `[TimeSpan]`. Passing it directly to `New-IcingaPlugin 'Oldest Job Age' $Queue.OldestJobAge` automatically converts it to seconds (`2700s`), sets `Unit = 's'`, renders it as `'45m'` in the output, and evaluates it against time thresholds like `-WarningJobAge '30m'` and `-CriticalJobAge '1h'`.
3. **`Driver Version` (`[INFO]` Notice with `.SetNotice()`)**:
   An informational leaf check that prints `[INFO] Driver Version: v4.12.0` at `-Verbosity 2` without affecting the package state or summary counts.

---

## 6. Step 5: Complete, Production-Ready Plugin Code

Below is the complete code combining all features -- including `AddMissingChecks` (to report a required `-QueueName` that was not found on the host) and `-MitigateUnknown` (using `.SetIgnoreEmptyPackage($MitigateUnknown)`):

```powershell
function Invoke-IcingaCheckSpoolerTutorial()
{
    param (
        [array]$QueueName          = @(),
        $Warning                   = $null,
        $Critical                  = $null,
        $WarningSpool              = $null,
        $CriticalSpool             = $null,
        $WarningJobAge             = $null,
        $CriticalJobAge            = $null,
        [array]$State              = @('Ready', 'Printing'),
        [ValidateSet('Ok', 'Warning', 'Critical', 'Unknown')]
        [string]$OverrideNotFound  = 'Critical',
        [switch]$MitigateUnknown   = $false,
        [switch]$NoPerfData        = $false,
        [ValidateSet(0, 1, 2, 3)]
        [int]$Verbosity            = 0
    );

    # Lookup table mapping numeric spooler status codes to display names
    [hashtable]$StateMap = @{
        1 = 'Stopped';
        2 = 'Paused';
        3 = 'Ready';
        4 = 'Printing';
    };

    # Create the root package and configure perfdata, verbosity, and empty-package mitigation
    $CheckPackage = New-IcingaPlugin 'Spooler Queues';
    $CheckPackage.SetNoPerfData($NoPerfData).SetIgnoreEmptyPackage($MitigateUnknown).SetVerbose($Verbosity).Commit();

    # Fetch queues from the provider and handle collection errors
    $Queues = Get-IcingaSpoolerQueue -QueueName $QueueName;
    if (Test-IcingaError -InputObject $Queues) {
        return $CheckPackage.SetError($Queues).Compile();
    }

    [array]$FoundNames = @();

    foreach ($Queue in $Queues) {
        $FoundNames  += $Queue.Name;
        $QueuePackage = New-IcingaPlugin ([string]::Format('Queue "{0}"', $Queue.Name));

        # 1. State check: translates numeric code to string and checks membership in $State
        $StateCheck = (New-IcingaPlugin 'State' $Queue.StatusCode).Translate($StateMap).MetricIndex($Queue.Name).MetricLabel('State');

        if ($State.Count -gt 0) {
            $StateCheck.Critical($State).CheckNotIn().Commit();
        } else {
            $StateCheck.SetOk().Commit();
        }

        $QueuePackage.AddCheck($StateCheck).Commit();

        # 2. Queued Jobs count check
        $JobsCheck = (New-IcingaPlugin 'Queued Jobs' $Queue.Jobs).Minimum(0).Maximum($Queue.MaxJobs).MetricIndex($Queue.Name).MetricLabel('Queued Jobs');
        $JobsCheck.Warning($Warning).Critical($Critical).CheckRange().Commit();
        $QueuePackage.AddCheck($JobsCheck).Commit();

        # 3. Spool Size byte check ('B')
        $SpoolCheck = (New-IcingaPlugin 'Spool Size' $Queue.SpoolBytes 'B').Minimum(0).MetricIndex($Queue.Name).MetricLabel('Spool Size');
        $SpoolCheck.Warning($WarningSpool).Critical($CriticalSpool).CheckRange().Commit();
        $QueuePackage.AddCheck($SpoolCheck).Commit();

        # 4. Oldest Job Age TimeSpan check (auto-converted to seconds with Unit = 's')
        $AgeCheck = (New-IcingaPlugin 'Oldest Job Age' $Queue.OldestJobAge).Minimum(0).MetricIndex($Queue.Name).MetricLabel('Oldest Job Age');
        $AgeCheck.Warning($WarningJobAge).Critical($CriticalJobAge).CheckRange().Commit();
        $QueuePackage.AddCheck($AgeCheck).Commit();

        # 5. Informational notice check ([INFO])
        $QueuePackage.AddCheck(
            (New-IcingaPlugin 'Driver Version' $Queue.DriverVersion).SetNotice()
        ).Commit();

        $CheckPackage.AddCheck($QueuePackage).Commit();
    }

    # Automatically add a locked check for any explicitly requested queue that was not found
    $CheckPackage.AddMissingChecks(
        $QueueName,
        $FoundNames,
        'Queue "{0}"',
        'Print queue was not found on host',
        $OverrideNotFound
    ).Commit();

    return $CheckPackage.Compile();
}
```

---

## 7. Testing the Plugin Output Across Scenarios

### Scenario A: All Checks OK (Default Verbosity `0`)

```powershell
Invoke-IcingaCheckSpoolerTutorial -Warning 20 -Critical 40 -WarningSpool '200MB' -WarningJobAge '1h';
```

```text
[OK] Spooler Queues: 8 Ok
| invoiceprinter::ifw_spoolertutorial::state=3;;;; invoiceprinter::ifw_spoolertutorial::queuedjobs=14;20;40;0;50 invoiceprinter::ifw_spoolertutorial::spoolsize=157286400B;200000000;;0; invoiceprinter::ifw_spoolertutorial::oldestjobage=2700s;3600;;0; labelprinter::ifw_spoolertutorial::state=3;;;; labelprinter::ifw_spoolertutorial::queuedjobs=2;20;40;0;50 labelprinter::ifw_spoolertutorial::spoolsize=10485760B;200000000;;0; labelprinter::ifw_spoolertutorial::oldestjobage=180s;3600;;0;
0
```

> Notice that `8 Ok` counts the `4` active leaf checks on each of the `2` queues, while the `[INFO] Driver Version` notice nodes are automatically excluded from the summary count.

### Scenario B: Threshold Breach with `-Verbosity 2`

```powershell
Invoke-IcingaCheckSpoolerTutorial -Warning 10 -Critical 30 -WarningJobAge '30m' -CriticalJobAge '1h' -Verbosity 2;
```

```text
[WARNING] Spooler Queues: 2 Warning 6 Ok [WARNING] Queued Jobs, Oldest Job Age
\_ [WARNING] Queue "Invoice-Printer"
   \_ [OK] State: 'Ready' is ok
   \_ [WARNING] Queued Jobs: 14 is greater than threshold 10
   \_ [OK] Spool Size: 150MiB is ok
   \_ [WARNING] Oldest Job Age: 45m is greater than threshold 30m
   \_ [INFO] Driver Version: v4.12.0
\_ [OK] Queue "Label-Printer"
   \_ [OK] State: 'Ready' is ok
   \_ [OK] Queued Jobs: 2 is ok
   \_ [OK] Spool Size: 10MiB is ok
   \_ [OK] Oldest Job Age: 3m is ok
   \_ [INFO] Driver Version: v4.12.0
| invoiceprinter::ifw_spoolertutorial::state=3;;;; invoiceprinter::ifw_spoolertutorial::queuedjobs=14;10;30;0;50 invoiceprinter::ifw_spoolertutorial::spoolsize=157286400B;;;0; invoiceprinter::ifw_spoolertutorial::oldestjobage=2700s;1800;3600;0; labelprinter::ifw_spoolertutorial::state=3;;;; labelprinter::ifw_spoolertutorial::queuedjobs=2;10;30;0;50 labelprinter::ifw_spoolertutorial::spoolsize=10485760B;;;0; labelprinter::ifw_spoolertutorial::oldestjobage=180s;1800;3600;0;
1
```

### Scenario C: Missing Required Queue (`AddMissingChecks`)

```powershell
Invoke-IcingaCheckSpoolerTutorial -QueueName @('Invoice-Printer', 'Warehouse-Printer') -OverrideNotFound 'Critical';
```

```text
[CRITICAL] Spooler Queues: 1 Critical 4 Ok [CRITICAL] Queue "Warehouse-Printer"
\_ [CRITICAL] Queue "Warehouse-Printer": Print queue was not found on host
| invoiceprinter::ifw_spoolertutorial::state=3;;;; invoiceprinter::ifw_spoolertutorial::queuedjobs=14;;;0;50 invoiceprinter::ifw_spoolertutorial::spoolsize=157286400B;;;0; invoiceprinter::ifw_spoolertutorial::oldestjobage=2700s;;;0;
2
```

---

## 8. Developer Checklist for Every Plugin

Before submitting a new or migrated plugin, verify the following points:

1. **No class literals in functions:** Always use `New-IcingaPlugin`, `Test-IcingaError`, and `('IcingaError' -as [type])`. Validated by `Tests/ClassLiteral.Tests.ps1`.
2. **Every chain ends with `.Commit()` or `.Compile()`:** Never leave an `IcingaPlugin` chain unterminated and never use `| Out-Null`.
3. **Always handle provider errors:** Immediately check provider results with `if (Test-IcingaError -InputObject $Data) { return $CheckPackage.SetError($Data).Compile(); }`.
4. **Set `MetricIndex` and `MetricLabel` on multi-instance checks:** Ensures every instance produces a unique `index::ifw_template::label` metric in `check_multi` format.
5. **Follow `CLAUDE.md` code-styling rules:** UTF-8 without BOM, 4-space indentation, Allman braces with `function Name()`, vertically aligned `=` across assignment blocks, aligned `.PARAMETER` Markdown help tables, and no Unicode em-dashes (`\u2014`) or en-dashes (`\u2013`) (use `--` or `-` instead). Validated by `build/Test-ModuleCodeStyling.ps1`.

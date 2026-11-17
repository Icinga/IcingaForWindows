<#
.SYNOPSIS
Unified Icinga plugin node that is both a single check and a container

.DESCRIPTION
IcingaPlugin replaces the previous three-part construct (New-IcingaCheck,
New-IcingaCheckPackage, New-IcingaCheckResult) with a single class. One instance
can act as a leaf check (a measured value evaluated against warning and critical
thresholds and immediately put into a state 0 OK, 1 WARNING, 2 CRITICAL or
3 UNKNOWN the moment a comparison method is called), as a container (a node that
aggregates child plugins with a configurable operator, defaulting to all children
must be OK, with arbitrary nesting), or as a hybrid node that carries its own
value and child checks so its own evaluated state participates in the aggregation
as one more element. A node with only children and no own evaluated value behaves
identically to the classic package.

The surface is fluent: threshold setters, comparison methods, override methods,
operator methods and AddCheck all return the instance ($this) so calls chain. A
chain is terminated either by AddCheck / an assignment that consumes the return
value, by the integer-returning Compile() at the root, or by the void Commit()
end-of-chain marker, so callers never need '| Out-Null' or '[void]'.

Threshold comparison is delegated to the existing IcingaThresholds class, so all
unit, percentage and range handling is shared and there is no duplicated
comparison math here. State transitions from threshold evaluation and from
aggregation are escalate-only (a state is only ever raised, never lowered); the
SetState override family is the single, central way to force a specific state, with
an optional lock that freezes it. SetError reports a failed data collection (a
message with format arguments, or an IcingaError returned by a data function) as a
locked UNKNOWN state.

Compile() aggregates the tree, renders the indented plugin output, collects the
performance data and stores an IcingaCheckResult in the thread-local runtime state
at $Global:IcingaForWindows.Private.Icinga.CheckResult. On the main thread it also
writes the output to the console; inside a background daemon
(Protected.IsBackgroundDaemon) it writes nothing to the console and leaves the
result in Private for the REST API to pick up. Compile() returns the integer exit
code either way.

.OUTPUTS
IcingaPlugin -- Plugin node exposing the fluent check, override and container surface.

.EXAMPLE
PS> return (New-IcingaPlugin 'Disks').
        AddCheck((New-IcingaPlugin 'C:' 55 '%').Warning('80').Critical('90').CheckRange()).
        AddCheck((New-IcingaPlugin 'D:' 95 '%').Warning('80').Critical('90').CheckRange()).
        CheckAnd().
        Compile()

Builds a two-disk package, evaluates each disk immediately, aggregates with the
default "all must be OK" rule and returns the worst exit code.

.NOTES
Reuses IcingaThresholds / IcingaThresholdResult for comparison and IcingaUnit for
unit handling. Those types are referenced only inside method bodies because the
build concatenates class files alphabetically and IcingaPlugin is parsed before
them; referencing them as property, parameter or base types would fail at parse
time. Writes only to the thread-local Private runtime state, never to Public.

Functions create instances only through New-IcingaPlugin, never with
[IcingaPlugin]::new(). Every runspace shares the compiled kernel, so a class
literal inside a function resolves to the type of the main runspace; on Windows
PowerShell 5.1 the methods of such an instance stall in a background thread until
the main runspace is idle.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
class IcingaPlugin
{
    [string]$Name                       = '';
    [object]$Value                      = $null;
    [string]$Unit                       = '';
    [int]$Verbose                       = 0;
    [bool]$NoPerfData                   = $false;
    [bool]$IsHidden                     = $false;
    [bool]$IsNotice                     = $false;
    [bool]$IgnoreEmptyPackage           = $false;
    [bool]$AddSummaryHeader             = $false;
    [bool]$SkipSummary                  = $false;

    hidden [int]$State                  = 0;
    hidden [bool]$Locked                = $false;
    hidden [bool]$FixedState            = $false;
    hidden [bool]$IsNoticeObject        = $false;
    hidden [bool]$IgnoredEmpty          = $false;
    hidden [bool]$Evaluated             = $false;
    hidden [bool]$HasError              = $false;
    hidden [string]$OutputMessage       = '';
    hidden [int]$Indention              = 0;
    hidden [IcingaPlugin]$Parent        = $null;
    hidden [array]$Checks               = @();
    hidden [array]$PerfData             = @();
    hidden [string]$Operator            = 'And';
    hidden [int]$OperatorMin            = -1;
    hidden [int]$OperatorMax            = -1;
    hidden [string]$WarningThreshold    = '';
    hidden [string]$CriticalThreshold   = '';
    hidden [array]$WarningList          = @();
    hidden [array]$CriticalList         = @();
    hidden [string]$ResolvedWarning     = '';
    hidden [string]$ResolvedCritical    = '';
    hidden [string]$MinimumValue        = '';
    hidden [string]$MaximumValue        = '';
    hidden [object]$BaseValueSetting    = $null;
    hidden [string]$MetricIndexValue    = '';
    hidden [string]$MetricNameValue     = '';
    hidden [string]$MetricLabelValue    = '';
    hidden [string]$CheckCommand        = '';
    hidden [hashtable]$Translation      = @{};
    hidden [string]$TranslatedText      = '';

    static hidden [hashtable]$StateText = @{
        0 = '[OK]';
        1 = '[WARNING]';
        2 = '[CRITICAL]';
        3 = '[UNKNOWN]';
    };

    static hidden [hashtable]$StateMap  = @{
        'ok'       = 0;
        'warning'  = 1;
        'critical' = 2;
        'unknown'  = 3;
        '0'        = 0;
        '1'        = 1;
        '2'        = 2;
        '3'        = 3;
    };

    <#
    .SYNOPSIS
    Create a plugin node with a name only

    .DESCRIPTION
    Creates a node without a measured value. Typically used as a container that
    aggregates child checks added with AddCheck.

    .PARAMETER Name
    | Name | Type          | Description                      | Default |
    |------|---------------|----------------------------------|---------|
    | Name | System.String | Display name of the plugin node. |         |

    .OUTPUTS
    IcingaPlugin -- Configured plugin node.

    .EXAMPLE
    PS> New-IcingaPlugin 'Disks'

    .NOTES
    Delegates to the shared Initialize helper. Functions call it through
    New-IcingaPlugin.
    #>
    IcingaPlugin([string]$Name)
    {
        $this.Initialize($Name, $null, '');
    }

    <#
    .SYNOPSIS
    Create a plugin node with a name and a measured value

    .DESCRIPTION
    Creates a leaf check with a measured value but no unit. Thresholds are applied
    afterwards through the fluent setters and comparison methods.

    .PARAMETER Name
    | Name | Type          | Description                | Default |
    |------|---------------|----------------------------|---------|
    | Name | System.String | Display name of the check. |         |

    .PARAMETER Value
    | Name  | Type          | Description                                 | Default |
    |-------|---------------|---------------------------------------------|---------|
    | Value | System.Object | Measured value; number or '<number><unit>'. |         |

    .OUTPUTS
    IcingaPlugin -- Configured plugin node.

    .EXAMPLE
    PS> New-IcingaPlugin 'Load' 95

    .NOTES
    Delegates to the shared Initialize helper. Functions call it through
    New-IcingaPlugin.
    #>
    IcingaPlugin([string]$Name, [object]$Value)
    {
        $this.Initialize($Name, $Value, '');
    }

    <#
    .SYNOPSIS
    Create a plugin node with a name, value and unit

    .DESCRIPTION
    Creates a leaf check with a measured value and an Icinga unit (for example '%',
    'MB', 's'). The unit is appended to the performance data and reused by the
    threshold comparison.

    .PARAMETER Name
    | Name | Type          | Description                | Default |
    |------|---------------|----------------------------|---------|
    | Name | System.String | Display name of the check. |         |

    .PARAMETER Value
    | Name  | Type          | Description                                 | Default |
    |-------|---------------|---------------------------------------------|---------|
    | Value | System.Object | Measured value; number or '<number><unit>'. |         |

    .PARAMETER Unit
    | Name | Type          | Description                       | Default |
    |------|---------------|-----------------------------------|---------|
    | Unit | System.String | Icinga unit appended to perfdata. |         |

    .OUTPUTS
    IcingaPlugin -- Configured plugin node.

    .EXAMPLE
    PS> New-IcingaPlugin 'Load' 95 '%'

    .NOTES
    Delegates to the shared Initialize helper. Functions call it through
    New-IcingaPlugin.
    #>
    IcingaPlugin([string]$Name, [object]$Value, [string]$Unit)
    {
        $this.Initialize($Name, $Value, $Unit);
    }

    <#
    .SYNOPSIS
    Store the base settings of the node

    .DESCRIPTION
    Shared constructor logic that stores the name, measured value and unit. Kept in
    a single helper so every constructor overload behaves identically.

    .PARAMETER Name
    | Name | Type          | Description               | Default |
    |------|---------------|---------------------------|---------|
    | Name | System.String | Display name of the node. |         |

    .PARAMETER Value
    | Name  | Type          | Description              | Default |
    |-------|---------------|--------------------------|---------|
    | Value | System.Object | Measured value or $null. |         |

    .PARAMETER Unit
    | Name | Type          | Description  | Default |
    |------|---------------|--------------|---------|
    | Unit | System.String | Icinga unit. |         |

    .OUTPUTS
    None -- Updates instance state.

    .EXAMPLE
    PS> $this.Initialize('Load', 95, '%')

    .NOTES
    Internal helper shared by all constructors.
    #>
    hidden [void] Initialize([string]$Name, [object]$Value, [string]$Unit)
    {
        $this.Name = $Name;

        if ($Value -is [TimeSpan]) {
            $this.Value = ([TimeSpan]$Value).TotalSeconds;
            if ('' -eq $Unit) {
                $this.Unit = 's';
            } else {
                $this.Unit = $Unit;
            }
        } else {
            $this.Value = $Value;
            $this.Unit  = $Unit;
        }

        $this.CheckCommand = $this.DetectCheckCommand();
    }

    <#
    .SYNOPSIS
    Set the warning threshold and return the node for chaining

    .DESCRIPTION
    Stores the warning threshold string verbatim and clears any multi-value warning
    list. The threshold is not evaluated until a comparison method (CheckRange,
    CheckGreater, ...) is called.

    .PARAMETER Warning
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Warning | System.String | Warning threshold string ('' = unset). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('80')

    .NOTES
    Fluent setter; combine with Critical and a comparison method.
    #>
    [IcingaPlugin] Warning([string]$Warning)
    {
        $this.WarningList      = @();
        $this.WarningThreshold = $Warning;
        return $this;
    }

    <#
    .SYNOPSIS
    Set a multi-value warning threshold list and return the node for chaining

    .DESCRIPTION
    Stores one or more warning threshold entries for multi-value comparisons
    (CheckIn, CheckNotIn, CheckEqual, CheckNotEqual, CheckLike, CheckNotLike,
    CheckMatch, CheckNotMatch). Null and empty entries are ignored; an empty array
    leaves the warning threshold unset, a single entry is stored as a standard
    threshold string, and multiple entries are stored both in WarningList and as a
    comma-separated display string in WarningThreshold.

    .PARAMETER Warning
    | Name    | Type         | Description                                    | Default |
    |---------|--------------|------------------------------------------------|---------|
    | Warning | System.Array | Array of warning threshold values or patterns. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning(@('Paused', 'Pending')).CheckIn()

    .NOTES
    Fluent setter; also accepts single non-string values such as numbers, enums or TimeSpans.
    #>
    [IcingaPlugin] Warning([array]$Warning)
    {
        [array]$Cleaned = $this.CleanThresholdList($Warning);

        if ($Cleaned.Count -eq 0) {
            $this.WarningList      = @();
            $this.WarningThreshold = '';
        } elseif ($Cleaned.Count -eq 1) {
            $this.WarningList      = @();
            $this.WarningThreshold = [string]$Cleaned[0];
        } else {
            $this.WarningList      = $Cleaned;
            $this.WarningThreshold = ($Cleaned -join ', ');
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Set a single object warning threshold and return the node for chaining

    .DESCRIPTION
    Converts a single non-string warning threshold value (such as a number, enum or
    TimeSpan) to its invariant threshold string representation via
    ConvertThresholdEntry, or delegates to Warning([array]) when an array is passed
    through an untyped variable.

    .PARAMETER Warning
    | Name    | Type          | Description                                       | Default |
    |---------|---------------|---------------------------------------------------|---------|
    | Warning | System.Object | Warning threshold value (number, enum, TimeSpan). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning([TimeSpan]::FromMinutes(30)).CheckRange()

    .NOTES
    Fluent setter; normalizes TimeSpans to seconds and numbers to invariant strings.
    #>
    [IcingaPlugin] Warning([object]$Warning)
    {
        if ($Warning -is [array]) {
            return $this.Warning([array]$Warning);
        }

        $this.WarningList      = @();
        $this.WarningThreshold = $this.ConvertThresholdEntry($Warning);
        return $this;
    }

    <#
    .SYNOPSIS
    Set the critical threshold and return the node for chaining

    .DESCRIPTION
    Stores the critical threshold string verbatim and clears any multi-value critical
    list. The threshold is not evaluated until a comparison method is called.

    .PARAMETER Critical
    | Name     | Type          | Description                             | Default |
    |----------|---------------|-----------------------------------------|---------|
    | Critical | System.String | Critical threshold string ('' = unset). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Critical('90')

    .NOTES
    Fluent setter; combine with Warning and a comparison method.
    #>
    [IcingaPlugin] Critical([string]$Critical)
    {
        $this.CriticalList      = @();
        $this.CriticalThreshold = $Critical;
        return $this;
    }

    <#
    .SYNOPSIS
    Set a multi-value critical threshold list and return the node for chaining

    .DESCRIPTION
    Stores one or more critical threshold entries for multi-value comparisons
    (CheckIn, CheckNotIn, CheckEqual, CheckNotEqual, CheckLike, CheckNotLike,
    CheckMatch, CheckNotMatch). Null and empty entries are ignored; an empty array
    leaves the critical threshold unset, a single entry is stored as a standard
    threshold string, and multiple entries are stored both in CriticalList and as a
    comma-separated display string in CriticalThreshold.

    .PARAMETER Critical
    | Name     | Type         | Description                                     | Default |
    |----------|--------------|-------------------------------------------------|---------|
    | Critical | System.Array | Array of critical threshold values or patterns. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Critical(@('Ready', 'Running')).CheckNotIn()

    .NOTES
    Fluent setter; also accepts single non-string values such as numbers, enums or TimeSpans.
    #>
    [IcingaPlugin] Critical([array]$Critical)
    {
        [array]$Cleaned = $this.CleanThresholdList($Critical);

        if ($Cleaned.Count -eq 0) {
            $this.CriticalList      = @();
            $this.CriticalThreshold = '';
        } elseif ($Cleaned.Count -eq 1) {
            $this.CriticalList      = @();
            $this.CriticalThreshold = [string]$Cleaned[0];
        } else {
            $this.CriticalList      = $Cleaned;
            $this.CriticalThreshold = ($Cleaned -join ', ');
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Set a single object critical threshold and return the node for chaining

    .DESCRIPTION
    Converts a single non-string critical threshold value (such as a number, enum or
    TimeSpan) to its invariant threshold string representation via
    ConvertThresholdEntry, or delegates to Critical([array]) when an array is passed
    through an untyped variable.

    .PARAMETER Critical
    | Name     | Type          | Description                                        | Default |
    |----------|---------------|----------------------------------------------------|---------|
    | Critical | System.Object | Critical threshold value (number, enum, TimeSpan). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Critical([TimeSpan]::FromHours(1)).CheckRange()

    .NOTES
    Fluent setter; normalizes TimeSpans to seconds and numbers to invariant strings.
    #>
    [IcingaPlugin] Critical([object]$Critical)
    {
        if ($Critical -is [array]) {
            return $this.Critical([array]$Critical);
        }

        $this.CriticalList      = @();
        $this.CriticalThreshold = $this.ConvertThresholdEntry($Critical);
        return $this;
    }

    <#
    .SYNOPSIS
    Normalize a single threshold list entry to its invariant string form

    .DESCRIPTION
    Converts a threshold list item to a string under the invariant culture. TimeSpan
    values are converted to seconds with an 's' unit suffix, floating-point numbers
    are formatted without scientific notation using a dot decimal separator, and all
    other non-null values use their string representation.

    .PARAMETER Entry
    | Name  | Type          | Description                       | Default |
    |-------|---------------|-----------------------------------|---------|
    | Entry | System.Object | Threshold list item to normalize. |         |

    .OUTPUTS
    System.String -- Normalized threshold string, or '' when null.

    .EXAMPLE
    PS> $this.ConvertThresholdEntry(80.5)

    .NOTES
    Internal helper used by CleanThresholdList.
    #>
    hidden [string] ConvertThresholdEntry([object]$Entry)
    {
        if ($null -eq $Entry) {
            return '';
        }

        if ($Entry -is [TimeSpan]) {
            return (([TimeSpan]$Entry).TotalSeconds.ToString('0.##########', [System.Globalization.CultureInfo]::InvariantCulture) + 's');
        }

        if ($Entry -is [double] -or $Entry -is [single] -or $Entry -is [decimal]) {
            return $this.FormatNumber($Entry);
        }

        return [string]$Entry;
    }

    <#
    .SYNOPSIS
    Filter and normalize an array of threshold entries

    .DESCRIPTION
    Converts each non-null, non-empty entry in the supplied array through
    ConvertThresholdEntry and returns the resulting string array.

    .PARAMETER Thresholds
    | Name       | Type         | Description                           | Default |
    |------------|--------------|---------------------------------------|---------|
    | Thresholds | System.Array | Raw threshold array passed by caller. |         |

    .OUTPUTS
    System.Array -- Cleaned array of non-empty threshold strings.

    .EXAMPLE
    PS> $this.CleanThresholdList(@('Ready', 'Running'))

    .NOTES
    Internal helper used by Warning([array]) and Critical([array]).
    #>
    hidden [array] CleanThresholdList([array]$Thresholds)
    {
        [array]$Cleaned = @();

        if ($null -eq $Thresholds) {
            return $Cleaned;
        }

        foreach ($Entry in $Thresholds) {
            [string]$Text = $this.ConvertThresholdEntry($Entry);
            if ('' -ne $Text) {
                $Cleaned += $Text;
            }
        }

        return $Cleaned;
    }

    <#
    .SYNOPSIS
    Set the performance-data minimum and return the node for chaining

    .DESCRIPTION
    Stores the minimum value that is emitted as the 'min' field of the performance
    data. Accepts a number or string; does not influence the threshold evaluation.

    .PARAMETER Minimum
    | Name    | Type          | Description                    | Default |
    |---------|---------------|--------------------------------|---------|
    | Minimum | System.Object | Perfdata minimum ('' = unset). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Minimum('0')

    .NOTES
    Fluent setter for the perfdata min field.
    #>
    [IcingaPlugin] Minimum([object]$Minimum)
    {
        if ($null -eq $Minimum -or '' -eq [string]$Minimum) {
            $this.MinimumValue = '';
        } else {
            $this.MinimumValue = $this.FormatNumber($Minimum);
        }

        if ($this.Evaluated) {
            $this.BuildPerfData();
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Set the performance-data maximum and return the node for chaining

    .DESCRIPTION
    Stores the maximum value that is emitted as the 'max' field of the performance
    data. Accepts a number or string; does not influence the threshold evaluation.

    .PARAMETER Maximum
    | Name    | Type          | Description                    | Default |
    |---------|---------------|--------------------------------|---------|
    | Maximum | System.Object | Perfdata maximum ('' = unset). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Maximum('100')

    .NOTES
    Fluent setter for the perfdata max field.
    #>
    [IcingaPlugin] Maximum([object]$Maximum)
    {
        if ($null -eq $Maximum -or '' -eq [string]$Maximum) {
            $this.MaximumValue = '';
        } else {
            $this.MaximumValue = $this.FormatNumber($Maximum);
        }

        if ($this.Evaluated) {
            $this.BuildPerfData();
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Set the base value for percentage and Max comparisons

    .DESCRIPTION
    Stores the base value (a number or a unit string such as '1TB') that percent
    thresholds and the CheckMax comparison resolve against. Passed on to
    IcingaThresholds when a comparison method is called.

    .PARAMETER BaseValue
    | Name      | Type          | Description                                | Default |
    |-----------|---------------|--------------------------------------------|---------|
    | BaseValue | System.Object | Base/maximum value; number or unit string. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.BaseValue('1TB').Warning('80%').Critical('90%').CheckMax()

    .NOTES
    Fluent setter; required for percent thresholds and CheckMax.
    #>
    [IcingaPlugin] BaseValue([object]$BaseValue)
    {
        if ($BaseValue -is [TimeSpan]) {
            $this.BaseValueSetting = ([TimeSpan]$BaseValue).TotalSeconds;
        } else {
            $this.BaseValueSetting = $BaseValue;
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Set the performance-data metric index and return the node for chaining

    .DESCRIPTION
    Sets the first segment of the check_multi performance-data label
    ('index::ifw_template::label'). The index typically identifies the instance, such
    as a CPU core number or a disk letter. Defaults to 'default' when left unset.

    .PARAMETER Index
    | Name  | Type          | Description                         | Default |
    |-------|---------------|-------------------------------------|---------|
    | Index | System.String | Metric index / instance identifier. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.MetricIndex('0')

    .NOTES
    Fluent setter; sanitized (non-word characters removed, lower-cased) at render time.
    #>
    [IcingaPlugin] MetricIndex([string]$Index)
    {
        $this.MetricIndexValue = $Index;
        return $this;
    }

    <#
    .SYNOPSIS
    Set the performance-data metric template and return the node for chaining

    .DESCRIPTION
    Sets the template segment of the check_multi performance-data label
    ('index::ifw_template::label'). The fixed 'ifw_' namespace is always prepended, so
    passing 'cpu' yields 'ifw_cpu'. When left unset the template is derived from the
    calling Invoke-IcingaCheck* command (for example Invoke-IcingaCheckCPU yields
    'cpu'), falling back to 'check' when no such command is on the call stack.

    .PARAMETER Name
    | Name | Type          | Description                                       | Default |
    |------|---------------|---------------------------------------------------|---------|
    | Name | System.String | Template name without the fixed 'ifw_' namespace. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.MetricName('cpu')

    .NOTES
    Fluent setter; 'ifw_' is not doubled when the value already carries it.
    #>
    [IcingaPlugin] MetricName([string]$Name)
    {
        $this.MetricNameValue = $Name;
        return $this;
    }

    <#
    .SYNOPSIS
    Set the performance-data metric label and return the node for chaining

    .DESCRIPTION
    Sets the label segment of the check_multi performance-data label
    ('index::ifw_template::label'), for example 'load' or 'free'. Defaults to the
    node's Name when left unset.

    .PARAMETER Label
    | Name  | Type          | Description                    | Default |
    |-------|---------------|--------------------------------|---------|
    | Label | System.String | Metric label / measured value. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.MetricLabel('load')

    .NOTES
    Fluent setter; sanitized (non-word characters removed, lower-cased) at render time.
    #>
    [IcingaPlugin] MetricLabel([string]$Label)
    {
        $this.MetricLabelValue = $Label;
        return $this;
    }

    <#
    .SYNOPSIS
    Translate the node's value (such as an enum or boolean) for human-readable output

    .DESCRIPTION
    Enables display translation for the node's current value while keeping its numeric
    representation for performance data. Useful when Value is a [System.Enum] or
    [System.Boolean] whose string name should be shown in the output message and whose
    integer code should be emitted in performance data.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> (New-IcingaPlugin 'Spooler' ([IcingaServiceStatus]::Running)).Translate().Critical('Running').CheckNotEqual()

    .NOTES
    Fluent setter; may be called before or after a comparison method.
    #>
    [IcingaPlugin] Translate()
    {
        if ($null -ne $this.Value) {
            $this.TranslatedText = [string]$this.Value;
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Set a translation table for human-readable output while preserving numeric perfdata

    .DESCRIPTION
    Stores a lookup hashtable (for example @{ 1 = 'Stopped'; 4 = 'Running' } or
    @{ 0 = 'Never' }) used to translate both the measured value and threshold values
    into human-readable text in the output message while emitting the underlying
    numeric value in the performance data.

    .PARAMETER Translation
    | Name        | Type                         | Description                               | Default |
    |-------------|------------------------------|-------------------------------------------|---------|
    | Translation | System.Collections.Hashtable | Mapping of raw values to display strings. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> (New-IcingaPlugin 'Spooler' 4).Translate(@{ 1 = 'Stopped'; 4 = 'Running' }).Critical('Running').CheckNotEqual()

    .NOTES
    Lookups match both direct keys and case-insensitive string representations.
    #>
    [IcingaPlugin] Translate([hashtable]$Translation)
    {
        if ($null -eq $Translation) {
            $this.Translation = @{};
        } else {
            $this.Translation = $Translation;
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Set an explicit human-readable display string for the node's value

    .DESCRIPTION
    Overrides the human-readable text used to render the node's measured value in the
    output message while keeping the raw numeric Value for threshold evaluation and
    performance data.

    .PARAMETER Text
    | Name | Type          | Description                                     | Default |
    |------|---------------|-------------------------------------------------|---------|
    | Text | System.String | Human-readable display representation of Value. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> (New-IcingaPlugin 'Spooler' 4).Translate('Running').CheckRange()

    .NOTES
    Fluent setter.
    #>
    [IcingaPlugin] Translate([string]$Text)
    {
        $this.TranslatedText = $Text;
        return $this;
    }

    <#
    .SYNOPSIS
    Set the verbosity level and return the node for chaining

    .DESCRIPTION
    Sets the output verbosity level (0 problems only, 1 plus affected siblings,
    2 all checks, 3 all checks plus operator configuration) and returns the node.

    .PARAMETER Verbose
    | Name    | Type         | Description             | Default |
    |---------|--------------|-------------------------|---------|
    | Verbose | System.Int32 | Verbosity level (0..3). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.SetVerbose(2)

    .NOTES
    Fluent counterpart to the Verbose property.
    #>
    [IcingaPlugin] SetVerbose([int]$Verbose)
    {
        $this.Verbose = $Verbose;
        return $this;
    }

    <#
    .SYNOPSIS
    Disable performance data for this node and its subtree

    .DESCRIPTION
    Sets NoPerfData to true so neither this node nor its children emit performance
    data, and returns the node for chaining.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetNoPerfData()

    .NOTES
    Fluent counterpart to the NoPerfData property.
    #>
    [IcingaPlugin] SetNoPerfData()
    {
        return $this.SetNoPerfData($true);
    }

    <#
    .SYNOPSIS
    Configure whether performance data is disabled for this node and its subtree

    .DESCRIPTION
    Sets NoPerfData to the supplied boolean and returns the node for chaining.

    .PARAMETER NoPerfData
    | Name       | Type           | Description                           | Default |
    |------------|----------------|---------------------------------------|---------|
    | NoPerfData | System.Boolean | When true, suppress performance data. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.SetNoPerfData($NoPerfData)

    .NOTES
    Fluent counterpart to the NoPerfData property.
    #>
    [IcingaPlugin] SetNoPerfData([bool]$NoPerfData)
    {
        $this.NoPerfData = $NoPerfData;
        return $this;
    }

    <#
    .SYNOPSIS
    Hide this node from the rendered text output and summary counts

    .DESCRIPTION
    Marks the node as hidden so it is omitted from the text output and aggregation
    while still contributing its performance data.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $metricPackage.SetHidden()

    .NOTES
    Fluent counterpart to the IsHidden property.
    #>
    [IcingaPlugin] SetHidden()
    {
        return $this.SetHidden($true);
    }

    <#
    .SYNOPSIS
    Configure whether this node is hidden from the rendered text output

    .DESCRIPTION
    Sets IsHidden to the supplied boolean and returns the node for chaining.

    .PARAMETER Hidden
    | Name   | Type           | Description                           | Default |
    |--------|----------------|---------------------------------------|---------|
    | Hidden | System.Boolean | When true, hide the node from output. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $metricPackage.SetHidden($true)

    .NOTES
    Fluent counterpart to the IsHidden property.
    #>
    [IcingaPlugin] SetHidden([bool]$Hidden)
    {
        $this.IsHidden = $Hidden;
        return $this;
    }

    <#
    .SYNOPSIS
    Allow an empty package to compile as OK instead of UNKNOWN

    .DESCRIPTION
    Sets IgnoreEmptyPackage to true so a container without child checks and without
    an own measured value resolves to OK instead of raising UNKNOWN ('No checks added
    to this package').

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.SetIgnoreEmptyPackage()

    .NOTES
    Fluent counterpart to the IgnoreEmptyPackage property.
    #>
    [IcingaPlugin] SetIgnoreEmptyPackage()
    {
        return $this.SetIgnoreEmptyPackage($true);
    }

    <#
    .SYNOPSIS
    Configure whether an empty package compiles as OK instead of UNKNOWN

    .DESCRIPTION
    Sets IgnoreEmptyPackage to the supplied boolean and returns the node for chaining.

    .PARAMETER Ignore
    | Name   | Type           | Description                                 | Default |
    |--------|----------------|---------------------------------------------|---------|
    | Ignore | System.Boolean | When true, an empty package resolves to OK. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.SetIgnoreEmptyPackage($MitigateUnknown)

    .NOTES
    Fluent counterpart to the IgnoreEmptyPackage property.
    #>
    [IcingaPlugin] SetIgnoreEmptyPackage([bool]$Ignore)
    {
        $this.IgnoreEmptyPackage = $Ignore;
        return $this;
    }

    <#
    .SYNOPSIS
    Enable the summary header on a nested container

    .DESCRIPTION
    Sets AddSummaryHeader to true so a non-root container also renders the per-state
    leaf summary on its container line.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $subPackage.SetSummaryHeader()

    .NOTES
    Fluent counterpart to the AddSummaryHeader property.
    #>
    [IcingaPlugin] SetSummaryHeader()
    {
        return $this.SetSummaryHeader($true);
    }

    <#
    .SYNOPSIS
    Configure whether a nested container renders a summary header

    .DESCRIPTION
    Sets AddSummaryHeader to the supplied boolean and returns the node for chaining.

    .PARAMETER AddHeader
    | Name      | Type           | Description                            | Default |
    |-----------|----------------|----------------------------------------|---------|
    | AddHeader | System.Boolean | When true, include the summary header. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $subPackage.SetSummaryHeader($true)

    .NOTES
    Fluent counterpart to the AddSummaryHeader property.
    #>
    [IcingaPlugin] SetSummaryHeader([bool]$AddHeader)
    {
        $this.AddSummaryHeader = $AddHeader;
        return $this;
    }

    <#
    .SYNOPSIS
    Exclude this node from its parent container's summary header counts

    .DESCRIPTION
    Sets SkipSummary to true so the node still participates in state aggregation and
    tree output, but is omitted from the per-state leaf count and name lists in the
    container summary header (matching the classic -NoHeaderReport switch).

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetSkipSummary()

    .NOTES
    Fluent counterpart to the SkipSummary property.
    #>
    [IcingaPlugin] SetSkipSummary()
    {
        return $this.SetSkipSummary($true);
    }

    <#
    .SYNOPSIS
    Configure whether this node is excluded from the container summary header

    .DESCRIPTION
    Sets SkipSummary to the supplied boolean and returns the node for chaining.

    .PARAMETER Skip
    | Name | Type           | Description                                        | Default |
    |------|----------------|----------------------------------------------------|---------|
    | Skip | System.Boolean | When true, omit from the container summary header. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetSkipSummary($true)

    .NOTES
    Fluent counterpart to the SkipSummary property.
    #>
    [IcingaPlugin] SetSkipSummary([bool]$Skip)
    {
        $this.SkipSummary = $Skip;
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value against the thresholds using the Icinga range grammar

    .DESCRIPTION
    Builds an IcingaThresholds pair from the configured warning, critical and base
    values, compares the node's value with the full Icinga/Nagios range grammar and
    immediately puts the node into the resulting state (escalate-only). Performance
    data is (re)built from the current value and thresholds.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> (New-IcingaPlugin 'Load' 95 '%').Warning('80').Critical('90').CheckRange()

    .NOTES
    Delegates to IcingaThresholds.CheckRange.
    #>
    [IcingaPlugin] CheckRange()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckRange($this.AttachBaseUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a greater-than comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    greater-than operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('80').Critical('90').CheckGreater()

    .NOTES
    Delegates to IcingaThresholds.CheckGreater.
    #>
    [IcingaPlugin] CheckGreater()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckGreater($this.AttachBaseUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a greater-than-or-equal comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    greater-than-or-equal operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('80').Critical('90').CheckGreaterEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckGreaterEqual.
    #>
    [IcingaPlugin] CheckGreaterEqual()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckGreaterEqual($this.AttachBaseUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a lower-than comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    lower-than operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('20').Critical('10').CheckLower()

    .NOTES
    Delegates to IcingaThresholds.CheckLower.
    #>
    [IcingaPlugin] CheckLower()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckLower($this.AttachBaseUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a lower-than-or-equal comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    lower-than-or-equal operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('20').Critical('10').CheckLowerEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckLowerEqual.
    #>
    [IcingaPlugin] CheckLowerEqual()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckLowerEqual($this.AttachBaseUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value against its maximum-relative thresholds

    .DESCRIPTION
    Requires a base value. Compares the node's value against the warning and
    critical thresholds relative to the base value (commonly percentages of the
    maximum) and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.BaseValue('1TB').Warning('80%').Critical('90%').CheckMax()

    .NOTES
    Delegates to IcingaThresholds.CheckMax; without a base value the result is UNKNOWN.
    #>
    [IcingaPlugin] CheckMax()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckMax($this.AttachBaseUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a regular-expression match

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds as regular
    expressions and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('^warn').Critical('^err').CheckMatch()

    .NOTES
    Delegates to IcingaThresholds.CheckMatch.
    #>
    [IcingaPlugin] CheckMatch()
    {
        if ($this.WarningList.Count -gt 1 -or $this.CriticalList.Count -gt 1) {
            $this.ApplyThresholdResult($this.EvaluateListComparison('match', 'matches'));
            return $this;
        }

        $this.ApplyThresholdResult($this.NewStringThresholds().CheckMatch($this.ResolveStringValue()));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a negated regular-expression match

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds as regular
    expressions and alerts when the value does NOT match, then puts the node into
    the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('^ok').Critical('^healthy').CheckNotMatch()

    .NOTES
    Delegates to IcingaThresholds.CheckNotMatch.
    #>
    [IcingaPlugin] CheckNotMatch()
    {
        if ($this.WarningList.Count -gt 1 -or $this.CriticalList.Count -gt 1) {
            $this.ApplyThresholdResult($this.EvaluateListComparison('notmatch', 'does not match'));
            return $this;
        }

        $this.ApplyThresholdResult($this.NewStringThresholds().CheckNotMatch($this.ResolveStringValue()));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a wildcard 'like' comparison

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds as PowerShell
    wildcard patterns and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('*warn*').Critical('*error*').CheckLike()

    .NOTES
    Delegates to IcingaThresholds.CheckLike.
    #>
    [IcingaPlugin] CheckLike()
    {
        if ($this.WarningList.Count -gt 1 -or $this.CriticalList.Count -gt 1) {
            $this.ApplyThresholdResult($this.EvaluateListComparison('like', 'is like'));
            return $this;
        }

        $this.ApplyThresholdResult($this.NewStringThresholds().CheckLike($this.ResolveStringValue()));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a negated wildcard 'like' comparison

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds as PowerShell
    wildcard patterns and alerts when the value is NOT like the pattern, then puts
    the node into the resulting state.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('*ok*').Critical('*healthy*').CheckNotLike()

    .NOTES
    Delegates to IcingaThresholds.CheckNotLike.
    #>
    [IcingaPlugin] CheckNotLike()
    {
        if ($this.WarningList.Count -gt 1 -or $this.CriticalList.Count -gt 1) {
            $this.ApplyThresholdResult($this.EvaluateListComparison('notlike', 'is not like'));
            return $this;
        }

        $this.ApplyThresholdResult($this.NewStringThresholds().CheckNotLike($this.ResolveStringValue()));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with an equality comparison

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds with a
    case-insensitive string equality test and puts the node into the resulting state.
    When an array of multiple warning or critical values was configured, alerts when
    the value equals any entry in the list.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('degraded').Critical('offline').CheckEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckEqual or EvaluateListComparison.
    #>
    [IcingaPlugin] CheckEqual()
    {
        if ($this.WarningList.Count -gt 1 -or $this.CriticalList.Count -gt 1) {
            $this.ApplyThresholdResult($this.EvaluateListComparison('eq', 'equals'));
            return $this;
        }

        $this.ApplyThresholdResult($this.NewStringThresholds().CheckEqual($this.ResolveStringValue()));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a negated equality comparison

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds with a
    case-insensitive string inequality test and puts the node into the resulting
    state. When an array of multiple warning or critical values was configured,
    alerts when the value does not equal any entry in the allowed list.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('online').Critical('online').CheckNotEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckNotEqual or EvaluateListComparison.
    #>
    [IcingaPlugin] CheckNotEqual()
    {
        if ($this.WarningList.Count -gt 1 -or $this.CriticalList.Count -gt 1) {
            $this.ApplyThresholdResult($this.EvaluateListComparison('ne', 'does not equal'));
            return $this;
        }

        $this.ApplyThresholdResult($this.NewStringThresholds().CheckNotEqual($this.ResolveStringValue()));
        return $this;
    }

    <#
    .SYNOPSIS
    Alert when the value matches any entry in the configured threshold list

    .DESCRIPTION
    Evaluates the node's value against the configured warning and critical threshold
    lists (or single values) using case-insensitive equality and alerts when the value
    is found in the list. Critical takes precedence over warning.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning(@('Paused', 'Pending')).Critical(@('Stopped')).CheckIn()

    .NOTES
    Delegates to CheckEqual.
    #>
    [IcingaPlugin] CheckIn()
    {
        return $this.CheckEqual();
    }

    <#
    .SYNOPSIS
    Alert when the value is not in the configured allowed threshold list

    .DESCRIPTION
    Evaluates the node's value against the configured warning and critical threshold
    lists (or single values) using case-insensitive equality and alerts when the value
    does not match any entry in the allowed list. Critical takes precedence over
    warning.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.Critical(@('Ready', 'Running')).CheckNotIn()

    .NOTES
    Delegates to CheckNotEqual.
    #>
    [IcingaPlugin] CheckNotIn()
    {
        return $this.CheckNotEqual();
    }

    <#
    .SYNOPSIS
    Resolve a threshold list with translation mapping applied

    .DESCRIPTION
    Returns the effective array of threshold strings from the supplied list (or the
    single fallback string when the list is empty), mapping each item through
    ResolveTranslation when a translation applies.

    .PARAMETER List
    | Name | Type         | Description                             | Default |
    |------|--------------|-----------------------------------------|---------|
    | List | System.Array | Multi-value threshold list on the node. |         |

    .PARAMETER Fallback
    | Name     | Type          | Description                              | Default |
    |----------|---------------|------------------------------------------|---------|
    | Fallback | System.String | Single threshold string when List empty. |         |

    .OUTPUTS
    System.Array -- Resolved threshold strings for comparison.

    .EXAMPLE
    PS> $this.ResolveThresholdList($this.CriticalList, $this.CriticalThreshold)

    .NOTES
    Internal helper used by EvaluateListComparison.
    #>
    hidden [array] ResolveThresholdList([array]$List, [string]$Fallback)
    {
        [array]$Source = @();

        if ($null -ne $List -and $List.Count -gt 0) {
            $Source = $List;
        } elseif ('' -ne $Fallback) {
            $Source = @($Fallback);
        }

        [array]$Resolved = @();

        foreach ($Entry in $Source) {
            [string]$Mapped = $this.ResolveTranslation($Entry);
            if ($null -ne $Mapped -and '' -ne $Mapped) {
                $Resolved += $Mapped;
            } else {
                $Resolved += [string]$Entry;
            }
        }

        return $Resolved;
    }

    <#
    .SYNOPSIS
    Find the first pattern in a list that matches the supplied string value

    .DESCRIPTION
    Iterates through the supplied pattern list and tests each entry against Value
    using case-insensitive equality ('eq'/'ne'), wildcard matching ('like'/'notlike')
    or regular-expression matching ('match'/'notmatch'). Returns the first matching
    pattern string, or $null when no entry matches.

    .PARAMETER InputValue
    | Name       | Type          | Description           | Default |
    |------------|---------------|-----------------------|---------|
    | InputValue | System.String | String value to test. |         |

    .PARAMETER Patterns
    | Name     | Type         | Description                  | Default |
    |----------|--------------|------------------------------|---------|
    | Patterns | System.Array | Candidate patterns to check. |         |

    .PARAMETER Operator
    | Name     | Type          | Description                                                | Default |
    |----------|---------------|------------------------------------------------------------|---------|
    | Operator | System.String | One of 'eq', 'ne', 'like', 'notlike', 'match', 'notmatch'. |         |

    .OUTPUTS
    System.String -- The first matching pattern, or '' when none matches.

    .EXAMPLE
    PS> $this.FindMatchingPattern('Ready', @('Ready', 'Running'), 'ne')

    .NOTES
    Internal helper used by EvaluateListComparison.
    #>
    hidden [string] FindMatchingPattern([string]$InputValue, [array]$Patterns, [string]$Operator)
    {
        foreach ($Entry in $Patterns) {
            [string]$Pattern = [string]$Entry;

            if ($Operator -eq 'eq' -or $Operator -eq 'ne') {
                if ($InputValue -eq $Pattern) {
                    return $Pattern;
                }
            } elseif ($Operator -eq 'like' -or $Operator -eq 'notlike') {
                if ($InputValue -like $Pattern) {
                    return $Pattern;
                }
            } elseif ($Operator -eq 'match' -or $Operator -eq 'notmatch') {
                if ($InputValue -match $Pattern) {
                    return $Pattern;
                }
            }
        }

        return '';
    }

    <#
    .SYNOPSIS
    Evaluate a multi-value threshold list comparison against the node's string value

    .DESCRIPTION
    Evaluates the node's resolved string value against multi-value warning and
    critical threshold lists. For positive operators ('eq', 'like', 'match'), raises
    an alert when the value matches any entry in the list; for negated operators
    ('ne', 'notlike', 'notmatch'), raises an alert when the list is non-empty and the
    value does not match any entry in the allowed list. Critical is evaluated before
    warning.

    .PARAMETER Operator
    | Name     | Type          | Description                                                | Default |
    |----------|---------------|------------------------------------------------------------|---------|
    | Operator | System.String | One of 'eq', 'ne', 'like', 'notlike', 'match', 'notmatch'. |         |

    .PARAMETER OperatorText
    | Name         | Type          | Description                              | Default |
    |--------------|---------------|------------------------------------------|---------|
    | OperatorText | System.String | Human-readable operator for the message. |         |

    .OUTPUTS
    System.Object -- An IcingaThresholdResult describing the outcome.

    .EXAMPLE
    PS> $this.EvaluateListComparison('ne', 'does not equal')

    .NOTES
    Internal helper used when WarningList or CriticalList contains multiple entries.
    #>
    hidden [object] EvaluateListComparison([string]$Operator, [string]$OperatorText)
    {
        [object]$ResolvedValue = $this.ResolveStringValue();
        if ($null -eq $ResolvedValue) {
            return [IcingaThresholdResult]::new($null, $this.WarningThreshold, $this.CriticalThreshold, 3, 'the value is null and cannot be compared as a string');
        }

        [string]$Text     = [string]$ResolvedValue;
        [array]$WarnItems = $this.ResolveThresholdList($this.WarningList, $this.WarningThreshold);
        [array]$CritItems = $this.ResolveThresholdList($this.CriticalList, $this.CriticalThreshold);
        [bool]$WarnSet    = ($WarnItems.Count -gt 0);
        [bool]$CritSet    = ($CritItems.Count -gt 0);
        [string]$WarnJoin = ($WarnItems -join ', ');
        [string]$CritJoin = ($CritItems -join ', ');

        if ($Operator -eq 'match' -or $Operator -eq 'notmatch') {
            foreach ($Pattern in $CritItems) {
                try {
                    [void][regex]::new([string]$Pattern);
                } catch {
                    return [IcingaThresholdResult]::new($Text, $WarnJoin, $CritJoin, 3, ("The critical pattern '{0}' is not a valid regular expression" -f $Pattern));
                }
            }

            foreach ($Pattern in $WarnItems) {
                try {
                    [void][regex]::new([string]$Pattern);
                } catch {
                    return [IcingaThresholdResult]::new($Text, $WarnJoin, $CritJoin, 3, ("The warning pattern '{0}' is not a valid regular expression" -f $Pattern));
                }
            }
        }

        [bool]$IsNegated = ($Operator -eq 'ne' -or $Operator -eq 'notlike' -or $Operator -eq 'notmatch');

        if ($CritSet) {
            [string]$MatchedCrit = $this.FindMatchingPattern($Text, $CritItems, $Operator);
            if ($IsNegated) {
                if ('' -eq $MatchedCrit) {
                    return [IcingaThresholdResult]::new($Text, $WarnJoin, $CritJoin, 2, ("'{0}' {1} pattern '{2}'" -f $Text, $OperatorText, $CritJoin));
                }
            } else {
                if ('' -ne $MatchedCrit) {
                    return [IcingaThresholdResult]::new($Text, $WarnJoin, $CritJoin, 2, ("'{0}' {1} pattern '{2}'" -f $Text, $OperatorText, $MatchedCrit));
                }
            }
        }

        if ($WarnSet) {
            [string]$MatchedWarn = $this.FindMatchingPattern($Text, $WarnItems, $Operator);
            if ($IsNegated) {
                if ('' -eq $MatchedWarn) {
                    return [IcingaThresholdResult]::new($Text, $WarnJoin, $CritJoin, 1, ("'{0}' {1} pattern '{2}'" -f $Text, $OperatorText, $WarnJoin));
                }
            } else {
                if ('' -ne $MatchedWarn) {
                    return [IcingaThresholdResult]::new($Text, $WarnJoin, $CritJoin, 1, ("'{0}' {1} pattern '{2}'" -f $Text, $OperatorText, $MatchedWarn));
                }
            }
        }

        return [IcingaThresholdResult]::new($Text, $WarnJoin, $CritJoin, 0, ("'{0}' is ok" -f $Text));
    }

    <#
    .SYNOPSIS
    Build an IcingaThresholds pair from the configured thresholds

    .DESCRIPTION
    Creates an IcingaThresholds object from the stored warning and critical strings,
    passing the base value as well when one was set. A plain numeric base value of a
    byte or time node carries the 'B' or 's' unit, so percent thresholds resolve and
    render in that unit. When the node itself already measures a percentage (Unit '%'),
    percentage signs on threshold bounds ('10%', '10%:80%') are normalized to plain
    numbers in that same '%' unit so callers may write either '10' or '10%' without
    requiring a separate base value or duplicating the percentage in the output. The
    return type is object because IcingaThresholds is parsed after IcingaPlugin during
    the build and may therefore only be referenced from method bodies.

    .OUTPUTS
    System.Object -- An IcingaThresholds instance.

    .EXAMPLE
    PS> $this.NewThresholds()

    .NOTES
    Internal helper used by every comparison method.
    #>
    hidden [object] NewThresholds()
    {
        [string]$Warning  = $this.WarningThreshold;
        [string]$Critical = $this.CriticalThreshold;

        if ($this.Unit -eq '%' -and ($null -eq $this.BaseValueSetting -or '' -eq [string]$this.BaseValueSetting -or [string]$this.BaseValueSetting -eq '100')) {
            $Warning  = $Warning -replace '(?<=\d)%', '';
            $Critical = $Critical -replace '(?<=\d)%', '';

            return [IcingaThresholds]::new($Warning, $Critical);
        }

        if ($null -ne $this.BaseValueSetting -and '' -ne [string]$this.BaseValueSetting) {
            return [IcingaThresholds]::new($Warning, $Critical, [string]$this.AttachBaseUnit($this.BaseValueSetting));
        }

        return [IcingaThresholds]::new($Warning, $Critical);
    }

    <#
    .SYNOPSIS
    Build an IcingaThresholds pair with translated string thresholds when applicable

    .DESCRIPTION
    Creates an IcingaThresholds instance for string/pattern comparison methods. When a
    translation table is configured, translates the warning and critical threshold
    tokens through ResolveTranslation so a caller may pass either a raw code ('4') or
    its translated display name ('Running').

    .OUTPUTS
    System.Object -- An IcingaThresholds instance.

    .EXAMPLE
    PS> $this.NewStringThresholds()

    .NOTES
    Internal helper used by CheckMatch, CheckNotMatch, CheckLike, CheckNotLike,
    CheckEqual and CheckNotEqual.
    #>
    hidden [object] NewStringThresholds()
    {
        [string]$Warning  = $this.WarningThreshold;
        [string]$Critical = $this.CriticalThreshold;

        if ('' -ne $Warning) {
            [string]$MappedWarning = $this.ResolveTranslation($Warning);
            if ($null -ne $MappedWarning -and '' -ne $MappedWarning) {
                $Warning = $MappedWarning;
            }
        }

        if ('' -ne $Critical) {
            [string]$MappedCritical = $this.ResolveTranslation($Critical);
            if ($null -ne $MappedCritical -and '' -ne $MappedCritical) {
                $Critical = $MappedCritical;
            }
        }

        return [IcingaThresholds]::new($Warning, $Critical);
    }

    <#
    .SYNOPSIS
    Resolve the node's value for string comparison and display

    .DESCRIPTION
    Returns the translated representation of the node's value when a translation is
    configured (or when Value is an enum), otherwise returns Value as-is.

    .OUTPUTS
    System.Object -- The value to compare in string comparison methods.

    .EXAMPLE
    PS> $this.ResolveStringValue()

    .NOTES
    Internal helper used by string comparison methods.
    #>
    hidden [object] ResolveStringValue()
    {
        if ($null -eq $this.Value) {
            return $null;
        }

        [string]$Mapped = $this.ResolveTranslation($this.Value);
        if ($null -ne $Mapped -and '' -ne $Mapped) {
            return $Mapped;
        }

        return $this.Value;
    }

    <#
    .SYNOPSIS
    Look up the human-readable translation for a value or threshold

    .DESCRIPTION
    Resolves an input item against TranslatedText (when matching the node's Value),
    the Translation hashtable (matching direct keys, numeric enum values and
    case-insensitive string keys), or a [System.Enum] name. Returns $null when no
    translation applies.

    .PARAMETER Item
    | Name | Type          | Description                      | Default |
    |------|---------------|----------------------------------|---------|
    | Item | System.Object | Value or threshold token to map. |         |

    .OUTPUTS
    System.String -- Translated display string, or $null when none applies.

    .EXAMPLE
    PS> $this.ResolveTranslation(4)

    .NOTES
    Internal helper shared by display rendering and string threshold comparisons.
    #>
    hidden [string] ResolveTranslation([object]$Item)
    {
        if ($null -eq $Item) {
            return $null;
        }

        if ('' -ne $this.TranslatedText -and [string]$Item -eq [string]$this.Value) {
            return $this.TranslatedText;
        }

        if ($null -ne $this.Translation -and $this.Translation.Count -gt 0) {
            if ($this.Translation.ContainsKey($Item)) {
                return [string]$this.Translation[$Item];
            }

            if ($Item -is [System.Enum]) {
                [int]$EnumCode = [int]$Item;
                if ($this.Translation.ContainsKey($EnumCode)) {
                    return [string]$this.Translation[$EnumCode];
                }
            }

            [string]$ItemText = [string]$Item;
            foreach ($Key in $this.Translation.Keys) {
                if ([string]::Equals([string]$Key, $ItemText, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [string]$this.Translation[$Key];
                }
            }
        }

        if ($Item -is [System.Enum]) {
            return [string]$Item;
        }

        return $null;
    }

    <#
    .SYNOPSIS
    Test whether the node measures plain bytes or plain seconds

    .DESCRIPTION
    Returns true when the node's unit is the byte base unit 'B' or the time base
    unit 's'. Such a node hands its value to the threshold engine as a byte or time
    quantity, so it compares exactly against size thresholds ('400GB'), duration
    thresholds ('30m', '1d:') and percent thresholds of a base value, and its output
    message shows human-readable sizes or durations. Plain-number thresholds keep
    meaning bytes or seconds, which matches both the threshold engine and the Icinga
    perfdata unit. Every other unit ('%', 'GiB', 'ms', none) returns false and keeps
    the plain display-unit behaviour.

    .OUTPUTS
    System.Boolean -- True when the unit is 'B' or 's'.

    .EXAMPLE
    PS> $this.HasBaseUnit()

    .NOTES
    Internal helper. Larger units are excluded on purpose: a plain threshold such as
    '80' would resolve to 80 bytes or seconds instead of 80 of the node's unit.
    #>
    hidden [bool] HasBaseUnit()
    {
        # Time units are case-sensitive in IcingaUnit ('m' minute, 'M' month), data units are not.
        return ($this.Unit -eq 'B' -or $this.Unit -ceq 's');
    }

    <#
    .SYNOPSIS
    Append the base unit to a plain numeric value

    .DESCRIPTION
    Turns a plain number into a '<number>B' or '<number>s' string (for example
    442692000000 becomes '442692000000B') when the node measures bytes or seconds, so
    the threshold engine resolves the value as a byte or time quantity. The number is
    written in fixed-point notation under the invariant culture so large byte counts
    never use an exponent. A duration below one second is written in milliseconds or
    microseconds ('0.004' becomes '4ms'), so the output message keeps its precision.
    Any other value, and every value of a node without such a base unit, is returned
    unchanged.

    .PARAMETER Value
    | Name  | Type          | Description                             | Default |
    |-------|---------------|-----------------------------------------|---------|
    | Value | System.Object | Measured value or base value to adjust. |         |

    .OUTPUTS
    System.Object -- The value with the unit attached, or the unchanged value.

    .EXAMPLE
    PS> $this.AttachBaseUnit(442692000000)

    .NOTES
    Internal helper used by the numeric comparison methods and NewThresholds.
    #>
    hidden [object] AttachBaseUnit([object]$Value)
    {
        if ($null -eq $Value -or -not $this.HasBaseUnit()) {
            return $Value;
        }

        [double]$Parsed = 0;
        if (-not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed)) {
            return $Value;
        }

        [string]$ValueUnit = $this.Unit;

        # The threshold engine renders a value in the unit it was given with at most two
        # decimals, so 0.004s would show as 0s. Sub-second durations are therefore handed
        # over in milli- or microseconds; the comparison is unaffected.
        if ($ValueUnit -ceq 's' -and $Parsed -ne 0 -and [System.Math]::Abs($Parsed) -lt 1) {
            if ([System.Math]::Abs($Parsed) -ge 0.001) {
                $Parsed    = $Parsed * 1000;
                $ValueUnit = 'ms';
            } else {
                $Parsed    = $Parsed * 1000000;
                $ValueUnit = 'us';
            }
        }

        return ($Parsed.ToString('0.##########', [System.Globalization.CultureInfo]::InvariantCulture) + $ValueUnit);
    }

    <#
    .SYNOPSIS
    Apply a threshold evaluation result to the node

    .DESCRIPTION
    Marks the node as evaluated, stores the human-readable output message, escalates
    the node state to the result's status code and rebuilds the performance data.
    The thresholds as resolved by the comparison (base units, percentages already
    applied) are kept for the performance data, because Icinga requires perfdata
    thresholds in the same unit as the value.

    .PARAMETER Result
    | Name   | Type          | Description                                 | Default |
    |--------|---------------|---------------------------------------------|---------|
    | Result | System.Object | An IcingaThresholdResult from a comparison. |         |

    .OUTPUTS
    None -- Updates instance state.

    .EXAMPLE
    PS> $this.ApplyThresholdResult($result)

    .NOTES
    Internal helper shared by every comparison method.
    #>
    hidden [void] ApplyThresholdResult([object]$Result)
    {
        $this.Evaluated = $true;

        # A locked node froze its state and message via an override; later threshold
        # evaluation must not overwrite either. EscalateState honours the lock too.
        if (-not $this.Locked) {
            if ([int]$Result.StatusCode -eq 3) {
                # Do not suffix units onto threshold parse/configuration error explanations.
                $this.OutputMessage = [string]$Result.Output;
            } elseif ($this.Unit -eq 'B') {
                $this.OutputMessage = $this.HumanizeByteValues([string]$Result.Output);
            } elseif ($this.Unit -ceq 's') {
                $this.OutputMessage = $this.HumanizeTimeValues([string]$Result.Output);
            } else {
                $this.OutputMessage = $this.ApplyDisplayUnit([string]$Result.Output);
            }

            if ([int]$Result.StatusCode -ne 3) {
                $this.OutputMessage = $this.ApplyValueTranslation($this.OutputMessage);
            }
        }

        $this.ResolvedWarning  = '';
        $this.ResolvedCritical = '';

        if ($null -ne $Result.WarningValue) {
            $this.ResolvedWarning = $this.FormatNumber($Result.WarningValue);
        }

        if ($null -ne $Result.CriticalValue) {
            $this.ResolvedCritical = $this.FormatNumber($Result.CriticalValue);
        }

        $this.EscalateState([int]$Result.StatusCode);
        $this.BuildPerfData();
    }

    <#
    .SYNOPSIS
    Replace the leading value figure in a numeric comparison message with its translation

    .DESCRIPTION
    When a translation applies to the node's measured value (for example 0 -> 'Never'
    on a time check, or 4 -> 'Running' on a numeric check), replaces the leading
    rendered value token in the threshold message with the translated string.

    .PARAMETER Message
    | Name    | Type          | Description                           | Default |
    |---------|---------------|---------------------------------------|---------|
    | Message | System.String | Output message after unit formatting. |         |

    .OUTPUTS
    System.String -- Message with the translated value applied when configured.

    .EXAMPLE
    PS> $this.ApplyValueTranslation('0s is ok')

    .NOTES
    Internal helper used by ApplyThresholdResult.
    #>
    hidden [string] ApplyValueTranslation([string]$Message)
    {
        [string]$Mapped = $this.ResolveTranslation($this.Value);
        if ($null -eq $Mapped -or '' -eq $Mapped) {
            return $Message;
        }

        # String comparisons already receive the translated value directly.
        if ($Message.StartsWith("'" + $Mapped + "'", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $Message;
        }

        [string]$Updated = [regex]::Replace($Message, '^-?\d+(?:\.\d+)?[A-Za-z%]*', ($Mapped -replace '\$', '$$$$'));

        if ($null -ne $this.Translation -and $this.Translation.Count -gt 0) {
            $ThresholdMatch = [regex]::Match($Updated, '\bthreshold\s+(-?\d+(?:\.\d+)?)\b');
            if ($ThresholdMatch.Success) {
                [string]$MappedThreshold = $this.ResolveTranslation($ThresholdMatch.Groups[1].Value);
                if ($null -ne $MappedThreshold -and '' -ne $MappedThreshold) {
                    $Updated = [regex]::Replace($Updated, '\bthreshold\s+-?\d+(?:\.\d+)?\b', ('threshold ' + ($MappedThreshold -replace '\$', '$$$$')));
                }
            }
        }

        return $Updated;
    }

    <#
    .SYNOPSIS
    Render plain byte figures of an output message as human-readable sizes

    .DESCRIPTION
    Replaces every '<number>B' figure in a threshold output message with its
    best-fitting binary size (for example '442692000000B' becomes '412.29GiB'). The
    threshold engine renders the value and the percent thresholds of a byte node in
    plain bytes; figures in any other unit (such as a '400GB' threshold) and
    percentages are left untouched.

    .PARAMETER Message
    | Name    | Type          | Description                   | Default |
    |---------|---------------|-------------------------------|---------|
    | Message | System.String | The threshold output message. |         |

    .OUTPUTS
    System.String -- The message with byte figures converted to their best-fit unit.

    .EXAMPLE
    PS> $this.HumanizeByteValues('442692000000B (86.46%) is greater than threshold 409600000000B (80%)')

    .NOTES
    Internal helper used by ApplyThresholdResult for byte nodes. A figure that
    IcingaUnit cannot convert is kept as it is. IcingaUnit is parsed after
    IcingaPlugin during the build, so it is referenced only inside this method body.
    #>
    hidden [string] HumanizeByteValues([string]$Message)
    {
        [string]$Output = '';
        [int]$Position  = 0;

        foreach ($Match in [regex]::Matches($Message, '(?<![\w.])(-?\d+(?:\.\d+)?)B\b')) {
            $Converted = [IcingaUnit]::new($Match.Groups[1].Value, 'B', '', $false);

            if (-not $Converted.Success) {
                continue;
            }

            $Output  += $Message.Substring($Position, $Match.Index - $Position) + $Converted.OutputString;
            $Position = $Match.Index + $Match.Length;
        }

        return ($Output + $Message.Substring($Position));
    }

    <#
    .SYNOPSIS
    Render plain second figures of an output message as human-readable durations

    .DESCRIPTION
    Replaces every '<number>s' figure in a threshold output message with its
    decomposed duration (for example '93784s' becomes '1d 2h 3m 4s'). The threshold
    engine renders the value and the percent thresholds of a time node in plain
    seconds; figures in any other unit (such as a '30m' threshold), plain numbers and
    percentages are left untouched.

    .PARAMETER Message
    | Name    | Type          | Description                   | Default |
    |---------|---------------|-------------------------------|---------|
    | Message | System.String | The threshold output message. |         |

    .OUTPUTS
    System.String -- The message with second figures converted to durations.

    .EXAMPLE
    PS> $this.HumanizeTimeValues('3600s is greater than threshold 30m')

    .NOTES
    Internal helper used by ApplyThresholdResult for time nodes. A figure that
    IcingaUnit cannot convert is kept as it is. IcingaUnit is parsed after
    IcingaPlugin during the build, so it is referenced only inside this method body.
    #>
    hidden [string] HumanizeTimeValues([string]$Message)
    {
        [string]$Output = '';
        [int]$Position  = 0;

        foreach ($Match in [regex]::Matches($Message, '(?<![\w.])(-?\d+(?:\.\d+)?)s\b')) {
            $Converted = [IcingaUnit]::new($Match.Groups[1].Value, 's', '', $false);

            if (-not $Converted.Success) {
                continue;
            }

            $Output  += $Message.Substring($Position, $Match.Index - $Position) + $Converted.OutputString;
            $Position = $Match.Index + $Match.Length;
        }

        return ($Output + $Message.Substring($Position));
    }

    <#
    .SYNOPSIS
    Append the display unit to the numeric figures of an output message

    .DESCRIPTION
    Suffixes the node's unit onto every bare number in a threshold output message so a
    plain display unit such as '%' shows on the value and thresholds (for example
    '95 is greater than threshold 90' becomes '95% is greater than threshold 90%').
    IcingaThresholds treats '%' only as a percent-of-base threshold, not as a value
    suffix, so this covers the common case of a dimensionless display unit. Numbers
    that already carry the unit or a percent sign are not doubled, and the continuous
    counter perfdata unit 'c' is not appended to display text.

    .PARAMETER Message
    | Name    | Type          | Description                   | Default |
    |---------|---------------|-------------------------------|---------|
    | Message | System.String | The threshold output message. |         |

    .OUTPUTS
    System.String -- The message with the unit appended to each bare number.

    .EXAMPLE
    PS> $this.ApplyDisplayUnit('95 is greater than threshold 90')

    .NOTES
    Internal helper used by ApplyThresholdResult. The unit's '$' characters are
    escaped so they are not treated as regex replacement references.
    #>
    hidden [string] ApplyDisplayUnit([string]$Message)
    {
        if ('' -eq $this.Unit -or $this.Unit -ceq 'c') {
            return $Message;
        }

        [string]$EscapedUnit = [regex]::Escape($this.Unit);
        [string]$Pattern     = [string]::Format('(?<![\w.])-?\d+(?:\.\d+)?(?![\w.])(?!\s*{0})(?!%)', $EscapedUnit);
        [string]$Replacement = '$0' + ($this.Unit -replace '\$', '$$$$');
        return [regex]::Replace($Message, $Pattern, $Replacement);
    }

    <#
    .SYNOPSIS
    Raise the node state without ever lowering it

    .DESCRIPTION
    Sets the node state to the supplied value only when it is worse than the current
    state, implementing the escalate-only rule shared by threshold evaluation and
    aggregation. A locked node is never changed.

    .PARAMETER State
    | Name  | Type         | Description                                     | Default |
    |-------|--------------|-------------------------------------------------|---------|
    | State | System.Int32 | Candidate state (0 OK, 1 WARN, 2 CRIT, 3 UNKN). |         |

    .OUTPUTS
    None -- Updates instance state.

    .EXAMPLE
    PS> $this.EscalateState(2)

    .NOTES
    Internal helper; use SetState to force a specific state instead.
    #>
    hidden [void] EscalateState([int]$State)
    {
        if ($this.Locked) {
            return;
        }

        if ($this.State -lt $State) {
            $this.State = $State;
        }
    }

    <#
    .SYNOPSIS
    Resolve a state name or numeric string to its integer exit code

    .DESCRIPTION
    Maps 'Ok', 'Warning', 'Critical', 'Unknown' (case-insensitively) or '0'..'3' to
    the corresponding Icinga plugin exit code (0..3). Unknown strings default to 3.

    .PARAMETER State
    | Name  | Type          | Description                                          | Default |
    |-------|---------------|------------------------------------------------------|---------|
    | State | System.String | State name ('Ok', 'Warning', 'Critical', 'Unknown'). |         |

    .OUTPUTS
    System.Int32 -- The resolved Icinga state code (0..3).

    .EXAMPLE
    PS> $this.ResolveStateCode('Critical')

    .NOTES
    Internal helper used by the string overloads of SetState and AddMissingChecks.
    #>
    hidden [int] ResolveStateCode([string]$State)
    {
        if ($null -eq $State) {
            return 3;
        }

        [string]$Key = $State.Trim().ToLowerInvariant();
        if ([IcingaPlugin]::StateMap.ContainsKey($Key)) {
            return [IcingaPlugin]::StateMap[$Key];
        }

        return 3;
    }

    <#
    .SYNOPSIS
    Force the node into a specific numeric state

    .DESCRIPTION
    Overrides the node state to the given integer exit code (0..3) without changing
    the output message or locking the node.

    .PARAMETER State
    | Name  | Type         | Description                                  | Default |
    |-------|--------------|----------------------------------------------|---------|
    | State | System.Int32 | Forced state (0 OK, 1 WARN, 2 CRIT, 3 UNKN). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetState(2)

    .NOTES
    Delegates to SetState([int], [string], [bool]).
    #>
    [IcingaPlugin] SetState([int]$State)
    {
        return $this.SetState($State, '', $false);
    }

    <#
    .SYNOPSIS
    Force the node into a specific numeric state with a message

    .DESCRIPTION
    Overrides the node state to the given integer exit code (0..3) and replaces the
    output message when one is given, without locking the node.

    .PARAMETER State
    | Name  | Type         | Description                                  | Default |
    |-------|--------------|----------------------------------------------|---------|
    | State | System.Int32 | Forced state (0 OK, 1 WARN, 2 CRIT, 3 UNKN). |         |

    .PARAMETER Message
    | Name    | Type          | Description                                    | Default |
    |---------|---------------|------------------------------------------------|---------|
    | Message | System.String | Output message; '' keeps the existing message. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetState(2, 'Service is stopped')

    .NOTES
    Delegates to SetState([int], [string], [bool]).
    #>
    [IcingaPlugin] SetState([int]$State, [string]$Message)
    {
        return $this.SetState($State, $Message, $false);
    }

    <#
    .SYNOPSIS
    Central override that forces a specific node state

    .DESCRIPTION
    The single, unified way to override a node's state. Unless the node is locked it
    marks the state as fixed, sets the requested state (this override may lower the
    state, unlike EscalateState) and replaces the output message when one is given.
    When Lock is true the node is locked so no later evaluation or aggregation can
    change it. Returns the node so overrides chain.

    .PARAMETER State
    | Name  | Type         | Description                                  | Default |
    |-------|--------------|----------------------------------------------|---------|
    | State | System.Int32 | Forced state (0 OK, 1 WARN, 2 CRIT, 3 UNKN). |         |

    .PARAMETER Message
    | Name    | Type          | Description                                    | Default |
    |---------|---------------|------------------------------------------------|---------|
    | Message | System.String | Output message; '' keeps the existing message. |         |

    .PARAMETER Lock
    | Name | Type           | Description                                        | Default |
    |------|----------------|----------------------------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state against later changes. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetState(2, 'Service is stopped', $true)

    .NOTES
    All SetOk/SetWarning/SetCritical/SetUnknown wrappers funnel through this method.
    #>
    [IcingaPlugin] SetState([int]$State, [string]$Message, [bool]$Lock)
    {
        if (-not $this.Locked) {
            $this.FixedState     = $true;
            $this.IsNoticeObject = $false;
            $this.State          = $State;
            if ('' -ne $Message) {
                $this.OutputMessage = $Message;
            }
        }

        if ($Lock) {
            $this.Locked = $true;
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Force the node into a state specified by name

    .DESCRIPTION
    Overrides the node state using a state name ('Ok', 'Warning', 'Critical',
    'Unknown') without changing the output message or locking the node.

    .PARAMETER State
    | Name  | Type          | Description                                            | Default |
    |-------|---------------|--------------------------------------------------------|---------|
    | State | System.String | Forced state ('Ok', 'Warning', 'Critical', 'Unknown'). |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetState($OverrideNotOk)

    .NOTES
    Delegates to SetState([int], [string], [bool]).
    #>
    [IcingaPlugin] SetState([string]$State)
    {
        return $this.SetState($this.ResolveStateCode($State), '', $false);
    }

    <#
    .SYNOPSIS
    Force the node into a state specified by name with a message

    .DESCRIPTION
    Overrides the node state using a state name ('Ok', 'Warning', 'Critical',
    'Unknown') and replaces the output message when one is given.

    .PARAMETER State
    | Name  | Type          | Description                                            | Default |
    |-------|---------------|--------------------------------------------------------|---------|
    | State | System.String | Forced state ('Ok', 'Warning', 'Critical', 'Unknown'). |         |

    .PARAMETER Message
    | Name    | Type          | Description                                    | Default |
    |---------|---------------|------------------------------------------------|---------|
    | Message | System.String | Output message; '' keeps the existing message. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetState($OverrideNotOk, 'Service is stopped')

    .NOTES
    Delegates to SetState([int], [string], [bool]).
    #>
    [IcingaPlugin] SetState([string]$State, [string]$Message)
    {
        return $this.SetState($this.ResolveStateCode($State), $Message, $false);
    }

    <#
    .SYNOPSIS
    Force the node into a state specified by name, optionally locking it

    .DESCRIPTION
    Overrides the node state using a state name ('Ok', 'Warning', 'Critical',
    'Unknown'), replaces the output message when one is given, and optionally locks
    the state against later changes.

    .PARAMETER State
    | Name  | Type          | Description                                            | Default |
    |-------|---------------|--------------------------------------------------------|---------|
    | State | System.String | Forced state ('Ok', 'Warning', 'Critical', 'Unknown'). |         |

    .PARAMETER Message
    | Name    | Type          | Description                                    | Default |
    |---------|---------------|------------------------------------------------|---------|
    | Message | System.String | Output message; '' keeps the existing message. |         |

    .PARAMETER Lock
    | Name | Type           | Description                                        | Default |
    |------|----------------|----------------------------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state against later changes. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetState($OverrideNotOk, '', $true)

    .NOTES
    Delegates to SetState([int], [string], [bool]).
    #>
    [IcingaPlugin] SetState([string]$State, [string]$Message, [bool]$Lock)
    {
        return $this.SetState($this.ResolveStateCode($State), $Message, $Lock);
    }

    <#
    .SYNOPSIS
    Force the node into the OK state without changing the output message

    .DESCRIPTION
    Overrides the node state to OK while keeping the existing or default output
    message.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetOk()

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetOk()
    {
        return $this.SetState(0, '', $false);
    }

    <#
    .SYNOPSIS
    Force the node into the OK state

    .DESCRIPTION
    Overrides the node state to OK with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                      | Default |
    |---------|---------------|----------------------------------|---------|
    | Message | System.String | Output message for the OK state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetOk('All good')

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetOk([string]$Message)
    {
        return $this.SetState(0, $Message, $false);
    }

    <#
    .SYNOPSIS
    Force the node into the OK state, optionally locking it

    .DESCRIPTION
    Overrides the node state to OK with the given message and, when Lock is true,
    freezes the state against later changes.

    .PARAMETER Message
    | Name    | Type          | Description                      | Default |
    |---------|---------------|----------------------------------|---------|
    | Message | System.String | Output message for the OK state. |         |

    .PARAMETER Lock
    | Name | Type           | Description                  | Default |
    |------|----------------|------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetOk('All good', $true)

    .NOTES
    Convenience wrapper around SetState.
    #>
    [IcingaPlugin] SetOk([string]$Message, [bool]$Lock)
    {
        return $this.SetState(0, $Message, $Lock);
    }

    <#
    .SYNOPSIS
    Force the node into the WARNING state without changing the output message

    .DESCRIPTION
    Overrides the node state to WARNING while keeping the existing or default output
    message.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetWarning()

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetWarning()
    {
        return $this.SetState(1, '', $false);
    }

    <#
    .SYNOPSIS
    Force the node into the WARNING state

    .DESCRIPTION
    Overrides the node state to WARNING with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                           | Default |
    |---------|---------------|---------------------------------------|---------|
    | Message | System.String | Output message for the WARNING state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetWarning('Approaching limit')

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetWarning([string]$Message)
    {
        return $this.SetState(1, $Message, $false);
    }

    <#
    .SYNOPSIS
    Force the node into the WARNING state, optionally locking it

    .DESCRIPTION
    Overrides the node state to WARNING with the given message and, when Lock is
    true, freezes the state against later changes.

    .PARAMETER Message
    | Name    | Type          | Description                           | Default |
    |---------|---------------|---------------------------------------|---------|
    | Message | System.String | Output message for the WARNING state. |         |

    .PARAMETER Lock
    | Name | Type           | Description                  | Default |
    |------|----------------|------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetWarning('Approaching limit', $true)

    .NOTES
    Convenience wrapper around SetState.
    #>
    [IcingaPlugin] SetWarning([string]$Message, [bool]$Lock)
    {
        return $this.SetState(1, $Message, $Lock);
    }

    <#
    .SYNOPSIS
    Force the node into the CRITICAL state without changing the output message

    .DESCRIPTION
    Overrides the node state to CRITICAL while keeping the existing or default output
    message.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetCritical()

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetCritical()
    {
        return $this.SetState(2, '', $false);
    }

    <#
    .SYNOPSIS
    Force the node into the CRITICAL state

    .DESCRIPTION
    Overrides the node state to CRITICAL with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message for the CRITICAL state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetCritical('Service is stopped')

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetCritical([string]$Message)
    {
        return $this.SetState(2, $Message, $false);
    }

    <#
    .SYNOPSIS
    Force the node into the CRITICAL state, optionally locking it

    .DESCRIPTION
    Overrides the node state to CRITICAL with the given message and, when Lock is
    true, freezes the state against later changes.

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message for the CRITICAL state. |         |

    .PARAMETER Lock
    | Name | Type           | Description                  | Default |
    |------|----------------|------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetCritical('Service is stopped', $true)

    .NOTES
    Convenience wrapper around SetState.
    #>
    [IcingaPlugin] SetCritical([string]$Message, [bool]$Lock)
    {
        return $this.SetState(2, $Message, $Lock);
    }

    <#
    .SYNOPSIS
    Force the node into the UNKNOWN state without changing the output message

    .DESCRIPTION
    Overrides the node state to UNKNOWN while keeping the existing or default output
    message.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetUnknown()

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetUnknown()
    {
        return $this.SetState(3, '', $false);
    }

    <#
    .SYNOPSIS
    Force the node into the UNKNOWN state

    .DESCRIPTION
    Overrides the node state to UNKNOWN with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                           | Default |
    |---------|---------------|---------------------------------------|---------|
    | Message | System.String | Output message for the UNKNOWN state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetUnknown('Data source unavailable')

    .NOTES
    Convenience wrapper around SetState; does not lock the state.
    #>
    [IcingaPlugin] SetUnknown([string]$Message)
    {
        return $this.SetState(3, $Message, $false);
    }

    <#
    .SYNOPSIS
    Force the node into the UNKNOWN state, optionally locking it

    .DESCRIPTION
    Overrides the node state to UNKNOWN with the given message and, when Lock is
    true, freezes the state against later changes.

    .PARAMETER Message
    | Name    | Type          | Description                           | Default |
    |---------|---------------|---------------------------------------|---------|
    | Message | System.String | Output message for the UNKNOWN state. |         |

    .PARAMETER Lock
    | Name | Type           | Description                  | Default |
    |------|----------------|------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetUnknown('Data source unavailable', $true)

    .NOTES
    Convenience wrapper around SetState.
    #>
    [IcingaPlugin] SetUnknown([string]$Message, [bool]$Lock)
    {
        return $this.SetState(3, $Message, $Lock);
    }

    <#
    .SYNOPSIS
    Put the node into a locked UNKNOWN error state with a message

    .DESCRIPTION
    Reports that the check could not be performed, typically because collecting
    its data failed. The node is forced to UNKNOWN and locked, so no later
    comparison or aggregation can change it, and the message is shown on the
    node's output line even when the node is a container with children.

    .PARAMETER Message
    | Name    | Type          | Description            | Default |
    |---------|---------------|------------------------|---------|
    | Message | System.String | Error message to show. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> return $CheckPackage.SetError('No partition data available').Compile()

    .NOTES
    The message is used verbatim, without format processing.
    #>
    [IcingaPlugin] SetError([string]$Message)
    {
        return $this.ApplyError($Message);
    }

    <#
    .SYNOPSIS
    Put the node into a locked UNKNOWN error state with a formatted message

    .DESCRIPTION
    Like SetError([string]), with the '{0}' placeholder of the message replaced by
    the argument in the style of [string]::Format.

    .PARAMETER Message
    | Name    | Type          | Description                             | Default |
    |---------|---------------|-----------------------------------------|---------|
    | Message | System.String | Format string with a '{0}' placeholder. |         |

    .PARAMETER Argument
    | Name     | Type          | Description               | Default |
    |----------|---------------|---------------------------|---------|
    | Argument | System.Object | Value inserted for '{0}'. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $CheckPackage.SetError('Failed to read the counter {0}', $CounterPath)

    .NOTES
    Formatting never throws; see IcingaError.FormatMessage.
    #>
    [IcingaPlugin] SetError([string]$Message, [object]$Argument)
    {
        return $this.ApplyError([IcingaError]::FormatMessage($Message, @($Argument)));
    }

    <#
    .SYNOPSIS
    Put the node into a locked UNKNOWN error state with a message and two arguments

    .DESCRIPTION
    Like SetError([string]), with the '{0}' and '{1}' placeholders of the message
    replaced by the arguments in the style of [string]::Format.

    .PARAMETER Message
    | Name    | Type          | Description                         | Default |
    |---------|---------------|-------------------------------------|---------|
    | Message | System.String | Format string with '{0}' and '{1}'. |         |

    .PARAMETER Argument1
    | Name      | Type          | Description               | Default |
    |-----------|---------------|---------------------------|---------|
    | Argument1 | System.Object | Value inserted for '{0}'. |         |

    .PARAMETER Argument2
    | Name      | Type          | Description               | Default |
    |-----------|---------------|---------------------------|---------|
    | Argument2 | System.Object | Value inserted for '{1}'. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $CheckPackage.SetError('Failed to query {0}: {1}', $ClassName, $Reason)

    .NOTES
    Formatting never throws; see IcingaError.FormatMessage.
    #>
    [IcingaPlugin] SetError([string]$Message, [object]$Argument1, [object]$Argument2)
    {
        return $this.ApplyError([IcingaError]::FormatMessage($Message, @($Argument1, $Argument2)));
    }

    <#
    .SYNOPSIS
    Put the node into a locked UNKNOWN error state with a message and three arguments

    .DESCRIPTION
    Like SetError([string]), with the '{0}', '{1}' and '{2}' placeholders of the
    message replaced by the arguments in the style of [string]::Format.

    .PARAMETER Message
    | Name    | Type          | Description                             | Default |
    |---------|---------------|-----------------------------------------|---------|
    | Message | System.String | Format string with '{0}', '{1}', '{2}'. |         |

    .PARAMETER Argument1
    | Name      | Type          | Description               | Default |
    |-----------|---------------|---------------------------|---------|
    | Argument1 | System.Object | Value inserted for '{0}'. |         |

    .PARAMETER Argument2
    | Name      | Type          | Description               | Default |
    |-----------|---------------|---------------------------|---------|
    | Argument2 | System.Object | Value inserted for '{1}'. |         |

    .PARAMETER Argument3
    | Name      | Type          | Description               | Default |
    |-----------|---------------|---------------------------|---------|
    | Argument3 | System.Object | Value inserted for '{2}'. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $CheckPackage.SetError('{0} failed on {1}: {2}', $Step, $Target, $Reason)

    .NOTES
    For more arguments use the SetError([string], [object[]]) overload.
    #>
    [IcingaPlugin] SetError([string]$Message, [object]$Argument1, [object]$Argument2, [object]$Argument3)
    {
        return $this.ApplyError([IcingaError]::FormatMessage($Message, @($Argument1, $Argument2, $Argument3)));
    }

    <#
    .SYNOPSIS
    Put the node into a locked UNKNOWN error state with a message and an argument list

    .DESCRIPTION
    Like SetError([string]), with the placeholders of the message replaced by the
    elements of the argument array in the style of [string]::Format.

    .PARAMETER Message
    | Name    | Type          | Description                                  | Default |
    |---------|---------------|----------------------------------------------|---------|
    | Message | System.String | Format string with '{0}'-style placeholders. |         |

    .PARAMETER Arguments
    | Name      | Type            | Description                            | Default |
    |-----------|-----------------|----------------------------------------|---------|
    | Arguments | System.Object[] | Values inserted into the placeholders. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $CheckPackage.SetError('{0}/{1}/{2}/{3}', @('a', 'b', 'c', 'd'))

    .NOTES
    Formatting never throws; see IcingaError.FormatMessage.
    #>
    [IcingaPlugin] SetError([string]$Message, [object[]]$Arguments)
    {
        return $this.ApplyError([IcingaError]::FormatMessage($Message, $Arguments));
    }

    <#
    .SYNOPSIS
    Put the node into a locked UNKNOWN error state from an IcingaError

    .DESCRIPTION
    Takes the error object a data collection function returned instead of its data
    and shows its message, so a plugin reports the failure with a single call.

    .PARAMETER IcingaError
    | Name        | Type        | Description                          | Default |
    |-------------|-------------|--------------------------------------|---------|
    | IcingaError | IcingaError | Error returned by a data collection. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> if (Test-IcingaError -InputObject $Services) { return $CheckPackage.SetError($Services).Compile(); }

    .NOTES
    A $null error falls back to a generic message instead of failing.
    #>
    [IcingaPlugin] SetError([IcingaError]$IcingaError)
    {
        if ($null -eq $IcingaError) {
            return $this.ApplyError('An unknown error occurred');
        }

        return $this.ApplyError($IcingaError.Message);
    }

    <#
    .SYNOPSIS
    Apply the error state shared by every SetError overload

    .DESCRIPTION
    Marks the node as failed, so its output line shows the message even as a
    container, and forces it into a locked UNKNOWN state. A node that is already
    locked keeps its state and message.

    .PARAMETER Message
    | Name    | Type          | Description          | Default |
    |---------|---------------|----------------------|---------|
    | Message | System.String | Final error message. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $this.ApplyError('Failed to query Win32_Service')

    .NOTES
    Internal helper; funnels into SetState like every other override.
    #>
    hidden [IcingaPlugin] ApplyError([string]$Message)
    {
        if (-not $this.Locked) {
            $this.HasError = $true;
        }

        return $this.SetState(3, $Message, $true);
    }

    <#
    .SYNOPSIS
    Mark the node or container as an informational notice

    .DESCRIPTION
    Turns the node or package into an informational notice that renders with the
    [INFO] prefix and keeps the OK state without changing the output message.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $noticePkg.SetNotice()

    .NOTES
    Notices never raise the plugin state; they are purely informational.
    #>
    [IcingaPlugin] SetNotice()
    {
        if (-not $this.Locked) {
            $this.State    = 0;
            $this.IsNotice = $true;
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Mark the node as an informational notice

    .DESCRIPTION
    Turns the node into an informational object that renders with the [INFO] prefix
    and keeps the OK state, replacing the output message when one is given.

    .PARAMETER Message
    | Name    | Type          | Description                       | Default |
    |---------|---------------|-----------------------------------|---------|
    | Message | System.String | Informational message to display. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetNotice('Collected 5 samples')

    .NOTES
    Notices never raise the plugin state; they are purely informational.
    #>
    [IcingaPlugin] SetNotice([string]$Message)
    {
        return $this.SetNotice($Message, $false);
    }

    <#
    .SYNOPSIS
    Mark the node as an informational notice, optionally locking it

    .DESCRIPTION
    Turns the node into an informational object that renders with the [INFO] prefix
    and keeps the OK state, replacing the output message when one is given. When Lock
    is true the node is frozen against later changes.

    .PARAMETER Message
    | Name    | Type          | Description                       | Default |
    |---------|---------------|-----------------------------------|---------|
    | Message | System.String | Informational message to display. |         |

    .PARAMETER Lock
    | Name | Type           | Description                 | Default |
    |------|----------------|-----------------------------|---------|
    | Lock | System.Boolean | When true, freeze the node. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $check.SetNotice('Collected 5 samples', $true)

    .NOTES
    Notices never raise the plugin state; they are purely informational.
    #>
    [IcingaPlugin] SetNotice([string]$Message, [bool]$Lock)
    {
        if (-not $this.Locked) {
            $this.State          = 0;
            $this.IsNoticeObject = $true;
            if ('' -ne $Message) {
                $this.OutputMessage = $Message;
            }
        }

        if ($Lock) {
            $this.Locked = $true;
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Aggregate children with the 'all must be OK' operator

    .DESCRIPTION
    Sets the container operator so the node becomes not-OK as soon as any child is
    not OK. This is the default operator.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.CheckAnd()

    .NOTES
    Equivalent to the default; use CheckDefault for the same effect.
    #>
    [IcingaPlugin] CheckAnd()
    {
        $this.Operator = 'And';
        return $this;
    }

    <#
    .SYNOPSIS
    Aggregate children with the 'at least one must be OK' operator

    .DESCRIPTION
    Sets the container operator so the node is OK as long as at least one child is
    OK, and becomes not-OK only when every child is not OK.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.CheckOr()

    .NOTES
    Mirrors the classic OperatorOr package behaviour.
    #>
    [IcingaPlugin] CheckOr()
    {
        $this.Operator = 'Or';
        return $this;
    }

    <#
    .SYNOPSIS
    Aggregate children with the 'none may be OK' operator

    .DESCRIPTION
    Sets the container operator so the node becomes not-OK as soon as any child is
    OK.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.CheckNone()

    .NOTES
    Mirrors the classic OperatorNone package behaviour.
    #>
    [IcingaPlugin] CheckNone()
    {
        $this.Operator = 'None';
        return $this;
    }

    <#
    .SYNOPSIS
    Aggregate children with the default operator

    .DESCRIPTION
    Sets the container operator to the default 'all must be OK'. Provided so the
    intent can be stated explicitly in a chain.

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.CheckDefault()

    .NOTES
    Identical to CheckAnd.
    #>
    [IcingaPlugin] CheckDefault()
    {
        $this.Operator = 'And';
        return $this;
    }

    <#
    .SYNOPSIS
    Require at least a minimum number of OK children

    .DESCRIPTION
    Sets the container so it becomes not-OK when fewer than Count children are OK.

    .PARAMETER Count
    | Name  | Type         | Description                                 | Default |
    |-------|--------------|---------------------------------------------|---------|
    | Count | System.Int32 | Minimum number of children that must be OK. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.CheckMinimum(3)

    .NOTES
    Distinct from the leaf CheckMax comparison; this counts OK children.
    #>
    [IcingaPlugin] CheckMinimum([int]$Count)
    {
        $this.OperatorMin = $Count;
        return $this;
    }

    <#
    .SYNOPSIS
    Allow at most a maximum number of OK children

    .DESCRIPTION
    Sets the container so it becomes not-OK when more than Count children are OK.

    .PARAMETER Count
    | Name  | Type         | Description                                | Default |
    |-------|--------------|--------------------------------------------|---------|
    | Count | System.Int32 | Maximum number of children that may be OK. |         |

    .OUTPUTS
    IcingaPlugin -- The same node, for chaining.

    .EXAMPLE
    PS> $package.CheckMaximum(5)

    .NOTES
    Distinct from the leaf CheckMax comparison; this counts OK children.
    #>
    [IcingaPlugin] CheckMaximum([int]$Count)
    {
        $this.OperatorMax = $Count;
        return $this;
    }

    <#
    .SYNOPSIS
    Add a child plugin to this node

    .DESCRIPTION
    Registers a child plugin, sets its parent, indentation and verbosity, propagates
    the indentation into any grandchildren and appends it to the list of children.
    Returns this container so multiple AddCheck calls chain.

    .PARAMETER Check
    | Name  | Type         | Description          | Default |
    |-------|--------------|----------------------|---------|
    | Check | IcingaPlugin | Child plugin to add. |         |

    .OUTPUTS
    IcingaPlugin -- This container, for chaining.

    .EXAMPLE
    PS> $package.AddCheck($diskC).AddCheck($diskD)

    .NOTES
    A $null child is ignored.
    #>
    [IcingaPlugin] AddCheck([IcingaPlugin]$Check)
    {
        if ($null -eq $Check) {
            return $this;
        }

        $Check.Parent    = $this;
        $Check.Indention = $this.Indention + 1;
        $Check.Verbose   = $this.Verbose;
        $Check.PropagateIndention();
        $this.Checks    += $Check;

        return $this;
    }

    <#
    .SYNOPSIS
    Add multiple child plugins to this node

    .DESCRIPTION
    Adds every plugin in the supplied array as a child, in order. Returns this
    container so the call chains.

    .PARAMETER Checks
    | Name   | Type         | Description           | Default |
    |--------|--------------|-----------------------|---------|
    | Checks | System.Array | Child plugins to add. |         |

    .OUTPUTS
    IcingaPlugin -- This container, for chaining.

    .EXAMPLE
    PS> $package.AddCheck(@($diskC, $diskD))

    .NOTES
    Each element is added through the single-child AddCheck overload.
    #>
    [IcingaPlugin] AddCheck([array]$Checks)
    {
        foreach ($Check in $Checks) {
            $this.AddCheck($Check);
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Add a check for every required entry that is missing from the available ones

    .DESCRIPTION
    Compares a list of required entries (for example the -RequiredPartition or
    -Service arguments of a plugin) with the entries found on the host and adds a
    child check for every required entry without a match. The new check is named
    after NameFormat with '{0}' replaced by the entry, carries the message and is
    locked in the given state, so the plugin reports missing objects with a single
    call instead of its own loop.

    Required entries are wildcard patterns compared case-insensitively, so a plain
    name matches itself. An entry is found when either its raw form or its form
    without NormalizePattern matches an available entry. The normalized form is
    also used in the check name, so 'C:' with NormalizePattern '[:\\/]+$' is
    found as 'C' and reported as 'Partition C'.

    .PARAMETER Required
    | Name     | Type         | Description                                 | Default |
    |----------|--------------|---------------------------------------------|---------|
    | Required | System.Array | Entries that must exist, wildcards allowed. |         |

    .PARAMETER Available
    | Name      | Type         | Description                          | Default |
    |-----------|--------------|--------------------------------------|---------|
    | Available | System.Array | Entries that were found on the host. |         |

    .PARAMETER NameFormat
    | Name       | Type          | Description                                  | Default |
    |------------|---------------|----------------------------------------------|---------|
    | NameFormat | System.String | Check name with '{0}' for the missing entry. |         |

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message of every missing check. |         |

    .PARAMETER State
    | Name  | Type         | Description                                                 | Default |
    |-------|--------------|-------------------------------------------------------------|---------|
    | State | System.Int32 | State of the missing checks (0 OK, 1 WARN, 2 CRIT, 3 UNKN). |         |

    .OUTPUTS
    IcingaPlugin -- This container, for chaining.

    .EXAMPLE
    PS> $CheckPackage.AddMissingChecks($Service, $KnownServices, '{0}', 'Service not found', 3).Commit()

    .NOTES
    Delegates to the overload with NormalizePattern, without normalization.
    #>
    [IcingaPlugin] AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [int]$State)
    {
        return $this.AddMissingChecks($Required, $Available, $NameFormat, $Message, $State, '');
    }

    <#
    .SYNOPSIS
    Add a check for every required entry that is missing, with entry normalization

    .DESCRIPTION
    Like AddMissingChecks without NormalizePattern; every match of the regular
    expression NormalizePattern is removed from a required entry before it is
    compared a second time and before it is used in the check name. An invalid
    regular expression leaves the entries unchanged.

    .PARAMETER Required
    | Name     | Type         | Description                                 | Default |
    |----------|--------------|---------------------------------------------|---------|
    | Required | System.Array | Entries that must exist, wildcards allowed. |         |

    .PARAMETER Available
    | Name      | Type         | Description                          | Default |
    |-----------|--------------|--------------------------------------|---------|
    | Available | System.Array | Entries that were found on the host. |         |

    .PARAMETER NameFormat
    | Name       | Type          | Description                                  | Default |
    |------------|---------------|----------------------------------------------|---------|
    | NameFormat | System.String | Check name with '{0}' for the missing entry. |         |

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message of every missing check. |         |

    .PARAMETER State
    | Name  | Type         | Description                                                 | Default |
    |-------|--------------|-------------------------------------------------------------|---------|
    | State | System.Int32 | State of the missing checks (0 OK, 1 WARN, 2 CRIT, 3 UNKN). |         |

    .PARAMETER NormalizePattern
    | Name             | Type          | Description                                       | Default |
    |------------------|---------------|---------------------------------------------------|---------|
    | NormalizePattern | System.String | Regex removed from each entry; '' keeps it as is. |         |

    .OUTPUTS
    IcingaPlugin -- This container, for chaining.

    .EXAMPLE
    PS> $CheckPackage.AddMissingChecks($RequiredPartition, $KnownPartitions, 'Partition {0}', 'Mandatory partition not found on host', 2, '[:\\/]+$').Commit()

    .NOTES
    An invalid wildcard pattern counts as not found, so the entry is reported.
    #>
    [IcingaPlugin] AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [int]$State, [string]$NormalizePattern)
    {
        foreach ($Entry in $Required) {
            [string]$Raw        = [string]$Entry;
            [string]$Normalized = $Raw;

            if ('' -eq $Raw) {
                continue;
            }

            if ('' -ne $NormalizePattern) {
                try {
                    $Normalized = [regex]::Replace($Raw, $NormalizePattern, '');
                } catch {
                    $Error.Clear();
                }
            }

            if ($this.ContainsMatch($Available, $Raw) -or $this.ContainsMatch($Available, $Normalized)) {
                continue;
            }

            $this.AddCheck(
                [IcingaPlugin]::new([IcingaError]::FormatMessage($NameFormat, @($Normalized))).SetState($State, $Message, $true)
            ).Commit();
        }

        return $this;
    }

    <#
    .SYNOPSIS
    Add a check for every required entry that is missing, using a state name

    .DESCRIPTION
    Like AddMissingChecks with an integer state, accepting the state by name
    ('Ok', 'Warning', 'Critical', 'Unknown').

    .PARAMETER Required
    | Name     | Type         | Description                                 | Default |
    |----------|--------------|---------------------------------------------|---------|
    | Required | System.Array | Entries that must exist, wildcards allowed. |         |

    .PARAMETER Available
    | Name      | Type         | Description                          | Default |
    |-----------|--------------|--------------------------------------|---------|
    | Available | System.Array | Entries that were found on the host. |         |

    .PARAMETER NameFormat
    | Name       | Type          | Description                                  | Default |
    |------------|---------------|----------------------------------------------|---------|
    | NameFormat | System.String | Check name with '{0}' for the missing entry. |         |

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message of every missing check. |         |

    .PARAMETER State
    | Name  | Type          | Description                                          | Default |
    |-------|---------------|------------------------------------------------------|---------|
    | State | System.String | State name ('Ok', 'Warning', 'Critical', 'Unknown'). |         |

    .OUTPUTS
    IcingaPlugin -- This container, for chaining.

    .EXAMPLE
    PS> $CheckPackage.AddMissingChecks($Service, $KnownServices, '{0}', 'Service not found', 'Critical').Commit()

    .NOTES
    Delegates to the overload with NormalizePattern, without normalization.
    #>
    [IcingaPlugin] AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [string]$State)
    {
        return $this.AddMissingChecks($Required, $Available, $NameFormat, $Message, $this.ResolveStateCode($State), '');
    }

    <#
    .SYNOPSIS
    Add a check for every required entry that is missing, with entry normalization and a state name

    .DESCRIPTION
    Like AddMissingChecks with NormalizePattern, accepting the state by name
    ('Ok', 'Warning', 'Critical', 'Unknown').

    .PARAMETER Required
    | Name     | Type         | Description                                 | Default |
    |----------|--------------|---------------------------------------------|---------|
    | Required | System.Array | Entries that must exist, wildcards allowed. |         |

    .PARAMETER Available
    | Name      | Type         | Description                          | Default |
    |-----------|--------------|--------------------------------------|---------|
    | Available | System.Array | Entries that were found on the host. |         |

    .PARAMETER NameFormat
    | Name       | Type          | Description                                  | Default |
    |------------|---------------|----------------------------------------------|---------|
    | NameFormat | System.String | Check name with '{0}' for the missing entry. |         |

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message of every missing check. |         |

    .PARAMETER State
    | Name  | Type          | Description                                          | Default |
    |-------|---------------|------------------------------------------------------|---------|
    | State | System.String | State name ('Ok', 'Warning', 'Critical', 'Unknown'). |         |

    .PARAMETER NormalizePattern
    | Name             | Type          | Description                                       | Default |
    |------------------|---------------|---------------------------------------------------|---------|
    | NormalizePattern | System.String | Regex removed from each entry; '' keeps it as is. |         |

    .OUTPUTS
    IcingaPlugin -- This container, for chaining.

    .EXAMPLE
    PS> $CheckPackage.AddMissingChecks($RequiredPartition, $KnownPartitions, 'Partition {0}', 'Mandatory partition not found on host', 'Critical', '[:\\/]+$').Commit()

    .NOTES
    Delegates to the integer state overload after resolving the state name.
    #>
    [IcingaPlugin] AddMissingChecks([array]$Required, [array]$Available, [string]$NameFormat, [string]$Message, [string]$State, [string]$NormalizePattern)
    {
        return $this.AddMissingChecks($Required, $Available, $NameFormat, $Message, $this.ResolveStateCode($State), $NormalizePattern);
    }

    <#
    .SYNOPSIS
    Test whether any entry matches a wildcard pattern

    .DESCRIPTION
    Compares every entry, converted to a string, case-insensitively with the
    wildcard pattern. An invalid pattern matches nothing instead of throwing.

    .PARAMETER Entries
    | Name    | Type         | Description         | Default |
    |---------|--------------|---------------------|---------|
    | Entries | System.Array | Entries to compare. |         |

    .PARAMETER Pattern
    | Name    | Type          | Description                | Default |
    |---------|---------------|----------------------------|---------|
    | Pattern | System.String | Wildcard pattern to match. |         |

    .OUTPUTS
    System.Boolean -- True when at least one entry matches.

    .EXAMPLE
    PS> $this.ContainsMatch(@('C', 'D'), 'c')

    .NOTES
    Internal helper of AddMissingChecks.
    #>
    hidden [bool] ContainsMatch([array]$Entries, [string]$Pattern)
    {
        try {
            foreach ($Entry in $Entries) {
                if ([string]$Entry -like $Pattern) {
                    return $true;
                }
            }
        } catch {
            $Error.Clear();
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Test whether the node has any visible child check

    .DESCRIPTION
    Returns true as soon as at least one non-hidden child was added, so a plugin can
    detect an empty package and report it, for example with
    SetError('No service matches the given filter'). Hidden children carry background
    metrics only and do not count as active checks.

    .OUTPUTS
    System.Boolean -- True when the node has at least one non-hidden child.

    .EXAMPLE
    PS> if (-not $CheckPackage.HasChecks()) { return $CheckPackage.SetError('Nothing to check').Compile(); }

    .NOTES
    Counts direct non-hidden children only.
    #>
    [bool] HasChecks()
    {
        foreach ($Child in $this.Checks) {
            if (-not $Child.IsHidden) {
                return $true;
            }
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Test whether this node is an empty container without value, state or checks

    .DESCRIPTION
    Returns true when the node has no visible child checks, no own value, was neither
    evaluated nor locked into a fixed or error state, is not a notice leaf and carries
    no output message. Used by ResolveState to apply the classic empty-package handling
    (UNKNOWN 'No checks added to this package', OK when IgnoreEmptyPackage is set, or
    [INFO] 'Nothing to report' for a notice package).

    .OUTPUTS
    System.Boolean -- True when this node is an empty package.

    .EXAMPLE
    PS> $this.IsEmptyPackage()

    .NOTES
    Internal helper used by ResolveState.
    #>
    hidden [bool] IsEmptyPackage()
    {
        return (
            -not $this.HasChecks() -and
            $null -eq $this.Value -and
            -not $this.Evaluated -and
            -not $this.FixedState -and
            -not $this.IsNoticeObject -and
            -not $this.HasError -and
            '' -eq $this.OutputMessage
        );
    }

    <#
    .SYNOPSIS
    Test whether this node is an informational notice node

    .DESCRIPTION
    Returns true when the node is a notice package (IsNotice), an explicit notice leaf
    (SetNotice / IsNoticeObject), or an unevaluated leaf without a fixed state (which
    renders as [INFO]). Notice nodes never participate in state aggregation or summary
    counts.

    .OUTPUTS
    System.Boolean -- True when this node is purely informational.

    .EXAMPLE
    PS> $this.IsNoticeNode()

    .NOTES
    Internal helper used by ResolveState and CollectLeafChecks.
    #>
    hidden [bool] IsNoticeNode()
    {
        if ($this.IsNotice -or $this.IsNoticeObject) {
            return $true;
        }

        if (-not $this.HasChecks() -and -not $this.FixedState -and -not $this.Evaluated -and -not $this.IgnoredEmpty) {
            return $true;
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Ensure a leaf check with a value has a default output message and performance data

    .DESCRIPTION
    Populates a default output message from the node's value (applying any configured
    translation, human-readable byte/time conversion or display unit) when no threshold
    comparison or state override set one, and builds the node's performance data when
    none was built yet or when metric attributes were updated after comparison.

    .OUTPUTS
    None -- Updates OutputMessage and PerfData on this node.

    .EXAMPLE
    PS> $this.EnsureLeafDefaults()

    .NOTES
    Internal helper called by ResolveState.
    #>
    hidden [void] EnsureLeafDefaults()
    {
        if ($null -eq $this.Value -or $this.HasError) {
            return;
        }

        if ('' -eq $this.OutputMessage) {
            [string]$Translated = $this.ResolveTranslation($this.Value);

            if ('' -ne $Translated) {
                $this.OutputMessage = $Translated;
            } elseif ($this.Unit -eq 'B' -and $this.IsNumeric($this.Value)) {
                $this.OutputMessage = $this.HumanizeByteValues([string]::Format('{0}B', $this.FormatNumber($this.Value)));
            } elseif ($this.Unit -ceq 's' -and $this.IsNumeric($this.Value)) {
                $this.OutputMessage = $this.HumanizeTimeValues([string]::Format('{0}s', $this.FormatNumber($this.Value)));
            } elseif ($this.IsNumeric($this.Value)) {
                $this.OutputMessage = $this.ApplyDisplayUnit($this.FormatNumber($this.Value));
            } else {
                $this.OutputMessage = [string]$this.Value;
            }
        }

        if (-not ($this.Evaluated -and $this.PerfData.Count -eq 0 -and $this.State -eq 3)) {
            $this.BuildPerfData();
        }
    }

    <#
    .SYNOPSIS
    Recompute the indentation of all descendants

    .DESCRIPTION
    Sets every child's indentation to one level below this node and propagates the
    verbosity, then recurses. Needed when a subtree that already had children is
    attached to a new parent.

    .OUTPUTS
    None -- Updates the children's state.

    .EXAMPLE
    PS> $this.PropagateIndention()

    .NOTES
    Internal helper used by AddCheck.
    #>
    hidden [void] PropagateIndention()
    {
        foreach ($Child in $this.Checks) {
            $Child.Indention = $this.Indention + 1;
            $Child.Verbose   = $this.Verbose;
            $Child.PropagateIndention();
        }
    }

    <#
    .SYNOPSIS
    Propagate a verbosity level through the whole subtree

    .DESCRIPTION
    Sets this node's verbosity and recursively applies it to every descendant.
    Called at compile time so a verbosity set on the root after the tree was built
    still reaches every child and controls the output pruning consistently.

    .PARAMETER Verbose
    | Name    | Type         | Description                          | Default |
    |---------|--------------|--------------------------------------|---------|
    | Verbose | System.Int32 | Verbosity level to apply everywhere. |         |

    .OUTPUTS
    None -- Updates this node and its descendants.

    .EXAMPLE
    PS> $this.PropagateVerbose(2)

    .NOTES
    Internal helper used by Compile.
    #>
    hidden [void] PropagateVerbose([int]$Verbose)
    {
        $this.Verbose = $Verbose;

        foreach ($Child in $this.Checks) {
            $Child.PropagateVerbose($Verbose);
        }
    }

    <#
    .SYNOPSIS
    Resolve the final state of this node and its subtree

    .DESCRIPTION
    For a leaf, ensures default output and performance data are populated and returns
    the state that threshold evaluation or an override set. For an empty package
    without value or children, marks the node as UNKNOWN ('No checks added to this
    package'), OK when IgnoreEmptyPackage is enabled, or [INFO] ('Nothing to report')
    when IsNotice is enabled. For a container, recursively resolves every child,
    counts OK versus not-OK children (skipping hidden, notice and ignored-empty nodes;
    a hybrid node's own evaluated state counts as one more element), determines the
    worst child state and escalates this node according to the configured operator
    (And/Or/None and the Minimum/Maximum counts).

    .OUTPUTS
    System.Int32 -- The resolved state of this node.

    .EXAMPLE
    PS> $this.ResolveState()

    .NOTES
    Called by Compile before rendering; escalate-only, so overrides survive.
    #>
    hidden [int] ResolveState()
    {
        if (-not $this.HasChecks()) {
            foreach ($Child in $this.Checks) {
                [void]$Child.ResolveState();
            }

            if ($this.IsEmptyPackage()) {
                if ($this.IsNotice) {
                    $this.OutputMessage = 'Nothing to report';
                    return $this.State;
                }

                if ($this.IgnoreEmptyPackage) {
                    $this.IgnoredEmpty = $true;
                    $this.FixedState   = $true;
                    return $this.State;
                }

                $this.ApplyError('No checks added to this object');
                return $this.State;
            }

            $this.EnsureLeafDefaults();
            return $this.State;
        }

        if ($null -ne $this.Value) {
            $this.EnsureLeafDefaults();
        }

        [int]$Worst   = 0;
        [int]$OkCount = 0;
        [int]$NotOk   = 0;

        foreach ($Child in $this.Checks) {
            [int]$ChildState = $Child.ResolveState();

            if ($Child.IsHidden -or $Child.IsNoticeNode() -or $Child.IgnoredEmpty) {
                continue;
            }

            if ($Worst -lt $ChildState) {
                $Worst = $ChildState;
            }

            if ($ChildState -eq 0) {
                $OkCount++;
            } else {
                $NotOk++;
            }
        }

        if ($this.Evaluated) {
            if ($Worst -lt $this.State) {
                $Worst = $this.State;
            }

            if ($this.State -eq 0) {
                $OkCount++;
            } else {
                $NotOk++;
            }
        }

        # A Minimum/Maximum count replaces the And/Or/None rule (Minimum and Maximum
        # may be combined); otherwise the And/Or/None operator decides. When a count
        # or None rule is violated even though all children are OK ($Worst -eq 0),
        # escalate to CRITICAL (2).
        if ($this.OperatorMin -ne -1 -or $this.OperatorMax -ne -1) {
            if ($this.OperatorMin -ne -1 -and $OkCount -lt $this.OperatorMin) {
                $this.EscalateState([System.Math]::Max($Worst, 2));
            }

            if ($this.OperatorMax -ne -1 -and $OkCount -gt $this.OperatorMax) {
                $this.EscalateState([System.Math]::Max($Worst, 2));
            }
        } else {
            switch ($this.Operator) {
                'And' {
                    if ($NotOk -ne 0) {
                        $this.EscalateState($Worst);
                    }
                    break;
                }
                'Or' {
                    if (($OkCount + $NotOk) -gt 0 -and $OkCount -eq 0) {
                        $this.EscalateState($Worst);
                    }
                    break;
                }
                'None' {
                    if ($OkCount -ne 0) {
                        $this.EscalateState([System.Math]::Max($Worst, 2));
                    }
                    break;
                }
            }
        }

        return $this.State;
    }

    <#
    .SYNOPSIS
    Report whether this node has any not-OK children

    .DESCRIPTION
    Returns true when at least one visible child is not OK, or when a hybrid node's
    own evaluated state is not OK. Used to decide whether a container is shown at low
    verbosity levels.

    .OUTPUTS
    System.Boolean -- True when a not-OK child (or own state) exists.

    .EXAMPLE
    PS> $this.HasNotOkChecks()

    .NOTES
    Requires ResolveState to have run so child states are final.
    #>
    hidden [bool] HasNotOkChecks()
    {
        foreach ($Child in $this.Checks) {
            if ($Child.IsHidden) {
                continue;
            }

            if ($Child.State -ne 0) {
                return $true;
            }
        }

        if ($this.Evaluated -and $this.State -ne 0) {
            return $true;
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Decide whether this node is printed at the current verbosity

    .DESCRIPTION
    Reproduces the classic verbosity pruning: the root always prints; verbosity 2 or
    higher prints everything; a not-OK node always prints; a container prints when it
    has not-OK children; at verbosity 1 an OK child of an affected parent also
    prints. Otherwise the node is hidden from the output.

    .OUTPUTS
    System.Boolean -- True when the node should be part of the output.

    .EXAMPLE
    PS> $this.CanOutput()

    .NOTES
    Verbosity is propagated from the root through AddCheck.
    #>
    hidden [bool] CanOutput()
    {
        if ($this.Indention -eq 0) {
            return $true;
        }

        if ($this.Verbose -ge 2) {
            return $true;
        }

        if ($this.State -ne 0) {
            return $true;
        }

        if ($this.HasChecks()) {
            return $this.HasNotOkChecks();
        }

        if ($this.Verbose -eq 1 -and $null -ne $this.Parent -and $this.Parent.HasChecks()) {
            return $this.Parent.HasNotOkChecks();
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Build the indentation prefix for a tree level

    .DESCRIPTION
    Returns the leading whitespace and '\_ ' marker for the given indentation level,
    matching the classic Icinga for Windows nested output. Level 0 has no prefix.

    .PARAMETER Indention
    | Name      | Type         | Description            | Default |
    |-----------|--------------|------------------------|---------|
    | Indention | System.Int32 | Zero-based tree depth. |         |

    .OUTPUTS
    System.String -- The indentation prefix.

    .EXAMPLE
    PS> $this.IndentPrefix(1)

    .NOTES
    Level 1 is flush-left ('\_ '); each additional level adds three leading spaces.
    #>
    hidden [string] IndentPrefix([int]$Indention)
    {
        if ($Indention -le 0) {
            return '';
        }

        # First level ('\_ ') starts at column 0; only deeper levels are indented.
        [string]$Prefix = '';
        for ($i = 1; $i -lt $Indention; $i++) {
            $Prefix += '   ';
        }

        return $Prefix + '\_ ';
    }

    <#
    .SYNOPSIS
    Build the single output line for this node

    .DESCRIPTION
    Returns the container summary line when the node has visible children, otherwise
    the leaf line.

    .OUTPUTS
    System.String -- The node's own one-line output (without indentation).

    .EXAMPLE
    PS> $this.BuildLine()

    .NOTES
    Internal helper used by RenderOutput.
    #>
    hidden [string] BuildLine()
    {
        if ($this.HasChecks()) {
            return $this.BuildContainerLine();
        }

        return $this.BuildLeafLine();
    }

    <#
    .SYNOPSIS
    Build the output line for a leaf check

    .DESCRIPTION
    Renders '[STATE] Name: message' (or '[STATE] Name' without a message). A node
    that was neither evaluated nor forced, or one explicitly marked as a notice,
    renders with the [INFO] prefix.

    .OUTPUTS
    System.String -- The leaf output line.

    .EXAMPLE
    PS> $this.BuildLeafLine()

    .NOTES
    Internal helper used by BuildLine.
    #>
    hidden [string] BuildLeafLine()
    {
        [string]$Status = [IcingaPlugin]::StateText[$this.State];

        if ($this.IsNoticeObject -or $this.IsNotice) {
            $Status = '[INFO]';
        } elseif (-not $this.FixedState -and -not $this.Evaluated) {
            $Status = '[INFO]';
        }

        if ('' -ne $this.OutputMessage) {
            return [string]::Format('{0} {1}: {2}', $Status, $this.Name, $this.OutputMessage);
        }

        return [string]::Format('{0} {1}', $Status, $this.Name);
    }

    <#
    .SYNOPSIS
    Build the output line for a container

    .DESCRIPTION
    Renders '[STATE] Name'. At the root, or when AddSummaryHeader is set, it also
    appends the summary header: a per-state count of every leaf check in the whole
    subtree (containers themselves are not counted) including the OK count, followed
    by the named lists of the not-OK leaf checks, for example
    '[CRITICAL] Disks: 2 Critical 2 Ok [CRITICAL] C:, D:'. At verbosity level 3 or
    higher the operator configuration is appended, for example ' (All must be [OK])'.
    A notice package renders with the [INFO] prefix. A container put into the error
    state with SetError renders '[UNKNOWN] Name: message' instead of the summary
    header.

    .OUTPUTS
    System.String -- The container output line.

    .EXAMPLE
    PS> $this.BuildContainerLine()

    .NOTES
    Internal helper used by BuildLine. The header aggregates leaf checks recursively
    so the first line reflects the state of every actual check, not just the direct
    children.
    #>
    hidden [string] BuildContainerLine()
    {
        [string]$Status = [IcingaPlugin]::StateText[$this.State];

        if ($this.IsNotice) {
            $Status = '[INFO]';
        }

        [string]$Config = '';
        if ($this.Verbose -ge 3) {
            $Config = $this.ShowPackageConfig();
        }

        # The error explains why the checks below are incomplete, so it replaces the
        # summary header instead of being hidden behind it.
        if ($this.HasError -and '' -ne $this.OutputMessage) {
            return [string]::Format('{0} {1}: {2}{3}', $Status, $this.Name, $this.OutputMessage, $Config);
        }

        if ($this.Indention -ne 0 -and -not $this.AddSummaryHeader) {
            return [string]::Format('{0} {1}{2}', $Status, $this.Name, $Config);
        }

        [array]$Leaves   = $this.CollectLeafChecks();
        [int]$OkCount    = 0;
        [array]$Unknown  = @();
        [array]$Critical = @();
        [array]$Warning  = @();

        foreach ($Leaf in $Leaves) {
            switch ($Leaf.State) {
                3 { $Unknown  += $Leaf.Name; break; }
                2 { $Critical += $Leaf.Name; break; }
                1 { $Warning  += $Leaf.Name; break; }
                0 { $OkCount++; break; }
            }
        }

        [string]$Summary = '';
        if ($Unknown.Count -gt 0) {
            $Summary += [string]::Format(' {0} Unknown', $Unknown.Count);
        }
        if ($Critical.Count -gt 0) {
            $Summary += [string]::Format(' {0} Critical', $Critical.Count);
        }
        if ($Warning.Count -gt 0) {
            $Summary += [string]::Format(' {0} Warning', $Warning.Count);
        }
        if ($OkCount -gt 0) {
            $Summary += [string]::Format(' {0} Ok', $OkCount);
        }

        [string]$Lists = '';
        if ($Unknown.Count -gt 0) {
            $Lists += [string]::Format(' [UNKNOWN] {0}', ($Unknown -join ', '));
        }
        if ($Critical.Count -gt 0) {
            $Lists += [string]::Format(' [CRITICAL] {0}', ($Critical -join ', '));
        }
        if ($Warning.Count -gt 0) {
            $Lists += [string]::Format(' [WARNING] {0}', ($Warning -join ', '));
        }

        [string]$Colon = '';
        if ('' -ne $Summary -or '' -ne $Lists) {
            $Colon = ':';
        }

        return [string]::Format('{0} {1}{2}{3}{4}{5}', $Status, $this.Name, $Colon, $Summary, $Lists, $Config);
    }

    <#
    .SYNOPSIS
    Collect every leaf check in the subtree

    .DESCRIPTION
    Recursively gathers all descendant nodes that are active leaf checks (nodes
    without visible children), skipping container nodes, hidden nodes, nodes with
    SkipSummary set, ignored-empty packages and informational notice nodes. Used by
    the summary header so the root line reflects the state of every actual check
    regardless of nesting depth.

    .OUTPUTS
    System.Array -- The leaf IcingaPlugin nodes in the subtree.

    .EXAMPLE
    PS> $this.CollectLeafChecks()

    .NOTES
    Internal helper used by BuildContainerLine.
    #>
    hidden [array] CollectLeafChecks()
    {
        [array]$Leaves = @();

        foreach ($Child in $this.Checks) {
            if ($Child.IsHidden -or $Child.SkipSummary -or $Child.IsNoticeNode() -or $Child.IgnoredEmpty) {
                continue;
            }

            if (-not $Child.HasChecks()) {
                $Leaves += $Child;
            } else {
                $Leaves += $Child.CollectLeafChecks();
            }
        }

        return $Leaves;
    }

    <#
    .SYNOPSIS
    Describe the container's aggregation operator

    .DESCRIPTION
    Returns a short, human-readable suffix describing how the container aggregates
    its children, matching the classic package config text. Shown in the output at
    verbosity level 3 or higher.

    .OUTPUTS
    System.String -- The operator description, for example ' (All must be [OK])'.

    .EXAMPLE
    PS> $this.ShowPackageConfig()

    .NOTES
    Internal helper used by BuildContainerLine; the Minimum/Maximum counts take
    precedence over the And/Or/None operator when set.
    #>
    hidden [string] ShowPackageConfig()
    {
        # Match the original framework: notice packages and the 'None' operator carry
        # no configuration text.
        if ($this.IsNotice) {
            return '';
        }

        if ($this.OperatorMin -ne -1 -and $this.OperatorMax -ne -1) {
            return [string]::Format(' (Between {0} and {1} must be [OK])', $this.OperatorMin, $this.OperatorMax);
        }

        if ($this.OperatorMin -ne -1) {
            return [string]::Format(' (Atleast {0} must be [OK])', $this.OperatorMin);
        }

        if ($this.OperatorMax -ne -1) {
            return [string]::Format(' (Not more than {0} must be [OK])', $this.OperatorMax);
        }

        if ($this.Operator -eq 'And') {
            return ' (All must be [OK])';
        }

        if ($this.Operator -eq 'Or') {
            return ' (Atleast one must be [OK])';
        }

        return '';
    }

    <#
    .SYNOPSIS
    Render the indented output tree for this node

    .DESCRIPTION
    Produces the node's own line prefixed with its indentation and recursively
    appends the rendered output of every visible child, joined with newlines. Hidden
    nodes and nodes pruned by the current verbosity are skipped.

    .OUTPUTS
    System.String -- The multi-line, indented output.

    .EXAMPLE
    PS> $this.RenderOutput()

    .NOTES
    Requires ResolveState to have run so states are final.
    #>
    hidden [string] RenderOutput()
    {
        if ($this.IsHidden -or -not $this.CanOutput()) {
            return '';
        }

        [array]$Lines = @();
        $Lines       += ($this.IndentPrefix($this.Indention) + $this.BuildLine());

        foreach ($Child in $this.Checks) {
            if ($Child.IsHidden -or -not $Child.CanOutput()) {
                continue;
            }

            $Lines += $Child.RenderOutput();
        }

        return ($Lines -join "`n");
    }

    <#
    .SYNOPSIS
    Resolve a node value to its numeric representation for performance data

    .DESCRIPTION
    Converts enumeration values to their underlying integer and maps translated string
    values back to their numeric key when a translation hashtable is present. Returns
    the value unchanged when it is already numeric or has no numeric representation.

    .PARAMETER Item
    | Name | Type          | Description                   | Default |
    |------|---------------|-------------------------------|---------|
    | Item | System.Object | Value to resolve numerically. |         |

    .OUTPUTS
    System.Object -- The numeric representation, or the original value.

    .EXAMPLE
    PS> $this.ResolveNumericValue($this.Value)

    .NOTES
    Internal helper used by BuildPerfData.
    #>
    hidden [object] ResolveNumericValue([object]$Item)
    {
        if ($null -eq $Item) {
            return $null;
        }

        if ($Item -is [System.Enum]) {
            return [int]$Item;
        }

        if ($this.IsNumeric($Item)) {
            return $Item;
        }

        if ($this.Translation.Count -gt 0) {
            [string]$ItemText = [string]$Item;
            foreach ($Key in $this.Translation.Keys) {
                if ([string]$this.Translation[$Key] -ieq $ItemText -and $this.IsNumeric($Key)) {
                    return $Key;
                }
            }
        }

        return $Item;
    }

    <#
    .SYNOPSIS
    Resolve a threshold to a valid numeric Icinga performance-data threshold string

    .DESCRIPTION
    Returns the resolved threshold when it is already a valid numeric or Icinga range
    expression. When a string threshold matches a translated display name (for example
    'Running' mapped from 4), returns the corresponding numeric key ('4'). Non-numeric
    string patterns (such as regex or wildcard patterns) are omitted from performance
    data by returning an empty string.

    .PARAMETER Threshold
    | Name      | Type          | Description                  | Default |
    |-----------|---------------|------------------------------|---------|
    | Threshold | System.String | Configured threshold string. |         |

    .PARAMETER Resolved
    | Name     | Type          | Description                       | Default |
    |----------|---------------|-----------------------------------|---------|
    | Resolved | System.String | Threshold resolved by comparison. |         |

    .OUTPUTS
    System.String -- Numeric Icinga threshold string, or '' when non-numeric.

    .EXAMPLE
    PS> $this.ResolvePerfDataThreshold($this.CriticalThreshold, $this.ResolvedCritical)

    .NOTES
    Internal helper used by BuildPerfData.
    #>
    hidden [string] ResolvePerfDataThreshold([string]$Threshold, [string]$Resolved)
    {
        if ($this.Unit -eq '%' -and '' -ne $Threshold) {
            $Threshold = $Threshold -replace '(?<=\d)%', '';
        }

        if ('' -ne $Resolved -and $Resolved -match '^@?(~|-?\d+(?:\.\d+)?)(:(-?\d+(?:\.\d+)?)?)?$') {
            return $Resolved;
        }

        if ('' -ne $Threshold -and $Threshold -match '^@?(~|-?\d+(?:\.\d+)?)(:(-?\d+(?:\.\d+)?)?)?$') {
            return $Threshold;
        }

        [string]$Candidate = $Threshold;
        if ('' -ne $Resolved) {
            $Candidate = $Resolved;
        }

        if ('' -eq $Candidate) {
            return '';
        }

        if ('' -ne $this.TranslatedText -and $this.TranslatedText -ieq $Candidate -and $this.IsNumeric($this.Value)) {
            return $this.FormatNumber($this.Value);
        }

        if ($this.Translation.Count -gt 0) {
            foreach ($Key in $this.Translation.Keys) {
                if (([string]$this.Translation[$Key] -ieq $Candidate -or [string]$Key -ieq $Candidate) -and $this.IsNumeric($Key)) {
                    return $this.FormatNumber($Key);
                }
            }
        }

        return '';
    }

    <#
    .SYNOPSIS
    Rebuild the performance data for a leaf check

    .DESCRIPTION
    Formats a single performance-data metric of the form
    index::ifw_template::label=value<unit>;warn;crit;min;max (the check_multi format)
    from the current value, unit and thresholds, and stores it as this node's
    performance data. The thresholds are written as resolved by the last comparison
    (percent and unit thresholds in base units, for example '80%' of 500GB becomes
    '400000000000'), falling back to the configured strings when no resolved value
    exists. The structured label is built by BuildPerfDataLabel. No metric is produced
    when performance data is disabled or the value is not numeric.

    .OUTPUTS
    None -- Updates this node's performance data.

    .EXAMPLE
    PS> $this.BuildPerfData()

    .NOTES
    Called after each comparison and during state resolution; only numeric values yield perfdata.
    #>
    hidden [void] BuildPerfData()
    {
        $this.PerfData = @();

        if ($this.NoPerfData) {
            return;
        }

        [object]$NumericValue = $this.ResolveNumericValue($this.Value);

        if (-not $this.IsNumeric($NumericValue)) {
            return;
        }

        [string]$Warning  = $this.ResolvePerfDataThreshold($this.WarningThreshold, $this.ResolvedWarning);
        [string]$Critical = $this.ResolvePerfDataThreshold($this.CriticalThreshold, $this.ResolvedCritical);

        [string]$Metric   = [string]::Format(
            '{0}={1}{2};{3};{4};{5};{6}',
            $this.BuildPerfDataLabel(),
            $this.FormatNumber($NumericValue),
            $this.Unit,
            $Warning,
            $Critical,
            $this.MinimumValue,
            $this.MaximumValue
        );

        $this.PerfData    = @($Metric);
    }

    <#
    .SYNOPSIS
    Detect the calling Invoke-IcingaCheck* command from the call stack

    .DESCRIPTION
    Walks the PowerShell call stack and returns the name of the first frame whose
    command looks like an Icinga check command (Invoke-IcingaCheck*). This is used to
    derive the default performance-data template. Returns an empty string when no such
    command is on the stack (for example when constructed outside a plugin).

    .OUTPUTS
    System.String -- The check command name, or '' when none was found.

    .EXAMPLE
    PS> $this.DetectCheckCommand()

    .NOTES
    Internal helper called at construction; caches the resolved command in
    (Get-GlobalRuntimeVariable).Private.Icinga.ActiveCheckCommand until Compile resets it.
    #>
    hidden [string] DetectCheckCommand()
    {
        $GlobalVariable = Get-GlobalRuntimeVariable;

        # Reuse the cached command name across all child/metric nodes built during the current check run
        # so Get-PSCallStack is walked only once on the very first node instead of O(N) times per plugin
        if (-not [string]::IsNullOrEmpty($GlobalVariable.Private.Icinga.ActiveCheckCommand)) {
            return $GlobalVariable.Private.Icinga.ActiveCheckCommand;
        }

        foreach ($Frame in (Get-PSCallStack)) {
            if (([string]$Frame.Command).ToLower() -like 'invoke-icingacheck*') {
                $GlobalVariable.Private.Icinga.ActiveCheckCommand = [string]$Frame.Command;
                return [string]$Frame.Command;
            }
        }

        return '';
    }

    <#
    .SYNOPSIS
    Sanitize a performance-data metric segment

    .DESCRIPTION
    Removes every non-word character and lower-cases the value so a metric segment is
    a safe, space-free token for the check_multi label. Underscores are preserved.

    .PARAMETER Value
    | Name  | Type          | Description             | Default |
    |-------|---------------|-------------------------|---------|
    | Value | System.String | The raw metric segment. |         |

    .OUTPUTS
    System.String -- The sanitized, lower-cased segment.

    .EXAMPLE
    PS> $this.SanitizeMetric('Core #0')

    .NOTES
    Internal helper used by BuildPerfDataLabel.
    #>
    hidden [string] SanitizeMetric([string]$Value)
    {
        return ($Value -replace '[\W]', '').ToLower();
    }

    <#
    .SYNOPSIS
    Build the check_multi performance-data label

    .DESCRIPTION
    Assembles the structured label 'index::ifw_template::label' used by the check_multi
    performance-data format. The index defaults to 'default'; the template defaults to
    the calling Invoke-IcingaCheck* command with that prefix stripped (falling back to
    'check'), always carries the fixed 'ifw_' namespace, and can be overridden with
    MetricName; the label defaults to the node's Name (falling back to 'value' when
    sanitizing strips all characters) and can be overridden with MetricLabel. Every
    segment is sanitized and lower-cased, with fallbacks applied after sanitization.

    .OUTPUTS
    System.String -- The structured performance-data label.

    .EXAMPLE
    PS> $this.BuildPerfDataLabel()

    .NOTES
    Internal helper used by BuildPerfData. Example: 'c::ifw_partitionspace::free'.
    #>
    hidden [string] BuildPerfDataLabel()
    {
        [string]$Index = $this.SanitizeMetric($this.MetricIndexValue);
        if ('' -eq $Index) {
            $Index = 'default';
        }

        [string]$RawTemplate = $this.MetricNameValue;
        if ('' -eq $RawTemplate) {
            $RawTemplate = ([string]$this.CheckCommand) -replace '(?i)^Invoke-IcingaCheck', '';
        }
        $RawTemplate      = $RawTemplate -replace '(?i)^ifw_', '';

        [string]$Template = $this.SanitizeMetric($RawTemplate);
        if ('' -eq $Template) {
            $Template = 'check';
        }
        $Template      = 'ifw_' + $Template;

        [string]$Label = $this.SanitizeMetric($this.MetricLabelValue);
        if ('' -eq $Label) {
            $Label = $this.SanitizeMetric($this.Name);
        }
        if ('' -eq $Label) {
            $Label = 'value';
        }

        return [string]::Format(
            '{0}::{1}::{2}',
            $Index,
            $Template,
            $Label
        );
    }

    <#
    .SYNOPSIS
    Collect the performance data of this node and its subtree

    .DESCRIPTION
    Returns a flat, deduplicated array containing this node's performance-data metric
    (if any) and, recursively, the metrics of every child. Returns an empty array when
    NoPerfData is set on this node, suppressing performance data for the entire
    subtree. Duplicate metric labels are skipped so each index::ifw_template::label
    appears at most once.

    .OUTPUTS
    System.Array -- All unique performance-data metric strings in the subtree.

    .EXAMPLE
    PS> $this.CollectPerfData()

    .NOTES
    Internal helper used by Compile.
    #>
    hidden [array] CollectPerfData()
    {
        if ($this.NoPerfData) {
            return @();
        }

        [array]$RawPerf = @();

        if ($this.PerfData.Count -gt 0) {
            $RawPerf += $this.PerfData;
        }

        foreach ($Child in $this.Checks) {
            $RawPerf += $Child.CollectPerfData();
        }

        [array]$Perf     = @();
        [hashtable]$Seen = @{};

        foreach ($Entry in $RawPerf) {
            [string]$Metric = [string]$Entry;
            if ('' -eq $Metric) {
                continue;
            }

            [string]$MetricKey = ($Metric -split '=', 2)[0];
            if ($Seen.ContainsKey($MetricKey)) {
                continue;
            }

            $Seen[$MetricKey] = $true;
            $Perf            += $Metric;
        }

        return $Perf;
    }

    <#
    .SYNOPSIS
    Test whether a value can be treated as a number

    .DESCRIPTION
    Returns true when the value parses as a number under the invariant culture (excluding
    booleans, which parse as False/True strings). Used to decide whether a leaf produces
    performance data.

    .PARAMETER Value
    | Name  | Type          | Description    | Default |
    |-------|---------------|----------------|---------|
    | Value | System.Object | Value to test. |         |

    .OUTPUTS
    System.Boolean -- True when the value is numeric.

    .EXAMPLE
    PS> $this.IsNumeric(95)

    .NOTES
    Internal helper used by BuildPerfData.
    #>
    hidden [bool] IsNumeric([object]$Value)
    {
        if ($null -eq $Value -or $Value -is [bool]) {
            return $false;
        }

        [double]$Parsed = 0;
        return [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed);
    }

    <#
    .SYNOPSIS
    Format a numeric value for performance data

    .DESCRIPTION
    Formats the value under the invariant culture without scientific notation so the
    decimal separator is always a dot and very small or large numbers remain plain
    decimals for Icinga 2 performance data. Falls back to the raw string when the
    value is not numeric.

    .PARAMETER Value
    | Name  | Type          | Description      | Default |
    |-------|---------------|------------------|---------|
    | Value | System.Object | Value to format. |         |

    .OUTPUTS
    System.String -- The formatted value.

    .EXAMPLE
    PS> $this.FormatNumber(95)

    .NOTES
    Internal helper used by BuildPerfData.
    #>
    hidden [string] FormatNumber([object]$Value)
    {
        [decimal]$ParsedDecimal = 0;
        if ([decimal]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedDecimal)) {
            return $ParsedDecimal.ToString('0.##########', [System.Globalization.CultureInfo]::InvariantCulture);
        }

        [double]$Parsed = 0;
        if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed)) {
            return $Parsed.ToString('0.##########', [System.Globalization.CultureInfo]::InvariantCulture);
        }

        return [string]$Value;
    }

    <#
    .SYNOPSIS
    Write the plugin output and performance data to the console

    .DESCRIPTION
    Writes the rendered output and, on a following line, the performance-data block
    ('| metric1 metric2 ...') straight to the console so an Icinga agent can parse it
    verbatim. Used only on the main thread; inside a background daemon Compile skips
    this and leaves the result in the thread-local runtime state.

    .PARAMETER Output
    | Name   | Type          | Description             | Default |
    |--------|---------------|-------------------------|---------|
    | Output | System.String | Rendered plugin output. |         |

    .PARAMETER Perf
    | Name | Type         | Description                      | Default |
    |------|--------------|----------------------------------|---------|
    | Perf | System.Array | Performance-data metric strings. |         |

    .OUTPUTS
    None -- Writes to the console.

    .EXAMPLE
    PS> $this.WriteConsoleOutput('[OK] Load: 5%', @('load=5%;80;90;0;100'))

    .NOTES
    Uses System.Console directly because Icinga parses the plugin output literally
    and it must not be reformatted by the logging subsystem.
    #>
    hidden [void] WriteConsoleOutput([string]$Output, [array]$Perf)
    {
        [string]$Line = $Output;

        if ($Perf.Count -gt 0) {
            $Line = [string]::Format('{0}{1}| {2}', $Output, "`n", ($Perf -join ' '));
        }

        [System.Console]::WriteLine($Line);
    }

    <#
    .SYNOPSIS
    Terminate a configuration chain without producing output

    .DESCRIPTION
    A void end-of-chain marker. Because every fluent setter, comparison, override and
    operator method returns the node, an unconsumed chain would otherwise leak the
    node to the pipeline. Calling Commit at the end consumes it so callers never need
    '| Out-Null' or a '[void]' cast.

    .OUTPUTS
    None -- Ends the chain.

    .EXAMPLE
    PS> $check.Warning('80').Critical('90').CheckRange().Commit()

    .NOTES
    Compile is the terminator at the root; Commit is for configuration-only chains.
    #>
    [void] Commit()
    {
    }

    <#
    .SYNOPSIS
    Compile the plugin tree into a result and return the exit code

    .DESCRIPTION
    Resolves the state of the whole tree, renders the indented output, collects the
    performance data and stores an IcingaCheckResult in the thread-local runtime
    state at $Global:IcingaForWindows.Private.Icinga.CheckResult. On the main thread
    it also writes the output to the console; inside a background daemon it writes
    nothing and leaves the result in Private for the REST API. Always returns the
    integer Icinga exit code (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN).

    .OUTPUTS
    System.Int32 -- The Icinga plugin exit code.

    .EXAMPLE
    PS> return $package.Compile()

    .NOTES
    The result (exit code, output and the performance-data array) is always written
    to Private, never to Public. Access the global via Get-GlobalRuntimeVariable so
    the correct per-runspace state is used inside worker threads.
    #>
    [int] Compile()
    {
        $GlobalVariable = Get-GlobalRuntimeVariable;

        try {
            $this.ResolveState();
            $this.PropagateVerbose($this.Verbose);

            [string]$Output                            = $this.RenderOutput();
            [array]$Perf                               = $this.CollectPerfData();
            $GlobalVariable.Private.Icinga.CheckResult = [IcingaCheckResult]::new($this.State, $Output, $Perf);

            if (-not $GlobalVariable.Protected.IsBackgroundDaemon) {
                $this.WriteConsoleOutput($Output, $Perf);
            }

            return $this.State;
        } finally {
            # Always clear the cached check command when root compilation finishes so the next check
            # executed in the same session or worker thread resolves its own Invoke-IcingaCheck* frame
            $GlobalVariable.Private.Icinga.ActiveCheckCommand = $null;
        }
    }
}

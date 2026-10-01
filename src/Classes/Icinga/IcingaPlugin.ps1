<#
.SYNOPSIS
Unified Icinga plugin node that is both a single check and a container

.DESCRIPTION
IcingaPlugin replaces the previous three-part construct (New-IcingaCheck,
New-IcingaCheckPackage, New-IcingaCheckResult) with a single class. One instance
can act as:

- a leaf check — a measured value that is evaluated against warning and critical
  thresholds and immediately put into a state (0 OK, 1 WARNING, 2 CRITICAL,
  3 UNKNOWN) the moment a comparison method is called;
- a container — a node that aggregates child plugins with a configurable operator
  (default: all children must be OK). Nesting is arbitrary; a child may itself be a
  container;
- a hybrid — a node that carries its own value AND child checks; its own evaluated
  state then participates in the aggregation as one more element. A node with only
  children (no own value evaluated) behaves exactly like the classic package.

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
an optional lock that freezes it.

Compile() aggregates the tree, renders the indented plugin output, collects the
performance data and stores an IcingaCheckResult in the thread-local runtime state
at $Global:IcingaForWindows.Private.Icinga.CheckResult. On the main thread it also
writes the output to the console; inside a background daemon
(Protected.IsBackgroundDaemon) it writes nothing to the console and leaves the
result in Private for the REST API to pick up. Compile() returns the integer exit
code either way.

.OUTPUTS
IcingaPlugin — Plugin node exposing the fluent check, override and container surface.

.EXAMPLE
PS> return [IcingaPlugin]::new('Disks').
        AddCheck([IcingaPlugin]::new('C:', 55, '%').Warning('80').Critical('90').CheckRange()).
        AddCheck([IcingaPlugin]::new('D:', 95, '%').Warning('80').Critical('90').CheckRange()).
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
#>
class IcingaPlugin
{
    [string]$Name             = '';
    [object]$Value            = $null;
    [string]$Unit             = '';
    [int]$Verbose             = 0;
    [bool]$NoPerfData         = $false;
    [bool]$IsHidden           = $false;
    [bool]$IsNotice           = $false;
    [bool]$IgnoreEmptyPackage = $false;
    [bool]$AddSummaryHeader   = $false;

    hidden [int]$State                = 0;
    hidden [bool]$Locked              = $false;
    hidden [bool]$FixedState          = $false;
    hidden [bool]$IsNoticeObject      = $false;
    hidden [bool]$Evaluated           = $false;
    hidden [string]$OutputMessage     = '';
    hidden [int]$Indention            = 0;
    hidden [IcingaPlugin]$Parent      = $null;
    hidden [array]$Checks             = @();
    hidden [array]$PerfData           = @();
    hidden [string]$Operator          = 'And';
    hidden [int]$OperatorMin          = -1;
    hidden [int]$OperatorMax          = -1;
    hidden [string]$WarningThreshold  = '';
    hidden [string]$CriticalThreshold = '';
    hidden [string]$ResolvedWarning   = '';
    hidden [string]$ResolvedCritical  = '';
    hidden [string]$MinimumValue      = '';
    hidden [string]$MaximumValue      = '';
    hidden [object]$BaseValueSetting  = $null;
    hidden [string]$MetricIndexValue  = '';
    hidden [string]$MetricNameValue   = '';
    hidden [string]$MetricLabelValue  = '';
    hidden [string]$CheckCommand      = '';

    static hidden [hashtable]$StateText = @{
        0 = '[OK]';
        1 = '[WARNING]';
        2 = '[CRITICAL]';
        3 = '[UNKNOWN]';
    };

    <#
    .SYNOPSIS
    Create a plugin node with a name only

    .DESCRIPTION
    Creates a node without a measured value. Typically used as a container that
    aggregates child checks added with AddCheck.

    .PARAMETER Name
    | Name | Type          | Description                          | Default |
    |------|---------------|--------------------------------------|---------|
    | Name | System.String | Display name of the plugin node.     |         |

    .OUTPUTS
    IcingaPlugin — Configured plugin node.

    .EXAMPLE
    PS> [IcingaPlugin]::new('Disks')

    .NOTES
    Delegates to the shared Initialize helper.
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
    | Name | Type          | Description                       | Default |
    |------|---------------|-----------------------------------|---------|
    | Name | System.String | Display name of the check.        |         |

    .PARAMETER Value
    | Name  | Type          | Description                                   | Default |
    |-------|---------------|-----------------------------------------------|---------|
    | Value | System.Object | Measured value; number or '<number><unit>'.   |         |

    .OUTPUTS
    IcingaPlugin — Configured plugin node.

    .EXAMPLE
    PS> [IcingaPlugin]::new('Load', 95)

    .NOTES
    Delegates to the shared Initialize helper.
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
    | Name | Type          | Description                       | Default |
    |------|---------------|-----------------------------------|---------|
    | Name | System.String | Display name of the check.        |         |

    .PARAMETER Value
    | Name  | Type          | Description                                   | Default |
    |-------|---------------|-----------------------------------------------|---------|
    | Value | System.Object | Measured value; number or '<number><unit>'.   |         |

    .PARAMETER Unit
    | Name | Type          | Description                        | Default |
    |------|---------------|------------------------------------|---------|
    | Unit | System.String | Icinga unit appended to perfdata.  |         |

    .OUTPUTS
    IcingaPlugin — Configured plugin node.

    .EXAMPLE
    PS> [IcingaPlugin]::new('Load', 95, '%')

    .NOTES
    Delegates to the shared Initialize helper.
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
    | Name | Type          | Description                    | Default |
    |------|---------------|--------------------------------|---------|
    | Name | System.String | Display name of the node.      |         |

    .PARAMETER Value
    | Name  | Type          | Description                   | Default |
    |-------|---------------|-------------------------------|---------|
    | Value | System.Object | Measured value or $null.      |         |

    .PARAMETER Unit
    | Name | Type          | Description        | Default |
    |------|---------------|--------------------|---------|
    | Unit | System.String | Icinga unit.       |         |

    .OUTPUTS
    None — Updates instance state.

    .EXAMPLE
    PS> $this.Initialize('Load', 95, '%')

    .NOTES
    Internal helper shared by all constructors.
    #>
    hidden [void] Initialize([string]$Name, [object]$Value, [string]$Unit)
    {
        $this.Name         = $Name;
        $this.Value        = $Value;
        $this.Unit         = $Unit;
        $this.CheckCommand = $this.DetectCheckCommand();
    }

    <#
    .SYNOPSIS
    Set the warning threshold and return the node for chaining

    .DESCRIPTION
    Stores the warning threshold string verbatim. The threshold is not evaluated
    until a comparison method (CheckRange, CheckGreater, ...) is called.

    .PARAMETER Warning
    | Name    | Type          | Description                              | Default |
    |---------|---------------|------------------------------------------|---------|
    | Warning | System.String | Warning threshold string ('' = unset).   |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('80')

    .NOTES
    Fluent setter; combine with Critical and a comparison method.
    #>
    [IcingaPlugin] Warning([string]$Warning)
    {
        $this.WarningThreshold = $Warning;
        return $this;
    }

    <#
    .SYNOPSIS
    Set the critical threshold and return the node for chaining

    .DESCRIPTION
    Stores the critical threshold string verbatim. The threshold is not evaluated
    until a comparison method is called.

    .PARAMETER Critical
    | Name     | Type          | Description                             | Default |
    |----------|---------------|-----------------------------------------|---------|
    | Critical | System.String | Critical threshold string ('' = unset). |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Critical('90')

    .NOTES
    Fluent setter; combine with Warning and a comparison method.
    #>
    [IcingaPlugin] Critical([string]$Critical)
    {
        $this.CriticalThreshold = $Critical;
        return $this;
    }

    <#
    .SYNOPSIS
    Set the performance-data minimum and return the node for chaining

    .DESCRIPTION
    Stores the minimum value that is emitted as the 'min' field of the performance
    data. Does not influence the threshold evaluation.

    .PARAMETER Minimum
    | Name    | Type          | Description                         | Default |
    |---------|---------------|-------------------------------------|---------|
    | Minimum | System.String | Perfdata minimum ('' = unset).      |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Minimum('0')

    .NOTES
    Fluent setter for the perfdata min field.
    #>
    [IcingaPlugin] Minimum([string]$Minimum)
    {
        $this.MinimumValue = $Minimum;
        return $this;
    }

    <#
    .SYNOPSIS
    Set the performance-data maximum and return the node for chaining

    .DESCRIPTION
    Stores the maximum value that is emitted as the 'max' field of the performance
    data. Does not influence the threshold evaluation.

    .PARAMETER Maximum
    | Name    | Type          | Description                         | Default |
    |---------|---------------|-------------------------------------|---------|
    | Maximum | System.String | Perfdata maximum ('' = unset).      |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Maximum('100')

    .NOTES
    Fluent setter for the perfdata max field.
    #>
    [IcingaPlugin] Maximum([string]$Maximum)
    {
        $this.MaximumValue = $Maximum;
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
    | Name      | Type          | Description                                    | Default |
    |-----------|---------------|------------------------------------------------|---------|
    | BaseValue | System.Object | Base/maximum value; number or unit string.     |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.BaseValue('1TB').Warning('80%').Critical('90%').CheckMax()

    .NOTES
    Fluent setter; required for percent thresholds and CheckMax.
    #>
    [IcingaPlugin] BaseValue([object]$BaseValue)
    {
        $this.BaseValueSetting = $BaseValue;
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
    | Name  | Type          | Description                                | Default |
    |-------|---------------|--------------------------------------------|---------|
    | Index | System.String | Metric index / instance identifier.        |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    IcingaPlugin — The same node, for chaining.

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
    IcingaPlugin — The same node, for chaining.

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
    Evaluate the value against the thresholds using the Icinga range grammar

    .DESCRIPTION
    Builds an IcingaThresholds pair from the configured warning, critical and base
    values, compares the node's value with the full Icinga/Nagios range grammar and
    immediately puts the node into the resulting state (escalate-only). Performance
    data is (re)built from the current value and thresholds.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> [IcingaPlugin]::new('Load', 95, '%').Warning('80').Critical('90').CheckRange()

    .NOTES
    Delegates to IcingaThresholds.CheckRange.
    #>
    [IcingaPlugin] CheckRange()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckRange($this.AttachByteUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a greater-than comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    greater-than operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('80').Critical('90').CheckGreater()

    .NOTES
    Delegates to IcingaThresholds.CheckGreater.
    #>
    [IcingaPlugin] CheckGreater()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckGreater($this.AttachByteUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a greater-than-or-equal comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    greater-than-or-equal operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('80').Critical('90').CheckGreaterEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckGreaterEqual.
    #>
    [IcingaPlugin] CheckGreaterEqual()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckGreaterEqual($this.AttachByteUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a lower-than comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    lower-than operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('20').Critical('10').CheckLower()

    .NOTES
    Delegates to IcingaThresholds.CheckLower.
    #>
    [IcingaPlugin] CheckLower()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckLower($this.AttachByteUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the value with a lower-than-or-equal comparison

    .DESCRIPTION
    Compares the node's value against the warning and critical thresholds with a
    lower-than-or-equal operator and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('20').Critical('10').CheckLowerEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckLowerEqual.
    #>
    [IcingaPlugin] CheckLowerEqual()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckLowerEqual($this.AttachByteUnit($this.Value)));
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
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.BaseValue('1TB').Warning('80%').Critical('90%').CheckMax()

    .NOTES
    Delegates to IcingaThresholds.CheckMax; without a base value the result is UNKNOWN.
    #>
    [IcingaPlugin] CheckMax()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckMax($this.AttachByteUnit($this.Value)));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a regular-expression match

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds as regular
    expressions and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('^warn').Critical('^err').CheckMatch()

    .NOTES
    Delegates to IcingaThresholds.CheckMatch.
    #>
    [IcingaPlugin] CheckMatch()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckMatch($this.Value));
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
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('^ok').Critical('^healthy').CheckNotMatch()

    .NOTES
    Delegates to IcingaThresholds.CheckNotMatch.
    #>
    [IcingaPlugin] CheckNotMatch()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckNotMatch($this.Value));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a wildcard 'like' comparison

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds as PowerShell
    wildcard patterns and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('*warn*').Critical('*error*').CheckLike()

    .NOTES
    Delegates to IcingaThresholds.CheckLike.
    #>
    [IcingaPlugin] CheckLike()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckLike($this.Value));
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
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('*ok*').Critical('*healthy*').CheckNotLike()

    .NOTES
    Delegates to IcingaThresholds.CheckNotLike.
    #>
    [IcingaPlugin] CheckNotLike()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckNotLike($this.Value));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with an equality comparison

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds with a
    case-insensitive string equality test and puts the node into the resulting state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('degraded').Critical('offline').CheckEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckEqual.
    #>
    [IcingaPlugin] CheckEqual()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckEqual($this.Value));
        return $this;
    }

    <#
    .SYNOPSIS
    Evaluate the string value with a negated equality comparison

    .DESCRIPTION
    Tests the node's value against the warning and critical thresholds with a
    case-insensitive string inequality test and puts the node into the resulting
    state.

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.Warning('online').Critical('online').CheckNotEqual()

    .NOTES
    Delegates to IcingaThresholds.CheckNotEqual.
    #>
    [IcingaPlugin] CheckNotEqual()
    {
        $this.ApplyThresholdResult($this.NewThresholds().CheckNotEqual($this.Value));
        return $this;
    }

    <#
    .SYNOPSIS
    Build an IcingaThresholds pair from the configured thresholds

    .DESCRIPTION
    Creates an IcingaThresholds object from the stored warning and critical strings,
    passing the base value as well when one was set. A plain numeric base value of a
    byte node carries the 'B' unit, so percent thresholds resolve and render in
    bytes. The return type is object because IcingaThresholds is parsed after
    IcingaPlugin during the build and may therefore only be referenced from method
    bodies.

    .OUTPUTS
    System.Object — An IcingaThresholds instance.

    .EXAMPLE
    PS> $this.NewThresholds()

    .NOTES
    Internal helper used by every comparison method.
    #>
    hidden [object] NewThresholds()
    {
        if ($null -ne $this.BaseValueSetting -and '' -ne [string]$this.BaseValueSetting) {
            return [IcingaThresholds]::new($this.WarningThreshold, $this.CriticalThreshold, [string]$this.AttachByteUnit($this.BaseValueSetting));
        }

        return [IcingaThresholds]::new($this.WarningThreshold, $this.CriticalThreshold);
    }

    <#
    .SYNOPSIS
    Test whether the node measures plain bytes

    .DESCRIPTION
    Returns true when the node's unit is the byte base unit 'B'. Such a node hands
    its value to the threshold engine as a byte quantity, so it compares exactly
    against size thresholds ('400GB') and percent thresholds of a base value, and its
    output message shows human-readable sizes. Plain-number thresholds keep meaning
    bytes, which matches both the threshold engine and the Icinga perfdata unit.
    Every other unit ('%', 'GiB', time units, none) returns false and keeps the
    plain display-unit behaviour.

    .OUTPUTS
    System.Boolean — True when the unit is 'B'.

    .EXAMPLE
    PS> $this.HasByteUnit()

    .NOTES
    Internal helper. Larger data units are excluded on purpose: a plain threshold
    such as '80' would resolve to 80 bytes instead of 80 of the node's unit.
    #>
    hidden [bool] HasByteUnit()
    {
        return ($this.Unit -eq 'B');
    }

    <#
    .SYNOPSIS
    Append the byte unit to a plain numeric value

    .DESCRIPTION
    Turns a plain number into a '<number>B' string (for example 442692000000
    becomes '442692000000B') when the node measures bytes, so the threshold engine
    resolves the value as a byte quantity. The number is written in fixed-point
    notation under the invariant culture so large byte counts never use an
    exponent. Any other value, and every value of a node that does not measure
    bytes, is returned unchanged.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Measured value or base value to adjust.  |         |

    .OUTPUTS
    System.Object — The value with the unit attached, or the unchanged value.

    .EXAMPLE
    PS> $this.AttachByteUnit(442692000000)

    .NOTES
    Internal helper used by the numeric comparison methods and NewThresholds.
    #>
    hidden [object] AttachByteUnit([object]$Value)
    {
        if ($null -eq $Value -or -not $this.HasByteUnit()) {
            return $Value;
        }

        [double]$Parsed = 0;
        if (-not [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed)) {
            return $Value;
        }

        return ($Parsed.ToString('0.##########', [System.Globalization.CultureInfo]::InvariantCulture) + $this.Unit);
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
    | Name   | Type          | Description                                | Default |
    |--------|---------------|--------------------------------------------|---------|
    | Result | System.Object | An IcingaThresholdResult from a comparison. |        |

    .OUTPUTS
    None — Updates instance state.

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
            if ($this.HasByteUnit()) {
                $this.OutputMessage = $this.HumanizeByteValues([string]$Result.Output);
            } else {
                $this.OutputMessage = $this.ApplyDisplayUnit([string]$Result.Output);
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
    Render plain byte figures of an output message as human-readable sizes

    .DESCRIPTION
    Replaces every '<number>B' figure in a threshold output message with its
    best-fitting binary size (for example '442692000000B' becomes '412.29GiB'). The
    threshold engine renders the value and the percent thresholds of a byte node in
    plain bytes; figures in any other unit (such as a '400GB' threshold) and
    percentages are left untouched.

    .PARAMETER Message
    | Name    | Type          | Description                    | Default |
    |---------|---------------|--------------------------------|---------|
    | Message | System.String | The threshold output message.  |         |

    .OUTPUTS
    System.String — The message with byte figures converted to their best-fit unit.

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

        foreach ($Match in [regex]::Matches($Message, '(?<![\w.])(\d+(?:\.\d+)?)B\b')) {
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
    Append the display unit to the numeric figures of an output message

    .DESCRIPTION
    Suffixes the node's unit onto every number in a threshold output message so a
    plain display unit such as '%' shows on the value and thresholds (for example
    '95 is greater than threshold 90' becomes '95% is greater than threshold 90%').
    IcingaThresholds treats '%' only as a percent-of-base threshold, not as a value
    suffix, so this covers the common case of a dimensionless display unit. No change
    is made when the node has no unit. Intended for the numeric comparison methods.

    .PARAMETER Message
    | Name    | Type          | Description                    | Default |
    |---------|---------------|--------------------------------|---------|
    | Message | System.String | The threshold output message.  |         |

    .OUTPUTS
    System.String — The message with the unit appended to each number.

    .EXAMPLE
    PS> $this.ApplyDisplayUnit('95 is greater than threshold 90')

    .NOTES
    Internal helper used by ApplyThresholdResult. The unit's '$' characters are
    escaped so they are not treated as regex replacement references.
    #>
    hidden [string] ApplyDisplayUnit([string]$Message)
    {
        if ('' -eq $this.Unit) {
            return $Message;
        }

        [string]$Replacement = '$0' + ($this.Unit -replace '\$', '$$$$');
        return [regex]::Replace($Message, '-?\d+(?:\.\d+)?', $Replacement);
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
    None — Updates instance state.

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
    Central override that forces a specific node state

    .DESCRIPTION
    The single, unified way to override a node's state. Unless the node is locked it
    marks the state as fixed, sets the requested state (this override may lower the
    state, unlike EscalateState) and replaces the output message when one is given.
    When Lock is true the node is locked so no later evaluation or aggregation can
    change it. Returns the node so overrides chain.

    .PARAMETER State
    | Name  | Type         | Description                                     | Default |
    |-------|--------------|-------------------------------------------------|---------|
    | State | System.Int32 | Forced state (0 OK, 1 WARN, 2 CRIT, 3 UNKN).    |         |

    .PARAMETER Message
    | Name    | Type          | Description                                      | Default |
    |---------|---------------|--------------------------------------------------|---------|
    | Message | System.String | Output message; '' keeps the existing message.   |         |

    .PARAMETER Lock
    | Name | Type           | Description                                     | Default |
    |------|----------------|-------------------------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state against later changes. |     |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.SetState(2, 'Service is stopped', $true)

    .NOTES
    All SetOk/SetWarning/SetCritical/SetUnknown wrappers funnel through this method.
    #>
    hidden [IcingaPlugin] SetState([int]$State, [string]$Message, [bool]$Lock)
    {
        if (-not $this.Locked) {
            $this.FixedState = $true;
            $this.State      = $State;
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
    Force the node into the OK state

    .DESCRIPTION
    Overrides the node state to OK with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                        | Default |
    |---------|---------------|------------------------------------|---------|
    | Message | System.String | Output message for the OK state.   |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    | Name    | Type          | Description                        | Default |
    |---------|---------------|------------------------------------|---------|
    | Message | System.String | Output message for the OK state.   |         |

    .PARAMETER Lock
    | Name | Type           | Description                         | Default |
    |------|----------------|-------------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state.        |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    Force the node into the WARNING state

    .DESCRIPTION
    Overrides the node state to WARNING with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message for the WARNING state.  |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message for the WARNING state.  |         |

    .PARAMETER Lock
    | Name | Type           | Description                         | Default |
    |------|----------------|-------------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state.        |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    Force the node into the CRITICAL state

    .DESCRIPTION
    Overrides the node state to CRITICAL with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                             | Default |
    |---------|---------------|-----------------------------------------|---------|
    | Message | System.String | Output message for the CRITICAL state.  |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    | Name    | Type          | Description                             | Default |
    |---------|---------------|-----------------------------------------|---------|
    | Message | System.String | Output message for the CRITICAL state.  |         |

    .PARAMETER Lock
    | Name | Type           | Description                         | Default |
    |------|----------------|-------------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state.        |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    Force the node into the UNKNOWN state

    .DESCRIPTION
    Overrides the node state to UNKNOWN with the given message.

    .PARAMETER Message
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message for the UNKNOWN state.  |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    | Name    | Type          | Description                            | Default |
    |---------|---------------|----------------------------------------|---------|
    | Message | System.String | Output message for the UNKNOWN state.  |         |

    .PARAMETER Lock
    | Name | Type           | Description                         | Default |
    |------|----------------|-------------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the state.        |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    Mark the node as an informational notice

    .DESCRIPTION
    Turns the node into an informational object that renders with the [INFO] prefix
    and keeps the OK state, replacing the output message when one is given.

    .PARAMETER Message
    | Name    | Type          | Description                       | Default |
    |---------|---------------|-----------------------------------|---------|
    | Message | System.String | Informational message to display. |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    | Name | Type           | Description                    | Default |
    |------|----------------|--------------------------------|---------|
    | Lock | System.Boolean | When true, freeze the node.    |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

    .EXAMPLE
    PS> $check.SetNotice('Collected 5 samples', $true)

    .NOTES
    Notices never raise the plugin state; they are purely informational.
    #>
    [IcingaPlugin] SetNotice([string]$Message, [bool]$Lock)
    {
        if (-not $this.Locked) {
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
    IcingaPlugin — The same node, for chaining.

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
    IcingaPlugin — The same node, for chaining.

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
    IcingaPlugin — The same node, for chaining.

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
    IcingaPlugin — The same node, for chaining.

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
    | Name  | Type         | Description                              | Default |
    |-------|--------------|------------------------------------------|---------|
    | Count | System.Int32 | Minimum number of children that must be OK. |     |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    | Name  | Type         | Description                                 | Default |
    |-------|--------------|---------------------------------------------|---------|
    | Count | System.Int32 | Maximum number of children that may be OK.  |         |

    .OUTPUTS
    IcingaPlugin — The same node, for chaining.

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
    | Name  | Type        | Description                     | Default |
    |-------|-------------|---------------------------------|---------|
    | Check | IcingaPlugin | Child plugin to add.           |         |

    .OUTPUTS
    IcingaPlugin — This container, for chaining.

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
    | Name   | Type         | Description                   | Default |
    |--------|--------------|-------------------------------|---------|
    | Checks | System.Array | Child plugins to add.         |         |

    .OUTPUTS
    IcingaPlugin — This container, for chaining.

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
    Recompute the indentation of all descendants

    .DESCRIPTION
    Sets every child's indentation to one level below this node and propagates the
    verbosity, then recurses. Needed when a subtree that already had children is
    attached to a new parent.

    .OUTPUTS
    None — Updates the children's state.

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
    None — Updates this node and its descendants.

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
    For a leaf, returns the state that threshold evaluation or an override already
    set. For a container, recursively resolves every child, counts OK versus not-OK
    children (a hybrid node's own evaluated state counts as one more element),
    determines the worst child state and escalates this node to it according to the
    configured operator (And/Or/None and the Minimum/Maximum counts).

    .OUTPUTS
    System.Int32 — The resolved state of this node.

    .EXAMPLE
    PS> $this.ResolveState()

    .NOTES
    Called by Compile before rendering; escalate-only, so overrides survive.
    #>
    hidden [int] ResolveState()
    {
        if ($this.Checks.Count -eq 0) {
            return $this.State;
        }

        [int]$Worst   = 0;
        [int]$OkCount = 0;
        [int]$NotOk   = 0;

        foreach ($Child in $this.Checks) {
            [int]$ChildState = $Child.ResolveState();

            if ($Child.IsHidden) {
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
        # may be combined); otherwise the And/Or/None operator decides.
        if ($this.OperatorMin -ne -1 -or $this.OperatorMax -ne -1) {
            if ($this.OperatorMin -ne -1 -and $OkCount -lt $this.OperatorMin) {
                $this.EscalateState($Worst);
            }

            if ($this.OperatorMax -ne -1 -and $OkCount -gt $this.OperatorMax) {
                $this.EscalateState($Worst);
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
                    if ($OkCount -eq 0) {
                        $this.EscalateState($Worst);
                    }
                    break;
                }
                'None' {
                    if ($OkCount -ne 0) {
                        $this.EscalateState($Worst);
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
    Returns true when at least one child is not OK, or when a hybrid node's own
    evaluated state is not OK. Used to decide whether a container is shown at low
    verbosity levels.

    .OUTPUTS
    System.Boolean — True when a not-OK child (or own state) exists.

    .EXAMPLE
    PS> $this.HasNotOkChecks()

    .NOTES
    Requires ResolveState to have run so child states are final.
    #>
    hidden [bool] HasNotOkChecks()
    {
        foreach ($Child in $this.Checks) {
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
    System.Boolean — True when the node should be part of the output.

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

        if ($this.Checks.Count -ne 0) {
            return $this.HasNotOkChecks();
        }

        if ($this.Verbose -eq 1 -and $null -ne $this.Parent -and $this.Parent.Checks.Count -ne 0) {
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
    | Name      | Type         | Description                    | Default |
    |-----------|--------------|--------------------------------|---------|
    | Indention | System.Int32 | Zero-based tree depth.         |         |

    .OUTPUTS
    System.String — The indentation prefix.

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
    Returns the container summary line when the node has children, otherwise the
    leaf line.

    .OUTPUTS
    System.String — The node's own one-line output (without indentation).

    .EXAMPLE
    PS> $this.BuildLine()

    .NOTES
    Internal helper used by RenderOutput.
    #>
    hidden [string] BuildLine()
    {
        if ($this.Checks.Count -ne 0) {
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
    System.String — The leaf output line.

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
    A notice package renders with the [INFO] prefix.

    .OUTPUTS
    System.String — The container output line.

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
    Recursively gathers all descendant nodes that are leaf checks (nodes without
    children), skipping container nodes and hidden nodes. Used by the summary header
    so the root line reflects the state of every actual check regardless of nesting
    depth.

    .OUTPUTS
    System.Array — The leaf IcingaPlugin nodes in the subtree.

    .EXAMPLE
    PS> $this.CollectLeafChecks()

    .NOTES
    Internal helper used by BuildContainerLine.
    #>
    hidden [array] CollectLeafChecks()
    {
        [array]$Leaves = @();

        foreach ($Child in $this.Checks) {
            if ($Child.IsHidden) {
                continue;
            }

            if ($Child.Checks.Count -eq 0) {
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
    System.String — The operator description, for example ' (All must be [OK])'.

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
    System.String — The multi-line, indented output.

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
        $Lines += ($this.IndentPrefix($this.Indention) + $this.BuildLine());

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
    None — Updates this node's performance data.

    .EXAMPLE
    PS> $this.BuildPerfData()

    .NOTES
    Called after each comparison; only numeric values yield perfdata.
    #>
    hidden [void] BuildPerfData()
    {
        $this.PerfData = @();

        if ($this.NoPerfData) {
            return;
        }

        if (-not $this.IsNumeric($this.Value)) {
            return;
        }

        [string]$Warning  = $this.WarningThreshold;
        [string]$Critical = $this.CriticalThreshold;

        if ('' -ne $this.ResolvedWarning) {
            $Warning = $this.ResolvedWarning;
        }

        if ('' -ne $this.ResolvedCritical) {
            $Critical = $this.ResolvedCritical;
        }

        [string]$Metric = [string]::Format(
            '{0}={1}{2};{3};{4};{5};{6}',
            $this.BuildPerfDataLabel(),
            $this.FormatNumber($this.Value),
            $this.Unit,
            $Warning,
            $Critical,
            $this.MinimumValue,
            $this.MaximumValue
        );

        $this.PerfData = @($Metric);
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
    System.String — The check command name, or '' when none was found.

    .EXAMPLE
    PS> $this.DetectCheckCommand()

    .NOTES
    Internal helper called once at construction.
    #>
    hidden [string] DetectCheckCommand()
    {
        foreach ($Frame in (Get-PSCallStack)) {
            if (([string]$Frame.Command).ToLower() -like 'invoke-icingacheck*') {
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
    | Name  | Type          | Description                 | Default |
    |-------|---------------|-----------------------------|---------|
    | Value | System.String | The raw metric segment.     |         |

    .OUTPUTS
    System.String — The sanitized, lower-cased segment.

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
    MetricName; the label defaults to the node's Name and can be overridden with
    MetricLabel. Every segment is sanitized and lower-cased.

    .OUTPUTS
    System.String — The structured performance-data label.

    .EXAMPLE
    PS> $this.BuildPerfDataLabel()

    .NOTES
    Internal helper used by BuildPerfData. Example: 'c::ifw_partitionspace::free'.
    #>
    hidden [string] BuildPerfDataLabel()
    {
        [string]$Index = $this.MetricIndexValue;
        if ('' -eq $Index) {
            $Index = 'default';
        }

        [string]$Template = $this.MetricNameValue;
        if ('' -eq $Template) {
            $Template = ([string]$this.CheckCommand) -replace '(?i)^Invoke-IcingaCheck', '';
        }
        if ('' -eq $Template) {
            $Template = 'check';
        }
        if ($Template.ToLower() -notlike 'ifw_*') {
            $Template = 'ifw_' + $Template;
        }

        [string]$Label = $this.MetricLabelValue;
        if ('' -eq $Label) {
            $Label = $this.Name;
        }

        return [string]::Format(
            '{0}::{1}::{2}',
            $this.SanitizeMetric($Index),
            $this.SanitizeMetric($Template),
            $this.SanitizeMetric($Label)
        );
    }

    <#
    .SYNOPSIS
    Collect the performance data of this node and its subtree

    .DESCRIPTION
    Returns a flat array containing this node's performance-data metric (if any) and,
    recursively, the metrics of every child.

    .OUTPUTS
    System.Array — All performance-data metric strings in the subtree.

    .EXAMPLE
    PS> $this.CollectPerfData()

    .NOTES
    Internal helper used by Compile.
    #>
    hidden [array] CollectPerfData()
    {
        [array]$Perf = @();

        if ($this.PerfData.Count -gt 0) {
            $Perf += $this.PerfData;
        }

        foreach ($Child in $this.Checks) {
            $Perf += $Child.CollectPerfData();
        }

        return $Perf;
    }

    <#
    .SYNOPSIS
    Test whether a value can be treated as a number

    .DESCRIPTION
    Returns true when the value parses as a number under the invariant culture. Used
    to decide whether a leaf produces performance data.

    .PARAMETER Value
    | Name  | Type          | Description               | Default |
    |-------|---------------|---------------------------|---------|
    | Value | System.Object | Value to test.            |         |

    .OUTPUTS
    System.Boolean — True when the value is numeric.

    .EXAMPLE
    PS> $this.IsNumeric(95)

    .NOTES
    Internal helper used by BuildPerfData.
    #>
    hidden [bool] IsNumeric([object]$Value)
    {
        if ($null -eq $Value) {
            return $false;
        }

        [double]$Parsed = 0;
        return [double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed);
    }

    <#
    .SYNOPSIS
    Format a numeric value for performance data

    .DESCRIPTION
    Formats the value under the invariant culture so the decimal separator is always
    a dot. Falls back to the raw string when the value is not numeric.

    .PARAMETER Value
    | Name  | Type          | Description               | Default |
    |-------|---------------|---------------------------|---------|
    | Value | System.Object | Value to format.          |         |

    .OUTPUTS
    System.String — The formatted value.

    .EXAMPLE
    PS> $this.FormatNumber(95)

    .NOTES
    Internal helper used by BuildPerfData.
    #>
    hidden [string] FormatNumber([object]$Value)
    {
        [double]$Parsed = 0;
        if ([double]::TryParse([string]$Value, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed)) {
            return $Parsed.ToString([System.Globalization.CultureInfo]::InvariantCulture);
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
    | Name   | Type          | Description                  | Default |
    |--------|---------------|------------------------------|---------|
    | Output | System.String | Rendered plugin output.      |         |

    .PARAMETER Perf
    | Name | Type         | Description                          | Default |
    |------|--------------|--------------------------------------|---------|
    | Perf | System.Array | Performance-data metric strings.     |         |

    .OUTPUTS
    None — Writes to the console.

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
    Ensure the thread-local check-result slot exists

    .DESCRIPTION
    Guarantees that the supplied Private runtime object has an Icinga sub-object with
    a CheckResult property before Compile writes to it. New-ModuleBaseEnvironment
    creates this slot for fresh sessions and worker runspaces, but a session that was
    already warm when the module was updated keeps an older Private object without it;
    this makes Compile self-sufficient in that case too, adding the missing members
    on demand.

    .PARAMETER Private
    | Name    | Type          | Description                                   | Default |
    |---------|---------------|-----------------------------------------------|---------|
    | Private | System.Object | The Private runtime object to normalise.      |         |

    .OUTPUTS
    None — Adds the Icinga.CheckResult slot when it is missing.

    .EXAMPLE
    PS> $this.EnsureResultSlot((Get-GlobalRuntimeVariable).Private)

    .NOTES
    Internal helper used by Compile.
    #>
    hidden [void] EnsureResultSlot([object]$Private)
    {
        if ($null -eq $Private.PSObject.Properties['Icinga'] -or $null -eq $Private.Icinga) {
            $Private | Add-Member -MemberType NoteProperty -Name 'Icinga' -Value ([PSCustomObject]@{ 'CheckResult' = $null }) -Force;
            return;
        }

        if ($null -eq $Private.Icinga.PSObject.Properties['CheckResult']) {
            $Private.Icinga | Add-Member -MemberType NoteProperty -Name 'CheckResult' -Value $null;
        }
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
    None — Ends the chain.

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
    System.Int32 — The Icinga plugin exit code.

    .EXAMPLE
    PS> return $package.Compile()

    .NOTES
    The result (exit code, output and the performance-data array) is always written
    to Private, never to Public. Access the global via Get-GlobalRuntimeVariable so
    the correct per-runspace state is used inside worker threads.
    #>
    [int] Compile()
    {
        $this.ResolveState();
        $this.PropagateVerbose($this.Verbose);

        [string]$Output = $this.RenderOutput();
        [array]$Perf    = $this.CollectPerfData();

        $GlobalVariable = Get-GlobalRuntimeVariable;
        $this.EnsureResultSlot($GlobalVariable.Private);
        $GlobalVariable.Private.Icinga.CheckResult = [IcingaCheckResult]::new($this.State, $Output, $Perf);

        if (-not $GlobalVariable.Protected.IsBackgroundDaemon) {
            $this.WriteConsoleOutput($Output, $Perf);
        }

        return $this.State;
    }
}

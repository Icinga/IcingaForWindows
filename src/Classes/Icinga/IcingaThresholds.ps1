<#
.SYNOPSIS
Value object representing a single parsed Icinga threshold range

.DESCRIPTION
IcingaThresholdRange parses one threshold string written in the standard
Icinga/Nagios range grammar and evaluates whether a measured value falls into
its alert range. It is used internally by IcingaThresholds to back the warning
and the critical range of a threshold pair.

The supported grammar is "[@][start:]end". A bare value 'X' is the range 0..X;
'X:' is X..infinity; '~:X' is -infinity..X; 'X:Y' is X..Y; a leading '@' inverts
the range so that a value inside the bounds raises the alert instead of a value
outside them. Each bound may be a plain number (interpreted as the smallest/base
unit, e.g. bytes), a value carrying a unit suffix (10GB, 100MB, 500ms) which is
normalized to its base unit through the IcingaUnit class, or a percentage (90%)
which is resolved against a supplied base value. A null or empty threshold is a
valid "unset" range that never raises an alert.

The original threshold string is preserved verbatim so it round-trips 1:1 via
ToString. Like IcingaUnit, the class never throws on invalid input; it records a
failure through Success and a semantic ReturnCode instead. All bound arithmetic
uses [decimal] for precision and open ends are stored as [double] infinities.

.OUTPUTS
IcingaThresholdRange — Value object describing the parsed range.

.EXAMPLE
PS> [IcingaThresholdRange]::new('10:20', 0, $false)

Parses the inclusive range 10..20; values below 10 or above 20 are in alert.

.EXAMPLE
PS> [IcingaThresholdRange]::new('90%', 1000, $true)

Resolves 90% of the base value 1000 into the upper bound 900.

.NOTES
Self-contained value object. Does not modify global state or access external
services. Reuses the IcingaUnit class for unit-carrying bounds. Safe to construct
in multi-threaded runspaces.
#>
class IcingaThresholdRange
{
    hidden [string]$Threshold    = '';
    hidden [bool]$IsSet          = $false;
    hidden [bool]$Inverted       = $false;
    hidden [double]$Start        = 0;
    hidden [double]$End          = 0;
    hidden [string]$StartUnit    = '';
    hidden [string]$EndUnit      = '';
    hidden [string]$StartPercent = '';
    hidden [string]$EndPercent   = '';
    hidden [string]$Family       = '';
    hidden [bool]$Success        = $false;
    hidden [string]$ReturnCode   = '';
    hidden [double]$BaseValue    = 0;
    hidden [bool]$HasBaseValue   = $false;

    static hidden [regex]$PercentRegex = [regex]::new('^\s*(-?\d+(?:[.,]\d+)?)\s*%\s*$', [System.Text.RegularExpressions.RegexOptions]::Compiled);
    static hidden [regex]$NumberRegex  = [regex]::new('^\s*(-?\d+(?:[.,]\d+)?)\s*$', [System.Text.RegularExpressions.RegexOptions]::Compiled);

    <#
    .SYNOPSIS
    Parse a single threshold range string into an evaluatable range

    .DESCRIPTION
    Parses the threshold grammar, resolving the optional inversion marker, the
    lower and upper bounds and any unit or percent notation, and validates that
    the lower bound does not exceed the upper bound. On invalid input the range
    records a failure via Success and ReturnCode instead of throwing.

    .PARAMETER Threshold
    | Name      | Type          | Description                                                | Default |
    |-----------|---------------|------------------------------------------------------------|---------|
    | Threshold | System.String | Threshold range string, e.g. '10', '10:', '~:10', '@10:20'.|         |

    .PARAMETER BaseValue
    | Name      | Type           | Description                                             | Default |
    |-----------|----------------|---------------------------------------------------------|---------|
    | BaseValue | System.Double  | Base value that percent bounds are resolved against.    |         |

    .PARAMETER HasBaseValue
    | Name         | Type           | Description                                        | Default |
    |--------------|----------------|----------------------------------------------------|---------|
    | HasBaseValue | System.Boolean | Whether a base value was supplied for percent math.|         |

    .OUTPUTS
    IcingaThresholdRange — Configured range instance with Success and ReturnCode.

    .EXAMPLE
    PS> [IcingaThresholdRange]::new('~:10', 0, $false)

    .NOTES
    Does not throw on invalid input; inspect the Success property and ReturnCode.
    #>
    IcingaThresholdRange([string]$Threshold, [double]$BaseValue, [bool]$HasBaseValue)
    {
        $this.BaseValue    = $BaseValue;
        $this.HasBaseValue = $HasBaseValue;

        # A null or empty threshold is a valid "unset" range that never alerts.
        if ([string]::IsNullOrWhiteSpace($Threshold)) {
            $this.IsSet      = $false;
            $this.Success    = $true;
            $this.ReturnCode = 'IcingaThresholdParsed';
            return;
        }

        $this.Threshold = $Threshold;
        $this.IsSet     = $true;

        [string]$Body = $Threshold.Trim();

        # A leading '@' inverts the range: alert when the value is inside the
        # bounds instead of outside them.
        if ($Body.StartsWith('@')) {
            $this.Inverted = $true;
            $Body          = $Body.Substring(1);
        }

        [double]$LowerBound   = 0;
        [double]$UpperBound   = 0;
        [string]$LowerFamily  = '';
        [string]$LowerUnit    = '';
        [string]$LowerPercent = '';
        [string]$UpperFamily  = '';
        [string]$UpperUnit    = '';
        [string]$UpperPercent = '';
        [int]$Separator       = $Body.IndexOf(':');

        if ($Separator -lt 0) {
            # A single value 'X' is the range 0 .. X.
            $LowerBound = 0;
            if (-not $this.ParseBound($Body, [ref]$UpperBound, [ref]$UpperFamily, [ref]$UpperUnit, [ref]$UpperPercent)) {
                return;
            }
        } else {
            [string]$LeftPart  = $Body.Substring(0, $Separator);
            [string]$RightPart = $Body.Substring($Separator + 1);

            # A range may contain exactly one colon.
            if ($RightPart.IndexOf(':') -ge 0) {
                $this.Fail('IcingaThresholdInvalidBound');
                return;
            }

            if ([string]::IsNullOrEmpty($LeftPart)) {
                $LowerBound = 0;
            } elseif ($LeftPart -eq '~') {
                $LowerBound = [double]::NegativeInfinity;
            } elseif (-not $this.ParseBound($LeftPart, [ref]$LowerBound, [ref]$LowerFamily, [ref]$LowerUnit, [ref]$LowerPercent)) {
                return;
            }

            if ([string]::IsNullOrEmpty($RightPart)) {
                $UpperBound = [double]::PositiveInfinity;
            } elseif (-not $this.ParseBound($RightPart, [ref]$UpperBound, [ref]$UpperFamily, [ref]$UpperUnit, [ref]$UpperPercent)) {
                return;
            }
        }

        if ($LowerBound -gt $UpperBound) {
            $this.Fail('IcingaThresholdStartGreaterEnd');
            return;
        }

        $this.Start        = $LowerBound;
        $this.End          = $UpperBound;
        $this.StartUnit    = $LowerUnit;
        $this.EndUnit      = $UpperUnit;
        $this.StartPercent = $LowerPercent;
        $this.EndPercent   = $UpperPercent;
        $this.Family       = $LowerFamily;
        if ([string]::IsNullOrEmpty($this.Family)) {
            $this.Family = $UpperFamily;
        }
        $this.Success    = $true;
        $this.ReturnCode = 'IcingaThresholdParsed';
    }

    <#
    .SYNOPSIS
    Resolve a single bound token into a numeric base-unit value

    .DESCRIPTION
    Converts one bound of a threshold range into a numeric value. A percentage is
    resolved against the base value (failing when no base value was provided); a
    unit-carrying value is normalized to its base unit through IcingaUnit; a plain
    number is taken as-is in the smallest/base unit. Any other token is rejected.

    .PARAMETER Token
    | Name  | Type          | Description                          | Default |
    |-------|---------------|--------------------------------------|---------|
    | Token | System.String | Single bound token to resolve.       |         |

    .PARAMETER Result
    | Name   | Type                             | Description                                  | Default |
    |--------|----------------------------------|----------------------------------------------|---------|
    | Result | System.Management.Automation.PSReference | Receives the resolved numeric bound value.   |         |

    .PARAMETER Family
    | Name   | Type                                     | Description                                            | Default |
    |--------|------------------------------------------|--------------------------------------------------------|---------|
    | Family | System.Management.Automation.PSReference | Receives the unit family ('Data'/'Time'), '' when none.|         |

    .PARAMETER Unit
    | Name | Type                                     | Description                                       | Default |
    |------|------------------------------------------|---------------------------------------------------|---------|
    | Unit | System.Management.Automation.PSReference | Receives the original unit token, '' when none.   |         |

    .PARAMETER PercentToken
    | Name         | Type                                     | Description                                        | Default |
    |--------------|------------------------------------------|----------------------------------------------------|---------|
    | PercentToken | System.Management.Automation.PSReference | Receives the original percent token, '' when none. |         |

    .OUTPUTS
    System.Boolean — $true on success, $false when the bound could not be resolved.

    .EXAMPLE
    PS> $this.ParseBound('100MB', [ref]$value, [ref]$family, [ref]$unit, [ref]$percent)

    .NOTES
    Internal helper. The IcingaUnit reference is intentionally used inside the
    method body so the alphabetical kernel ordering (this file is emitted before
    IcingaUnit) resolves the type at runtime rather than at parse time.
    #>
    hidden [bool] ParseBound([string]$Token, [ref]$Result, [ref]$Family, [ref]$Unit, [ref]$PercentToken)
    {
        $Family.Value       = '';
        $Unit.Value         = '';
        $PercentToken.Value = '';

        [string]$Trimmed = $Token.Trim();

        if ([string]::IsNullOrEmpty($Trimmed)) {
            $this.Fail('IcingaThresholdInvalidBound');
            return $false;
        }

        $PercentMatch = [IcingaThresholdRange]::PercentRegex.Match($Trimmed);
        if ($PercentMatch.Success) {
            if (-not $this.HasBaseValue) {
                $this.Fail('IcingaThresholdMissingBaseValue');
                return $false;
            }

            [decimal]$Percent = 0;
            if (-not [decimal]::TryParse($PercentMatch.Groups[1].Value.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Percent)) {
                $this.Fail('IcingaThresholdInvalidBound');
                return $false;
            }

            $Result.Value       = [double](($Percent / 100) * [decimal]$this.BaseValue);
            $PercentToken.Value = $Trimmed;
            return $true;
        }

        $NumberMatch = [IcingaThresholdRange]::NumberRegex.Match($Trimmed);

        if ($NumberMatch.Success) {
            [decimal]$Number = 0;
            if (-not [decimal]::TryParse($NumberMatch.Groups[1].Value.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Number)) {
                $this.Fail('IcingaThresholdInvalidBound');
                return $false;
            }

            $Result.Value = [double]$Number;
            return $true;
        }

        # Anything left must be a '<number><unit>' value; reuse the unit engine to
        # normalize it to its base unit (bytes or seconds) without rounding.
        $UnitValue = [IcingaUnit]::new($Trimmed, $null, $null, $false);
        if (-not $UnitValue.Success) {
            $this.Fail('IcingaThresholdInvalidBound');
            return $false;
        }

        $Result.Value = $UnitValue.BaseValue;
        $Family.Value = $UnitValue.Family;
        $Unit.Value   = $UnitValue.InputUnit;
        return $true;
    }

    <#
    .SYNOPSIS
    Determine whether a measured value falls into this range's alert region

    .DESCRIPTION
    Evaluates a numeric value against the parsed bounds. For a normal range the
    value is in alert when it lies outside the bounds; for an inverted ('@') range
    the value is in alert when it lies inside the bounds. An unset range never
    raises an alert.

    .PARAMETER Value
    | Name  | Type          | Description                                  | Default |
    |-------|---------------|----------------------------------------------|---------|
    | Value | System.Double | Measured value in base units to evaluate.    |         |

    .OUTPUTS
    System.Boolean — $true when the value is in the alert region, otherwise $false.

    .EXAMPLE
    PS> $range.InAlertRange(15)

    .NOTES
    Internal evaluation helper. Open bounds are compared against infinities.
    #>
    hidden [bool] InAlertRange([double]$Value)
    {
        if (-not $this.IsSet) {
            return $false;
        }

        [bool]$Inside = ($Value -ge $this.Start) -and ($Value -le $this.End);

        if ($this.Inverted) {
            return $Inside;
        }

        return (-not $Inside);
    }

    <#
    .SYNOPSIS
    Return the original threshold string for 1:1 round-tripping

    .DESCRIPTION
    Returns the verbatim threshold string the range was constructed from so that a
    parsed range renders back into exactly the same notation it was given.

    .OUTPUTS
    System.String — The original threshold string ('' for an unset range).

    .EXAMPLE
    PS> $range.ToString()

    .NOTES
    Internal formatting helper.
    #>
    [string] ToString()
    {
        return $this.Threshold;
    }

    <#
    .SYNOPSIS
    Render the range's alert condition as a human-readable comparison

    .DESCRIPTION
    Translates the range into the plain comparison under which it raises an alert:
    '10:' to '< 10', '~:10' to '> 10', '10:20' to '< 10 or > 20', '@10:20' to
    '>= 10 and <= 20' and a single value '10' to '< 0 or > 10'. Numbers use the
    invariant culture and open ends are omitted. An unset range returns ''.

    .OUTPUTS
    System.String — The alert condition, or '' when the range is unset.

    .EXAMPLE
    PS> $range.ToAlertString()

    .NOTES
    Bounds are the resolved base-unit values.
    #>
    [string] ToAlertString()
    {
        return $this.ToAlertString('');
    }

    <#
    .SYNOPSIS
    Render the alert condition, rounding indivisible byte bounds to whole numbers

    .DESCRIPTION
    Like the parameterless ToAlertString, but takes the family of the quantity the range
    describes so that Data-family (byte) bounds render as whole numbers. A percent range
    parses no unit of its own and so cannot know it resolves against a byte base value;
    the caller supplies that family here. A bound with its own parsed unit family is
    unaffected. Time and unit-less bounds keep their precision.

    .PARAMETER EffectiveFamily
    | Name            | Type          | Description                                                    | Default |
    |-----------------|---------------|----------------------------------------------------------------|---------|
    | EffectiveFamily | System.String | Family of the compared quantity ('Data'/'Time'), '' when none. |         |

    .OUTPUTS
    System.String — The alert condition, or '' when the range is unset.

    .EXAMPLE
    PS> $range.ToAlertString('Data')

    .NOTES
    Byte bounds round half away from zero via FormatBest; the range keeps its own
    unrounded bounds for comparison.
    #>
    [string] ToAlertString([string]$EffectiveFamily)
    {
        if (-not $this.IsSet) {
            return '';
        }

        # The range's own parsed unit family wins; percent ranges parse none, so fall
        # back to the family the caller resolved the percent against.
        [string]$BoundFamily = $this.Family;
        if ([string]::IsNullOrEmpty($BoundFamily)) {
            $BoundFamily = $EffectiveFamily;
        }

        [bool]$HasLow  = -not [double]::IsNegativeInfinity($this.Start);
        [bool]$HasHigh = -not [double]::IsPositiveInfinity($this.End);
        [string]$Low   = [IcingaThresholdRange]::FormatBest($this.Start, $BoundFamily, $this.StartUnit);
        [string]$High  = [IcingaThresholdRange]::FormatBest($this.End, $BoundFamily, $this.EndUnit);

        if ($this.Inverted) {
            if ($HasLow -and $HasHigh) {
                return (">= {0} and <= {1}" -f $Low, $High);
            }
            if ($HasHigh) {
                return ("<= {0}" -f $High);
            }
            if ($HasLow) {
                return (">= {0}" -f $Low);
            }
            return 'any value';
        }

        if ($HasLow -and $HasHigh) {
            return ("< {0} or > {1}" -f $Low, $High);
        }
        if ($HasLow) {
            return ("< {0}" -f $Low);
        }
        if ($HasHigh) {
            return ("> {0}" -f $High);
        }
        return 'never';
    }

    <#
    .SYNOPSIS
    Render the range with its bounds resolved to base-unit numbers (no units)

    .DESCRIPTION
    Reconstructs the threshold in Icinga range notation but with every bound
    expressed as its resolved base-unit number and all unit suffixes and percent
    signs removed: '10MB' to '10000000', '15MB:' to '15000000:', '@10MB:20MB' to
    '@10000000:20000000' and '90%' (base 1000) to '900'. Suitable for the numeric
    warning/critical fields of a plugin result. An unset range returns ''.

    .OUTPUTS
    System.String — The resolved range string, or '' when the range is unset.

    .EXAMPLE
    PS> $range.ToBaseThresholdString()

    .NOTES
    Numbers use the invariant culture; open ends and single values keep their form.
    #>
    [string] ToBaseThresholdString()
    {
        return $this.ToBaseThresholdString('');
    }

    <#
    .SYNOPSIS
    Render the range's bounds as base-unit numbers, rounding indivisible byte units

    .DESCRIPTION
    Like the parameterless ToBaseThresholdString, but takes the family of the quantity
    the range describes so that Data-family (byte) bounds render as whole numbers. A
    percent range parses no unit of its own, so it cannot know it resolves against a byte
    base value; the caller supplies that family here. A bound whose own parsed unit is
    Data still rounds even when no effective family is passed, so an absolute byte range
    such as '15GiB:' is covered too.

    .PARAMETER EffectiveFamily
    | Name            | Type          | Description                                                     | Default |
    |-----------------|---------------|-----------------------------------------------------------------|---------|
    | EffectiveFamily | System.String | Family of the compared quantity ('Data'/'Time'), '' when none.  |         |

    .OUTPUTS
    System.String — The resolved range string, or '' when the range is unset.

    .EXAMPLE
    PS> $range.ToBaseThresholdString('Data')

    .NOTES
    Byte bounds round half away from zero; the range's own bounds stay unrounded for
    comparison. Open ends and single values keep their form.
    #>
    [string] ToBaseThresholdString([string]$EffectiveFamily)
    {
        if (-not $this.IsSet) {
            return '';
        }

        # The range's own parsed unit family wins; percent ranges parse none, so fall
        # back to the family the caller resolved the percent against.
        [string]$RenderFamily = $this.Family;
        if ([string]::IsNullOrEmpty($RenderFamily)) {
            $RenderFamily = $EffectiveFamily;
        }

        [string]$Prefix = '';
        if ($this.Inverted) {
            $Prefix = '@';
        }

        [string]$UpperText = ([IcingaThresholdRange]::RoundBaseValue($this.End, $RenderFamily)).ToString([System.Globalization.CultureInfo]::InvariantCulture);

        # A single value 'X' (no colon in the source) renders as just its upper bound.
        if (-not $this.Threshold.Contains(':')) {
            return ($Prefix + $UpperText);
        }

        [string]$LowerText = '~';
        if (-not [double]::IsNegativeInfinity($this.Start)) {
            $LowerText = ([IcingaThresholdRange]::RoundBaseValue($this.Start, $RenderFamily)).ToString([System.Globalization.CultureInfo]::InvariantCulture);
        }

        if ([double]::IsPositiveInfinity($this.End)) {
            $UpperText = '';
        }

        return ($Prefix + $LowerText + ':' + $UpperText);
    }

    <#
    .SYNOPSIS
    Record a failure state with a semantic error return code

    .DESCRIPTION
    Sets the internal Success flag to $false and stores the specified semantic
    error code in ReturnCode for downstream error propagation.

    .PARAMETER Code
    | Name | Type          | Description                                  | Default |
    |------|---------------|----------------------------------------------|---------|
    | Code | System.String | Semantic return code identifying the failure.|         |

    .OUTPUTS
    None — Updates instance state.

    .EXAMPLE
    PS> $this.Fail('IcingaThresholdInvalidBound')

    .NOTES
    Internal helper method for failure handling.
    #>
    hidden [void] Fail([string]$Code)
    {
        $this.Success    = $false;
        $this.ReturnCode = $Code;
    }

    <#
    .SYNOPSIS
    Map a unit family to its base-unit symbol

    .DESCRIPTION
    Returns the single-character base-unit symbol for a resolved unit family: 'B'
    for the Data family (bytes) and 's' for the Time family (seconds). Any other
    family — including the empty family of a plain number — yields an empty string
    so that unit-less values render without a suffix.

    .PARAMETER Family
    | Name   | Type          | Description                              | Default |
    |--------|---------------|------------------------------------------|---------|
    | Family | System.String | Resolved unit family ('Data' or 'Time'). |         |

    .OUTPUTS
    System.String — The base-unit symbol, or '' when the family is unknown/unset.

    .EXAMPLE
    PS> [IcingaThresholdRange]::UnitSymbol('Data')

    .NOTES
    Internal static helper shared by the value and message formatters.
    #>
    static hidden [string] UnitSymbol([string]$Family)
    {
        if ($Family -eq 'Data') {
            return 'B';
        }
        if ($Family -eq 'Time') {
            return 's';
        }

        return '';
    }

    <#
    .SYNOPSIS
    Round a base-unit value to a whole number for indivisible units

    .DESCRIPTION
    Bytes are indivisible, so a Data-family value must never carry a fractional part in a
    rendered result field even when it was derived from a fractional unit (for example
    '254.55GiB') or from percentage arithmetic. This rounds a Data-family value to the
    nearest whole base unit and returns every other family — including sub-second Time
    values and unit-less numbers — unchanged, preserving their precision.

    .PARAMETER Value
    | Name  | Type          | Description                         | Default |
    |-------|---------------|-------------------------------------|---------|
    | Value | System.Double | Value already scaled to base units. |         |

    .PARAMETER Family
    | Name   | Type          | Description                              | Default |
    |--------|---------------|------------------------------------------|---------|
    | Family | System.String | Resolved unit family ('Data' or 'Time'). |         |

    .OUTPUTS
    System.Double — The value rounded to a whole number for 'Data', otherwise unchanged.

    .EXAMPLE
    PS> [IcingaThresholdRange]::RoundBaseValue(273320981299.2, 'Data')

    .NOTES
    Internal static helper. Rounds half away from zero. The comparison logic keeps the
    unrounded value; only rendered result fields pass through here.
    #>
    static hidden [double] RoundBaseValue([double]$Value, [string]$Family)
    {
        if ($Family -eq 'Data') {
            return [System.Math]::Round($Value, [System.MidpointRounding]::AwayFromZero);
        }

        return $Value;
    }

    <#
    .SYNOPSIS
    Render a base-unit value with its base-unit symbol

    .DESCRIPTION
    Formats a resolved base-unit value as its invariant-culture number followed by
    the family's base-unit symbol (bytes 'B', seconds 's'). A value without a
    family renders as the bare number, preserving the unit-less rendering of plain
    numbers and percent-resolved values. Used for the InputValue result field.

    .PARAMETER Value
    | Name  | Type          | Description                          | Default |
    |-------|---------------|--------------------------------------|---------|
    | Value | System.Double | Value already scaled to base units.  |         |

    .PARAMETER Family
    | Name   | Type          | Description                              | Default |
    |--------|---------------|------------------------------------------|---------|
    | Family | System.String | Resolved unit family ('Data' or 'Time'). |         |

    .OUTPUTS
    System.String — The base value with its base-unit symbol, e.g. '19000000B'.

    .EXAMPLE
    PS> [IcingaThresholdRange]::FormatBase(19000000, 'Data')

    .NOTES
    Internal static helper. Base symbol comes from UnitSymbol.
    #>
    static hidden [string] FormatBase([double]$Value, [string]$Family)
    {
        [double]$Rounded = [IcingaThresholdRange]::RoundBaseValue($Value, $Family);
        return ($Rounded.ToString([System.Globalization.CultureInfo]::InvariantCulture) + [IcingaThresholdRange]::UnitSymbol($Family));
    }

    <#
    .SYNOPSIS
    Render a base-unit value back into the unit it was originally given in

    .DESCRIPTION
    Converts a resolved base-unit value back into a human-readable string using the
    unit token originally supplied for it (for example base 10000000 with unit 'MB'
    renders as '10MB', base 21600 with unit 'h' as '6h'), reusing the IcingaUnit
    conversion engine with the family's base unit as the source. When the value
    carries no family or unit it renders as the bare invariant number, so plain
    numbers and percent-resolved values keep their unit-less form. Falls back to the
    bare number if the conversion fails.

    .PARAMETER Value
    | Name  | Type          | Description                          | Default |
    |-------|---------------|--------------------------------------|---------|
    | Value | System.Double | Value already scaled to base units.  |         |

    .PARAMETER Family
    | Name   | Type          | Description                              | Default |
    |--------|---------------|------------------------------------------|---------|
    | Family | System.String | Resolved unit family ('Data' or 'Time'). |         |

    .PARAMETER Unit
    | Name | Type          | Description                                 | Default |
    |------|---------------|---------------------------------------------|---------|
    | Unit | System.String | Original unit token to render the value in. |         |

    .OUTPUTS
    System.String — The value rendered in its original unit, e.g. '10MB' or '6h'.

    .EXAMPLE
    PS> [IcingaThresholdRange]::FormatBest(10000000, 'Data', 'MB')

    .NOTES
    Internal static helper. The IcingaUnit reference is used inside the method body
    so the kernel's alphabetical class ordering resolves the type at runtime.
    #>
    static hidden [string] FormatBest([double]$Value, [string]$Family, [string]$Unit)
    {
        # Bytes are indivisible, so a Data-family value never renders with a fractional
        # part; Time and unit-less values keep their precision.
        [string]$Number = ([IcingaThresholdRange]::RoundBaseValue($Value, $Family)).ToString([System.Globalization.CultureInfo]::InvariantCulture);

        if ([string]::IsNullOrEmpty($Unit) -or [string]::IsNullOrEmpty($Family)) {
            return $Number;
        }

        $Converted = [IcingaUnit]::new($Number, [IcingaThresholdRange]::UnitSymbol($Family), $Unit, $false);
        if ($Converted.Success) {
            return $Converted.OutputString;
        }

        return $Number;
    }
}

<#
.SYNOPSIS
Result of evaluating a measured value against an IcingaThresholds definition

.DESCRIPTION
IcingaThresholdResult is the value object every IcingaThresholds comparison method
returns. It carries the measured value together with the warning and critical
thresholds it was compared against — for numeric comparisons these are expressed
in the smallest (base) unit, for pattern comparisons they hold the raw strings —
plus the resulting Icinga plugin state code and a short, user-friendly output
message describing why that state was chosen. When the threshold was created with a
base value, BaseValue additionally carries that resolved base (its maximum) in the
smallest unit; otherwise it is $null.

.OUTPUTS
IcingaThresholdResult — Value object describing a single evaluation.

.EXAMPLE
PS> [IcingaThresholdResult]::new(950, 800, 900, 2, 'value 950 is greater than critical threshold 900')

Creates a critical result for a value that exceeded the critical threshold.

.NOTES
Self-contained value object. Does not modify global state or access external
services. Safe to construct in multi-threaded runspaces.
#>
class IcingaThresholdResult
{
    [object]$InputValue    = $null;
    [object]$WarningValue  = $null;
    [object]$CriticalValue = $null;
    [object]$BaseValue     = $null;
    [int]$StatusCode       = 0;
    [string]$Output        = '';

    <#
    .SYNOPSIS
    Initialize a threshold evaluation result

    .DESCRIPTION
    Stores the measured value, the warning and critical thresholds it was compared
    against, the resulting Icinga plugin state code and the human-readable output
    message.

    .PARAMETER InputValue
    | Name       | Type          | Description                                            | Default |
    |------------|---------------|--------------------------------------------------------|---------|
    | InputValue | System.Object | Measured value in the smallest unit, or the raw input. |         |

    .PARAMETER WarningValue
    | Name         | Type          | Description                                          | Default |
    |--------------|---------------|------------------------------------------------------|---------|
    | WarningValue | System.Object | Warning threshold (smallest unit or pattern), or $null.|       |

    .PARAMETER CriticalValue
    | Name          | Type          | Description                                            | Default |
    |---------------|---------------|--------------------------------------------------------|---------|
    | CriticalValue | System.Object | Critical threshold (smallest unit or pattern), or $null.|       |

    .PARAMETER StatusCode
    | Name       | Type         | Description                                       | Default |
    |------------|--------------|---------------------------------------------------|---------|
    | StatusCode | System.Int32 | Icinga plugin state: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN. |   |

    .PARAMETER Output
    | Name   | Type          | Description                                     | Default |
    |--------|---------------|-------------------------------------------------|---------|
    | Output | System.String | Human-readable description of the result state. |         |

    .OUTPUTS
    IcingaThresholdResult — Configured result instance.

    .EXAMPLE
    PS> [IcingaThresholdResult]::new(5, $null, 10, 2, 'value 5 is lower than critical threshold 10')

    .NOTES
    Plain data container; performs no evaluation itself.
    #>
    IcingaThresholdResult([object]$InputValue, [object]$WarningValue, [object]$CriticalValue, [int]$StatusCode, [string]$Output)
    {
        $this.InputValue    = $InputValue;
        $this.WarningValue  = $WarningValue;
        $this.CriticalValue = $CriticalValue;
        $this.StatusCode    = $StatusCode;
        $this.Output        = $Output;
    }

    <#
    .SYNOPSIS
    Return the human-readable output message

    .DESCRIPTION
    Returns the Output message so a result renders as its description when used in
    string context.

    .OUTPUTS
    System.String — The Output message.

    .EXAMPLE
    PS> $result.ToString()

    .NOTES
    Internal formatting helper.
    #>
    [string] ToString()
    {
        return $this.Output;
    }
}

<#
.SYNOPSIS
Threshold pair that compares a measured value and returns an Icinga plugin state

.DESCRIPTION
IcingaThresholds holds a warning and a critical threshold plus an optional base
value and exposes a family of comparison methods. Each method compares a measured
value against the warning and the critical threshold using a specific operator and
returns an IcingaThresholdResult carrying the value, both thresholds, the resulting
Icinga plugin state (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN) and a user-friendly
output message. The critical threshold is evaluated first so that it takes
precedence over the warning threshold.

CheckRange uses the full Icinga/Nagios range grammar; Greater, GreaterEqual, Lower
and LowerEqual are numeric comparisons; Max compares against thresholds relative to
the base value (its maximum); Matches/NotMatches use regular expressions and
Like/NotLike use wildcard patterns for string values. Numeric values and thresholds
may be plain numbers (smallest/base unit), unit strings such as '10GB' or '500ms'
(normalized through IcingaUnit) or percentages resolved against the base value; the
base value itself may be a number or a unit string such as '1TB'. The warning and
critical strings are stored verbatim so they round-trip 1:1.

The class never throws. Any problem — an invalid threshold or base value, an
unresolvable measured value, a percentage without a base value, or an invalid
pattern — yields a result with StatusCode 3 (UNKNOWN) and a clean explanatory
Output message. A null or empty warning or critical is a valid "unset" threshold
that never raises that state.

.OUTPUTS
IcingaThresholds — Threshold object exposing the comparison methods.

.EXAMPLE
PS> [IcingaThresholds]::new('10:20', '5:30').CheckRange(3)

Returns a CRITICAL result because 3 is outside the critical range 5:30.

.EXAMPLE
PS> [IcingaThresholds]::new('80%', '90%', '1TB').CheckMax('950GB')

Resolves the percent thresholds against the 1 TB maximum and evaluates 950 GB.

.NOTES
Self-contained value object. Reuses IcingaUnit for unit normalization and
IcingaThresholdRange for range parsing. Does not modify global state or access
external services. Safe to construct in multi-threaded runspaces.
#>
class IcingaThresholds
{
    [string]$Warning  = '';
    [string]$Critical = '';
    [double]$Maximum  = 0;

    hidden [bool]$HasBaseValue = $false;
    hidden [bool]$BaseValid    = $true;
    hidden [string]$BaseError  = '';
    hidden [string]$BaseFamily = '';
    hidden [string]$BaseUnit   = '';

    static hidden [regex]$PercentRegex = [regex]::new('^\s*(-?\d+(?:[.,]\d+)?)\s*%\s*$', [System.Text.RegularExpressions.RegexOptions]::Compiled);

    # Regex metacharacters that make a pattern more than a plain literal. Whitespace and
    # '#' are literal under the operators' default options and so are not listed.
    static hidden [char[]]$RegexMetaChars = [char[]]@('.', '^', '$', '*', '+', '?', '(', ')', '[', ']', '{', '}', '|', '\');

    <#
    .SYNOPSIS
    Create a threshold pair without a base value

    .DESCRIPTION
    Stores the raw warning and critical threshold strings. Percentages are not
    supported without a base value and produce an UNKNOWN result at comparison time.

    .PARAMETER Warning
    | Name    | Type          | Description                                  | Default |
    |---------|---------------|----------------------------------------------|---------|
    | Warning | System.String | Warning threshold string ('' = unset).       |         |

    .PARAMETER Critical
    | Name     | Type          | Description                                 | Default |
    |----------|---------------|---------------------------------------------|---------|
    | Critical | System.String | Critical threshold string ('' = unset).     |         |

    .OUTPUTS
    IcingaThresholds — Configured threshold object.

    .EXAMPLE
    PS> [IcingaThresholds]::new('10:20', '5:30')

    .NOTES
    Never throws; comparison methods surface any problem as an UNKNOWN result.
    #>
    IcingaThresholds([string]$Warning, [string]$Critical)
    {
        $this.Initialize($Warning, $Critical, '', $false);
    }

    <#
    .SYNOPSIS
    Create a threshold pair with a base value for percent and Max comparisons

    .DESCRIPTION
    Stores the raw warning and critical threshold strings and resolves the base
    value (a number or a unit string such as '1TB') into the Maximum property.
    Percentages in thresholds are resolved against this base value.

    .PARAMETER Warning
    | Name    | Type          | Description                                  | Default |
    |---------|---------------|----------------------------------------------|---------|
    | Warning | System.String | Warning threshold string ('' = unset).       |         |

    .PARAMETER Critical
    | Name     | Type          | Description                                 | Default |
    |----------|---------------|---------------------------------------------|---------|
    | Critical | System.String | Critical threshold string ('' = unset).     |         |

    .PARAMETER BaseValue
    | Name      | Type          | Description                                                     | Default |
    |-----------|---------------|-----------------------------------------------------------------|---------|
    | BaseValue | System.String | Base/maximum value; a number or unit string such as '1TB'.      |         |

    .OUTPUTS
    IcingaThresholds — Configured threshold object.

    .EXAMPLE
    PS> [IcingaThresholds]::new('20%:', '10%:', '1TB')

    .NOTES
    An unresolvable base value is remembered and surfaced as an UNKNOWN result.
    #>
    IcingaThresholds([string]$Warning, [string]$Critical, [string]$BaseValue)
    {
        $this.Initialize($Warning, $Critical, $BaseValue, $true);
    }

    <#
    .SYNOPSIS
    Store the thresholds and resolve the base value

    .DESCRIPTION
    Shared constructor logic. Stores the verbatim warning and critical strings and,
    when a base value was supplied, resolves it into the Maximum property. A base
    value that cannot be resolved is recorded (BaseValid/BaseError) and later turns
    every comparison into an UNKNOWN result; nothing is thrown.

    .PARAMETER Warning
    | Name    | Type          | Description                      | Default |
    |---------|---------------|----------------------------------|---------|
    | Warning | System.String | Warning threshold string.        |         |

    .PARAMETER Critical
    | Name     | Type          | Description                     | Default |
    |----------|---------------|---------------------------------|---------|
    | Critical | System.String | Critical threshold string.      |         |

    .PARAMETER BaseValue
    | Name      | Type          | Description                                        | Default |
    |-----------|---------------|----------------------------------------------------|---------|
    | BaseValue | System.String | Base value as a number or unit string.             |         |

    .PARAMETER HasBaseValue
    | Name         | Type           | Description                        | Default |
    |--------------|----------------|------------------------------------|---------|
    | HasBaseValue | System.Boolean | Whether a base value was supplied. |         |

    .OUTPUTS
    None — Updates instance state.

    .EXAMPLE
    PS> $this.Initialize('20%:', '10%:', '1TB', $true)

    .NOTES
    Internal helper shared by both constructors.
    #>
    hidden [void] Initialize([string]$Warning, [string]$Critical, [string]$BaseValue, [bool]$HasBaseValue)
    {
        $this.Warning      = $Warning;
        $this.Critical     = $Critical;
        $this.HasBaseValue = $HasBaseValue;

        if ($HasBaseValue) {
            [double]$Resolved     = 0;
            [string]$ResolvedFam  = '';
            [string]$ResolvedUnit = '';
            if ($this.TryResolveValue($BaseValue, [ref]$Resolved, [ref]$ResolvedFam, [ref]$ResolvedUnit)) {
                $this.Maximum    = $Resolved;
                $this.BaseFamily = $ResolvedFam;
                $this.BaseUnit   = $ResolvedUnit;
                $this.BaseValid  = $true;
            } else {
                $this.BaseValid = $false;
                $this.BaseError = ("the base value '{0}' is not a valid number or '<number><unit>' value" -f $BaseValue);
            }
        }
    }

    <#
    .SYNOPSIS
    Compare a value against the warning and critical ranges (Icinga range grammar)

    .DESCRIPTION
    Parses the warning and critical thresholds as Icinga/Nagios ranges and returns
    the resulting state: CRITICAL when the value is in the critical range's alert
    region, WARNING when in the warning range's, otherwise OK. An invalid range,
    invalid base value or unresolvable value yields UNKNOWN with an explanatory
    message.

    .PARAMETER Value
    | Name  | Type          | Description                                              | Default |
    |-------|---------------|----------------------------------------------------------|---------|
    | Value | System.Object | Measured value; a number, a '<number><unit>' string, or $null. |   |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> $thresholds.CheckRange(15)

    .NOTES
    Uses IcingaThresholdRange for parsing; percent bounds resolve against Maximum.
    #>
    [IcingaThresholdResult] CheckRange([object]$Value)
    {
        if ($this.HasBaseValue -and -not $this.BaseValid) {
            return $this.BuildResult($Value, $this.Warning, $this.Critical, 3, $this.BaseError);
        }

        [double]$Numeric     = 0;
        [string]$ValueFamily = '';
        [string]$ValueUnit   = '';
        if (-not $this.TryResolveValue($Value, [ref]$Numeric, [ref]$ValueFamily, [ref]$ValueUnit)) {
            return $this.BuildResult($Value, $this.Warning, $this.Critical, 3, ("The value '{0}' could not be interpreted as a number" -f $Value));
        }

        # InputValue carries the resolved base value with its base-unit symbol.
        [string]$InputOut = [IcingaThresholdRange]::FormatBase($Numeric, $ValueFamily);

        if ($this.HasBaseValue -and $this.BaseValid -and $Numeric -gt $this.Maximum) {
            return $this.BuildResult($InputOut, $this.Warning, $this.Critical, 3, $this.DescribeBaseValueExceeded($Value, $InputOut, $ValueFamily));
        }

        $WarnRange = [IcingaThresholdRange]::new($this.Warning, $this.Maximum, $this.HasBaseValue);
        if (-not $WarnRange.Success) {
            return $this.BuildResult($InputOut, $this.Warning, $this.Critical, 3, ("warning: {0}" -f $this.RangeError($WarnRange.ReturnCode, $this.Warning)));
        }

        $CritRange = [IcingaThresholdRange]::new($this.Critical, $this.Maximum, $this.HasBaseValue);
        if (-not $CritRange.Success) {
            return $this.BuildResult($InputOut, $this.Warning, $this.Critical, 3, ("critical: {0}" -f $this.RangeError($CritRange.ReturnCode, $this.Critical)));
        }

        # When percent thresholds are in play, every message shows the value's share
        # of the base value; each percent threshold shows its own percent token.
        [bool]$ShowPercent    = ($WarnRange.StartPercent -ne '') -or ($WarnRange.EndPercent -ne '') -or ($CritRange.StartPercent -ne '') -or ($CritRange.EndPercent -ne '');
        [string]$ValueDisplay = $this.FormatValueDisplay($Numeric, $ValueFamily, $ValueUnit, $ShowPercent);

        # Warning/Critical result fields carry the resolved bounds without units. The
        # measured value's family (or, for a unit-less value, the base value's) tells the
        # ranges whether their percent-resolved bounds are indivisible bytes.
        [string]$ResultFamily = $ValueFamily;
        if ([string]::IsNullOrEmpty($ResultFamily)) {
            $ResultFamily = $this.BaseFamily;
        }

        [object]$WarnOut = $null;
        [object]$CritOut = $null;
        if ($WarnRange.IsSet) {
            $WarnOut = $WarnRange.ToBaseThresholdString($ResultFamily);
        }
        if ($CritRange.IsSet) {
            $CritOut = $CritRange.ToBaseThresholdString($ResultFamily);
        }

        if ($WarnRange.IsSet -and $CritRange.IsSet) {
            [string]$Unreachable = $this.RangeUnreachableState($WarnRange, $CritRange);
            if ($Unreachable -ne '') {
                return $this.BuildResult($InputOut, $WarnOut, $CritOut, 3, ("Check can never reach [{0}]-State if warning is '{1}' and critical is '{2}'" -f $Unreachable, $WarnRange.ToAlertString($ResultFamily), $CritRange.ToAlertString($ResultFamily)));
            }
        }

        if ($CritRange.IsSet -and $CritRange.InAlertRange($Numeric)) {
            return $this.BuildResult($InputOut, $WarnOut, $CritOut, 2, $this.DescribeRangeAlert($Numeric, $ValueDisplay, $CritRange));
        }

        if ($WarnRange.IsSet -and $WarnRange.InAlertRange($Numeric)) {
            return $this.BuildResult($InputOut, $WarnOut, $CritOut, 1, $this.DescribeRangeAlert($Numeric, $ValueDisplay, $WarnRange));
        }

        return $this.BuildResult($InputOut, $WarnOut, $CritOut, 0, ("{0} is ok" -f $ValueDisplay));
    }

    <#
    .SYNOPSIS
    Alert when the value is greater than the thresholds

    .DESCRIPTION
    Returns CRITICAL when the value is greater than the critical threshold, WARNING
    when greater than the warning threshold, otherwise OK. Unresolvable input or
    thresholds yield UNKNOWN.

    .PARAMETER Value
    | Name  | Type          | Description                                              | Default |
    |-------|---------------|----------------------------------------------------------|---------|
    | Value | System.Object | Measured value; number, '<number><unit>' string, or $null.|        |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> $thresholds.CheckGreater(950)

    .NOTES
    Percent thresholds resolve against the base value.
    #>
    [IcingaThresholdResult] CheckGreater([object]$Value)
    {
        return $this.CompareNumeric($Value, 'gt', 'greater than');
    }

    <#
    .SYNOPSIS
    Alert when the value is greater than or equal to the thresholds

    .DESCRIPTION
    Returns CRITICAL when the value is greater than or equal to the critical
    threshold, WARNING when greater than or equal to the warning threshold,
    otherwise OK. Unresolvable input or thresholds yield UNKNOWN.

    .PARAMETER Value
    | Name  | Type          | Description                                              | Default |
    |-------|---------------|----------------------------------------------------------|---------|
    | Value | System.Object | Measured value; number, '<number><unit>' string, or $null.|        |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> $thresholds.CheckGreaterEqual(90)

    .NOTES
    Percent thresholds resolve against the base value.
    #>
    [IcingaThresholdResult] CheckGreaterEqual([object]$Value)
    {
        return $this.CompareNumeric($Value, 'ge', 'greater than or equal to');
    }

    <#
    .SYNOPSIS
    Alert when the value is lower than the thresholds

    .DESCRIPTION
    Returns CRITICAL when the value is lower than the critical threshold, WARNING
    when lower than the warning threshold, otherwise OK. Unresolvable input or
    thresholds yield UNKNOWN.

    .PARAMETER Value
    | Name  | Type          | Description                                              | Default |
    |-------|---------------|----------------------------------------------------------|---------|
    | Value | System.Object | Measured value; number, '<number><unit>' string, or $null.|        |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> $thresholds.CheckLower(5)

    .NOTES
    Percent thresholds resolve against the base value.
    #>
    [IcingaThresholdResult] CheckLower([object]$Value)
    {
        return $this.CompareNumeric($Value, 'lt', 'lower than');
    }

    <#
    .SYNOPSIS
    Alert when the value is lower than or equal to the thresholds

    .DESCRIPTION
    Returns CRITICAL when the value is lower than or equal to the critical
    threshold, WARNING when lower than or equal to the warning threshold, otherwise
    OK. Unresolvable input or thresholds yield UNKNOWN.

    .PARAMETER Value
    | Name  | Type          | Description                                              | Default |
    |-------|---------------|----------------------------------------------------------|---------|
    | Value | System.Object | Measured value; number, '<number><unit>' string, or $null.|        |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> $thresholds.CheckLowerEqual(10)

    .NOTES
    Percent thresholds resolve against the base value.
    #>
    [IcingaThresholdResult] CheckLowerEqual([object]$Value)
    {
        return $this.CompareNumeric($Value, 'le', 'lower than or equal to');
    }

    <#
    .SYNOPSIS
    Alert when the value reaches its maximum-relative thresholds

    .DESCRIPTION
    Requires a base value (the Maximum). Returns CRITICAL when the value is greater
    than or equal to the critical threshold, WARNING when greater than or equal to
    the warning threshold, otherwise OK. Thresholds are commonly percentages
    resolved against the Maximum. Without a base value the result is UNKNOWN.

    .PARAMETER Value
    | Name  | Type          | Description                                              | Default |
    |-------|---------------|----------------------------------------------------------|---------|
    | Value | System.Object | Measured value; number, '<number><unit>' string, or $null.|        |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> [IcingaThresholds]::new('80%', '90%', '1TB').CheckMax('950GB')

    .NOTES
    Equivalent to CheckGreaterEqual with the base value acting as the 100% maximum.
    #>
    [IcingaThresholdResult] CheckMax([object]$Value)
    {
        if (-not $this.HasBaseValue) {
            return $this.BuildResult($Value, $this.Warning, $this.Critical, 3, 'the CheckMax comparison requires a base value');
        }

        return $this.CompareNumeric($Value, 'ge', 'greater than or equal to');
    }

    <#
    .SYNOPSIS
    Alert when the string value matches the threshold regular expressions

    .DESCRIPTION
    Returns CRITICAL when the value matches the critical regular expression, WARNING
    when it matches the warning regular expression, otherwise OK. An invalid pattern
    yields UNKNOWN.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Value to test as a string, or $null.     |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> [IcingaThresholds]::new('^warn', '^err').CheckMatch('error state')

    .NOTES
    Thresholds are treated as .NET regular expressions (case-insensitive).
    #>
    [IcingaThresholdResult] CheckMatch([object]$Value)
    {
        return $this.CompareString($Value, 'match', 'matches');
    }

    <#
    .SYNOPSIS
    Alert when the string value does not match the threshold regular expressions

    .DESCRIPTION
    Returns CRITICAL when the value does not match the critical regular expression,
    WARNING when it does not match the warning regular expression, otherwise OK. An
    invalid pattern yields UNKNOWN.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Value to test as a string, or $null.     |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> [IcingaThresholds]::new('^ok', '^healthy').CheckNotMatch('degraded')

    .NOTES
    Thresholds are treated as .NET regular expressions (case-insensitive).
    #>
    [IcingaThresholdResult] CheckNotMatch([object]$Value)
    {
        return $this.CompareString($Value, 'notmatch', 'does not match');
    }

    <#
    .SYNOPSIS
    Alert when the string value is like the threshold wildcard patterns

    .DESCRIPTION
    Returns CRITICAL when the value is like the critical wildcard pattern, WARNING
    when it is like the warning wildcard pattern, otherwise OK.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Value to test as a string, or $null.     |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> [IcingaThresholds]::new('*warn*', '*error*').CheckLike('fatal error occurred')

    .NOTES
    Thresholds are treated as PowerShell wildcard patterns (case-insensitive).
    #>
    [IcingaThresholdResult] CheckLike([object]$Value)
    {
        return $this.CompareString($Value, 'like', 'is like');
    }

    <#
    .SYNOPSIS
    Alert when the string value is not like the threshold wildcard patterns

    .DESCRIPTION
    Returns CRITICAL when the value is not like the critical wildcard pattern,
    WARNING when it is not like the warning wildcard pattern, otherwise OK.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Value to test as a string, or $null.     |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> [IcingaThresholds]::new('*ok*', '*healthy*').CheckNotLike('service down')

    .NOTES
    Thresholds are treated as PowerShell wildcard patterns (case-insensitive).
    #>
    [IcingaThresholdResult] CheckNotLike([object]$Value)
    {
        return $this.CompareString($Value, 'notlike', 'is not like');
    }

    <#
    .SYNOPSIS
    Alert when the string value equals the threshold values

    .DESCRIPTION
    Returns CRITICAL when the value equals the critical threshold, WARNING when it
    equals the warning threshold, otherwise OK. The comparison is a case-insensitive
    string equality test, not a pattern match.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Value to test as a string, or $null.     |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> [IcingaThresholds]::new('degraded', 'offline').CheckEqual('offline')

    .NOTES
    Thresholds are compared as plain strings (case-insensitive), not patterns.
    #>
    [IcingaThresholdResult] CheckEqual([object]$Value)
    {
        return $this.CompareString($Value, 'eq', 'equals');
    }

    <#
    .SYNOPSIS
    Alert when the string value does not equal the threshold values

    .DESCRIPTION
    Returns CRITICAL when the value does not equal the critical threshold, WARNING
    when it does not equal the warning threshold, otherwise OK. The comparison is a
    case-insensitive string equality test, not a pattern match.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Value to test as a string, or $null.     |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> [IcingaThresholds]::new('online', 'online').CheckNotEqual('offline')

    .NOTES
    Thresholds are compared as plain strings (case-insensitive), not patterns.
    #>
    [IcingaThresholdResult] CheckNotEqual([object]$Value)
    {
        return $this.CompareString($Value, 'ne', 'does not equal');
    }

    <#
    .SYNOPSIS
    Evaluate a value numerically against the warning and critical thresholds

    .DESCRIPTION
    Shared numeric comparison used by CheckGreater, CheckGreaterEqual, CheckLower,
    CheckLowerEqual and CheckMax. Resolves the value and each threshold to a
    base-unit number (percent
    thresholds resolve against the base value), applies the operator with critical
    taking precedence over warning, and builds an IcingaThresholdResult. Any
    resolution failure returns an UNKNOWN result with an explanatory message.

    .PARAMETER Value
    | Name  | Type          | Description                           | Default |
    |-------|---------------|---------------------------------------|---------|
    | Value | System.Object | Measured value to evaluate.           |         |

    .PARAMETER Operator
    | Name     | Type          | Description                                       | Default |
    |----------|---------------|---------------------------------------------------|---------|
    | Operator | System.String | Comparison operator: 'gt', 'ge', 'lt' or 'le'.    |         |

    .PARAMETER OperatorText
    | Name         | Type          | Description                              | Default |
    |--------------|---------------|------------------------------------------|---------|
    | OperatorText | System.String | Human-readable operator for the message. |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> $this.CompareNumeric(950, 'gt', 'greater than')

    .NOTES
    Internal helper. An unset threshold is skipped (never raises its state).
    #>
    hidden [IcingaThresholdResult] CompareNumeric([object]$Value, [string]$Operator, [string]$OperatorText)
    {
        if ($this.HasBaseValue -and -not $this.BaseValid) {
            return $this.BuildResult($Value, $this.Warning, $this.Critical, 3, $this.BaseError);
        }

        [double]$Numeric     = 0;
        [string]$ValueFamily = '';
        [string]$ValueUnit   = '';
        if (-not $this.TryResolveValue($Value, [ref]$Numeric, [ref]$ValueFamily, [ref]$ValueUnit)) {
            return $this.BuildResult($Value, $this.Warning, $this.Critical, 3, ("The value '{0}' could not be interpreted as a number" -f $Value));
        }

        # InputValue carries the resolved base value with its base-unit symbol.
        [string]$InputOut = [IcingaThresholdRange]::FormatBase($Numeric, $ValueFamily);

        if ($this.HasBaseValue -and $this.BaseValid -and $Numeric -gt $this.Maximum) {
            return $this.BuildResult($InputOut, $this.Warning, $this.Critical, 3, $this.DescribeBaseValueExceeded($Value, $InputOut, $ValueFamily));
        }

        [bool]$WarnSet       = -not [string]::IsNullOrWhiteSpace($this.Warning);
        [bool]$CritSet       = -not [string]::IsNullOrWhiteSpace($this.Critical);
        [double]$WarnNum     = 0;
        [double]$CritNum     = 0;
        [string]$Reason      = '';
        [string]$WarnFamily  = '';
        [string]$WarnUnit    = '';
        [string]$WarnPercent = '';
        [string]$CritFamily  = '';
        [string]$CritUnit    = '';
        [string]$CritPercent = '';

        if ($WarnSet -and -not $this.TryResolveThreshold($this.Warning, [ref]$WarnNum, [ref]$Reason, [ref]$WarnFamily, [ref]$WarnUnit, [ref]$WarnPercent)) {
            return $this.BuildResult($InputOut, $this.Warning, $this.Critical, 3, ("warning: {0}" -f $Reason));
        }

        if ($CritSet -and -not $this.TryResolveThreshold($this.Critical, [ref]$CritNum, [ref]$Reason, [ref]$CritFamily, [ref]$CritUnit, [ref]$CritPercent)) {
            return $this.BuildResult($InputOut, $this.Warning, $this.Critical, 3, ("critical: {0}" -f $Reason));
        }

        if ($WarnSet -and $CritSet -and $this.NumericWarningMasked($WarnNum, $CritNum, $Operator)) {
            return $this.BuildResult($InputOut, $WarnNum, $CritNum, 3, ("Check can never reach [WARNING]-State if warning is '{0}' and critical is '{1}'" -f $this.NumericAlertString($WarnNum, $Operator, $WarnFamily, $WarnUnit), $this.NumericAlertString($CritNum, $Operator, $CritFamily, $CritUnit)));
        }

        # When percent thresholds are in play, every message shows the value's share
        # of the base value; each percent threshold shows its own percent token.
        [bool]$ShowPercent    = ($WarnPercent -ne '') -or ($CritPercent -ne '');
        [string]$ValueDisplay = $this.FormatValueDisplay($Numeric, $ValueFamily, $ValueUnit, $ShowPercent);

        # Result fields carry the resolved base-unit numbers; byte thresholds render as
        # whole bytes (percent thresholds inherit the base value's family).
        [string]$ResultFamily = $ValueFamily;
        if ([string]::IsNullOrEmpty($ResultFamily)) {
            $ResultFamily = $this.BaseFamily;
        }

        [object]$WarnOut = $null;
        [object]$CritOut = $null;
        if ($WarnSet) {
            $WarnOut = [IcingaThresholdRange]::RoundBaseValue($WarnNum, $ResultFamily);
        }
        if ($CritSet) {
            $CritOut = [IcingaThresholdRange]::RoundBaseValue($CritNum, $ResultFamily);
        }

        if ($CritSet -and $this.CompareOp($Numeric, $CritNum, $Operator)) {
            return $this.BuildResult($InputOut, $WarnOut, $CritOut, 2, ("{0} is {1} threshold {2}" -f $ValueDisplay, $OperatorText, $this.FormatThresholdDisplay($CritNum, $CritFamily, $CritUnit, $CritPercent)));
        }

        if ($WarnSet -and $this.CompareOp($Numeric, $WarnNum, $Operator)) {
            return $this.BuildResult($InputOut, $WarnOut, $CritOut, 1, ("{0} is {1} threshold {2}" -f $ValueDisplay, $OperatorText, $this.FormatThresholdDisplay($WarnNum, $WarnFamily, $WarnUnit, $WarnPercent)));
        }

        return $this.BuildResult($InputOut, $WarnOut, $CritOut, 0, ("{0} is ok" -f $ValueDisplay));
    }

    <#
    .SYNOPSIS
    Evaluate a value against the thresholds as string patterns

    .DESCRIPTION
    Shared string comparison used by CheckMatch, CheckNotMatch, CheckLike,
    CheckNotLike, CheckEqual and CheckNotEqual. Treats the value as a string and the
    warning and critical thresholds as regex, wildcard or literal-equality patterns as
    the operator dictates, with critical taking precedence over warning. An invalid
    pattern or a null value returns an UNKNOWN result with an explanatory message.

    .PARAMETER Value
    | Name  | Type          | Description                     | Default |
    |-------|---------------|---------------------------------|---------|
    | Value | System.Object | Value to test as a string.      |         |

    .PARAMETER Operator
    | Name     | Type          | Description                                            | Default |
    |----------|---------------|--------------------------------------------------------|---------|
    | Operator | System.String | One of 'match', 'notmatch', 'like', 'notlike', 'eq' or 'ne'. |         |

    .PARAMETER OperatorText
    | Name         | Type          | Description                              | Default |
    |--------------|---------------|------------------------------------------|---------|
    | OperatorText | System.String | Human-readable operator for the message. |         |

    .OUTPUTS
    IcingaThresholdResult — The evaluation result.

    .EXAMPLE
    PS> $this.CompareString('error', 'match', 'matches')

    .NOTES
    Internal helper. An unset threshold is skipped (never raises its state).
    #>
    hidden [IcingaThresholdResult] CompareString([object]$Value, [string]$Operator, [string]$OperatorText)
    {
        if ($null -eq $Value) {
            return $this.BuildResult($null, $this.Warning, $this.Critical, 3, 'the value is null and cannot be compared as a string');
        }

        [string]$Text  = [string]$Value;
        [bool]$WarnSet = -not [string]::IsNullOrEmpty($this.Warning);
        [bool]$CritSet = -not [string]::IsNullOrEmpty($this.Critical);

        # The regex operators reject a syntactically invalid pattern up front with a
        # clean, operator-facing message so the raw .NET regex-parser error never
        # leaks into the plugin output. Critical is validated first to mirror its
        # precedence over the warning threshold.
        if ($Operator -eq 'match' -or $Operator -eq 'notmatch') {
            if ($CritSet -and -not $this.IsValidRegex($this.Critical)) {
                return $this.BuildResult($Text, $this.Warning, $this.Critical, 3, ("The critical pattern '{0}' is not a valid regular expression" -f $this.Critical));
            }
            if ($WarnSet -and -not $this.IsValidRegex($this.Warning)) {
                return $this.BuildResult($Text, $this.Warning, $this.Critical, 3, ("The warning pattern '{0}' is not a valid regular expression" -f $this.Warning));
            }
        }

        if ($WarnSet -and $CritSet -and $this.PatternWarningMasked($Operator)) {
            return $this.BuildResult($Text, $this.Warning, $this.Critical, 3, ("Check can never reach [WARNING]-State if warning is '{0} {1}' and critical is '{2} {3}'" -f $OperatorText, $this.Warning, $OperatorText, $this.Critical));
        }

        try {
            if ($CritSet -and $this.MatchOp($Text, $this.Critical, $Operator)) {
                return $this.BuildResult($Text, $this.Warning, $this.Critical, 2, ("'{0}' {1} pattern '{2}'" -f $Text, $OperatorText, $this.Critical));
            }

            if ($WarnSet -and $this.MatchOp($Text, $this.Warning, $Operator)) {
                return $this.BuildResult($Text, $this.Warning, $this.Critical, 1, ("'{0}' {1} pattern '{2}'" -f $Text, $OperatorText, $this.Warning));
            }
        } catch {
            return $this.BuildResult($Text, $this.Warning, $this.Critical, 3, ("the comparison pattern is not valid: {0}" -f $_.Exception.Message));
        }

        return $this.BuildResult($Text, $this.Warning, $this.Critical, 0, ("'{0}' is ok" -f $Text));
    }

    <#
    .SYNOPSIS
    Apply a numeric comparison operator

    .DESCRIPTION
    Compares a value against a threshold using the given operator and returns
    whether the comparison is true.

    .PARAMETER Value
    | Name  | Type          | Description                   | Default |
    |-------|---------------|-------------------------------|---------|
    | Value | System.Double | Resolved measured value.      |         |

    .PARAMETER Threshold
    | Name      | Type          | Description                   | Default |
    |-----------|---------------|-------------------------------|---------|
    | Threshold | System.Double | Resolved threshold value.     |         |

    .PARAMETER Operator
    | Name     | Type          | Description                                    | Default |
    |----------|---------------|------------------------------------------------|---------|
    | Operator | System.String | Comparison operator: 'gt', 'ge', 'lt' or 'le'. |         |

    .OUTPUTS
    System.Boolean — Result of the comparison.

    .EXAMPLE
    PS> $this.CompareOp(950, 900, 'gt')

    .NOTES
    Internal helper.
    #>
    hidden [bool] CompareOp([double]$Value, [double]$Threshold, [string]$Operator)
    {
        if ($Operator -eq 'gt') {
            return ($Value -gt $Threshold);
        }
        if ($Operator -eq 'ge') {
            return ($Value -ge $Threshold);
        }
        if ($Operator -eq 'lt') {
            return ($Value -lt $Threshold);
        }
        if ($Operator -eq 'le') {
            return ($Value -le $Threshold);
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Apply a string pattern comparison operator

    .DESCRIPTION
    Compares a string value against a pattern using regex (match/notmatch) or
    wildcard (like/notlike) semantics and returns whether the comparison is true.

    .PARAMETER Value
    | Name  | Type          | Description                | Default |
    |-------|---------------|----------------------------|---------|
    | Value | System.String | Value to test.             |         |

    .PARAMETER Pattern
    | Name    | Type          | Description                | Default |
    |---------|---------------|----------------------------|---------|
    | Pattern | System.String | Regex or wildcard pattern. |         |

    .PARAMETER Operator
    | Name     | Type          | Description                                        | Default |
    |----------|---------------|----------------------------------------------------|---------|
    | Operator | System.String | One of 'match', 'notmatch', 'like', 'notlike', 'eq' or 'ne'. |         |

    .OUTPUTS
    System.Boolean — Result of the comparison.

    .EXAMPLE
    PS> $this.MatchOp('error', '^err', 'match')

    .NOTES
    Internal helper. May throw on an invalid regex; callers guard with try/catch.
    #>
    hidden [bool] MatchOp([string]$Value, [string]$Pattern, [string]$Operator)
    {
        if ($Operator -eq 'match') {
            return ($Value -match $Pattern);
        }
        if ($Operator -eq 'notmatch') {
            return ($Value -notmatch $Pattern);
        }
        if ($Operator -eq 'like') {
            return ($Value -like $Pattern);
        }
        if ($Operator -eq 'notlike') {
            return ($Value -notlike $Pattern);
        }
        if ($Operator -eq 'eq') {
            return ($Value -eq $Pattern);
        }
        if ($Operator -eq 'ne') {
            return ($Value -ne $Pattern);
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Determine whether a pattern is a valid regular expression

    .DESCRIPTION
    Tries to compile the given pattern as a .NET regular expression and reports
    whether it is syntactically valid. The regex comparison operators use this to
    reject an invalid pattern up front with a clean, operator-facing message instead
    of surfacing the raw .NET regex-parser exception text. A wildcard-style pattern
    such as '*or*' is a common invalid regex here, since '*' is a quantifier with
    nothing to quantify; such patterns belong to the '-like' comparisons instead.

    .PARAMETER Pattern
    | Name    | Type          | Description                      | Default |
    |---------|---------------|----------------------------------|---------|
    | Pattern | System.String | Pattern to validate as a regex.  |         |

    .OUTPUTS
    System.Boolean — $true when the pattern compiles as a regex, otherwise $false.

    .EXAMPLE
    PS> $this.IsValidRegex('^err')

    .NOTES
    Internal helper. The compiled instance is only used for validation and discarded.
    #>
    hidden [bool] IsValidRegex([string]$Pattern)
    {
        try {
            [void][regex]::new($Pattern);
            return $true;
        } catch {
            return $false;
        }
    }

    <#
    .SYNOPSIS
    Build a result object and stamp the base value when one is set

    .DESCRIPTION
    Central factory for every IcingaThresholdResult this class returns. It creates
    the result from the measured value, the warning and critical thresholds, the
    plugin state and the output message, and — when the threshold was created with a
    valid base value — additionally records that resolved base (its maximum) in
    BaseValue so callers see it alongside WarningValue and CriticalValue.

    .PARAMETER InputValue
    | Name       | Type          | Description                             | Default |
    |------------|---------------|-----------------------------------------|---------|
    | InputValue | System.Object | Measured value for the result field.    |         |

    .PARAMETER WarningValue
    | Name         | Type          | Description                           | Default |
    |--------------|---------------|---------------------------------------|---------|
    | WarningValue | System.Object | Warning threshold field, or $null.    |         |

    .PARAMETER CriticalValue
    | Name          | Type          | Description                          | Default |
    |---------------|---------------|--------------------------------------|---------|
    | CriticalValue | System.Object | Critical threshold field, or $null.  |         |

    .PARAMETER StatusCode
    | Name       | Type         | Description                                        | Default |
    |------------|--------------|----------------------------------------------------|---------|
    | StatusCode | System.Int32 | Icinga plugin state: 0 OK, 1 WARN, 2 CRIT, 3 UNKNOWN.|       |

    .PARAMETER Output
    | Name   | Type          | Description                        | Default |
    |--------|---------------|------------------------------------|---------|
    | Output | System.String | Human-readable result description. |         |

    .OUTPUTS
    IcingaThresholdResult — The configured result, with BaseValue set when a base
    value is available.

    .EXAMPLE
    PS> $this.BuildResult(100, 20, 40, 2, '100 (50%) is greater than threshold 40 (20%)')

    .NOTES
    Internal helper. BaseValue stays $null when no valid base value was supplied.
    #>
    hidden [IcingaThresholdResult] BuildResult([object]$InputValue, [object]$WarningValue, [object]$CriticalValue, [int]$StatusCode, [string]$Output)
    {
        [IcingaThresholdResult]$Result = [IcingaThresholdResult]::new($InputValue, $WarningValue, $CriticalValue, $StatusCode, $Output);

        if ($this.HasBaseValue -and $this.BaseValid) {
            $Result.BaseValue = [IcingaThresholdRange]::RoundBaseValue($this.Maximum, $this.BaseFamily);
        }

        return $Result;
    }

    <#
    .SYNOPSIS
    Build the message for a value that exceeds the base value

    .DESCRIPTION
    Composes the UNKNOWN message emitted when a measured value is greater than the
    base value. The value and the base value are both rendered in their own unit and
    followed by their resolved base-unit form in parentheses (for example
    '1000MB (1000000000B)'). The parenthetical is omitted whenever it would merely
    repeat the rendered form — a plain number, or a value already given in the base
    unit — so no redundant '(…)' is shown.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Object | Original measured value as supplied.     |         |

    .PARAMETER InputOut
    | Name     | Type          | Description                                     | Default |
    |----------|---------------|-------------------------------------------------|---------|
    | InputOut | System.String | Value resolved to its base-unit form (with B/s).|         |

    .PARAMETER ValueFamily
    | Name        | Type          | Description                                  | Default |
    |-------------|---------------|----------------------------------------------|---------|
    | ValueFamily | System.String | The value's unit family, '' for a plain number.|       |

    .OUTPUTS
    System.String — The formatted "cannot be greater than the BaseValue" message.

    .EXAMPLE
    PS> $this.DescribeBaseValueExceeded('10GB', '10000000000B', 'Data')

    .NOTES
    Internal helper. The base value is formatted in the unit it was supplied in.
    #>
    hidden [string] DescribeBaseValueExceeded([object]$Value, [string]$InputOut, [string]$ValueFamily)
    {
        [string]$BaseText = [IcingaThresholdRange]::FormatBest($this.Maximum, $this.BaseFamily, $this.BaseUnit);
        [string]$BaseFull = [IcingaThresholdRange]::FormatBase($this.Maximum, $this.BaseFamily);
        if ($BaseText -ne $BaseFull) {
            $BaseText = ("{0} ({1})" -f $BaseText, $BaseFull);
        }

        if ([string]::IsNullOrEmpty($ValueFamily)) {
            return ("The value '{0}' cannot be greater than the BaseValue {1}" -f $Value, $BaseText);
        }

        return ("The value '{0}' ({1}) cannot be greater than the BaseValue {2}" -f $Value, $InputOut, $BaseText);
    }

    <#
    .SYNOPSIS
    Express a measured value as a percentage of the base value

    .DESCRIPTION
    Computes the value's share of the base value (Maximum) as 'value / Maximum * 100'
    and formats it with the invariant '0.##' pattern (at most two decimals, trailing
    zeros trimmed). Returns '' when there is no usable base value, so callers omit the
    percentage instead of dividing by zero.

    .PARAMETER Value
    | Name  | Type          | Description                                   | Default |
    |-------|---------------|-----------------------------------------------|---------|
    | Value | System.Double | Measured value in base units.                 |         |

    .OUTPUTS
    System.String — The percentage number without a sign, e.g. '50', or '' when unset.

    .EXAMPLE
    PS> $this.PercentOf(100)

    .NOTES
    Internal helper. Only meaningful when a base value has been resolved.
    #>
    hidden [string] PercentOf([double]$Value)
    {
        if (-not ($this.HasBaseValue -and $this.BaseValid) -or $this.Maximum -eq 0) {
            return '';
        }

        [decimal]$Percent = ([decimal]$Value / [decimal]$this.Maximum) * 100;
        return ([System.Math]::Round($Percent, 2)).ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture);
    }

    <#
    .SYNOPSIS
    Render a measured value for an output message, optionally with its percentage

    .DESCRIPTION
    Renders the value in its original unit through FormatBest and, when percentages
    are in play (ShowPercent) and a base value is available, appends the value's
    share of the base value as ' (<percent>%)'. Used for the value part of every
    numeric comparison message so a percent-driven check reads '100 (50%)'.

    .PARAMETER Value
    | Name  | Type          | Description                          | Default |
    |-------|---------------|--------------------------------------|---------|
    | Value | System.Double | Measured value in base units.        |         |

    .PARAMETER Family
    | Name   | Type          | Description                                | Default |
    |--------|---------------|--------------------------------------------|---------|
    | Family | System.String | The value's resolved unit family, '' none. |         |

    .PARAMETER Unit
    | Name | Type          | Description                              | Default |
    |------|---------------|------------------------------------------|---------|
    | Unit | System.String | The value's original unit token, '' none.|         |

    .PARAMETER ShowPercent
    | Name        | Type           | Description                                        | Default |
    |-------------|----------------|----------------------------------------------------|---------|
    | ShowPercent | System.Boolean | Whether to append the value's percentage of base.  |         |

    .OUTPUTS
    System.String — The value display, e.g. '100 (50%)' or '100'.

    .EXAMPLE
    PS> $this.FormatValueDisplay(100, '', '', $true)

    .NOTES
    Internal helper. The percentage is omitted when PercentOf returns ''.
    #>
    hidden [string] FormatValueDisplay([double]$Value, [string]$Family, [string]$Unit, [bool]$ShowPercent)
    {
        [string]$Best = [IcingaThresholdRange]::FormatBest($Value, $Family, $Unit);

        if (-not $ShowPercent) {
            return $Best;
        }

        [string]$Percent = $this.PercentOf($Value);
        if ([string]::IsNullOrEmpty($Percent)) {
            return $Best;
        }

        return ("{0} ({1}%)" -f $Best, $Percent);
    }

    <#
    .SYNOPSIS
    Render a threshold for an output message, optionally with its percentage

    .DESCRIPTION
    Renders a resolved threshold value for a message. A percent threshold shows its
    numeric part in the base value's unit followed by the original percent token,
    for example '40 (20%)' or '25.45GiB (10%)'. An absolute threshold renders in its
    own unit through FormatBest, exactly as before.

    .PARAMETER Value
    | Name  | Type          | Description                            | Default |
    |-------|---------------|----------------------------------------|---------|
    | Value | System.Double | Resolved threshold value in base units.|         |

    .PARAMETER Family
    | Name   | Type          | Description                                    | Default |
    |--------|---------------|------------------------------------------------|---------|
    | Family | System.String | The threshold's resolved unit family, '' none. |         |

    .PARAMETER Unit
    | Name | Type          | Description                                  | Default |
    |------|---------------|----------------------------------------------|---------|
    | Unit | System.String | The threshold's original unit token, '' none.|         |

    .PARAMETER Percent
    | Name    | Type          | Description                                             | Default |
    |---------|---------------|---------------------------------------------------------|---------|
    | Percent | System.String | Original percent token when the threshold is a percent. |         |

    .OUTPUTS
    System.String — The threshold display, e.g. '40 (20%)' or '10MB'.

    .EXAMPLE
    PS> $this.FormatThresholdDisplay(40, '', '', '20%')

    .NOTES
    Internal helper. A percent threshold's numeric part uses the base value's unit.
    #>
    hidden [string] FormatThresholdDisplay([double]$Value, [string]$Family, [string]$Unit, [string]$Percent)
    {
        if (-not [string]::IsNullOrEmpty($Percent)) {
            return ("{0} ({1})" -f [IcingaThresholdRange]::FormatBest($Value, $this.BaseFamily, $this.BaseUnit), $Percent);
        }

        return [IcingaThresholdRange]::FormatBest($Value, $Family, $Unit);
    }

    <#
    .SYNOPSIS
    Resolve a numeric or percent threshold into a base-unit value

    .DESCRIPTION
    Resolves a single numeric threshold. A percentage is resolved against the base
    value (failing when none is available); everything else is delegated to
    TryResolveValue (plain number, numeric string or unit string). On failure a
    user-friendly reason is written to the ErrorMessage reference.

    .PARAMETER Token
    | Name  | Type          | Description                     | Default |
    |-------|---------------|---------------------------------|---------|
    | Token | System.String | Threshold token to resolve.     |         |

    .PARAMETER Result
    | Name   | Type                                     | Description                          | Default |
    |--------|------------------------------------------|--------------------------------------|---------|
    | Result | System.Management.Automation.PSReference | Receives the resolved base value.    |         |

    .PARAMETER ErrorMessage
    | Name         | Type                                     | Description                       | Default |
    |--------------|------------------------------------------|-----------------------------------|---------|
    | ErrorMessage | System.Management.Automation.PSReference | Receives a reason on failure.     |         |

    .PARAMETER Family
    | Name   | Type                                     | Description                                            | Default |
    |--------|------------------------------------------|--------------------------------------------------------|---------|
    | Family | System.Management.Automation.PSReference | Receives the unit family ('Data'/'Time'), '' when none.|         |

    .PARAMETER Unit
    | Name | Type                                     | Description                                     | Default |
    |------|------------------------------------------|-------------------------------------------------|---------|
    | Unit | System.Management.Automation.PSReference | Receives the original unit token, '' when none. |         |

    .PARAMETER PercentToken
    | Name         | Type                                     | Description                                        | Default |
    |--------------|------------------------------------------|----------------------------------------------------|---------|
    | PercentToken | System.Management.Automation.PSReference | Receives the original percent token, '' when none. |         |

    .OUTPUTS
    System.Boolean — $true on success, $false when the token could not be resolved.

    .EXAMPLE
    PS> $this.TryResolveThreshold('90%', [ref]$value, [ref]$reason, [ref]$family, [ref]$unit, [ref]$percent)

    .NOTES
    Internal helper. Percent thresholds require a resolved base value.
    #>
    hidden [bool] TryResolveThreshold([string]$Token, [ref]$Result, [ref]$ErrorMessage, [ref]$Family, [ref]$Unit, [ref]$PercentToken)
    {
        $Family.Value       = '';
        $Unit.Value         = '';
        $PercentToken.Value = '';

        [string]$Trimmed = $Token.Trim();

        $PercentMatch = [IcingaThresholds]::PercentRegex.Match($Trimmed);
        if ($PercentMatch.Success) {
            if (-not ($this.HasBaseValue -and $this.BaseValid)) {
                $ErrorMessage.Value = ("the percent threshold '{0}' requires a base value" -f $Token);
                return $false;
            }

            [decimal]$Percent = 0;
            if (-not [decimal]::TryParse($PercentMatch.Groups[1].Value.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Percent)) {
                $ErrorMessage.Value = ("the percent threshold '{0}' is not valid" -f $Token);
                return $false;
            }

            $Result.Value       = [double](($Percent / 100) * [decimal]$this.Maximum);
            $PercentToken.Value = $Trimmed;
            return $true;
        }

        [double]$Numeric = 0;
        if ($this.TryResolveValue($Trimmed, [ref]$Numeric, $Family, $Unit)) {
            $Result.Value = $Numeric;
            return $true;
        }

        $ErrorMessage.Value = ("the threshold '{0}' is not a valid number or '<number><unit>' value" -f $Token);
        return $false;
    }

    <#
    .SYNOPSIS
    Resolve a measured value or base value into a numeric base-unit value

    .DESCRIPTION
    Convenience overload that resolves a value into its numeric base-unit form when
    the caller does not need the unit family or token. Numeric input is used
    directly; a plain numeric string is parsed with the invariant culture (a comma
    is accepted as the decimal separator); a string carrying a unit suffix is
    normalized to its base unit through IcingaUnit. Null, empty or otherwise
    uninterpretable input fails. Delegates to the four-argument overload.

    .PARAMETER Value
    | Name  | Type          | Description                 | Default |
    |-------|---------------|-----------------------------|---------|
    | Value | System.Object | Value to resolve.           |         |

    .PARAMETER Result
    | Name   | Type                                     | Description                            | Default |
    |--------|------------------------------------------|----------------------------------------|---------|
    | Result | System.Management.Automation.PSReference | Receives the resolved base-unit value. |         |

    .OUTPUTS
    System.Boolean — $true on success, $false when the value cannot be resolved.

    .EXAMPLE
    PS> $this.TryResolveValue('10GB', [ref]$value)

    .NOTES
    Internal helper. Delegates to the reporting overload; used where the unit family
    and token are not needed (for example base value resolution in Initialize).
    #>
    hidden [bool] TryResolveValue([object]$Value, [ref]$Result)
    {
        [string]$Family = '';
        [string]$Unit   = '';
        return $this.TryResolveValue($Value, $Result, [ref]$Family, [ref]$Unit);
    }

    <#
    .SYNOPSIS
    Resolve a value into a base-unit number and report its unit family and token

    .DESCRIPTION
    Behaves like the two-argument overload but additionally reports, for a value
    carrying a unit suffix, the resolved unit family ('Data'/'Time') and the
    normalized original unit token. Plain numbers and numeric strings resolve with
    an empty family and token so they render without a unit.

    .PARAMETER Value
    | Name  | Type          | Description                 | Default |
    |-------|---------------|-----------------------------|---------|
    | Value | System.Object | Value to resolve.           |         |

    .PARAMETER Result
    | Name   | Type                                     | Description                            | Default |
    |--------|------------------------------------------|----------------------------------------|---------|
    | Result | System.Management.Automation.PSReference | Receives the resolved base-unit value. |         |

    .PARAMETER Family
    | Name   | Type                                     | Description                                            | Default |
    |--------|------------------------------------------|--------------------------------------------------------|---------|
    | Family | System.Management.Automation.PSReference | Receives the unit family ('Data'/'Time'), '' when none.|         |

    .PARAMETER Unit
    | Name | Type                                     | Description                                     | Default |
    |------|------------------------------------------|-------------------------------------------------|---------|
    | Unit | System.Management.Automation.PSReference | Receives the original unit token, '' when none. |         |

    .OUTPUTS
    System.Boolean — $true on success, $false when the value cannot be resolved.

    .EXAMPLE
    PS> $this.TryResolveValue('10GB', [ref]$value, [ref]$family, [ref]$unit)

    .NOTES
    Internal helper. The IcingaUnit reference is used inside the method body so the
    kernel's alphabetical class ordering resolves the type at runtime.
    #>
    hidden [bool] TryResolveValue([object]$Value, [ref]$Result, [ref]$Family, [ref]$Unit)
    {
        $Family.Value = '';
        $Unit.Value   = '';

        if ($null -eq $Value) {
            return $false;
        }

        # A numeric type is already a base-unit value and needs no parsing.
        if ($Value -isnot [string]) {
            try {
                $Result.Value = [double]$Value;
                return $true;
            } catch {
                return $false;
            }
        }

        [string]$Text = ([string]$Value).Trim();
        if ([string]::IsNullOrEmpty($Text)) {
            return $false;
        }

        # A plain number is taken as-is in the smallest/base unit.
        [double]$Parsed = 0;
        if ([double]::TryParse($Text.Replace(',', '.'), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Parsed)) {
            $Result.Value = $Parsed;
            return $true;
        }

        # Otherwise it must be a '<number><unit>' value; normalize it to base units.
        $UnitValue = [IcingaUnit]::new($Text, $null, $null, $false);
        if ($UnitValue.Success) {
            $Result.Value = $UnitValue.BaseValue;
            $Family.Value = $UnitValue.Family;
            $Unit.Value   = $UnitValue.InputUnit;
            return $true;
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Translate a range parse return code into a user-friendly reason

    .DESCRIPTION
    Maps the semantic ReturnCode of a failed IcingaThresholdRange parse into a
    short, human-readable explanation for the result Output.

    .PARAMETER Code
    | Name | Type          | Description                          | Default |
    |------|---------------|--------------------------------------|---------|
    | Code | System.String | ReturnCode from IcingaThresholdRange.|         |

    .PARAMETER Threshold
    | Name      | Type          | Description                        | Default |
    |-----------|---------------|------------------------------------|---------|
    | Threshold | System.String | The offending threshold string.    |         |

    .OUTPUTS
    System.String — A user-friendly explanation.

    .EXAMPLE
    PS> $this.RangeError('IcingaThresholdStartGreaterEnd', '20:10')

    .NOTES
    Internal helper.
    #>
    hidden [string] RangeError([string]$Code, [string]$Threshold)
    {
        if ($Code -eq 'IcingaThresholdMissingBaseValue') {
            return ("the percent threshold '{0}' requires a base value" -f $Threshold);
        }

        if ($Code -eq 'IcingaThresholdStartGreaterEnd') {
            return ("the range '{0}' has a lower bound greater than its upper bound" -f $Threshold);
        }

        return ("the threshold '{0}' is not a valid range" -f $Threshold);
    }

    <#
    .SYNOPSIS
    Describe, direction- and bound-precise, why a range raised an alert

    .DESCRIPTION
    Builds the short output message for a range that is in its alert region: for a
    normal range whether the value fell below the lower bound or rose above the
    upper bound (naming the crossed bound), and for an inverted range that the value
    lies within the bounds. A percent bound additionally shows its percent token.

    .PARAMETER Value
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Value | System.Double | Measured value that raised the alert.    |         |

    .PARAMETER ValueDisplay
    | Name         | Type          | Description                                                    | Default |
    |--------------|---------------|----------------------------------------------------------------|---------|
    | ValueDisplay | System.String | Measured value pre-rendered for display (unit and percentage). |         |

    .PARAMETER Range
    | Name  | Type                 | Description                          | Default |
    |-------|----------------------|--------------------------------------|---------|
    | Range | IcingaThresholdRange | The range that is in its alert region.|        |

    .OUTPUTS
    System.String — The short, human-readable alert description.

    .EXAMPLE
    PS> $this.DescribeRangeAlert(100, '100 (50%)', $range)

    .NOTES
    Internal helper. Only called when the range is actually in alert.
    #>
    hidden [string] DescribeRangeAlert([double]$Value, [string]$ValueDisplay, [IcingaThresholdRange]$Range)
    {
        [string]$StartBest = $this.FormatThresholdDisplay($Range.Start, $Range.Family, $Range.StartUnit, $Range.StartPercent);
        [string]$EndBest   = $this.FormatThresholdDisplay($Range.End, $Range.Family, $Range.EndUnit, $Range.EndPercent);

        if ($Range.Inverted) {
            return ("{0} is within range {1} to {2}" -f $ValueDisplay, $StartBest, $EndBest);
        }

        if ($Value -lt $Range.Start) {
            return ("{0} is lower than threshold {1}" -f $ValueDisplay, $StartBest);
        }

        return ("{0} is greater than threshold {1}" -f $ValueDisplay, $EndBest);
    }

    <#
    .SYNOPSIS
    Determine whether a numeric warning threshold can never win against critical

    .DESCRIPTION
    For a numeric comparison, decides whether every value that would raise the
    warning threshold would also raise the critical threshold (critical always
    preempts warning), which makes the warning state unreachable. For 'gt'/'ge' that
    is the case when warning is greater than or equal to critical; for 'lt'/'le'
    when warning is lower than or equal to critical.

    .PARAMETER WarningValue
    | Name         | Type          | Description                      | Default |
    |--------------|---------------|----------------------------------|---------|
    | WarningValue | System.Double | Resolved warning threshold.      |         |

    .PARAMETER CriticalValue
    | Name          | Type          | Description                     | Default |
    |---------------|---------------|---------------------------------|---------|
    | CriticalValue | System.Double | Resolved critical threshold.    |         |

    .PARAMETER Operator
    | Name     | Type          | Description                                    | Default |
    |----------|---------------|------------------------------------------------|---------|
    | Operator | System.String | Comparison operator: 'gt', 'ge', 'lt' or 'le'. |         |

    .OUTPUTS
    System.Boolean — $true when the warning state is unreachable.

    .EXAMPLE
    PS> $this.NumericWarningMasked(90, 80, 'gt')

    .NOTES
    Internal helper. Only meaningful when both thresholds are set.
    #>
    hidden [bool] NumericWarningMasked([double]$WarningValue, [double]$CriticalValue, [string]$Operator)
    {
        if ($Operator -eq 'gt' -or $Operator -eq 'ge') {
            return ($WarningValue -ge $CriticalValue);
        }

        if ($Operator -eq 'lt' -or $Operator -eq 'le') {
            return ($WarningValue -le $CriticalValue);
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Render a numeric threshold's alert condition as a human-readable comparison

    .DESCRIPTION
    Translates a resolved numeric threshold and its comparison operator into the
    plain condition under which it raises an alert: 'gt' to '> value', 'ge' to
    '>= value', 'lt' to '< value' and 'le' to '<= value'. The number uses the
    invariant culture.

    .PARAMETER Value
    | Name  | Type          | Description                  | Default |
    |-------|---------------|------------------------------|---------|
    | Value | System.Double | Resolved threshold value.    |         |

    .PARAMETER Operator
    | Name     | Type          | Description                                    | Default |
    |----------|---------------|------------------------------------------------|---------|
    | Operator | System.String | Comparison operator: 'gt', 'ge', 'lt' or 'le'. |         |

    .PARAMETER Family
    | Name   | Type          | Description                                     | Default |
    |--------|---------------|-------------------------------------------------|---------|
    | Family | System.String | Resolved unit family ('Data'/'Time'), '' none.  |         |

    .PARAMETER Unit
    | Name | Type          | Description                                 | Default |
    |------|---------------|---------------------------------------------|---------|
    | Unit | System.String | Original unit token to render, '' when none.|         |

    .OUTPUTS
    System.String — The alert condition, e.g. '> 90'.

    .EXAMPLE
    PS> $this.NumericAlertString(90, 'gt', '', '')

    .NOTES
    Internal helper for the unreachable-warning message.
    #>
    hidden [string] NumericAlertString([double]$Value, [string]$Operator, [string]$Family, [string]$Unit)
    {
        [string]$Number = [IcingaThresholdRange]::FormatBest($Value, $Family, $Unit);

        if ($Operator -eq 'gt') {
            return ("> {0}" -f $Number);
        }
        if ($Operator -eq 'ge') {
            return (">= {0}" -f $Number);
        }
        if ($Operator -eq 'lt') {
            return ("< {0}" -f $Number);
        }
        if ($Operator -eq 'le') {
            return ("<= {0}" -f $Number);
        }

        return $Number;
    }

    <#
    .SYNOPSIS
    Determine which plugin state a warning/critical range pair can never reach

    .DESCRIPTION
    Detects two misconfigurations of a warning and critical range pair by testing
    representative points derived from the finite bounds of both ranges (each bound,
    each midpoint between consecutive bounds, and a point just below the smallest and
    just above the largest). Returns 'WARNING' when the warning range can fire yet is
    always preempted by critical (the WARNING state is unreachable), 'OK' when no
    value escapes both ranges (the OK state is unreachable), or '' when the pair is
    sound. WARNING takes precedence over OK. Works for normal, inverted and
    open-ended ranges.

    .PARAMETER WarningRange
    | Name         | Type                 | Description                 | Default |
    |--------------|----------------------|-----------------------------|---------|
    | WarningRange | IcingaThresholdRange | Parsed warning range.       |         |

    .PARAMETER CriticalRange
    | Name          | Type                 | Description                | Default |
    |---------------|----------------------|----------------------------|---------|
    | CriticalRange | IcingaThresholdRange | Parsed critical range.     |         |

    .OUTPUTS
    System.String — 'WARNING', 'OK', or '' when the pair is sound.

    .EXAMPLE
    PS> $this.RangeUnreachableState($warnRange, $critRange)

    .NOTES
    Internal helper. Only meaningful when both ranges are set.
    #>
    hidden [string] RangeUnreachableState([IcingaThresholdRange]$WarningRange, [IcingaThresholdRange]$CriticalRange)
    {
        [System.Collections.Generic.List[double]]$Bounds = [System.Collections.Generic.List[double]]::new();
        foreach ($Bound in @($WarningRange.Start, $WarningRange.End, $CriticalRange.Start, $CriticalRange.End)) {
            if (-not [double]::IsInfinity($Bound)) {
                $Bounds.Add($Bound);
            }
        }

        [System.Collections.Generic.List[double]]$Candidates = [System.Collections.Generic.List[double]]::new();
        if ($Bounds.Count -eq 0) {
            $Candidates.Add(0);
        } else {
            [double[]]$Sorted = $Bounds.ToArray();
            [array]::Sort($Sorted);

            $Candidates.Add($Sorted[0] - 1);
            for ($i = 0; $i -lt $Sorted.Length; $i++) {
                $Candidates.Add($Sorted[$i]);
                if ($i -lt ($Sorted.Length - 1)) {
                    $Candidates.Add(($Sorted[$i] + $Sorted[$i + 1]) / 2);
                }
            }
            $Candidates.Add($Sorted[$Sorted.Length - 1] + 1);
        }

        [bool]$WarnCanFire = $false;
        [bool]$WarnCanWin  = $false;
        [bool]$OkReachable = $false;
        foreach ($Point in $Candidates) {
            [bool]$WarnFires = $WarningRange.InAlertRange($Point);
            [bool]$CritFires = $CriticalRange.InAlertRange($Point);

            if ($WarnFires) {
                $WarnCanFire = $true;
            }
            if ($WarnFires -and -not $CritFires) {
                $WarnCanWin = $true;
            }
            if ((-not $WarnFires) -and (-not $CritFires)) {
                $OkReachable = $true;
            }
        }

        if ($WarnCanFire -and -not $WarnCanWin) {
            return 'WARNING';
        }
        if (-not $OkReachable) {
            return 'OK';
        }

        return '';
    }

    <#
    .SYNOPSIS
    Determine whether a string/pattern warning threshold can never win against critical

    .DESCRIPTION
    For a string comparison, decides whether every value that would raise the warning
    threshold would also raise the critical threshold, which makes the WARNING state
    unreachable because critical always preempts warning. Identical patterns (compared
    case-insensitively, matching the case-insensitive operators) always mask and are
    checked first. Beyond that, 'like' and 'notlike' use exact wildcard-language
    containment: for 'like' the warning language must be a subset of the critical
    language, for 'notlike' the reverse, because negation flips the direction. Full
    regex-language containment for 'match'/'notmatch' is not generally decidable, so it
    is decided only for plain-literal patterns (no regex metacharacters): because
    '-match' is an unanchored substring test, the warning language is contained in the
    critical language exactly when the critical literal occurs within the warning
    literal ('notmatch' flips the direction). Any pattern carrying regex metacharacters,
    and any other operator, mask only when the patterns are identical.

    .PARAMETER Operator
    | Name     | Type          | Description                                                  | Default |
    |----------|---------------|--------------------------------------------------------------|---------|
    | Operator | System.String | One of 'match', 'notmatch', 'like', 'notlike', 'eq' or 'ne'. |         |

    .OUTPUTS
    System.Boolean — $true when the warning state is unreachable, otherwise $false.

    .EXAMPLE
    PS> $this.PatternWarningMasked('like')

    .NOTES
    Internal helper. Only meaningful when both the warning and critical thresholds are
    set; the caller guards on that. Conservative: an undecidable case yields $false so a
    sound configuration is never falsely rejected.
    #>
    hidden [bool] PatternWarningMasked([string]$Operator)
    {
        # Identical patterns always mask, regardless of operator direction, and this
        # cheap check also covers wildcards the containment automaton declines (those
        # with a character class), so run it first.
        if ([string]::Equals($this.Warning, $this.Critical, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true;
        }

        if ($Operator -eq 'like') {
            return $this.WildcardSubset($this.Warning, $this.Critical);
        }

        if ($Operator -eq 'notlike') {
            return $this.WildcardSubset($this.Critical, $this.Warning);
        }

        if ($Operator -eq 'match') {
            return $this.RegexLiteralSubset($this.Warning, $this.Critical);
        }

        if ($Operator -eq 'notmatch') {
            return $this.RegexLiteralSubset($this.Critical, $this.Warning);
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Decide plain-literal regex containment for the warning-masking check

    .DESCRIPTION
    Decides whether L(Inner) is a subset of L(Outer) for the '-match' operator, i.e.
    whether every string that matches the Inner pattern also matches the Outer pattern,
    but only for plain-literal patterns. Because '-match' is an unanchored, case-
    insensitive substring search, a string matches a literal pattern exactly when it
    contains that literal; the Inner language is therefore contained in the Outer
    language exactly when the Outer literal occurs somewhere inside the Inner literal.
    Any pattern that carries a regex metacharacter is not a plain literal and is
    declined with $false so a sound configuration is never falsely rejected — general
    regex-language containment is not decided here.

    .PARAMETER Inner
    | Name  | Type          | Description                                          | Default |
    |-------|---------------|------------------------------------------------------|---------|
    | Inner | System.String | Pattern whose match language must be contained.      |         |

    .PARAMETER Outer
    | Name  | Type          | Description                                          | Default |
    |-------|---------------|------------------------------------------------------|---------|
    | Outer | System.String | Pattern that must contain the Inner match language.  |         |

    .OUTPUTS
    System.Boolean — $true when both patterns are plain literals and L(Inner) is a
    subset of L(Outer), otherwise $false.

    .EXAMPLE
    PS> $this.RegexLiteralSubset('fo', 'f')

    Returns $true because every string containing 'fo' also contains 'f'.

    .NOTES
    Internal helper. Case-insensitive to mirror the '-match' operator; the '#' and
    whitespace characters are treated as literal, matching the operator's default
    options.
    #>
    hidden [bool] RegexLiteralSubset([string]$Inner, [string]$Outer)
    {
        if ($Inner.IndexOfAny([IcingaThresholds]::RegexMetaChars) -ge 0 -or $Outer.IndexOfAny([IcingaThresholds]::RegexMetaChars) -ge 0) {
            return $false;
        }

        return ($Inner.IndexOf($Outer, [System.StringComparison]::OrdinalIgnoreCase) -ge 0);
    }

    <#
    .SYNOPSIS
    Decide whether every string matching one wildcard pattern also matches another

    .DESCRIPTION
    Exactly decides wildcard-language containment: whether L(Inner) is a subset of
    L(Outer), i.e. whether every string the Inner pattern matches is also matched by the
    Outer pattern. It builds the Outer pattern's non-deterministic automaton, then feeds
    the Inner pattern into it symbolically, tracking the set of Outer states reachable by
    any concrete string the Inner pattern can produce; containment holds when every one
    of those states is accepting. Matching mirrors PowerShell's '-like' operator: it is
    case-insensitive and supports the '*' (zero or more), '?' (exactly one) and backtick-
    escape wildcards. Character classes ('[...]') are not decided here; a pattern that
    contains one yields $false so a sound configuration is never falsely rejected.

    .PARAMETER Inner
    | Name  | Type          | Description                                            | Default |
    |-------|---------------|--------------------------------------------------------|---------|
    | Inner | System.String | Wildcard pattern whose language must be contained.     |         |

    .PARAMETER Outer
    | Name  | Type          | Description                                            | Default |
    |-------|---------------|--------------------------------------------------------|---------|
    | Outer | System.String | Wildcard pattern that must contain the Inner language. |         |

    .OUTPUTS
    System.Boolean — $true when L(Inner) is a subset of L(Outer), otherwise $false.

    .EXAMPLE
    PS> $this.WildcardSubset('*fo*', '*f*')

    Returns $true because every string containing 'fo' also contains 'f'.

    .NOTES
    Internal helper. The reduced 'minterm' alphabet consists of the outer pattern's
    literal characters plus one sentinel ('') standing for every other character, which
    keeps the state search finite while staying exact for the supported wildcards.
    #>
    hidden [bool] WildcardSubset([string]$Inner, [string]$Outer)
    {
        [string[]]$InnerKinds = @();
        [string[]]$InnerChars = @();
        [string[]]$OuterKinds = @();
        [string[]]$OuterChars = @();

        if (-not $this.TokenizeWildcard($Inner, [ref]$InnerKinds, [ref]$InnerChars)) {
            return $false;
        }
        if (-not $this.TokenizeWildcard($Outer, [ref]$OuterKinds, [ref]$OuterChars)) {
            return $false;
        }

        [int]$Accept = $OuterKinds.Length;

        # Minterm alphabet: every distinct character the outer pattern discriminates on,
        # plus one sentinel ('') that stands for any other character. All non-literal
        # characters drive identical outer transitions, so this stays exact.
        [System.Collections.Generic.HashSet[string]]$OuterLiterals = [System.Collections.Generic.HashSet[string]]::new();
        for ($i = 0; $i -lt $OuterKinds.Length; $i++) {
            if ($OuterKinds[$i] -eq 'lit') {
                [void]$OuterLiterals.Add($OuterChars[$i]);
            }
        }

        [System.Collections.Generic.List[string]]$Alphabet = [System.Collections.Generic.List[string]]::new();
        foreach ($Literal in $OuterLiterals) {
            $Alphabet.Add($Literal);
        }
        $Alphabet.Add('');

        # Reach: every outer state set reachable by some concrete string the inner
        # pattern can produce, keyed canonically so duplicates collapse.
        [System.Collections.Generic.Dictionary[string, int[]]]$Reach = [System.Collections.Generic.Dictionary[string, int[]]]::new();
        [int[]]$Start = $this.WildcardClosure(@(0), $OuterKinds);
        $Reach[$this.PosKey($Start)] = $Start;

        for ($t = 0; $t -lt $InnerKinds.Length; $t++) {
            [System.Collections.Generic.Dictionary[string, int[]]]$Next = [System.Collections.Generic.Dictionary[string, int[]]]::new();

            if ($InnerKinds[$t] -eq 'lit') {
                # A concrete literal maps to itself when the outer pattern knows it, else
                # to the sentinel that represents every other character.
                [string]$Symbol = '';
                if ($OuterLiterals.Contains($InnerChars[$t])) {
                    $Symbol = $InnerChars[$t];
                }

                foreach ($State in $Reach.Values) {
                    [int[]]$Moved = $this.WildcardStep($State, $Symbol, $OuterKinds, $OuterChars);
                    $Next[$this.PosKey($Moved)] = $Moved;
                }
            } elseif ($InnerKinds[$t] -eq 'any') {
                foreach ($State in $Reach.Values) {
                    foreach ($Symbol in $Alphabet) {
                        [int[]]$Moved = $this.WildcardStep($State, $Symbol, $OuterKinds, $OuterChars);
                        $Next[$this.PosKey($Moved)] = $Moved;
                    }
                }
            } else {
                # A star produces zero or more arbitrary characters: take the closure of
                # the current states under consuming any single character, repeatedly.
                foreach ($Pair in $Reach.GetEnumerator()) {
                    $Next[$Pair.Key] = $Pair.Value;
                }

                [System.Collections.Generic.Queue[int[]]]$Work = [System.Collections.Generic.Queue[int[]]]::new();
                foreach ($State in $Reach.Values) {
                    $Work.Enqueue($State);
                }

                while ($Work.Count -gt 0) {
                    [int[]]$State = $Work.Dequeue();
                    foreach ($Symbol in $Alphabet) {
                        [int[]]$Moved = $this.WildcardStep($State, $Symbol, $OuterKinds, $OuterChars);
                        [string]$Key = $this.PosKey($Moved);
                        if (-not $Next.ContainsKey($Key)) {
                            $Next[$Key] = $Moved;
                            $Work.Enqueue($Moved);
                        }
                    }
                }
            }

            $Reach = $Next;
        }

        # A single reachable non-accepting state means some inner string escapes the
        # outer pattern, so the inner language is not contained.
        foreach ($State in $Reach.Values) {
            if (-not $this.WildcardAccepts($State, $Accept)) {
                return $false;
            }
        }

        return $true;
    }

    <#
    .SYNOPSIS
    Tokenize a wildcard pattern into a linear list of match tokens

    .DESCRIPTION
    Splits a PowerShell wildcard pattern into parallel kind/character arrays used by the
    containment automaton. Each token is 'star' ('*', zero or more characters), 'any'
    ('?', exactly one character) or 'lit' (a single literal character, lower-cased so the
    comparison stays case-insensitive like '-like'); a backtick escapes the next
    character into a literal. A character class ('[...]') is not modelled and makes the
    method return $false so the caller treats the containment as undecidable.

    .PARAMETER Pattern
    | Name    | Type          | Description                        | Default |
    |---------|---------------|------------------------------------|---------|
    | Pattern | System.String | Wildcard pattern to tokenize.      |         |

    .PARAMETER Kinds
    | Name  | Type                                     | Description                                       | Default |
    |-------|------------------------------------------|---------------------------------------------------|---------|
    | Kinds | System.Management.Automation.PSReference | Receives the per-token kinds ('star'/'any'/'lit').|         |

    .PARAMETER Chars
    | Name  | Type                                     | Description                                          | Default |
    |-------|------------------------------------------|------------------------------------------------------|---------|
    | Chars | System.Management.Automation.PSReference | Receives the per-token literal character, '' if none.|         |

    .OUTPUTS
    System.Boolean — $true when the pattern was fully tokenized, $false when it contains
    an unsupported character class.

    .EXAMPLE
    PS> $this.TokenizeWildcard('*fo*', [ref]$kinds, [ref]$chars)

    .NOTES
    Internal helper. Literals are lower-cased so containment matches the case-insensitive
    behaviour of the '-like' operator.
    #>
    hidden [bool] TokenizeWildcard([string]$Pattern, [ref]$Kinds, [ref]$Chars)
    {
        [System.Collections.Generic.List[string]]$K = [System.Collections.Generic.List[string]]::new();
        [System.Collections.Generic.List[string]]$C = [System.Collections.Generic.List[string]]::new();

        [int]$i = 0;
        while ($i -lt $Pattern.Length) {
            [char]$Ch = $Pattern[$i];

            if ($Ch -eq '`') {
                # A backtick escapes the next character into a literal.
                if (($i + 1) -lt $Pattern.Length) {
                    $K.Add('lit');
                    $C.Add(([string]$Pattern[$i + 1]).ToLowerInvariant());
                    $i += 2;
                    continue;
                }

                $K.Add('lit');
                $C.Add(([string]$Ch).ToLowerInvariant());
                $i += 1;
                continue;
            }

            if ($Ch -eq '[') {
                return $false;
            }

            if ($Ch -eq '*') {
                $K.Add('star');
                $C.Add('');
                $i += 1;
                continue;
            }

            if ($Ch -eq '?') {
                $K.Add('any');
                $C.Add('');
                $i += 1;
                continue;
            }

            $K.Add('lit');
            $C.Add(([string]$Ch).ToLowerInvariant());
            $i += 1;
        }

        $Kinds.Value = $K.ToArray();
        $Chars.Value = $C.ToArray();
        return $true;
    }

    <#
    .SYNOPSIS
    Expand a set of wildcard-automaton positions over star epsilon transitions

    .DESCRIPTION
    Computes the epsilon-closure of a set of positions in the outer pattern's automaton:
    a 'star' token may be skipped without consuming a character, so every position on a
    star also reaches the following position. The closure is applied transitively until
    no new positions appear. Positions index the token list; the position equal to the
    token count is the accepting position.

    .PARAMETER Positions
    | Name      | Type          | Description                                  | Default |
    |-----------|---------------|----------------------------------------------|---------|
    | Positions | System.Int32[]| Positions to expand.                         |         |

    .PARAMETER Kinds
    | Name  | Type           | Description                                | Default |
    |-------|----------------|--------------------------------------------|---------|
    | Kinds | System.String[]| Token kinds of the outer pattern.          |         |

    .OUTPUTS
    System.Int32[] — The epsilon-closed set of positions.

    .EXAMPLE
    PS> $this.WildcardClosure(@(0), $outerKinds)

    .NOTES
    Internal helper for the wildcard containment automaton.
    #>
    hidden [int[]] WildcardClosure([int[]]$Positions, [string[]]$Kinds)
    {
        [System.Collections.Generic.HashSet[int]]$Set = [System.Collections.Generic.HashSet[int]]::new();
        [System.Collections.Generic.Queue[int]]$Queue = [System.Collections.Generic.Queue[int]]::new();

        foreach ($Position in $Positions) {
            if ($Set.Add($Position)) {
                $Queue.Enqueue($Position);
            }
        }

        while ($Queue.Count -gt 0) {
            [int]$Pos = $Queue.Dequeue();
            if ($Pos -lt $Kinds.Length -and $Kinds[$Pos] -eq 'star') {
                if ($Set.Add($Pos + 1)) {
                    $Queue.Enqueue($Pos + 1);
                }
            }
        }

        [int[]]$Result = [int[]]::new($Set.Count);
        $Set.CopyTo($Result);
        return $Result;
    }

    <#
    .SYNOPSIS
    Advance a set of wildcard-automaton positions by consuming one character

    .DESCRIPTION
    Computes the epsilon-closed set of outer positions reachable after consuming a single
    input symbol from an already epsilon-closed set. A 'star' token consumes the symbol
    and stays on itself; an 'any' token consumes any symbol and advances; a 'lit' token
    advances only when the symbol equals its literal character (the '' sentinel, standing
    for every non-literal character, matches no literal). The raw successor set is
    epsilon-closed before it is returned.

    .PARAMETER Positions
    | Name      | Type          | Description                                        | Default |
    |-----------|---------------|----------------------------------------------------|---------|
    | Positions | System.Int32[]| Epsilon-closed positions to advance.               |         |

    .PARAMETER Symbol
    | Name   | Type          | Description                                             | Default |
    |--------|---------------|---------------------------------------------------------|---------|
    | Symbol | System.String | Input symbol; '' is the sentinel for any other character.|       |

    .PARAMETER Kinds
    | Name  | Type           | Description                        | Default |
    |-------|----------------|------------------------------------|---------|
    | Kinds | System.String[]| Token kinds of the outer pattern.  |         |

    .PARAMETER Chars
    | Name  | Type           | Description                                  | Default |
    |-------|----------------|----------------------------------------------|---------|
    | Chars | System.String[]| Literal characters of the outer pattern.     |         |

    .OUTPUTS
    System.Int32[] — The epsilon-closed set of positions after the transition.

    .EXAMPLE
    PS> $this.WildcardStep(@(0, 1), 'f', $outerKinds, $outerChars)

    .NOTES
    Internal helper for the wildcard containment automaton.
    #>
    hidden [int[]] WildcardStep([int[]]$Positions, [string]$Symbol, [string[]]$Kinds, [string[]]$Chars)
    {
        [System.Collections.Generic.HashSet[int]]$Raw = [System.Collections.Generic.HashSet[int]]::new();

        foreach ($Pos in $Positions) {
            if ($Pos -ge $Kinds.Length) {
                continue;
            }

            [string]$Kind = $Kinds[$Pos];
            if ($Kind -eq 'star') {
                [void]$Raw.Add($Pos);
            } elseif ($Kind -eq 'any') {
                [void]$Raw.Add($Pos + 1);
            } elseif ($Kind -eq 'lit') {
                if ($Symbol -ne '' -and $Symbol -eq $Chars[$Pos]) {
                    [void]$Raw.Add($Pos + 1);
                }
            }
        }

        [int[]]$RawArray = [int[]]::new($Raw.Count);
        $Raw.CopyTo($RawArray);
        return $this.WildcardClosure($RawArray, $Kinds);
    }

    <#
    .SYNOPSIS
    Determine whether a set of wildcard-automaton positions is accepting

    .DESCRIPTION
    Returns whether the accepting position — the index equal to the outer pattern's token
    count, reached when every token has been consumed — is present in the given set.

    .PARAMETER Positions
    | Name      | Type          | Description                          | Default |
    |-----------|---------------|--------------------------------------|---------|
    | Positions | System.Int32[]| Positions to test.                   |         |

    .PARAMETER Accept
    | Name   | Type         | Description                           | Default |
    |--------|--------------|---------------------------------------|---------|
    | Accept | System.Int32 | The accepting position index.         |         |

    .OUTPUTS
    System.Boolean — $true when the accepting position is present, otherwise $false.

    .EXAMPLE
    PS> $this.WildcardAccepts(@(0, 1, 3), 3)

    .NOTES
    Internal helper for the wildcard containment automaton.
    #>
    hidden [bool] WildcardAccepts([int[]]$Positions, [int]$Accept)
    {
        foreach ($Position in $Positions) {
            if ($Position -eq $Accept) {
                return $true;
            }
        }

        return $false;
    }

    <#
    .SYNOPSIS
    Render a set of wildcard-automaton positions as a canonical key

    .DESCRIPTION
    Produces a stable, order-independent string key for a set of positions so equal state
    sets collapse in the reachability search. The positions are de-duplicated, sorted
    ascending and joined with commas.

    .PARAMETER Positions
    | Name      | Type          | Description                          | Default |
    |-----------|---------------|--------------------------------------|---------|
    | Positions | System.Int32[]| Positions to render.                 |         |

    .OUTPUTS
    System.String — The canonical comma-joined key, '' for an empty set.

    .EXAMPLE
    PS> $this.PosKey(@(2, 0, 1))

    .NOTES
    Internal helper for the wildcard containment automaton.
    #>
    hidden [string] PosKey([int[]]$Positions)
    {
        [System.Collections.Generic.List[int]]$Unique = [System.Collections.Generic.List[int]]::new();
        foreach ($Position in $Positions) {
            if (-not $Unique.Contains($Position)) {
                $Unique.Add($Position);
            }
        }

        $Unique.Sort();
        return ($Unique -join ',');
    }
}

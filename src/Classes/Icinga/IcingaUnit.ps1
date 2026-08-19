<#
.SYNOPSIS
Data container representing a single measurement unit definition

.DESCRIPTION
IcingaUnitEntry stores the metadata and scaling factor for an individual unit of
measurement. It is used internally by IcingaUnit lookup tables and conversion
ladders to resolve unit tokens, map them to unit families, and scale values
to and from base units (bytes for data, seconds for time).

.OUTPUTS
IcingaUnitEntry — Instantiated unit definition entry.

.EXAMPLE
PS> [IcingaUnitEntry]::new('KiB', [decimal]1024, 'Kibibyte', 'byte', 'Data')

Creates a unit entry representing Kibibytes with a base factor of 1024 bytes.

.NOTES
Internal data structure used exclusively by the IcingaUnit conversion system.
No external dependencies or global state.
#>
class IcingaUnitEntry
{
    [string]$Short   = '';
    [decimal]$Factor = 0;
    [string]$Long    = '';
    [string]$Kind    = '';
    [string]$Family  = '';

    <#
    .SYNOPSIS
    Initialize a new unit entry definition

    .DESCRIPTION
    Creates an immutable descriptor for a unit with its short symbol, base factor,
    long name, kind category, and parent family.

    .PARAMETER Short
    | Name  | Type          | Description                              | Default |
    |-------|---------------|------------------------------------------|---------|
    | Short | System.String | Short unit symbol (e.g. 'KiB', 's', 'B').|         |

    .PARAMETER Factor
    | Name   | Type           | Description                                     | Default |
    |--------|----------------|-------------------------------------------------|---------|
    | Factor | System.Decimal | Conversion factor relative to family base unit. |         |

    .PARAMETER Long
    | Name | Type          | Description                                    | Default |
    |------|---------------|------------------------------------------------|---------|
    | Long | System.String | Full singular name (e.g. 'Kibibyte', 'Second').|         |

    .PARAMETER Kind
    | Name | Type          | Description                                    | Default |
    |------|---------------|------------------------------------------------|---------|
    | Kind | System.String | Sub-categorization ('byte', 'bit', or 'time'). |         |

    .PARAMETER Family
    | Name   | Type          | Description                           | Default |
    |--------|---------------|---------------------------------------|---------|
    | Family | System.String | Major unit family ('Data' or 'Time'). |         |

    .OUTPUTS
    IcingaUnitEntry — Configured unit definition instance.

    .EXAMPLE
    PS> [IcingaUnitEntry]::new('MiB', [decimal]1048576, 'Mebibyte', 'byte', 'Data')

    .NOTES
    Factors must be defined in bytes for data units and seconds for time units.
    #>
    IcingaUnitEntry([string]$Short, [decimal]$Factor, [string]$Long, [string]$Kind, [string]$Family)
    {
        $this.Short  = $Short;
        $this.Factor = $Factor;
        $this.Long   = $Long;
        $this.Kind   = $Kind;
        $this.Family = $Family;
    }
}

<#
.SYNOPSIS
Value object that parses, converts and formats values between measurement units

.DESCRIPTION
IcingaUnit is the backing type for ConvertTo-IcingaUnit. Given a raw input value
(optionally carrying a unit suffix), an optional input unit, and an optional
target unit, it parses the value, resolves the units into their family (data size
or time duration), converts the value and renders a compact or human-readable
OutputString.

Two unit families are supported. Data sizes (binary bytes KiB/MiB/GiB, decimal
bytes KB/MB/GB, and bits Kbit/Mbit/Gbit) are matched case-insensitively and are
always emitted as a single scaled value. Time durations use the Icinga single-
letter tokens (ns, us, ms, s, m=minute, h, d, w, M=month, y=year) and are
matched case-sensitively so that minute (m) and month (M) remain distinct; time
is always decomposed into its non-zero components.

The class never throws exceptions on invalid user input. On invalid input it sets
Success to $false and assigns a semantic ReturnCode so calling functions can
surface errors through the module return-value system. All internal arithmetic
uses [decimal] to maintain exact precision down to nanoseconds. The class is
fully self-contained, thread-safe, and compatible with Windows PowerShell 5.1
and PowerShell 7+.

.OUTPUTS
IcingaUnit — Value object describing the conversion result.

.EXAMPLE
PS> [IcingaUnit]::new('1024B', $null, $null, $false)

Parses 1024 bytes and automatically promotes it to '1KiB' using the binary ladder.

.EXAMPLE
PS> [IcingaUnit]::new('8600', 's', $null, $true)

Decomposes 8600 seconds into '2 Hours 23 Minutes 20 Seconds'.

.EXAMPLE
PS> [IcingaUnit]::new('1000B', $null, 'GiB', $false)

Converts 1000 bytes explicitly to GiB.

.NOTES
Self-contained value object. Does not modify global state or access external
services. Safe to construct in multi-threaded runspaces.
#>
class IcingaUnit
{
    [double]$InputValue        = 0;
    [string]$InputUnit         = '';
    [double]$OutputValue       = 0;
    [string]$OutputUnit        = '';
    [string]$OutputString      = '';

    hidden [bool]$Success      = $false;
    hidden [string]$ReturnCode = '';

    static hidden [regex]$ValueRegex                                                          = [regex]::new('^\s*(-?\d+(?:[.,]\d+)?)\s*([A-Za-z]+)?\s*$', [System.Text.RegularExpressions.RegexOptions]::Compiled);
    static hidden [System.Collections.Generic.Dictionary[string, IcingaUnitEntry]]$TimeLookup = $null;
    static hidden [System.Collections.Generic.Dictionary[string, IcingaUnitEntry]]$DataLookup = $null;
    static hidden [IcingaUnitEntry[]]$TimeLadder                                              = $null;
    static hidden [IcingaUnitEntry[]]$DataBinaryLadder                                        = $null;
    static hidden [IcingaUnitEntry[]]$DataBitLadder                                           = $null;
    static hidden [IcingaUnitEntry]$SecondsEntry                                              = $null;

    <#
    .SYNOPSIS
    Populate static unit lookup dictionaries and conversion ladders

    .DESCRIPTION
    Initializes static lookup tables for time and data units, building case-
    sensitive and case-insensitive dictionaries along with conversion ladders
    ordered from largest unit to smallest. Also warms up the compiled regular
    expression. Safe to call multiple times (idempotent).

    .OUTPUTS
    None — Populates static class fields.

    .EXAMPLE
    PS> [IcingaUnit]::InitializeUnitTables()

    .NOTES
    Executed automatically upon module loading and guarded against re-entry.
    #>
    static [void] InitializeUnitTables()
    {
        if ($null -ne [IcingaUnit]::TimeLookup) {
            return;
        }

        # Ordered largest to smallest for decomposition. Month and year use the
        # common approximate lengths (30 and 365 days).
        [IcingaUnit]::TimeLadder   = @(
            [IcingaUnitEntry]::new('y',  [decimal]31536000,    'Year',        'time', 'Time'),
            [IcingaUnitEntry]::new('M',  [decimal]2592000,     'Month',       'time', 'Time'),
            [IcingaUnitEntry]::new('w',  [decimal]604800,      'Week',        'time', 'Time'),
            [IcingaUnitEntry]::new('d',  [decimal]86400,       'Day',         'time', 'Time'),
            [IcingaUnitEntry]::new('h',  [decimal]3600,        'Hour',        'time', 'Time'),
            [IcingaUnitEntry]::new('m',  [decimal]60,          'Minute',      'time', 'Time'),
            [IcingaUnitEntry]::new('s',  [decimal]1,           'Second',      'time', 'Time'),
            [IcingaUnitEntry]::new('ms', [decimal]0.001,       'Millisecond', 'time', 'Time'),
            [IcingaUnitEntry]::new('us', [decimal]0.000001,    'Microsecond', 'time', 'Time'),
            [IcingaUnitEntry]::new('ns', [decimal]0.000000001, 'Nanosecond',  'time', 'Time')
        );
        [IcingaUnit]::SecondsEntry = [IcingaUnit]::TimeLadder[6];

        $LocalTimeLookup = [System.Collections.Generic.Dictionary[string, IcingaUnitEntry]]::new([System.StringComparer]::Ordinal);
        foreach ($Entry in [IcingaUnit]::TimeLadder) {
            $LocalTimeLookup[$Entry.Short] = $Entry;
        }
        [IcingaUnit]::TimeLookup = $LocalTimeLookup;

        # Factors are expressed in bytes. 'Kind' selects the auto ladder: byte
        # input auto-formats against the binary ladder, bit input against bits.
        [IcingaUnitEntry[]]$DataUnits = @(
            [IcingaUnitEntry]::new('B',    [decimal]1,                'Byte',     'byte', 'Data'),
            [IcingaUnitEntry]::new('KiB',  [decimal]1024,             'Kibibyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('MiB',  [decimal]1048576,          'Mebibyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('GiB',  [decimal]1073741824,       'Gibibyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('TiB',  [decimal]1099511627776,    'Tebibyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('PiB',  [decimal]1125899906842624, 'Pebibyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('KB',   [decimal]1000,             'Kilobyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('MB',   [decimal]1000000,          'Megabyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('GB',   [decimal]1000000000,       'Gigabyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('TB',   [decimal]1000000000000,    'Terabyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('PB',   [decimal]1000000000000000, 'Petabyte', 'byte', 'Data'),
            [IcingaUnitEntry]::new('bit',  [decimal]0.125,            'Bit',      'bit',  'Data'),
            [IcingaUnitEntry]::new('Kbit', [decimal]125,              'Kilobit',  'bit',  'Data'),
            [IcingaUnitEntry]::new('Mbit', [decimal]125000,           'Megabit',  'bit',  'Data'),
            [IcingaUnitEntry]::new('Gbit', [decimal]125000000,        'Gigabit',  'bit',  'Data'),
            [IcingaUnitEntry]::new('Tbit', [decimal]125000000000,     'Terabit',  'bit',  'Data')
        );

        $LocalDataLookup = [System.Collections.Generic.Dictionary[string, IcingaUnitEntry]]::new([System.StringComparer]::OrdinalIgnoreCase);
        foreach ($Entry in $DataUnits) {
            $LocalDataLookup[$Entry.Short] = $Entry;
        }
        [IcingaUnit]::DataLookup = $LocalDataLookup;

        [IcingaUnit]::DataBinaryLadder = @(
            $LocalDataLookup['PiB'],
            $LocalDataLookup['TiB'],
            $LocalDataLookup['GiB'],
            $LocalDataLookup['MiB'],
            $LocalDataLookup['KiB'],
            $LocalDataLookup['B']
        );

        [IcingaUnit]::DataBitLadder = @(
            $LocalDataLookup['Tbit'],
            $LocalDataLookup['Gbit'],
            $LocalDataLookup['Mbit'],
            $LocalDataLookup['Kbit'],
            $LocalDataLookup['bit']
        );

        # Warm up regex compilation
        [void][IcingaUnit]::ValueRegex.Match('0B');
    }

    <#
    .SYNOPSIS
    Parse, convert and format a measurement value into an IcingaUnit instance

    .DESCRIPTION
    Constructs and evaluates an IcingaUnit conversion. Parses the InputValue string
    for numeric content and optional unit suffix, resolves the input unit, checks
    family compatibility with any specified TargetUnit, performs conversion or
    ladder auto-selection/decomposition, and populates the output properties.

    .PARAMETER InputValue
    | Name       | Type          | Description                                                  | Default |
    |------------|---------------|--------------------------------------------------------------|---------|
    | InputValue | System.String | Raw value to parse, with or without an embedded unit suffix. |         |

    .PARAMETER InputUnit
    | Name      | Type          | Description                                                   | Default |
    |-----------|---------------|---------------------------------------------------------------|---------|
    | InputUnit | System.String | Fallback unit when InputValue does not contain a unit suffix. |         |

    .PARAMETER TargetUnit
    | Name       | Type          | Description                                                  | Default |
    |------------|---------------|--------------------------------------------------------------|---------|
    | TargetUnit | System.String | Target unit for conversion. When omitted, best-fit is chosen. |         |

    .PARAMETER AsHumanReadable
    | Name            | Type           | Description                                                  | Default |
    |-----------------|----------------|--------------------------------------------------------------|---------|
    | AsHumanReadable | System.Boolean | When $true, formats OutputString with full pluralized names. |         |

    .OUTPUTS
    IcingaUnit — Configured instance containing conversion status and results.

    .EXAMPLE
    PS> [IcingaUnit]::new('1024B', '', '', $false)

    .EXAMPLE
    PS> [IcingaUnit]::new('8600', 's', '', $true)

    .NOTES
    Does not throw on invalid input; inspect the Success property and ReturnCode.
    #>
    IcingaUnit([string]$InputValue, [string]$InputUnit, [string]$TargetUnit, [bool]$AsHumanReadable)
    {
        if ($null -eq [IcingaUnit]::TimeLookup) {
            [IcingaUnit]::InitializeUnitTables();
        }

        if ([string]::IsNullOrWhiteSpace($InputValue)) {
            $this.Fail('IcingaUnitInvalidInputValue');
            return;
        }

        # Parse the raw value with a fully anchored pattern that requires at least
        # one digit. A unit substring buried inside a label (e.g. 'Serverms-001')
        # must never be treated as a unit, and non-numeric strings ('testb:testc',
        # '20:40') must be rejected here instead of blowing up in a numeric cast.
        $RegexMatch = [IcingaUnit]::ValueRegex.Match($InputValue);

        if (-not $RegexMatch.Success) {
            $this.Fail('IcingaUnitInvalidInputValue');
            return;
        }

        [string]$NumberPart = $RegexMatch.Groups[1].Value.Replace(',', '.');
        [string]$SuffixPart = $RegexMatch.Groups[2].Value;
        [decimal]$Number    = 0;

        if (-not [decimal]::TryParse($NumberPart, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$Number)) {
            $this.Fail('IcingaUnitInvalidInputValue');
            return;
        }

        # A unit given as a suffix on the value wins over the -InputUnit parameter.
        [string]$SourceUnit = $SuffixPart;
        if ([string]::IsNullOrEmpty($SourceUnit)) {
            $SourceUnit = $InputUnit;
        }

        if ([string]::IsNullOrEmpty($SourceUnit)) {
            $this.Fail('IcingaUnitMissingInputUnit');
            return;
        }

        [IcingaUnitEntry]$InputEntry = [IcingaUnit]::ResolveUnit($SourceUnit);
        if ($null -eq $InputEntry) {
            $this.Fail('IcingaUnitUnknownUnit');
            return;
        }

        [string]$InputFamily = $InputEntry.Family;

        $this.InputValue = [double]$Number;
        $this.InputUnit  = $InputEntry.Short;

        # Convert the input into the family base unit (bytes for data, seconds for
        # time) so every following calculation shares a common scale.
        [decimal]$BaseValue = $Number * $InputEntry.Factor;
        [int]$Sign          = 1;

        if ($BaseValue -lt 0) {
            $Sign      = -1;
            $BaseValue = -$BaseValue;
        }

        if (-not [string]::IsNullOrEmpty($TargetUnit)) {
            [IcingaUnitEntry]$TargetEntry = [IcingaUnit]::ResolveUnit($TargetUnit);
            if ($null -eq $TargetEntry) {
                $this.Fail('IcingaUnitUnknownUnit');
                return;
            }

            if ($TargetEntry.Family -ne $InputFamily) {
                $this.Fail('IcingaUnitFamilyMismatch');
                return;
            }

            [decimal]$Converted = $BaseValue / $TargetEntry.Factor;

            $this.OutputValue  = $Sign * [double][System.Math]::Round($Converted, 2);
            $this.OutputUnit   = $TargetEntry.Short;
            $this.OutputString = $this.ApplySign($Sign, $this.FormatSingle($Converted, $TargetEntry, $AsHumanReadable));
            $this.Success      = $true;
            $this.ReturnCode   = 'IcingaUnitConverted';
            return;
        }

        # No explicit target unit: auto-select. Time is decomposed into its
        # non-zero parts; data picks the largest unit that keeps the value >= 1.
        if ($InputFamily -eq 'Time') {
            $this.BuildTimeDecomposition($BaseValue, $Sign, $AsHumanReadable);
        } else {
            $this.BuildDataBestFit($BaseValue, $Sign, $InputEntry, $AsHumanReadable);
        }

        $this.Success    = $true;
        $this.ReturnCode = 'IcingaUnitConverted';
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
    PS> $this.Fail('IcingaUnitInvalidInputValue')

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
    Resolve a unit token string to its matching IcingaUnitEntry definition

    .DESCRIPTION
    Looks up a unit identifier in the registered time and data unit tables.
    Time tokens are matched case-sensitively to preserve distinction between
    minute ('m') and month ('M'). Data tokens are matched case-insensitively.

    .PARAMETER Token
    | Name  | Type          | Description                           | Default |
    |-------|---------------|---------------------------------------|---------|
    | Token | System.String | Unit symbol or identifier to resolve. |         |

    .OUTPUTS
    IcingaUnitEntry — Matching unit definition entry, or $null if unknown.

    .EXAMPLE
    PS> [IcingaUnit]::ResolveUnit('GiB')

    .NOTES
    Internal static lookup helper.
    #>
    static hidden [IcingaUnitEntry] ResolveUnit([string]$Token)
    {
        if ([string]::IsNullOrEmpty($Token)) {
            return $null;
        }

        # Time is matched case-sensitively first (m vs M), data case-insensitively.
        [IcingaUnitEntry]$FoundEntry = $null;
        if ([IcingaUnit]::TimeLookup.TryGetValue($Token, [ref]$FoundEntry)) {
            return $FoundEntry;
        }

        if ([IcingaUnit]::DataLookup.TryGetValue($Token, [ref]$FoundEntry)) {
            return $FoundEntry;
        }

        return $null;
    }

    <#
    .SYNOPSIS
    Select the best-fitting data unit and format the output

    .DESCRIPTION
    Walks down the appropriate data ladder (binary bytes or bits) from largest
    to smallest, selecting the largest unit where the converted value remains
    greater than or equal to 1. Sets OutputValue, OutputUnit, and OutputString.

    .PARAMETER BaseValue
    | Name      | Type           | Description                           | Default |
    |-----------|----------------|---------------------------------------|---------|
    | BaseValue | System.Decimal | Value scaled to the base unit (bytes).|         |

    .PARAMETER Sign
    | Name | Type         | Description                                        | Default |
    |------|--------------|----------------------------------------------------|---------|
    | Sign | System.Int32 | Numeric sign multiplier (1 for positive, -1 for -).|         |

    .PARAMETER InputEntry
    | Name       | Type            | Description                               | Default |
    |------------|-----------------|-------------------------------------------|---------|
    | InputEntry | IcingaUnitEntry | Unit definition entry of the input value. |         |

    .PARAMETER AsHumanReadable
    | Name            | Type           | Description                                                  | Default |
    |-----------------|----------------|--------------------------------------------------------------|---------|
    | AsHumanReadable | System.Boolean | When $true, formats OutputString with full pluralized names. |         |

    .OUTPUTS
    None — Updates instance output properties.

    .EXAMPLE
    PS> $this.BuildDataBestFit([decimal]1048576, 1, $inputEntry, $false)

    .NOTES
    Internal helper method for automatic data size scaling.
    #>
    hidden [void] BuildDataBestFit([decimal]$BaseValue, [int]$Sign, [IcingaUnitEntry]$InputEntry, [bool]$AsHumanReadable)
    {
        [IcingaUnitEntry[]]$Ladder = [IcingaUnit]::DataBinaryLadder;
        if ($InputEntry.Kind -eq 'bit') {
            $Ladder = [IcingaUnit]::DataBitLadder;
        }

        [IcingaUnitEntry]$Chosen = $null;
        foreach ($Unit in $Ladder) {
            if (($BaseValue / $Unit.Factor) -ge 1) {
                $Chosen = $Unit;
                break;
            }
        }

        # Everything below the smallest unit (or a plain zero) falls back to the
        # base unit so the value is never rendered against a unit that rounds it
        # away to zero.
        if ($null -eq $Chosen) {
            $Chosen = $Ladder[$Ladder.Length - 1];
        }

        [decimal]$Converted = $BaseValue / $Chosen.Factor;

        $this.OutputValue  = $Sign * [double][System.Math]::Round($Converted, 2);
        $this.OutputUnit   = $Chosen.Short;
        $this.OutputString = $this.ApplySign($Sign, $this.FormatSingle($Converted, $Chosen, $AsHumanReadable));
    }

    <#
    .SYNOPSIS
    Decompose a time duration into non-zero units and format the output

    .DESCRIPTION
    Breaks down a duration in base seconds across the time ladder (years down to
    nanoseconds), collecting every non-zero component and building a combined
    compact or human-readable duration string.

    .PARAMETER BaseValue
    | Name      | Type           | Description                           | Default |
    |-----------|----------------|---------------------------------------|---------|
    | BaseValue | System.Decimal | Time duration scaled to base seconds. |         |

    .PARAMETER Sign
    | Name | Type         | Description                                        | Default |
    |------|--------------|----------------------------------------------------|---------|
    | Sign | System.Int32 | Numeric sign multiplier (1 for positive, -1 for -).|         |

    .PARAMETER AsHumanReadable
    | Name            | Type           | Description                                                  | Default |
    |-----------------|----------------|--------------------------------------------------------------|---------|
    | AsHumanReadable | System.Boolean | When $true, formats OutputString with full pluralized names. |         |

    .OUTPUTS
    None — Updates instance output properties.

    .EXAMPLE
    PS> $this.BuildTimeDecomposition([decimal]8600, 1, $true)

    .NOTES
    Internal helper method for time decomposition.
    #>
    hidden [void] BuildTimeDecomposition([decimal]$BaseValue, [int]$Sign, [bool]$AsHumanReadable)
    {
        [decimal]$Remaining                                = $BaseValue;
        [System.Collections.Generic.List[string]]$Segments = [System.Collections.Generic.List[string]]::new();
        [double]$FirstCount                                = 0;
        [string]$FirstUnit                                 = '';
        [bool]$HasParts                                    = $false;

        foreach ($Unit in [IcingaUnit]::TimeLadder) {
            [decimal]$Count = [System.Math]::Floor($Remaining / $Unit.Factor);
            if ($Count -gt 0) {
                if (-not $HasParts) {
                    $FirstCount = [double]$Count;
                    $FirstUnit  = $Unit.Short;
                    $HasParts   = $true;
                }
                if ($AsHumanReadable) {
                    $Segments.Add(('{0} {1}' -f $Count, $this.Pluralize($Unit.Long, $Count)));
                } else {
                    $Segments.Add(('{0}{1}' -f $Count, $Unit.Short));
                }
                $Remaining = $Remaining - ($Count * $Unit.Factor);
            }
        }

        # A value smaller than a nanosecond (or exactly zero) has no whole parts;
        # render it as a single rounded seconds value instead of an empty string.
        if (-not $HasParts) {
            [IcingaUnitEntry]$Seconds = [IcingaUnit]::SecondsEntry;
            $this.OutputValue         = $Sign * [double][System.Math]::Round($BaseValue, 2);
            $this.OutputUnit          = $Seconds.Short;
            $this.OutputString        = $this.ApplySign($Sign, $this.FormatSingle($BaseValue, $Seconds, $AsHumanReadable));
            return;
        }

        $this.OutputValue  = $Sign * $FirstCount;
        $this.OutputUnit   = $FirstUnit;
        $this.OutputString = $this.ApplySign($Sign, [string]::Join(' ', $Segments));
    }

    <#
    .SYNOPSIS
    Format a single numeric value and unit entry into a display string

    .DESCRIPTION
    Rounds a numeric value to at most two decimal places and combines it with
    either the short symbol or the long pluralized name of the unit entry.

    .PARAMETER Value
    | Name  | Type           | Description                 | Default |
    |-------|----------------|-----------------------------|---------|
    | Value | System.Decimal | Numeric value to format.    |         |

    .PARAMETER Entry
    | Name  | Type            | Description                 | Default |
    |-------|-----------------|-----------------------------|---------|
    | Entry | IcingaUnitEntry | Target unit definition entry|         |

    .PARAMETER AsHumanReadable
    | Name            | Type           | Description                                         | Default |
    |-----------------|----------------|-----------------------------------------------------|---------|
    | AsHumanReadable | System.Boolean | When $true, uses full unit name with pluralization. |         |

    .OUTPUTS
    System.String — Formatted display string representing the value and unit.

    .EXAMPLE
    PS> $this.FormatSingle([decimal]1.5, $entry, $false)

    .NOTES
    Internal formatting helper method.
    #>
    hidden [string] FormatSingle([decimal]$Value, [IcingaUnitEntry]$Entry, [bool]$AsHumanReadable)
    {
        [decimal]$Rounded = [System.Math]::Round($Value, 2);
        [string]$Number   = $Rounded.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture);

        if ($AsHumanReadable) {
            return ('{0} {1}' -f $Number, $this.Pluralize($Entry.Long, $Rounded));
        }

        return ('{0}{1}' -f $Number, $Entry.Short);
    }

    <#
    .SYNOPSIS
    Determine the singular or plural form of a unit name based on value

    .DESCRIPTION
    Returns the unmodified unit name when the value equals exactly 1; otherwise,
    appends an 's' suffix to produce the regular English plural form.

    .PARAMETER Long
    | Name | Type          | Description                   | Default |
    |------|---------------|-------------------------------|---------|
    | Long | System.String | Singular unit name in English.|         |

    .PARAMETER Value
    | Name  | Type           | Description                                | Default |
    |-------|----------------|--------------------------------------------|---------|
    | Value | System.Decimal | Numeric value evaluated for pluralization. |         |

    .OUTPUTS
    System.String — Appropriately inflected unit name string.

    .EXAMPLE
    PS> $this.Pluralize('Hour', [decimal]2)

    .NOTES
    Internal grammar helper method.
    #>
    hidden [string] Pluralize([string]$Long, [decimal]$Value)
    {
        if ($Value -eq 1) {
            return $Long;
        }

        return ($Long + 's');
    }

    <#
    .SYNOPSIS
    Prefix a negative sign to formatted text if the sign multiplier is negative

    .DESCRIPTION
    Prepends '-' to the text when the sign is less than zero, or returns the text
    unmodified when positive.

    .PARAMETER Sign
    | Name | Type         | Description                                        | Default |
    |------|--------------|----------------------------------------------------|---------|
    | Sign | System.Int32 | Numeric sign multiplier (1 for positive, -1 for -).|         |

    .PARAMETER Text
    | Name | Type          | Description                      | Default |
    |------|---------------|----------------------------------|---------|
    | Text | System.String | Formatted text string to prefix. |         |

    .OUTPUTS
    System.String — Sign-adjusted text string.

    .EXAMPLE
    PS> $this.ApplySign(-1, '500MB')

    .NOTES
    Internal formatting helper method.
    #>
    hidden [string] ApplySign([int]$Sign, [string]$Text)
    {
        if ($Sign -lt 0) {
            return ('-' + $Text);
        }

        return $Text;
    }
}

[IcingaUnit]::InitializeUnitTables();

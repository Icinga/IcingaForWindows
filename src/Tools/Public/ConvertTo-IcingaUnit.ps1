<#
.SYNOPSIS
Convert a value between data-size or time units and render it for display

.DESCRIPTION
ConvertTo-IcingaUnit parses a numeric value with an optional unit, converts it
into a requested target unit or automatically picks the best-fitting unit, and
returns an `IcingaUnit` object describing the result. The value may be passed as
a combined string such as '1000B' or as a plain number together with -InputUnit.

Two unit families are supported. Data sizes cover binary bytes (B, KiB, MiB,
GiB, TiB, PiB), decimal bytes (KB, MB, GB, TB, PB) and bits (bit, Kbit, Mbit,
Gbit, Tbit); their unit names are matched case-insensitively and the result is a
single value. Time durations use the Icinga single-letter tokens (ns, us, ms, s,
m for minute, h, d, w, M for month, y for year); their names are matched
case-sensitively so that minute and month stay distinct, and the result is
decomposed into every non-zero unit (for example '2h 23m 20s'). Without a
target unit the function keeps the value at or above one so it never rounds a
non-zero result down to zero; for data it defaults to the binary ladder.

Parsing is strict and fully anchored: only a string of the exact shape
'<number><unit>' is accepted, so label-like values such as 'Serverms-001' or a
threshold range such as '20:40' are rejected instead of being misread as a unit
value. On success the converted IcingaUnit object is returned; on any failure
the function logs the reason through the module return-value system and returns
$null.

.PARAMETER InputValue
| Name       | Type          | Description                                                                                    | Default |
|------------|---------------|------------------------------------------------------------------------------------------------|---------|
| InputValue | System.String | Value to convert, either as a plain number ('1000') or with a unit suffix ('1000B', '1.5MiB'). | $null   |

.PARAMETER InputUnit
| Name      | Type          | Description                                                                               | Default |
|-----------|---------------|-------------------------------------------------------------------------------------------|---------|
| InputUnit | System.String | Unit of the input when InputValue has no suffix. A suffix on InputValue takes precedence. | $null   |

.PARAMETER TargetUnit
| Name       | Type          | Description                                                                                           | Default |
|------------|---------------|-------------------------------------------------------------------------------------------------------|---------|
| TargetUnit | System.String | Unit to convert to. Must be in the same family as the input. When omitted the best-fitting unit wins. | $null   |

.PARAMETER AsHumanReadable
| Name            | Type                                         | Description                                                                             | Default |
|-----------------|----------------------------------------------|-----------------------------------------------------------------------------------------|---------|
| AsHumanReadable | System.Management.Automation.SwitchParameter | Render OutputString with full, pluralized unit names ('2 Hours 23 Minutes 20 Seconds'). | $false  |

.OUTPUTS
IcingaUnit -- Object with InputValue, InputUnit, OutputValue, OutputUnit and
OutputString describing the conversion. Returns $null via Write-FunctionReturnValue
on failure with return codes IcingaUnitInvalidInputValue, IcingaUnitMissingInputUnit,
IcingaUnitUnknownUnit or IcingaUnitFamilyMismatch.

.EXAMPLE
PS> ConvertTo-IcingaUnit -InputValue '1024B'

Auto-selects the best-fitting binary unit and returns an object whose
OutputString is '1KiB'.

.EXAMPLE
PS> ConvertTo-IcingaUnit -InputValue '8600' -InputUnit 's' -AsHumanReadable

Decomposes 8600 seconds and returns an object whose OutputString is
'2 Hours 23 Minutes 20 Seconds'.

.EXAMPLE
PS> ConvertTo-IcingaUnit -InputValue '1000' -InputUnit 'B' -TargetUnit 'GiB'

Converts 1000 bytes into the explicitly requested GiB unit.

.NOTES
The conversion logic lives in the IcingaUnit class. Failures are surfaced through
Write-FunctionReturnValue, which logs at the severity registered for each return
code in Set-InternalExitCodes (Error for failures, Debug for the successful
conversion). No external services, credentials or configuration files are used.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function ConvertTo-IcingaUnit()
{
    param (
        [string]$InputValue      = $null,
        [string]$InputUnit       = $null,
        [string]$TargetUnit      = $null,
        [switch]$AsHumanReadable = $false
    );

    $Unit = ('IcingaUnit' -as [type])::new($InputValue, $InputUnit, $TargetUnit, $AsHumanReadable.IsPresent);

    if (-not $Unit.Success) {
        return (Write-FunctionReturnValue -ReturnValue $Unit.ReturnCode -Data @{
            'InputValue' = $InputValue;
            'InputUnit'  = $InputUnit;
            'TargetUnit' = $TargetUnit;
        } -OverrideReturn $null);
    }

    return (Write-FunctionReturnValue -ReturnValue 'IcingaUnitConverted' -Data @{
        'OutputString' = $Unit.OutputString;
    } -OverrideReturn $Unit);
}

# Icinga.Tools

*Auto-generated from `src/Tools/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Compare-IcingaTextContent](#compare-icingatextcontent)
- [ConvertTo-IcingaUnit](#convertto-icingaunit)
- [Get-IcingaUnixTime](#get-icingaunixtime)
- [Join-WebPath](#join-webpath)
- [Resolve-IcingaIPAddress](#resolve-icingaipaddress)

## Private helpers

- [ConvertFrom-ModuleJson](#convertfrom-modulejson)
- [ConvertTo-ModuleJson](#convertto-modulejson)
- [ConvertTo-StringNormalizedArray](#convertto-stringnormalizedarray)
- [Get-NormalizedTextContent](#get-normalizedtextcontent)
- [Remove-ModuleAmbitiousCharacters](#remove-moduleambitiouscharacters)

---

### Compare-IcingaTextContent

*Public function*

**Synopsis:** Compares two text or JSON inputs and produces a unified diff

#### Description

Compare-IcingaTextContent computes a line-level unified diff between an old and a
new content source. Pass the new content via -NewConfig and the old baseline either
as an inline string via -OldConfig or as a file path via -OldFile. When -OldFile is
provided the file is read via Read-SecureFile. Both inputs are normalized via
ConvertFrom-Json / ConvertTo-Json before comparison so that insignificant JSON
formatting differences are ignored. The diff is computed with a
Longest-Common-Subsequence (LCS) algorithm and output follows the unified diff
format with three lines of context around each changed block. When -Colorized is
set, removed lines carry ANSI red and added lines ANSI green; the output is
otherwise plain text. Compatible with PowerShell 5 and PowerShell 7. No external
tools or modules are required.

#### Parameters

**`$NewConfig`**

| Name      | Type          | Description                                     | Default |
|-----------|---------------|-------------------------------------------------|---------|
| NewConfig | System.String | The new content as a JSON string or plain text. | $null   |

**`$OldConfig`**

| Name      | Type          | Description                                           | Default |
|-----------|---------------|-------------------------------------------------------|---------|
| OldConfig | System.String | The baseline content as a JSON string or plain text.  | $null   |

**`$OldFile`**

| Name    | Type          | Description                                                           | Default |
|---------|---------------|-----------------------------------------------------------------------|---------|
| OldFile | System.String | File path to the baseline; read via Read-SecureFile when provided.    | $null   |

**`$Colorized`**

| Name      | Type                                         | Description                                                    | Default |
|-----------|----------------------------------------------|----------------------------------------------------------------|---------|
| Colorized | System.Management.Automation.SwitchParameter | When set, embeds ANSI color codes (green/red/cyan) in output. | $false  |

#### Outputs

System.Collections.Hashtable — Always returns @{ ExitCode = System.Int32; Output = System.String }.
ExitCode is 0 when both inputs are identical after normalization, 1 when they differ.
Output is an empty string when identical; otherwise a unified diff with header lines
(--- old / +++ new), @@ hunk headers and +/-/space-prefixed content lines.
With -Colorized the Output string contains ANSI escape sequences.

#### Examples

```powershell
PS> Compare-IcingaTextContent -NewConfig '{"key":"new"}' -OldConfig '{"key":"old"}'

Compares two inline JSON strings and returns a hashtable with the unified diff in Output.
```

```powershell
PS> Compare-IcingaTextContent -NewConfig $JsonString -OldFile 'C:\icinga\restapi.json' -Colorized

Reads restapi.json via Read-SecureFile, normalizes both sides as JSON, and returns
a hashtable with a colorized unified diff in Output.
```

#### Notes

Read-SecureFile restricts reads to the module root and module config directories;
paths outside those locations will cause -OldFile to resolve to an empty baseline.
-OldConfig and -OldFile are mutually exclusive by convention; when both are provided
-OldConfig takes precedence. The LCS algorithm allocates an (m+1)x(n+1) integer
matrix; inputs beyond a few thousand lines will consume significant memory, which
is acceptable for config-file comparison. No external binaries, modules, or .NET
packages beyond the PowerShell standard library are used.

*Source: [src/Tools/Public/Compare-IcingaTextContent.ps1](../../src/Tools/Public/Compare-IcingaTextContent.ps1)*

---

### ConvertTo-IcingaUnit

*Public function*

**Synopsis:** Convert a value between data-size or time units and render it for display

#### Description

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

#### Parameters

**`$InputValue`**

| Name       | Type          | Description                                                                                    | Default |
|------------|---------------|------------------------------------------------------------------------------------------------|---------|
| InputValue | System.String | Value to convert, either as a plain number ('1000') or with a unit suffix ('1000B', '1.5MiB'). | $null   |

**`$InputUnit`**

| Name      | Type          | Description                                                                               | Default |
|-----------|---------------|-------------------------------------------------------------------------------------------|---------|
| InputUnit | System.String | Unit of the input when InputValue has no suffix. A suffix on InputValue takes precedence. | $null   |

**`$TargetUnit`**

| Name       | Type          | Description                                                                                           | Default |
|------------|---------------|-------------------------------------------------------------------------------------------------------|---------|
| TargetUnit | System.String | Unit to convert to. Must be in the same family as the input. When omitted the best-fitting unit wins. | $null   |

**`$AsHumanReadable`**

| Name            | Type                                         | Description                                                                             | Default |
|-----------------|----------------------------------------------|-----------------------------------------------------------------------------------------|---------|
| AsHumanReadable | System.Management.Automation.SwitchParameter | Render OutputString with full, pluralized unit names ('2 Hours 23 Minutes 20 Seconds'). | $false  |

#### Outputs

IcingaUnit -- Object with InputValue, InputUnit, OutputValue, OutputUnit and
OutputString describing the conversion. Returns $null via Write-FunctionReturnValue
on failure with return codes IcingaUnitInvalidInputValue, IcingaUnitMissingInputUnit,
IcingaUnitUnknownUnit or IcingaUnitFamilyMismatch.

#### Examples

```powershell
PS> ConvertTo-IcingaUnit -InputValue '1024B'

Auto-selects the best-fitting binary unit and returns an object whose
OutputString is '1KiB'.
```

```powershell
PS> ConvertTo-IcingaUnit -InputValue '8600' -InputUnit 's' -AsHumanReadable

Decomposes 8600 seconds and returns an object whose OutputString is
'2 Hours 23 Minutes 20 Seconds'.
```

```powershell
PS> ConvertTo-IcingaUnit -InputValue '1000' -InputUnit 'B' -TargetUnit 'GiB'

Converts 1000 bytes into the explicitly requested GiB unit.
```

#### Notes

The conversion logic lives in the IcingaUnit class. Failures are surfaced through
Write-FunctionReturnValue, which logs at the severity registered for each return
code in Set-InternalExitCodes (Error for failures, Debug for the successful
conversion). No external services, credentials or configuration files are used.

*Source: [src/Tools/Public/ConvertTo-IcingaUnit.ps1](../../src/Tools/Public/ConvertTo-IcingaUnit.ps1)*

---

### Get-IcingaUnixTime

*Public function*

**Synopsis:** Returns the current Unix time (epoch) from the local system in UTC.

#### Description

Get-IcingaUnixTime returns the number of seconds (or, when requested, milliseconds) elapsed since the Unix epoch (1970-01-01T00:00:00Z).
The function obtains the current time in UTC and converts it to a numeric Unix timestamp.

#### Parameters

**`$Milliseconds`**

| Name         | Type                                         | Description                                                          | Default |
|--------------|----------------------------------------------|----------------------------------------------------------------------|---------|
| Milliseconds | System.Management.Automation.SwitchParameter | When set, returns Unix time in milliseconds (Int64) instead of seconds (Int32). | $false |

#### Outputs

System.Int32 — Unix time in seconds when called without -Milliseconds.
System.Int64 — Unix time in milliseconds when called with -Milliseconds.

#### Examples

```powershell
PS> Get-IcingaUnixTime
1609459200

Returns the current Unix time in seconds (int).
```

```powershell
PS> Get-IcingaUnixTime -Milliseconds
1609459200000

Intended to return the current Unix time in milliseconds (int64).
```

#### Notes

The timestamp is calculated using UTC to represent the standard Unix epoch (1970-01-01T00:00:00Z).
Without -Milliseconds the function returns a System.Int32 via Get-Date -UFormat %s.
With -Milliseconds the function divides TotalMilliseconds by 1000 and casts to Int64;
callers requiring sub-second precision should verify the returned value before use.

*Source: [src/Tools/Public/Get-IcingaUnixTime.ps1](../../src/Tools/Public/Get-IcingaUnixTime.ps1)*

---

### Join-WebPath

*Public function*

**Synopsis:** Joins path segments into a single well-formed web path.

#### Description

Combines a base path and additional child path segments, handling trailing and leading slashes,
URL query parameters and avoiding duplicate slashes. Preserves scheme endings like '://'.

#### Parameters

**`$Path`**

| Name | Type          | Description                  | Default |
|------|---------------|------------------------------|---------|
| Path | System.String | Base path or URL to start from. | $null   |

**`$ChildPath`**

| Name      | Type         | Description                                                                          | Default |
|-----------|--------------|--------------------------------------------------------------------------------------|---------|
| ChildPath | System.Array | Child path segments to append. Segments may start with /, ? or & for query strings. | $null   |

#### Outputs

System.String — The assembled web path or URL.

#### Examples

```powershell
PS> Join-WebPath -Path 'http://example.com/' -ChildPath @('api', 'v1', 'items')

Returns 'http://example.com/api/v1/items'.
```

```powershell
PS> Join-WebPath -Path 'http://example.com' -ChildPath @('search', '?q=test', '&page=2')

Returns 'http://example.com/search?q=test&page=2'.
```

#### Notes

No external dependencies.

*Source: [src/Tools/Public/Join-WebPath.ps1](../../src/Tools/Public/Join-WebPath.ps1)*

---

### Resolve-IcingaIPAddress

*Public function*

**Synopsis:** Resolves a hostname or returns a validated IP address string.

#### Description

Resolve-IcingaIPAddress accepts a hostname or IP address string and attempts to
return a canonical IP address string. If the input is already a valid IPv4 or
IPv6 literal, it is returned unchanged. Otherwise the function performs DNS
resolution and prefers an IPv4 address when multiple addresses are returned.
On failure or exception, the function uses the module's Write-FunctionReturnValue
mechanism to emit a standardized return value and typically returns $null.

#### Parameters

**`$Address`**

| Name    | Type          | Description                                                                  | Default |
|---------|---------------|------------------------------------------------------------------------------|---------|
| Address | System.String | Hostname or IP address to resolve. Empty or null triggers IPAddressLookupEmpty. | $null   |

#### Outputs

System.String — IPv4 or IPv6 address string on success.
Returns $null via Write-FunctionReturnValue on failure with tokens
IPAddressLookupEmpty, IPAddressLookupFailure, IPAddressLookupFailedForV4AndV6
or IPAddressLookupException.

#### Examples

```powershell
PS> Resolve-IcingaIPAddress -Address 'icinga-master.example.local'

Resolves the hostname and returns the first IPv4 address found, or the first IPv6
address if no IPv4 is available.
```

```powershell
PS> Resolve-IcingaIPAddress -Address '192.0.2.1'

Returns '192.0.2.1' unchanged since the input is already a valid IPv4 literal.
```

#### Notes

DNS resolution is performed via [System.Net.Dns]::GetHostAddresses. IPv4 addresses
are preferred; the function returns the first IPv4 found, otherwise the first IPv6.
Simple regex literal checks are performed before DNS resolution to avoid unnecessary
lookups. Error conditions are surfaced via Write-FunctionReturnValue.

*Source: [src/Tools/Public/Resolve-IcingaIPAddress.ps1](../../src/Tools/Public/Resolve-IcingaIPAddress.ps1)*

---

### ConvertFrom-ModuleJson

*Private function*

**Synopsis:** Converts a JSON formatted string to a hashtable or dictionary safely across PowerShell versions.

#### Description

ConvertFrom-ModuleJson provides a cross-platform, cross-version safe way to parse JSON
strings into hashtables. It addresses the well-known memory leak (ETS cache bloat) in
Windows PowerShell 5.1 by falling back to System.Web.Script.Serialization.JavaScriptSerializer,
which natively returns dictionaries instead of PSCustomObjects. In PowerShell 6 and higher,
it uses the native ConvertFrom-Json cmdlet with the -AsHashtable switch.

#### Parameters

**`$InputObject`**

| Name        | Type          | Description                                | Default |
|-------------|---------------|--------------------------------------------|---------|
| InputObject | System.String | The JSON string to deserialize.            | ''      |

#### Outputs

System.Collections.Hashtable — Returns a hashtable (or dictionary) representation of the JSON string.
Returns `$null` if the input is empty or parsing fails.

#### Examples

```powershell
PS> $hashtable = ConvertFrom-ModuleJson -InputObject '{"key": "value"}'
```

#### Notes

In Windows PowerShell 5.1, this function dynamically loads the System.Web.Extensions
assembly if it is not already loaded in the current runspace.

*Source: [src/Tools/Private/ConvertFrom-ModuleJson.ps1](../../src/Tools/Private/ConvertFrom-ModuleJson.ps1)*

---

### ConvertTo-ModuleJson

*Private function*

**Synopsis:** Converts an object to a JSON formatted string safely across PowerShell versions.

#### Description

ConvertTo-ModuleJson provides a cross-platform, cross-version safe way to serialize
objects into JSON strings. It addresses memory leaks in Windows PowerShell 5.1
associated with the native ConvertTo-Json cmdlet when called rapidly by falling
back to System.Web.Script.Serialization.JavaScriptSerializer. In PowerShell 6
and higher, it uses the native ConvertTo-Json cmdlet.

#### Parameters

**`$InputObject`**

| Name        | Type          | Description                                | Default |
|-------------|---------------|--------------------------------------------|---------|
| InputObject | System.Object | The object to serialize.                   | $null   |

#### Outputs

System.String — Returns a JSON string representation of the object.
Returns an empty string if the input is null or serialization fails.

#### Examples

```powershell
PS> $json = ConvertTo-ModuleJson -InputObject @{ key = "value" }
```

#### Notes

In Windows PowerShell 5.1, this function dynamically loads the System.Web.Extensions
assembly if it is not already loaded.

*Source: [src/Tools/Private/ConvertTo-ModuleJson.ps1](../../src/Tools/Private/ConvertTo-ModuleJson.ps1)*

---

### ConvertTo-StringNormalizedArray

*Private function*

**Synopsis:** Normalize string elements of an array to lower- or upper-case.

#### Description

`ConvertTo-StringNormalizedArray` returns a new array where string elements
are converted to a normalized case (lower-case by default or upper-case when
`-UpperCase` is specified). Non-string elements are preserved unchanged.
This helper is useful for normalizing user lists for case-insensitive or
consistent comparisons.

#### Parameters

**`$InputArray`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| InputArray | System.Object[] | Array of items to normalize; string items will be case-normalized | @() |

**`$UpperCase`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| UpperCase | Switch | When set, convert string items to upper-case instead of lower-case | $false |

#### Outputs

Array of the same length with string items converted to the selected case.

#### Examples

```powershell
$norm = ConvertTo-StringNormalizedArray -InputArray @('Alice','BOB', 123)
```

```powershell
$normUpper = ConvertTo-StringNormalizedArray -InputArray @('Alice','BOB') -UpperCase
```

#### Notes

- Non-string items are returned unchanged.

*Source: [src/Tools/Private/ConvertTo-StringNormalizedArray.ps1](../../src/Tools/Private/ConvertTo-StringNormalizedArray.ps1)*

---

### Get-NormalizedTextContent

*Private function*

**Synopsis:** Normalize a string by re-serializing it when it contains valid JSON

#### Description

Get-NormalizedTextContent attempts to parse the input string as JSON via
ConvertFrom-Json. When parsing succeeds the object is immediately re-serialized
with ConvertTo-Json at depth 20, producing a consistently formatted JSON string
free of whitespace artifacts. When parsing fails the original string is returned
unchanged, making this function safe to call on plain-text content. A null or
empty input returns an empty string without attempting any conversion.

#### Parameters

**`$Content`**

| Name    | Type          | Description              | Default |
|---------|---------------|--------------------------|---------|
| Content | System.String | The string to normalize. | $null   |

#### Outputs

System.String — Re-serialized JSON string when the input is valid JSON, the
original input string when it is not, or an empty string for null or empty input.

#### Examples

```powershell
PS> Get-NormalizedTextContent -Content '{"b":2,"a":1}'

Returns the JSON re-serialized with ConvertTo-Json formatting.
```

#### Notes

Used by Compare-IcingaTextContent to ensure both sides of a diff use identical
formatting before line-level comparison. Relies only on ConvertFrom-Json and
ConvertTo-Json from the PowerShell standard library; no external dependencies.

*Source: [src/Tools/Private/Get-NormalizedTextContent.ps1](../../src/Tools/Private/Get-NormalizedTextContent.ps1)*

---

### Remove-ModuleAmbitiousCharacters

*Private function*

**Synopsis:** Remove characters that are invalid in Windows filenames.

#### Description

Cleans an input string by removing characters that are not allowed in
Windows filenames. Optionally removes whitespace as well. Useful when
deriving filenames from user-supplied role names or identifiers.

#### Parameters

**`$InputString`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| InputString | System.String | Input string to sanitize. | $null |

**`$RemoveSpaces`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RemoveSpaces | System.Management.Automation.SwitchParameter | Remove all whitespace characters when set. | $false |

#### Outputs

System.String — The sanitized string suitable for use as a filename.

#### Examples

```powershell
PS> Remove-ModuleAmbitiousCharacters -InputString 'Admin Role #1' -RemoveSpaces
```

#### Notes

Only removes a restricted set of characters; callers may perform additional
normalization (lowercasing, trimming) if needed.

*Source: [src/Tools/Private/Remove-ModuleAmbitiousCharacters.ps1](../../src/Tools/Private/Remove-ModuleAmbitiousCharacters.ps1)*


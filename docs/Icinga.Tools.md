# Icinga.Tools

*Auto-generated from `src/Tools/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Compare-IcingaTextContent](#compare-icingatextcontent)
- [ConvertTo-IcingaSortedArray](#convertto-icingasortedarray)
- [ConvertTo-IcingaUnit](#convertto-icingaunit)
- [Get-IcingaUnixTime](#get-icingaunixtime)
- [Get-IcingaWindowsInformation](#get-icingawindowsinformation)
- [Join-WebPath](#join-webpath)
- [Resolve-IcingaIPAddress](#resolve-icingaipaddress)
- [Test-IcingaArrayFilter](#test-icingaarrayfilter)

## Private helpers

- [ConvertFrom-ModuleBoolean](#convertfrom-moduleboolean)
- [ConvertFrom-ModuleJson](#convertfrom-modulejson)
- [ConvertTo-ModuleJson](#convertto-modulejson)
- [ConvertTo-ModuleOrderedDictionary](#convertto-moduleordereddictionary)
- [ConvertTo-ModuleParameterValue](#convertto-moduleparametervalue)
- [ConvertTo-ModuleSecureString](#convertto-modulesecurestring)
- [ConvertTo-StringNormalizedArray](#convertto-stringnormalizedarray)
- [Format-ModuleCommandLineArguments](#format-modulecommandlinearguments)
- [Get-ModuleCommandParameterMap](#get-modulecommandparametermap)
- [Get-ModuleObjectValue](#get-moduleobjectvalue)
- [Get-NormalizedTextContent](#get-normalizedtextcontent)
- [Invoke-ModulePowerShellCommand](#invoke-modulepowershellcommand)
- [Remove-ModuleAmbitiousCharacters](#remove-moduleambitiouscharacters)
- [Test-ModuleWildcardMatch](#test-modulewildcardmatch)

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

| Name      | Type          | Description                                          | Default |
|-----------|---------------|------------------------------------------------------|---------|
| OldConfig | System.String | The baseline content as a JSON string or plain text. | $null   |

**`$OldFile`**

| Name    | Type          | Description                                                        | Default |
|---------|---------------|--------------------------------------------------------------------|---------|
| OldFile | System.String | File path to the baseline; read via Read-SecureFile when provided. | $null   |

**`$Colorized`**

| Name      | Type                                         | Description                                                   | Default |
|-----------|----------------------------------------------|---------------------------------------------------------------|---------|
| Colorized | System.Management.Automation.SwitchParameter | When set, embeds ANSI color codes (green/red/cyan) in output. | $false  |

#### Outputs

System.Collections.Hashtable -- Always returns @{ ExitCode = System.Int32; Output = System.String }.
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

*Source: [src/Tools/Public/Compare-IcingaTextContent.ps1](../src/Tools/Public/Compare-IcingaTextContent.ps1)*

---

### ConvertTo-IcingaSortedArray

*Public function*

**Synopsis:** Sort objects by one or more properties in natural order without a script block

#### Description

ConvertTo-IcingaSortedArray sorts an array without Sort-Object and without any
script block, so the plugins stay usable in JEA sessions. Every element gets a
sort key from IcingaSortKey once, then the native [Array]::Sort orders keys and
elements with an ordinal string comparison, which keeps the sort fast for large
inputs such as all Windows services.

The objects are compared by the given properties in order of precedence, or by
themselves when no property is given. Values sort in natural order: numbers
numerically and strings case-insensitively with digit runs compared by value,
so '0,2' comes before '0,10' and '_Total' after every numbered instance. The
sort is stable, equal elements keep their input order in both directions.
Hashtables are read by key, every other object (including CIM instances) by
member name.

#### Parameters

**`$InputObject`**

| Name        | Type         | Description           | Default |
|-------------|--------------|-----------------------|---------|
| InputObject | System.Array | The elements to sort. | @()     |

**`$Property`**

| Name     | Type         | Description                                                              | Default |
|----------|--------------|--------------------------------------------------------------------------|---------|
| Property | System.Array | Properties to sort by, in order of precedence; empty sorts the elements. | @()     |

**`$Descending`**

| Name       | Type                                         | Description               | Default |
|------------|----------------------------------------------|---------------------------|---------|
| Descending | System.Management.Automation.SwitchParameter | Sort in descending order. | False   |

#### Outputs

System.Object[] -- A new array with the sorted elements; the input stays unchanged.

#### Examples

```powershell
PS> ConvertTo-IcingaSortedArray -InputObject @('0,10', '_Total', '0,2', '0,_Total')

Returns @('0,2', '0,10', '0,_Total', '_Total').
```

```powershell
PS> ConvertTo-IcingaSortedArray -InputObject $Services -Property 'Name'

Sorts Win32_Service instances by their name.
```

#### Notes

No external dependencies. Replaces 'Sort-Object -Property { ... }' in plugin
code. The verb follows the approved PowerShell verbs; 'Sort' is not one of them.

*Source: [src/Tools/Public/ConvertTo-IcingaSortedArray.ps1](../src/Tools/Public/ConvertTo-IcingaSortedArray.ps1)*

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

*Source: [src/Tools/Public/ConvertTo-IcingaUnit.ps1](../src/Tools/Public/ConvertTo-IcingaUnit.ps1)*

---

### Get-IcingaUnixTime

*Public function*

**Synopsis:** Return the current Unix epoch timestamp in UTC

#### Description

Get-IcingaUnixTime returns the current UTC Unix timestamp relative to
1970-01-01T00:00:00Z using DateTimeOffset.UtcNow so local system timezones or
culture formats never skew the result. Without -Milliseconds it returns whole
seconds as an Int32; with -Milliseconds it returns fractional seconds with
millisecond precision as a Double, matching the timestamp format expected by
Icinga 2 check result payloads (execution_start and execution_end).

#### Parameters

**`$Milliseconds`**

| Name         | Type                                         | Description                                                                    | Default |
|--------------|----------------------------------------------|--------------------------------------------------------------------------------|---------|
| Milliseconds | System.Management.Automation.SwitchParameter | When set, returns fractional Unix seconds with millisecond precision (Double). | $false  |

#### Outputs

System.ValueType -- System.Int32 whole Unix seconds by default, or System.Double
fractional Unix seconds when -Milliseconds is set.

#### Examples

```powershell
PS> Get-IcingaUnixTime
1731750000

Returns the current UTC Unix time in whole seconds.
```

```powershell
PS> Get-IcingaUnixTime -Milliseconds
1731750000.123

Returns the current UTC Unix time in seconds with millisecond precision.
```

#### Notes

Uses System.DateTimeOffset.UtcNow across Windows PowerShell 5.1 and PowerShell 7+.

*Source: [src/Tools/Public/Get-IcingaUnixTime.ps1](../src/Tools/Public/Get-IcingaUnixTime.ps1)*

---

### Get-IcingaWindowsInformation

*Public function*

**Synopsis:** Query a CIM class and return its instances or an IcingaError

#### Description

Get-IcingaWindowsInformation is the single entry point for reading Windows
management data. It runs Get-CimInstance with -ErrorAction Stop and never
throws: on success it returns the instances as an array (empty when nothing
matches), on failure it returns an IcingaError that names the class, the
namespace and the reason, so a plugin can stop with one check:

    if (Test-IcingaError -InputObject $Data) { return $CheckPackage.SetError($Data).Compile(); }

Every exit goes through Write-FunctionReturnValue with its own return code, so
the log shows exactly which query succeeded or failed and why: a successful
query (WindowsInformationQueried), a missing class name
(WindowsInformationClassNameMissing), an unknown class
(WindowsInformationClassUnknown), an unknown namespace
(WindowsInformationNamespaceInvalid), missing permissions
(WindowsInformationAccessDenied), an invalid filter or property list
(WindowsInformationInvalidQuery) and every other error
(WindowsInformationQueryFailed). The return code of a failure is also stored in
the ReturnCode of the IcingaError.

OperationOption passes provider-specific custom options with the query, such as
@{ 'PolicyStore' = 'ActiveStore' } for the NetSecurity classes in
root/StandardCimv2. Get-CimInstance cannot carry them, so such a query runs as
WQL ('SELECT <Property> FROM <ClassName> WHERE <Filter>') through a local
CimSession, which is disposed afterwards. Errors map to the same return codes.

#### Parameters

**`$ClassName`**

| Name      | Type          | Description                     | Default |
|-----------|---------------|---------------------------------|---------|
| ClassName | System.String | Name of the CIM class to query. |         |

**`$Namespace`**

| Name      | Type          | Description                 | Default    |
|-----------|---------------|-----------------------------|------------|
| Namespace | System.String | CIM namespace of the class. | root/cimv2 |

**`$Filter`**

| Name   | Type          | Description                                   | Default |
|--------|---------------|-----------------------------------------------|---------|
| Filter | System.String | WQL filter, e.g. 'DriveType = 3'; '' for all. |         |

**`$Property`**

| Name     | Type         | Description                                     | Default |
|----------|--------------|-------------------------------------------------|---------|
| Property | System.Array | Properties to fetch; empty fetches all of them. | @()     |

**`$OperationOption`**

| Name            | Type                         | Description                                                           | Default |
|-----------------|------------------------------|-----------------------------------------------------------------------|---------|
| OperationOption | System.Collections.Hashtable | CIM custom options for the provider, e.g. @{ PolicyStore = 'RSOP' }.  | @{ }    |

#### Outputs

System.Object[] -- The CIM instances on success (an empty array when nothing
matches), or an IcingaError when the query failed.

#### Examples

```powershell
PS> Get-IcingaWindowsInformation -ClassName 'Win32_Volume' -Filter 'DriveType = 3' -Property 'Name', 'Capacity', 'FreeSpace'

Returns the local disk volumes with the three requested properties.
```

```powershell
PS> Get-IcingaWindowsInformation -ClassName 'MSFT_NetFirewallProfile' -Namespace 'root/StandardCimv2' -OperationOption @{ 'PolicyStore' = 'ActiveStore'; }

Returns the effective firewall profiles, merged from local settings and Group
Policy.
```

```powershell
PS> $Mpio =Get-IcingaWindowsInformation -ClassName 'MPIO_DISK_INFO' -Namespace 'root/wmi'

Returns an IcingaError with the return code WindowsInformationClassUnknown on
hosts without the MPIO feature.
```

#### Notes

Windows-only, uses the local CIM provider. The required permissions depend on
the class; standard users can read most root/cimv2 classes. Unknown classes and
namespaces are logged at Debug level only, because optional classes are probed
on purpose.

*Source: [src/Tools/Public/Get-IcingaWindowsInformation.ps1](../src/Tools/Public/Get-IcingaWindowsInformation.ps1)*

---

### Join-WebPath

*Public function*

**Synopsis:** Joins path segments into a single well-formed web path.

#### Description

Combines a base path and additional child path segments, handling trailing and leading slashes,
URL query parameters and avoiding duplicate slashes. Preserves scheme endings like '://'.

#### Parameters

**`$Path`**

| Name | Type          | Description                     | Default |
|------|---------------|---------------------------------|---------|
| Path | System.String | Base path or URL to start from. | $null   |

**`$ChildPath`**

| Name      | Type         | Description                                                                         | Default |
|-----------|--------------|-------------------------------------------------------------------------------------|---------|
| ChildPath | System.Array | Child path segments to append. Segments may start with /, ? or & for query strings. | $null   |

#### Outputs

System.String -- The assembled web path or URL.

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

*Source: [src/Tools/Public/Join-WebPath.ps1](../src/Tools/Public/Join-WebPath.ps1)*

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

| Name    | Type          | Description                                                                     | Default |
|---------|---------------|---------------------------------------------------------------------------------|---------|
| Address | System.String | Hostname or IP address to resolve. Empty or null triggers IPAddressLookupEmpty. | $null   |

#### Outputs

System.String -- IPv4 or IPv6 address string on success.
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

*Source: [src/Tools/Public/Resolve-IcingaIPAddress.ps1](../src/Tools/Public/Resolve-IcingaIPAddress.ps1)*

---

### Test-IcingaArrayFilter

*Public function*

**Synopsis:** Test a value against include and exclude wildcard lists

#### Description

Test-IcingaArrayFilter decides whether a value passes the usual plugin filters
-Include and -Exclude, without any script block. Both lists hold wildcard
patterns ('*', '?', '[a-z]') that are compared case-insensitively against the
value converted to a string. An exclude match always wins; with an empty include
list every value that is not excluded passes, otherwise at least one include
pattern has to match.

A single value returns a boolean. An array returns a new array with every
element that passes, so a whole list can be filtered in one call. An invalid
wildcard pattern is logged through Write-FunctionReturnValue
(ArrayFilterInvalidPattern) and the value is treated as not matching that
pattern.

#### Parameters

**`$InputObject`**

| Name        | Type          | Description                         | Default |
|-------------|---------------|-------------------------------------|---------|
| InputObject | System.Object | Value, or array of values, to test. | $null   |

**`$Include`**

| Name    | Type         | Description                                           | Default |
|---------|--------------|-------------------------------------------------------|---------|
| Include | System.Array | Wildcard patterns of which at least one has to match. | @()     |

**`$Exclude`**

| Name    | Type         | Description                                | Default |
|---------|--------------|--------------------------------------------|---------|
| Exclude | System.Array | Wildcard patterns of which none may match. | @()     |

#### Outputs

System.Boolean -- For a single value, whether it passes the filters.
System.Object[] -- For an array, the elements that pass the filters.

#### Examples

```powershell
PS> Test-IcingaArrayFilter -InputObject 'Spooler' -Include 'Spo*' -Exclude 'WinRM'

Returns $true.
```

```powershell
PS> Test-IcingaArrayFilter -InputObject @('C', 'D', 'E') -Exclude 'D'

Returns the array @('C', 'E').
```

#### Notes

No external dependencies. A $null value never passes. Used by the plugins for
their -Include/-Exclude parameters, which must not rely on script blocks so the
plugins stay usable in JEA sessions.

*Source: [src/Tools/Public/Test-IcingaArrayFilter.ps1](../src/Tools/Public/Test-IcingaArrayFilter.ps1)*

---

### ConvertFrom-ModuleBoolean

*Private function*

**Synopsis:** Convert boolean, numeric or string macro values into a PowerShell Boolean

#### Description

ConvertFrom-ModuleBoolean converts JSON and Icinga 2 macro values into a strict
System.Boolean so PowerShell switch and bool parameters never misinterpret
strings such as 'False' or '0' as truthy. Recognizes booleans, SwitchParameter
values, numeric 1/0, and case-insensitive strings ('true', '1', 'yes', '$true'
for $true; 'false', '0', 'no', '$false', '' and $null for $false). Unknown values
are logged through Write-FunctionReturnValue using StringToBoolConversionInvalidValue
and evaluate to $false.

#### Parameters

**`$Value`**

| Name  | Type          | Description                                        | Default |
|-------|---------------|----------------------------------------------------|---------|
| Value | System.Object | Input value from JSON or Icinga macros to convert. | $null   |

#### Outputs

System.Boolean -- Resolved boolean value ($true or $false).

#### Examples

```powershell
PS> ConvertFrom-ModuleBoolean -Value 'False'
False

Converts the string 'False' into boolean $false instead of PowerShell's non-empty
string truthiness.
```

#### Notes

Uses Write-FunctionReturnValue with key StringToBoolConversionInvalidValue when
an unrecognized value is supplied.

*Source: [src/Tools/Private/ConvertFrom-ModuleBoolean.ps1](../src/Tools/Private/ConvertFrom-ModuleBoolean.ps1)*

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

| Name        | Type          | Description                     | Default |
|-------------|---------------|---------------------------------|---------|
| InputObject | System.String | The JSON string to deserialize. | ''      |

#### Outputs

System.Collections.Hashtable -- Returns a hashtable (or dictionary) representation of the JSON string.
Returns `$null` if the input is empty or parsing fails.

#### Examples

```powershell
PS> $hashtable = ConvertFrom-ModuleJson -InputObject '{"key": "value"}'
```

#### Notes

In Windows PowerShell 5.1, this function dynamically loads the System.Web.Extensions
assembly if it is not already loaded in the current runspace.

*Source: [src/Tools/Private/ConvertFrom-ModuleJson.ps1](../src/Tools/Private/ConvertFrom-ModuleJson.ps1)*

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

| Name        | Type          | Description              | Default |
|-------------|---------------|--------------------------|---------|
| InputObject | System.Object | The object to serialize. | $null   |

#### Outputs

System.String -- Returns a JSON string representation of the object.
Returns an empty string if the input is null or serialization fails.

#### Examples

```powershell
PS> $json = ConvertTo-ModuleJson -InputObject @{ key = "value" }
```

#### Notes

In Windows PowerShell 5.1, this function dynamically loads the System.Web.Extensions
assembly if it is not already loaded.

*Source: [src/Tools/Private/ConvertTo-ModuleJson.ps1](../src/Tools/Private/ConvertTo-ModuleJson.ps1)*

---

### ConvertTo-ModuleOrderedDictionary

*Private function*

**Synopsis:** Convert a dictionary or object into a case-sensitive OrderedDictionary

#### Description

ConvertTo-ModuleOrderedDictionary normalizes any IDictionary (Hashtable,
Dictionary[string, object], OrderedDictionary) or PSCustomObject into a
System.Collections.Specialized.OrderedDictionary configured with
StringComparer.Ordinal so key order and case-distinct CLI flags (such as '-p'
and '-P') are preserved across Windows PowerShell 5.1 and PowerShell 7+. When
SkipEmptyKeys is enabled, null, empty and whitespace-only keys (such as Icinga
placeholder macros) are omitted.

#### Parameters

**`$InputObject`**

| Name        | Type          | Description                                | Default |
|-------------|---------------|--------------------------------------------|---------|
| InputObject | System.Object | Dictionary or object to copy entries from. | $null   |

**`$SkipEmptyKeys`**

| Name          | Type                                         | Description                                        | Default |
|---------------|----------------------------------------------|----------------------------------------------------|---------|
| SkipEmptyKeys | System.Management.Automation.SwitchParameter | Omit null, empty or whitespace-only keys when set. | $false  |

#### Outputs

System.Collections.Specialized.OrderedDictionary -- Case-sensitive ordered
dictionary containing the normalized entries.

#### Examples

```powershell
PS> $map = ConvertTo-ModuleOrderedDictionary -InputObject @{ '-p' = '8080' } -SkipEmptyKeys

Creates an ordinal OrderedDictionary preserving exact key casing.
```

#### Notes

Compatible with Windows PowerShell 5.1 and PowerShell 7+.

*Source: [src/Tools/Private/ConvertTo-ModuleOrderedDictionary.ps1](../src/Tools/Private/ConvertTo-ModuleOrderedDictionary.ps1)*

---

### ConvertTo-ModuleParameterValue

*Private function*

**Synopsis:** Coerce a raw JSON or macro value to match a PowerShell ParameterMetadata target

#### Description

ConvertTo-ModuleParameterValue centralizes parameter type coercion across native
Invoke-IcingaCheck* plugins and approved external PowerShell scripts (.ps1):
- SwitchParameter and Boolean values are converted deterministically through
  ConvertFrom-ModuleBoolean.
- SecureString values are copied (when already a SecureString) or converted via
  ConvertTo-ModuleSecureString and returned in AllocatedSecret for deterministic
  disposal by the caller.
- Typed and untyped array parameters skip empty strings and empty IList
  collections (@()), while coercing value-type and enum elements on typed arrays.
- Scalar numeric (12 .NET integer/floating-point types) and enum parameters skip
  whitespace/empty strings and empty IList values before coercing with '-as'.
- String parameters carrying ValidateSet or ValidatePattern attributes skip
  empty or whitespace values that are not explicitly listed as valid.

#### Parameters

**`$ParameterMetadata`**

| Name              | Type          | Description                                               | Default |
|-------------------|---------------|-----------------------------------------------------------|---------|
| ParameterMetadata | System.Object | PowerShell ParameterMetadata describing the target param. | $null   |

**`$RawValue`**

| Name     | Type          | Description                                      | Default |
|----------|---------------|--------------------------------------------------|---------|
| RawValue | System.Object | Raw JSON, CLI or macro value to coerce and bind. | $null   |

#### Outputs

System.Collections.Hashtable -- Hashtable containing Status ('Bound', 'Skipped'
or 'Error'), Value, IsSecret, AllocatedSecret and ErrorReason.

#### Examples

```powershell
PS> $cmd = Get-Command -Name 'Invoke-IcingaCheckDirectory'
PS> ConvertTo-ModuleParameterValue -ParameterMetadata $cmd.Parameters['Verbosity'] -RawValue '2'

Coerces the string '2' into Int32 2 with Status 'Bound'.
```

#### Notes

Callers must call Dispose() on AllocatedSecret when non-null once command
execution completes.

*Source: [src/Tools/Private/ConvertTo-ModuleParameterValue.ps1](../src/Tools/Private/ConvertTo-ModuleParameterValue.ps1)*

---

### ConvertTo-ModuleSecureString

*Private function*

**Synopsis:** Convert plain-text or existing secret input into a SecureString safely

#### Description

ConvertTo-ModuleSecureString converts plain-text strings delivered through
Icinga 2 command macros into read-only System.Security.SecureString instances
via direct character population (AppendChar + MakeReadOnly), avoiding both
ConvertTo-SecureString -AsPlainText analyzer errors and empty-string
ParameterBindingException failures on Windows PowerShell 5.1. Null values
return $null, existing SecureString instances are returned unchanged, and
conversion errors emit SecureStringConversionFailed via
Write-FunctionReturnValue and return $null.

#### Parameters

**`$InputObject`**

| Name        | Type          | Description                                                 | Default |
|-------------|---------------|-------------------------------------------------------------|---------|
| InputObject | System.Object | Plain-text string, SecureString or null value to normalize. | $null   |

#### Outputs

System.Security.SecureString -- Converted SecureString instance, or $null when
InputObject is $null or conversion fails (SecureStringConversionFailed).

#### Examples

```powershell
PS> $secret = ConvertTo-ModuleSecureString -InputObject 'MySecretValue'

Converts the plain-text string into a SecureString instance.
```

#### Notes

Compatible with Windows PowerShell 5.1 and PowerShell 7+. Callers that allocate
temporary SecureString instances for check execution should call Dispose() once
the check finishes.

*Source: [src/Tools/Private/ConvertTo-ModuleSecureString.ps1](../src/Tools/Private/ConvertTo-ModuleSecureString.ps1)*

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

| Name       | Type            | Description                                                       | Default |
|------------|-----------------|-------------------------------------------------------------------|---------|
| InputArray | System.Object[] | Array of items to normalize; string items will be case-normalized | @()     |

**`$UpperCase`**

| Name      | Type   | Description                                                        | Default |
|-----------|--------|--------------------------------------------------------------------|---------|
| UpperCase | Switch | When set, convert string items to upper-case instead of lower-case | $false  |

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

*Source: [src/Tools/Private/ConvertTo-StringNormalizedArray.ps1](../src/Tools/Private/ConvertTo-StringNormalizedArray.ps1)*

---

### Format-ModuleCommandLineArguments

*Private function*

**Synopsis:** Format an array of CLI tokens using Windows CommandLineToArgvW quoting rules

#### Description

Format-ModuleCommandLineArguments escapes and space-joins an array of argument
tokens according to the Windows C runtime and CommandLineToArgvW specification:
empty tokens become '""', tokens without whitespace or double quotes remain
unquoted, and tokens containing whitespace or double quotes are wrapped in
double quotes with preceding backslashes doubled before embedded quotes and
before the closing quote.

#### Parameters

**`$Arguments`**

| Name      | Type         | Description                                    | Default |
|-----------|--------------|------------------------------------------------|---------|
| Arguments | System.Array | Ordered CLI argument tokens to quote and join. | @()     |

#### Outputs

System.String -- Space-joined, CommandLineToArgvW-compliant argument string.

#### Examples

```powershell
PS> Format-ModuleCommandLineArguments -Arguments @('-H', 'X-Test: 1', 'C:\Trailing\')
-H "X-Test: 1" C:\Trailing\

Quotes tokens containing spaces or quotes while leaving simple tokens intact.
```

#### Notes

Pure string formatter with no external dependencies or global state access.

*Source: [src/Tools/Private/Format-ModuleCommandLineArguments.ps1](../src/Tools/Private/Format-ModuleCommandLineArguments.ps1)*

---

### Get-ModuleCommandParameterMap

*Private function*

**Synopsis:** Build a parameter lookup table and ordered positional parameter list for a command

#### Description

Get-ModuleCommandParameterMap inspects the Parameters dictionary of a PowerShell
CommandInfo object, filters out the 14 built-in PowerShell common and
ShouldProcess parameters, registers every canonical parameter name and alias in
a case-insensitive Lookup hashtable, and produces an ordered Positional list
excluding ValueFromRemainingArguments parameters (honoring explicit non-negative
Position attributes first and declaration order thereafter).

#### Parameters

**`$Parameters`**

| Name       | Type          | Description                                               | Default |
|------------|---------------|-----------------------------------------------------------|---------|
| Parameters | System.Object | CommandInfo.Parameters dictionary to index and normalize. | $null   |

#### Outputs

System.Collections.Hashtable -- Hashtable containing Lookup (Hashtable of
canonical and alias names to ParameterMetadata) and Positional (Array of
ordered ParameterMetadata entries).

#### Examples

```powershell
PS> $cmd = Get-Command -Name 'Invoke-IcingaCheckDirectory'
PS> $map = Get-ModuleCommandParameterMap -Parameters $cmd.Parameters

Builds the canonical/alias lookup map and positional list for the command.
```

#### Notes

Pure metadata helper with no external dependencies or side effects.

*Source: [src/Tools/Private/Get-ModuleCommandParameterMap.ps1](../src/Tools/Private/Get-ModuleCommandParameterMap.ps1)*

---

### Get-ModuleObjectValue

*Private function*

**Synopsis:** Retrieve a property or key value case-insensitively from a dictionary or object

#### Description

Get-ModuleObjectValue performs a uniform, null-safe lookup across PowerShell
hashtables, Windows PowerShell 5.1 Dictionary[string, object] instances,
OrderedDictionary collections and PSCustomObject payloads. Exact-case keys are
checked first on IDictionary instances before falling back to an
OrdinalIgnoreCase scan so case-distinct keys remain deterministic while
deserialized JSON payloads remain accessible regardless of casing. Collection
values (such as arrays and ArrayLists) are returned without PowerShell pipeline
unrolling.

#### Parameters

**`$InputObject`**

| Name        | Type          | Description                                        | Default |
|-------------|---------------|----------------------------------------------------|---------|
| InputObject | System.Object | Dictionary or object to read the named value from. | $null   |

**`$Name`**

| Name | Type          | Description                                     | Default |
|------|---------------|-------------------------------------------------|---------|
| Name | System.String | Key or property name to look up on InputObject. | ''      |

**`$DefaultValue`**

| Name         | Type          | Description                                              | Default |
|--------------|---------------|----------------------------------------------------------|---------|
| DefaultValue | System.Object | Fallback value returned when the key is missing or null. | $null   |

#### Outputs

System.Object -- Matched property or dictionary value, or DefaultValue when
missing or null.

#### Examples

```powershell
PS> Get-ModuleObjectValue -InputObject @{ 'Check_Timeout' = 30 } -Name 'check_timeout' -DefaultValue 60
30

Reads the value of 'Check_Timeout' case-insensitively from the dictionary.
```

#### Notes

Compatible with Windows PowerShell 5.1 and PowerShell 7+. Does not mutate global
state.

*Source: [src/Tools/Private/Get-ModuleObjectValue.ps1](../src/Tools/Private/Get-ModuleObjectValue.ps1)*

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

System.String -- Re-serialized JSON string when the input is valid JSON, the
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

*Source: [src/Tools/Private/Get-NormalizedTextContent.ps1](../src/Tools/Private/Get-NormalizedTextContent.ps1)*

---

### Invoke-ModulePowerShellCommand

*Private function*

**Synopsis:** Execute a PowerShell check command or external script with isolated runtime state

#### Description

Invoke-ModulePowerShellCommand provides the single, runspace-safe execution
wrapper for native Invoke-IcingaCheck* plugins and external .ps1 scripts inside
Get-ModuleBinaryDirectory:
1. Saves Protected.IsBackgroundDaemon, enables daemon mode to suppress direct
   console writes, and clears thread-local Private.Icinga.CheckResult and
   Private.Icinga.ActiveCheckCommand (plus LASTEXITCODE when UseLastExitCode is
   enabled).
2. Invokes the target command in-process with '&' (never dot-sourced).
3. Reads primitive ExitCode, Output and PerformanceData from
   Private.Icinga.CheckResult when populated by IcingaPlugin.Compile(), or falls
   back to Split-IcingaBinaryPluginOutput for standard Nagios/Icinga stdout.
4. Restores Protected.IsBackgroundDaemon, clears thread-local CheckResult and
   ActiveCheckCommand slots, and disposes every entry in AllocatedSecrets inside
   a finally block.

#### Parameters

**`$Command`**

| Name    | Type          | Description                                               | Default |
|---------|---------------|-----------------------------------------------------------|---------|
| Command | System.String | PowerShell command name or full .ps1 script path to call. | ''      |

**`$NamedArguments`**

| Name           | Type                         | Description                          | Default |
|----------------|------------------------------|--------------------------------------|---------|
| NamedArguments | System.Collections.Hashtable | Named parameter splatting hashtable. | @{}     |

**`$PositionalArguments`**

| Name                | Type         | Description                                    | Default |
|---------------------|--------------|------------------------------------------------|---------|
| PositionalArguments | System.Array | Optional positional arguments to pass after @. | @()     |

**`$AllocatedSecrets`**

| Name             | Type         | Description                                             | Default |
|------------------|--------------|---------------------------------------------------------|---------|
| AllocatedSecrets | System.Array | Temporary SecureString instances to dispose in finally. | @()     |

**`$UseLastExitCode`**

| Name            | Type                                         | Description                                                  | Default |
|-----------------|----------------------------------------------|--------------------------------------------------------------|---------|
| UseLastExitCode | System.Management.Automation.SwitchParameter | Fall back to $global:LASTEXITCODE for external .ps1 scripts. | $false  |

**`$ErrorContext`**

| Name         | Type          | Description                                                    | Default |
|--------------|---------------|----------------------------------------------------------------|---------|
| ErrorContext | System.String | Optional custom prefix for [UNKNOWN] unhandled error messages. | ''      |

#### Outputs

System.Collections.Hashtable -- Plain hashtable containing primitive ExitCode,
Output and PerformanceData values safe to pass across runspaces.

#### Examples

```powershell
PS> Invoke-ModulePowerShellCommand -Command 'Invoke-IcingaCheckUptime' -NamedArguments @{ 'Verbosity' = 2 }

Executes Invoke-IcingaCheckUptime in daemon mode and returns its primitive check
result hashtable.
```

#### Notes

Accesses runtime state exclusively via Get-GlobalRuntimeVariable. Never returns
PowerShell class instances across thread boundaries.

*Source: [src/Tools/Private/Invoke-ModulePowerShellCommand.ps1](../src/Tools/Private/Invoke-ModulePowerShellCommand.ps1)*

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

| Name        | Type          | Description               | Default |
|-------------|---------------|---------------------------|---------|
| InputString | System.String | Input string to sanitize. | $null   |

**`$RemoveSpaces`**

| Name         | Type                                         | Description                                | Default |
|--------------|----------------------------------------------|--------------------------------------------|---------|
| RemoveSpaces | System.Management.Automation.SwitchParameter | Remove all whitespace characters when set. | $false  |

#### Outputs

System.String -- The sanitized string suitable for use as a filename.

#### Examples

```powershell
PS> Remove-ModuleAmbitiousCharacters -InputString 'Admin Role #1' -RemoveSpaces
```

#### Notes

Only removes a restricted set of characters; callers may perform additional
normalization (lowercasing, trimming) if needed.

*Source: [src/Tools/Private/Remove-ModuleAmbitiousCharacters.ps1](../src/Tools/Private/Remove-ModuleAmbitiousCharacters.ps1)*

---

### Test-ModuleWildcardMatch

*Private function*

**Synopsis:** Test a string against a single wildcard pattern without throwing

#### Description

Compares the value case-insensitively with a wildcard pattern ('*', '?',
'[a-z]'). An invalid pattern, such as an unclosed '[', is logged through
Write-FunctionReturnValue (ArrayFilterInvalidPattern) and counts as no match, so
a broken filter argument never aborts a plugin.

#### Parameters

**`$Value`**

| Name  | Type          | Description        | Default |
|-------|---------------|--------------------|---------|
| Value | System.String | The value to test. |         |

**`$Pattern`**

| Name    | Type          | Description                | Default |
|---------|---------------|----------------------------|---------|
| Pattern | System.String | Wildcard pattern to match. |         |

#### Outputs

System.Boolean -- True when the value matches the pattern.

#### Examples

```powershell
PS> Test-ModuleWildcardMatch -Value 'Spooler' -Pattern 'spo*'

Returns $true.
```

#### Notes

Internal helper of Test-IcingaArrayFilter.

*Source: [src/Tools/Private/Test-ModuleWildcardMatch.ps1](../src/Tools/Private/Test-ModuleWildcardMatch.ps1)*


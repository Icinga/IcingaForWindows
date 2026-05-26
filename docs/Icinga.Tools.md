# Icinga.Tools

*Auto-generated from `src/Tools/`. Do not edit by hand — run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Get-IcingaUnixTime](#get-icingaunixtime)
- [Join-WebPath](#join-webpath)
- [Resolve-IcingaIPAddress](#resolve-icingaipaddress)

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



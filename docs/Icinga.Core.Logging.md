# Icinga.Core.Logging

*Auto-generated from `src/Core/Logging/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Set-IcingaLogLevel](#set-icingaloglevel)

## Private helpers

- [Format-LoggingConsoleException](#format-loggingconsoleexception)
- [Format-LoggingConsoleMessage](#format-loggingconsolemessage)
- [Format-LoggingConsoleNullValue](#format-loggingconsolenullvalue)
- [Format-LoggingConsoleObjectProperties](#format-loggingconsoleobjectproperties)
- [Format-LoggingConsoleObjects](#format-loggingconsoleobjects)
- [Format-LoggingConsoleScalar](#format-loggingconsolescalar)
- [Format-LoggingConsoleSslStream](#format-loggingconsolesslstream)
- [Format-LoggingConsoleTcpClient](#format-loggingconsoletcpclient)
- [Format-LoggingConsoleTcpListener](#format-loggingconsoletcplistener)
- [Format-LoggingConsoleTlsCertificate](#format-loggingconsoletlscertificate)
- [Get-LoggingConsoleColorForObjectType](#get-loggingconsolecolorforobjecttype)
- [Get-LoggingConsoleColorForValue](#get-loggingconsolecolorforvalue)
- [Get-LoggingConsoleNestedProperty](#get-loggingconsolenestedproperty)
- [Get-LoggingEventLogSeverity](#get-loggingeventlogseverity)
- [Register-LoggingWindowsEventLog](#register-loggingwindowseventlog)
- [Set-LoggingLogLevel](#set-loggingloglevel)
- [Start-LoggingDaemon](#start-loggingdaemon)
- [Test-LoggingConsoleNextObjectIterable](#test-loggingconsolenextobjectiterable)
- [Test-LoggingWriteLog](#test-loggingwritelog)
- [Update-LoggingThreadLoggingId](#update-loggingthreadloggingid)
- [Write-LoggingEntry](#write-loggingentry)

---

### Set-IcingaLogLevel

*Public function*

**Synopsis:** Set the global logging level for Icinga

#### Description

`Set-IcingaLogLevel` updates the module-wide logging threshold stored in
`$Global:Icinga.Public.Logging.Level`. The logging subsystem uses this value
to decide which messages should be enqueued and processed. Use one of the
predefined levels to control verbosity.

#### Parameters

**`$Level`**

| Name  | Type          | Description                   | Default |
|-------|---------------|-------------------------------|---------|
| Level | System.String | Desired minimum logging level | 'Info'  |

#### Outputs

None -- This function sets a global variable and does not emit pipeline output.

#### Examples

```powershell
PS> Set-IcingaLogLevel -Level 'Warning'
```

#### Notes

Valid levels are `Debug`, `Audit`, `Info`, `Success`, `Warning`, `Error` and `Fatal`.
`Test-LoggingWriteLog` consults the global level to decide whether a message
at a given severity should be emitted.

*Source: [src/Core/Logging/Public/Set-IcingaLogLevel.ps1](../src/Core/Logging/Public/Set-IcingaLogLevel.ps1)*

---

### Format-LoggingConsoleException

*Private function*

**Synopsis:** Format an exception object for console output.

#### Description

`Format-LoggingConsoleException` returns a formatted representation of an exception
using `Format-LoggingConsoleObjectProperties` and a predefined set of properties.

#### Parameters

**`$Exception`**

| Name      | Type             | Description             | Default |
|-----------|------------------|-------------------------|---------|
| Exception | System.Exception | The exception to format |         |

**`$Indent`**

| Name   | Type          | Description                                       | Default |
|--------|---------------|---------------------------------------------------|---------|
| Indent | System.String | Optional indentation string for nested formatting | ''      |

#### Outputs

System.String -- A formatted multiline string describing the exception.

#### Examples

```powershell
PS> Format-LoggingConsoleException -Exception $ex -Indent '  '
```

#### Notes

Uses `Format-LoggingConsoleObjectProperties` to extract common exception details.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleException.ps1](../src/Core/Logging/Private/Format-LoggingConsoleException.ps1)*

---

### Format-LoggingConsoleMessage

*Private function*

**Synopsis:** Format a markup-colored logging message for console output.

#### Description

`Format-LoggingConsoleMessage` parses simple color markup tokens (e.g. [Red]...[/Red])
and returns either a formatted string or writes the colored message to the host.

#### Parameters

**`$Message`**

| Name    | Type          | Description                            | Default |
|---------|---------------|----------------------------------------|---------|
| Message | System.String | Message containing optional color tags |         |

**`$GetMsgObj`**

| Name      | Type                   | Description                                                                   | Default  |
|-----------|------------------------|-------------------------------------------------------------------------------|----------|
| GetMsgObj | System.SwitchParameter | When set the function returns the formatted string instead of writing to host | `$false` |

#### Outputs

System.String -- The formatted message string when `-GetMsgObj` is set; otherwise None, the message is written directly to the host.

#### Examples

```powershell
PS> Format-LoggingConsoleMessage -Message '[Green]OK[/Green] Completed' -GetMsgObj
```

#### Notes

Supports escaping and validates color names against `System.ConsoleColor`.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleMessage.ps1](../src/Core/Logging/Private/Format-LoggingConsoleMessage.ps1)*

---

### Format-LoggingConsoleNullValue

*Private function*

**Synopsis:** Return a formatted representation for null values in console output.

#### Description

`Format-LoggingConsoleNullValue` returns a short, colored string representation
for null values used throughout logging output formatting helpers.

#### Parameters

**`$Indent`**

| Name   | Type          | Description                                         | Default |
|--------|---------------|-----------------------------------------------------|---------|
| Indent | System.String | Optional prefix indentation for the returned string | ''      |

#### Outputs

System.String -- A one-line formatted representation of a null value.

#### Examples

```powershell
PS> Format-LoggingConsoleNullValue -Indent '  '
```

#### Notes

Used by multiple formatting helpers to ensure consistent null rendering.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleNullValue.ps1](../src/Core/Logging/Private/Format-LoggingConsoleNullValue.ps1)*

---

### Format-LoggingConsoleObjectProperties

*Private function*

**Synopsis:** Format selected properties of an object for console logging.

#### Description

`Format-LoggingConsoleObjectProperties` extracts named properties (including nested)
from an object and returns a colorized string suitable for console logging.

#### Parameters

**`$Object`**

| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Object | System.Object | The input object to inspect |         |

**`$Properties`**

| Name       | Type         | Description                                               | Default |
|------------|--------------|-----------------------------------------------------------|---------|
| Properties | System.Array | List of property paths to extract (e.g. 'Client.Address') | @()     |

**`$Indent`**

| Name   | Type          | Description                                | Default |
|--------|---------------|--------------------------------------------|---------|
| Indent | System.String | Indentation prefix for each formatted line | ''      |

#### Outputs

System.String -- A multi-line formatted string with property:value pairs.

#### Examples

```powershell
PS> Format-LoggingConsoleObjectProperties -Object $resp -Properties @('Status','Body')
```

#### Notes

Relies on `Get-LoggingConsoleNestedProperty`, `Get-LoggingConsoleColorForObjectType`,
and `Get-LoggingConsoleColorForValue` for nested access and color selection.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleObjectProperties.ps1](../src/Core/Logging/Private/Format-LoggingConsoleObjectProperties.ps1)*

---

### Format-LoggingConsoleObjects

*Private function*

**Synopsis:** Render complex objects into a readable, colorized console representation.

#### Description

`Format-LoggingConsoleObjects` handles arrays, hashtables, PSCustomObjects and
several special CLR types (TcpClient, SslStream, X509Certificate2, TcpListener)
and returns a string with structured, colorized output for logging.

#### Parameters

**`$Object`**

| Name   | Type          | Description                             | Default |
|--------|---------------|-----------------------------------------|---------|
| Object | System.Object | The object to format for console output |         |

**`$Level`**

| Name  | Type         | Description                                   | Default |
|-------|--------------|-----------------------------------------------|---------|
| Level | System.Int32 | Indentation/nesting level for pretty printing | 0       |

#### Outputs

System.String -- A formatted multi-line representation of the object.

#### Examples

```powershell
PS> Format-LoggingConsoleObjects -Object $response -Level 1
```

#### Notes

This function delegates to other helpers (scalar, properties, nested access)
and is the central place for human-friendly logging formatting.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleObjects.ps1](../src/Core/Logging/Private/Format-LoggingConsoleObjects.ps1)*

---

### Format-LoggingConsoleScalar

*Private function*

**Synopsis:** Format a scalar value with color for console logging.

#### Description

`Format-LoggingConsoleScalar` returns a one-line colored string for scalar values
using `Get-LoggingConsoleColorForValue` to determine an appropriate color.

#### Parameters

**`$Object`**

| Name   | Type          | Description         | Default |
|--------|---------------|---------------------|---------|
| Object | System.Object | The value to format |         |

**`$Indent`**

| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | ''      |

#### Outputs

System.String -- A formatted single-line representation of the scalar value.

#### Examples

```powershell
PS> Format-LoggingConsoleScalar -Object 123 -Indent '  '
```

#### Notes

Used internally by `Format-LoggingConsoleObjects` for fallback scalar formatting.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleScalar.ps1](../src/Core/Logging/Private/Format-LoggingConsoleScalar.ps1)*

---

### Format-LoggingConsoleSslStream

*Private function*

**Synopsis:** Format `SslStream` properties for console output.

#### Description

`Format-LoggingConsoleSslStream` extracts and formats commonly useful properties
from a `System.Net.Security.SslStream` and returns a colorized string.

#### Parameters

**`$Stream`**

| Name   | Type                          | Description               | Default |
|--------|-------------------------------|---------------------------|---------|
| Stream | System.Net.Security.SslStream | The SSL stream to inspect |         |

**`$Indent`**

| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | $null   |

#### Outputs

System.String -- A multi-line formatted representation of the stream properties.

#### Examples

```powershell
PS> Format-LoggingConsoleSslStream -Stream $sslStream -Indent '  '
```

#### Notes

Delegates property extraction to `Format-LoggingConsoleObjectProperties`.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleSslStream.ps1](../src/Core/Logging/Private/Format-LoggingConsoleSslStream.ps1)*

---

### Format-LoggingConsoleTcpClient

*Private function*

**Synopsis:** Format a `TcpClient` for console logging.

#### Description

`Format-LoggingConsoleTcpClient` returns a formatted representation of a
`System.Net.Sockets.TcpClient`, including connection status and endpoints.

#### Parameters

**`$Client`**

| Name   | Type                         | Description                       | Default |
|--------|------------------------------|-----------------------------------|---------|
| Client | System.Net.Sockets.TcpClient | The TCP client instance to format |         |

**`$Indent`**

| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | ''      |

#### Outputs

System.String -- A formatted multi-line description of the `TcpClient`.

#### Examples

```powershell
PS> Format-LoggingConsoleTcpClient -Client $client
```

#### Notes

This helper uses `Format-LoggingConsoleObjectProperties` for property extraction.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleTcpClient.ps1](../src/Core/Logging/Private/Format-LoggingConsoleTcpClient.ps1)*

---

### Format-LoggingConsoleTcpListener

*Private function*

**Synopsis:** Format a `TcpListener` object for console logging.

#### Description

`Format-LoggingConsoleTcpListener` extracts and formats selected properties of a
`System.Net.Sockets.TcpListener` and returns a colorized string for logging.

#### Parameters

**`$TcpListener`**

| Name        | Type                           | Description            | Default |
|-------------|--------------------------------|------------------------|---------|
| TcpListener | System.Net.Sockets.TcpListener | The listener to format |         |

**`$Indent`**

| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | ''      |

#### Outputs

System.String -- A formatted string describing listener properties.

#### Examples

```powershell
PS> Format-LoggingConsoleTcpListener -TcpListener $listener
```

#### Notes

Used to present network listener details consistently in logs.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleTcpListener.ps1](../src/Core/Logging/Private/Format-LoggingConsoleTcpListener.ps1)*

---

### Format-LoggingConsoleTlsCertificate

*Private function*

**Synopsis:** Format an X509 certificate for console logging.

#### Description

`Format-LoggingConsoleTlsCertificate` extracts a set of useful properties from a
`System.Security.Cryptography.X509Certificates.X509Certificate2` and returns
them as a colorized multi-line string for inclusion in logs.

#### Parameters

**`$Certificate`**

| Name        | Type                                                           | Description           | Default |
|-------------|----------------------------------------------------------------|-----------------------|---------|
| Certificate | System.Security.Cryptography.X509Certificates.X509Certificate2 | Certificate to format |         |

**`$Indent`**

| Name   | Type          | Description                 | Default |
|--------|---------------|-----------------------------|---------|
| Indent | System.String | Optional indentation prefix | ''      |

#### Outputs

System.String -- A formatted representation of the certificate.

#### Examples

```powershell
PS> Format-LoggingConsoleTlsCertificate -Certificate $cert
```

#### Notes

Useful when logging TLS connection metadata.

*Source: [src/Core/Logging/Private/Format-LoggingConsoleTlsCertificate.ps1](../src/Core/Logging/Private/Format-LoggingConsoleTlsCertificate.ps1)*

---

### Get-LoggingConsoleColorForObjectType

*Private function*

**Synopsis:** Select a console color name for a given object type or parameter.

#### Description

`Get-LoggingConsoleColorForObjectType` returns a string matching a
`System.ConsoleColor` name appropriate for the provided object name or
for special cases like parameters and null values.

#### Parameters

**`$ObjectName`**

| Name       | Type          | Description                                    | Default |
|------------|---------------|------------------------------------------------|---------|
| ObjectName | System.String | The CLR type name or friendly name to evaluate |         |

**`$IsParameter`**

| Name        | Type                   | Description                                         | Default |
|-------------|------------------------|-----------------------------------------------------|---------|
| IsParameter | System.SwitchParameter | When set returns the color used for parameter names | $false  |

**`$IsNullValue`**

| Name        | Type                   | Description                                     | Default |
|-------------|------------------------|-------------------------------------------------|---------|
| IsNullValue | System.SwitchParameter | When set returns the color used for null values | $false  |

#### Outputs

System.String -- The name of a `System.ConsoleColor` value.

#### Examples

```powershell
PS> Get-LoggingConsoleColorForObjectType -ObjectName 'String'
```

#### Notes

Color choices are mapped to common CLR type names and special flags.

*Source: [src/Core/Logging/Private/Get-LoggingConsoleColorForObjectType.ps1](../src/Core/Logging/Private/Get-LoggingConsoleColorForObjectType.ps1)*

---

### Get-LoggingConsoleColorForValue

*Private function*

**Synopsis:** Return the console color name for an arbitrary value.

#### Description

`Get-LoggingConsoleColorForValue` inspects the input value and returns an
appropriate `System.ConsoleColor` name by delegating to
`Get-LoggingConsoleColorForObjectType` with the value's CLR type name.

#### Parameters

**`$Value`**

| Name  | Type          | Description                     | Default |
|-------|---------------|---------------------------------|---------|
| Value | System.Object | The value to choose a color for |         |

#### Outputs

System.String -- The chosen console color name.

#### Examples

```powershell
PS> Get-LoggingConsoleColorForValue -Value 42
```

#### Notes

Returns a special color for `$null` values.

*Source: [src/Core/Logging/Private/Get-LoggingConsoleColorForValue.ps1](../src/Core/Logging/Private/Get-LoggingConsoleColorForValue.ps1)*

---

### Get-LoggingConsoleNestedProperty

*Private function*

**Synopsis:** Resolve a nested property path on an object safely.

#### Description

`Get-LoggingConsoleNestedProperty` walks a dot-separated property path (for example
'Client.Address') on an input object and returns the resolved value or `$null` if
any segment cannot be resolved.

#### Parameters

**`$InputObject`**

| Name        | Type          | Description         | Default |
|-------------|---------------|---------------------|---------|
| InputObject | System.Object | The object to query |         |

**`$PropertyPath`**

| Name         | Type          | Description                            | Default |
|--------------|---------------|----------------------------------------|---------|
| PropertyPath | System.String | Dot-separated property path to resolve |         |

#### Outputs

System.Object -- The resolved property value or `$null` when not found.

#### Examples

```powershell
PS> Get-LoggingConsoleNestedProperty -InputObject $resp -PropertyPath 'Client.Address'
```

#### Notes

This helper intentionally swallows property access errors and returns `$null` on failure.

*Source: [src/Core/Logging/Private/Get-LoggingConsoleNestedProperty.ps1](../src/Core/Logging/Private/Get-LoggingConsoleNestedProperty.ps1)*

---

### Get-LoggingEventLogSeverity

*Private function*

**Synopsis:** Map internal log severity to Windows EventLog entry types.

#### Description

`Get-LoggingEventLogSeverity` converts module logging severity labels to
Windows EventLog entry types such as 'Information' or 'Error'.

#### Parameters

**`$Severity`**

| Name     | Type          | Description                                     | Default |
|----------|---------------|-------------------------------------------------|---------|
| Severity | System.String | Internal severity string (e.g. 'Debug', 'Info') |         |

#### Outputs

System.String -- The Windows EventLog entry type name.

#### Examples

```powershell
PS> Get-LoggingEventLogSeverity -Severity 'Error'
```

#### Notes

Unknown severities default to 'Information'.

*Source: [src/Core/Logging/Private/Get-LoggingEventLogSeverity.ps1](../src/Core/Logging/Private/Get-LoggingEventLogSeverity.ps1)*

---

### Register-LoggingWindowsEventLog

*Private function*

**Synopsis:** Create and configure Windows Event Log sources for Icinga for Windows

#### Description

Register-LoggingWindowsEventLog registers every unique IcingaForWindows::<Area>
Windows Event Log source from (Get-GlobalRuntimeVariable).Public.ReturnCodes
(always seeding IcingaForWindows::Logging) and configures the maximum log size
to 100 MiB (104857600 bytes). On non-Windows platforms the function returns
immediately without side effects.

#### Outputs

None -- Registers event sources under the module name and configures the maximum log size.

#### Examples

```powershell
PS> Set-InternalExitCodes
PS> Register-LoggingWindowsEventLog

Populates the internal return-code registry, registers all Icinga for Windows
Event Log sources, and configures the 100 MiB maximum log size.
```

#### Notes

Requires administrative privileges on Windows to create Windows Event Log
sources and modify log settings. Callers (such as Install-IcingaForWindows)
must invoke Set-InternalExitCodes beforehand so
(Get-GlobalRuntimeVariable).Public.ReturnCodes is populated with all subsystem
Area definitions prior to source enumeration. The module name is resolved via
Get-ModuleProjectName, and sources are checked and registered in-process via
[System.Diagnostics.EventLog]::SourceExists and
[System.Diagnostics.EventLog]::CreateEventSource on both Windows PowerShell 5.1
and PowerShell 7+.

*Source: [src/Core/Logging/Private/Register-LoggingWindowsEventLog.ps1](../src/Core/Logging/Private/Register-LoggingWindowsEventLog.ps1)*

---

### Set-LoggingLogLevel

*Private function*

**Synopsis:** Set the global logging level for this module.

#### Description

`Set-LoggingLogLevel` updates the runtime logging level in the global
runtime variable so subsequent log writes follow the desired verbosity.

#### Parameters

**`$Level`**

| Name  | Type          | Description                                                       | Default |
|-------|---------------|-------------------------------------------------------------------|---------|
| Level | System.String | One of 'Debug','Audit','Info','Success','Warning','Error','Fatal' | 'Info'  |

#### Outputs

None -- Updates `(Get-GlobalRuntimeVariable).Public.Logging.Level`.

#### Examples

```powershell
PS> Set-LoggingLogLevel -Level 'Debug'
```

#### Notes

Use `Test-LoggingWriteLog` to determine whether a message at a given level will be emitted.

*Source: [src/Core/Logging/Private/Set-LoggingLogLevel.ps1](../src/Core/Logging/Private/Set-LoggingLogLevel.ps1)*

---

### Start-LoggingDaemon

*Private function*

**Synopsis:** Background logging daemon that consumes the logging queue

#### Description

`Start-LoggingDaemon` runs in a loop while `Test-ThreadRunning` is true
and processes objects from the global logging queue. It formats messages,
writes Windows Event Log entries on Windows hosts, and prints colorized output
to the console.

#### Outputs

None -- Operates for side effects (writes logs and event entries).

#### Examples

```powershell
PS> Start-LoggingDaemon

Starts the blocking logging queue consumer loop inside a background runspace.
```

#### Notes

This function must be executed inside a dedicated background runspace. It blocks
while polling `BlockingCollection.TryTake()` on the logging queue, so it must
never run on the main thread. All access to shared state goes through
`Get-GlobalRuntimeVariable` because the runspace receives only a snapshot of
`$Global:IcingaForWindows` at startup. The daemon exits cleanly when
`Test-ThreadRunning` returns `$false`.

*Source: [src/Core/Logging/Private/Start-LoggingDaemon.ps1](../src/Core/Logging/Private/Start-LoggingDaemon.ps1)*

---

### Test-LoggingConsoleNextObjectIterable

*Private function*

**Synopsis:** Determine whether an object should be treated as iterable for logging.

#### Description

`Test-LoggingConsoleNextObjectIterable` inspects the provided value and returns
`$true` if the logging formatter should iterate its child elements, or `$false`
for scalar values such as strings.

#### Parameters

**`$Value`**

| Name  | Type          | Description                             | Default |
|-------|---------------|-----------------------------------------|---------|
| Value | System.Object | The value to test for iterable printing |         |

#### Outputs

System.Boolean -- `$true` when the value is considered iterable for logging.

#### Examples

```powershell
PS> Test-LoggingConsoleNextObjectIterable -Value $arr
```

#### Notes

Strings and certain CLR types are intentionally excluded from iteration.

*Source: [src/Core/Logging/Private/Test-LoggingConsoleNextObjectIterable.ps1](../src/Core/Logging/Private/Test-LoggingConsoleNextObjectIterable.ps1)*

---

### Test-LoggingWriteLog

*Private function*

**Synopsis:** Decide if a message at a given level should be emitted by the logger.

#### Description

`Test-LoggingWriteLog` compares the requested message level against the
currently configured global logging level and returns `$true` when the message
should be written.

#### Parameters

**`$Level`**

| Name  | Type          | Description                             | Default |
|-------|---------------|-----------------------------------------|---------|
| Level | System.String | The severity of the message to evaluate | 'Info'  |

#### Outputs

System.Boolean -- `$true` if the message should be written given the current logging level.

#### Examples

```powershell
PS> Test-LoggingWriteLog -Level 'Debug'
```

#### Notes

Logging level hierarchy is implemented by explicit membership checks per level.

*Source: [src/Core/Logging/Private/Test-LoggingWriteLog.ps1](../src/Core/Logging/Private/Test-LoggingWriteLog.ps1)*

---

### Update-LoggingThreadLoggingId

*Private function*

**Synopsis:** Set or renew the current per-thread logging identifier.

#### Description

`Update-LoggingThreadLoggingId` assigns a unique logging GUID for tracing logs
generated by a thread. If a `ThreadId` is provided it is used; otherwise a new GUID is created.

#### Parameters

**`$ThreadId`**

| Name     | Type          | Description                                    | Default |
|----------|---------------|------------------------------------------------|---------|
| ThreadId | System.String | Optional GUID to use as the current logging id | $null   |

#### Outputs

None -- Updates `(Get-GlobalRuntimeVariable).Private.Logging.CurrentLoggingId`.

#### Examples

```powershell
PS> Update-LoggingThreadLoggingId -ThreadId (New-Guid).ToString()
```

#### Notes

This id helps correlate logs produced during the lifetime of a thread.

*Source: [src/Core/Logging/Private/Update-LoggingThreadLoggingId.ps1](../src/Core/Logging/Private/Update-LoggingThreadLoggingId.ps1)*

---

### Write-LoggingEntry

*Private function*

**Synopsis:** Queue a structured log entry for asynchronous processing

#### Description

`Write-LoggingEntry` constructs a logging object (message, level, event id, area,
and additional data) and enqueues it into the global logging queue for processing
by the logging daemon. When `-Area` is omitted or empty, it falls back to the
generic `'Logging'` area defined by `EventLogGenericLog` in `Set-InternalExitCodes`.
It also assigns a per-message logging id for correlation.

#### Parameters

**`$Message`**

| Name    | Type          | Description          | Default |
|---------|---------------|----------------------|---------|
| Message | System.String | The log message text | $null   |

**`$Level`**

| Name  | Type          | Description                                                    | Default |
|-------|---------------|----------------------------------------------------------------|---------|
| Level | System.String | Severity (Debug,Output,Audit,Info,Success,Warning,Error,Fatal) | 'Info'  |

**`$EventId`**

| Name    | Type         | Description                                | Default |
|---------|--------------|--------------------------------------------|---------|
| EventId | System.Int32 | Numeric event identifier for the log entry | 15      |

**`$Area`**

| Name | Type          | Description                                                           | Default |
|------|---------------|-----------------------------------------------------------------------|---------|
| Area | System.String | Event Log source area; falls back to 'Logging' when omitted or empty. | $null   |

**`$Data`**

| Name | Type                         | Description                                              | Default |
|------|------------------------------|----------------------------------------------------------|---------|
| Data | System.Collections.Hashtable | Additional structured data to include with the log entry | @{}     |

#### Outputs

System.Management.Automation.PSCustomObject -- The enqueued log object when called from a background daemon with Level 'Output'; None otherwise.

#### Examples

```powershell
PS> Write-LoggingEntry -Message 'Started processing' -Level 'Info' -EventId 100 -Area 'Installer'

Queues an informational log entry under the 'Installer' Event Log area.
```

#### Notes

This function is intentionally non-blocking: it enqueues messages for a background
consumer. It uses `(Get-GlobalRuntimeVariable).Private.Logging.CurrentLoggingId` to tag messages.

*Source: [src/Core/Logging/Private/Write-LoggingEntry.ps1](../src/Core/Logging/Private/Write-LoggingEntry.ps1)*


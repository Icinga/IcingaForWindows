# Icinga.Core.ErrorHandling

*Auto-generated from `src/Core/ErrorHandling/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [Set-InternalExitCodes](#set-internalexitcodes)
- [Write-FunctionReturnValue](#write-functionreturnvalue)

---

### Set-InternalExitCodes

*Private function*

**Synopsis:** Initialize the module's internal return code table

#### Description

Populates `(Get-GlobalRuntimeVariable).Public.ReturnCodes` with a
centralized hashtable of semantic return-code entries used throughout
our module. Each entry contains a numeric code, a short message, a
longer description, severity and area metadata. The function is
idempotent and will return immediately if the table is already set.

#### Outputs

None — Populates (Get-GlobalRuntimeVariable).Public.ReturnCodes as a side effect.

#### Examples

```powershell
PS> Set-InternalExitCodes

Ensures the return-code table is initialized; exits immediately if the table
is already populated.
```

#### Notes

Private helper used by error-handling and logging routines; safe to call
multiple times because it will not overwrite an existing table.

*Source: [src/Core/ErrorHandling/Private/Set-InternalExitCodes.ps1](../../src/Core/ErrorHandling/Private/Set-InternalExitCodes.ps1)*

---

### Write-FunctionReturnValue

*Private function*

**Synopsis:** Emit a standardized numeric return value and optional log entry.

#### Description

Looks up the semantic return identifier in the internal return-code table
and emits the mapped numeric code. If the entry's severity is enabled in
the current logging configuration, a structured log entry is enqueued.
Supports returning an override value instead of the mapped code.

#### Parameters

**`$ReturnValue`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ReturnValue | System.String | Semantic key of the return-code entry to emit (for example: 'TlsHandshakeSuccessful'). | |

**`$Data`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Data | System.Collections.Hashtable | Additional contextual data to attach to the log entry. | @{} |

**`$OverrideReturn`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| OverrideReturn | System.Object | If provided (not 'Core::IgnoreOverride'), this value is returned instead of the mapped numeric code. Booleans are returned via explicit cast to preserve type. | Core::IgnoreOverride |

**`$AutomationRun`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AutomationRun | System.Management.Automation.SwitchParameter | When set, returns @{ ExitCode; Output } instead of the numeric code. ExitCode is 0 for Info/Audit/Debug severities, 2 for all others. | $false |

#### Outputs

System.Int32 — Numeric code from the return-code table when neither -OverrideReturn nor -AutomationRun is active.
System.Collections.Hashtable — @{ ExitCode = System.Int32; Output = System.String } when -AutomationRun is set.
System.Object — The -OverrideReturn value as-is when provided, taking precedence over both the numeric code and -AutomationRun.

#### Examples

```powershell
PS> Write-FunctionReturnValue -ReturnValue 'TlsHandshakeSuccessful'
```

#### Notes

Calls Set-InternalExitCodes to ensure the return-code table is populated before the first lookup.
Enqueues a log entry via Write-LoggingEntry only when the entry's severity is enabled in the
current logging configuration and is not 'Audit'. Must be called from the main thread or via
Get-GlobalRuntimeVariable in daemon context.

*Source: [src/Core/ErrorHandling/Private/Write-FunctionReturnValue.ps1](../../src/Core/ErrorHandling/Private/Write-FunctionReturnValue.ps1)*



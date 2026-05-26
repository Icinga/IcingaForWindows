# Icinga.Core.ErrorHandling

*Auto-generated from `src/Core/ErrorHandling/`. Do not edit by hand — run `build/Build-ModuleDocs.ps1` to regenerate.*

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

**Synopsis:** Emit a standardized numeric return value and optional log entry

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
| OverrideReturn | System.Object | If provided (not 'Core::IgnoreOverride'), this value is returned instead of the mapped numeric code. Can be a boolean or numeric value. | Core::IgnoreOverride |

#### Outputs

System.Int32
Numeric return code mapped from the semantic `ReturnValue`, or the provided `OverrideReturn`.

#### Examples

```powershell
PS> Write-FunctionReturnValue -ReturnValue 'TlsHandshakeSuccessful'
```

#### Notes

This helper depends on `Set-InternalExitCodes` and `Write-LoggingEntry`.

*Source: [src/Core/ErrorHandling/Private/Write-FunctionReturnValue.ps1](../../src/Core/ErrorHandling/Private/Write-FunctionReturnValue.ps1)*



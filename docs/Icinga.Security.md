# Icinga.Security

*Auto-generated from `src/Security/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [Get-FileEncoding](#get-fileencoding)
- [Get-SecureChildItem](#get-securechilditem)
- [New-SecureItem](#new-secureitem)
- [Read-SecureFile](#read-securefile)
- [Remove-SecureItem](#remove-secureitem)
- [Test-SecureApprovedPath](#test-secureapprovedpath)
- [Write-SecureFile](#write-securefile)

---

### Get-FileEncoding

*Private function*

**Synopsis:** Detect the most likely file encoding for a given file.

#### Description

`Get-FileEncoding` examines the first bytes of a file to detect common byte-order
marks (BOM) and falls back to heuristics to distinguish ASCII and UTF8 when no BOM
is present. Returns a short encoding identifier string.

#### Parameters

**`$Path`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Path to the file to inspect | '' |

#### Outputs

System.String — One of: UTF8-BOM, UTF8, Unicode, BigEndianUnicode, UTF7, UTF32, ASCII.

#### Examples

```powershell
Get-FileEncoding -Path (Join-Path (Get-ModuleConfigDirectory) 'settings.json')
```

#### Notes

- Returns a cmdlet-style error via `Write-FunctionReturnValue` when the file is not found.

*Source: [src/Security/Private/Get-FileEncoding.ps1](../../src/Security/Private/Get-FileEncoding.ps1)*

---

### Get-SecureChildItem

*Private function*

**Synopsis:** Secure wrapper around Get-ChildItem that restricts access to approved paths

#### Description

Fetches child items from the filesystem while enforcing approved-path checks
via Test-SecureApprovedPath. This prevents access to arbitrary filesystem
locations outside the module root, configuration, cache and binaries
directories. Logs outcomes via Write-FunctionReturnValue and returns the
enumerated child items via -OverrideReturn on success or $null on error.

#### Parameters

**`$Path`**

| Name | Type          | Description                  | Default |
|------|---------------|------------------------------|---------|
| Path | System.String | Directory path to enumerate. | ''      |

**`$Filter`**

| Name   | Type          | Description                              | Default |
|--------|---------------|------------------------------------------|---------|
| Filter | System.String | File name filter (for example '*.json'). | '*'     |

**`$Include`**

| Name    | Type         | Description                                     | Default |
|---------|--------------|-------------------------------------------------|---------|
| Include | System.Array | Additional include patterns for Get-ChildItem.  | @()     |

**`$File`**

| Name | Type                                         | Description               | Default |
|------|----------------------------------------------|---------------------------|---------|
| File | System.Management.Automation.SwitchParameter | If set, only return files.| $false  |

**`$Directory`**

| Name      | Type                                         | Description                     | Default |
|-----------|----------------------------------------------|---------------------------------|---------|
| Directory | System.Management.Automation.SwitchParameter | If set, only return directories.| $false  |

**`$Recurse`**

| Name    | Type                                         | Description                  | Default |
|---------|----------------------------------------------|------------------------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Recurse into subdirectories. | $false  |

#### Outputs

System.Object -- Enumerated FileInfo/DirectoryInfo items via -OverrideReturn on
success (ChildItemFetchSucceeded), or $null on ChildItemPathArgumentEmpty,
AccessViolation or ChildItemFetchFailed.

#### Examples

```powershell
PS> Get-SecureChildItem -Path (Get-ModuleConfigDirectory) -File
```

#### Notes

This helper logs attempted access to unapproved paths and returns AccessViolation.

*Source: [src/Security/Private/Get-SecureChildItem.ps1](../../src/Security/Private/Get-SecureChildItem.ps1)*

---

### New-SecureItem

*Private function*

**Synopsis:** Create a filesystem item (file or directory) only in approved locations.

#### Description

Creates a new file or directory using `New-Item` but first verifies that the
target path is within approved config directories using `Test-SecureApprovedPath`.
Returns standardized return values via `Write-FunctionReturnValue` and logs
unauthorized attempts.

#### Parameters

**`$Path`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Path to create (file or directory). | $null |

**`$ItemType`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ItemType | System.String | 'File' or 'Directory'. | 'File' |

**`$Force`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.Management.Automation.SwitchParameter | Pass `-Force` to `New-Item` to overwrite existing items. | $false |

#### Outputs

PSCustomObject — Function return value via Write-FunctionReturnValue.
ObjectCreationSucceeded on success (Data contains Path, ItemType and Item).
ObjectCreationFailed, AccessViolation or DirectoryArgumentEmpty on errors.

#### Examples

```powershell
PS> New-SecureItem -Path (Join-Path (Get-ModuleConfigDirectory) 'my.conf') -ItemType File
```

#### Notes

Intended for use when module code must create config files; restricts creation
to module config directories only.

*Source: [src/Security/Private/New-SecureItem.ps1](../../src/Security/Private/New-SecureItem.ps1)*

---

### Read-SecureFile

*Private function*

**Synopsis:** Read a file from approved locations with retry handling for locks.

#### Description

Reads a file from disk only if the path is approved via `Test-SecureApprovedPath`.
Implements a retry loop to handle temporary file locks and detects UTF8 BOM when
assembling the file content. Returns standardized return values via
`Write-FunctionReturnValue`.

#### Parameters

**`$File`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| File | System.String | Path to the file to read. | $null |

#### Outputs

System.String — File content on success (returned as raw override via Write-FunctionReturnValue).
ObjectReadSucceeded on success (Data contains Path and Content).
FileNotFound, AccessViolation or FileLockException on errors.

#### Examples

```powershell
PS> Read-SecureFile -File (Join-Path (Get-ModuleConfigDirectory) 'settings.json')
```

#### Notes

This helper attempts to open the file for up to ~5 seconds before failing with
`FileLockException`. Use for reading module configuration files safely.

*Source: [src/Security/Private/Read-SecureFile.ps1](../../src/Security/Private/Read-SecureFile.ps1)*

---

### Remove-SecureItem

*Private function*

**Synopsis:** Safely remove files or directories within approved module locations.

#### Description

Removes filesystem items after verifying the target path is within approved
directories. Logs unauthorized attempts and returns structured return values
using `Write-FunctionReturnValue`.

#### Parameters

**`$Path`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Path to remove. | '' |

**`$Recurse`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Recurse | System.Management.Automation.SwitchParameter | Remove child items recursively. | $false |

**`$Force`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Force | System.Management.Automation.SwitchParameter | Force deletion (pass `-Force` to `Remove-Item`). | $false |

#### Outputs

PSCustomObject — Function return value via Write-FunctionReturnValue.
RemoveItemSuccess on success (Data contains Path).
RemoveItemFailed, AccessViolation, RemoveItemNoPathProvided or RemoveItemPathNotFound on errors.

#### Examples

```powershell
PS> Remove-SecureItem -Path (Join-Path (Get-ModuleCacheDirectory) 'temp.log') -Force
```

#### Notes

Intended to limit deletion operations to module-managed directories only.

*Source: [src/Security/Private/Remove-SecureItem.ps1](../../src/Security/Private/Remove-SecureItem.ps1)*

---

### Test-SecureApprovedPath

*Private function*

**Synopsis:** Check whether a path is within an approved set of directories.

#### Description

Normalizes the provided approved paths and the target path, then verifies
whether the target path starts with any approved path prefix. Logs an audit
entry for each check and returns standardized return values.

#### Parameters

**`$Path`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Path | System.String | Path to validate. | $null |

**`$ApprovedPath`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ApprovedPath | System.Array | Array of allowed directory paths (strings). | @() |

#### Outputs

PSCustomObject — Function return value via Write-FunctionReturnValue.
AccessGranted when the path is within an approved directory.
AccessViolation or DirectoryArgumentEmpty otherwise.

#### Examples

```powershell
PS> Test-SecureApprovedPath -Path (Join-Path (Get-ModuleConfigDirectory) 'x') -ApprovedPath @(Get-ModuleConfigDirectory)
```

#### Notes

Uses `Resolve-Path` to normalize paths; callers should ensure ApprovedPath entries exist.

*Source: [src/Security/Private/Test-SecureApprovedPath.ps1](../../src/Security/Private/Test-SecureApprovedPath.ps1)*

---

### Write-SecureFile

*Private function*

**Synopsis:** Write content to a file in approved locations with retry-on-lock semantics.

#### Description

Writes content to disk after ensuring the target path exists and is within an
approved location. Handles several input types (hashtable, PSCustomObject,
arrays) by serializing them appropriately. Attempts to open the file for write
and retries on lock for a short period. Returns structured return values via
`Write-FunctionReturnValue`.

#### Parameters

**`$File`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| File | System.String | Target file path to write. | $null |

**`$Value`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Value | System.Object | Content to write. Can be hashtable, PSCustomObject, array or string. | (none) |

#### Outputs

PSCustomObject — Function return value via Write-FunctionReturnValue.
WriteFileSuccess on success (Data contains Path and Content), WriteFileLockException
when the file cannot be opened within the retry window.

#### Examples

```powershell
PS> Write-SecureFile -File (Join-Path (Get-ModuleConfigDirectory) 'settings.json') -Value @{ key = 'value' }
```

#### Notes

Creates the file if it does not exist by delegating to `New-SecureItem`. Uses UTF8
without BOM when writing bytes. Caller receives the content in the return data.

*Source: [src/Security/Private/Write-SecureFile.ps1](../../src/Security/Private/Write-SecureFile.ps1)*


# Icinga.Config

*Auto-generated from `src/Config/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [New-ModuleConfigEnvironment](#new-moduleconfigenvironment)
- [Read-ModuleConfigFile](#read-moduleconfigfile)

---

### New-ModuleConfigEnvironment

*Private function*

**Synopsis:** Ensure the module configuration directory exists

#### Description

New-ModuleConfigEnvironment checks whether the module configuration directory
exists via Get-ModuleConfigDirectory. If the directory is already present the
function returns a structured Write-FunctionReturnValue result with ReturnValue
set to ConfigPresent. If the directory is missing it creates it with New-Item
and returns ConfigMissing.

#### Outputs

System.Object — Structured return object from Write-FunctionReturnValue with
ReturnValue set to either ConfigPresent or ConfigMissing.

#### Examples

```powershell
PS> New-ModuleConfigEnvironment

Ensures the config directory is present, creating it if necessary, and returns
a structured result indicating whether the directory was already there.
```

#### Notes

Uses Get-ModuleConfigDirectory to resolve the target path. The directory is
created with -Force when it is missing.

*Source: [src/Config/Private/New-ModuleConfigEnvironment.ps1](../../src/Config/Private/New-ModuleConfigEnvironment.ps1)*

---

### Read-ModuleConfigFile

*Private function*

**Synopsis:** Read and parse a module JSON configuration file

#### Description

Read-ModuleConfigFile loads a configuration file from the module config
directory, parses it as JSON and returns the resulting object. If
-IncludeSubConfig is supplied and the top-level JSON object contains a Config
property, that sub-config will be read recursively and attached as a Config
property on the returned object. On error the function returns a structured
error object via Write-FunctionReturnValue with -OverrideReturn $null so that
callers receive $null on failure.

#### Parameters

**`$Config`**

| Name   | Type          | Description                       | Default |
|--------|---------------|-----------------------------------|---------|
| Config | System.String | Filename of the config to read.   | $null   |

**`$IncludeSubConfig`**

| Name             | Type                                        | Description                                               | Default |
|------------------|---------------------------------------------|-----------------------------------------------------------|---------|
| IncludeSubConfig | System.Management.Automation.SwitchParameter | When set, recursively reads sub-configs referenced by Config. | $false  |

#### Outputs

System.Object — Parsed JSON object on success, or $null on error.

#### Examples

```powershell
PS> Read-ModuleConfigFile -Config 'module.json' -IncludeSubConfig

Reads module.json from the module config directory and recursively attaches
any referenced sub-config.
```

#### Notes

Relies on Get-ModuleConfigDirectory and Read-SecureFile for file I/O.
Returns $null via -OverrideReturn $null on error to match calling conventions
elsewhere in the module.

*Source: [src/Config/Private/Read-ModuleConfigFile.ps1](../../src/Config/Private/Read-ModuleConfigFile.ps1)*



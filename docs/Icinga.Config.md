# Icinga.Config

*Auto-generated from `src/Config/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Private helpers

- [New-ModuleConfigEnvironment](#new-moduleconfigenvironment)
- [Read-ModuleConfigFile](#read-moduleconfigfile)

---

### New-ModuleConfigEnvironment

*Private function*

**Synopsis:** Ensure the module configuration and binaries directories exist

#### Description

New-ModuleConfigEnvironment checks whether the module binaries directory
(Get-ModuleBinaryDirectory) and module configuration directory
(Get-ModuleConfigDirectory) exist. Missing directories are created automatically
with New-Item. If the configuration directory was already present, the function
emits ConfigPresent via Write-FunctionReturnValue and returns its mapped numeric
return code; otherwise it creates the directory, emits ConfigMissing and returns
its mapped numeric return code.

#### Outputs

System.Int32 -- Mapped numeric return code from Write-FunctionReturnValue for
ConfigPresent or ConfigMissing.

#### Examples

```powershell
PS> New-ModuleConfigEnvironment

Ensures both the binaries directory and the config directory are present,
creating them if necessary, and returns the mapped numeric return code.
```

#### Notes

Uses Get-ModuleConfigDirectory and Get-ModuleBinaryDirectory to resolve target
paths. Missing directories are created with -Force.

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


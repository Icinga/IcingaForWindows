# Icinga.IcingaProtocol

*Auto-generated from `src/IcingaProtocol/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [Import-IcingaCertAuthority](#import-icingacertauthority)
- [New-IcingaProtocolCertificate](#new-icingaprotocolcertificate)
- [New-IcingaProtocolEndpoint](#new-icingaprotocolendpoint)
- [New-IcingaProtocolEnvironment](#new-icingaprotocolenvironment)
- [Start-IcingaAgent](#start-icingaagent)

## Private helpers

- [Add-IcingaProtocolClient](#add-icingaprotocolclient)
- [Add-IcingaRPCMessageToWorker](#add-icingarpcmessagetoworker)
- [Add-IcingaRPCMessageToWriterQueue](#add-icingarpcmessagetowriterqueue)
- [ConvertFrom-IcingaProtocolMacros](#convertfrom-icingaprotocolmacros)
- [Expand-IcingaProtocolMacroValue](#expand-icingaprotocolmacrovalue)
- [Invoke-IcingaProtocolBinaryProcess](#invoke-icingaprotocolbinaryprocess)
- [Invoke-IcingaProtocolCheckCommand](#invoke-icingaprotocolcheckcommand)
- [Invoke-IcingaProtocolExternalScript](#invoke-icingaprotocolexternalscript)
- [New-IcingaAgentEnvironment](#new-icingaagentenvironment)
- [New-IcingaRPCMessage](#new-icingarpcmessage)
- [Read-IcingaProtocolConnection](#read-icingaprotocolconnection)
- [Read-IcingaRPCMessage](#read-icingarpcmessage)
- [Resolve-IcingaProtocolCommand](#resolve-icingaprotocolcommand)
- [Send-IcingaProtocolCertificateRequest](#send-icingaprotocolcertificaterequest)
- [Send-IcingaProtocolCheckResult](#send-icingaprotocolcheckresult)
- [Send-IcingaProtocolHeartbeat](#send-icingaprotocolheartbeat)
- [Send-IcingaProtocolHello](#send-icingaprotocolhello)
- [Send-IcingaProtocolLogPosition](#send-icingaprotocollogposition)
- [Split-IcingaBinaryPluginOutput](#split-icingabinarypluginoutput)
- [Start-IcingaProtocolConnector](#start-icingaprotocolconnector)
- [Start-IcingaProtocolHeartbeat](#start-icingaprotocolheartbeat)
- [Start-IcingaProtocolListener](#start-icingaprotocollistener)
- [Start-IcingaProtocolSocketReader](#start-icingaprotocolsocketreader)
- [Start-IcingaProtocolSocketWriter](#start-icingaprotocolsocketwriter)
- [Start-IcingaProtocolWorker](#start-icingaprotocolworker)
- [Stop-IcingaProtocolProcessTree](#stop-icingaprotocolprocesstree)
- [Test-IcingaProtocolClientStatus](#test-icingaprotocolclientstatus)

---

### Import-IcingaCertAuthority

*Public function*

**Synopsis:** Import the Icinga 2 CA certificate into the Windows LocalMachine Root store or local directory

#### Description

Import-IcingaCertAuthority accepts an Icinga 2 CA certificate either as a
direct PEM string (-Certificate) or via a local file or HTTP/HTTPS URL (-Path).
On Windows, it imports the certificate into Cert:\LocalMachine\Root
(StoreName::Root, StoreLocation::LocalMachine), skipping import if a
certificate with the same thumbprint already exists. On Linux and macOS, it
writes the PEM certificate to ca.crt inside Get-ModuleCertificateDirectory.

#### Parameters

**`$Certificate`**

| Name        | Type          | Description                               | Default |
|-------------|---------------|-------------------------------------------|---------|
| Certificate | System.String | The PEM-formatted CA certificate payload. |         |

**`$Path`**

| Name | Type          | Description                                       | Default |
|------|---------------|---------------------------------------------------|---------|
| Path | System.String | Local file path or HTTP/HTTPS URL to the CA cert. |         |

#### Outputs

System.Object -- Returns nothing ($null) when the CA certificate is imported or
written to disk, or a standardized System.Int32 error code from
Write-FunctionReturnValue (50013 IcingaCAImportPathNotfound when a local -Path
does not exist, or 50014 IcingaCAContentIsEmpty when the certificate payload is
empty or whitespace).

#### Examples

```powershell
PS> Import-IcingaCertAuthority -Path 'C:\Temp\ca.crt'

Imports the Icinga 2 CA certificate from a local file into Cert:\LocalMachine\Root
on Windows (or saves ca.crt locally on Linux/macOS).
```

```powershell
PS> Import-IcingaCertAuthority -Path 'https://icinga-master01.example.com/ca.crt'

Downloads and imports the Icinga 2 CA certificate from an HTTPS endpoint.
```

#### Notes

Requires administrative privileges on Windows to open Cert:\LocalMachine\Root
for read/write access.

*Source: [src/IcingaProtocol/Public/Import-IcingaCertAuthority.ps1](../src/IcingaProtocol/Public/Import-IcingaCertAuthority.ps1)*

---

### New-IcingaProtocolCertificate

*Public function*

**Synopsis:** Generate a self-signed certificate or merge an existing private key with a signed certificate

#### Description

New-IcingaProtocolCertificate generates a 4096-bit RSA self-signed TLS
certificate valid for 3 months for the specified Common Name (CN). If the
SignedCert parameter is provided, it instead extracts the existing RSA private
key and merges it with the signed PEM certificate.

Depending on the operating system, the certificate is either stored exclusively
in Cert:\CurrentUser\My on Windows (automatically replacing any previous
self-signed or Icinga-issued certificate for the same CN) or written to disk as
a passwordless PKCS#12 (.pfx) file under Get-ModuleCertificateDirectory on
Linux and macOS.

#### Parameters

**`$CommonName`**

| Name       | Type          | Description                               | Default |
|------------|---------------|-------------------------------------------|---------|
| CommonName | System.String | The common name (CN) for the certificate. | $null   |

**`$SignedCert`**

| Name       | Type          | Description                           | Default |
|------------|---------------|---------------------------------------|---------|
| SignedCert | System.String | The PEM-formatted signed certificate. | $null   |

#### Outputs

System.Int32 -- Standardized return code from Write-FunctionReturnValue (50011
when stored in Cert:\CurrentUser\My on Windows, 50010 when stored locally as a
.pfx file on Linux/macOS, 50009 when -CommonName is missing or whitespace, or
50012 when the existing certificate cannot be found during a -SignedCert merge).

#### Examples

```powershell
PS> New-IcingaProtocolCertificate -CommonName 'win-srv01.example.com'

Generates a new self-signed certificate for 'win-srv01.example.com' and stores
it in Cert:\CurrentUser\My on Windows or as a local .pfx file on Linux/macOS.
```

```powershell
PS> New-IcingaProtocolCertificate -CommonName 'win-srv01.example.com' -SignedCert '-----BEGIN CERTIFICATE-----...'

Merges the signed PEM certificate with the existing private key for
'win-srv01.example.com' and replaces the stored certificate.
```

#### Notes

Stores Windows certificates in Cert:\CurrentUser\My of the executing user
account (does not require LocalMachine store elevation; ensure certificate
provisioning and the Icinga for Windows runtime execute under the same Windows
user account). On non-Windows platforms, Get-ModuleCertificateDirectory is
created automatically before writing <CommonName>.pfx.

*Source: [src/IcingaProtocol/Public/New-IcingaProtocolCertificate.ps1](../src/IcingaProtocol/Public/New-IcingaProtocolCertificate.ps1)*

---

### New-IcingaProtocolEndpoint

*Public function*

**Synopsis:** Creates a new Icinga Protocol endpoint configuration object.

#### Description

Creates a hashtable representing an Icinga Protocol endpoint with the specified Name, Address, and Port.
This object is typically passed into New-IcingaProtocolEnvironment.

#### Parameters

**`$Name`**

| Name | Type          | Description                              | Default |
|------|---------------|------------------------------------------|---------|
| Name | System.String | The human-readable name of the endpoint. |         |

**`$Address`**

| Name    | Type          | Description                             | Default |
|---------|---------------|-----------------------------------------|---------|
| Address | System.String | The IP address or FQDN of the endpoint. |         |

**`$Port`**

| Name | Type         | Description                 | Default |
|------|--------------|-----------------------------|---------|
| Port | System.Int32 | The TCP port to connect to. |         |

#### Outputs

System.Collections.Hashtable -- Returns a hashtable with the endpoint configuration.

#### Examples

```powershell
PS> New-IcingaProtocolEndpoint -Name 'Master1' -Address '192.168.1.10' -Port 5665

Creates a new endpoint object for Master1.
```

#### Notes

This object is required for configuring the Icinga environment structure.

*Source: [src/IcingaProtocol/Public/New-IcingaProtocolEndpoint.ps1](../src/IcingaProtocol/Public/New-IcingaProtocolEndpoint.ps1)*

---

### New-IcingaProtocolEnvironment

*Public function*

**Synopsis:** Generate and save the Icinga Protocol environment configuration

#### Description

New-IcingaProtocolEnvironment validates and writes the Icinga 2 cluster
connection settings (Endpoints, Zone, Hostname, and TlsCertConfig) to
Config\IcingaProtocol\Connection.json. Single-quoted '$fqdn' and '$hostname'
placeholders in -Hostname, -CertCN, and -CertIssuer are preserved verbatim in
Connection.json and resolved dynamically when Read-IcingaProtocolConnection
loads the file.

When -DryRun is specified, the function computes a unified diff against any
existing Connection.json via Compare-IcingaTextContent and returns @{ ExitCode;
Output } without creating directories or saving changes to disk. Call
New-IcingaProtocolEnvironment again without -DryRun and without .Output to
persist the configuration.

#### Parameters

**`$Endpoints`**

| Name      | Type         | Description                      | Default |
|-----------|--------------|----------------------------------|---------|
| Endpoints | System.Array | An array of endpoint hashtables. | @()     |

**`$Zone`**

| Name | Type          | Description                  | Default  |
|------|---------------|------------------------------|----------|
| Zone | System.String | The name of the Icinga zone. | 'master' |

**`$Hostname`**

| Name     | Type          | Description                                                        | Default     |
|----------|---------------|--------------------------------------------------------------------|-------------|
| Hostname | System.String | Icinga 2 Endpoint/Host Object Name (supports '$fqdn'/'$hostname'). | '$hostname' |

**`$TlsCertConfig`**

| Name          | Type                                          | Description                               | Default |
|---------------|-----------------------------------------------|-------------------------------------------|---------|
| TlsCertConfig | System.Management.Automation.PSCustomObject   | The TLS certificate configuration object. | $null   |

**`$DryRun`**

| Name   | Type                                         | Description                                                 | Default |
|--------|----------------------------------------------|-------------------------------------------------------------|---------|
| DryRun | System.Management.Automation.SwitchParameter | Return a unified diff hashtable without saving to disk.     | $false  |

#### Outputs

System.Object -- Returns System.Int32 from Write-FunctionReturnValue when
persisting configuration or failing validation (50019 IcingaProtoclConfigWritten
on write, or 50015-50018 on missing required inputs), or
System.Collections.Hashtable (@{ ExitCode = System.Int32; Output = System.String })
from Compare-IcingaTextContent when -DryRun is specified.

#### Examples

```powershell
PS> $Endpoints = @(New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665)
PS> $CertConfig = New-IcingaTlsCertConfig -CertCN '$fqdn' -CertStore 'My' -CertStoreLocation 'CurrentUser' -CertIssuer @( 'Icinga CA', '$fqdn' )
PS> (New-IcingaProtocolEnvironment -Endpoints $Endpoints -Zone 'master' -Hostname '$fqdn' -TlsCertConfig $CertConfig -DryRun).Output
PS> New-IcingaProtocolEnvironment -Endpoints $Endpoints -Zone 'master' -Hostname '$fqdn' -TlsCertConfig $CertConfig

Previews the unified diff via -DryRun without modifying disk state, then writes
Config\IcingaProtocol\Connection.json (returning 50019).
```

#### Notes

Writes configuration data to Config\IcingaProtocol\Connection.json via
Write-SecureFile. The -Hostname and certificate CN must match the exact
Endpoint and Host Object Name configured in Icinga 2. Always single-quote
'$fqdn' and '$hostname' so PowerShell does not expand them before invocation.

*Source: [src/IcingaProtocol/Public/New-IcingaProtocolEnvironment.ps1](../src/IcingaProtocol/Public/New-IcingaProtocolEnvironment.ps1)*

---

### Start-IcingaAgent

*Public function*

**Synopsis:** Starts the Icinga protocol agent environment in a background thread.

#### Description

Start-IcingaAgent spawns a background thread via New-Thread that calls
New-IcingaAgentEnvironment to initialize the full Icinga protocol stack.
Use this function to activate the protocol listener, connector and worker
threads for Icinga JSON-RPC communication.

#### Outputs

None -- Starts a background thread; no pipeline output.

#### Examples

```powershell
PS> Start-IcingaAgent
```

#### Notes

This function requires New-IcingaAgentEnvironment and New-Thread to be available.
The agent environment is initialized asynchronously in the spawned thread.
Call this once during module startup after global configuration is in place.

*Source: [src/IcingaProtocol/Public/Start-IcingaAgent.ps1](../src/IcingaProtocol/Public/Start-IcingaAgent.ps1)*

---

### Add-IcingaProtocolClient

*Private function*

**Synopsis:** Adds or updates a TcpClient entry in the global IcingaProtocol connections table.

#### Description

Add-IcingaProtocolClient inserts a System.Net.Sockets.TcpClient into the global
$Global:IcingaForWindows.Public.IcingaProtocol.Connections hashtable keyed by
the provided Address. If the Address already exists, the function replaces the
existing entry with the supplied TcpClient. If the Address does not exist, a new
entry is added.

The function performs basic parameter validation and uses Write-FunctionReturnValue
to emit a standardized operation result object indicating success or failure.

#### Parameters

**`$Address`**

| Name    | Type          | Description                                                                                | Default |
|---------|---------------|--------------------------------------------------------------------------------------------|---------|
| Address | System.String | String key (typically an IP address) used to index the TcpClient in the connections table. | $null   |

**`$TcpClient`**

| Name      | Type                         | Description                                                  | Default |
|-----------|------------------------------|--------------------------------------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Active TcpClient instance to store in the connections table. | $null   |

#### Outputs

PSCustomObject -- Return value produced by Write-FunctionReturnValue.
Possible tokens: IcingaClientAddingFailed (validation failed) or IcingaClientAdded (success).

#### Examples

```powershell
PS> $tcp = New-Object System.Net.Sockets.TcpClient
PS> $tcp.Connect('10.0.0.5', 5665)
PS> Add-IcingaProtocolClient -Address '10.0.0.5' -TcpClient $tcp
```

```powershell
PS> Add-IcingaProtocolClient -Address '10.0.0.5' -TcpClient $newTcp

Replaces an existing connection entry for the same address with a new TcpClient.
```

#### Notes

This function modifies $Global:IcingaForWindows.Public.IcingaProtocol.Connections directly.
The caller is responsible for the lifetime and disposal of the TcpClient objects.
No additional connectivity checks are performed; the function only stores the provided instance.

*Source: [src/IcingaProtocol/Private/Add-IcingaProtocolClient.ps1](../src/IcingaProtocol/Private/Add-IcingaProtocolClient.ps1)*

---

### Add-IcingaRPCMessageToWorker

*Private function*

**Synopsis:** Add a serialized Icinga 2 JSON-RPC message to a worker queue in round-robin order

#### Description

Add-IcingaRPCMessageToWorker accepts a serialized JSON-RPC message string,
strips Icinga empty-key placeholder entries ('"":"$"') for Windows PowerShell
5.1 JavaScriptSerializer compatibility, deserializes the payload via
ConvertFrom-ModuleJson, and enqueues the parsed message together with the
current socket client and TLS stream into the next worker queue via round-robin
selection. Null, empty or malformed JSON payloads emit structured return values
and are dropped without throwing.

#### Parameters

**`$Message`**

| Name    | Type          | Description                                                                 | Default |
|---------|---------------|-----------------------------------------------------------------------------|---------|
| Message | System.String | Serialized JSON-RPC message payload to enqueue. Ignored when null or empty. | $null   |

#### Outputs

None -- Enqueues the parsed message object into WorkerQueue and returns nothing.

#### Examples

```powershell
PS> Add-IcingaRPCMessageToWorker -Message '{"jsonrpc":"2.0","method":"event::ExecuteCommand","params":{}}'

Parses the JSON-RPC message and dispatches it to the next protocol worker queue.
```

#### Notes

Caller must ensure WorkerCount and WorkerQueue are initialized in
Public.IcingaProtocol before invoking this helper.

*Source: [src/IcingaProtocol/Private/Add-IcingaRPCMessageToWorker.ps1](../src/IcingaProtocol/Private/Add-IcingaRPCMessageToWorker.ps1)*

---

### Add-IcingaRPCMessageToWriterQueue

*Private function*

**Synopsis:** Adds a pre-built RPC message object to the per-endpoint writer queue.

#### Description

Add-IcingaRPCMessageToWriterQueue enqueues a message object created by
New-IcingaRPCMessage into the appropriate per-endpoint BlockingCollection
inside $Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue. If the
writer queue has not yet been initialized, or if no entry exists for the
current remote endpoint, the message is sent directly via Send-TCPMessage
as a fallback (for example during the early handshake phase). Null or
empty message objects are silently discarded. The function reads the
current TCP client and writer queue through Get-GlobalRuntimeVariable so
that it works correctly inside worker thread runspaces.

#### Parameters

**`$MsgObj`**

| Name   | Type          | Description                                                             | Default |
|--------|---------------|-------------------------------------------------------------------------|---------|
| MsgObj | System.Object | Message object as returned by New-IcingaRPCMessage (@{message;length}). | $null   |

#### Outputs

None -- The function enqueues the message or sends it directly; no pipeline output is produced.

#### Examples

```powershell
PS> Add-IcingaRPCMessageToWriterQueue -MsgObj (New-IcingaRPCMessage -Method 'icinga::Hello')
```

#### Notes

This function uses Get-GlobalRuntimeVariable to access global state, making it safe to
call from within thread runspaces. The writer queue is keyed by the string representation
of the remote endpoint IP address.

*Source: [src/IcingaProtocol/Private/Add-IcingaRPCMessageToWriterQueue.ps1](../src/IcingaProtocol/Private/Add-IcingaRPCMessageToWriterQueue.ps1)*

---

### ConvertFrom-IcingaProtocolMacros

*Private function*

**Synopsis:** Parse Icinga 2 ExecuteCommand macros into typed PowerShell or binary arguments

#### Description

ConvertFrom-IcingaProtocolMacros translates the macros dictionary of an Icinga 2
event::ExecuteCommand message into either a typed PowerShell splatting hashtable
or an ordered string array of CLI arguments for external binaries, plus a
human-readable CommandLine string with SecureString secrets masked as '********'.

Two Icinga 2 delivery modes are supported seamlessly across Windows PowerShell
5.1 (Dictionary[string, object]) and PowerShell 7+ (Hashtable):
1. Active ifw-api template (macros.ifw_api_arguments present): resolves single
   and embedded $macro$ references via Expand-IcingaProtocolMacroValue,
   evaluates set_if conditions, orders binary arguments by order, honors
   skip_key and repeat_key, and rejects unknown PowerShell parameters that carry
   a non-empty value with IWKB001001 (skipping empty strings, empty lists and
   empty dictionaries).
2. Fallback without ifw-api (macros.ifw_api_arguments absent): ignores internal
   ifw_api_* and IcingaPowerShellBase_* variables, maps PowerShell parameters by
   exact parameter/alias name or the IcingaCheck<Name>_<Type>_<Param> convention
   (returning IWKB001000 on unmapped custom variables), and enforces '-' or '/'
   prefixes on custom variables passed to external binaries (returning IWKB001002
   when unprefixed custom variables are present).

#### Parameters

**`$ResolvedCommand`**

| Name            | Type                         | Description                                                   | Default |
|-----------------|------------------------------|---------------------------------------------------------------|---------|
| ResolvedCommand | System.Collections.Hashtable | Command descriptor returned by Resolve-IcingaProtocolCommand. | @{}     |

**`$Macros`**

| Name   | Type          | Description                                                          | Default |
|--------|---------------|----------------------------------------------------------------------|---------|
| Macros | System.Object | Deserialized macros dictionary or object from event::ExecuteCommand. | $null   |

#### Outputs

System.Collections.Hashtable -- Parsed argument bundle containing Status,
PowerShellArguments, BinaryArguments, AllocatedSecureStrings, CommandLine,
Message, KnowledgeBaseId and ReturnCodeKey.

#### Examples

```powershell
PS> $resolved = Resolve-IcingaProtocolCommand -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheckDirectory' }
PS> ConvertFrom-IcingaProtocolMacros -ResolvedCommand $resolved -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheckDirectory'; 'Path' = 'C:\Temp' }

Maps the Path macro to Invoke-IcingaCheckDirectory's -Path parameter.
```

#### Notes

Callers must dispose every entry in AllocatedSecureStrings once plugin execution
completes. On validation errors, any SecureString allocated earlier in the same
call is disposed before returning.

*Source: [src/IcingaProtocol/Private/ConvertFrom-IcingaProtocolMacros.ps1](../src/IcingaProtocol/Private/ConvertFrom-IcingaProtocolMacros.ps1)*

---

### Expand-IcingaProtocolMacroValue

*Private function*

**Synopsis:** Expand single and embedded Icinga 2 macro references against a macro dictionary

#### Description

Expand-IcingaProtocolMacroValue evaluates a single Icinga 2 argument value or
set_if expression against an ordinal MacroMap and case-insensitive fallback
table:
- Non-string values (booleans, numbers, arrays, dictionaries) preserve their
  native type directly when non-null.
- Exact single-token '$macro$' strings resolve directly to the native macro
  object (preserving arrays, booleans and numbers without stringifying).
- Strings containing embedded '$macro$' tokens or escaped '$$' literals are
  interpolated in a single left-to-right pass so macro values containing '$'
  characters (such as Windows administrative shares '\\host\C$\MSSQL$INST') are
  never re-expanded. If any referenced token is unset or null, IsSet returns
  $false so optional Icinga arguments are cleanly skipped.

#### Parameters

**`$Expression`**

| Name       | Type          | Description                                                | Default |
|------------|---------------|------------------------------------------------------------|---------|
| Expression | System.Object | Raw 'value' or 'set_if' expression from ifw_api_arguments. | $null   |

**`$MacroMap`**

| Name     | Type          | Description                                           | Default |
|----------|---------------|-------------------------------------------------------|---------|
| MacroMap | System.Object | Case-sensitive OrderedDictionary of macro key/values. | $null   |

**`$MacroIgnoreCase`**

| Name            | Type                         | Description                                     | Default |
|-----------------|------------------------------|-------------------------------------------------|---------|
| MacroIgnoreCase | System.Collections.Hashtable | Case-insensitive fallback hashtable for macros. | @{}     |

#### Outputs

System.Collections.Hashtable -- Hashtable with keys IsSet (System.Boolean) and
Value (System.Object).

#### Examples

```powershell
PS> Expand-IcingaProtocolMacroValue -Expression 'http://$address$:$port$/health' -MacroMap $map -MacroIgnoreCase $ci

Interpolates the '$address$' and '$port$' tokens in a single pass.
```

#### Notes

Pure macro evaluator with no side effects or global state dependencies.

*Source: [src/IcingaProtocol/Private/Expand-IcingaProtocolMacroValue.ps1](../src/IcingaProtocol/Private/Expand-IcingaProtocolMacroValue.ps1)*

---

### Invoke-IcingaProtocolBinaryProcess

*Private function*

**Synopsis:** Execute an approved external binary or batch check process with timeout control

#### Description

Invoke-IcingaProtocolBinaryProcess runs an approved executable (.exe, .com, .cmd
or .bat) inside Get-ModuleBinaryDirectory via System.Diagnostics.Process with
UseShellExecute = $false:
1. Validates .cmd/.bat arguments against cmd.exe command, redirection and
   '%VAR%' expansion metacharacters before spawning a child process.
2. Escapes CLI tokens via Format-ModuleCommandLineArguments.
3. Captures StandardOutput and StandardError asynchronously (falling back to
   StandardError when StandardOutput is blank).
4. Enforces TimeoutMs across both process exit and output stream closure,
   terminating the entire process tree via Stop-IcingaProtocolProcessTree when
   exceeded.
5. Splits output and performance data via Split-IcingaBinaryPluginOutput.

#### Parameters

**`$BinaryPath`**

| Name       | Type          | Description                                            | Default |
|------------|---------------|--------------------------------------------------------|---------|
| BinaryPath | System.String | Full canonical path to the approved binary executable. | ''      |

**`$CommandName`**

| Name        | Type          | Description                                          | Default |
|-------------|---------------|------------------------------------------------------|---------|
| CommandName | System.String | Display file name of the binary for status messages. | ''      |

**`$BinaryArguments`**

| Name            | Type            | Description                                         | Default |
|-----------------|-----------------|-----------------------------------------------------|---------|
| BinaryArguments | System.String[] | Ordered CLI argument tokens to pass to the process. | @()     |

**`$TimeoutMs`**

| Name      | Type         | Description                                                  | Default |
|-----------|--------------|--------------------------------------------------------------|---------|
| TimeoutMs | System.Int32 | Maximum execution window in milliseconds before termination. | 60000   |

**`$DefaultCommandLine`**

| Name               | Type          | Description                                              | Default |
|--------------------|---------------|----------------------------------------------------------|---------|
| DefaultCommandLine | System.String | Rendered command line reported in CheckResult telemetry. | ''      |

#### Outputs

System.Collections.Hashtable -- Hashtable containing ExitCode, Output,
PerformanceData and CommandLine.

#### Examples

```powershell
PS> Invoke-IcingaProtocolBinaryProcess -BinaryPath 'C:\ProgramData\IcingaForWindows\Binaries\check_load.exe' -CommandName 'check_load.exe' -BinaryArguments @('-w', '80%') -TimeoutMs 60000

Executes check_load.exe with a 60s timeout and splits its Nagios output.
```

#### Notes

Always disposes the root Process handle in finally.

*Source: [src/IcingaProtocol/Private/Invoke-IcingaProtocolBinaryProcess.ps1](../src/IcingaProtocol/Private/Invoke-IcingaProtocolBinaryProcess.ps1)*

---

### Invoke-IcingaProtocolCheckCommand

*Private function*

**Synopsis:** Resolve, validate and execute an Icinga 2 ExecuteCommand payload

#### Description

Invoke-IcingaProtocolCheckCommand orchestrates the complete execution lifecycle
for an Icinga 2 event::ExecuteCommand RPC request:
1. Clears the thread-local CheckResult and ActiveCheckCommand slots on
   Get-GlobalRuntimeVariable.
2. Resolves macros.ifw_api_command via Resolve-IcingaProtocolCommand (returning
   UNKNOWN 3 with IWKB001003 on missing, unapproved or unknown commands).
3. Parses macros via ConvertFrom-IcingaProtocolMacros (returning UNKNOWN 3 with
   IWKB001000, IWKB001001 or IWKB001002 on macro/parameter mapping errors).
4. Executes PowerShell check plugins via Invoke-ModulePowerShellCommand and
   approved external .ps1 scripts via Invoke-IcingaProtocolExternalScript.
5. Executes approved native binaries and batch scripts (.exe, .cmd, .bat, .com)
   via Invoke-IcingaProtocolBinaryProcess with check_timeout enforcement and
   descendant process-tree termination.
6. Normalizes exit codes outside 0..3 to 3 (UNKNOWN) and records telemetry.

Returns a plain hashtable of primitive values and arrays so no PowerShell class
instance ever crosses runspace boundaries.

#### Parameters

**`$Params`**

| Name   | Type          | Description                                                          | Default |
|--------|---------------|----------------------------------------------------------------------|---------|
| Params | System.Object | Deserialized params dictionary or object from event::ExecuteCommand. | $null   |

#### Outputs

System.Collections.Hashtable -- Hashtable containing ExitCode (Int32 0..3),
Output (String), PerformanceData (Array) and CommandLine (String).

#### Examples

```powershell
PS> Invoke-IcingaProtocolCheckCommand -Params @{ 'command' = 'Invoke-IcingaCheckUptime'; 'macros' = @{ 'ifw_api_command' = 'Invoke-IcingaCheckUptime' } }

Executes Invoke-IcingaCheckUptime and returns its exit code, output, perfdata
and rendered command line.
```

#### Notes

Runs inside protocol worker threads; accesses runtime state exclusively via
Get-GlobalRuntimeVariable.

*Source: [src/IcingaProtocol/Private/Invoke-IcingaProtocolCheckCommand.ps1](../src/IcingaProtocol/Private/Invoke-IcingaProtocolCheckCommand.ps1)*

---

### Invoke-IcingaProtocolExternalScript

*Private function*

**Synopsis:** Bind CLI arguments and execute an approved external PowerShell check script

#### Description

Invoke-IcingaProtocolExternalScript introspects an external .ps1 script inside
Get-ModuleBinaryDirectory via Get-ModuleCommandParameterMap, parses CLI-style
BinaryArguments ('-Param:Val', '-Param Val', switches, multi-item arrays and
positional parameters), coerces values through ConvertTo-ModuleParameterValue,
masks any SecureString parameter tokens as '********' in the returned
CommandLine via Format-ModuleCommandLineArguments, and executes the script
in-process via Invoke-ModulePowerShellCommand -UseLastExitCode.

#### Parameters

**`$ScriptPath`**

| Name       | Type          | Description                                            | Default |
|------------|---------------|--------------------------------------------------------|---------|
| ScriptPath | System.String | Full canonical path to the approved .ps1 check script. | ''      |

**`$CommandName`**

| Name        | Type          | Description                                         | Default |
|-------------|---------------|-----------------------------------------------------|---------|
| CommandName | System.String | Display file name of the script for error messages. | ''      |

**`$BinaryArguments`**

| Name            | Type            | Description                                      | Default |
|-----------------|-----------------|--------------------------------------------------|---------|
| BinaryArguments | System.String[] | Ordered CLI tokens produced by macro resolution. | @()     |

**`$DefaultCommandLine`**

| Name               | Type          | Description                                              | Default |
|--------------------|---------------|----------------------------------------------------------|---------|
| DefaultCommandLine | System.String | Pre-rendered command line when no secret masking occurs. | ''      |

#### Outputs

System.Collections.Hashtable -- Hashtable containing ExitCode, Output,
PerformanceData and CommandLine.

#### Examples

```powershell
PS> Invoke-IcingaProtocolExternalScript -ScriptPath 'C:\ProgramData\IcingaForWindows\Binaries\check_custom.ps1' -CommandName 'check_custom.ps1' -BinaryArguments @('-ExitWith', '0')

Binds the parameters of check_custom.ps1 and executes it in-process.
```

#### Notes

Delegates execution and deterministic SecureString disposal to
Invoke-ModulePowerShellCommand.

*Source: [src/IcingaProtocol/Private/Invoke-IcingaProtocolExternalScript.ps1](../src/IcingaProtocol/Private/Invoke-IcingaProtocolExternalScript.ps1)*

---

### New-IcingaAgentEnvironment

*Private function*

**Synopsis:** Initializes the Icinga Protocol runtime environment and starts worker, listener and connector threads.

#### Description

New-IcingaAgentEnvironment prepares $Global:IcingaForWindows.Public.IcingaProtocol for
accepting and initiating Icinga 2 protocol connections. It reads connection configuration
via Read-IcingaProtocolConnection and certificate directory via Get-ModuleCertificateDirectory.
When a connection configuration is present, it applies Zone, Hostname, Endpoints,
ListenAddress and ListenPort to the global config. If no connection configuration is
returned, the function assumes the remote master or satellite will initiate connections
to this host. Default values of 0.0.0.0 and port 5665 are applied when not provided.
The function then loads a PFX certificate named after the configured hostname from the
certificate directory. If the certificate file is not found, the function returns early
via Write-FunctionReturnValue. After certificate loading, it initializes the Connections
hashtable and WorkerQueue, creates one BlockingCollection-backed queue per worker and
spawns the corresponding Start-IcingaProtocolWorker threads via New-Thread. Finally, it
starts the listener and connector threads. This function must be called once during
process initialization and must not be called again while threads are running.

#### Outputs

None -- Performs initialization and starts background threads. Returns early via
Write-FunctionReturnValue when the certificate file is missing.

#### Examples

```powershell
PS> New-IcingaAgentEnvironment

Reads module configuration, loads the PFX certificate, initializes global runtime
structures and starts all protocol worker, listener and connector threads.
```

#### Notes

Requires read access to the PFX certificate file under the module certificate directory.
The PFX is loaded without an explicit password; ensure it is not password-protected.
Global state modified: $Global:IcingaForWindows.Public.IcingaProtocol.Config,
Certificate, Connections and WorkerQueue. Config.WorkerCount must be a positive integer
before this function is called.

*Source: [src/IcingaProtocol/Private/New-IcingaAgentEnvironment.ps1](../src/IcingaProtocol/Private/New-IcingaAgentEnvironment.ps1)*

---

### New-IcingaRPCMessage

*Private function*

**Synopsis:** Creates a length-prefixed JSON-RPC 2.0 message for the Icinga protocol.

#### Description

New-IcingaRPCMessage builds a JSON-RPC 2.0 message hashtable with the keys
jsonrpc, method and params, serializes it to compact JSON and prefixes it with
the UTF-8 byte length followed by a colon (Icinga framing). The result is a
hashtable with the keys message (byte array) and length (integer) ready to be
passed to Send-TCPMessage or Add-IcingaRPCMessageToWriterQueue.

#### Parameters

**`$Method`**

| Name   | Type          | Description                                       | Default |
|--------|---------------|---------------------------------------------------|---------|
| Method | System.String | JSON-RPC method name (for example icinga::Hello). |         |

**`$Parameters`**

| Name       | Type                         | Description                                    | Default |
|------------|------------------------------|------------------------------------------------|---------|
| Parameters | System.Collections.Hashtable | Parameters to include in the RPC params field. | @{}     |

#### Outputs

System.Collections.Hashtable -- Hashtable with keys message (System.Byte[]) and length (System.Int32).

#### Examples

```powershell
PS> New-IcingaRPCMessage -Method 'icinga::Hello'

Returns a length-prefixed encoded message hashtable for the Hello handshake.
```

#### Notes

The method call is logged at Debug level via Write-LoggingEntry before the byte
encoding step.

*Source: [src/IcingaProtocol/Private/New-IcingaRPCMessage.ps1](../src/IcingaProtocol/Private/New-IcingaRPCMessage.ps1)*

---

### Read-IcingaProtocolConnection

*Private function*

**Synopsis:** Reads the Icinga protocol connection configuration file and returns parsed JSON.

#### Description

Read-IcingaProtocolConnection locates the module configuration directory, loads
IcingaProtocol\Connection.json, performs simple placeholder replacements
($fqdn, $hostname) and returns the parsed JSON object. When the configuration
file is not found, the function returns a standardized result object via
Write-FunctionReturnValue with return value IcingaClientConfigNotFound.

#### Outputs

PSCustomObject -- Parsed JSON connection configuration.
Returns a Write-FunctionReturnValue result object when the file is missing.

#### Examples

```powershell
PS> $cfg = Read-IcingaProtocolConnection
```

#### Notes

Placeholder substitution uses [System.Net.Dns]::GetHostEntry and GetHostName.
The configuration file is read through Read-SecureFile to enforce path approval.

*Source: [src/IcingaProtocol/Private/Read-IcingaProtocolConnections.ps1](../src/IcingaProtocol/Private/Read-IcingaProtocolConnections.ps1)*

---

### Read-IcingaRPCMessage

*Private function*

**Synopsis:** Parses one or more length-prefixed JSON-RPC frames from a StringBuilder buffer.

#### Description

Read-IcingaRPCMessage processes the accumulated StringBuilder buffer in a
loop. For each iteration it strips a leading comma if present, reads the numeric
length prefix before the first colon, extracts exactly that many characters as the
RPC payload and passes the payload to Add-IcingaRPCMessageToWorker for worker
dispatch. The consumed portion is removed from the buffer and the loop continues
until the buffer is empty, the size prefix is invalid or insufficient data remains
for a complete frame.

#### Parameters

**`$Buffer`**

| Name   | Type                      | Description                                                                         | Default |
|--------|---------------------------|-------------------------------------------------------------------------------------|---------|
| Buffer | System.Text.StringBuilder | Accumulated StringBuilder buffer containing one or more length-prefixed RPC frames. | $null   |

#### Outputs

None -- The buffer is modified in place.

#### Examples

```powershell
PS> Read-IcingaRPCMessage -Buffer $buffer
```

#### Notes

Each call may process multiple complete frames in a single pass. Partial frames at
the end of the buffer are preserved for the next read cycle.
Complete messages are dispatched via Add-IcingaRPCMessageToWorker.

*Source: [src/IcingaProtocol/Private/Read-IcingaRPCMessage.ps1](../src/IcingaProtocol/Private/Read-IcingaRPCMessage.ps1)*

---

### Resolve-IcingaProtocolCommand

*Private function*

**Synopsis:** Resolve and validate an Icinga ExecuteCommand target against approved plugins and binaries

#### Description

Resolve-IcingaProtocolCommand inspects macros.ifw_api_command from an incoming
Icinga 2 event::ExecuteCommand payload and resolves it deterministically without
consulting $env:PATH or guessing from params.command. If ifw_api_command is
missing or blank, Status is returned as CommandMissing (IWKB001003). Control
characters (0x00..0x1F), NTFS Alternate Data Stream colons, drive-relative paths,
directory separators and parent-directory traversal segments are validated and
normalized against Get-ModuleBinaryDirectory, returning BinaryPathRejected
(IWKB001003) whenever invalid or escaping that directory. Explicit
Invoke-IcingaCheck* names are resolved via Get-Command against loaded functions
and cmdlets (preferring Icinga* module commands). Bare names and relative
filenames are probed strictly inside Get-ModuleBinaryDirectory via
System.IO.File.Exists (exact match when a known executable extension is present,
or probing .exe, .cmd, .bat, .com, .ps1 when extensionless or carrying a
non-executable dotted suffix such as check_app_v1.2). If no binary exists in
Get-ModuleBinaryDirectory and the name has neither path separators nor an
extension, shorthand PowerShell check names such as 'cpu' or 'IcingaCheckCPU'
are expanded to 'Invoke-IcingaCheck*' and resolved as PowerShell check commands.

#### Parameters

**`$Macros`**

| Name   | Type          | Description                                                          | Default |
|--------|---------------|----------------------------------------------------------------------|---------|
| Macros | System.Object | Deserialized macros dictionary or object from event::ExecuteCommand. | $null   |

**`$CheckCommand`**

| Name         | Type          | Description                                                                  | Default |
|--------------|---------------|------------------------------------------------------------------------------|---------|
| CheckCommand | System.String | Optional Icinga CheckCommand object name (params.command) for error context. | ''      |

#### Outputs

System.Collections.Hashtable -- Resolution descriptor containing Status, Kind,
CommandName, BinaryPath, Parameters, Message, KnowledgeBaseId and ReturnCodeKey.

#### Examples

```powershell
PS> Resolve-IcingaProtocolCommand -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheckDirectory' }

Resolves the PowerShell check command and returns its parameter metadata.
```

```powershell
PS> Resolve-IcingaProtocolCommand -Macros @{ 'ifw_api_command' = 'cpu' }

Expands the shorthand 'cpu' to Invoke-IcingaCheckCPU when no cpu binary exists
in Get-ModuleBinaryDirectory.
```

#### Notes

Never searches $env:PATH for binaries or scripts. External executables must
reside inside Get-ModuleBinaryDirectory.

*Source: [src/IcingaProtocol/Private/Resolve-IcingaProtocolCommand.ps1](../src/IcingaProtocol/Private/Resolve-IcingaProtocolCommand.ps1)*

---

### Send-IcingaProtocolCertificateRequest

*Private function*

**Synopsis:** Send a certificate request message over the Icinga protocol

#### Description

Sends an Icinga RPC message with the method 'pki::RequestCertificate'
to request a new certificate. This is typically part of the initial node
setup and certificate signing request (CSR) workflow. If a ticket is
provided it is included in the RPC parameters for auto-signing.

#### Parameters

**`$Ticket`**

| Name   | Type          | Description                         | Default |
|--------|---------------|-------------------------------------|---------|
| Ticket | System.String | The ticket to use for auto-signing. | $null   |

#### Outputs

None -- Does not return any value.

#### Examples

```powershell
PS> Send-IcingaProtocolCertificateRequest -Ticket '1234567890abcdef'

Sends a certificate request to the connected Icinga endpoint.
```

#### Notes

Requires an active TCP connection to the Icinga endpoint.

*Source: [src/IcingaProtocol/Private/Send-IcingaProtocolCertificateRequest.ps1](../src/IcingaProtocol/Private/Send-IcingaProtocolCertificateRequest.ps1)*

---

### Send-IcingaProtocolCheckResult

*Private function*

**Synopsis:** Sends a check result as a JSON-RPC event to the remote Icinga endpoint.

#### Description

Send-IcingaProtocolCheckResult takes a hashtable describing a plugin check
result and packages it into an RPC message with method event::CheckResult via
New-IcingaRPCMessage and enqueues it through Add-IcingaRPCMessageToWriterQueue.
The function validates the provided hashtable and logs an error if it is empty
or null.

#### Parameters

**`$CheckResult`**

| Name        | Type                         | Description                                                 | Default |
|-------------|------------------------------|-------------------------------------------------------------|---------|
| CheckResult | System.Collections.Hashtable | Check result fields expected by Icinga (host, service, cr). | @{}     |

#### Outputs

None -- Logs errors via Write-LoggingEntry and enqueues the message through the writer queue.

#### Examples

```powershell
PS> Send-IcingaProtocolCheckResult -CheckResult @{ host = 'myhost'; service = 'ping'; cr = @{ exit_status = 0; output = 'OK' } }
```

#### Notes

Requires New-IcingaRPCMessage and Add-IcingaRPCMessageToWriterQueue to be available.
The check result is sent asynchronously via the per-endpoint writer queue.

*Source: [src/IcingaProtocol/Private/Send-IcingaProtocolCheckResult.ps1](../src/IcingaProtocol/Private/Send-IcingaProtocolCheckResult.ps1)*

---

### Send-IcingaProtocolHeartbeat

*Private function*

**Synopsis:** Sends a periodic Icinga protocol heartbeat over the established TCP connection.

#### Description

Checks the module's global heartbeat timer and, if the configured interval has elapsed
(or no previous heartbeat time exists), constructs and transmits an Icinga RPC heartbeat
message. The function logs the activity, creates an RPC message with method 'event::Heartbeat'
and a timeout parameter of 120 seconds, sends it via the module's TCP send routine, and
updates the global heartbeat timestamp.

#### Outputs

None -- Performs side effects: sends a TCP heartbeat message, writes log entries and updates the global heartbeat timestamp.

#### Examples

```powershell
PS> Send-IcingaProtocolHeartbeat

Sends a heartbeat now if the configured interval has elapsed, otherwise does nothing.
```

#### Notes

Relies on $Global:IcingaForWindows.Private.TCP.HeartbeatTimer and HeartbeatInterval
being present and correctly configured. Requires Write-LoggingEntry, New-IcingaRPCMessage
and Send-TCPMessage. The heartbeat message includes a parameter timeout set to 120 seconds.
Time comparisons use Get-Date and TotalSeconds to determine interval expiry.

*Source: [src/IcingaProtocol/Private/Send-IcingaProtocolHeartbeat.ps1](../src/IcingaProtocol/Private/Send-IcingaProtocolHeartbeat.ps1)*

---

### Send-IcingaProtocolHello

*Private function*

**Synopsis:** Sends an Icinga protocol Hello message on the active connection.

#### Description

Send-IcingaProtocolHello constructs a minimal JSON-RPC hello message using
New-IcingaRPCMessage with method icinga::Hello and sends it directly via
Send-TCPMessage. Use this to initiate the protocol handshake where required
by the remote endpoint, typically before the writer queue is active.

#### Outputs

None -- Sends the Hello frame directly via Send-TCPMessage; no pipeline output.

#### Examples

```powershell
PS> Send-IcingaProtocolHello

Sends the Hello message over the current TCP/SSL stream.
```

#### Notes

This function bypasses the writer queue and calls Send-TCPMessage directly,
making it suitable for early handshake messages before the queue is initialized.

*Source: [src/IcingaProtocol/Private/Send-IcingaProtocolHello.ps1](../src/IcingaProtocol/Private/Send-IcingaProtocolHello.ps1)*

---

### Send-IcingaProtocolLogPosition

*Private function*

**Synopsis:** Send a log position update message over the Icinga protocol

#### Description

Sends an Icinga RPC message with the method 'log::SetLogPosition'
to update the current log position on the connected endpoint. The
log position is automatically set to the current Unix timestamp
using Get-IcingaUnixTime.

#### Outputs

None -- Does not return any value.

#### Examples

```powershell
PS> Send-IcingaProtocolLogPosition

Sends the log position update to the connected Icinga endpoint.
```

#### Notes

Requires an active TCP connection to the Icinga endpoint.

*Source: [src/IcingaProtocol/Private/Send-IcingaProtocolLogPosition.ps1](../src/IcingaProtocol/Private/Send-IcingaProtocolLogPosition.ps1)*

---

### Split-IcingaBinaryPluginOutput

*Private function*

**Synopsis:** Split Nagios and Icinga binary plugin stdout into text output and performance data

#### Description

Split-IcingaBinaryPluginOutput separates raw console output produced by an
external Nagios or Icinga plugin binary at the pipe delimiter ('|') according to
the Monitoring Plugins specification. Supports single-line and multi-line check
output as well as multi-line performance data blocks, while preserving quoted,
scoped and doubled-quote metric labels containing spaces (for example
"'C:\ Free Space'=50GB;20;10;0;100" or "check_disk::'C:\ Free Space'=12GB") as
individual elements in the returned PerformanceData array.

#### Parameters

**`$RawOutput`**

| Name      | Type          | Description                                            | Default |
|-----------|---------------|--------------------------------------------------------|---------|
| RawOutput | System.String | Raw stdout captured from an external binary or script. | ''      |

#### Outputs

System.Collections.Hashtable -- Hashtable with keys Output (System.String) and
PerformanceData (System.Array of metric strings).

#### Examples

```powershell
PS> Split-IcingaBinaryPluginOutput -RawOutput "DISK OK - free space | 'C:\ Free'=50GB;20;10;0;100 inode=12%"

Splits the plugin output into its human-readable status message and two
individual performance-data metric strings.
```

#### Notes

Pure string parser with no external dependencies or side effects.

*Source: [src/IcingaProtocol/Private/Split-IcingaBinaryPluginOutput.ps1](../src/IcingaProtocol/Private/Split-IcingaBinaryPluginOutput.ps1)*

---

### Start-IcingaProtocolConnector

*Private function*

**Synopsis:** Starts a continuous connector loop that attempts to establish and maintain TCP connections to configured Icinga endpoints.

#### Description

Start-IcingaProtocolConnector runs an infinite loop that iterates through the configured
endpoints stored in $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints. For
each endpoint it logs a connection attempt, resolves the address via Resolve-IcingaIPAddress,
checks the current connection status with Test-IcingaProtocolClientStatus and, when a new
connection is required, creates a System.Net.Sockets.TcpClient, connects to the configured
address and port, registers the client via Add-IcingaProtocolClient and spawns a socket
reader thread with Start-IcingaProtocolSocketReader. Exceptions per endpoint are caught,
logged and do not stop the overall loop. The loop pauses for 5 seconds between full endpoint
scans. Because the function runs indefinitely, it must always be started in a background thread.

#### Outputs

None -- Manages connections, global state and log entries; no pipeline output.

#### Examples

```powershell
PS> New-Thread -Command 'Start-IcingaProtocolConnector' -Start

Starts the connector loop in a dedicated background thread via the module thread helper.
```

#### Notes

Reads endpoints from $Global:IcingaForWindows.Public.IcingaProtocol.Config.Endpoints.
Uses return-code constants from $Global:IcingaForWindows.Public.ReturnCodes.
The function is intentionally long-running and blocking; always run it in a background
thread. Exceptions during individual connection attempts are logged and do not stop the
overall loop. The loop pauses for 5 seconds between full endpoint scans to avoid tight
reconnect cycles.

*Source: [src/IcingaProtocol/Private/Start-IcingaProtocolConnector.ps1](../src/IcingaProtocol/Private/Start-IcingaProtocolConnector.ps1)*

---

### Start-IcingaProtocolHeartbeat

*Private function*

**Synopsis:** Starts a recurring heartbeat sender over an established TCP/TLS connection to keep the remote endpoint alive and detect disconnects.

#### Description

Start-IcingaProtocolHeartbeat validates and registers a provided System.Net.Sockets.TcpClient and System.Net.Security.SslStream for use by the Icinga protocol heartbeat subsystem, then enters a loop that periodically sends heartbeat messages until the TCP connection is lost. The function logs connection loss and other exceptions, closes the TCP connection when the client disconnects, and stops the current Icinga thread.

This function relies on helper functions from the Icinga for Windows module (for example: Set-TCPClientAndStream, Test-TCPConnection, Send-IcingaProtocolHeartbeat, Close-TCPConnection, Stop-Thread, Get-ThreadId and Write-LoggingEntry) to perform its work. It is intended to be used after a successful connection handshake and when you have an active SslStream wrapped around a TcpClient.

#### Parameters

**`$TcpClient`**

| Name      | Type                         | Description                                                      | Default |
|-----------|------------------------------|------------------------------------------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Connected TCP client representing the remote endpoint. Required. | $null   |

**`$SslStream`**

| Name      | Type                          | Description                                                                    | Default |
|-----------|-------------------------------|--------------------------------------------------------------------------------|---------|
| SslStream | System.Net.Security.SslStream | SSL/TLS stream wrapping the network stream for secure communication. Required. | $null   |

#### Outputs

None -- Sends heartbeat messages, writes log entries, closes the connection and stops
the current thread when the connection terminates.

#### Examples

```powershell
PS> Start-IcingaProtocolHeartbeat -TcpClient $tcp -SslStream $stream

Starts the heartbeat loop for an established TcpClient and its authenticated SslStream.
```

```powershell
PS> New-Thread -Command 'Start-IcingaProtocolHeartbeat' -Parameters @{ '-TcpClient' = $tcp; '-SslStream' = $stream } -Start

Starts the heartbeat in a dedicated background thread using the module thread helper.
```

#### Notes

The function returns immediately with an error log entry if either parameter is null.
Heartbeats are sent once per second while Test-ThreadRunning -CheckTcpConnection returns
true. MethodInvocationException during send is logged at Info level as a connection loss
event. After the loop exits, the TCP connection is closed and the current thread is stopped
via Stop-Thread.

*Source: [src/IcingaProtocol/Private/Start-IcingaProtocolHeartbeat.ps1](../src/IcingaProtocol/Private/Start-IcingaProtocolHeartbeat.ps1)*

---

### Start-IcingaProtocolListener

*Private function*

**Synopsis:** Starts the Icinga protocol TCP listener and accepts incoming client connections.

#### Description

Start-IcingaProtocolListener opens a TCP listener on the configured ListenAddress and
ListenPort via Open-TCPSocket and enters a continuous loop to accept and validate
incoming TCP clients. For each accepted connection it validates the client via
Test-IcingaProtocolClientStatus, closes duplicate or invalid connections, registers
the new client via Add-IcingaProtocolClient and spawns a dedicated socket reader
thread with Start-IcingaProtocolSocketReader via New-Thread. Exceptions per iteration
are caught and logged to keep the listener loop alive. The function runs until the
hosting process is stopped and must always be started in a background thread.

#### Outputs

None -- Side-effect driven: opens a network listener, updates global state, writes log entries and spawns threads.

#### Examples

```powershell
PS> New-Thread -Command 'Start-IcingaProtocolListener' -Start

Starts the TCP listener in a dedicated background thread using the module thread helper.
```

#### Notes

Configuration is read from $Global:IcingaForWindows.Public.IcingaProtocol.Config.ListenAddress
and ListenPort. The function is intentionally long-running and blocking; always run it in a
background thread. Requires Open-TCPSocket, Close-TCPConnection, Test-IcingaProtocolClientStatus,
Add-IcingaProtocolClient, New-Thread, Start-IcingaProtocolSocketReader and Write-LoggingEntry.
Exceptions are caught per iteration to keep the listener loop alive.

*Source: [src/IcingaProtocol/Private/Start-IcingaProtocolListener.ps1](../src/IcingaProtocol/Private/Start-IcingaProtocolListener.ps1)*

---

### Start-IcingaProtocolSocketReader

*Private function*

**Synopsis:** Starts a background loop that reads JSON-RPC framed messages from an established TCP/SSL connection and queues them for worker processing.

#### Description

Start-IcingaProtocolSocketReader initializes and manages reading from a provided System.Net.Sockets.TcpClient. It validates and registers the TCP client in the module's global connection state, spawns a heartbeat sender thread, optionally sends an initial Hello when acting as a client, and then continuously reads from the associated SSL stream. Incoming data is assembled into framed JSON-RPC messages (using a length-prefixed framing scheme), complete messages are enqueued for worker processing, and partial messages are preserved between reads. The reader loop runs until the TCP connection becomes invalid or an unrecoverable read error occurs; on exit, the connection is closed and the reader thread is stopped.

#### Parameters

**`$Client`**

| Name   | Type                         | Description                                                                | Default |
|--------|------------------------------|----------------------------------------------------------------------------|---------|
| Client | System.Net.Sockets.TcpClient | Established TCP connection to read from. Required; null causes early exit. | $null   |

**`$Endpoint`**

| Name     | Type          | Description                                                                    | Default |
|----------|---------------|--------------------------------------------------------------------------------|---------|
| Endpoint | System.String | Endpoint name used for SSL authentication with the IcingaProtocol certificate. | $null   |

**`$IsClient`**

| Name     | Type                                         | Description                                                      | Default |
|----------|----------------------------------------------|------------------------------------------------------------------|---------|
| IsClient | System.Management.Automation.SwitchParameter | When set, the reader sends an initial Hello after TLS handshake. | $false  |

#### Outputs

None -- Enqueues parsed JSON-RPC payloads for worker processing and updates global connection state.

#### Examples

```powershell
PS> New-Thread -Command 'Start-IcingaProtocolSocketReader' -Parameters @{ '-Client' = $client } -Start

Starts the socket reader for an accepted TcpClient in server role.
```

```powershell
PS> New-Thread -Command 'Start-IcingaProtocolSocketReader' -Parameters @{ '-Client' = $client; 'IsClient' = $true; 'Endpoint' = 'icinga-master' } -Start

Starts the socket reader for an outbound client connection and sends the initial Hello.
```

#### Notes

Updates global state under $Global:IcingaForWindows.Private.TCP (client, stream, LastWorkerId).
Uses a 4096-byte read buffer per iteration. Partial frames are accumulated and passed back
to Read-IcingaRPCMessage on subsequent reads. Heartbeat and writer threads are started via
New-Thread before the read loop begins.

*Source: [src/IcingaProtocol/Private/Start-IcingaProtocolSocketReader.ps1](../src/IcingaProtocol/Private/Start-IcingaProtocolSocketReader.ps1)*

---

### Start-IcingaProtocolSocketWriter

*Private function*

**Synopsis:** Drains the per-endpoint writer queue and sends each message over the SSL stream.

#### Description

Start-IcingaProtocolSocketWriter registers a BlockingCollection entry in
$Global:IcingaForWindows.Public.IcingaProtocol.WriterQueue keyed by the remote
endpoint IP address and then enters a blocking loop that takes messages from that
queue and forwards them via Send-TCPMessage. The function validates TcpClient and
SslStream on entry and stops the current thread if either is null or the TCP
connection is no longer valid. On a disposed writer queue the current thread is
stopped and the function exits cleanly after the loop. On any other dequeue error
the exception is logged and the loop continues. The function is intended to run in
a dedicated background thread spawned
by Start-IcingaProtocolSocketReader.

#### Parameters

**`$TcpClient`**

| Name      | Type                         | Description                                                             | Default |
|-----------|------------------------------|-------------------------------------------------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Connected TCP client whose remote endpoint identifies the writer queue. | $null   |

**`$SslStream`**

| Name      | Type                          | Description                                                      | Default |
|-----------|-------------------------------|------------------------------------------------------------------|---------|
| SslStream | System.Net.Security.SslStream | Authenticated SSL stream used by Send-TCPMessage to write bytes. | $null   |

#### Outputs

None -- Dequeues and sends messages; no pipeline output.

#### Examples

```powershell
PS> New-Thread -Command 'Start-IcingaProtocolSocketWriter' -Parameters @{ '-TcpClient' = $tcp; '-SslStream' = $stream } -Start -WaitForJobs

Starts the writer thread and waits until its queue entry is registered before continuing.
```

#### Notes

The writer queue entry for the endpoint is created inside this function using a
ConcurrentQueue-backed BlockingCollection. The WaitForJobs flag on New-Thread ensures the
queue slot exists before the first message is enqueued by other threads.

*Source: [src/IcingaProtocol/Private/Start-IcingaProtocolSocketWriter.ps1](../src/IcingaProtocol/Private/Start-IcingaProtocolSocketWriter.ps1)*

---

### Start-IcingaProtocolWorker

*Private function*

**Synopsis:** Start a protocol worker that processes enqueued Icinga 2 JSON-RPC messages

#### Description

Start-IcingaProtocolWorker pulls RPC message objects from the BlockingCollection
at (Get-GlobalRuntimeVariable).Public.IcingaProtocol.WorkerQueue[$WorkerId] and
dispatches them by method name via a switch statement. Supported methods include
icinga::Hello, event::ExecuteCommand, event::Heartbeat, config::Update,
log::SetLogPosition and pki::UpdateCertificate. For event::ExecuteCommand, the
worker starts a monotonic execution timer immediately before resolving and
evaluating arguments via Invoke-IcingaProtocolCheckCommand, stops the timer
immediately after check execution completes, logs execution telemetry and
dispatches the resulting CheckResult via Send-IcingaProtocolCheckResult.

#### Parameters

**`$WorkerId`**

| Name     | Type          | Description                                        | Default |
|----------|---------------|----------------------------------------------------|---------|
| WorkerId | System.Object | Zero-based index of the worker queue to pull from. | $null   |

#### Outputs

None -- Processes queued messages and sends replies; no pipeline output.

#### Examples

```powershell
PS> New-Thread -Command 'Start-IcingaProtocolWorker' -Parameters @{ 'WorkerId' = 0 } -KeepAlive -WaitForJobs -Start
```

#### Notes

WorkerId must be a valid index into the WorkerQueue ArrayList initialized by
New-IcingaAgentEnvironment. Accesses shared state via Get-GlobalRuntimeVariable
and nulls all per-iteration reference variables in finally to prevent daemon
memory retention.

*Source: [src/IcingaProtocol/Private/Start-IcingaProtocolWorker.ps1](../src/IcingaProtocol/Private/Start-IcingaProtocolWorker.ps1)*

---

### Stop-IcingaProtocolProcessTree

*Private function*

**Synopsis:** Terminate a timed-out external binary process and all of its descendant processes

#### Description

Stop-IcingaProtocolProcessTree ensures that a timed-out external binary check
cannot leave orphaned child processes holding stdout/stderr handles open or
consuming host resources:
- On Windows, kills the root process first while holding its SafeProcessHandle
  open (preventing OS PID reuse), performs up to three Win32_Process
  ParentProcessId breadth-first sweeps to terminate any newly spawned
  descendants, waits up to 2000ms per handle, and disposes all descendant
  Process handles.
- On Linux and macOS, walks child PIDs via 'pgrep -P', kills the root process
  tree (using Process.Kill($true) on PowerShell 7+), terminates every discovered
  descendant handle, waits for exit, and disposes all descendant handles.

#### Parameters

**`$Process`**

| Name    | Type                       | Description                                       | Default |
|---------|----------------------------|---------------------------------------------------|---------|
| Process | System.Diagnostics.Process | Live root Process object whose handle stays open. | $null   |

**`$RootProcessId`**

| Name          | Type         | Description                                     | Default |
|---------------|--------------|-------------------------------------------------|---------|
| RootProcessId | System.Int32 | OS process identifier of the root binary check. | 0       |

#### Outputs

None -- Terminates the process tree and waits briefly for OS rundown.

#### Examples

```powershell
PS> Stop-IcingaProtocolProcessTree -Process $proc -RootProcessId $proc.Id

Kills the root process and all descendant processes spawned by it.
```

#### Notes

Caller remains responsible for disposing the root Process instance after stream
drain completes.

*Source: [src/IcingaProtocol/Private/Stop-IcingaProtocolProcessTree.ps1](../src/IcingaProtocol/Private/Stop-IcingaProtocolProcessTree.ps1)*

---

### Test-IcingaProtocolClientStatus

*Private function*

**Synopsis:** Validates the status of an Icinga protocol TCP client for the specified address and optionally registers a new connection.

#### Description

Test-IcingaProtocolClientStatus examines the global Icinga for Windows protocol connection table to determine whether a TCP client for the provided Address is present and connected. If Address is null or empty, the function returns an invalid-address result. If a connection entry exists, the function checks the client object and its Connected property and returns a corresponding status. If no entry exists, the function attempts to add a new entry to the global connection table using the $TcpClient variable from the current scope and returns a created status.

#### Parameters

**`$Address`**

| Name    | Type          | Description                                                                   | Default |
|---------|---------------|-------------------------------------------------------------------------------|---------|
| Address | System.String | IP address string used to look up the client in the global connections table. | $null   |

#### Outputs

PSCustomObject -- Standardized result object from Write-FunctionReturnValue.
Possible tokens: IcingaAddressInvalid, IcingaClientReplaced, IcingaClientConnected, IcingaClientCreated.

#### Examples

```powershell
PS> Test-IcingaProtocolClientStatus -Address '10.0.0.5'

Checks the connection table for the given address and returns the appropriate status token.
```

```powershell
PS> Test-IcingaProtocolClientStatus

Returns IcingaAddressInvalid when no Address is provided.
```

#### Notes

- Side effects: when no existing connection entry is found the function adds a new entry to
    $Global:IcingaForWindows.Public.IcingaProtocol.Connections using the $TcpClient variable from the caller's scope.
- Precondition: $Global:IcingaForWindows.Public.IcingaProtocol.Connections must be an initialized hashtable or dictionary-like object that supports ContainsKey(), indexing, and Add().
- The function relies on client objects exposing a Connected property to determine connectivity.

*Source: [src/IcingaProtocol/Private/Test-IcingaProtocolClientStatus.ps1](../src/IcingaProtocol/Private/Test-IcingaProtocolClientStatus.ps1)*


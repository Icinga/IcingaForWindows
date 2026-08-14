# Icinga.Core.RestApi

*Auto-generated from `src/Core/RestApi/`. Do not edit by hand — run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [New-IcingaRestApiAccessControlObject](#new-icingarestapiaccesscontrolobject)
- [Send-IcingaRestApiRequest](#send-icingarestapirequest)
- [Set-IcingaRestApiConfig](#set-icingarestapiconfig)

## Private helpers

- [Add-RestApiClientToWorker](#add-restapiclienttoworker)
- [Expand-RestApiHeader](#expand-restapiheader)
- [Expand-RestApiQueryString](#expand-restapiquerystring)
- [Expand-RestApiWebPath](#expand-restapiwebpath)
- [Invoke-RestApiCall](#invoke-restapicall)
- [Invoke-RestApiCommandExecutionField](#invoke-restapicommandexecutionfield)
- [New-RestApiAccessControlObject](#new-restapiaccesscontrolobject)
- [New-RestApiEnvironment](#new-restapienvironment)
- [New-RestApiFaviconResponse](#new-restapifaviconresponse)
- [New-RestApiResponse](#new-restapiresponse)
- [Read-RestApiBody](#read-restapibody)
- [Read-RestApiConfig](#read-restapiconfig)
- [Read-RestApiHeader](#read-restapiheader)
- [Read-RestApiSpacesConfig](#read-restapispacesconfig)
- [Send-RestApiHtmlEndpointResponse](#send-restapihtmlendpointresponse)
- [Send-RestApiRequest](#send-restapirequest)
- [Set-RestApiConfig](#set-restapiconfig)
- [Start-RestApiDaemon](#start-restapidaemon)
- [Start-RestApiListener](#start-restapilistener)
- [Start-RestApiWorker](#start-restapiworker)
- [Test-RestApiAccessControl](#test-restapiaccesscontrol)
- [Test-RestApiCommandExecutionField](#test-restapicommandexecutionfield)

---

### New-IcingaRestApiAccessControlObject

*Public function*

**Synopsis:** Create a RestApi access control object for use in Icinga role definitions

#### Description

Public wrapper around `New-RestApiAccessControlObject` that constructs a
reusable access control descriptor for the RestApi subsystem. The returned
object specifies which HTTP methods, resources and client origins are
permitted for a role, whether credentials are required and the maximum
allowed request body size. Pass the returned object to `New-AccessRole`
to attach it to a user or group.

#### Parameters

**`$AllowedMethods`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedMethods | System.String[] | List of allowed HTTP methods (case-insensitive). Use `*` to allow all. | @('GET') |

**`$AllowedResources`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedResources | System.String[] | Glob-style patterns of resources that are explicitly allowed. Use `*` to allow all. | @() |

**`$BlockedResources`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| BlockedResources | System.String[] | Glob-style patterns of resources that are explicitly blocked. Use `*` to block all. | @('*') |

**`$AllowedOrigins`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedOrigins | System.String[] | Client IP or hostname patterns that may access the API. Use `*` to allow all origins. | @('*') |

**`$RequireCredentials`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequireCredentials | System.Boolean | When true, the access control entry requires credentials. | $false |

**`$RequestBodySizeLimitKB`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequestBodySizeLimitKB | System.Int32 | Maximum allowed request body size in kilobytes. Negative values are normalized to 0. | 1024 |

#### Outputs

PSCustomObject — access control object with `AllowedMethods`, `AllowedResources`,
`BlockedResources`, `AllowedOrigins`, `RequireCredentials`,
`RequestBodySizeLimit` (bytes) and `Scope` set to `RestApi`.

#### Examples

```powershell
PS> New-IcingaRestApiAccessControlObject -AllowedMethods @('GET','POST') -AllowedResources @('/v1/*') -RequestBodySizeLimitKB 512
```

#### Notes

The `RequireCredentials` flag is informational in the current implementation;
credential enforcement must be added in the request handling logic.
The KB limit is converted to bytes internally. At least one allowed method
must be specified; passing an empty array causes the function to return `$null`.

*Source: [src/Core/RestApi/Public/New-IcingaRestApiAccessControlObject.ps1](../../src/Core/RestApi/Public/New-IcingaRestApiAccessControlObject.ps1)*

---

### Send-IcingaRestApiRequest

*Public function*

**Synopsis:** Send an HTTP(S) request to the local Icinga RestApi endpoint

#### Description

Public wrapper around `Send-RestApiRequest` that sends an HTTP or HTTPS
request to the locally running RestApi daemon. The function loads the
RestApi configuration to determine the listen port, constructs the full
URI and forwards the call using `Invoke-RestMethod` with TLS certificate
checking disabled for self-signed certificates. Non-GET methods serialize
the `Body` hashtable as JSON. Non-200 responses are returned as failures.

#### Parameters

**`$WebPath`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| WebPath | System.String | Relative web path or endpoint (e.g. '/v1/status'). Leading slash is optional. | '' |

**`$Method`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Method | System.String | HTTP method to use (GET, POST, PUT, DELETE, etc.). | 'GET' |

**`$Headers`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Headers | System.Collections.Hashtable | Additional HTTP headers to include in the request. | @{ 'Content-Type' = 'application/json'; } |

**`$Body`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Body | System.Collections.Hashtable | Request body serialized as JSON for non-GET methods. | @{ } |

#### Outputs

PSCustomObject — structured return value from `Write-FunctionReturnValue`.
`RestApiRequestSuccessful` with `Response` in Data on success;
`RestApiRequestFailed` with `StatusCode` and `Response` or `Exception` on failure.

#### Examples

```powershell
PS> Send-IcingaRestApiRequest -WebPath '/v1/status' -Method 'GET'
PS> Send-IcingaRestApiRequest -WebPath '/v1/items' -Method 'POST' -Body @{ name = 'test' }
```

#### Notes

Requires a valid `restapi.json` configuration file to be present in the
module config directory. The request always targets `https://localhost:<port>`.
Certificate validation is skipped via `-SkipCertificateCheck` to support
self-signed TLS certificates.

*Source: [src/Core/RestApi/Public/Send-IcingaRestApiRequest.ps1](../../src/Core/RestApi/Public/Send-IcingaRestApiRequest.ps1)*

---

### Set-IcingaRestApiConfig

*Public function*

**Synopsis:** Public wrapper to configure the Icinga RestApi settings.

#### Description

Public function that validates and applies RestApi configuration by delegating
to the private `Set-RestApiConfig` function. This is the supported public API
for module consumers to update the RestApi listen address, port, TLS
configuration and worker count. The function returns the same standardized
return objects as the underlying private implementation.

#### Parameters

**`$ListenAddress`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ListenAddress | System.String | IP address or hostname to bind the RestApi listener. Use '0.0.0.0' to bind all interfaces. | '0.0.0.0' |

**`$ListenPort`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ListenPort | System.Int32 | TCP port to listen on (1-65535). | 5668 |

**`$TlsCertConfig`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| TlsCertConfig | System.PSCustomObject | TLS certificate configuration created by `New-IcingaTlsCertConfig`. | $null |

**`$WorkerCount`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| WorkerCount | System.Int32 | Number of worker threads to spawn for handling connections. | 5 |

**`$DryRun`**

| Name   | Type                                         | Description                                                                                       | Default |
|--------|----------------------------------------------|---------------------------------------------------------------------------------------------------|---------|
| DryRun | System.Management.Automation.SwitchParameter | When set, returns a unified diff of the pending configuration versus the persisted restapi.json instead of writing the change. | $false |

#### Outputs

PSCustomObject — Function return value forwarded from `Set-RestApiConfig`.

#### Examples

```powershell
PS> Set-IcingaRestApiConfig -ListenAddress '127.0.0.1' -ListenPort 10443 -WorkerCount 8
```

#### Notes

This public wrapper exists to expose a stable module API while keeping the
implementation in `Set-RestApiConfig` (private) where validation and persistence
logic is implemented.

*Source: [src/Core/RestApi/Public/Set-IcingaRestApiConfig.ps1](../../src/Core/RestApi/Public/Set-IcingaRestApiConfig.ps1)*

---

### Add-RestApiClientToWorker

*Private function*

**Synopsis:** Assign a new TCP client to a RestApi worker queue.

#### Description

Performs a simple round-robin assignment of an accepted `TcpClient` to one
of the RestApi worker queues managed in the global runtime state. Logs the
assignment and validates the input client.

#### Parameters

**`$TcpClient`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | Accepted TCP client to assign to a worker queue. | |

#### Outputs

None

#### Examples

```powershell
PS> Add-RestApiClientToWorker -TcpClient $acceptedClient
```

#### Notes

This helper expects RestApi worker queues to be initialized under
`(Get-GlobalRuntimeVariable).Public.RestApi.WorkerQueue` and a
`WorkerCount` value in the RestApi configuration.

*Source: [src/Core/RestApi/Private/Add-RestApiClientToWorker.ps1](../../src/Core/RestApi/Private/Add-RestApiClientToWorker.ps1)*

---

### Expand-RestApiHeader

*Private function*

**Synopsis:** Parse raw HTTP header text into structured header data.

#### Description

Parses a raw HTTP request header string into a hashtable containing the
request method, path, HTTP version and a dictionary of headers. Returns
the parsed structure or logs an error and returns `$null` on parse failure.

#### Parameters

**`$HeaderString`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| HeaderString | System.String | Raw HTTP header string including request line and headers. | |

#### Outputs

System.Collections.Hashtable — parsed header hashtable with `Method`, `Path`, `HttpVersion` and `Headers`.

#### Examples

```powershell
PS> Expand-RestApiHeader -HeaderString $rawHeader
```

#### Notes

Used by RestApi worker processing to interpret incoming HTTP requests.

*Source: [src/Core/RestApi/Private/Expand-RestApiHeader.ps1](../../src/Core/RestApi/Private/Expand-RestApiHeader.ps1)*

---

### Expand-RestApiQueryString

*Private function*

**Synopsis:** Parse a URL query string into a hashtable of parameters.

#### Description

Parses a query string into key/value pairs while respecting quoted
values and percent-encoding. Multiple occurrences of the same key
are converted into arrays.

#### Parameters

**`$QueryString`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| QueryString | System.String | Raw query string (may include leading '?'). | |

**`$QueryParams`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| QueryParams | System.Collections.Hashtable | Hashtable to populate with parsed parameters. | @{} |

#### Outputs

None — modifies the provided `QueryParams` hashtable in place.

#### Examples

```powershell
PS> Expand-RestApiQueryString -QueryString '?q=hello%20world&tags=one&tags=two' -QueryParams $params
```

#### Notes

This function is tolerant to quoted parameter values and retains array
semantics for repeated keys.

*Source: [src/Core/RestApi/Private/Expand-RestApiQueryString.ps1](../../src/Core/RestApi/Private/Expand-RestApiQueryString.ps1)*

---

### Expand-RestApiWebPath

*Private function*

**Synopsis:** Normalize and split an HTTP path into segments.

#### Description

Normalizes a web path by collapsing consecutive slashes, trimming trailing
slashes (except for root) and returning an object with the normalized path
and an array of path segments.

#### Parameters

**`$WebPath`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| WebPath | System.String | The HTTP path to normalize (e.g. '/api/v1/resource/'). | |

#### Outputs

System.Collections.Hashtable — parsed path object with keys `Segments`, `QueryParams`, `WebPath`,
`HasQuery`, `SegmentCount` and optional `Version`, `Space`, `Action`, `Resource`.

#### Examples

```powershell
PS> Expand-RestApiWebPath -Path '/api//v1/resource/'
```

#### Notes

This helper is used when routing incoming requests to configured RestApi
spaces and handlers.

*Source: [src/Core/RestApi/Private/Expand-RestApiWebPath.ps1](../../src/Core/RestApi/Private/Expand-RestApiWebPath.ps1)*

---

### Invoke-RestApiCall

*Private function*

**Synopsis:** Resolve the REST API path to a configured handler and execute it.

#### Description

Core dispatcher of the Icinga for Windows REST API. Reads the parsed web-path
and headers from `$Global.Private.RestApi.*`, walks the configured
spaces hashtable (Space → Action → Resource) to locate an
`ApiCommandExecution` field and invokes the bound PowerShell function
via `Invoke-RestApiCommandExecutionField`. Emits the appropriate JSON
response on success and well-formed error responses on failure
(missing space → 404, invalid path depth → 400, command error → 500,
no spaces configured → 500, no command at all → HTML endpoint listing
or 200 / 404 for JSON callers).

#### Outputs

System.Int32 — A semantic return code resolved through
`Write-FunctionReturnValue` for downstream diagnostics. The HTTP
response is sent directly over the worker's TCP stream.

#### Examples

```powershell
PS> Invoke-RestApiCall

Called by `Start-RestApiWorker` after the request line and body have
been parsed; arguments are taken from worker-private state.
```

#### Notes

Path schema is `/v1/<Space>/<Action>/<Resource>`. The actual
`ApiCommandExecution` lookup supports 2, 3 or 4 segments (segment
count is checked before the handler runs).

*Source: [src/Core/RestApi/Private/Invoke-RestApiCall.ps1](../../src/Core/RestApi/Private/Invoke-RestApiCall.ps1)*

---

### Invoke-RestApiCommandExecutionField

*Private function*

**Synopsis:** Invoke the function defined in an ApiCommandExecution space configuration

#### Description

Validates the provided space object, resolves the configured PowerShell
function name, verifies the HTTP method is permitted, maps query or body
parameters to the expected types defined in the space configuration and
then calls the function via splatting. Web path, header and body context
are read from `(Get-GlobalRuntimeVariable).Private.RestApi`. Returns the
function result or a structured error object on failure.

#### Parameters

**`$Space`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Space | PSCustomObject | ApiCommandExecution configuration object with `Function`, `Method` and `Parameters` properties. | $null |

#### Outputs

System.Object — the return value of the invoked function, or a hashtable
with an `error` key when the invocation fails or is not permitted.

#### Examples

```powershell
PS> Invoke-RestApiCommandExecutionField -Space $spaceObj.ApiCommandExecution
```

#### Notes

Parameter type mapping supports `int`, `string`, `bool` and `array`.
Array values in GET query strings are split on commas while respecting
quoted strings. Must only be called from within a RestApi worker thread
after `Private.RestApi.WebPath` and `Private.RestApi.Header` are set.

*Source: [src/Core/RestApi/Private/Invoke-RestApiCommandExecutionField.ps1](../../src/Core/RestApi/Private/Invoke-RestApiCommandExecutionField.ps1)*

---

### New-RestApiAccessControlObject

*Private function*

**Synopsis:** Create a RestApi access control object describing allowed methods and resources.

#### Description

Helps construct a reusable access control object for RestApi spaces. The
object contains allowed HTTP methods, allowed/blocked resources, allowed
client origins, credentials requirement and a request body size limit.
It is intended to be embedded in system access roles or used directly by
the RestApi access control evaluation routines.

#### Parameters

**`$AllowedMethods`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedMethods | System.String[] | List of allowed HTTP methods (case-insensitive). Use `*` to allow all. | @('GET') |

**`$AllowedResources`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedResources | System.String[] | Glob-style patterns of resources that are explicitly allowed. Use `*` to allow all. | @() |

**`$BlockedResources`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| BlockedResources | System.String[] | Glob-style patterns of resources that are explicitly blocked. Use `*` to block all. | @('*') |

**`$AllowedOrigins`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| AllowedOrigins | System.String[] | Client IP/hostname patterns that are allowed to access the API. Use `*` to allow all origins. | @('*') |

**`$RequireCredentials`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequireCredentials | System.Boolean | When true, the ACL requires credentials (not implemented in this helper). | $false |

**`$RequestBodySizeLimitKB`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| RequestBodySizeLimitKB | System.Int32 | Maximum allowed request body size in kilobytes. Negative values are normalized to 0. | 1024 |

#### Outputs

PSCustomObject — access control object ready for inclusion in role definitions.

#### Examples

```powershell
PS> New-RestApiAccessControlObject -AllowedMethods @('GET','POST') -AllowedResources @('/v1/*') -RequestBodySizeLimitKB 512
```

#### Notes

The returned object converts KB limit to bytes and normalizes string
arrays. The `RequireCredentials` flag is informational — credential
enforcement must be implemented in the request handling logic.

*Source: [src/Core/RestApi/Private/New-RestApiAccessControlObject.ps1](../../src/Core/RestApi/Private/New-RestApiAccessControlObject.ps1)*

---

### New-RestApiEnvironment

*Private function*

**Synopsis:** Initialize RestApi runtime environment structures

#### Description

Loads the RestApi configuration from disk via `Read-RestApiConfig`, reads
all space definitions via `Read-RestApiSpacesConfig`, loads the TLS
certificate and then creates the blocking worker queues and spawns one
`Start-RestApiWorker` thread per configured worker. Finally, it starts the
`Start-RestApiListener` thread. The function reads worker count from
`(Get-GlobalRuntimeVariable).Public.RestApi.Config.WorkerCount` which must
be populated before this function runs.

#### Outputs

None — populates `(Get-GlobalRuntimeVariable).Public.RestApi.WorkerQueue`
and starts all worker and listener threads.

#### Examples

```powershell
PS> New-RestApiEnvironment
```

#### Notes

Must be called after `Set-RestApiConfig` has been executed so that a valid
`restapi.json` configuration file exists. All threads started here rely on
the global runtime variable rather than parameters, so thread-safety
depends on the blocking collections used for the worker queues.

*Source: [src/Core/RestApi/Private/New-RestApiEnvironment.ps1](../../src/Core/RestApi/Private/New-RestApiEnvironment.ps1)*

---

### New-RestApiFaviconResponse

*Private function*

**Synopsis:** Build an HTTP response object for a favicon.ico request.

#### Description

Constructs a simple response object containing the provided icon bytes
and correct `Content-Type` header for `image/x-icon`. Returns the response
structure or logs an error when no data is supplied.

#### Outputs

System.Collections.Hashtable — response object with `Message` (byte[]) and
`Length` (int), ready to pass to `Send-TCPMessage`.

#### Examples

```powershell
PS> New-RestApiFaviconResponse
```

#### Notes

The favicon is read from `assets\restapi\favicon.png` under the module root
directory. The function selects the correct MIME type (`image/x-icon` or
`image/png`) based on the file extension found at that path.

*Source: [src/Core/RestApi/Private/New-RestApiFaviconResponse.ps1](../../src/Core/RestApi/Private/New-RestApiFaviconResponse.ps1)*

---

### New-RestApiResponse

*Private function*

**Synopsis:** Build a full HTTP response byte array from status and body.

#### Description

Converts a status code, status message, content type and response body
into a single byte array suitable for sending over a TCP socket. When the
`Content-Type` is JSON the body is serialized with `ConvertTo-Json`.

#### Parameters

**`$StatusCode`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| StatusCode | System.Int32 | HTTP status code to send (e.g. 200). | 200 |

**`$StatusMessage`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| StatusMessage | System.String | Short HTTP status message (e.g. 'OK'). | 'OK' |

**`$ContentType`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ContentType | System.String | MIME type for the response body. | 'application/json; charset=utf-8' |

**`$ResponseBody`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ResponseBody | Object | Body payload; may be byte[], string or object (serialized to JSON). | |

#### Outputs

Hashtable with `Message` (byte[]) and `Length` (int) keys.

#### Examples

```powershell
PS> New-RestApiResponse -StatusCode 200 -ResponseBody @{ success = $true }
```

#### Notes

The returned `Message` is ready to be written to a TCP stream.

*Source: [src/Core/RestApi/Private/New-RestApiResponse.ps1](../../src/Core/RestApi/Private/New-RestApiResponse.ps1)*

---

### Read-RestApiBody

*Private function*

**Synopsis:** Read the HTTP request body from the TCP stream based on Content-Length.

#### Description

Reads the request body for an HTTP request already parsed into headers.
Honors `Content-Length`, enforces access control via
`Test-RestApiAccessControl` and returns a structured object with raw
bytes, string and parsed JSON (if applicable).

#### Parameters

**`$ParsedHeaders`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ParsedHeaders | System.Collections.Hashtable | Parsed header object produced by `Expand-RestApiHeader`. | @{ } |

**`$PreReadBodyBytes`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| PreReadBodyBytes | byte[] | Any body bytes that were read along with the headers. | @() |

#### Outputs

System.Collections.Hashtable — object with keys `RawBytes`, `RawString`, `JsonObj` and `ContentLength`.

#### Examples

```powershell
PS> Read-RestApiBody -ParsedHeaders $parsed -PreReadBodyBytes $extraBytes
```

#### Notes

Closes the TCP connection and returns `$null` if access control denies
the request or a timeout occurs while reading.

*Source: [src/Core/RestApi/Private/Read-RestApiBody.ps1](../../src/Core/RestApi/Private/Read-RestApiBody.ps1)*

---

### Read-RestApiConfig

*Private function*

**Synopsis:** Load RestApi configuration from disk.

#### Description

Reads the `restapi.json` configuration file from the module config
directory and stores the parsed object into the global runtime variable
under `(Get-GlobalRuntimeVariable).Public.RestApi.Config`.

#### Outputs

PSCustomObject — the loaded RestApi configuration on success, or a
structured return code object when the file is missing or corrupt.

#### Examples

```powershell
PS> Read-RestApiConfig
```

#### Notes

Logs structured return codes using `Write-FunctionReturnValue` when the
file is missing or cannot be parsed.

*Source: [src/Core/RestApi/Private/Read-RestApiConfig.ps1](../../src/Core/RestApi/Private/Read-RestApiConfig.ps1)*

---

### Read-RestApiHeader

*Private function*

**Synopsis:** Read raw HTTP header bytes from the TCP stream and return parsed header data.

#### Description

Reads from the TCP stream until the HTTP header terminator (`\r\n\r\n`) is
encountered or a timeout occurs. Returns a hashtable with raw header string,
raw bytes and any extra body bytes that were read alongside the headers.

#### Outputs

System.Collections.Hashtable — object with `RawString`, `RawBytes` and `ExtraBodyBytes`.

#### Examples

```powershell
PS> Read-RestApiHeader
```

#### Notes

This function reads directly from `(Get-GlobalRuntimeVariable).Private.TCP.Stream`.

*Source: [src/Core/RestApi/Private/Read-RestApiHeader.ps1](../../src/Core/RestApi/Private/Read-RestApiHeader.ps1)*

---

### Read-RestApiSpacesConfig

*Private function*

**Synopsis:** Load RestApi space definitions from the data directory.

#### Description

Reads all JSON files under `data/restapi/` and populates the global
private RestApi `Spaces` hashtable with parsed space configurations keyed
by filename (lowercase). Logs per-file parse results using `Write-FunctionReturnValue`.

#### Outputs

None — populates `(Get-GlobalRuntimeVariable).Private.RestApi.Spaces`.

#### Examples

```powershell
PS> Read-RestApiSpacesConfig
```

#### Notes

Each space file must contain a valid JSON object describing routes,
handlers and optional access control for that API space.

*Source: [src/Core/RestApi/Private/Read-RestApiSpacesConfig.ps1](../../src/Core/RestApi/Private/Read-RestApiSpacesConfig.ps1)*

---

### Send-RestApiHtmlEndpointResponse

*Private function*

**Synopsis:** Return an HTML listing of available RestApi endpoints for a space.

#### Description

Generates a simple HTML document listing available endpoints for the
provided space object or, if no space is given, lists all configured
spaces. The HTML is returned to the client as an HTTP response.

#### Parameters

**`$SpaceObj`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| SpaceObj | PSCustomObject | Optional space configuration object to enumerate endpoints for. | |

#### Outputs

None — sends an HTTP response with `Content-Type: text/html` via `Send-TCPMessage`.

#### Examples

```powershell
PS> Send-RestApiHtmlEndpointResponse -SpaceObj $space
```

#### Notes

Intended to be used by browser-based exploration of the RestApi.

*Source: [src/Core/RestApi/Private/Send-RestApiHtmlEndpointResponse.ps1](../../src/Core/RestApi/Private/Send-RestApiHtmlEndpointResponse.ps1)*

---

### Send-RestApiRequest

*Private function*

**Synopsis:** Send an HTTPS request to the local RestApi.

#### Description

Sends an HTTP(S) request to the local RestApi endpoint configured in the runtime.
Ensures the RestApi configuration is loaded, constructs the request URI and forwards
the request using `Invoke-RestMethod`. JSON bodies are serialized for non-GET
methods. The function returns standardized return values using
`Write-FunctionReturnValue`.

#### Parameters

**`$WebPath`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| WebPath | System.String | Relative web path or endpoint (for example '/v1/status'). Leading slash optional. | '' |

**`$Method`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Method | System.String | HTTP method to use (GET, POST, PUT, DELETE, etc.). | 'GET' |

**`$Headers`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Headers | System.Collections.Hashtable | Additional HTTP headers to include. | @{ 'Content-Type' = 'application/json'; } |

**`$Body`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Body | System.Hashtable | Request body to be serialized as JSON for non-GET methods. | @{ } |

#### Outputs

PSCustomObject — Function return value produced by `Write-FunctionReturnValue`.
- `RestApiRequestSuccessful`: Data contains `Response`.
- `RestApiRequestFailed`: Data contains `Exception`, `Uri`, `Method`, `Headers`, `Body` or `StatusCode` and `Response`.

#### Examples

```powershell
PS> Send-RestApiRequest -WebPath '/v1/status' -Method 'GET'
PS> Send-RestApiRequest -WebPath '/v1/items' -Method 'POST' -Body @{ name = 'test' }
```

#### Notes

Uses `Read-RestApiConfig` to ensure RestApi is configured and `Invoke-RestMethod`
with `-SkipCertificateCheck` for local/self-signed certificates. Non-200 status
codes are treated as failures and returned via `Write-FunctionReturnValue`.

*Source: [src/Core/RestApi/Private/Send-RestApiRequest.ps1](../../src/Core/RestApi/Private/Send-RestApiRequest.ps1)*

---

### Set-RestApiConfig

*Private function*

**Synopsis:** Configure RestApi listener, TLS and worker count and persist to restapi.json.

#### Description

Validates listen address, port and worker count, updates the global RestApi
configuration and writes the configuration to the module config directory as
`restapi.json`. Returns standardized function return values via
`Write-FunctionReturnValue`.

#### Parameters

**`$ListenAddress`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ListenAddress | System.String | IP address or hostname to bind the RestApi listener. Use '0.0.0.0' to bind all interfaces. | '0.0.0.0' |

**`$ListenPort`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| ListenPort | System.Int32 | TCP port to listen on (1-65535). | 10000 |

**`$TlsCertConfig`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| TlsCertConfig | System.PSCustomObject | TLS certificate configuration created by `New-TlsCertConfig`. | $null |

**`$WorkerCount`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| WorkerCount | System.Int32 | Number of worker threads to spawn for handling connections. | 5 |

**`$DryRun`**

| Name   | Type                                         | Description                                                                                       | Default |
|--------|----------------------------------------------|---------------------------------------------------------------------------------------------------|---------|
| DryRun | System.Management.Automation.SwitchParameter | When set, returns a unified diff of the pending configuration versus the persisted restapi.json instead of writing the change. | $false |

#### Outputs

PSCustomObject — Function return value via `Write-FunctionReturnValue`.
- `RestApiConfigConfigured`: Data contains `Config`.
- `NoRestApiListenAddressProvided`: invalid listen address.
- `NoRestApiListenPortProvided`: invalid port.
- `InvalidRestApiWorkerCountProvided`: invalid worker count (Data contains `WorkerCount` and `MaxThreads`).

#### Examples

```powershell
PS> Set-RestApiConfig -ListenAddress '127.0.0.1' -ListenPort 10443 -WorkerCount 8
```

#### Notes

Persists the configuration to `restapi.json` under the module config directory
using `Write-SecureFile` and `Get-ModuleConfigDirectory`. `WorkerCount` is
bounded by the global `Threading.MaxThreads` setting.

*Source: [src/Core/RestApi/Private/Set-RestApiConfig.ps1](../../src/Core/RestApi/Private/Set-RestApiConfig.ps1)*

---

### Start-RestApiDaemon

*Private function*

**Synopsis:** Start the RestApi daemon by initializing the RestApi environment.

#### Description

Creates a background thread that initializes the RestApi runtime
environment. This is a lightweight helper that delegates to
`New-RestApiEnvironment` on a new thread.

#### Outputs

None — starts a background thread and returns immediately.

#### Examples

```powershell
PS> Start-RestApiDaemon
```

#### Notes

This function starts a thread but does not wait for the environment to be
fully initialized. Use `New-RestApiEnvironment` directly when synchronous
initialization is required.

*Source: [src/Core/RestApi/Private/Start-RestApiDaemon.ps1](../../src/Core/RestApi/Private/Start-RestApiDaemon.ps1)*

---

### Start-RestApiListener

*Private function*

**Synopsis:** Start the RestApi TCP listener and accept incoming connections.

#### Description

Opens a TCP socket according to the RestApi configuration, then accepts
incoming connections and assigns them to worker queues via
`Add-RestApiClientToWorker`.

#### Outputs

None

#### Examples

```powershell
PS> Start-RestApiListener
```

#### Notes

This function runs on a dedicated thread and uses global runtime state
for configuration and worker management.

*Source: [src/Core/RestApi/Private/Start-RestApiListener.ps1](../../src/Core/RestApi/Private/Start-RestApiListener.ps1)*

---

### Start-RestApiWorker

*Private function*

**Synopsis:** Worker loop that processes assigned RestApi TCP clients.

#### Description

Executes the worker loop for a single RestApi worker. The worker
waits for accepted `TcpClient` instances from its queue, performs TLS
handshake, access control checks, reads the request and dispatches it to
the appropriate handler.

#### Parameters

**`$WorkerId`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| WorkerId | System.Int32 | Numeric identifier for this worker. | -1 |

**`$Spaces`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Spaces | System.Collections.Hashtable | Hashtable of RestApi space configurations. | @{ } |

#### Outputs

None — sends responses over the TCP connection and logs results.

#### Examples

```powershell
PS> Start-RestApiWorker -WorkerId 0 -Spaces $spaces
```

#### Notes

This function is designed to run as a long-lived thread and relies on
global runtime variables for TCP streams and timeouts.

*Source: [src/Core/RestApi/Private/Start-RestApiWorker.ps1](../../src/Core/RestApi/Private/Start-RestApiWorker.ps1)*

---

### Test-RestApiAccessControl

*Private function*

**Synopsis:** Evaluate access control rules for an incoming RestApi request.

#### Description

Checks configured access control entries for the RestApi subsystem and
determines whether the current request is permitted. Supports checking
origins (client IP) and request body size limits.

#### Parameters

**`$TestOrigins`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| TestOrigins | SwitchParameter | If set, evaluates allowed client origins for the request. | $false |

**`$TestContentLength`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| TestContentLength | SwitchParameter | If set, enforces configured request body size limits. | $false |

#### Outputs

System.Int32 — structured return code from `Write-FunctionReturnValue` indicating
permission granted, denied, origin blocked or content length exceeded.

#### Examples

```powershell
PS> Test-RestApiAccessControl -TestOrigins
```

#### Notes

This function uses the protected `AccessControl` configuration stored in
the global runtime variable and the current RestApi context.

*Source: [src/Core/RestApi/Private/Test-RestApiAccessControl.ps1](../../src/Core/RestApi/Private/Test-RestApiAccessControl.ps1)*

---

### Test-RestApiCommandExecutionField

*Private function*

**Synopsis:** Check whether a RestApi space exposes an ApiCommandExecution field.

#### Description

Validates that a provided space configuration contains an `ApiCommandExecution`
entry which indicates that an executable API command is configured for the
space. Returns boolean-like structured return codes via
`Write-FunctionReturnValue`.

#### Parameters

**`$Space`**

| Name | Type | Description | Default |
|------|------|-------------|---------|
| Space | PSCustomObject | Space configuration object to inspect. | |

#### Outputs

System.Boolean — `$true` when `ApiCommandExecution` is present, `$false` otherwise,
wrapped via `Write-FunctionReturnValue`.

#### Examples

```powershell
PS> Test-RestApiCommandExecutionField -Space $space
```

#### Notes

Used by routing logic to decide whether to invoke a command or render
sub-endpoints for a space.

*Source: [src/Core/RestApi/Private/Test-RestApiCommandExecutionField.ps1](../../src/Core/RestApi/Private/Test-RestApiCommandExecutionField.ps1)*



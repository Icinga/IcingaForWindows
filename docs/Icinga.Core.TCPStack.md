# Icinga.Core.TCPStack

*Auto-generated from `src/Core/TCPStack/`. Do not edit by hand -- run `build/Build-ModuleDocs.ps1` to regenerate.*

## Public functions

- [New-IcingaTlsCertConfig](#new-icingatlscertconfig)

## Private helpers

- [Close-TCPConnection](#close-tcpconnection)
- [Close-TCPSocket](#close-tcpsocket)
- [Get-TlsCertificate](#get-tlscertificate)
- [New-TlsCertConfig](#new-tlscertconfig)
- [Open-SSLStream](#open-sslstream)
- [Open-TCPSocket](#open-tcpsocket)
- [Send-TCPMessage](#send-tcpmessage)
- [Set-TCPClientAndStream](#set-tcpclientandstream)
- [Test-TCPConnection](#test-tcpconnection)
- [Update-TCPConnection](#update-tcpconnection)

---

### New-IcingaTlsCertConfig

*Public function*

**Synopsis:** Create an Icinga TLS certificate configuration object

#### Description

Returns a standardized TLS certificate configuration object by delegating to
`New-TlsCertConfig`. This wrapper supplies Icinga-specific defaults for the
certificate store and store location while allowing callers to specify a
certificate file, thumbprint, CN, issuer, or alternative store settings.

#### Parameters

**`$CertPath`**

| Name     | Type          | Description                                     | Default |
|----------|---------------|-------------------------------------------------|---------|
| CertPath | System.String | Path to a PKCS#12/PFX certificate file to load. |         |

**`$CertThumbprint`**

| Name           | Type          | Description                                                   | Default |
|----------------|---------------|---------------------------------------------------------------|---------|
| CertThumbprint | System.String | Thumbprint of a certificate to locate in a certificate store. |         |

**`$CertCN`**

| Name   | Type          | Description                                                  | Default |
|--------|---------------|--------------------------------------------------------------|---------|
| CertCN | System.String | Common Name (CN) to match when searching certificate stores. |         |

**`$CertStore`**

| Name      | Type          | Description                                     | Default |
|-----------|---------------|-------------------------------------------------|---------|
| CertStore | System.String | Certificate store name (for example: My, Root). | My      |

**`$CertStoreLocation`**

| Name              | Type          | Description                                                          | Default      |
|-------------------|---------------|----------------------------------------------------------------------|--------------|
| CertStoreLocation | System.String | Certificate store location (for example: LocalMachine, CurrentUser). | LocalMachine |

**`$CertIssuer`**

| Name       | Type         | Description                                                       | Default |
|------------|--------------|-------------------------------------------------------------------|---------|
| CertIssuer | System.Array | Array of issuer names to match when searching certificate stores. |         |

#### Outputs

System.Object -- TLS certificate configuration object for the TCP stack, returned from `New-TlsCertConfig`.

#### Examples

```powershell
PS> New-IcingaTlsCertConfig -CertPath 'C:\certs\icinga.pfx'
```

#### Notes

This function is a thin Icinga-specific wrapper around `New-TlsCertConfig`. Refer to
`New-TlsCertConfig` for full validation rules and additional options. At least one of
CertPath, CertThumbprint, CertCN or CertIssuer must be supplied.

*Source: [src/Core/TCPStack/Public/New-IcingaTlsCertConfig.ps1](../src/Core/TCPStack/Public/New-IcingaTlsCertConfig.ps1)*

---

### Close-TCPConnection

*Private function*

**Synopsis:** Close and dispose the active TCP client and SSL stream

#### Description

`Close-TCPConnection` safely closes and disposes the current TCP client and
associated SSL stream stored in the global runtime variable, if present.

#### Outputs

None -- Clears the SSL stream, TCP client and their references in the global state.

#### Examples

```powershell
PS> Close-TCPConnection
```

#### Notes

This is idempotent and swallows disposal exceptions.

*Source: [src/Core/TCPStack/Private/Close-TCPConnection.ps1](../src/Core/TCPStack/Private/Close-TCPConnection.ps1)*

---

### Close-TCPSocket

*Private function*

**Synopsis:** Stop and release the TCP listener socket

#### Description

`Close-TCPSocket` stops the active `TcpListener` (if any), logs the action
and clears the listener reference in the global runtime variable.

#### Outputs

None -- Stops the listener and clears its reference in the global state.

#### Examples

```powershell
PS> Close-TCPSocket
```

#### Notes

Requires privileges sufficient to stop the listener; exceptions are logged.

*Source: [src/Core/TCPStack/Private/Close-TCPSocket.ps1](../src/Core/TCPStack/Private/Close-TCPSocket.ps1)*

---

### Get-TlsCertificate

*Private function*

**Synopsis:** Load a TLS certificate from path or certificate store according to config.

#### Description

`Get-TlsCertificate` attempts to load a certificate based on the provided
TLS configuration object. It supports loading from a file path or by searching
the specified certificate store using thumbprint, common name or issuer filters.

#### Parameters

**`$TlsCertConfig`**

| Name          | Type                  | Description                                            | Default |
|---------------|-----------------------|--------------------------------------------------------|---------|
| TlsCertConfig | System.PSCustomObject | Configuration describing how to locate the certificate |         |

#### Outputs

System.Security.Cryptography.X509Certificates.X509Certificate2 -- The loaded certificate, or $null on failure.

#### Examples

```powershell
PS> Get-TlsCertificate -TlsCertConfig $cfg
```

#### Notes

Uses `Write-FunctionReturnValue` to report detailed result codes for callers.

*Source: [src/Core/TCPStack/Private/Get-TlsCertificate.ps1](../src/Core/TCPStack/Private/Get-TlsCertificate.ps1)*

---

### New-TlsCertConfig

*Private function*

**Synopsis:** Create a TLS certificate configuration object

#### Description

`New-TlsCertConfig` builds a PSCustomObject that describes how to locate a
TLS certificate, either by file path, thumbprint or search filters (CN/Issuer).
It validates that at least one selector is provided.

#### Parameters

**`$CertPath`**

| Name     | Type          | Description                                    | Default |
|----------|---------------|------------------------------------------------|---------|
| CertPath | System.String | Optional filesystem path to a certificate file | $null   |

**`$CertThumbprint`**

| Name           | Type          | Description                               | Default |
|----------------|---------------|-------------------------------------------|---------|
| CertThumbprint | System.String | Thumbprint to locate certificate in store | $null   |

**`$CertCN`**

| Name   | Type          | Description                                     | Default |
|--------|---------------|-------------------------------------------------|---------|
| CertCN | System.String | Common Name filter for certificate store search | $null   |

**`$CertStore`**

| Name      | Type          | Description                        | Default |
|-----------|---------------|------------------------------------|---------|
| CertStore | System.String | Certificate store name (e.g. 'My') | 'My'    |

**`$CertStoreLocation`**

| Name              | Type          | Description                          | Default        |
|-------------------|---------------|--------------------------------------|----------------|
| CertStoreLocation | System.String | Store location (e.g. 'LocalMachine') | 'LocalMachine' |

**`$CertIssuer`**

| Name       | Type         | Description                                                      | Default |
|------------|--------------|------------------------------------------------------------------|---------|
| CertIssuer | System.Array | Array of issuer names to match when searching certificate stores | $null   |

#### Outputs

System.Management.Automation.PSCustomObject -- Constructed TLS configuration object, returned via `Write-FunctionReturnValue`.

#### Examples

```powershell
PS> New-TlsCertConfig -CertThumbprint 'ABCDEF...'
```

#### Notes

At least one of `CertPath`, `CertThumbprint`, `CertCN` or `CertIssuer` must be provided.

*Source: [src/Core/TCPStack/Private/New-TlsCertConfig.ps1](../src/Core/TCPStack/Private/New-TlsCertConfig.ps1)*

---

### Open-SSLStream

*Private function*

**Synopsis:** Create and authenticate an SSL stream for the active TCP client.

#### Description

`Open-SSLStream` wraps the active TCP client's network stream in an
`SslStream`, configures timeouts, and performs client or server authentication
using the thread-local TLS certificate. On failure it closes the TCP connection.

#### Parameters

**`$Endpoint`**

| Name     | Type          | Description                                              | Default |
|----------|---------------|----------------------------------------------------------|---------|
| Endpoint | System.String | Expected remote endpoint name (required for client auth) | $null   |

**`$IsClient`**

| Name     | Type                   | Description                                 | Default |
|----------|------------------------|---------------------------------------------|---------|
| IsClient | System.SwitchParameter | When set perform client-side authentication | $false  |

#### Outputs

None -- Stores the opened SslStream in the global state; result codes are reported via `Write-FunctionReturnValue`.

#### Examples

```powershell
PS> Open-SSLStream -Endpoint 'example.com' -IsClient
```

#### Notes

Requires a valid certificate in `(Get-GlobalRuntimeVariable).Private.TCP.Certificate`.

*Source: [src/Core/TCPStack/Private/Open-SSLStream.ps1](../src/Core/TCPStack/Private/Open-SSLStream.ps1)*

---

### Open-TCPSocket

*Private function*

**Synopsis:** Create and (optionally) start a TCP listener socket

#### Description

`Open-TCPSocket` creates a `TcpListener` bound to the provided address and
port, stores it in the global runtime variable and optionally starts listening.
An optional TLS certificate can be associated for incoming connections.

#### Parameters

**`$Address`**

| Name    | Type          | Description                              | Default |
|---------|---------------|------------------------------------------|---------|
| Address | System.String | IP address to bind or empty for loopback | ''      |

**`$Port`**

| Name | Type         | Description      | Default |
|------|--------------|------------------|---------|
| Port | System.Int32 | TCP port to bind | 0       |

**`$Start`**

| Name  | Type                   | Description                              | Default |
|-------|------------------------|------------------------------------------|---------|
| Start | System.SwitchParameter | When set, immediately start the listener | $false  |

**`$TlsCertificate`**

| Name           | Type                                                           | Description                           | Default |
|----------------|----------------------------------------------------------------|---------------------------------------|---------|
| TlsCertificate | System.Security.Cryptography.X509Certificates.X509Certificate2 | Optional server certificate to attach | $null   |

#### Outputs

None. Stores listener and certificate in global runtime state.

#### Examples

```powershell
PS> Open-TCPSocket -Port 8080 -Start
```

#### Notes

Use `Close-TCPSocket` to stop and clear the listener.

*Source: [src/Core/TCPStack/Private/Open-TCPSocket.ps1](../src/Core/TCPStack/Private/Open-TCPSocket.ps1)*

---

### Send-TCPMessage

*Private function*

**Synopsis:** Write a prepared message buffer to the active TCP/SSL stream

#### Description

`Send-TCPMessage` takes a message object containing the buffer and length
and writes it to the active SSL stream of the current TCP client. It logs
an error if no valid stream is available.

#### Parameters

**`$MsgObj`**

| Name   | Type          | Description                                            | Default |
|--------|---------------|--------------------------------------------------------|---------|
| MsgObj | System.Object | Object with `message` (buffer) and `length` properties | $null   |

#### Outputs

None -- Writes the message buffer to the SSL stream and flushes it; logs an error if no valid stream is available.

#### Examples

```powershell
PS> Send-TCPMessage -MsgObj $msg
```

#### Notes

This helper assumes the active stream is an `SslStream` exposing `Write` and `Flush`.

*Source: [src/Core/TCPStack/Private/Send-TCPMessage.ps1](../src/Core/TCPStack/Private/Send-TCPMessage.ps1)*

---

### Set-TCPClientAndStream

*Private function*

**Synopsis:** Set the global TCP client and SSL stream references

#### Description

`Set-TCPClientAndStream` assigns the provided `TcpClient` and `SslStream`
instances into the runtime private TCP container so other helpers can access them.

#### Parameters

**`$TcpClient`**

| Name      | Type                         | Description                       | Default |
|-----------|------------------------------|-----------------------------------|---------|
| TcpClient | System.Net.Sockets.TcpClient | The connected TCP client instance | $null   |

**`$SslStream`**

| Name      | Type                          | Description                                         | Default |
|-----------|-------------------------------|-----------------------------------------------------|---------|
| SslStream | System.Net.Security.SslStream | The SSL stream wrapping the client's network stream | $null   |

#### Outputs

None -- Updates the `TcpClient` and `SslStream` references in `(Get-GlobalRuntimeVariable).Private.TCP`.

#### Examples

```powershell
PS> Set-TCPClientAndStream -TcpClient $c -SslStream $s
```

#### Notes

This is a trivial assignment helper used after connection establishment.

*Source: [src/Core/TCPStack/Private/Set-TCPClientAndStream.ps1](../src/Core/TCPStack/Private/Set-TCPClientAndStream.ps1)*

---

### Test-TCPConnection

*Private function*

**Synopsis:** Check whether the current TCP client and stream are connected.

#### Description

`Test-TCPConnection` validates that both the TCP client and its associated
stream are present and returns the client's `Connected` state.

#### Outputs

System.Boolean -- $true when connected and a valid client and stream are present; $false otherwise.

#### Examples

```powershell
PS> Test-TCPConnection
```

#### Notes

Used by thread health checks and higher-level network monitors.

*Source: [src/Core/TCPStack/Private/Test-TCPConnection.ps1](../src/Core/TCPStack/Private/Test-TCPConnection.ps1)*

---

### Update-TCPConnection

*Private function*

**Synopsis:** Register a new TcpClient and open its SSL stream.

#### Description

`Update-TCPConnection` sets the provided `TcpClient` into the runtime private
TCP container and calls `Open-SSLStream` to wrap and authenticate the connection
as client or server depending on the `IsClient` flag.

#### Parameters

**`$Client`**

| Name   | Type                         | Description                               | Default |
|--------|------------------------------|-------------------------------------------|---------|
| Client | System.Net.Sockets.TcpClient | Connected TCP client instance to register | $null   |

**`$Endpoint`**

| Name     | Type          | Description                                     | Default |
|----------|---------------|-------------------------------------------------|---------|
| Endpoint | System.String | Remote endpoint name (used for client SSL auth) | $null   |

**`$IsClient`**

| Name     | Type                   | Description                                     | Default |
|----------|------------------------|-------------------------------------------------|---------|
| IsClient | System.SwitchParameter | When set perform client-side SSL authentication | $false  |

#### Outputs

None -- Result codes from `Open-SSLStream` are forwarded via `Write-FunctionReturnValue`.

#### Examples

```powershell
PS> Update-TCPConnection -Client $c -Endpoint 'example.com' -IsClient
```

#### Notes

Validates `$Client` and returns `UpdateTcpClientInvalid` when missing.

*Source: [src/Core/TCPStack/Private/Update-TCPConnection.ps1](../src/Core/TCPStack/Private/Update-TCPConnection.ps1)*


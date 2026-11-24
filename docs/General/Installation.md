# Icinga for Windows -- Step-by-Step Installation Guide

This guide walks through installing and configuring **Icinga for Windows** (`v27.0.0`) on a Windows Server or Windows client host, trusting the Icinga 2 Certificate Authority (CA), configuring cluster endpoints and TLS certificates, completing certificate signing, and starting the background agent runtime.

---

## 1. Prerequisites, Privileges & Module Import

### Supported Runtimes
* **Production Target:** Windows PowerShell 5.1 or PowerShell 7.5+ on Windows Server / Windows 11.
* **Development & CI Fallback:** Linux and macOS (when `$env:ProgramData` is unset, `IcingaForWindows.psm1` sets `$env:ProgramData` to `$HOME/ProgramData`, resolving the module data root to `$HOME/ProgramData/IcingaForWindows`).

### Administrative Privileges & User Account Context on Windows
1. **Run Initial Setup as Administrator:** Open an **elevated PowerShell session** (*Run as Administrator*) for host provisioning so `Register-LoggingWindowsEventLog` can create the `IcingaForWindows::<Area>` Windows Event Log sources and `100 MiB` log limit, and `Import-IcingaCertAuthority` can import the Icinga 2 CA certificate into `Cert:\LocalMachine\Root`.
2. **Consistent User Context (`Cert:\CurrentUser\My`):** On Windows, `New-IcingaProtocolCertificate` stores the node TLS certificate and private key inside `Cert:\CurrentUser\My` (`StoreLocation::CurrentUser`) rather than writing a `.pfx` file to disk. Always run `Install-IcingaForWindows` and `Use-IcingaForWindows` under the **same Windows user account** so the runtime locates the private key in `Cert:\CurrentUser\My`.

### One-Time Module Import per Session
`IcingaForWindows.psd1` keeps `FunctionsToExport = '*'` while `IcingaForWindows.psm1` dot-sources the compiled `lib/IcingaForWindows.Classes.ps1` and `lib/IcingaForWindows.Kernel.ps1` artifacts dynamically at import time. Import the module once per PowerShell session (or inside `$PROFILE`) before invoking cmdlets:

```powershell
Import-Module IcingaForWindows -Force -Global;
```

Once imported, all exported public cmdlets (`Install-IcingaForWindows`, `Import-IcingaCertAuthority`, `New-IcingaProtocolEnvironment`, `New-IcingaProtocolEndpoint`, `New-IcingaTlsCertConfig`, `New-IcingaProtocolCertificate`, `Use-IcingaForWindows`, `Invoke-IcingaCheck*`, ...) remain available for the lifetime of the session and inside every background worker runspace.

### Runtime Directory Layout (`$env:ProgramData\IcingaForWindows`)

| Path | Helper Function | Purpose |
| ---- | --------------- | ------- |
| `C:\ProgramData\IcingaForWindows\Binaries` | `Get-ModuleBinaryDirectory` | Approved directory for external `.exe`, `.cmd`, `.bat`, and `.ps1` check plugins (`IWKB001003`) |
| `C:\ProgramData\IcingaForWindows\Config` | `Get-ModuleConfigDirectory` | Persistent JSON configuration (`IcingaProtocol\Connection.json`, `RestApi\`, `AccessControl\`, `WebSocket\`) |
| `C:\ProgramData\IcingaForWindows\Cache` | `Get-ModuleCacheDirectory` | Runtime caches such as `PerformanceCounter.json` |
| `C:\ProgramData\IcingaForWindows\Certificates` | `Get-ModuleCertificateDirectory` | Local `ca.crt` and passwordless `<CommonName>.pfx` storage on Linux and macOS |

---

## 2. Node Identity, Icinga 2 Object Names & Runtime Placeholders

Before generating certificates or writing `Connection.json`, determine the **exact Object Name** configured for this host in Icinga 2 or Icinga Director (`object Endpoint "..."` and `object Host "..."`):

* During the TLS handshake and JSON-RPC session, Icinga 2 validates that the peer certificate Common Name (`CN`) and reported check source match the configured **Object Name** (case-sensitively).
* If Icinga 2 uses the host's **FQDN** (for example `win-srv01.example.com`), both the certificate `CN` and `-Hostname` must resolve to that FQDN.
* If Icinga 2 uses the **short hostname** (for example `win-srv01`), both the certificate `CN` and `-Hostname` must resolve to that short hostname.

### Concrete Names vs. Runtime Placeholders (`'$fqdn'` and `'$hostname'`)

* **`Install-IcingaForWindows -Hostname` / `New-IcingaProtocolCertificate -CommonName`:** Generates the X.509 certificate immediately (`Subject = CN=<Value>`). Always pass the **concrete node name** (such as `'win-srv01.example.com'`, `([System.Net.Dns]::GetHostEntry('').HostName)`, or `([System.Net.Dns]::GetHostName())`) -- **never** pass literal `'$fqdn'` or `'$hostname'` to certificate creation.
* **`New-IcingaProtocolEnvironment` & `New-IcingaTlsCertConfig`:** Writes settings into `Config\IcingaProtocol\Connection.json`. Whenever `Read-IcingaProtocolConnection` loads `Connection.json`, it performs case-sensitive string substitution on the raw JSON text before parsing:

| Value in `Connection.json` | Quoting Rule in PowerShell | Runtime Resolution (`Read-IcingaProtocolConnection`) | When to Use |
| -------------------------- | -------------------------- | ---------------------------------------------------- | ----------- |
| `'$fqdn'` | **Single quotes**, lowercase (`'$fqdn'`) | `[System.Net.Dns]::GetHostEntry('').HostName` | Icinga 2 `Endpoint` / `Host` Object Name is the host's **FQDN** (recommended for domain hosts) |
| `'$hostname'` | **Single quotes**, lowercase (`'$hostname'`) | `[System.Net.Dns]::GetHostName()` | Icinga 2 `Endpoint` / `Host` Object Name is the **short hostname** |
| `'win-srv01.example.com'` | Single or double quotes | Used verbatim without DNS lookup | Custom Icinga 2 Object Name that differs from OS DNS/NetBIOS names |

> **Important:** Always wrap `'$fqdn'` and `'$hostname'` in **single quotes** and keep them **lowercase**. Using double quotes (`"$fqdn"`, `"$hostname"`) causes PowerShell to expand undefined shell variables to an empty string `""` *before* calling `New-IcingaProtocolEnvironment`, resulting in `50017` (`IcingaHostnameNotDefined`) or an empty `CertCN`.

---

## 3. Step 1 -- Base Host Installation (`Install-IcingaForWindows`)

Run `Install-IcingaForWindows` in an elevated PowerShell session, passing the concrete Icinga 2 Object Name for this host:

```powershell
Import-Module IcingaForWindows -Force -Global;

# Option A: Icinga 2 Object Name is an explicit FQDN (or [System.Net.Dns]::GetHostEntry('').HostName)
Install-IcingaForWindows -Hostname 'win-srv01.example.com';

# Option B: Icinga 2 Object Name is the local short hostname
# Install-IcingaForWindows -Hostname ([System.Net.Dns]::GetHostName());
```

### What `Install-IcingaForWindows` Provisions
1. **Non-Interactive Parameter Validation:** Checks `-Hostname` without `[Parameter(Mandatory = $true)]` so unattended automation never hangs on an interactive prompt (returns `7000` if null, empty, or whitespace) and trims surrounding whitespace.
2. **Return-Code Registry Initialization:** Calls `Set-InternalExitCodes` so `(Get-GlobalRuntimeVariable).Public.ReturnCodes` is populated before directory and Event Log setup.
3. **Base Directories:** Calls `New-ModuleConfigEnvironment` to ensure `ProgramData\IcingaForWindows\Binaries` and `ProgramData\IcingaForWindows\Config` exist.
4. **Windows Event Log Registration:** Calls `Register-LoggingWindowsEventLog` on Windows to register every unique `IcingaForWindows::<Area>` source (including `IcingaForWindows::Logging` and `IcingaForWindows::Installer`) under the `IcingaForWindows` Event Log via `[System.Diagnostics.EventLog]` and configures the maximum log size to `100 MiB` (`104857600` bytes).
5. **Initial Self-Signed TLS Certificate:** Calls `New-IcingaProtocolCertificate -CommonName $Hostname` to generate a 4096-bit RSA SHA-256 self-signed certificate valid for 3 months, storing it in `Cert:\CurrentUser\My` on Windows (`50011`) or `$env:ProgramData\IcingaForWindows\Certificates\<Hostname>.pfx` on Linux/macOS (`50010`).

### Installer & Certificate Return Codes

| Code | Semantic Key | Severity | Description |
| ---- | ------------ | -------- | ----------- |
| `7001` | `InstallerCompleted` | `Info` | Base directories, Windows Event Log sources, and node TLS certificate provisioned successfully |
| `7000` | `InstallerHostnameMissing` | `Error` | `-Hostname` was omitted, empty, or whitespace; installation aborted cleanly |
| `50011` | `IcingaCertStoredCertStore` | `Info` | Certificate stored in `Cert:\CurrentUser\My` on Windows (`New-IcingaProtocolCertificate`) |
| `50010` | `IcingaCertStoredLocally` | `Info` | Certificate written as passwordless `.pfx` on Linux/macOS (`New-IcingaProtocolCertificate`) |
| `50009` | `IcingaCertCommonNameMissing` | `Error` | `-CommonName` passed to `New-IcingaProtocolCertificate` was null, empty, or whitespace |
| `50012` | `IcingaCertMissingForMerge` | `Error` | Existing certificate/private key was not found when merging `-SignedCert` |

---

## 4. Step 2 -- Import the Icinga 2 CA Certificate (`Import-IcingaCertAuthority`)

To verify parent/master server certificates during TLS handshakes, import your Icinga 2 CA certificate (`ca.crt` from `/var/lib/icinga2/certs/ca.crt` on the Icinga 2 CA master) from an **elevated Administrator** session:

```powershell
# Option A: Import from a local file path
Import-IcingaCertAuthority -Path 'C:\Temp\ca.crt';

# Option B: Download and import from an internal HTTPS endpoint
# Import-IcingaCertAuthority -Path 'https://icinga-master01.example.com/ca.crt';

# Option C: Import from an inline PEM string
# Import-IcingaCertAuthority -Certificate '-----BEGIN CERTIFICATE-----...';
```

* **On Windows:** Imports the CA certificate into `Cert:\LocalMachine\Root` (`StoreName::Root`, `StoreLocation::LocalMachine`), automatically skipping import if a certificate with the same thumbprint is already present.
* **On Linux/macOS:** Writes the PEM certificate to `$env:ProgramData\IcingaForWindows\Certificates\ca.crt`.
* **Return Values:** Returns nothing (`$null`) on success, `50013` (`IcingaCAImportPathNotfound`) if a local `-Path` does not exist, or `50014` (`IcingaCAContentIsEmpty`) if the certificate payload is empty or whitespace.

---

## 5. Step 3 -- Configure Icinga 2 Cluster Endpoints & TLS (`New-IcingaProtocolEnvironment`)

Configure the parent Icinga 2 endpoints, parent zone, local node identity, and TLS certificate lookup filter via `New-IcingaProtocolEnvironment`.

> **Warning -- `-DryRun` Does NOT Save Configuration:**
> Passing `-DryRun` runs `Compare-IcingaTextContent` against any existing `Config\IcingaProtocol\Connection.json` and returns a hashtable `@{ ExitCode = <0|1>; Output = <UnifiedDiffString> }` **without creating directories or writing files to disk**.
> After inspecting `(... -DryRun).Output`, you **must execute `New-IcingaProtocolEnvironment` a second time without `-DryRun` and without `.Output`** to actually write `Connection.json` (which returns numeric code `50019`).

### Example A: FQDN Node Identity (`'$fqdn'`)

Use this configuration when your Icinga 2 `Endpoint` and `Host` Object Name is the Windows host's FQDN (matching `Install-IcingaForWindows -Hostname 'win-srv01.example.com'`):

```powershell
# Step 3a (Optional Preview): Inspect unified diff against Connection.json (-DryRun does NOT write to disk)
(
    New-IcingaProtocolEnvironment `
        -Endpoints @(
            (New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665),
            (New-IcingaProtocolEndpoint -Name 'icinga-master02.example.com' -Address 'icinga-master02.example.com' -Port 5665)
        ) `
        -Zone 'master' `
        -Hostname '$fqdn' `
        -TlsCertConfig (
            New-IcingaTlsCertConfig `
                -CertCN '$fqdn' `
                -CertStore 'My' `
                -CertStoreLocation 'CurrentUser' `
                -CertIssuer @( 'Icinga CA', '$fqdn' )
        ) `
        -DryRun
).Output;

# Step 3b (Save Configuration): Run WITHOUT -DryRun and WITHOUT .Output to write Connection.json (returns 50019)
New-IcingaProtocolEnvironment `
    -Endpoints @(
        (New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665),
        (New-IcingaProtocolEndpoint -Name 'icinga-master02.example.com' -Address 'icinga-master02.example.com' -Port 5665)
    ) `
    -Zone 'master' `
    -Hostname '$fqdn' `
    -TlsCertConfig (
        New-IcingaTlsCertConfig `
            -CertCN '$fqdn' `
            -CertStore 'My' `
            -CertStoreLocation 'CurrentUser' `
            -CertIssuer @( 'Icinga CA', '$fqdn' )
    );
```

### Example B: Short-Hostname Node Identity (`'$hostname'`)

Use this configuration when your Icinga 2 `Endpoint` and `Host` Object Name is the short hostname (matching `Install-IcingaForWindows -Hostname ([System.Net.Dns]::GetHostName())`):

```powershell
# Step 3a (Optional Preview): Inspect unified diff against Connection.json (-DryRun does NOT write to disk)
(
    New-IcingaProtocolEnvironment `
        -Endpoints @(
            (New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665),
            (New-IcingaProtocolEndpoint -Name 'icinga-master02.example.com' -Address 'icinga-master02.example.com' -Port 5665)
        ) `
        -Zone 'master' `
        -Hostname '$hostname' `
        -TlsCertConfig (
            New-IcingaTlsCertConfig `
                -CertCN '$hostname' `
                -CertStore 'My' `
                -CertStoreLocation 'CurrentUser' `
                -CertIssuer @( 'Icinga CA', '$hostname' )
        ) `
        -DryRun
).Output;

# Step 3b (Save Configuration): Run WITHOUT -DryRun and WITHOUT .Output to write Connection.json (returns 50019)
New-IcingaProtocolEnvironment `
    -Endpoints @(
        (New-IcingaProtocolEndpoint -Name 'icinga-master01.example.com' -Address 'icinga-master01.example.com' -Port 5665),
        (New-IcingaProtocolEndpoint -Name 'icinga-master02.example.com' -Address 'icinga-master02.example.com' -Port 5665)
    ) `
    -Zone 'master' `
    -Hostname '$hostname' `
    -TlsCertConfig (
        New-IcingaTlsCertConfig `
            -CertCN '$hostname' `
            -CertStore 'My' `
            -CertStoreLocation 'CurrentUser' `
            -CertIssuer @( 'Icinga CA', '$hostname' )
    );
```

### Key Configuration Details
* **Certificate Store Location (`-CertStore 'My' -CertStoreLocation 'CurrentUser'`):** `New-IcingaTlsCertConfig` defaults `-CertStoreLocation` to `'LocalMachine'`. Because `Install-IcingaForWindows` (`New-IcingaProtocolCertificate`) stores the node certificate in `Cert:\CurrentUser\My`, explicitly specify `-CertStore 'My' -CertStoreLocation 'CurrentUser'` on Windows.
* **Seamless Bootstrap & Signed Certificate Matching (`-CertIssuer`):** Before CA signing, the self-signed certificate has `Issuer = CN=<NodeName>`; after signing, the certificate has `Issuer = CN=Icinga CA` (adjust `'Icinga CA'` if your Icinga 2 CA uses a custom Common Name). Listing both `@( 'Icinga CA', '$fqdn' )` (or `'$hostname'`) allows `Get-TlsCertificate` to load the certificate before and after signing without modifying `Connection.json`.
* **Endpoint Name Verification:** For outbound connections (`Start-IcingaProtocolConnector`), `-Name` on `New-IcingaProtocolEndpoint` is passed to `SslStream.AuthenticateAsClient` and must match the Common Name (`CN`) or Subject Alternative Name (`SAN`) of the remote Icinga 2 parent/master certificate, while `-Address` can be an IP address or DNS name.
* **Connection Modes (Outbound & Inbound):** When `Start-IcingaAgent` (`New-IcingaAgentEnvironment`) starts, `Start-IcingaProtocolConnector` actively connects to all configured `Endpoints` every 5 seconds while `Start-IcingaProtocolListener` simultaneously listens on `0.0.0.0:5665` by default (customizable via optional `ListenAddress` and `ListenPort` fields in `Connection.json`) for parent-initiated connections (ensure Windows Firewall permits inbound TCP `5665` when parents initiate connections).

### Protocol Configuration Return Codes

| Code | Semantic Key | Severity | Description |
| ---- | ------------ | -------- | ----------- |
| `50019` | `IcingaProtoclConfigWritten` | `Info` | `Config\IcingaProtocol\Connection.json` was written to disk successfully |
| `50015` | `IcingaEndpointsEmpty` | `Error` | `-Endpoints` was null or empty |
| `50016` | `IcingaZoneNameNotDefined` | `Error` | `-Zone` was null or empty |
| `50017` | `IcingaHostnameNotDefined` | `Error` | `-Hostname` was null or empty (for example if unquoted `"$fqdn"` expanded to `""`) |
| `50018` | `IcingaTlsCertConfigMissing` | `Error` | `-TlsCertConfig` was `$null` |
| `1900` | `NoTlsCertConfigProvided` | `Warning` | `New-IcingaTlsCertConfig` received neither `CertPath`, `CertThumbprint`, `CertCN`, nor `CertIssuer` |

---

## 6. Step 4 -- Certificate Signing Workflow

### Option A: On-Demand Signing over the Icinga 2 Cluster Protocol (`pki::UpdateCertificate`)
1. Start the **Icinga for Windows** runtime (`Step 5` below). Upon connecting with its initial self-signed certificate, `Start-IcingaProtocolSocketReader` automatically sends `icinga::Hello` and `pki::RequestCertificate` to the connected Icinga 2 parent/master node.
2. On the **Icinga 2 CA master**, inspect pending certificate signing requests and sign the matching fingerprint:
   ```bash
   icinga2 ca list
   icinga2 ca sign <request-fingerprint>
   ```
3. Icinga 2 sends `pki::UpdateCertificate` back over the cluster connection. `Start-IcingaProtocolWorker` automatically calls `New-IcingaProtocolCertificate -CommonName $Hostname -SignedCert $SignedCert`, merges the signed PEM certificate with the existing 4096-bit RSA private key, replaces the self-signed certificate in `Cert:\CurrentUser\My`, and closes the transient socket so the connector reconnects immediately with the CA-signed certificate.

### Option B: Offline / Manual Certificate Merge (`New-IcingaProtocolCertificate -SignedCert`)
If you sign the certificate offline or distribute the signed `.crt` PEM file via configuration management, merge it directly with the existing private key in `Cert:\CurrentUser\My`:

```powershell
$SignedPem = Get-Content -Path 'C:\Temp\win-srv01.example.com.crt' -Raw;
New-IcingaProtocolCertificate -CommonName 'win-srv01.example.com' -SignedCert $SignedPem;
```

This replaces the self-signed certificate in `Cert:\CurrentUser\My` and returns `50011` (`50010` on Linux/macOS, or `50012` `IcingaCertMissingForMerge` if no matching private key exists for `-CommonName`).

---

## 7. Step 5 -- Start the Runtime & Verify Operation (`Use-IcingaForWindows`)

Start the **Icinga for Windows** runtime and background daemons either directly in the current PowerShell session (`-NoNewShell`) or inside a dedicated interactive `icinga> ` child shell via `Use-IcingaForWindows` (alias `ifw`, when `IcingaForWindows` is installed on `$env:PSModulePath`):

```powershell
# Option A: Initialize runtime and start all background daemons in the current session
Use-IcingaForWindows -NoNewShell -LogLevel 'Info' -RunBackgroundDaemons;

# Option B: Launch a dedicated interactive 'icinga> ' child shell with background daemons
# ifw -LogLevel 'Info' -RunBackgroundDaemons;
```

> **Note:** `-RunBackgroundDaemons` defaults to `$false` and `-LogLevel` defaults to `'Warning'` (running bare `ifw` opens an interactive `icinga> ` shell without starting background daemons). `Use-IcingaForWindows` is idempotent per process (`Protected.Initialized = $true`), so pass `-RunBackgroundDaemons` on the first call in a session. When stopping an interactive session with active background daemons, run `Exit-Icinga` so the PowerShell process exits immediately without waiting on background runspaces.

When `-RunBackgroundDaemons` is specified, `Use-IcingaForWindows` starts:
* `Start-LoggingDaemon` (console formatter and Windows Event Log writer)
* `Start-ModuleGarbageCollector` and `Start-ThreadHouseKeeper`
* `Start-IcingaPerformanceCounterDaemon`
* `Start-RestApiDaemon` and `Start-ModuleWebSocketDaemon`
* `Start-IcingaAgent` (`Start-IcingaProtocolWorker` pool, `Start-IcingaProtocolListener` on TCP `5665`, and `Start-IcingaProtocolConnector`)

### Verification Commands

```powershell
# 1. Verify the Windows Event Log configuration (100 MiB max size) and recent events
Get-WinEvent -ListLog 'IcingaForWindows';
Get-WinEvent -LogName 'IcingaForWindows' -MaxEvents 20 | Format-Table TimeCreated, Id, ProviderName, LevelDisplayName, Message -AutoSize;

# 2. Verify the node TLS certificate in Cert:\CurrentUser\My
Get-ChildItem -Path 'Cert:\CurrentUser\My' |
    Where-Object { $_.Subject -like '*CN=win-srv01.example.com*' } |
    Select-Object Subject, Issuer, Thumbprint, HasPrivateKey, NotAfter;

# 3. Execute built-in monitoring checks interactively
Invoke-IcingaCheckCPU -Warning '80' -Critical '95';
Invoke-IcingaCheckMemory -Warning '85%' -Critical '95%';
Invoke-IcingaCheckPartitionSpace -Warning '80%' -Critical '90%';
Invoke-IcingaCheckService;
```

---

## 8. Current Scope & Upcoming Capabilities

* **Standalone Setup Return Codes & Queued Logging:** Prior to starting `Start-LoggingDaemon` (`Use-IcingaForWindows -RunBackgroundDaemons`), standalone setup cmdlets such as `Install-IcingaForWindows` and `New-IcingaProtocolEnvironment` emit standardized numeric return codes (`7001`, `50019`, ...) to the pipeline and enqueue structured log entries into `$Global:IcingaForWindows.Public.Logging.Queue` (drained to the console and Windows Event Log when `Start-LoggingDaemon` is started in the same session with a matching `-LogLevel`). Direct console log rendering when `Start-LoggingDaemon` is inactive is planned on the [Roadmap](Roadmap.md).
* **Service Hosting & Single-Command Onboarding:** Native Windows service hosting, Windows Firewall rule automation, and ticket-driven single-command endpoint onboarding in `Install-IcingaForWindows` are tracked under `Priority 1` / `Priority 2` in the [Icinga for Windows Roadmap](Roadmap.md).

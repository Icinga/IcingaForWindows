$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force;
}

InModuleScope 'IcingaForWindows' {
    Describe 'Memory Leak Tests for Background Daemons' {
        Context 'RestApi Worker Memory Constraints' {
            It 'Should not leak OS handles after processing 20 requests' {
                if ($PSVersionTable.PSVersion.Major -lt 6) {
                    Write-Host 'Skipping RestApi live request test on PowerShell 5.1';
                    return;
                }

                # Setup
                $GlobalVariable = Get-GlobalRuntimeVariable;
                
                # 1. Create a dummy self-signed certificate for the RestApi
                # Use CurrentUser and KeySpec KeyExchange for SslStream compatibility in PS 5.1
                $Cert = New-SelfSignedCertificate -DnsName 'localhost', '127.0.0.1' -CertStoreLocation 'cert:\CurrentUser\My' -KeySpec KeyExchange -KeyExportPolicy Exportable -ErrorAction Stop;
                
                try {
                    # Configure the API to use this cert
                    $GlobalVariable.Public.RestApi.Certificate = $Cert;
                    $GlobalVariable.Public.RestApi.Config = @{
                        'ListenAddress' = '127.0.0.1';
                        'ListenPort'    = 56655;
                    };
                    
                    # Create the worker queue
                    $GlobalVariable.Public.RestApi.WorkerQueue = New-Object System.Collections.ArrayList;
                    $GlobalVariable.Public.RestApi.WorkerQueue.Add(
                        (New-Object System.Collections.Concurrent.BlockingCollection[System.Net.Sockets.TcpClient] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[System.Net.Sockets.TcpClient]))
                    ) | Out-Null;
                    
                    # Ensure spaces are initialized with a valid test endpoint
                    $Spaces = @{
                        'system' = [PSCustomObject]@{
                            'ApiCommandExecution' = [PSCustomObject]@{
                                'Method'     = @('GET');
                                'Parameters' = @{};
                                'Function'   = 'Get-IcingaUnixTime';
                            };
                        };
                    };
                    $GlobalVariable.Private.RestApi.Spaces = $Spaces;

                    # Start the Listener Thread
                    $ListenerThread = New-Thread -Command 'Start-RestApiListener' -KeepAlive -WaitForJobs -Start;
                    
                    # Start the Worker Thread (WorkerId 0)
                    $WorkerThread = New-Thread -Command 'Start-RestApiWorker' -Parameters @{ 'WorkerId' = 0; 'Spaces' = $Spaces; } -KeepAlive -WaitForJobs -Start;
                    
                    # Allow threads to initialize
                    Start-Sleep -Seconds 2;
                    
                    # Measure Handles BEFORE load
                    [System.GC]::Collect();
                    Start-Sleep -Seconds 1;
                    $HandlesBefore = (Get-Process -Id $PID).HandleCount;
                    
                    # Configure ServicePointManager for PS 5.1 (TLS 1.2, ConnectionLimit, Bypass cert/CRL check)
                    $PrevCertCallback           = [System.Net.ServicePointManager]::ServerCertificateValidationCallback;
                    $PrevSecurityProtocol       = [System.Net.ServicePointManager]::SecurityProtocol;
                    $PrevDefaultConnectionLimit = [System.Net.ServicePointManager]::DefaultConnectionLimit;
                    $PrevCheckCrl               = [System.Net.ServicePointManager]::CheckCertificateRevocationList;

                    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true };
                    [System.Net.ServicePointManager]::SecurityProtocol                     = [System.Net.SecurityProtocolType]::Tls12;
                    [System.Net.ServicePointManager]::DefaultConnectionLimit               = 100;
                    [System.Net.ServicePointManager]::CheckCertificateRevocationList       = $false;
                    [System.Net.ServicePointManager]::FindServicePoint([System.Uri]'https://127.0.0.1:56655').ConnectionLimit = 100;
                    
                    [int]$SuccessfulRequests = 0;

                    # Simulate 20 requests (enough to trigger leaks, but fast to run)
                    for ($i = 0; $i -lt 20; $i++) {
                        try {
                            $Response = if ($PSVersionTable.PSVersion.Major -ge 6) {
                                Invoke-RestMethod -Uri 'https://127.0.0.1:56655/v1/system' -Method 'Get' -TimeoutSec 10 -SkipCertificateCheck -ErrorAction Stop;
                            } else {
                                Invoke-RestMethod -Uri 'https://127.0.0.1:56655/v1/system' -Method 'Get' -TimeoutSec 10 -ErrorAction Stop;
                            };

                            if ($null -ne $Response) {
                                $SuccessfulRequests += 1;
                            }
                        } catch {
                            Write-Error ([string]::Format('RestApi request #{0} failed: {1}', $i, $_.Exception.Message));
                            throw $_;
                        }
                    }
                    
                    # Restore ServicePointManager settings
                    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $PrevCertCallback;
                    [System.Net.ServicePointManager]::SecurityProtocol                    = $PrevSecurityProtocol;
                    [System.Net.ServicePointManager]::DefaultConnectionLimit              = $PrevDefaultConnectionLimit;
                    [System.Net.ServicePointManager]::CheckCertificateRevocationList      = $PrevCheckCrl;
                    
                    # Allow worker to finish processing queued items
                    Start-Sleep -Seconds 2;
                    
                    # Measure Handles AFTER load
                    [System.GC]::Collect();
                    Start-Sleep -Seconds 1;
                    $HandlesAfter = (Get-Process -Id $PID).HandleCount;
                    
                    # Stop Threads
                    if ($null -ne $ListenerThread) {
                        Stop-Thread -ThreadId $ListenerThread.ThreadId;
                    }
                    if ($null -ne $WorkerThread) {
                        Stop-Thread -ThreadId $WorkerThread.ThreadId;
                    }
                    
                    Write-Host ([string]::Format('Handles Before: {0}, Handles After: {1}', $HandlesBefore, $HandlesAfter));
                    
                    # Assertions
                    ($SuccessfulRequests -eq 20) | Should Be $true;

                    # We allow a small tolerance (+100) for internal .NET threadpool/timer handles that may linger, 
                    # as well as Invoke-RestMethod connection pooling.
                    $IsSafe = $HandlesAfter -le ($HandlesBefore + 100);
                    $IsSafe | Should Be $true;
                    
                } finally {
                    # Cleanup certificate
                    Remove-Item -Path ([string]::Format('cert:\CurrentUser\My\{0}', $Cert.Thumbprint)) -Force -ErrorAction SilentlyContinue;
                }
            }
        }

        Context "IcingaProtocol Worker Memory Constraints" {
            It "Should not leak OS handles after processing Icinga Protocol check commands" {
                # Setup
                $GlobalVariable = Get-GlobalRuntimeVariable
                
                # 1. Create a dummy self-signed certificate for IcingaProtocol
                $Cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "cert:\CurrentUser\My" -ErrorAction Stop
                
                try {
                    $TlsCertConfig = [PSCustomObject]@{
                        CertStore         = 'My'
                        CertStoreLocation = 'CurrentUser'
                        CertThumbprint    = $Cert.Thumbprint
                        CertCN            = 'localhost'
                        CertIssuer        = @('localhost')
                    }
                    
                    # Configure IcingaProtocol runtime state
                    $GlobalVariable.Public.IcingaProtocol.Certificate = $Cert
                    $GlobalVariable.Public.IcingaProtocol.Config = [PSCustomObject]@{
                        ListenAddress = '127.0.0.1'
                        ListenPort    = 56656
                        WorkerCount   = 1
                        Hostname      = 'localhost'
                        TlsCertConfig = $TlsCertConfig
                    }
                    $GlobalVariable.Public.IcingaProtocol.Connections = @{}
                    $GlobalVariable.Public.IcingaProtocol.WriterQueue = [PSCustomObject]@{}
                    
                    # Initialize the worker queue
                    $GlobalVariable.Public.IcingaProtocol.WorkerQueue = New-Object System.Collections.ArrayList
                    $GlobalVariable.Public.IcingaProtocol.WorkerQueue.Add(
                        (New-Object System.Collections.Concurrent.BlockingCollection[PSObject] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[PSObject]))
                    ) | Out-Null
                    
                    # Start the Listener Thread
                    $ListenerThread = New-Thread -Command 'Start-IcingaProtocolListener' -Start
                    
                    # Start the Worker Thread (WorkerId 0)
                    $WorkerThread = New-Thread -Command 'Start-IcingaProtocolWorker' -Parameters @{ 'WorkerId' = 0 } -Start
                    
                    # Allow threads to initialize and initialize PerformanceCounters
                    Start-Sleep -Seconds 2
                    
                    # Measure Handles BEFORE load
                    [System.GC]::Collect()
                    Start-Sleep -Seconds 1
                    $HandlesBefore = (Get-Process -Id $PID).HandleCount
                    
                    # 1. Stress test via direct TCP / TLS socket connection with JSON-RPC frames
                    try {
                        $TcpClient = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 56656)
                        $SslStream = New-Object System.Net.Security.SslStream(
                            $TcpClient.GetStream(),
                            $false,
                            ([System.Net.Security.RemoteCertificateValidationCallback]{ $true })
                        )
                        $SslStream.AuthenticateAsClient('localhost')
                        
                        $JsonPayload = '{"jsonrpc":"2.0","method":"event::ExecuteCommand","params":{"host":"test-host","service":"cpu","command":"check_cpu","macros":{"ifw_api_command":"Invoke-IcingaCheckCPU"}}}'
                        $FramedMessage = "$($JsonPayload.Length):$JsonPayload"
                        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($FramedMessage)
                        
                        for ($i = 0; $i -lt 20; $i++) {
                            $SslStream.Write($Bytes, 0, $Bytes.Length)
                            $SslStream.Flush()
                        }
                        
                        Start-Sleep -Seconds 1
                        $SslStream.Dispose()
                        $TcpClient.Dispose()
                    } catch {
                        # Ignore connection errors during stress testing
                    }
                    
                    # 2. Stress test via direct Worker Queue check executions
                    $ExecuteMsg = [PSCustomObject]@{
                        'method' = 'event::ExecuteCommand'
                        'params' = [PSCustomObject]@{
                            'host'    = 'test-host'
                            'service' = 'cpu'
                            'command' = 'check_cpu'
                            'macros'  = [PSCustomObject]@{
                                'ifw_api_command' = 'Invoke-IcingaCheckCPU'
                            }
                        }
                    }
                    $HeartbeatMsg = [PSCustomObject]@{
                        'method' = 'event::Heartbeat'
                        'params' = [PSCustomObject]@{}
                    }
                    
                    for ($i = 0; $i -lt 30; $i++) {
                        $RPCObject = [PSCustomObject]@{
                            'Message' = if ($i % 5 -eq 0) { $HeartbeatMsg } else { $ExecuteMsg }
                            'Client'  = $null
                            'Stream'  = $null
                        }
                        $GlobalVariable.Public.IcingaProtocol.WorkerQueue[0].Add($RPCObject)
                    }
                    
                    # Wait for the worker queue to be drained
                    $Timeout = 10
                    while ($GlobalVariable.Public.IcingaProtocol.WorkerQueue[0].Count -gt 0 -and $Timeout -gt 0) {
                        Start-Sleep -Milliseconds 200
                        $Timeout -= 0.2
                    }
                    
                    Start-Sleep -Seconds 2
                    
                    # Measure Handles AFTER load
                    [System.GC]::Collect()
                    Start-Sleep -Seconds 1
                    $HandlesAfter = (Get-Process -Id $PID).HandleCount
                    
                    # Stop Threads
                    if ($null -ne $ListenerThread) {
                        Stop-Thread -ThreadId $ListenerThread.ThreadId
                    }
                    if ($null -ne $WorkerThread) {
                        Stop-Thread -ThreadId $WorkerThread.ThreadId
                    }
                    
                    Write-Host "IcingaProtocol Handles Before: $HandlesBefore, Handles After: $HandlesAfter"
                    
                    # Assertion
                    $IsSafe = $HandlesAfter -le ($HandlesBefore + 100)
                    $IsSafe | Should Be $true
                    
                } finally {
                    # Cleanup certificate
                    Remove-Item -Path "cert:\CurrentUser\My\$($Cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

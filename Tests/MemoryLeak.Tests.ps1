$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1'
if (-not (Get-Module -Name IcingaForWindows)) {
    Import-Module $ModulePath -Force
}

InModuleScope "IcingaForWindows" {
    Describe "Memory Leak Tests for Background Daemons" {
        Context "RestApi Worker Memory Constraints" {
            It "Should not leak OS handles after processing 20 requests" {
                # Setup
                $GlobalVariable = Get-GlobalRuntimeVariable
                
                # 1. Create a dummy self-signed certificate for the RestApi
                # Use CurrentUser to avoid requiring Admin privileges
                $Cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "cert:\CurrentUser\My" -ErrorAction Stop
                
                try {
                    # Configure the API to use this cert
                    $GlobalVariable.Public.RestApi.Certificate = $Cert
                    $GlobalVariable.Public.RestApi.Config = @{
                        ListenAddress = '127.0.0.1'
                        ListenPort = 56655
                    }
                    
                    # Create the worker queue
                    $GlobalVariable.Public.RestApi.WorkerQueue = New-Object System.Collections.ArrayList
                    $GlobalVariable.Public.RestApi.WorkerQueue.Add(
                        (New-Object System.Collections.Concurrent.BlockingCollection[System.Net.Sockets.TcpClient] -ArgumentList (New-Object System.Collections.Concurrent.ConcurrentQueue[System.Net.Sockets.TcpClient]))
                    ) | Out-Null
                    
                    # Ensure spaces are initialized for access control tests
                    $Spaces = @{
                        'v1' = @{
                            'Endpoints' = @{
                                'system' = @{
                                    'Access' = @('127.0.0.1')
                                }
                            }
                        }
                    }
                    $GlobalVariable.Private.RestApi.Spaces = $Spaces

                    # Start the Listener Thread
                    $ListenerThread = New-Thread -Command 'Start-RestApiListener' -Start
                    
                    # Start the Worker Thread (WorkerId 0)
                    $WorkerThread = New-Thread -Command 'Start-RestApiWorker' -Parameters @{ 'WorkerId' = 0; 'Spaces' = $Spaces } -Start
                    
                    # Allow threads to initialize
                    Start-Sleep -Seconds 2
                    
                    # Measure Handles BEFORE load
                    [System.GC]::Collect()
                    Start-Sleep -Seconds 1
                    $HandlesBefore = (Get-Process -Id $PID).HandleCount
                    
                    # Bypass certificate validation for PS 5.1
                    $PrevCertCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
                    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
                    
                    # Simulate 20 requests (enough to trigger leaks, but fast to run)
                    for ($i = 0; $i -lt 20; $i++) {
                        try {
                            if ($PSVersionTable.PSVersion.Major -ge 6) {
                                Invoke-RestMethod -Uri "https://127.0.0.1:56655/v1/system" -Method Get -SkipCertificateCheck -ErrorAction SilentlyContinue
                            } else {
                                Invoke-RestMethod -Uri "https://127.0.0.1:56655/v1/system" -Method Get -ErrorAction SilentlyContinue
                            }
                        } catch {
                            # Ignore errors; we just want to stress the TCP stack and RestApi parsing
                        }
                    }
                    
                    # Restore callback
                    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $PrevCertCallback
                    
                    # Allow worker to finish processing queued items
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
                    
                    Write-Host "Handles Before: $HandlesBefore, Handles After: $HandlesAfter"
                    
                    # Assertion
                    # We allow a small tolerance (+100) for internal .NET threadpool/timer handles that may linger, 
                    # as well as Invoke-RestMethod connection pooling.
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

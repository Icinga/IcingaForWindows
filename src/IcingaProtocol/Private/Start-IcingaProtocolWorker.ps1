<#
.SYNOPSIS
Start a protocol worker that processes enqueued Icinga 2 JSON-RPC messages

.DESCRIPTION
Start-IcingaProtocolWorker pulls RPC message objects from the BlockingCollection
at (Get-GlobalRuntimeVariable).Public.IcingaProtocol.WorkerQueue[$WorkerId] and
dispatches them by method name via a switch statement. Supported methods include
icinga::Hello, event::ExecuteCommand, event::Heartbeat, config::Update,
log::SetLogPosition and pki::UpdateCertificate. For event::ExecuteCommand, the
worker starts a monotonic execution timer immediately before resolving and
evaluating arguments via Invoke-IcingaProtocolCheckCommand, stops the timer
immediately after check execution completes, logs execution telemetry and
dispatches the resulting CheckResult via Send-IcingaProtocolCheckResult.

.PARAMETER WorkerId
| Name     | Type          | Description                                        | Default |
|----------|---------------|----------------------------------------------------|---------|
| WorkerId | System.Object | Zero-based index of the worker queue to pull from. | $null   |

.OUTPUTS
None -- Processes queued messages and sends replies; no pipeline output.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolWorker' -Parameters @{ 'WorkerId' = 0 } -KeepAlive -WaitForJobs -Start

.NOTES
WorkerId must be a valid index into the WorkerQueue ArrayList initialized by
New-IcingaAgentEnvironment. Accesses shared state via Get-GlobalRuntimeVariable
and nulls all per-iteration reference variables in finally to prevent daemon
memory retention.
#>
function Start-IcingaProtocolWorker()
{
    param (
        [object]$WorkerId = $null
    );

    if ($null -eq $WorkerId) {
        Write-LoggingEntry -Message 'Please specify a valid WorkerId to start the Icinga Protocol Worker' -Level 'Error';
        return;
    }

    $GlobalVariable = Get-GlobalRuntimeVariable;

    while (Test-ThreadRunning -NoSleep) {
        try {
            $RPCObject = $null;
            if (-not $GlobalVariable.Public.IcingaProtocol.WorkerQueue[$WorkerId].TryTake([ref]$RPCObject, 10000)) {
                Set-ThreadProcessing;
                continue;
            }

            if ($null -eq $RPCObject -or $null -eq $RPCObject.Message) {
                continue;
            }

            Set-ThreadProcessing;
            $RPCMessage = $RPCObject.Message;
            Set-TCPClientAndStream -TcpClient $RPCObject.Client -SslStream $RPCObject.Stream;

            $RawMethod  = Get-ModuleObjectValue -InputObject $RPCMessage -Name 'method';
            $MethodName = $null;
            if ($null -ne $RawMethod) {
                $MethodName = [string]$RawMethod;
            }
            $RPCParams = Get-ModuleObjectValue -InputObject $RPCMessage -Name 'params';

            switch ($MethodName) {
                'icinga::Hello' {
                    Write-LoggingEntry -Message '  [+] Received Hello method' -Level 'Debug';
                    break;
                };
                'event::ExecuteCommand' {
                    # 1. Start execution timer before command resolution & macro evaluation
                    [double]$CheckStarted   = [double](Get-IcingaUnixTime -Milliseconds);
                    $Stopwatch              = [System.Diagnostics.Stopwatch]::StartNew();

                    # 2. Evaluate macros/arguments and execute the PowerShell or binary check
                    $ExecutionResult        = Invoke-IcingaProtocolCheckCommand -Params $RPCParams;

                    # 3. Stop execution timer immediately after check completion
                    $Stopwatch.Stop();
                    [double]$ElapsedSeconds = $Stopwatch.Elapsed.TotalSeconds;
                    [double]$CheckFinished  = [System.Math]::Round(($CheckStarted + $ElapsedSeconds), 6);

                    # 4. Log telemetry and send CheckResult back to Icinga 2 (omitting 'service' on Host checks)
                    $HostName               = Get-ModuleObjectValue -InputObject $RPCParams -Name 'host';
                    $ServiceName            = Get-ModuleObjectValue -InputObject $RPCParams -Name 'service';

                    Write-LoggingEntry -Message 'Executed check command' -Level 'Debug' -Data @{
                        'Command'       = $ExecutionResult['CommandLine'];
                        'Host'          = $HostName;
                        'Service'       = $ServiceName;
                        'ExitCode'      = $ExecutionResult['ExitCode'];
                        'WorkerId'      = $WorkerId;
                        'CheckStarted'  = $CheckStarted;
                        'CheckFinished' = $CheckFinished;
                        'ExecutionTime' = $ElapsedSeconds;
                    };

                    [string]$CheckSource = [string]$GlobalVariable.Public.IcingaProtocol.Config.Hostname;
                    if ([string]::IsNullOrWhiteSpace($CheckSource) -and $null -ne $HostName) {
                        $CheckSource = [string]$HostName;
                    }

                    $CheckResultData = @{
                        'host' = $HostName;
                        'cr'   = @{
                            'check_source'     = $CheckSource;
                            'command'          = $ExecutionResult['CommandLine'];
                            'output'           = $ExecutionResult['Output'];
                            'exit_status'      = [int]$ExecutionResult['ExitCode'];
                            'active'           = $true;
                            'state'            = [int]$ExecutionResult['ExitCode'];
                            'type'             = 'CheckResult';
                            'execution_start'  = $CheckStarted;
                            'execution_end'    = $CheckFinished;
                            'performance_data' = @($ExecutionResult['PerformanceData']);
                        };
                    };

                    if (-not [string]::IsNullOrEmpty([string]$ServiceName)) {
                        $CheckResultData['service'] = $ServiceName;
                    }

                    Send-IcingaProtocolCheckResult -CheckResult $CheckResultData;
                    break;
                };
                'event::Heartbeat' {
                    Send-IcingaProtocolLogPosition;
                    Write-LoggingEntry -Message '  [+] Received Heartbeat event' -Level 'Debug';
                    break;
                };
                'config::Update' {
                    Write-LoggingEntry -Message '  [+] Received Config Update event' -Level 'Debug';
                    break;
                };
                'log::SetLogPosition' {
                    Write-LoggingEntry -Message '  [+] Received SetLogPosition event' -Level 'Debug' -Data @{ 'Message' = $RPCMessage; };
                    break;
                };
                'pki::UpdateCertificate' {
                    $SignedCert = Get-ModuleObjectValue -InputObject $RPCParams -Name 'cert';
                    New-IcingaProtocolCertificate -CommonName $GlobalVariable.Public.IcingaProtocol.Config.Hostname -SignedCert $SignedCert;
                    Close-TcpConnection;
                    Close-TcpSocket;
                    break;
                };
                default {
                    Write-LoggingEntry -Message '  [!] Received unhandled RPC method' -Level 'Error' -Data @{ 'Method' = $MethodName; };
                    break;
                };
            }
        } catch {
            Write-LoggingEntry -Message 'An error occurred in Icinga Protocol Worker' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; };
        } finally {
            $RPCObject                                        = $null;
            $RPCMessage                                       = $null;
            $RawMethod                                        = $null;
            $MethodName                                       = $null;
            $RPCParams                                        = $null;
            $Stopwatch                                        = $null;
            $ExecutionResult                                  = $null;
            $HostName                                         = $null;
            $ServiceName                                      = $null;
            $CheckSource                                      = $null;
            $CheckResultData                                  = $null;
            $SignedCert                                       = $null;
            $GlobalVariable.Private.Icinga.CheckResult        = $null;
            $GlobalVariable.Private.Icinga.ActiveCheckCommand = $null;
        }
    }
}

<#
.SYNOPSIS
Starts a protocol worker that processes enqueued RPC messages.

.DESCRIPTION
Start-IcingaProtocolWorker pulls RPC message objects from the BlockingCollection at
$Global:IcingaForWindows.Public.IcingaProtocol.WorkerQueue[$WorkerId] and dispatches
them by method name via a switch statement. Supported methods are icinga::Hello,
event::ExecuteCommand and event::Heartbeat. For each message, Set-ThreadProcessing
is called and Set-TCPClientAndStream is used to route replies to the correct connection.
The worker runs until Test-ThreadRunning returns false. Errors are caught per iteration
and logged without stopping the loop.

.PARAMETER WorkerId
| Name     | Type          | Description                                              | Default |
|----------|---------------|----------------------------------------------------------|---------|
| WorkerId | System.Object | Zero-based index of the worker queue to pull from.       | $null   |

.OUTPUTS
None — Processes queued messages and sends replies; no pipeline output.

.EXAMPLE
PS> New-Thread -Command 'Start-IcingaProtocolWorker' -Parameters @{ 'WorkerId' = 0 } -KeepAlive -WaitForJobs -Start

.NOTES
WorkerId must be a valid index into the WorkerQueue ArrayList initialized by
New-IcingaAgentEnvironment. The function logs an error and returns if WorkerId is null.
Thread safety relies on the BlockingCollection's Take() method.
#>
function Start-IcingaProtocolWorker()
{
    param (
        $WorkerId = $null
    );

    # Validate WorkerId
    if ($null -eq $WorkerId) {
        Write-LoggingEntry -Message 'Please specify a valid WorkerId to start the Icinga Protocol Worker' -Level 'Error';
        return;
    }

    # Start processing messages from the worker queue
    while (Test-ThreadRunning -NoSleep) {
        try {
            # Wait for a new RPC message to process
            $RPCObject    = $Global:IcingaForWindows.Public.IcingaProtocol.WorkerQueue[$WorkerId].Take();
            $CheckStarted = (Get-IcingaUnixTime -Milliseconds);

            if ($null -eq $RPCObject -or $null -eq $RPCObject.Message) {
                continue; # No message to process, loop again
            }

            # Ensure we set the thread processing context for proper logging and state management
            Set-ThreadProcessing;
            # $RPCMessage       = ConvertFrom-Json -InputObject $RPCMsg.Message.Replace('"macros":{"":"$",', '"macros":{');
            $RPCMessage = $RPCObject.Message;
            # Set our internal TCP client and stream to ensure we can send messages to the same connection
            Set-TCPClientAndStream -TcpClient $RPCObject.Client -SslStream $RPCObject.Stream;

            switch ($RPCMessage.method) {
                'icinga::Hello' {
                    Write-LoggingEntry -Message '  ✓ Received Hello method' -Level 'Debug';
                    #Write-Host "  → Sending: $testMessage" -ForegroundColor Yellow
                    #Send-IcingaApiMessage -Message (New-IcingaApiMessage -Method 'icinga::Hello') -Stream $sslStream;
                    #Write-Host "  ✓ Response sent" -ForegroundColor Green
                    break;
                };
                'event::ExecuteCommand' {
                    Write-LoggingEntry -Message '  ✓ Received ExecuteCommand event' -Level 'Debug' -Data @{ 'Command' = $RPCMessage.params.macros.ifw_api_command; };

                    [string]$ExecuteCommand = $RPCMessage.params.macros.ifw_api_command;

                    <#
                    # Read the command definition and arguments type, to ensure we properly handle SecureStrings
                    $CommandHelp    = Get-Help -Name $ExecuteCommand -Full;
                    $CommandDetails = @{ };

                    foreach ($parameter in $CommandHelp.parameters.parameter) {
                        $CommandDetails.Add($parameter.Name, $parameter.Type.Name);
                    }

                    # For executing the checks, we will require the data as
                    # hashtable, so declare it here
                    [hashtable]$Arguments = @{ };

                    # Now convert our custom object by Key<->Value to
                    # a valid hashtable, allowing us to parse arguments
                    # to our check command
                    $RPCMessage.params.macros.PSObject.Properties | ForEach-Object {
                        $CmdArgValue        = $_.Value;
                        [string]$CmdArgName = $_.Name;

                        if ($CmdArgName -eq 'ifw_api_command') {
                            return; # Skip the command name itself
                        }

                        # Ensure we can use both, `-MyArgument` and `MyArgument` as valid input
                        if ($CmdArgName[0] -eq '-') {
                            $CmdArgName = $CmdArgName.Substring(1, $CmdArgName.Length - 1);
                        }

                        $CmdArgName = $CmdArgName.Split('_')[-1];

                        # Ensure we convert strings to SecureString, in case the plugin argument requires it
                        if ($CommandDetails.ContainsKey($CmdArgName) -And $CommandDetails[$CmdArgName] -Like 'SecureString') {
                            $CmdArgValue = ConvertTo-IcingaSecureString -String $_.Value;
                        }

                        Add-IcingaHashtableItem `
                            -Hashtable $Arguments `
                            -Key $CmdArgName `
                            -Value $CmdArgValue | Out-Null;
                    }#>

                    #$ExitCode      = & $RPCMessage.params.macros.ifw_api_command @Arguments;
                    $CheckFinished = (Get-IcingaUnixTime -Milliseconds)
                    <#
                    $CheckResultData = @{
                        'host'    = $RPCMessage.params.host;
                        'service' = $RPCMessage.params.service;
                        'cr'      = @{
                            'output'           = (Get-IcingaInternalPluginOutput);
                            'exit_status'      = $ExitCode;
                            'active'           = $TRUE;
                            'state'            = $ExitCode;
                            'type'             = 'CheckResult';
                            'execution_start'  = $CheckStarted;
                            'execution_end'    = $CheckFinished;
                            'performance_data' = @((Get-IcingaCheckSchedulerPerfData).Split(' '));
                        }
                    };
                    #>

                    Write-LoggingEntry -Message 'Executing check command' -Level 'Debug' -Data @{
                        'Command'       = $ExecuteCommand;
                        'Host'          = $RPCMessage.params.host;
                        'Service'       = $RPCMessage.params.service;
                        'Arguments'     = $RPCMessage.params.macros.PSObject.Properties.Name -join ', ';
                        'WorkerId'      = $WorkerId;
                        'CheckStarted'  = $CheckStarted;
                        'CheckFinished' = $CheckFinished;
                        'ExecutionTime' = ($CheckFinished - $CheckStarted);
                    };

                    $CheckResultData = @{
                        'host'    = $RPCMessage.params.host;
                        'service' = $RPCMessage.params.service;
                        'cr'      = @{
                            'output'           = ([string]::Format('[OK] Everything is faked and healthy: {0}', (Get-Date -Format "yyyy-MM-dd HH:mm:ss:ffff")));
                            'exit_status'      = 0;
                            'active'           = $TRUE;
                            'state'            = 0;
                            'type'             = 'CheckResult';
                            'execution_start'  = $CheckStarted;
                            'execution_end'    = $CheckFinished;
                            'performance_data' = @();
                        }
                    };

                    Send-IcingaProtocolCheckResult -CheckResult $CheckResultData;
                    $CheckResultData = $null;
                    break;
                };
                'event::Heartbeat' {
                    Write-LoggingEntry -Message '  ✓ Received Heartbeat event' -Level 'Debug';
                    break;
                };
                'config::Update' {
                    Write-LoggingEntry -Message '  ✓ Received Config Update event' -Level 'Debug';
                    break;
                };
                default {
                    Write-LoggingEntry -Message '  ✓ Received unhandled RPC method' -Level 'Debug' -Data @{ 'Method' = $RPCMessage.method; };
                    break;
                };
            }
            $RPCMsg     = $null;
            $RPCMessage = $null;
        } catch {
            Write-LoggingEntry -Message 'An error occurred in Icinga Protocol Worker' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; };
        }
    }
}

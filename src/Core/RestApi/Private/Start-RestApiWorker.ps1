<#
.SYNOPSIS
Worker loop that processes assigned RestApi TCP clients.

.DESCRIPTION
Executes the worker loop for a single RestApi worker. The worker
waits for accepted `TcpClient` instances from its queue, performs TLS
handshake, access control checks, reads the request and dispatches it to
the appropriate handler.

.PARAMETER WorkerId
| Name | Type | Description | Default |
|------|------|-------------|---------|
| WorkerId | System.Int32 | Numeric identifier for this worker. | -1 |

.PARAMETER Spaces
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Spaces | System.Collections.Hashtable | Hashtable of RestApi space configurations. | @{ } |

.OUTPUTS
None — sends responses over the TCP connection and logs results.

.EXAMPLE
PS> Start-RestApiWorker -WorkerId 0 -Spaces $spaces

.NOTES
This function is designed to run as a long-lived thread and relies on
global runtime variables for TCP streams and timeouts.
#>
function Start-RestApiWorker()
{
    param (
        [int]$WorkerId     = -1,
        [hashtable]$Spaces = @{ }
    );

    $GlobalVariable                         = Get-GlobalRuntimeVariable;
    $GlobalVariable.Private.TCP.Certificate = $GlobalVariable.Public.RestApi.Certificate;
    $GlobalVariable.Private.RestApi.Spaces  = $Spaces;

    # Validate WorkerId
    if ($WorkerId -lt 0) {
        Write-LoggingEntry -Message 'Please specify a valid WorkerId to start the RestApi Worker' -Level 'Error';
        return;
    }

    # Start processing messages from the worker queue
    while (Test-ThreadRunning) {
        try {
            [System.Net.Sockets.TcpClient]$TcpClient = $GlobalVariable.Public.RestApi.WorkerQueue[$WorkerId].Take();
            Set-ThreadProcessing;

            if ((Update-TCPConnection -Client $TcpClient) -eq $GlobalVariable.Public.ReturnCodes.TlsHandshakeSuccessful.Code) {

                # This first test will check if the TcpClient's IP is allowed to access the API at all
                $AclTest = Test-RestApiAccessControl -TestOrigins;

                if ($AclTest -ne $GlobalVariable.Public.ReturnCodes.RestApiAccessControlPermissionGranted.Code -and $AclTest -ne $GlobalVariable.Public.ReturnCodes.RestApiAccessControlNotDefined.Code) {
                    Send-TCPMessage -MsgObj (New-RestApiResponse -StatusCode 403 -StatusMessage 'Forbidden' -ResponseBody @{ 'error' = 'You do not have access to this resource'} ) | Out-Null;
                    # Close the connection
                    Close-TCPConnection;

                    continue;
                }

                # Process the TCP connection by reading headers and body first
                [hashtable]$RawHttpHeader = Read-RestApiHeader;

                # This in general happens when the Api is accessed by a browser, which sends multiple connections
                # without actually sending any data. In this case we simply skip processing for this connection
                if ($null -eq $RawHttpHeader) {
                    # No data available, likely the client disconnected
                    Write-LoggingEntry -Message 'No data available on TCP connection, skipping processing' -Level 'Debug' -Data @{ 'WorkerId' = $WorkerId; 'Client' = $TcpClient };
                    Close-TCPConnection;
                    continue;
                }

                # Parse headers and read body
                [hashtable]$ParsedHttpHeader         = Expand-RestApiHeader -Header $RawHttpHeader.RawString;
                $GlobalVariable.Private.RestApi.Body = Read-RestApiBody -ParsedHeaders $ParsedHttpHeader -PreReadBodyBytes $RawHttpHeader.ExtraBodyBytes;

                # If we read the body and the user exceeded content length, we already closed the connection with
                # 413 Payload Too Large. We don't need to continue processing.
                if (-not (Test-TCPConnection)) {
                    Close-TCPConnection;
                    continue;
                }

                $GlobalVariable.Private.RestApi.WebPath = Expand-RestApiWebPath -WebPath $ParsedHttpHeader['Path'];
                $GlobalVariable.Private.RestApi.Header  = $ParsedHttpHeader;
                $AclTest                                = Test-RestApiAccessControl;

                Write-LoggingEntry -Message 'Processed RestApi request' -Level 'Debug' -Data @{
                    'WorkerId'     = $WorkerId;
                    'Client'       = $TcpClient;
                    'RawHeader'    = $RawHttpHeader.RawString;
                    'ParsedHeader' = $GlobalVariable.Private.RestApi.Header;
                    'BodyData'     = $GlobalVariable.Private.RestApi.Body.RawString;
                    'ApiWebPath'   = $GlobalVariable.Private.RestApi.WebPath;
                };

                if ($GlobalVariable.Private.RestApi.WebPath['Version'] -ne 'favicon.ico') {
                    if ($AclTest -ne $GlobalVariable.Public.ReturnCodes.RestApiAccessControlPermissionGranted.Code -and $AclTest -ne $GlobalVariable.Public.ReturnCodes.RestApiAccessControlNotDefined.Code) {
                        $GlobalVariable.Private.RestApi.Body          = $null;
                        $GlobalVariable.Private.RestApi.WebPath       = $null;
                        $GlobalVariable.Private.RestApi.Header        = $null;
                        $GlobalVariable.Private.RestApi.ContentLength = 0;

                        Send-TCPMessage -MsgObj (New-RestApiResponse -StatusCode 403 -StatusMessage 'Forbidden' -ResponseBody @{ 'error' = 'You do not have access to this resource'} ) | Out-Null;
                        # Close the connection
                        Close-TCPConnection;

                        continue;
                    }
                }

                # Here you would typically route the request to the appropriate handler based on the parsed headers and body
                switch ($GlobalVariable.Private.RestApi.WebPath['Version']) {
                    'v1' {
                        # Invoke the API call handler
                        # No arguments needed as context is in the global RestApi private space
                        Invoke-RestApiCall | Out-Null;
                        break;
                    };
                    'favicon.ico' {
                        Send-TCPMessage -MsgObj (New-RestApiFaviconResponse);
                        break;
                    };
                    default {
                        Show-ModuleWebUI;
                        break;
                    };
                }
            } else {
                Write-LoggingEntry -Message 'Failed to update TCP connection for RestApi Worker' -Level 'Error' -Data @{ 'TcpClient' = $TcpClient };
            }
        } catch {
            Write-LoggingEntry -Message 'Error processing RestApi Worker connection' -Level 'Error' -Data @{ 'WorkerId' = $WorkerId; 'Exception' = $_.Exception };
        }

        # Clear RestApi context to ensure we fresh start for the next connection
        $GlobalVariable.Private.RestApi.Body          = $null;
        $GlobalVariable.Private.RestApi.WebPath       = $null;
        $GlobalVariable.Private.RestApi.Header        = $null;
        $GlobalVariable.Private.RestApi.ContentLength = 0;

        # Close the connection once we are done
        Close-TCPConnection;
    }
}

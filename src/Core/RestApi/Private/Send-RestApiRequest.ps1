<#
.SYNOPSIS
Send an HTTPS request to the local RestApi.

.DESCRIPTION
Sends an HTTP(S) request to the local RestApi endpoint configured in the runtime.
Ensures the RestApi configuration is loaded, constructs the request URI and forwards
the request using `Invoke-RestMethod`. JSON bodies are serialized for non-GET
methods. The function returns standardized return values using
`Write-FunctionReturnValue`.

.PARAMETER WebPath
| Name | Type | Description | Default |
|------|------|-------------|---------|
| WebPath | System.String | Relative web path or endpoint (for example '/v1/status'). Leading slash optional. | '' |

.PARAMETER Method
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Method | System.String | HTTP method to use (GET, POST, PUT, DELETE, etc.). | 'GET' |

.PARAMETER Headers
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Headers | System.Collections.Hashtable | Additional HTTP headers to include. | @{ 'Content-Type' = 'application/json'; } |

.PARAMETER Body
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Body | System.Hashtable | Request body to be serialized as JSON for non-GET methods. | @{ } |

.OUTPUTS
PSCustomObject — Function return value produced by `Write-FunctionReturnValue`.
- `RestApiRequestSuccessful`: Data contains `Response`.
- `RestApiRequestFailed`: Data contains `Exception`, `Uri`, `Method`, `Headers`, `Body` or `StatusCode` and `Response`.

.EXAMPLE
PS> Send-RestApiRequest -WebPath '/v1/status' -Method 'GET'
PS> Send-RestApiRequest -WebPath '/v1/items' -Method 'POST' -Body @{ name = 'test' }

.NOTES
Uses `Read-RestApiConfig` to ensure RestApi is configured and `Invoke-RestMethod`
with `-SkipCertificateCheck` for local/self-signed certificates. Non-200 status
codes are treated as failures and returned via `Write-FunctionReturnValue`.
#>
function Send-RestApiRequest()
{
    param (
        [string]$WebPath    = '',
        [string]$Method     = 'GET',
        [hashtable]$Headers = @{ 'Content-Type' = 'application/json'; },
        [hashtable]$Body    = @{ }
    );

    $GlobalVariable = Get-GlobalRuntimeVariable;

    # Just load the REST API config to ensure we can process requests (knowing ports and everything)
    if ((Read-RestApiConfig) -ne $GlobalVariable.Public.ReturnCodes.RestApiConfigLoaded.Code) {
        return;
    }

    [string]$Uri = [string]::Format('https://localhost:{0}', $GlobalVariable.Public.RestApi.Config.ListenPort);
    $Uri         = Join-WebPath -Path $Uri -ChildPath $WebPath;

    try  {
        if ($Method -eq 'GET') {
            $Response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method 'GET' -SkipCertificateCheck -SkipHttpErrorCheck -StatusCodeVariable StatusCode;
        } else {
            $JsonBody = $Body | ConvertTo-Json -Depth 10;
            $Response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Body $JsonBody -Method $Method -SkipCertificateCheck -SkipHttpErrorCheck -StatusCodeVariable StatusCode;
        }

        if ($StatusCode -ne 200) {
            return (Write-FunctionReturnValue -ReturnValue 'RestApiRequestFailed' -Data @{ 'StatusCode' = $StatusCode; 'Response' = $Response; });
        }
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiRequestFailed' -Data @{ 'Exception' = $_.Exception; 'Uri' = $Uri; 'Method' = $Method; 'Headers' = $Headers; 'Body' = $Body; });
    }

    return (Write-FunctionReturnValue -ReturnValue 'RestApiRequestSuccessful' -Data @{ 'Response' = $Response });
}

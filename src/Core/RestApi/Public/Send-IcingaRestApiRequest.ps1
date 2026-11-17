<#
.SYNOPSIS
Send an HTTP(S) request to the local Icinga RestApi endpoint

.DESCRIPTION
Public wrapper around `Send-RestApiRequest` that sends an HTTP or HTTPS
request to the locally running RestApi daemon. The function loads the
RestApi configuration to determine the listen port, constructs the full
URI and forwards the call using `Invoke-RestMethod` with TLS certificate
checking disabled for self-signed certificates. Non-GET methods serialize
the `Body` hashtable as JSON. Non-200 responses are returned as failures.

.PARAMETER WebPath
| Name    | Type          | Description                                                                   | Default |
|---------|---------------|-------------------------------------------------------------------------------|---------|
| WebPath | System.String | Relative web path or endpoint (e.g. '/v1/status'). Leading slash is optional. | ''      |

.PARAMETER Method
| Name   | Type          | Description                                        | Default |
|--------|---------------|----------------------------------------------------|---------|
| Method | System.String | HTTP method to use (GET, POST, PUT, DELETE, etc.). | 'GET'   |

.PARAMETER Headers
| Name    | Type                         | Description                                        | Default                                   |
|---------|------------------------------|----------------------------------------------------|-------------------------------------------|
| Headers | System.Collections.Hashtable | Additional HTTP headers to include in the request. | @{ 'Content-Type' = 'application/json'; } |

.PARAMETER Body
| Name | Type                         | Description                                          | Default |
|------|------------------------------|------------------------------------------------------|---------|
| Body | System.Collections.Hashtable | Request body serialized as JSON for non-GET methods. | @{ }    |

.OUTPUTS
PSCustomObject -- structured return value from `Write-FunctionReturnValue`.
`RestApiRequestSuccessful` with `Response` in Data on success;
`RestApiRequestFailed` with `StatusCode` and `Response` or `Exception` on failure.

.EXAMPLE
PS> Send-IcingaRestApiRequest -WebPath '/v1/status' -Method 'GET'
PS> Send-IcingaRestApiRequest -WebPath '/v1/items' -Method 'POST' -Body @{ name = 'test' }

.NOTES
Requires a valid `restapi.json` configuration file to be present in the
module config directory. The request always targets `https://localhost:<port>`.
Certificate validation is skipped via `-SkipCertificateCheck` to support
self-signed TLS certificates.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Send-IcingaRestApiRequest()
{
    param (
        [string]$WebPath    = '',
        [string]$Method     = 'GET',
        [hashtable]$Headers = @{ 'Content-Type' = 'application/json'; },
        [hashtable]$Body    = @{ }
    );

    return (
        Send-RestApiRequest `
            -WebPath $WebPath `
            -Method $Method `
            -Headers $Headers `
            -Body $Body
    );
}

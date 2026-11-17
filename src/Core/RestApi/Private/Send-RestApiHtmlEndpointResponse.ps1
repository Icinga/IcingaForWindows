<#
.SYNOPSIS
Return an HTML listing of available RestApi endpoints for a space.

.DESCRIPTION
Generates a simple HTML document listing available endpoints for the
provided space object or, if no space is given, lists all configured
spaces. The HTML is returned to the client as an HTTP response.

.PARAMETER SpaceObj
| Name     | Type           | Description                                                     | Default |
|----------|----------------|-----------------------------------------------------------------|---------|
| SpaceObj | PSCustomObject | Optional space configuration object to enumerate endpoints for. |         |

.OUTPUTS
None -- sends an HTTP response with `Content-Type: text/html` via `Send-TCPMessage`.

.EXAMPLE
PS> Send-RestApiHtmlEndpointResponse -SpaceObj $space

.NOTES
Intended to be used by browser-based exploration of the RestApi.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Send-RestApiHtmlEndpointResponse()
{
    param (
        [PSCustomObject]$SpaceObj = $null
    );

    $GlobalVariable            = Get-GlobalRuntimeVariable;
    [hashtable]$Spaces         = $GlobalVariable.Private.RestApi.Spaces;
    [hashtable]$WebPath        = $GlobalVariable.Private.RestApi.WebPath;

    # Since we found a SpaceObj but no return value, there was nothing to be executed from
    # this path. However, we have sub-entries. We should help the user and provide an output
    # for available endpoints
    [array]$AvailableEndpoints = @();

    if ($null -ne $SpaceObj) {
        foreach ($entry in $SpaceObj.PSObject.Properties) {
            # Ensure we do not list the ApiCommandExecution entry itself, if present
            if ($entry.Name -ne 'ApiCommandExecution') {
                $AvailableEndpoints += $entry.Name;
            }
        }
    } else {
        # No space object found, we need to list all available spaces instead
        foreach ($space in $Spaces.Keys) {
            $AvailableEndpoints += $space;
        }
    }

    # Create a simple HTML document, listing available endpoints and building a link for each
    # entry the user can click on to explore further
    # We just add the links here, ensuring it will work by using the REST-Endpoint directly but also the Web UI's Api Explorer
    [string]$HtmlBody = "<html><head><title>Available RestApi Endpoints</title></head><body><ul>";
    foreach ($endpoint in $AvailableEndpoints) {
        [string]$EndpointLink = Join-WebPath -Path $WebPath['WebPath'] -ChildPath $endpoint;
        $HtmlBody            += [string]::Format('<li><a href="{0}">{1}</a></li>', $EndpointLink, $endpoint);
    }
    $HtmlBody += "</ul></body></html>";

    Send-TCPMessage `
        -MsgObj (
            New-RestApiResponse `
                -StatusCode 200 `
                -StatusMessage 'Ok' `
                -ContentType 'text/html; charset=utf-8' `
                -ResponseBody $HtmlBody
        );
}

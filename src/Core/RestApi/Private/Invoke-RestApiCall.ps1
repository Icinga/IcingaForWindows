<#
.SYNOPSIS
Resolve the REST API path to a configured handler and execute it.

.DESCRIPTION
Core dispatcher of the Icinga for Windows REST API. Reads the parsed web-path
and headers from `$Global.Private.RestApi.*`, walks the configured
spaces hashtable (Space -> Action -> Resource) to locate an
`ApiCommandExecution` field and invokes the bound PowerShell function
via `Invoke-RestApiCommandExecutionField`. Emits the appropriate JSON
response on success and well-formed error responses on failure
(missing space -> 404, invalid path depth -> 400, command error -> 500,
no spaces configured -> 500, no command at all -> HTML endpoint listing
or 200 / 404 for JSON callers).

.OUTPUTS
System.Int32 -- A semantic return code resolved through
`Write-FunctionReturnValue` for downstream diagnostics. The HTTP
response is sent directly over the worker's TCP stream.

.EXAMPLE
PS> Invoke-RestApiCall

Called by `Start-RestApiWorker` after the request line and body have
been parsed; arguments are taken from worker-private state.

.NOTES
Path schema is `/v1/<Space>/<Action>/<Resource>`. The actual
`ApiCommandExecution` lookup supports 2, 3 or 4 segments (segment
count is checked before the handler runs).

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-RestApiCall()
{
    $GlobalVariable           = Get-GlobalRuntimeVariable;
    # Retrieve context from global RestApi private space for easier usage
    [hashtable]$Spaces        = $GlobalVariable.Private.RestApi.Spaces;
    [hashtable]$WebPath       = $GlobalVariable.Private.RestApi.WebPath;
    [PSCustomObject]$SpaceObj = $null;
    $ReturnValue              = $null;

    if ($null -eq $Spaces -or $Spaces.Count -eq 0) {
        Send-TCPMessage `
            -MsgObj (
                New-RestApiResponse `
                    -StatusCode 500 `
                    -StatusMessage 'Internal Server Error' `
                    -ResponseBody @{ 'error' = 'API spaces configuration is missing on the server.' }
            );

        return (Write-FunctionReturnValue -ReturnValue 'RestApiNoSpacesConfigured' -OverrideReturn $null);
    }

    if ([string]::IsNullOrEmpty($WebPath.Space)) {
        # Send a HTML response listing available endpoints. As we are on the root, ignore SpaceObj
        # It will take care of listing all available spaces endpoints
        Send-RestApiHtmlEndpointResponse;

        return (Write-FunctionReturnValue -ReturnValue 'RestApiNoSpaceInPath' -Data @{ 'WebPath' = $WebPath } -OverrideReturn $null);
    }

    <#
    Now we need to navigate our space configuration to find the functions being used and
    fetch the objects properly from possible segments. Lets assume we have a space config like this:
    {
        "check": {
            "select": {
                "ApiCommandExecution": {
                    "Method": "GET",
                    "Parameters": {
                        "Name": "string"
                    },
                    "Function": "Set-DataValue"
                }
            },
            "increment": {
                "ApiCommandExecution": {
                    "Method": "POST",
                    "Parameters": {
                        "Count": "int"
                    },
                    "Function": "Add-DataToModule"
            }
            },
            "show": {
                "ApiCommandExecution": {
                    "Method": "GET",
                    "Parameters": {},
                    "Function": "Show-MyData"
                }
            },
            "ApiCommandExecution": {
                "Method": "*",
                "Parameters": { },
                "Function": "Show-AvailableCommands"
            }
        }
    }

    This entire call is handled within the v1 space, which means the version from our webpath is already handled directly at Start-RestApiWorker.
    Next, we need to find the correct space, which is "check" in this case. This is done by looking at the first segment of the webpath.

    The webpath object is configured as follows (Expand-RestApiWebPath):
    {
        'Segments'     = [string[]] Array of path segments (0-based index)
        'QueryParams'  = [hashtable] Key-value pairs of query parameters
        'WebPath'      = [string] Original web path
        'HasQuery'     = [bool] Indicates if query parameters are present
        'SegmentCount' = [int] Number of path segments
        'Version'      = [string] First path segment (if present)
        'Space'        = [string] Second path segment (if present)
        'Action'       = [string] Third path segment (if present)
        'Resource'     = [string] Fourth path segment (if present)
    }

    The Header is configured as follows (Expand-RestApiHeader):
    {
        'Method'      = [string] HTTP method (GET, POST, etc.)
        'Path'        = [string] Raw request path
        'Headers'     = [hashtable] Key-value pairs of headers
        'HttpVersion' = [string] HTTP version (e.g., HTTP/1.1)
    }

    We have the "Space" configured, which means we can tell exactly which space we want to use.

    The next entries would be action and resource, which is enough for the Rest-Api to provide a granular routing.
    Basically we have to do the following steps:
    1. Check if the space exists in our $Spaces hashtable
    2. Now we have to check if either action exists or if we already have a "ApiCommandExecution" field defined directly in the space
    3. If we have an action, we need to check there as well if there is a "ApiCommandExecution" defined or if we have to go deeper into resource
    4. Finally we need to check the resource and see if a "ApiCommandExecution" is defined there. If there is not, we need to return 500 with proper Json error message
    5. Once we have the "ApiCommandExecution" call, we need to validate the method (*, GET, POST, etc.) against the request method in the header
    6. Finally, we need to extract the parameters from either the query string (GET) or the body (POST) and call the function with those parameters
    7. We need to check if the function actually exists and is callable, and return 404 if not found with a proper Json error message
    8. If everything is fine, we call the function and capture the output to send. We can use the @ splatting operator for this, just have to map the parameters
       to a hashtable first.
    9. Finally, we need to send the response back to the client with proper status code and messages.
    10. In case of any errors, we need to catch them and send a proper error response back to the client.
    #>

    # Check if the requested space exists
    if (-not $Spaces.ContainsKey($WebPath.Space)) {
        Send-TCPMessage `
            -MsgObj (
                New-RestApiResponse `
                    -StatusCode 404 `
                    -StatusMessage 'Not Found' `
                    -ResponseBody @{ 'error' = "The requested API space '$($WebPath.Space)' does not exist." }
            );

        return (Write-FunctionReturnValue -ReturnValue 'RestApiSpaceNotFound' -Data @{ 'Space' = $WebPath.Space } -OverrideReturn $null);
    }

    # Now we need to navigate based on segment count. We can create a SpaceObj for easier access and
    # crawl through the possible ApiCommandExecution fields
    # Our Spaces hashtable contains all configured spaces, while the key is always the space name
    # and the value is a PSCustomObject with possible actions and resources
    switch ($WebPath.SegmentCount) {
        2 {
            # Example: /v1/space
            $SpaceObj = $Spaces[$WebPath.Space];
            break;
        };
        3 {
            # Example: /v1/space/action
            $SpaceObj = $Spaces[$WebPath.Space].($WebPath.Action);
            break;
        };
        4 {
            # Example: /v1/space/action/resource
            $SpaceObj = $Spaces[$WebPath.Space].($WebPath.Action).($WebPath.Resource);
            break;
        };
        Default {
            Send-TCPMessage `
                -MsgObj (
                    New-RestApiResponse `
                        -StatusCode 400 `
                        -StatusMessage 'Bad Request' `
                        -ResponseBody @{ 'error' = 'The requested API path is invalid or too deep.' }
                );

            return (Write-FunctionReturnValue -ReturnValue 'RestApiInvalidPath' -Data @{ 'WebPath' = $WebPath } -OverrideReturn $null);
        };
    }

    if (Test-RestApiCommandExecutionField -Space $SpaceObj) {
        $ReturnValue = Invoke-RestApiCommandExecutionField -Space $SpaceObj.ApiCommandExecution;
    }

    # Test for "error" in ReturnValue and check if an error message is present
    # ReturnValue could be anything from hashtable to PSCustomObject to string, etc.
    [string]$ErrorMsg = $null;
    if ($null -ne $ReturnValue) {
        if ($ReturnValue -is [System.Collections.IDictionary] -and $ReturnValue.ContainsKey('error')) {
            $ErrorMsg = [string]$ReturnValue['error'];
        } elseif ($ReturnValue -isnot [System.Collections.ICollection] -and $null -ne $ReturnValue.error) {
            $ErrorMsg = [string]$ReturnValue.error;
        }
    }

    if (-not [string]::IsNullOrEmpty($ErrorMsg)) {
        # An error occurred during command execution
        Send-TCPMessage `
            -MsgObj (
                New-RestApiResponse `
                    -StatusCode 500 `
                    -StatusMessage 'Internal Server Error' `
                    -ResponseBody $ReturnValue
            );

        return (
            Write-FunctionReturnValue `
                -ReturnValue 'RestApiCommandExecutionError' `
                -Data @{
                    'Error'    = $ErrorMsg;
                    'WebPath'  = $WebPath;
                    'Space'    = $Spaces;
                    'SpaceObj' = $SpaceObj;
                } `
                -OverrideReturn $null
            );
    }

    # Send the success message with the result
    # Will be automatically converted to JSON by New-RestApiResponse
    if ($null -ne $ReturnValue) {
        Send-TCPMessage `
        -MsgObj (
            New-RestApiResponse `
                -StatusCode 200 `
                -StatusMessage 'Ok' `
                -ResponseBody $ReturnValue
        );
    } else {
        # If we didn't get any return value, we send a 404 not found of the SpaceObj is empty
        # This means, we didn't have configured Api handling for this path
        if ($null -eq $SpaceObj) {
            Send-TCPMessage `
                -MsgObj (
                    New-RestApiResponse `
                        -StatusCode 404 `
                        -StatusMessage 'Not Found' `
                        -ResponseBody @{ 'error' = 'The requested resource was not found.' }
                );
        } else {
            # Do not send any HTML response if we requested a JSON response
            if ($null -ne $GlobalVariable.Private.RestApi.Header.Headers.'content-type' -and $GlobalVariable.Private.RestApi.Header.Headers.'content-type'.Value -like 'application/json*') {
                Send-TCPMessage `
                    -MsgObj (
                        New-RestApiResponse `
                            -StatusCode 200 `
                            -StatusMessage 'Ok' `
                            -ResponseBody $null
                    );
            } else {
                Send-RestApiHtmlEndpointResponse -SpaceObj $SpaceObj;
            }
        }
    }

    # Return success to our parent function with some debug logging
    return (
        Write-FunctionReturnValue `
            -ReturnValue 'RestApiCommandExecutionSucceeded' `
            -Data @{
                'WebPath'  = $WebPath;
                'Space'    = $Spaces;
                'SpaceObj' = $SpaceObj;
            } `
            -OverrideReturn $null
    );
}

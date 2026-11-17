<#
.SYNOPSIS
Invoke the function defined in an ApiCommandExecution space configuration

.DESCRIPTION
Validates the provided space object, resolves the configured PowerShell
function name, verifies the HTTP method is permitted, maps query or body
parameters to the expected types defined in the space configuration and
then calls the function via splatting. Web path, header and body context
are read from `(Get-GlobalRuntimeVariable).Private.RestApi`. Returns the
function result or a structured error object on failure.

.PARAMETER Space
| Name  | Type           | Description                                                                                     | Default |
|-------|----------------|-------------------------------------------------------------------------------------------------|---------|
| Space | PSCustomObject | ApiCommandExecution configuration object with `Function`, `Method` and `Parameters` properties. | $null   |

.OUTPUTS
System.Object -- the return value of the invoked function, or a hashtable
with an `error` key when the invocation fails or is not permitted.

.EXAMPLE
PS> Invoke-RestApiCommandExecutionField -Space $spaceObj.ApiCommandExecution

.NOTES
Parameter type mapping supports `int`, `string`, `bool` and `array`.
Array values in GET query strings are split on commas while respecting
quoted strings. Must only be called from within a RestApi worker thread
after `Private.RestApi.WebPath` and `Private.RestApi.Header` are set.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-RestApiCommandExecutionField()
{
    param (
        [PSCustomObject]$Space = $null
    );

    # We first validate the input
    if ($null -eq $Space) {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiSpaceMissing' -OverrideReturn @{ 'error' = 'No space object provided'; } );
    };

    $GlobalVariable       = Get-GlobalRuntimeVariable;
    [hashtable]$WebPath   = $GlobalVariable.Private.RestApi.WebPath;
    [hashtable]$Header    = $GlobalVariable.Private.RestApi.Header;
    [PSCustomObject]$Body = $null;
    [string]$FunctionCall = $Space.Function;
    $CommandExist         = $true;

    if ([string]::IsNullOrEmpty($FunctionCall)) {
        $CommandExist = $false;
        $FunctionCall = '';
    } else {
        if ($null -eq (Get-Command -Name $FunctionCall -ErrorAction SilentlyContinue)) {
            $CommandExist = $false;
        }
    }

    if ([string]::IsNullOrEmpty($FunctionCall) -or -not $CommandExist) {
        return (
            Write-FunctionReturnValue `
                -ReturnValue 'RestApiCommandExecutionFunctionError' `
                -Data @{ 'Space' = $Space; 'FunctionCall' = $FunctionCall; 'CommandExist' = $CommandExist; } `
                -OverrideReturn @{
                    'error' = ([string]::Format('No function specified for API command execution or command "{0}" not found.', $FunctionCall));
                }
        );
    };

    # If we have a body, get the JSON object and store it in $Body
    if ($null -ne $GlobalVariable.Private.RestApi.Body) {
        $Body = $GlobalVariable.Private.RestApi.Body.JsonObj;
    };

    <#
        We have confirmed that the ApiCommandExecution field exists in the provided Space object.
        Now we need to invoke the specified command.
        It is stored as PSCustomObject (because of JSON deserialization) with properties:
        - Command: string (the command to invoke)
        - Parameters: hashtable (the parameters available for the command)
        - Method: string (the HTTP method, e.g. GET, POST, etc.)

        Example ApiCommandExecution field:
        "ApiCommandExecution": {
            "Method": "*",
            "Parameters": {
                "Count": "int"
            },
            "Function": "Show-MyData"
        }

        # We now need to verify that the Method is allowed (e.g. matches the request method or is '*')
        # Afterwards we need to read the provided parameters (if any) from $WebPath.QueryParams or $Body (if POST/PUT/DELETE, etc.)
        # We need then to convert the values of the parameters to the expected types (e.g. int, string, bool, etc.)
        # The mapping is done at the Parameters property of the ApiCommandExecution field.
        # Finally, we invoke the command with the parameters and return the result.
    #>

    # Validate Method first
    if ($null -eq $Space.Method -and $Header.Method.ToUpper() -ne 'GET') {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiMethodNotAllowedForCommandExecution' -Data @{
            'ExpectedMethod' = 'GET';
            'ActualMethod'   = $Header.Method;
        } -OverrideReturn @{ 'error' = ([string]::Format('Method {0} not allowed for this command execution. Expected: GET', $Header.Method)); } );
    } elseif ($Space.Method -notcontains '*' -and $Space.Method -notcontains $Header.Method) {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiMethodNotAllowedForCommandExecution' -Data @{
            'ExpectedMethod' = $Space.Method;
            'ActualMethod'   = $Header.Method;
        } -OverrideReturn @{ 'error' = ([string]::Format('Method {0} not allowed for this command execution. Expected: {1}', $Header.Method, ($Space.Method | Out-String).Trim())); } );
    };

    # Prepare parameters for function call
    [hashtable]$FunctionParams = @{ };

    foreach ($ParamName in $Space.Parameters.PSObject.Properties.Name) {
        # ParamName is the name of the parameter
        # Now map the type "int", "string", "bool", etc. to ParamType
        $ParamType  = $Space.Parameters.$ParamName;

        # Determine source of parameter value
        $ParamValue = $null;
        # If we use GET, we read from query parameters
        if ($Header.Method.ToUpper() -eq 'GET') {
            # GET requests use query parameters
            # Check if parameter exists in query params
            if ($WebPath.QueryParams.ContainsKey($ParamName)) {
                # Store it as value
                $ParamValue = $WebPath.QueryParams[$ParamName];
            };
        } else {
            # Other methods use body parameters
            # Check if parameter exists in body
            if ($null -ne $Body -and $null -ne $Body.$ParamName) {
                # Store it as value
                $ParamValue = $Body.$ParamName;
            };
        };

        # Convert parameter to expected type
        if ($null -ne $ParamValue) {
            switch ($ParamType.ToLower()) {
                'int'    {
                    $FunctionParams[$ParamName] = [int]$ParamValue;
                    break;
                };
                'string' {
                    $FunctionParams[$ParamName] = [string]$ParamValue;
                    break;
                };
                'bool'   {
                    $FunctionParams[$ParamName] = ConvertFrom-ObjectToBool -Value $ParamValue;
                    break;
                };
                'array'  {
                    # Assume comma-separated values for array, but keep possible strings within "" with
                    # a text and comma inside intact
                    if ($ParamValue -is [array]) {
                        $FunctionParams[$ParamName] = $ParamValue;
                    } else {
                        # Split by comma, but respect quoted strings and remove the quota marks for each entry
                        $FunctionParams[$ParamName] = [System.Text.RegularExpressions.Regex]::Matches(
                            $ParamValue, '("[^"]*"|[^,]+)'
                        ) | ForEach-Object {
                            $_.Value.Trim('"')
                        };
                    };
                    break;
                };
                default  {
                    $FunctionParams[$ParamName] = $ParamValue;
                    break;
                };
            };
        };
    };

    # Now invoke the function with the parameters
    try {
        $Result = & $FunctionCall @FunctionParams;

        return (
            Write-FunctionReturnValue -ReturnValue 'RestApiCommandExecutionInvokingFunction' -Data @{
                'Function'   = $FunctionCall;
                'Parameters' = $FunctionParams;
                'Result'     = $Result;
            } -OverrideReturn $Result
        );
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiCommandExecutionFunctionError' -Data @{
            'Function'   = $FunctionCall;
            'Parameters' = $FunctionParams;
            'Exception'  = $_.Exception;
        } -OverrideReturn @{ 'error' = ([string]::Format("Error invoking function {0} {1}", $FunctionCall, $_.Exception.Message)); } );
    }
}

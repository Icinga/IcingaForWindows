<#
.SYNOPSIS
Load RestApi configuration from disk.

.DESCRIPTION
Reads the `restapi.json` configuration file from the module config
directory and stores the parsed object into the global runtime variable
under `(Get-GlobalRuntimeVariable).Public.RestApi.Config`.

.OUTPUTS
PSCustomObject — the loaded RestApi configuration on success, or a
structured return code object when the file is missing or corrupt.

.EXAMPLE
PS> Read-RestApiConfig

.NOTES
Logs structured return codes using `Write-FunctionReturnValue` when the
file is missing or cannot be parsed.
#>
function Read-RestApiConfig()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;
    $ConfigFile     = Join-Path -Path (Get-ModuleConfigDirectory) -ChildPath 'restapi.json';
    $FileContent    = Read-SecureFile -File $ConfigFile;

    if ($null -eq $FileContent) {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiConfigNotFound' -Data @{ 'ConfigFile' = $ConfigFile } -OverrideReturn $null);
    }

    try {
        $ConfigObject = $FileContent | ConvertFrom-Json -ErrorAction Stop;
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiConfigCorrupted' -Data @{ 'ConfigFile' = $ConfigFile; 'Exception' = $_.Exception } -OverrideReturn $null);
    }

    $GlobalVariable.Public.RestApi.Config = $ConfigObject;

    return (Write-FunctionReturnValue -ReturnValue 'RestApiConfigLoaded' -Data @{ 'Config' = $GlobalVariable.Public.RestApi.Config });
}

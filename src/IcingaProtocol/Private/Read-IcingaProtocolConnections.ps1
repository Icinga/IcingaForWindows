<#
.SYNOPSIS
Reads the Icinga protocol connection configuration file and returns parsed JSON.

.DESCRIPTION
Read-IcingaProtocolConnection locates the module configuration directory, loads
IcingaProtocol\Connection.json, performs simple placeholder replacements
($fqdn, $hostname) and returns the parsed JSON object. When the configuration
file is not found, the function returns a standardized result object via
Write-FunctionReturnValue with return value IcingaClientConfigNotFound.

.OUTPUTS
PSCustomObject — Parsed JSON connection configuration.
Returns a Write-FunctionReturnValue result object when the file is missing.

.EXAMPLE
PS> $cfg = Read-IcingaProtocolConnection

.NOTES
Placeholder substitution uses [System.Net.Dns]::GetHostEntry and GetHostName.
The configuration file is read through Read-SecureFile to enforce path approval.
#>
function Read-IcingaProtocolConnection()
{
    [string]$ConfigDir        = Get-ModuleConfigDirectory;
    [string]$ConnectionConfig = Join-Path -Path $ConfigDir -ChildPath 'IcingaProtocol\Connection.json';

    if (-not (Test-Path $ConnectionConfig)) {
        return (Write-FunctionReturnValue -ReturnValue 'IcingaClientConfigNotFound' -Data @{ 'Config' = $ConnectionConfig; } -OverrideReturn $null);
    }

    $ConfigJson = Read-SecureFile -File $ConnectionConfig;

    $ConfigJson = $ConfigJson.Replace('$fqdn', [System.Net.Dns]::GetHostEntry("").HostName);
    $ConfigJson = $ConfigJson.Replace('$hostname', [System.Net.Dns]::GetHostName());

    return (ConvertFrom-Json -InputObject $ConfigJson);
}

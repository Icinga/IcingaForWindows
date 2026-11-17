<#
.SYNOPSIS
Resolve, validate and execute an Icinga 2 ExecuteCommand payload

.DESCRIPTION
Invoke-IcingaProtocolCheckCommand orchestrates the complete execution lifecycle
for an Icinga 2 event::ExecuteCommand RPC request:
1. Clears the thread-local CheckResult and ActiveCheckCommand slots on
   Get-GlobalRuntimeVariable.
2. Resolves macros.ifw_api_command via Resolve-IcingaProtocolCommand (returning
   UNKNOWN 3 with IWKB001003 on missing, unapproved or unknown commands).
3. Parses macros via ConvertFrom-IcingaProtocolMacros (returning UNKNOWN 3 with
   IWKB001000, IWKB001001 or IWKB001002 on macro/parameter mapping errors).
4. Executes PowerShell check plugins via Invoke-ModulePowerShellCommand and
   approved external .ps1 scripts via Invoke-IcingaProtocolExternalScript.
5. Executes approved native binaries and batch scripts (.exe, .cmd, .bat, .com)
   via Invoke-IcingaProtocolBinaryProcess with check_timeout enforcement and
   descendant process-tree termination.
6. Normalizes exit codes outside 0..3 to 3 (UNKNOWN) and records telemetry.

Returns a plain hashtable of primitive values and arrays so no PowerShell class
instance ever crosses runspace boundaries.

.PARAMETER Params
| Name   | Type          | Description                                                          | Default |
|--------|---------------|----------------------------------------------------------------------|---------|
| Params | System.Object | Deserialized params dictionary or object from event::ExecuteCommand. | $null   |

.OUTPUTS
System.Collections.Hashtable -- Hashtable containing ExitCode (Int32 0..3),
Output (String), PerformanceData (Array) and CommandLine (String).

.EXAMPLE
PS> Invoke-IcingaProtocolCheckCommand -Params @{ 'command' = 'Invoke-IcingaCheckUptime'; 'macros' = @{ 'ifw_api_command' = 'Invoke-IcingaCheckUptime' } }

Executes Invoke-IcingaCheckUptime and returns its exit code, output, perfdata
and rendered command line.

.NOTES
Runs inside protocol worker threads; accesses runtime state exclusively via
Get-GlobalRuntimeVariable.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-IcingaProtocolCheckCommand()
{
    param (
        [object]$Params = $null
    );

    # Clear runspace-local plugin slots before resolving or executing the incoming check request
    $GlobalVariable                                   = Get-GlobalRuntimeVariable;
    $GlobalVariable.Private.Icinga.CheckResult        = $null;
    $GlobalVariable.Private.Icinga.ActiveCheckCommand = $null;

    [object]$Macros                                   = Get-ModuleObjectValue -InputObject $Params -Name 'macros';
    [object]$RawCommand                               = Get-ModuleObjectValue -InputObject $Params -Name 'command';
    [object]$RawTimeout                               = Get-ModuleObjectValue -InputObject $Params -Name 'check_timeout';
    [string]$CheckCommand                             = '';
    [int]$TimeoutMs                                   = 60000;

    if ($null -ne $RawCommand) {
        $CheckCommand = [string]$RawCommand;
    }

    # Convert Icinga 2's check_timeout (seconds, integer or fractional) into ceiling milliseconds
    # for external OS binary enforcement (defaulting to 60s and clamping to Int32.MaxValue)
    [double]$ParsedTimeout = 0;
    if ($null -ne $RawTimeout -and [double]::TryParse([string]$RawTimeout, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedTimeout) -and -not [double]::IsNaN($ParsedTimeout) -and $ParsedTimeout -gt 0) {
        [double]$ScaledTimeoutMs = [System.Math]::Ceiling($ParsedTimeout * 1000.0);
        if ($ScaledTimeoutMs -ge [double][int]::MaxValue) {
            $TimeoutMs = [int]::MaxValue;
        } else {
            $TimeoutMs = [int]$ScaledTimeoutMs;
        }
    }

    # 1. Resolve target command (PowerShell plugin or approved binary/script in Binaries)
    [hashtable]$Resolved = Resolve-IcingaProtocolCommand -Macros $Macros -CheckCommand $CheckCommand;

    if ($Resolved['Status'] -ne 'Ok') {
        Write-FunctionReturnValue -ReturnValue $Resolved['ReturnCodeKey'] -Data @{
            'CheckCommand' = $CheckCommand;
            'Status'       = $Resolved['Status'];
            'Message'      = $Resolved['Message'];
        } | Out-Null;

        [string]$FallbackCmd = $CheckCommand;
        if (-not [string]::IsNullOrWhiteSpace([string]$Resolved['CommandName'])) {
            $FallbackCmd = [string]$Resolved['CommandName'];
        }

        return @{
            'ExitCode'        = 3;
            'Output'          = [string]$Resolved['Message'];
            'PerformanceData' = @();
            'CommandLine'     = $FallbackCmd;
        };
    }

    # 2. Parse Icinga 2 macros into PowerShell splat arguments or ordered CLI tokens
    [hashtable]$Parsed = ConvertFrom-IcingaProtocolMacros -ResolvedCommand $Resolved -Macros $Macros;

    if ($Parsed['Status'] -ne 'Ok') {
        Write-FunctionReturnValue -ReturnValue $Parsed['ReturnCodeKey'] -Data @{
            'Command' = $Resolved['CommandName'];
            'Status'  = $Parsed['Status'];
            'Message' = $Parsed['Message'];
        } | Out-Null;

        return @{
            'ExitCode'        = 3;
            'Output'          = [string]$Parsed['Message'];
            'PerformanceData' = @();
            'CommandLine'     = [string]$Parsed['CommandLine'];
        };
    }

    [int]$ExitCode            = 3;
    [string]$CheckOutput      = '';
    [array]$CheckPerfData     = @();
    [string]$FinalCommandLine = [string]$Parsed['CommandLine'];

    # 3. Execute PowerShell plugin in-process, external .ps1 script in-process, or native binary via Win32 Process
    if ($Resolved['Kind'] -eq 'PowerShell') {
        [hashtable]$PluginExec = Invoke-ModulePowerShellCommand -Command ([string]$Resolved['CommandName']) -NamedArguments $Parsed['PowerShellArguments'] -AllocatedSecrets $Parsed['AllocatedSecureStrings'];
        $ExitCode              = [int]$PluginExec['ExitCode'];
        $CheckOutput           = [string]$PluginExec['Output'];
        $CheckPerfData         = @($PluginExec['PerformanceData']);
    } else {
        [string]$BinaryFullPath = [string]$Resolved['BinaryPath'];
        [string[]]$BinaryArgs   = $Parsed['BinaryArguments'];

        if ($BinaryFullPath.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
            [hashtable]$ScriptExec = Invoke-IcingaProtocolExternalScript -ScriptPath $BinaryFullPath -CommandName ([string]$Resolved['CommandName']) -BinaryArguments $BinaryArgs -DefaultCommandLine $FinalCommandLine;
            $ExitCode              = [int]$ScriptExec['ExitCode'];
            $CheckOutput           = [string]$ScriptExec['Output'];
            $CheckPerfData         = @($ScriptExec['PerformanceData']);
            $FinalCommandLine      = [string]$ScriptExec['CommandLine'];
        } else {
            [hashtable]$BinExec = Invoke-IcingaProtocolBinaryProcess -BinaryPath $BinaryFullPath -CommandName ([string]$Resolved['CommandName']) -BinaryArguments $BinaryArgs -TimeoutMs $TimeoutMs -DefaultCommandLine $FinalCommandLine;
            $ExitCode           = [int]$BinExec['ExitCode'];
            $CheckOutput        = [string]$BinExec['Output'];
            $CheckPerfData      = @($BinExec['PerformanceData']);
        }
    }

    # Normalize out-of-range exit codes (such as negative values or Win32 error codes > 3) to 3 (UNKNOWN)
    if ($ExitCode -lt 0 -or $ExitCode -gt 3) {
        $ExitCode = 3;
    }

    Write-FunctionReturnValue -ReturnValue 'IcingaProtocolCheckExecuted' -Data @{
        'Command'  = $Resolved['CommandName'];
        'Kind'     = $Resolved['Kind'];
        'ExitCode' = $ExitCode;
    } | Out-Null;

    return @{
        'ExitCode'        = [int]$ExitCode;
        'Output'          = [string]$CheckOutput;
        'PerformanceData' = [array]$CheckPerfData;
        'CommandLine'     = $FinalCommandLine;
    };
}

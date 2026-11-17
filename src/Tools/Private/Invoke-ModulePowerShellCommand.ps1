<#
.SYNOPSIS
Execute a PowerShell check command or external script with isolated runtime state

.DESCRIPTION
Invoke-ModulePowerShellCommand provides the single, runspace-safe execution
wrapper for native Invoke-IcingaCheck* plugins and external .ps1 scripts inside
Get-ModuleBinaryDirectory:
1. Saves Protected.IsBackgroundDaemon, enables daemon mode to suppress direct
   console writes, and clears thread-local Private.Icinga.CheckResult and
   Private.Icinga.ActiveCheckCommand (plus LASTEXITCODE when UseLastExitCode is
   enabled).
2. Invokes the target command in-process with '&' (never dot-sourced).
3. Reads primitive ExitCode, Output and PerformanceData from
   Private.Icinga.CheckResult when populated by IcingaPlugin.Compile(), or falls
   back to Split-IcingaBinaryPluginOutput for standard Nagios/Icinga stdout.
4. Restores Protected.IsBackgroundDaemon, clears thread-local CheckResult and
   ActiveCheckCommand slots, and disposes every entry in AllocatedSecrets inside
   a finally block.

.PARAMETER Command
| Name    | Type          | Description                                               | Default |
|---------|---------------|-----------------------------------------------------------|---------|
| Command | System.String | PowerShell command name or full .ps1 script path to call. | ''      |

.PARAMETER NamedArguments
| Name           | Type                         | Description                          | Default |
|----------------|------------------------------|--------------------------------------|---------|
| NamedArguments | System.Collections.Hashtable | Named parameter splatting hashtable. | @{}     |

.PARAMETER PositionalArguments
| Name                | Type         | Description                                    | Default |
|---------------------|--------------|------------------------------------------------|---------|
| PositionalArguments | System.Array | Optional positional arguments to pass after @. | @()     |

.PARAMETER AllocatedSecrets
| Name             | Type         | Description                                             | Default |
|------------------|--------------|---------------------------------------------------------|---------|
| AllocatedSecrets | System.Array | Temporary SecureString instances to dispose in finally. | @()     |

.PARAMETER UseLastExitCode
| Name            | Type                                         | Description                                                  | Default |
|-----------------|----------------------------------------------|--------------------------------------------------------------|---------|
| UseLastExitCode | System.Management.Automation.SwitchParameter | Fall back to $global:LASTEXITCODE for external .ps1 scripts. | $false  |

.PARAMETER ErrorContext
| Name         | Type          | Description                                                    | Default |
|--------------|---------------|----------------------------------------------------------------|---------|
| ErrorContext | System.String | Optional custom prefix for [UNKNOWN] unhandled error messages. | ''      |

.OUTPUTS
System.Collections.Hashtable -- Plain hashtable containing primitive ExitCode,
Output and PerformanceData values safe to pass across runspaces.

.EXAMPLE
PS> Invoke-ModulePowerShellCommand -Command 'Invoke-IcingaCheckUptime' -NamedArguments @{ 'Verbosity' = 2 }

Executes Invoke-IcingaCheckUptime in daemon mode and returns its primitive check
result hashtable.

.NOTES
Accesses runtime state exclusively via Get-GlobalRuntimeVariable. Never returns
PowerShell class instances across thread boundaries.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Invoke-ModulePowerShellCommand()
{
    param (
        [string]$Command            = '',
        [hashtable]$NamedArguments  = @{ },
        [array]$PositionalArguments = @(),
        [array]$AllocatedSecrets    = @(),
        [switch]$UseLastExitCode    = $false,
        [string]$ErrorContext       = ''
    );

    $GlobalVariable           = Get-GlobalRuntimeVariable;
    [bool]$PreviousDaemonFlag = [bool]$GlobalVariable.Protected.IsBackgroundDaemon;
    [int]$ExitCode            = 3;
    [string]$CheckOutput      = '';
    [array]$CheckPerfData     = @();

    try {
        # 1. Enter background-daemon execution mode so IcingaPlugin.Compile() suppresses console writes
        #    and stores its structured result in the runspace-local Private.Icinga.CheckResult slot
        $GlobalVariable.Protected.IsBackgroundDaemon      = $true;
        $GlobalVariable.Private.Icinga.CheckResult        = $null;
        $GlobalVariable.Private.Icinga.ActiveCheckCommand = $null;

        if ($UseLastExitCode) {
            $global:LASTEXITCODE = $null;
        }

        # 2. Invoke the PowerShell check function or external .ps1 script via '&' (never dot-sourced)
        $InvocationResult = $null;

        if ($null -ne $PositionalArguments -and $PositionalArguments.Count -gt 0) {
            $InvocationResult = & $Command @NamedArguments @PositionalArguments;
        } else {
            $InvocationResult = & $Command @NamedArguments;
        }

        # 3. Extract primitive ExitCode, Output and PerformanceData so no PowerShell class instance
        #    crosses runspace boundaries; fall back to stdout + $LASTEXITCODE for classic .ps1 scripts
        if ($null -ne $GlobalVariable.Private.Icinga.CheckResult) {
            $CompiledSlot  = $GlobalVariable.Private.Icinga.CheckResult;
            $ExitCode      = [int]$CompiledSlot.ExitCode;
            $CheckOutput   = [string]$CompiledSlot.Output;
            $CheckPerfData = @($CompiledSlot.PerformanceData);

            if ($InvocationResult -is [int]) {
                $ExitCode = [int]$InvocationResult;
            }
        } elseif (-not $UseLastExitCode -and $InvocationResult -is [int]) {
            $ExitCode = [int]$InvocationResult;
        } elseif ($UseLastExitCode -or $null -ne $InvocationResult) {
            [int]$FallbackExit = 0;

            if ($UseLastExitCode -and $null -ne $global:LASTEXITCODE) {
                $FallbackExit = [int]$global:LASTEXITCODE;
            }

            [string]$RawTextResult = '';
            if ($null -ne $InvocationResult) {
                $RawTextResult = ((@($InvocationResult) | ForEach-Object { [string]$_ }) -join "`n");
            }

            [hashtable]$SplitResult = Split-IcingaBinaryPluginOutput -RawOutput $RawTextResult;
            $CheckOutput            = [string]$SplitResult['Output'];
            $CheckPerfData          = @($SplitResult['PerformanceData']);
            $ExitCode               = $FallbackExit;
        }
    } catch {
        $ExitCode = 3;

        if ([string]::IsNullOrEmpty($ErrorContext)) {
            $CheckOutput = ('[UNKNOWN] Icinga Plugin Command Execution failed for "{0}": {1}' -f $Command, $_.Exception.Message);
        } else {
            $CheckOutput = ('[UNKNOWN] {0}: {1}' -f $ErrorContext, $_.Exception.Message);
        }
    } finally {
        # 4. Always restore daemon state, clear runspace-local slots and dispose temporary SecureString secrets
        $GlobalVariable.Protected.IsBackgroundDaemon      = $PreviousDaemonFlag;
        $GlobalVariable.Private.Icinga.CheckResult        = $null;
        $GlobalVariable.Private.Icinga.ActiveCheckCommand = $null;

        if ($null -ne $AllocatedSecrets) {
            foreach ($SecretObj in $AllocatedSecrets) {
                if ($null -ne $SecretObj -and $SecretObj -is [System.IDisposable]) {
                    $SecretObj.Dispose();
                }
            }
        }
    }

    return @{
        'ExitCode'        = [int]$ExitCode;
        'Output'          = [string]$CheckOutput;
        'PerformanceData' = [array]$CheckPerfData;
    };
}

<#
.SYNOPSIS
Resolve, validate and execute an Icinga 2 ExecuteCommand payload

.DESCRIPTION
Invoke-IcingaProtocolCheckCommand orchestrates the complete execution lifecycle
for an Icinga 2 event::ExecuteCommand RPC request:
1. Clears the thread-local CheckResult slot on Get-GlobalRuntimeVariable.
2. Resolves macros.ifw_api_command via Resolve-IcingaProtocolCommand (returning
   UNKNOWN 3 with IWKB001003 on missing, unapproved or unknown commands).
3. Parses macros via ConvertFrom-IcingaProtocolMacros (returning UNKNOWN 3 with
   IWKB001000, IWKB001001 or IWKB001002 on macro/parameter mapping errors).
4. Executes PowerShell check plugins (Invoke-IcingaCheck*) and approved external
   PowerShell scripts (.ps1 inside Get-ModuleBinaryDirectory) natively in-process
   using the '&' call operator (never dot-sourced) without a custom timeout
   wrapper (relying on Start-ThreadHouseKeeper), reading Private.Icinga.CheckResult
   when populated, masking SecureString arguments as '********' in CommandLine,
   and disposing all temporary SecureString instances in a finally block.
5. Executes approved native binaries and batch scripts (.exe, .cmd, .bat, .com)
   strictly by their full canonical path inside Get-ModuleBinaryDirectory with
   CommandLineToArgvW-compliant argument escaping, .cmd/.bat metacharacter
   validation, concurrent stdout/stderr capture (falling back to stderr when
   stdout is blank), check_timeout enforcement (60s default) with full descendant
   process-tree termination, exit-code normalization to 0..3 and Nagios/Icinga
   performance-data splitting.

Returns a plain hashtable of primitive values and arrays so no PowerShell class
instance ever crosses runspace boundaries.

.PARAMETER Params
| Name   | Type          | Description                                                           | Default |
|--------|---------------|-----------------------------------------------------------------------|---------|
| Params | System.Object | Deserialized params dictionary or object from event::ExecuteCommand.  | $null   |

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
#>
function Invoke-IcingaProtocolCheckCommand()
{
    param (
        [object]$Params = $null
    );

    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($null -ne $GlobalVariable -and $null -ne $GlobalVariable.Private -and $null -ne $GlobalVariable.Private.Icinga) {
        $GlobalVariable.Private.Icinga.CheckResult = $null;
    }

    [object]$Macros       = $null;
    [string]$CheckCommand = '';
    [int]$TimeoutMs       = 60000;

    if ($Params -is [System.Collections.IDictionary]) {
        foreach ($Key in $Params.Keys) {
            [string]$KeyName = [string]$Key;
            if ([string]::Equals($KeyName, 'macros', [System.StringComparison]::OrdinalIgnoreCase)) {
                $Macros = $Params[$Key];
            } elseif ([string]::Equals($KeyName, 'command', [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($null -ne $Params[$Key]) {
                    $CheckCommand = [string]$Params[$Key];
                }
            } elseif ([string]::Equals($KeyName, 'check_timeout', [System.StringComparison]::OrdinalIgnoreCase)) {
                [double]$ParsedTimeout = 0;
                if ($null -ne $Params[$Key] -and [double]::TryParse([string]$Params[$Key], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedTimeout) -and -not [double]::IsNaN($ParsedTimeout) -and $ParsedTimeout -gt 0) {
                    [double]$ScaledTimeoutMs = [System.Math]::Ceiling($ParsedTimeout * 1000.0);
                    if ($ScaledTimeoutMs -ge [double][int]::MaxValue) {
                        $TimeoutMs = [int]::MaxValue;
                    } else {
                        $TimeoutMs = [int]$ScaledTimeoutMs;
                    }
                }
            }
        }
    } elseif ($null -ne $Params) {
        foreach ($Prop in $Params.PSObject.Properties) {
            if ([string]::Equals([string]$Prop.Name, 'macros', [System.StringComparison]::OrdinalIgnoreCase)) {
                $Macros = $Prop.Value;
            } elseif ([string]::Equals([string]$Prop.Name, 'command', [System.StringComparison]::OrdinalIgnoreCase)) {
                if ($null -ne $Prop.Value) {
                    $CheckCommand = [string]$Prop.Value;
                }
            } elseif ([string]::Equals([string]$Prop.Name, 'check_timeout', [System.StringComparison]::OrdinalIgnoreCase)) {
                [double]$ParsedPropTimeout = 0;
                if ($null -ne $Prop.Value -and [double]::TryParse([string]$Prop.Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedPropTimeout) -and -not [double]::IsNaN($ParsedPropTimeout) -and $ParsedPropTimeout -gt 0) {
                    [double]$ScaledPropMs = [System.Math]::Ceiling($ParsedPropTimeout * 1000.0);
                    if ($ScaledPropMs -ge [double][int]::MaxValue) {
                        $TimeoutMs = [int]::MaxValue;
                    } else {
                        $TimeoutMs = [int]$ScaledPropMs;
                    }
                }
            }
        }
    }

    # 1. Resolve target command
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

    # 2. Parse macros into arguments
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

    # 3. Execute PowerShell plugin or approved external binary/script
    if ($Resolved['Kind'] -eq 'PowerShell') {
        [string]$TargetCmdName     = [string]$Resolved['CommandName'];
        [hashtable]$PowerShellArgs = $Parsed['PowerShellArguments'];
        [array]$AllocatedSecrets   = $Parsed['AllocatedSecureStrings'];
        [bool]$PreviousDaemonState = [bool]$GlobalVariable.Protected.IsBackgroundDaemon;

        try {
            $GlobalVariable.Protected.IsBackgroundDaemon = $true;
            $InvocationResult                            = & $TargetCmdName @PowerShellArgs;

            if ($null -ne $GlobalVariable.Private.Icinga.CheckResult) {
                $CompiledSlot  = $GlobalVariable.Private.Icinga.CheckResult;
                $ExitCode      = [int]$CompiledSlot.ExitCode;
                $CheckOutput   = [string]$CompiledSlot.Output;
                $CheckPerfData = @($CompiledSlot.PerformanceData);

                if ($InvocationResult -is [int]) {
                    $ExitCode = [int]$InvocationResult;
                }
            } elseif ($InvocationResult -is [int]) {
                $ExitCode = [int]$InvocationResult;
            } elseif ($null -ne $InvocationResult) {
                [string]$RawTextResult  = ((@($InvocationResult) | ForEach-Object { [string]$_ }) -join "`n");
                [hashtable]$SplitResult = Split-IcingaBinaryPluginOutput -RawOutput $RawTextResult;
                $CheckOutput            = [string]$SplitResult['Output'];
                $CheckPerfData          = @($SplitResult['PerformanceData']);
                $ExitCode               = 0;
            }
        } catch {
            $ExitCode    = 3;
            $CheckOutput = ('[UNKNOWN] Icinga Plugin Command Execution failed for "{0}": {1}' -f $TargetCmdName, $_.Exception.Message);
        } finally {
            $GlobalVariable.Protected.IsBackgroundDaemon = $PreviousDaemonState;
            $GlobalVariable.Private.Icinga.CheckResult   = $null;

            if ($null -ne $AllocatedSecrets) {
                foreach ($SecretObj in $AllocatedSecrets) {
                    if ($null -ne $SecretObj -and $SecretObj -is [System.IDisposable]) {
                        $SecretObj.Dispose();
                    }
                }
            }
        }
    } else {
        [string]$BinaryFullPath = [string]$Resolved['BinaryPath'];
        [string[]]$BinaryArgs   = $Parsed['BinaryArguments'];

        if ($BinaryFullPath.EndsWith('.ps1', [System.StringComparison]::OrdinalIgnoreCase)) {
            [array]$ScriptSecureStrings       = @();
            [hashtable]$MaskedScriptTokenText = @{ };
            [bool]$PrevScriptDaemonState      = [bool]$GlobalVariable.Protected.IsBackgroundDaemon;

            try {
                $GlobalVariable.Protected.IsBackgroundDaemon = $true;
                $global:LASTEXITCODE                         = $null;
                [hashtable]$ScriptNamedArgs                  = @{ };
                [array]$ScriptPositionalArgs                 = @();
                [string]$ScriptBindingError                  = '';
                $ExternalScriptMeta                          = $null;

                try {
                    $ExternalScriptMeta = Get-Command -Name $BinaryFullPath -CommandType ExternalScript -ErrorAction Stop;
                } catch {
                    $ExternalScriptMeta = $null;
                }

                [hashtable]$ExcludedScriptCommon = @{ };
                [array]$CommonScriptNames        = @(
                    'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
                    'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
                    'OutBuffer', 'PipelineVariable', 'ProgressAction', 'WhatIf', 'Confirm'
                );

                foreach ($CommonScriptName in $CommonScriptNames) {
                    $ExcludedScriptCommon[$CommonScriptName] = $true;
                }

                [hashtable]$ScriptParamMap  = @{ };
                [array]$ScriptOrderedParams = @();

                if ($null -ne $ExternalScriptMeta -and $null -ne $ExternalScriptMeta.Parameters -and $ExternalScriptMeta.Parameters.Count -gt 0) {
                    foreach ($ScriptParamEntry in $ExternalScriptMeta.Parameters.GetEnumerator()) {
                        $ScriptParamMeta = $ScriptParamEntry.Value;
                        if ($ExcludedScriptCommon.ContainsKey([string]$ScriptParamMeta.Name)) {
                            continue;
                        }

                        $ScriptParamMap[[string]$ScriptParamMeta.Name] = $ScriptParamMeta;

                        [bool]$TakesRemaining = $false;
                        if ($null -ne $ScriptParamMeta.ParameterSets) {
                            foreach ($ParamSetMeta in $ScriptParamMeta.ParameterSets.Values) {
                                if ($ParamSetMeta.ValueFromRemainingArguments) {
                                    $TakesRemaining = $true;
                                    break;
                                }
                            }
                        }

                        if (-not $TakesRemaining) {
                            $ScriptOrderedParams += $ScriptParamMeta;
                        }

                        if ($null -ne $ScriptParamMeta.Aliases) {
                            foreach ($ScriptAlias in $ScriptParamMeta.Aliases) {
                                if (-not [string]::IsNullOrWhiteSpace([string]$ScriptAlias)) {
                                    $ScriptParamMap[[string]$ScriptAlias] = $ScriptParamMeta;
                                }
                            }
                        }
                    }
                }

                if ($ScriptParamMap.Count -gt 0) {
                    for ($bIdx = 0; $bIdx -lt $BinaryArgs.Count; $bIdx++) {
                        [string]$CurrentArg = $BinaryArgs[$bIdx];
                        if ($CurrentArg.StartsWith('-') -and $CurrentArg.Length -gt 1) {
                            [string]$CandidateKey = $CurrentArg.TrimStart('-');
                            [int]$ColonPos        = $CandidateKey.IndexOf(':');

                            if ($ColonPos -gt 0) {
                                [string]$ColonKey = $CandidateKey.Substring(0, $ColonPos);
                                [string]$ColonVal = $CandidateKey.Substring($ColonPos + 1);

                                if ($ScriptParamMap.ContainsKey($ColonKey)) {
                                    $ColonParamMeta         = $ScriptParamMap[$ColonKey];
                                    [string]$ColonCanon     = [string]$ColonParamMeta.Name;
                                    [type]$ColonPType       = $ColonParamMeta.ParameterType;
                                    [bool]$IsColonNumOrEnum = ($ColonPType.IsEnum -or $ColonPType -eq [int] -or $ColonPType -eq [long] -or $ColonPType -eq [double] -or $ColonPType -eq [decimal] -or $ColonPType -eq [single] -or $ColonPType -eq [int16] -or $ColonPType -eq [byte] -or $ColonPType -eq [uint32] -or $ColonPType -eq [uint64] -or $ColonPType -eq [sbyte] -or $ColonPType -eq [uint16]);

                                    if ($ColonPType -eq [switch] -or $ColonPType -eq [System.Management.Automation.SwitchParameter] -or $ColonPType -eq [bool]) {
                                        $ScriptNamedArgs[$ColonCanon] = (ConvertFrom-ModuleBoolean -Value $ColonVal);
                                    } elseif ($ColonPType -eq [System.Security.SecureString]) {
                                        $MaskedScriptTokenText[$bIdx] = ('-{0}:********' -f $ColonKey);
                                        $ColonSec                     = ConvertTo-ModuleSecureString -InputObject $ColonVal;
                                        if ($null -eq $ColonSec) {
                                            $ScriptBindingError = ('[UNKNOWN] Failed to convert secret parameter "-{0}" on external PowerShell script "{1}" to SecureString' -f $ColonCanon, $Resolved['CommandName']);
                                            break;
                                        }
                                        $ScriptSecureStrings         += $ColonSec;
                                        $ScriptNamedArgs[$ColonCanon] = $ColonSec;
                                    } elseif ($ColonPType.IsArray -or $ColonPType -eq [array]) {
                                        if ($ColonVal.Length -gt 0) {
                                            $ScriptNamedArgs[$ColonCanon] = @( $ColonVal );
                                        }
                                    } elseif ($IsColonNumOrEnum) {
                                        if (-not [string]::IsNullOrWhiteSpace($ColonVal)) {
                                            $CoercedColonNum = $ColonVal -as $ColonPType;
                                            if ($null -ne $CoercedColonNum) {
                                                $ScriptNamedArgs[$ColonCanon] = $CoercedColonNum;
                                            } else {
                                                $ScriptNamedArgs[$ColonCanon] = $ColonVal;
                                            }
                                        }
                                    } else {
                                        $ScriptNamedArgs[$ColonCanon] = $ColonVal;
                                    }
                                    continue;
                                }
                            }

                            if ($ScriptParamMap.ContainsKey($CandidateKey)) {
                                $MatchedScriptParam      = $ScriptParamMap[$CandidateKey];
                                [string]$CanonScript     = [string]$MatchedScriptParam.Name;
                                [type]$ScriptPType       = $MatchedScriptParam.ParameterType;
                                [bool]$IsScriptNumOrEnum = ($ScriptPType.IsEnum -or $ScriptPType -eq [int] -or $ScriptPType -eq [long] -or $ScriptPType -eq [double] -or $ScriptPType -eq [decimal] -or $ScriptPType -eq [single] -or $ScriptPType -eq [int16] -or $ScriptPType -eq [byte] -or $ScriptPType -eq [uint32] -or $ScriptPType -eq [uint64] -or $ScriptPType -eq [sbyte] -or $ScriptPType -eq [uint16]);
                                [bool]$HasNextToken      = (($bIdx + 1) -lt $BinaryArgs.Count);
                                [bool]$NextIsKnownFlag   = $false;

                                if ($HasNextToken) {
                                    [string]$PeekArg = $BinaryArgs[$bIdx + 1];
                                    if ($PeekArg.StartsWith('-') -and $PeekArg.Length -gt 1) {
                                        [string]$PeekClean = $PeekArg.TrimStart('-');
                                        [int]$PeekColon    = $PeekClean.IndexOf(':');
                                        if ($PeekColon -gt 0) {
                                            $PeekClean = $PeekClean.Substring(0, $PeekColon);
                                        }
                                        if ($ScriptParamMap.ContainsKey($PeekClean)) {
                                            $NextIsKnownFlag = $true;
                                        }
                                    }
                                }

                                if ($ScriptPType -eq [switch] -or $ScriptPType -eq [System.Management.Automation.SwitchParameter]) {
                                    if ($HasNextToken -and -not $NextIsKnownFlag -and $BinaryArgs[$bIdx + 1].Trim() -match '^(?i:true|false|\$true|\$false|1|0|yes|no)$') {
                                        $bIdx++;
                                        $ScriptNamedArgs[$CanonScript] = (ConvertFrom-ModuleBoolean -Value $BinaryArgs[$bIdx]);
                                    } else {
                                        $ScriptNamedArgs[$CanonScript] = $true;
                                    }
                                } elseif ($ScriptPType.IsArray -or $ScriptPType -eq [array]) {
                                    [array]$CollectedItems = @();
                                    if ($ScriptNamedArgs.ContainsKey($CanonScript)) {
                                        $CollectedItems = @($ScriptNamedArgs[$CanonScript]);
                                    }

                                    while (($bIdx + 1) -lt $BinaryArgs.Count) {
                                        [string]$NextCandidate = $BinaryArgs[$bIdx + 1];
                                        if ($NextCandidate.StartsWith('-') -and $NextCandidate.Length -gt 1) {
                                            [string]$NextClean    = $NextCandidate.TrimStart('-');
                                            [int]$NextColonOffset = $NextClean.IndexOf(':');
                                            if ($NextColonOffset -gt 0) {
                                                $NextClean = $NextClean.Substring(0, $NextColonOffset);
                                            }
                                            if ($ScriptParamMap.ContainsKey($NextClean)) {
                                                break;
                                            }
                                        }

                                        $bIdx++;
                                        $CollectedItems += $BinaryArgs[$bIdx];
                                    }

                                    [bool]$IsSingleEmptyMacro = ($CollectedItems.Count -eq 1 -and $CollectedItems[0] -is [string] -and $CollectedItems[0].Length -eq 0 -and -not $ScriptNamedArgs.ContainsKey($CanonScript));
                                    if (-not $IsSingleEmptyMacro) {
                                        $ScriptNamedArgs[$CanonScript] = $CollectedItems;
                                    }
                                } elseif ($HasNextToken -and -not $NextIsKnownFlag) {
                                    if ($ScriptPType -eq [bool]) {
                                        $bIdx++;
                                        $ScriptNamedArgs[$CanonScript] = (ConvertFrom-ModuleBoolean -Value $BinaryArgs[$bIdx]);
                                    } elseif ($ScriptPType -eq [System.Security.SecureString]) {
                                        $bIdx++;
                                        $MaskedScriptTokenText[$bIdx] = '********';
                                        $ScriptSec                    = ConvertTo-ModuleSecureString -InputObject $BinaryArgs[$bIdx];
                                        if ($null -eq $ScriptSec) {
                                            $ScriptBindingError = ('[UNKNOWN] Failed to convert secret parameter "-{0}" on external PowerShell script "{1}" to SecureString' -f $CanonScript, $Resolved['CommandName']);
                                            break;
                                        }
                                        $ScriptSecureStrings          += $ScriptSec;
                                        $ScriptNamedArgs[$CanonScript] = $ScriptSec;
                                    } elseif ($IsScriptNumOrEnum) {
                                        $bIdx++;
                                        if (-not [string]::IsNullOrWhiteSpace($BinaryArgs[$bIdx])) {
                                            $CoercedScriptNum = $BinaryArgs[$bIdx] -as $ScriptPType;
                                            if ($null -ne $CoercedScriptNum) {
                                                $ScriptNamedArgs[$CanonScript] = $CoercedScriptNum;
                                            } else {
                                                $ScriptNamedArgs[$CanonScript] = $BinaryArgs[$bIdx];
                                            }
                                        }
                                    } else {
                                        $bIdx++;
                                        [bool]$SkipEmptyScriptSet = $false;
                                        if ($BinaryArgs[$bIdx].Length -eq 0 -and $null -ne $MatchedScriptParam.Attributes) {
                                            foreach ($ScriptAttr in $MatchedScriptParam.Attributes) {
                                                if ($ScriptAttr -is [System.Management.Automation.ValidateSetAttribute] -and ($ScriptAttr.ValidValues -notcontains '')) {
                                                    $SkipEmptyScriptSet = $true;
                                                    break;
                                                }
                                            }
                                        }

                                        if (-not $SkipEmptyScriptSet) {
                                            $ScriptNamedArgs[$CanonScript] = $BinaryArgs[$bIdx];
                                        }
                                    }
                                } else {
                                    $ScriptBindingError = ('[UNKNOWN] Missing value for parameter "-{0}" on external PowerShell script "{1}"' -f $CanonScript, $Resolved['CommandName']);
                                    break;
                                }
                                continue;
                            }
                        }

                        # Match unbound positional parameter metadata for SecureString/bool coercion and masking
                        $TargetPosMeta    = $null;
                        [int]$UnboundSeen = 0;

                        foreach ($OrderedMeta in $ScriptOrderedParams) {
                            [string]$OrdName = [string]$OrderedMeta.Name;
                            if ($ScriptNamedArgs.ContainsKey($OrdName)) {
                                continue;
                            }
                            if ($OrderedMeta.ParameterType -eq [switch] -or $OrderedMeta.ParameterType -eq [System.Management.Automation.SwitchParameter]) {
                                continue;
                            }
                            if ($UnboundSeen -eq $ScriptPositionalArgs.Count) {
                                $TargetPosMeta = $OrderedMeta;
                                break;
                            }
                            $UnboundSeen++;
                        }

                        if ($null -ne $TargetPosMeta -and $TargetPosMeta.ParameterType -eq [System.Security.SecureString]) {
                            $MaskedScriptTokenText[$bIdx] = '********';
                            $PosSec                       = ConvertTo-ModuleSecureString -InputObject $CurrentArg;
                            if ($null -eq $PosSec) {
                                $ScriptBindingError = ('[UNKNOWN] Failed to convert positional secret parameter "-{0}" on external PowerShell script "{1}" to SecureString' -f [string]$TargetPosMeta.Name, $Resolved['CommandName']);
                                break;
                            }
                            $ScriptSecureStrings  += $PosSec;
                            $ScriptPositionalArgs += $PosSec;
                        } elseif ($null -ne $TargetPosMeta -and $TargetPosMeta.ParameterType -eq [bool]) {
                            $ScriptPositionalArgs += (ConvertFrom-ModuleBoolean -Value $CurrentArg);
                        } else {
                            $ScriptPositionalArgs += $CurrentArg;
                        }
                    }
                } else {
                    $ScriptPositionalArgs = @($BinaryArgs);
                }

                if ($MaskedScriptTokenText.Count -gt 0) {
                    [array]$MaskedTokens = @( $BinaryFullPath );
                    for ($mIdx = 0; $mIdx -lt $BinaryArgs.Count; $mIdx++) {
                        if ($MaskedScriptTokenText.ContainsKey($mIdx)) {
                            $MaskedTokens += [string]$MaskedScriptTokenText[$mIdx];
                        } else {
                            $MaskedTokens += $BinaryArgs[$mIdx];
                        }
                    }

                    [array]$MaskedQuoted = @();
                    foreach ($RawMaskToken in $MaskedTokens) {
                        [string]$MaskText = [string]$RawMaskToken;
                        if ($MaskText.Length -eq 0) {
                            $MaskedQuoted += '""';
                        } elseif ($MaskText -notmatch '[\s"]') {
                            $MaskedQuoted += $MaskText;
                        } else {
                            $MaskBuilder      = New-Object System.Text.StringBuilder;
                            [void]$MaskBuilder.Append('"');
                            [int]$MaskSlashes = 0;

                            for ($mCharIdx = 0; $mCharIdx -lt $MaskText.Length; $mCharIdx++) {
                                [char]$MaskCh = $MaskText[$mCharIdx];
                                if ($MaskCh -eq '\') {
                                    $MaskSlashes++;
                                } elseif ($MaskCh -eq '"') {
                                    [void]$MaskBuilder.Append('\', ($MaskSlashes * 2 + 1));
                                    [void]$MaskBuilder.Append('"');
                                    $MaskSlashes = 0;
                                } else {
                                    if ($MaskSlashes -gt 0) {
                                        [void]$MaskBuilder.Append('\', $MaskSlashes);
                                        $MaskSlashes = 0;
                                    }
                                    [void]$MaskBuilder.Append($MaskCh);
                                }
                            }

                            if ($MaskSlashes -gt 0) {
                                [void]$MaskBuilder.Append('\', ($MaskSlashes * 2));
                            }

                            [void]$MaskBuilder.Append('"');
                            $MaskedQuoted += $MaskBuilder.ToString();
                        }
                    }

                    $FinalCommandLine = ($MaskedQuoted -join ' ');
                }

                if (-not [string]::IsNullOrEmpty($ScriptBindingError)) {
                    $ExitCode    = 3;
                    $CheckOutput = $ScriptBindingError;
                } else {
                    $ScriptRawOutput = & $BinaryFullPath @ScriptNamedArgs @ScriptPositionalArgs;

                    if ($null -ne $GlobalVariable.Private.Icinga.CheckResult) {
                        $CompiledScriptSlot = $GlobalVariable.Private.Icinga.CheckResult;
                        $ExitCode           = [int]$CompiledScriptSlot.ExitCode;
                        $CheckOutput        = [string]$CompiledScriptSlot.Output;
                        $CheckPerfData      = @($CompiledScriptSlot.PerformanceData);

                        if ($ScriptRawOutput -is [int]) {
                            $ExitCode = [int]$ScriptRawOutput;
                        }
                    } else {
                        [int]$ScriptExit = 0;
                        if ($null -ne $LASTEXITCODE) {
                            $ScriptExit = [int]$LASTEXITCODE;
                        }

                        [string]$JoinedScriptOut = ((@($ScriptRawOutput) | ForEach-Object { [string]$_ }) -join "`n");
                        [hashtable]$ParsedScript = Split-IcingaBinaryPluginOutput -RawOutput $JoinedScriptOut;
                        $CheckOutput             = [string]$ParsedScript['Output'];
                        $CheckPerfData           = @($ParsedScript['PerformanceData']);
                        $ExitCode                = $ScriptExit;
                    }
                }
            } catch {
                $ExitCode    = 3;
                $CheckOutput = ('[UNKNOWN] External PowerShell script "{0}" failed: {1}' -f $Resolved['CommandName'], $_.Exception.Message);
            } finally {
                $GlobalVariable.Protected.IsBackgroundDaemon = $PrevScriptDaemonState;
                $GlobalVariable.Private.Icinga.CheckResult   = $null;

                foreach ($ScriptSecObj in $ScriptSecureStrings) {
                    if ($null -ne $ScriptSecObj -and $ScriptSecObj -is [System.IDisposable]) {
                        $ScriptSecObj.Dispose();
                    }
                }
            }
        } else {
            # Native executable / batch script via System.Diagnostics.Process with full canonical path
            [bool]$IsBatchScript   = ($BinaryFullPath.EndsWith('.cmd', [System.StringComparison]::OrdinalIgnoreCase) -or $BinaryFullPath.EndsWith('.bat', [System.StringComparison]::OrdinalIgnoreCase));
            [string]$BatchArgError = '';

            if ($IsBatchScript) {
                foreach ($BatchCandidate in $BinaryArgs) {
                    [string]$BatchText = [string]$BatchCandidate;
                    if ($BatchText -match '[&|<>^\r\n"!]|%[^%]*%') {
                        $BatchArgError = ('[UNKNOWN] Argument for batch script "{0}" contains forbidden cmd.exe metacharacters' -f $Resolved['CommandName']);
                        break;
                    }
                }
            }

            if (-not [string]::IsNullOrEmpty($BatchArgError)) {
                $ExitCode    = 3;
                $CheckOutput = $BatchArgError;
            } else {
                [array]$EscapedArgs = @();

                foreach ($BinArg in $BinaryArgs) {
                    [string]$ArgText = [string]$BinArg;
                    if ($ArgText.Length -eq 0) {
                        $EscapedArgs += '""';
                    } elseif ($ArgText -notmatch '[\s"]') {
                        $EscapedArgs += $ArgText;
                    } else {
                        $ArgBuilder          = New-Object System.Text.StringBuilder;
                        [void]$ArgBuilder.Append('"');
                        [int]$PendingSlashes = 0;

                        for ($k = 0; $k -lt $ArgText.Length; $k++) {
                            [char]$Ch = $ArgText[$k];
                            if ($Ch -eq '\') {
                                $PendingSlashes++;
                            } elseif ($Ch -eq '"') {
                                [void]$ArgBuilder.Append('\', ($PendingSlashes * 2 + 1));
                                [void]$ArgBuilder.Append('"');
                                $PendingSlashes = 0;
                            } else {
                                if ($PendingSlashes -gt 0) {
                                    [void]$ArgBuilder.Append('\', $PendingSlashes);
                                    $PendingSlashes = 0;
                                }
                                [void]$ArgBuilder.Append($Ch);
                            }
                        }

                        if ($PendingSlashes -gt 0) {
                            [void]$ArgBuilder.Append('\', ($PendingSlashes * 2));
                        }

                        [void]$ArgBuilder.Append('"');
                        $EscapedArgs += $ArgBuilder.ToString();
                    }
                }

                $StartInfo                        = New-Object System.Diagnostics.ProcessStartInfo;
                $StartInfo.FileName               = $BinaryFullPath;
                $StartInfo.Arguments              = ($EscapedArgs -join ' ');
                $StartInfo.WorkingDirectory       = [System.IO.Path]::GetDirectoryName($BinaryFullPath);
                $StartInfo.UseShellExecute        = $false;
                $StartInfo.RedirectStandardOutput = $true;
                $StartInfo.RedirectStandardError  = $true;
                $StartInfo.CreateNoWindow         = $true;

                $Process                          = New-Object System.Diagnostics.Process;
                try {
                    $ProcWatch          = [System.Diagnostics.Stopwatch]::StartNew();
                    $Process.StartInfo  = $StartInfo;
                    [void]$Process.Start();

                    [int]$RootPid       = $Process.Id;
                    [bool]$TimedOut     = $false;
                    [string]$TimeoutMsg = '';
                    $StdoutTask         = $Process.StandardOutput.ReadToEndAsync();
                    $StderrTask         = $Process.StandardError.ReadToEndAsync();

                    if (-not $Process.WaitForExit($TimeoutMs)) {
                        $TimedOut   = $true;
                        $TimeoutMsg = ('[UNKNOWN] External binary check "{0}" timed out after {1}s' -f $Resolved['CommandName'], [System.Math]::Round(($TimeoutMs / 1000.0), 2));
                    } else {
                        $ProcWatch.Stop();
                        [int]$RemainingMs  = [System.Math]::Max(100, ($TimeoutMs - [int]$ProcWatch.ElapsedMilliseconds));
                        [bool]$StreamsDone = [System.Threading.Tasks.Task]::WaitAll(@( $StdoutTask, $StderrTask ), $RemainingMs);

                        if (-not $StreamsDone) {
                            $TimedOut   = $true;
                            $TimeoutMsg = ('[UNKNOWN] External binary check "{0}" timed out after {1}s while waiting for output streams to close' -f $Resolved['CommandName'], [System.Math]::Round(($TimeoutMs / 1000.0), 2));
                        }
                    }

                    if ($TimedOut) {
                        if ($env:OS -eq 'Windows_NT') {
                            [array]$DescendantHandles = @();
                            [hashtable]$KnownTreePids = @{ };
                            $KnownTreePids[$RootPid]  = $true;

                            try {
                                # Kill root first while keeping $Process open (SafeProcessHandle prevents Windows PID reuse)
                                try {
                                    if (-not $Process.HasExited) {
                                        if ($PSVersionTable.PSVersion.Major -ge 6) {
                                            try {
                                                $Process.Kill($true);
                                            } catch {
                                                $Process.Kill();
                                            }
                                        } else {
                                            $Process.Kill();
                                        }
                                    }
                                } catch {
                                    [void]$_;
                                }

                                for ($scanPass = 0; $scanPass -lt 3; $scanPass++) {
                                    [bool]$CimLookupFailed       = $false;
                                    [hashtable]$ChildrenByParent = @{ };

                                    try {
                                        [array]$AllProcs = @(Get-CimInstance -ClassName 'Win32_Process' -Property 'ProcessId', 'ParentProcessId' -ErrorAction Stop);
                                        foreach ($ProcRow in $AllProcs) {
                                            [int]$RowPid  = [int]$ProcRow.ProcessId;
                                            [int]$RowPpid = [int]$ProcRow.ParentProcessId;
                                            if ($RowPid -gt 0 -and $RowPid -ne $RowPpid) {
                                                if (-not $ChildrenByParent.ContainsKey($RowPpid)) {
                                                    $ChildrenByParent[$RowPpid] = New-Object System.Collections.ArrayList;
                                                }
                                                [void]$ChildrenByParent[$RowPpid].Add($RowPid);
                                            }
                                        }
                                    } catch {
                                        $CimLookupFailed  = $true;
                                        $ChildrenByParent = @{ };
                                    }

                                    if ($CimLookupFailed) {
                                        break;
                                    }

                                    $VisitQueue           = New-Object System.Collections.Queue;
                                    [hashtable]$PassSeen  = @{ };
                                    [int]$LiveFoundInPass = 0;

                                    foreach ($SeedPidObj in @($KnownTreePids.Keys)) {
                                        [int]$SeedPid       = [int]$SeedPidObj;
                                        $PassSeen[$SeedPid] = $true;
                                        $VisitQueue.Enqueue($SeedPid);
                                    }

                                    while ($VisitQueue.Count -gt 0) {
                                        [int]$CurrPid = [int]$VisitQueue.Dequeue();
                                        if ($ChildrenByParent.ContainsKey($CurrPid)) {
                                            foreach ($ChildPidObj in $ChildrenByParent[$CurrPid]) {
                                                [int]$NextPid = [int]$ChildPidObj;
                                                if (-not $PassSeen.ContainsKey($NextPid)) {
                                                    $PassSeen[$NextPid] = $true;
                                                    $VisitQueue.Enqueue($NextPid);

                                                    if (-not $KnownTreePids.ContainsKey($NextPid)) {
                                                        $KnownTreePids[$NextPid] = $true;
                                                        try {
                                                            $ChildHandle        = [System.Diagnostics.Process]::GetProcessById($NextPid);
                                                            $DescendantHandles += $ChildHandle;
                                                            if (-not $ChildHandle.HasExited) {
                                                                $LiveFoundInPass++;
                                                                $ChildHandle.Kill();
                                                            }
                                                        } catch {
                                                            [void]$_;
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    if ($LiveFoundInPass -eq 0) {
                                        break;
                                    }
                                }

                                try {
                                    [void]$Process.WaitForExit(2000);
                                } catch {
                                    [void]$_;
                                }

                                foreach ($DescHandle in $DescendantHandles) {
                                    if ($null -ne $DescHandle) {
                                        try {
                                            [void]$DescHandle.WaitForExit(2000);
                                        } catch {
                                            [void]$_;
                                        }
                                    }
                                }
                            } finally {
                                foreach ($DescHandle in $DescendantHandles) {
                                    if ($null -ne $DescHandle) {
                                        $DescHandle.Dispose();
                                    }
                                }
                            }
                        } else {
                            [array]$UnixDescendantHandles = @();

                            try {
                                [string]$PgrepPath = '/usr/bin/pgrep';
                                if (-not [System.IO.File]::Exists($PgrepPath)) {
                                    $PgrepPath = 'pgrep';
                                }

                                $UnixQueue           = New-Object System.Collections.Queue;
                                [hashtable]$UnixSeen = @{ };
                                $UnixSeen[$RootPid]  = $true;
                                $UnixQueue.Enqueue($RootPid);

                                while ($UnixQueue.Count -gt 0) {
                                    [int]$ParentUnixPid = [int]$UnixQueue.Dequeue();
                                    $PgrepProcess       = New-Object System.Diagnostics.Process;
                                    try {
                                        $PgrepInfo                        = New-Object System.Diagnostics.ProcessStartInfo;
                                        $PgrepInfo.FileName               = $PgrepPath;
                                        $PgrepInfo.Arguments              = ('-P {0}' -f $ParentUnixPid);
                                        $PgrepInfo.UseShellExecute        = $false;
                                        $PgrepInfo.RedirectStandardOutput = $true;
                                        $PgrepInfo.RedirectStandardError  = $true;
                                        $PgrepInfo.CreateNoWindow         = $true;
                                        $PgrepProcess.StartInfo           = $PgrepInfo;
                                        [void]$PgrepProcess.Start();
                                        [string]$PgrepOut                 = $PgrepProcess.StandardOutput.ReadToEnd();
                                        [void]$PgrepProcess.WaitForExit(1000);

                                        if (-not [string]::IsNullOrWhiteSpace($PgrepOut)) {
                                            foreach ($PidToken in ($PgrepOut -split '\s+')) {
                                                [int]$ParsedUnixChild = 0;
                                                if ([int]::TryParse($PidToken, [ref]$ParsedUnixChild) -and $ParsedUnixChild -gt 0 -and -not $UnixSeen.ContainsKey($ParsedUnixChild)) {
                                                    $UnixSeen[$ParsedUnixChild] = $true;
                                                    $UnixQueue.Enqueue($ParsedUnixChild);
                                                    try {
                                                        $UnixChildHandle        = [System.Diagnostics.Process]::GetProcessById($ParsedUnixChild);
                                                        $UnixDescendantHandles += $UnixChildHandle;
                                                    } catch {
                                                        [void]$_;
                                                    }
                                                }
                                            }
                                        }
                                    } catch {
                                        [void]$_;
                                    } finally {
                                        $PgrepProcess.Dispose();
                                    }
                                }

                                try {
                                    if (-not $Process.HasExited) {
                                        if ($PSVersionTable.PSVersion.Major -ge 6) {
                                            $Process.Kill($true);
                                        } else {
                                            $Process.Kill();
                                        }
                                    }
                                } catch {
                                    [void]$_;
                                }

                                foreach ($UnixDescHandle in $UnixDescendantHandles) {
                                    if ($null -ne $UnixDescHandle) {
                                        try {
                                            if (-not $UnixDescHandle.HasExited) {
                                                $UnixDescHandle.Kill();
                                            }
                                        } catch {
                                            [void]$_;
                                        }
                                    }
                                }

                                try {
                                    [void]$Process.WaitForExit(2000);
                                } catch {
                                    [void]$_;
                                }

                                foreach ($UnixDescHandle in $UnixDescendantHandles) {
                                    if ($null -ne $UnixDescHandle) {
                                        try {
                                            [void]$UnixDescHandle.WaitForExit(2000);
                                        } catch {
                                            [void]$_;
                                        }
                                    }
                                }
                            } finally {
                                foreach ($UnixDescHandle in $UnixDescendantHandles) {
                                    if ($null -ne $UnixDescHandle) {
                                        $UnixDescHandle.Dispose();
                                    }
                                }
                            }
                        }

                        try {
                            [void][System.Threading.Tasks.Task]::WaitAll(@( $StdoutTask, $StderrTask ), 500);
                        } catch {
                            [void]$_;
                        }

                        $ExitCode    = 3;
                        $CheckOutput = $TimeoutMsg;
                    } else {
                        [string]$StdoutText = '';
                        [string]$StderrText = '';

                        if ($StdoutTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                            $StdoutText = [string]$StdoutTask.Result;
                        }
                        if ($StderrTask.Status -eq [System.Threading.Tasks.TaskStatus]::RanToCompletion) {
                            $StderrText = [string]$StderrTask.Result;
                        }

                        [string]$Effective = $StdoutText;

                        if ([string]::IsNullOrWhiteSpace($Effective) -and -not [string]::IsNullOrWhiteSpace($StderrText)) {
                            $Effective = $StderrText;
                        }

                        [hashtable]$SplitBinary = Split-IcingaBinaryPluginOutput -RawOutput $Effective;
                        $CheckOutput            = [string]$SplitBinary['Output'];
                        $CheckPerfData          = @($SplitBinary['PerformanceData']);
                        $ExitCode               = [int]$Process.ExitCode;
                    }
                } catch {
                    $ExitCode    = 3;
                    $CheckOutput = ('[UNKNOWN] External binary check "{0}" failed to execute: {1}' -f $Resolved['CommandName'], $_.Exception.Message);
                } finally {
                    $Process.Dispose();
                }
            }
        }
    }

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

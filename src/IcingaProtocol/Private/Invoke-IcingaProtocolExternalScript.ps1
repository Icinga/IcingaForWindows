<#
.SYNOPSIS
Bind CLI arguments and execute an approved external PowerShell check script

.DESCRIPTION
Invoke-IcingaProtocolExternalScript introspects an external .ps1 script inside
Get-ModuleBinaryDirectory via Get-ModuleCommandParameterMap, parses CLI-style
BinaryArguments ('-Param:Val', '-Param Val', switches, multi-item arrays and
positional parameters), coerces values through ConvertTo-ModuleParameterValue,
masks any SecureString parameter tokens as '********' in the returned
CommandLine via Format-ModuleCommandLineArguments, and executes the script
in-process via Invoke-ModulePowerShellCommand -UseLastExitCode.

.PARAMETER ScriptPath
| Name       | Type          | Description                                             | Default |
|------------|---------------|---------------------------------------------------------|---------|
| ScriptPath | System.String | Full canonical path to the approved .ps1 check script.  | ''      |

.PARAMETER CommandName
| Name        | Type          | Description                                             | Default |
|-------------|---------------|---------------------------------------------------------|---------|
| CommandName | System.String | Display file name of the script for error messages.     | ''      |

.PARAMETER BinaryArguments
| Name            | Type            | Description                                         | Default |
|-----------------|-----------------|-----------------------------------------------------|---------|
| BinaryArguments | System.String[] | Ordered CLI tokens produced by macro resolution.    | @()     |

.PARAMETER DefaultCommandLine
| Name               | Type          | Description                                             | Default |
|--------------------|---------------|---------------------------------------------------------|---------|
| DefaultCommandLine | System.String | Pre-rendered command line when no secret masking occurs.| ''      |

.OUTPUTS
System.Collections.Hashtable -- Hashtable containing ExitCode, Output,
PerformanceData and CommandLine.

.EXAMPLE
PS> Invoke-IcingaProtocolExternalScript -ScriptPath 'C:\ProgramData\IcingaForWindows\Binaries\check_custom.ps1' -CommandName 'check_custom.ps1' -BinaryArguments @('-ExitWith', '0')

Binds the parameters of check_custom.ps1 and executes it in-process.

.NOTES
Delegates execution and deterministic SecureString disposal to
Invoke-ModulePowerShellCommand.
#>
function Invoke-IcingaProtocolExternalScript()
{
    param (
        [string]$ScriptPath         = '',
        [string]$CommandName        = '',
        [string[]]$BinaryArguments  = @(),
        [string]$DefaultCommandLine = ''
    );

    [array]$ScriptSecureStrings       = @();
    [hashtable]$MaskedScriptTokenText = @{ };
    [hashtable]$ScriptNamedArgs       = @{ };
    [array]$ScriptPositionalArgs      = @();
    [string]$ScriptBindingError       = '';
    [string]$FinalCommandLine         = $DefaultCommandLine;
    $ExternalScriptMeta               = $null;

    <#
    External .ps1 scripts inside Get-ModuleBinaryDirectory are resolved with Kind = 'Binary',
    so ConvertFrom-IcingaProtocolMacros produces a flat string[] of CLI tokens ($BinaryArguments)
    rather than a PowerShell parameter hashtable.

    To execute the .ps1 script safely in-process via '&' (without spawning powershell.exe and
    without dot-sourcing into worker scope), we:
    1. Inspect the script's declared param() block via Get-Command -CommandType ExternalScript.
    2. Walk $BinaryArguments left-to-right to recognize:
       - Colon-bound arguments (-Param:Value, including repeated -Tags:a -Tags:b on arrays)
       - Space-separated named flags (-Param Value, [switch] flags, and greedy multi-token arrays
         that stop as soon as the next known -Param flag is encountered)
       - Unbound positional arguments matched in declaration/Position order
    3. Coerce values through ConvertTo-ModuleParameterValue so [bool], [switch], numeric/enum,
       [ValidateSet] and [securestring] parameters behave identically to native plugins.
    4. Replace any token bound to a [securestring] parameter with '********' in FinalCommandLine
       so secrets never leak into Icinga's CheckResult.command or debug logs.
    5. Execute via Invoke-ModulePowerShellCommand -UseLastExitCode so scripts using either
       New-IcingaPlugin (.Compile()) or classic Write-Output + exit $code work seamlessly.
    #>

    # 1. Introspect ExternalScript parameter metadata to enable typed binding and SecureString masking
    try {
        $ExternalScriptMeta = Get-Command -Name $ScriptPath -CommandType ExternalScript -ErrorAction Stop;
    } catch {
        $ExternalScriptMeta = $null;
    }

    $RawParameters = $null;
    if ($null -ne $ExternalScriptMeta) {
        $RawParameters = $ExternalScriptMeta.Parameters;
    }

    # Build case-insensitive parameter/alias lookup and ordered positional parameter list (excluding CommonParameters)
    [hashtable]$ParamBundle     = Get-ModuleCommandParameterMap -Parameters $RawParameters;
    [hashtable]$ScriptParamMap  = $ParamBundle['Lookup'];
    [array]$ScriptOrderedParams = $ParamBundle['Positional'];

    if ($ScriptParamMap.Count -gt 0 -and $null -ne $BinaryArguments) {
        for ($bIdx = 0; $bIdx -lt $BinaryArguments.Count; $bIdx++) {
            [string]$CurrentArg = $BinaryArguments[$bIdx];

            # Check whether the current CLI token starts with '-' and matches a declared parameter or alias
            if ($CurrentArg.StartsWith('-') -and $CurrentArg.Length -gt 1) {
                [string]$CandidateKey = $CurrentArg.TrimStart('-');
                [int]$ColonPos        = $CandidateKey.IndexOf(':');

                # 2a. Colon-bound syntax (-Param:Value, e.g. -UseSsl:False, -Secret:MyPass, -Tags:a -Tags:b)
                if ($ColonPos -gt 0) {
                    [string]$ColonKey = $CandidateKey.Substring(0, $ColonPos);
                    [string]$ColonVal = $CandidateKey.Substring($ColonPos + 1);

                    if ($ScriptParamMap.ContainsKey($ColonKey)) {
                        $ColonParamMeta          = $ScriptParamMap[$ColonKey];
                        [string]$ColonCanon      = [string]$ColonParamMeta.Name;
                        [hashtable]$ColonCoerced = ConvertTo-ModuleParameterValue -ParameterMetadata $ColonParamMeta -RawValue $ColonVal;

                        # Mask secret token in the rendered command line while keeping the parameter prefix visible
                        if ($ColonCoerced['IsSecret']) {
                            $MaskedScriptTokenText[$bIdx] = ('-{0}:********' -f $ColonKey);
                        }

                        if ($ColonCoerced['Status'] -eq 'Error') {
                            $ScriptBindingError = ('[UNKNOWN] Failed to convert secret parameter "-{0}" on external PowerShell script "{1}" to SecureString' -f $ColonCanon, $CommandName);
                            break;
                        }

                        if ($null -ne $ColonCoerced['AllocatedSecret']) {
                            $ScriptSecureStrings += $ColonCoerced['AllocatedSecret'];
                        }

                        if ($ColonCoerced['Status'] -eq 'Bound') {
                            # Append when the same array parameter is passed multiple times via -Tags:a -Tags:b
                            if (($ColonParamMeta.ParameterType.IsArray -or $ColonParamMeta.ParameterType -eq [array]) -and $ScriptNamedArgs.ContainsKey($ColonCanon)) {
                                [array]$CombinedColon         = @($ScriptNamedArgs[$ColonCanon]) + @($ColonCoerced['Value']);
                                $ScriptNamedArgs[$ColonCanon] = $CombinedColon;
                            } else {
                                $ScriptNamedArgs[$ColonCanon] = $ColonCoerced['Value'];
                            }
                        }
                        continue;
                    }
                }

                # 2b. Standard named parameter token (-Param or -Param Value)
                if ($ScriptParamMap.ContainsKey($CandidateKey)) {
                    $MatchedScriptParam    = $ScriptParamMap[$CandidateKey];
                    [string]$CanonScript   = [string]$MatchedScriptParam.Name;
                    [type]$ScriptPType     = $MatchedScriptParam.ParameterType;
                    [bool]$HasNextToken    = (($bIdx + 1) -lt $BinaryArguments.Count);
                    [bool]$NextIsKnownFlag = $false;

                    # Peek ahead one token to avoid swallowing the next known '-Param' flag as a value
                    # (for example when a valueless flag precedes '-ForceCheck' or '-UseSsl:False')
                    if ($HasNextToken) {
                        [string]$PeekArg = $BinaryArguments[$bIdx + 1];
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
                        # Switches default to $true when standalone (-ForceCheck), but also consume an explicit
                        # boolean literal when passed as '-ForceCheck False' from a CLI-style template
                        if ($HasNextToken -and -not $NextIsKnownFlag -and $BinaryArguments[$bIdx + 1].Trim() -match '^(?i:true|false|\$true|\$false|1|0|yes|no)$') {
                            $bIdx++;
                            $ScriptNamedArgs[$CanonScript] = (ConvertFrom-ModuleBoolean -Value $BinaryArguments[$bIdx]);
                        } else {
                            $ScriptNamedArgs[$CanonScript] = $true;
                        }
                    } elseif ($ScriptPType.IsArray -or $ScriptPType -eq [array]) {
                        # Array parameters consume all following non-flag tokens until the next known '-Param'
                        # (supports both '-Targets a b' and repeated '-Targets a -Targets b' via repeat_key)
                        [array]$CollectedItems = @();
                        if ($ScriptNamedArgs.ContainsKey($CanonScript)) {
                            $CollectedItems = @($ScriptNamedArgs[$CanonScript]);
                        }

                        while (($bIdx + 1) -lt $BinaryArguments.Count) {
                            [string]$NextCandidate = $BinaryArguments[$bIdx + 1];
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
                            $CollectedItems += $BinaryArguments[$bIdx];
                        }

                        # When an external .ps1 script is invoked via CLI tokens (Kind = 'Binary'), an unpopulated
                        # scalar Icinga macro ($targets$ = "") arrives as a single empty string token ('-Targets', '').
                        # Skip binding in that single-token case so the script's declared default array stays intact.
                        [bool]$IsSingleEmptyMacro = ($CollectedItems.Count -eq 1 -and $CollectedItems[0] -is [string] -and $CollectedItems[0].Length -eq 0 -and -not $ScriptNamedArgs.ContainsKey($CanonScript));
                        if (-not $IsSingleEmptyMacro) {
                            [hashtable]$ArrCoerced = ConvertTo-ModuleParameterValue -ParameterMetadata $MatchedScriptParam -RawValue $CollectedItems;
                            if ($ArrCoerced['Status'] -eq 'Bound') {
                                $ScriptNamedArgs[$CanonScript] = $ArrCoerced['Value'];
                            }
                        }
                    } elseif ($HasNextToken -and -not $NextIsKnownFlag) {
                        # Scalar parameter (-String, -Int, -Bool, -Enum, -SecureString): consume exactly one value token
                        $bIdx++;
                        [hashtable]$ScalarCoerced = ConvertTo-ModuleParameterValue -ParameterMetadata $MatchedScriptParam -RawValue $BinaryArguments[$bIdx];

                        if ($ScalarCoerced['IsSecret']) {
                            $MaskedScriptTokenText[$bIdx] = '********';
                        }

                        if ($ScalarCoerced['Status'] -eq 'Error') {
                            $ScriptBindingError = ('[UNKNOWN] Failed to convert secret parameter "-{0}" on external PowerShell script "{1}" to SecureString' -f $CanonScript, $CommandName);
                            break;
                        }

                        if ($null -ne $ScalarCoerced['AllocatedSecret']) {
                            $ScriptSecureStrings += $ScalarCoerced['AllocatedSecret'];
                        }

                        if ($ScalarCoerced['Status'] -eq 'Bound') {
                            $ScriptNamedArgs[$CanonScript] = $ScalarCoerced['Value'];
                        }
                    } else {
                        # Non-switch scalar parameter appeared with no value (either at the end or right before another flag)
                        $ScriptBindingError = ('[UNKNOWN] Missing value for parameter "-{0}" on external PowerShell script "{1}"' -f $CanonScript, $CommandName);
                        break;
                    }
                    continue;
                }
            }

            # 2c. Unrecognized token or positional argument (e.g. skip_key = $true):
            #     find the next unbound non-switch positional parameter so SecureString/bool values are still coerced and masked
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
                [hashtable]$PosCoerced        = ConvertTo-ModuleParameterValue -ParameterMetadata $TargetPosMeta -RawValue $CurrentArg;

                if ($PosCoerced['Status'] -eq 'Error') {
                    $ScriptBindingError = ('[UNKNOWN] Failed to convert positional secret parameter "-{0}" on external PowerShell script "{1}" to SecureString' -f [string]$TargetPosMeta.Name, $CommandName);
                    break;
                }

                $ScriptSecureStrings  += $PosCoerced['AllocatedSecret'];
                $ScriptPositionalArgs += $PosCoerced['Value'];
            } elseif ($null -ne $TargetPosMeta -and $TargetPosMeta.ParameterType -eq [bool]) {
                $ScriptPositionalArgs += (ConvertFrom-ModuleBoolean -Value $CurrentArg);
            } else {
                $ScriptPositionalArgs += $CurrentArg;
            }
        }
    } elseif ($null -ne $BinaryArguments) {
        # Script declares no formal param() block (uses $args directly): forward all tokens positionally
        $ScriptPositionalArgs = @($BinaryArguments);
    }

    # 3. Rebuild the displayed CommandLine string if any token was masked as a SecureString secret
    if ($MaskedScriptTokenText.Count -gt 0) {
        [array]$MaskedTokens = @( $ScriptPath );

        for ($mIdx = 0; $mIdx -lt $BinaryArguments.Count; $mIdx++) {
            if ($MaskedScriptTokenText.ContainsKey($mIdx)) {
                $MaskedTokens += [string]$MaskedScriptTokenText[$mIdx];
            } else {
                $MaskedTokens += $BinaryArguments[$mIdx];
            }
        }

        $FinalCommandLine = Format-ModuleCommandLineArguments -Arguments $MaskedTokens;
    }

    # 4. Abort early with UNKNOWN (3) and dispose already-allocated SecureStrings if binding validation failed
    if (-not [string]::IsNullOrEmpty($ScriptBindingError)) {
        foreach ($ScriptSecObj in $ScriptSecureStrings) {
            if ($null -ne $ScriptSecObj -and $ScriptSecObj -is [System.IDisposable]) {
                $ScriptSecObj.Dispose();
            }
        }

        return @{
            'ExitCode'        = 3;
            'Output'          = $ScriptBindingError;
            'PerformanceData' = @();
            'CommandLine'     = $FinalCommandLine;
        };
    }

    # 5. Execute the external .ps1 script in-process via '&' (never dot-sourced), capturing either
    #    Private.Icinga.CheckResult (when the script uses New-IcingaPlugin) or stdout + $LASTEXITCODE
    [hashtable]$InvokeParams = @{
        'Command'             = $ScriptPath;
        'NamedArguments'      = $ScriptNamedArgs;
        'PositionalArguments' = $ScriptPositionalArgs;
        'AllocatedSecrets'    = $ScriptSecureStrings;
        'UseLastExitCode'     = $true;
        'ErrorContext'        = ('External PowerShell script "{0}" failed' -f $CommandName);
    };
    [hashtable]$ExecResult   = Invoke-ModulePowerShellCommand @InvokeParams;

    return @{
        'ExitCode'        = [int]$ExecResult['ExitCode'];
        'Output'          = [string]$ExecResult['Output'];
        'PerformanceData' = [array]$ExecResult['PerformanceData'];
        'CommandLine'     = $FinalCommandLine;
    };
}

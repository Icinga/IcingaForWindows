<#
.SYNOPSIS
Parse Icinga 2 ExecuteCommand macros into typed PowerShell or binary arguments

.DESCRIPTION
ConvertFrom-IcingaProtocolMacros translates the macros dictionary of an Icinga 2
event::ExecuteCommand message into either a typed PowerShell splatting hashtable
or an ordered string array of CLI arguments for external binaries, plus a
human-readable CommandLine string with SecureString secrets masked as '********'.

Two Icinga 2 delivery modes are supported seamlessly across Windows PowerShell
5.1 (Dictionary[string, object]) and PowerShell 7+ (Hashtable):
1. Active ifw-api template (macros.ifw_api_arguments present): resolves single
   and embedded $macro$ references, evaluates set_if conditions, orders binary
   arguments by order, honors skip_key and repeat_key, and rejects unknown
   PowerShell parameters that carry a non-empty value with IWKB001001.
2. Fallback without ifw-api (macros.ifw_api_arguments absent): ignores internal
   ifw_api_* and IcingaPowerShellBase_* variables, maps PowerShell parameters by
   exact parameter/alias name or the IcingaCheck<Name>_<Type>_<Param> convention
   (returning IWKB001000 on unmapped custom variables), and enforces '-' or '/'
   prefixes on custom variables passed to external binaries (returning IWKB001002
   when unprefixed custom variables are present).

.PARAMETER ResolvedCommand
| Name            | Type                         | Description                                                  | Default |
|-----------------|------------------------------|--------------------------------------------------------------|---------|
| ResolvedCommand | System.Collections.Hashtable | Command descriptor returned by Resolve-IcingaProtocolCommand.| @{}     |

.PARAMETER Macros
| Name   | Type          | Description                                                           | Default |
|--------|---------------|-----------------------------------------------------------------------|---------|
| Macros | System.Object | Deserialized macros dictionary or object from event::ExecuteCommand.  | $null   |

.OUTPUTS
System.Collections.Hashtable -- Parsed argument bundle containing Status,
PowerShellArguments, BinaryArguments, AllocatedSecureStrings, CommandLine,
Message, KnowledgeBaseId and ReturnCodeKey.

.EXAMPLE
PS> $resolved = Resolve-IcingaProtocolCommand -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheckDirectory' }
PS> ConvertFrom-IcingaProtocolMacros -ResolvedCommand $resolved -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheckDirectory'; 'Path' = 'C:\Temp' }

Maps the Path macro to Invoke-IcingaCheckDirectory's -Path parameter.

.NOTES
Callers must dispose every entry in AllocatedSecureStrings once plugin execution
completes. On validation errors, any SecureString allocated earlier in the same
call is disposed before returning.
#>
function ConvertFrom-IcingaProtocolMacros()
{
    param (
        [hashtable]$ResolvedCommand = @{ },
        [object]$Macros             = $null
    );

    [string]$Kind                  = [string]$ResolvedCommand['Kind'];
    [string]$CommandName           = [string]$ResolvedCommand['CommandName'];
    [string]$BinaryPath            = [string]$ResolvedCommand['BinaryPath'];
    $CommandParameters             = $ResolvedCommand['Parameters'];

    # Normalize Macros into an ordinal OrderedDictionary (preserving -p vs -P) plus case-insensitive lookup fallback
    $MacroMap                      = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::Ordinal);
    [hashtable]$MacroMapIgnoreCase = @{ };

    if ($Macros -is [System.Collections.IDictionary]) {
        foreach ($Key in $Macros.Keys) {
            [string]$MacroKeyStr = [string]$Key;
            if ([string]::IsNullOrWhiteSpace($MacroKeyStr)) {
                continue;
            }

            $MacroMap[$MacroKeyStr] = $Macros[$Key];
            if (-not $MacroMapIgnoreCase.ContainsKey($MacroKeyStr) -or $null -eq $MacroMapIgnoreCase[$MacroKeyStr]) {
                $MacroMapIgnoreCase[$MacroKeyStr] = $Macros[$Key];
            }
        }
    } elseif ($null -ne $Macros) {
        foreach ($Prop in $Macros.PSObject.Properties) {
            [string]$PropKeyStr = [string]$Prop.Name;
            if ([string]::IsNullOrWhiteSpace($PropKeyStr)) {
                continue;
            }

            $MacroMap[$PropKeyStr] = $Prop.Value;
            if (-not $MacroMapIgnoreCase.ContainsKey($PropKeyStr) -or $null -eq $MacroMapIgnoreCase[$PropKeyStr]) {
                $MacroMapIgnoreCase[$PropKeyStr] = $Prop.Value;
            }
        }
    }

    # Build case-insensitive parameter & alias lookup for PowerShell check commands
    [hashtable]$ParamLookup      = @{ };
    [hashtable]$ExcludedCommon   = @{ };
    [array]$CommonParameterNames = @(
        'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
        'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
        'OutBuffer', 'PipelineVariable', 'ProgressAction', 'WhatIf', 'Confirm'
    );

    foreach ($CommonName in $CommonParameterNames) {
        $ExcludedCommon[$CommonName] = $true;
    }

    if ($Kind -eq 'PowerShell' -and $null -ne $CommandParameters) {
        foreach ($ParamEntry in $CommandParameters.GetEnumerator()) {
            $ParamMeta = $ParamEntry.Value;
            if ($ExcludedCommon.ContainsKey([string]$ParamMeta.Name)) {
                continue;
            }

            $ParamLookup[[string]$ParamMeta.Name] = $ParamMeta;

            if ($null -ne $ParamMeta.Aliases) {
                foreach ($AliasName in $ParamMeta.Aliases) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$AliasName)) {
                        $ParamLookup[[string]$AliasName] = $ParamMeta;
                    }
                }
            }
        }
    }

    [bool]$HasApiArguments = $false;
    [object]$RawApiArgsObj = $null;

    if ($MacroMap.Contains('ifw_api_arguments')) {
        $RawApiArgsObj = $MacroMap['ifw_api_arguments'];
    } elseif ($MacroMapIgnoreCase.ContainsKey('ifw_api_arguments')) {
        $RawApiArgsObj = $MacroMapIgnoreCase['ifw_api_arguments'];
    }

    if ($null -ne $RawApiArgsObj -and ($RawApiArgsObj -is [System.Collections.IDictionary] -or $RawApiArgsObj -is [PSCustomObject])) {
        $HasApiArguments = $true;
    }

    [hashtable]$PowerShellArguments   = @{ };
    [hashtable]$MaskedParameters      = @{ };
    [array]$AllocatedSecureStrings    = @();
    [array]$PendingPowerShellBindings = @();
    [string[]]$BinaryArguments        = @();

    if ($HasApiArguments) {
        # -------------------------------------------------------------------
        # Mode A: ifw-api active (macros.ifw_api_arguments present)
        # -------------------------------------------------------------------
        $ApiArgEntries = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::Ordinal);

        if ($RawApiArgsObj -is [System.Collections.IDictionary]) {
            foreach ($ArgKey in $RawApiArgsObj.Keys) {
                $ApiArgEntries[[string]$ArgKey] = $RawApiArgsObj[$ArgKey];
            }
        } else {
            foreach ($ArgProp in $RawApiArgsObj.PSObject.Properties) {
                $ApiArgEntries[[string]$ArgProp.Name] = $ArgProp.Value;
            }
        }

        [array]$OrderedBinarySpecs = @();
        [int]$OriginalIndex        = 0;

        foreach ($ArgName in $ApiArgEntries.Keys) {
            [object]$RawArgSpec     = $ApiArgEntries[$ArgName];
            [bool]$IsStructuredSpec = ($RawArgSpec -is [System.Collections.IDictionary] -or $RawArgSpec -is [PSCustomObject]);
            $ArgSpec                = [ordered]@{ };

            if ($RawArgSpec -is [System.Collections.IDictionary]) {
                foreach ($SpecKey in $RawArgSpec.Keys) {
                    $ArgSpec[[string]$SpecKey] = $RawArgSpec[$SpecKey];
                }
            } elseif ($RawArgSpec -is [PSCustomObject]) {
                foreach ($SpecProp in $RawArgSpec.PSObject.Properties) {
                    $ArgSpec[[string]$SpecProp.Name] = $SpecProp.Value;
                }
            } else {
                $ArgSpec['value'] = $RawArgSpec;
            }

            [bool]$HasSetIf      = ($ArgSpec.Contains('set_if') -and $null -ne $ArgSpec['set_if']);
            [bool]$HasValueField = ($ArgSpec.Contains('value') -and $null -ne $ArgSpec['value']);

            # Evaluate set_if when defined
            if ($HasSetIf) {
                [object]$SetIfExpr  = $ArgSpec['set_if'];
                [bool]$SetIfIsSet   = $false;
                [object]$SetIfValue = $null;

                if ($SetIfExpr -isnot [string]) {
                    $SetIfIsSet = ($null -ne $SetIfExpr);
                    $SetIfValue = $SetIfExpr;
                } elseif ($SetIfExpr -match '^\$([A-Za-z0-9_.:-]+)\$$') {
                    [string]$SetIfRef = $Matches[1];
                    if ($MacroMap.Contains($SetIfRef) -and $null -ne $MacroMap[$SetIfRef]) {
                        $SetIfIsSet = $true;
                        $SetIfValue = $MacroMap[$SetIfRef];
                    } elseif ($MacroMapIgnoreCase.ContainsKey($SetIfRef) -and $null -ne $MacroMapIgnoreCase[$SetIfRef]) {
                        $SetIfIsSet = $true;
                        $SetIfValue = $MacroMapIgnoreCase[$SetIfRef];
                    }
                } else {
                    $TokenMatches = [regex]::Matches($SetIfExpr, '\$\$|\$([A-Za-z0-9_.:-]+)\$');
                    if ($TokenMatches.Count -gt 0) {
                        [bool]$AllTokensFound = $true;
                        $SetIfBuilder         = New-Object System.Text.StringBuilder;
                        [int]$SetIfPos        = 0;

                        foreach ($TokenMatch in $TokenMatches) {
                            if ($TokenMatch.Index -gt $SetIfPos) {
                                [void]$SetIfBuilder.Append($SetIfExpr.Substring($SetIfPos, ($TokenMatch.Index - $SetIfPos)));
                            }

                            if ($TokenMatch.Value -eq '$$') {
                                [void]$SetIfBuilder.Append('$');
                            } else {
                                [string]$TokenName = $TokenMatch.Groups[1].Value;
                                [object]$TokenVal  = $null;
                                if ($MacroMap.Contains($TokenName)) {
                                    $TokenVal = $MacroMap[$TokenName];
                                } elseif ($MacroMapIgnoreCase.ContainsKey($TokenName)) {
                                    $TokenVal = $MacroMapIgnoreCase[$TokenName];
                                }

                                if ($null -eq $TokenVal) {
                                    $AllTokensFound = $false;
                                    break;
                                }
                                [void]$SetIfBuilder.Append([string]$TokenVal);
                            }

                            $SetIfPos = $TokenMatch.Index + $TokenMatch.Length;
                        }

                        if ($AllTokensFound) {
                            if ($SetIfPos -lt $SetIfExpr.Length) {
                                [void]$SetIfBuilder.Append($SetIfExpr.Substring($SetIfPos));
                            }
                            $SetIfIsSet = $true;
                            $SetIfValue = $SetIfBuilder.ToString();
                        }
                    } else {
                        $SetIfIsSet = $true;
                        $SetIfValue = $SetIfExpr;
                    }
                }

                if (-not $SetIfIsSet) {
                    $OriginalIndex++;
                    continue;
                }

                [bool]$SetIfActive = ConvertFrom-ModuleBoolean -Value $SetIfValue;
                if (-not $SetIfActive) {
                    $OriginalIndex++;
                    continue;
                }
            }

            [bool]$ValueIsSet      = $false;
            [object]$ResolvedValue = $null;

            if ($HasValueField) {
                [object]$ValExpr = $ArgSpec['value'];

                if ($ValExpr -isnot [string]) {
                    $ValueIsSet    = ($null -ne $ValExpr);
                    $ResolvedValue = $ValExpr;
                } elseif ($ValExpr -match '^\$([A-Za-z0-9_.:-]+)\$$') {
                    [string]$MacroRef = $Matches[1];
                    if ($MacroMap.Contains($MacroRef) -and $null -ne $MacroMap[$MacroRef]) {
                        $ValueIsSet    = $true;
                        $ResolvedValue = $MacroMap[$MacroRef];
                    } elseif ($MacroMapIgnoreCase.ContainsKey($MacroRef) -and $null -ne $MacroMapIgnoreCase[$MacroRef]) {
                        $ValueIsSet    = $true;
                        $ResolvedValue = $MacroMapIgnoreCase[$MacroRef];
                    }
                } else {
                    $ValTokens = [regex]::Matches($ValExpr, '\$\$|\$([A-Za-z0-9_.:-]+)\$');
                    if ($ValTokens.Count -gt 0) {
                        [bool]$AllValTokensFound = $true;
                        $InterpBuilder           = New-Object System.Text.StringBuilder;
                        [int]$LastPos            = 0;

                        foreach ($ValToken in $ValTokens) {
                            if ($ValToken.Index -gt $LastPos) {
                                [void]$InterpBuilder.Append($ValExpr.Substring($LastPos, ($ValToken.Index - $LastPos)));
                            }

                            if ($ValToken.Value -eq '$$') {
                                [void]$InterpBuilder.Append('$');
                            } else {
                                [string]$RefName = $ValToken.Groups[1].Value;
                                [object]$RefVal  = $null;
                                if ($MacroMap.Contains($RefName)) {
                                    $RefVal = $MacroMap[$RefName];
                                } elseif ($MacroMapIgnoreCase.ContainsKey($RefName)) {
                                    $RefVal = $MacroMapIgnoreCase[$RefName];
                                }

                                if ($null -eq $RefVal) {
                                    $AllValTokensFound = $false;
                                    break;
                                }
                                [void]$InterpBuilder.Append([string]$RefVal);
                            }

                            $LastPos = $ValToken.Index + $ValToken.Length;
                        }

                        if ($AllValTokensFound) {
                            if ($LastPos -lt $ValExpr.Length) {
                                [void]$InterpBuilder.Append($ValExpr.Substring($LastPos));
                            }
                            $ValueIsSet    = $true;
                            $ResolvedValue = $InterpBuilder.ToString();
                        }
                    } else {
                        $ValueIsSet    = $true;
                        $ResolvedValue = $ValExpr;
                    }
                }
            } elseif ($IsStructuredSpec) {
                if ($Kind -eq 'Binary') {
                    $ValueIsSet    = $true;
                    $ResolvedValue = $true;
                } else {
                    [string]$CandidateSwitch = ([string]$ArgName) -replace '^-', '';
                    [bool]$IsTargetSwitch    = ($ParamLookup.ContainsKey($CandidateSwitch) -and ($ParamLookup[$CandidateSwitch].ParameterType -eq [switch] -or $ParamLookup[$CandidateSwitch].ParameterType -eq [System.Management.Automation.SwitchParameter]));

                    if ($IsTargetSwitch -or $HasSetIf) {
                        $ValueIsSet    = $true;
                        $ResolvedValue = $true;
                    }
                }
            }

            if (-not $ValueIsSet -or $null -eq $ResolvedValue) {
                $OriginalIndex++;
                continue;
            }

            if ($Kind -eq 'PowerShell') {
                [string]$CleanParamName = ([string]$ArgName) -replace '^-', '';

                if (-not $ParamLookup.ContainsKey($CleanParamName)) {
                    if ($ResolvedValue -is [string] -and $ResolvedValue.Length -eq 0) {
                        $OriginalIndex++;
                        continue;
                    }

                    return @{
                        'Status'                 = 'UnknownParameter';
                        'PowerShellArguments'    = @{ };
                        'BinaryArguments'        = [string[]]@();
                        'AllocatedSecureStrings' = @();
                        'CommandLine'            = $CommandName;
                        'Message'                = ('[UNKNOWN] Unknown parameter "{0}" supplied via "ifw_api_arguments" for Icinga for Windows Check "{1}" (IWKB001001)' -f $CleanParamName, $CommandName);
                        'KnowledgeBaseId'        = 'IWKB001001';
                        'ReturnCodeKey'          = 'IcingaProtocolUnknownParameter';
                    };
                }

                $PendingPowerShellBindings += @{
                    'Meta'  = $ParamLookup[$CleanParamName];
                    'Value' = $ResolvedValue;
                };
            } else {
                [double]$OrderValue = 0.0;
                if ($ArgSpec.Contains('order') -and $null -ne $ArgSpec['order']) {
                    if ($ArgSpec['order'] -is [int] -or $ArgSpec['order'] -is [long] -or $ArgSpec['order'] -is [double] -or $ArgSpec['order'] -is [single] -or $ArgSpec['order'] -is [decimal]) {
                        $OrderValue = [double]$ArgSpec['order'];
                    } else {
                        [double]$ParsedOrder = 0.0;
                        if ([double]::TryParse([string]$ArgSpec['order'], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$ParsedOrder) -and -not [double]::IsNaN($ParsedOrder) -and -not [double]::IsInfinity($ParsedOrder)) {
                            $OrderValue = $ParsedOrder;
                        }
                    }
                }

                [bool]$SkipKey = $false;
                if ($ArgSpec.Contains('skip_key') -and $null -ne $ArgSpec['skip_key']) {
                    $SkipKey = ConvertFrom-ModuleBoolean -Value $ArgSpec['skip_key'];
                }

                [bool]$RepeatKey = $true;
                if ($ArgSpec.Contains('repeat_key') -and $null -ne $ArgSpec['repeat_key']) {
                    $RepeatKey = ConvertFrom-ModuleBoolean -Value $ArgSpec['repeat_key'];
                }

                $OrderedBinarySpecs += [PSCustomObject]@{
                    'Key'           = [string]$ArgName;
                    'Order'         = $OrderValue;
                    'Index'         = $OriginalIndex;
                    'SkipKey'       = $SkipKey;
                    'RepeatKey'     = $RepeatKey;
                    'HasValueField' = $HasValueField;
                    'Value'         = $ResolvedValue;
                };
            }

            $OriginalIndex++;
        }

        if ($Kind -eq 'Binary' -and $OrderedBinarySpecs.Count -gt 0) {
            [array]$SortedSpecs = @($OrderedBinarySpecs | Sort-Object -Property 'Order', 'Index');
            [array]$BuiltArgs   = @();

            foreach ($Spec in $SortedSpecs) {
                if (-not $Spec.HasValueField) {
                    if (-not $Spec.SkipKey) {
                        $BuiltArgs += [string]$Spec.Key;
                    }
                    continue;
                }

                if ($Spec.Value -is [System.Collections.IList] -and $Spec.Value -isnot [string]) {
                    if ($Spec.Value.Count -gt 0) {
                        if ($Spec.SkipKey) {
                            foreach ($Item in $Spec.Value) {
                                $BuiltArgs += [string]$Item;
                            }
                        } elseif ($Spec.RepeatKey) {
                            foreach ($Item in $Spec.Value) {
                                $BuiltArgs += [string]$Spec.Key;
                                $BuiltArgs += [string]$Item;
                            }
                        } else {
                            $BuiltArgs += [string]$Spec.Key;
                            foreach ($Item in $Spec.Value) {
                                $BuiltArgs += [string]$Item;
                            }
                        }
                    }
                } else {
                    if (-not $Spec.SkipKey) {
                        $BuiltArgs += [string]$Spec.Key;
                    }
                    $BuiltArgs += [string]$Spec.Value;
                }
            }

            $BinaryArguments = [string[]]$BuiltArgs;
        }
    } else {
        # -------------------------------------------------------------------
        # Mode B: Fallback mode without ifw-api (macros.ifw_api_arguments absent)
        # -------------------------------------------------------------------
        if ($Kind -eq 'PowerShell') {
            [string]$PluginNamespace  = ($CommandName -replace '^Invoke-', '');
            [string]$NamespacePattern = ('^{0}_[A-Za-z0-9]+_(?<ParamName>.+)$' -f [regex]::Escape($PluginNamespace));
            [array]$UnmappedVariables = @();

            foreach ($MacroKey in $MacroMap.Keys) {
                if ($MacroKey.StartsWith('ifw_api_', [System.StringComparison]::OrdinalIgnoreCase) -or $MacroKey.StartsWith('IcingaPowerShellBase_', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue;
                }

                [string]$DirectCandidate = $MacroKey -replace '^-', '';
                $MatchedMeta             = $null;

                if ($ParamLookup.ContainsKey($DirectCandidate)) {
                    $MatchedMeta = $ParamLookup[$DirectCandidate];
                } elseif ($MacroKey -match $NamespacePattern) {
                    [string]$ExtractedParam = $Matches['ParamName'];
                    if ($ParamLookup.ContainsKey($ExtractedParam)) {
                        $MatchedMeta = $ParamLookup[$ExtractedParam];
                    }
                }

                if ($null -eq $MatchedMeta) {
                    $UnmappedVariables += [string]$MacroKey;
                    continue;
                }

                [object]$RawMacroVal = $MacroMap[$MacroKey];
                if ($null -ne $RawMacroVal) {
                    $PendingPowerShellBindings += @{
                        'Meta'  = $MatchedMeta;
                        'Value' = $RawMacroVal;
                    };
                }
            }

            if ($UnmappedVariables.Count -gt 0) {
                return @{
                    'Status'                 = 'MappingFailed';
                    'PowerShellArguments'    = @{ };
                    'BinaryArguments'        = [string[]]@();
                    'AllocatedSecureStrings' = @();
                    'CommandLine'            = $CommandName;
                    'Message'                = ('[UNKNOWN] Unable to map Custom-Variables to Icinga for Windows Check "{0}": {1} (IWKB001000)' -f $CommandName, ($UnmappedVariables -join ', '));
                    'KnowledgeBaseId'        = 'IWKB001000';
                    'ReturnCodeKey'          = 'IcingaProtocolMacroMappingFailed';
                };
            }
        } else {
            [array]$InvalidBinaryVars = @();
            [array]$FallbackBinArgs   = @();

            foreach ($MacroKey in $MacroMap.Keys) {
                if ($MacroKey.StartsWith('ifw_api_', [System.StringComparison]::OrdinalIgnoreCase) -or $MacroKey.StartsWith('IcingaPowerShellBase_', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue;
                }

                if (-not ($MacroKey.StartsWith('-') -or $MacroKey.StartsWith('/'))) {
                    $InvalidBinaryVars += [string]$MacroKey;
                    continue;
                }

                [object]$BinVal = $MacroMap[$MacroKey];
                if ($null -eq $BinVal) {
                    continue;
                }

                if ($BinVal -is [bool]) {
                    if ($BinVal) {
                        $FallbackBinArgs += [string]$MacroKey;
                    }
                } elseif ($BinVal -is [System.Collections.IList] -and $BinVal -isnot [string]) {
                    foreach ($Elem in $BinVal) {
                        $FallbackBinArgs += [string]$MacroKey;
                        $FallbackBinArgs += [string]$Elem;
                    }
                } else {
                    $FallbackBinArgs += [string]$MacroKey;
                    $FallbackBinArgs += [string]$BinVal;
                }
            }

            if ($InvalidBinaryVars.Count -gt 0) {
                return @{
                    'Status'                 = 'BinaryMappingFailed';
                    'PowerShellArguments'    = @{ };
                    'BinaryArguments'        = [string[]]@();
                    'AllocatedSecureStrings' = @();
                    'CommandLine'            = $BinaryPath;
                    'Message'                = ('[UNKNOWN] Unable to map Custom-Variables without "-" or "/" prefix to external binary check "{0}" when "ifw-api" is inactive: {1} (IWKB001002)' -f $CommandName, ($InvalidBinaryVars -join ', '));
                    'KnowledgeBaseId'        = 'IWKB001002';
                    'ReturnCodeKey'          = 'IcingaProtocolMacroMappingFailed';
                };
            }

            $BinaryArguments = [string[]]$FallbackBinArgs;
        }
    }

    # -----------------------------------------------------------------------
    # Coerce PowerShell parameter values & render masked CommandLine string
    # -----------------------------------------------------------------------
    [string]$RenderedCommandLine = '';

    try {
        if ($Kind -eq 'PowerShell') {
            foreach ($Binding in $PendingPowerShellBindings) {
                $ParamMeta             = $Binding['Meta'];
                [string]$CanonicalName = [string]$ParamMeta.Name;
                [type]$ParamType       = $ParamMeta.ParameterType;
                [object]$RawValue      = $Binding['Value'];

                [bool]$IsSwitchOrBool  = ($ParamType -eq [switch] -or $ParamType -eq [System.Management.Automation.SwitchParameter] -or $ParamType -eq [bool]);
                [bool]$IsSecureString  = ($ParamType -eq [System.Security.SecureString]);
                [bool]$IsArrayParam    = ($ParamType.IsArray -or $ParamType -eq [array]);
                [bool]$IsNumericOrEnum = ($ParamType.IsEnum -or $ParamType -eq [int] -or $ParamType -eq [long] -or $ParamType -eq [double] -or $ParamType -eq [decimal] -or $ParamType -eq [single] -or $ParamType -eq [int16] -or $ParamType -eq [byte] -or $ParamType -eq [uint32] -or $ParamType -eq [uint64] -or $ParamType -eq [sbyte] -or $ParamType -eq [uint16]);

                if ($IsSwitchOrBool) {
                    $PowerShellArguments[$CanonicalName] = (ConvertFrom-ModuleBoolean -Value $RawValue);
                } elseif ($IsSecureString) {
                    $SecureInstance = $null;
                    if ($RawValue -is [System.Security.SecureString]) {
                        $SecureInstance = $RawValue.Copy();
                    } else {
                        $SecureInstance = ConvertTo-ModuleSecureString -InputObject $RawValue;
                    }

                    if ($null -eq $SecureInstance) {
                        foreach ($AllocatedSecret in $AllocatedSecureStrings) {
                            if ($null -ne $AllocatedSecret -and $AllocatedSecret -is [System.IDisposable]) {
                                $AllocatedSecret.Dispose();
                            }
                        }

                        return @{
                            'Status'                 = 'CoercionFailed';
                            'PowerShellArguments'    = @{ };
                            'BinaryArguments'        = [string[]]@();
                            'AllocatedSecureStrings' = @();
                            'CommandLine'            = $CommandName;
                            'Message'                = ('[UNKNOWN] Failed to convert secret parameter "-{0}" for check "{1}" to SecureString' -f $CanonicalName, $CommandName);
                            'KnowledgeBaseId'        = '';
                            'ReturnCodeKey'          = 'IcingaProtocolMacroMappingFailed';
                        };
                    }

                    $AllocatedSecureStrings             += $SecureInstance;
                    $PowerShellArguments[$CanonicalName] = $SecureInstance;
                    $MaskedParameters[$CanonicalName]    = $true;
                } elseif ($IsArrayParam) {
                    if ($RawValue -is [string] -and $RawValue.Length -eq 0) {
                        continue;
                    }

                    [type]$ElemType = $null;
                    if ($ParamType.IsArray) {
                        $ElemType = $ParamType.GetElementType();
                    }

                    [bool]$FilterBlankItems = ($null -ne $ElemType -and ($ElemType.IsEnum -or $ElemType.IsValueType));

                    if ($RawValue -is [System.Collections.IList] -and $RawValue -isnot [string]) {
                        if ($FilterBlankItems) {
                            [array]$FilteredItems = @();
                            foreach ($RawElem in $RawValue) {
                                if ($null -eq $RawElem) {
                                    continue;
                                }
                                if ($RawElem -is [string] -and [string]::IsNullOrWhiteSpace($RawElem)) {
                                    continue;
                                }
                                if ($ElemType -eq [bool]) {
                                    $FilteredItems += (ConvertFrom-ModuleBoolean -Value $RawElem);
                                } else {
                                    $ConvertedElem = $RawElem -as $ElemType;
                                    if ($null -ne $ConvertedElem) {
                                        $FilteredItems += $ConvertedElem;
                                    } else {
                                        $FilteredItems += $RawElem;
                                    }
                                }
                            }
                            if ($FilteredItems.Count -eq 0 -and $RawValue.Count -gt 0) {
                                continue;
                            }
                            $PowerShellArguments[$CanonicalName] = $FilteredItems;
                        } else {
                            $PowerShellArguments[$CanonicalName] = @($RawValue);
                        }
                    } else {
                        if ($FilterBlankItems -and $RawValue -is [string] -and [string]::IsNullOrWhiteSpace($RawValue)) {
                            continue;
                        }
                        if ($FilterBlankItems) {
                            if ($ElemType -eq [bool]) {
                                $PowerShellArguments[$CanonicalName] = @( (ConvertFrom-ModuleBoolean -Value $RawValue) );
                            } else {
                                $ConvertedSingleElem = $RawValue -as $ElemType;
                                if ($null -ne $ConvertedSingleElem) {
                                    $PowerShellArguments[$CanonicalName] = @( $ConvertedSingleElem );
                                } else {
                                    $PowerShellArguments[$CanonicalName] = @( $RawValue );
                                }
                            }
                        } else {
                            $PowerShellArguments[$CanonicalName] = @( $RawValue );
                        }
                    }
                } elseif ($IsNumericOrEnum) {
                    if ($RawValue -is [string] -and [string]::IsNullOrWhiteSpace($RawValue)) {
                        continue;
                    }

                    $ConvertedNumeric = $RawValue -as $ParamType;
                    if ($null -ne $ConvertedNumeric) {
                        $PowerShellArguments[$CanonicalName] = $ConvertedNumeric;
                    } else {
                        $PowerShellArguments[$CanonicalName] = $RawValue;
                    }
                } else {
                    # Skip empty strings on ValidateSet parameters whose valid set does not include ''
                    if ($RawValue -is [string] -and $RawValue.Length -eq 0 -and $null -ne $ParamMeta.Attributes) {
                        [bool]$SkipEmptyValidateSet = $false;
                        foreach ($Attr in $ParamMeta.Attributes) {
                            if ($Attr -is [System.Management.Automation.ValidateSetAttribute] -and ($Attr.ValidValues -notcontains '')) {
                                $SkipEmptyValidateSet = $true;
                                break;
                            }
                        }

                        if ($SkipEmptyValidateSet) {
                            continue;
                        }
                    }

                    if ($ParamType -eq [string] -and $RawValue -isnot [string]) {
                        $PowerShellArguments[$CanonicalName] = [string]$RawValue;
                    } else {
                        $PowerShellArguments[$CanonicalName] = $RawValue;
                    }
                }
            }

            [array]$CmdParts  = @( $CommandName );
            [array]$ParamKeys = @($PowerShellArguments.Keys | Sort-Object);

            foreach ($BoundKey in $ParamKeys) {
                [object]$BoundVal = $PowerShellArguments[$BoundKey];
                $BoundMeta        = $ParamLookup[$BoundKey];

                if ($MaskedParameters.ContainsKey($BoundKey)) {
                    $CmdParts += ('-{0} ''********''' -f $BoundKey);
                } elseif ($null -ne $BoundMeta -and ($BoundMeta.ParameterType -eq [switch] -or $BoundMeta.ParameterType -eq [System.Management.Automation.SwitchParameter])) {
                    if ([bool]$BoundVal) {
                        $CmdParts += ('-{0}' -f $BoundKey);
                    } else {
                        $CmdParts += ('-{0}:$false' -f $BoundKey);
                    }
                } elseif ($BoundVal -is [bool]) {
                    $CmdParts += ('-{0} ${1}' -f $BoundKey, $BoundVal.ToString().ToLowerInvariant());
                } elseif ($BoundVal -is [System.Collections.IList] -and $BoundVal -isnot [string]) {
                    [array]$FormattedItems = @();
                    foreach ($ArrItem in $BoundVal) {
                        [bool]$IsNumericItem = ($ArrItem -is [int] -or $ArrItem -is [long] -or $ArrItem -is [double] -or $ArrItem -is [decimal] -or $ArrItem -is [single] -or $ArrItem -is [int16] -or $ArrItem -is [byte] -or $ArrItem -is [uint32] -or $ArrItem -is [uint64] -or $ArrItem -is [sbyte] -or $ArrItem -is [uint16]);
                        if ($IsNumericItem) {
                            $FormattedItems += [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $ArrItem);
                        } else {
                            $FormattedItems += ('''{0}''' -f ([string]$ArrItem).Replace('''', ''''''));
                        }
                    }
                    $CmdParts += ('-{0} @({1})' -f $BoundKey, ($FormattedItems -join ', '));
                } else {
                    [bool]$IsNumericScalar = ($BoundVal -is [int] -or $BoundVal -is [long] -or $BoundVal -is [double] -or $BoundVal -is [decimal] -or $BoundVal -is [single] -or $BoundVal -is [int16] -or $BoundVal -is [byte] -or $BoundVal -is [uint32] -or $BoundVal -is [uint64] -or $BoundVal -is [sbyte] -or $BoundVal -is [uint16]);
                    if ($IsNumericScalar) {
                        $CmdParts += ('-{0} {1}' -f $BoundKey, [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $BoundVal));
                    } else {
                        $CmdParts += ('-{0} ''{1}''' -f $BoundKey, ([string]$BoundVal).Replace('''', ''''''));
                    }
                }
            }

            $RenderedCommandLine = ($CmdParts -join ' ');
        } else {
            [array]$AllBinaryTokens = @( $BinaryPath ) + $BinaryArguments;
            [array]$QuotedTokens    = @();

            foreach ($Token in $AllBinaryTokens) {
                [string]$TextToken = [string]$Token;
                if ($TextToken.Length -eq 0) {
                    $QuotedTokens += '""';
                } elseif ($TextToken -notmatch '[\s"]') {
                    $QuotedTokens += $TextToken;
                } else {
                    $Builder             = New-Object System.Text.StringBuilder;
                    [void]$Builder.Append('"');
                    [int]$BackslashCount = 0;

                    for ($cIdx = 0; $cIdx -lt $TextToken.Length; $cIdx++) {
                        [char]$CurrentChar = $TextToken[$cIdx];
                        if ($CurrentChar -eq '\') {
                            $BackslashCount++;
                        } elseif ($CurrentChar -eq '"') {
                            [void]$Builder.Append('\', ($BackslashCount * 2 + 1));
                            [void]$Builder.Append('"');
                            $BackslashCount = 0;
                        } else {
                            if ($BackslashCount -gt 0) {
                                [void]$Builder.Append('\', $BackslashCount);
                                $BackslashCount = 0;
                            }
                            [void]$Builder.Append($CurrentChar);
                        }
                    }

                    if ($BackslashCount -gt 0) {
                        [void]$Builder.Append('\', ($BackslashCount * 2));
                    }

                    [void]$Builder.Append('"');
                    $QuotedTokens += $Builder.ToString();
                }
            }

            $RenderedCommandLine = ($QuotedTokens -join ' ');
        }
    } catch {
        foreach ($AllocatedSecret in $AllocatedSecureStrings) {
            if ($null -ne $AllocatedSecret -and $AllocatedSecret -is [System.IDisposable]) {
                $AllocatedSecret.Dispose();
            }
        }

        return @{
            'Status'                 = 'CoercionFailed';
            'PowerShellArguments'    = @{ };
            'BinaryArguments'        = [string[]]@();
            'AllocatedSecureStrings' = @();
            'CommandLine'            = $CommandName;
            'Message'                = ('[UNKNOWN] Failed to prepare arguments for check "{0}": {1}' -f $CommandName, $_.Exception.Message);
            'KnowledgeBaseId'        = '';
            'ReturnCodeKey'          = 'IcingaProtocolMacroMappingFailed';
        };
    }

    return @{
        'Status'                 = 'Ok';
        'PowerShellArguments'    = $PowerShellArguments;
        'BinaryArguments'        = $BinaryArguments;
        'AllocatedSecureStrings' = $AllocatedSecureStrings;
        'CommandLine'            = $RenderedCommandLine;
        'Message'                = '';
        'KnowledgeBaseId'        = '';
        'ReturnCodeKey'          = '';
    };
}

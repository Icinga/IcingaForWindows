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
   and embedded $macro$ references via Expand-IcingaProtocolMacroValue,
   evaluates set_if conditions, orders binary arguments by order, honors
   skip_key and repeat_key, and rejects unknown PowerShell parameters that carry
   a non-empty value with IWKB001001 (skipping empty strings, empty lists and
   empty dictionaries).
2. Fallback without ifw-api (macros.ifw_api_arguments absent): ignores internal
   ifw_api_* and IcingaPowerShellBase_* variables, maps PowerShell parameters by
   exact parameter/alias name or the IcingaCheck<Name>_<Type>_<Param> convention
   (returning IWKB001000 on unmapped custom variables), and enforces '-' or '/'
   prefixes on custom variables passed to external binaries (returning IWKB001002
   when unprefixed custom variables are present).

.PARAMETER ResolvedCommand
| Name            | Type                         | Description                                                   | Default |
|-----------------|------------------------------|---------------------------------------------------------------|---------|
| ResolvedCommand | System.Collections.Hashtable | Command descriptor returned by Resolve-IcingaProtocolCommand. | @{}     |

.PARAMETER Macros
| Name   | Type          | Description                                                          | Default |
|--------|---------------|----------------------------------------------------------------------|---------|
| Macros | System.Object | Deserialized macros dictionary or object from event::ExecuteCommand. | $null   |

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

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
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

    # Normalize Macros into an ordinal OrderedDictionary (preserving -p vs -P) plus a case-insensitive fallback map
    $MacroMap                      = ConvertTo-ModuleOrderedDictionary -InputObject $Macros -SkipEmptyKeys;
    [hashtable]$MacroMapIgnoreCase = @{ };

    foreach ($MacroKey in $MacroMap.Keys) {
        [string]$MacroKeyText = [string]$MacroKey;
        if (-not $MacroMapIgnoreCase.ContainsKey($MacroKeyText) -or $null -eq $MacroMapIgnoreCase[$MacroKeyText]) {
            $MacroMapIgnoreCase[$MacroKeyText] = $MacroMap[$MacroKey];
        }
    }

    # Build case-insensitive parameter & alias lookup for PowerShell check commands
    [hashtable]$ParamLookup = @{ };
    if ($Kind -eq 'PowerShell' -and $null -ne $CommandParameters) {
        [hashtable]$ParamBundle = Get-ModuleCommandParameterMap -Parameters $CommandParameters;
        $ParamLookup            = $ParamBundle['Lookup'];
    }

    [object]$RawApiArgsObj            = Get-ModuleObjectValue -InputObject $MacroMap -Name 'ifw_api_arguments';
    [bool]$HasApiArguments            = ($null -ne $RawApiArgsObj -and ($RawApiArgsObj -is [System.Collections.IDictionary] -or $RawApiArgsObj -is [PSCustomObject]));

    [hashtable]$PowerShellArguments   = @{ };
    [hashtable]$MaskedParameters      = @{ };
    [array]$AllocatedSecureStrings    = @();
    [array]$PendingPowerShellBindings = @();
    [string[]]$BinaryArguments        = @();

    if ($HasApiArguments) {
        # -------------------------------------------------------------------
        # Mode A: ifw-api active (macros.ifw_api_arguments present)
        # -------------------------------------------------------------------
        $ApiArgEntries             = ConvertTo-ModuleOrderedDictionary -InputObject $RawApiArgsObj;
        [array]$OrderedBinarySpecs = @();
        [int]$OriginalIndex        = 0;

        foreach ($ArgName in $ApiArgEntries.Keys) {
            [object]$RawArgSpec     = $ApiArgEntries[$ArgName];
            [bool]$IsStructuredSpec = ($RawArgSpec -is [System.Collections.IDictionary] -or $RawArgSpec -is [PSCustomObject]);
            $ArgSpec                = $null;

            if ($IsStructuredSpec) {
                $ArgSpec = ConvertTo-ModuleOrderedDictionary -InputObject $RawArgSpec;
            } else {
                $ArgSpec          = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::Ordinal);
                $ArgSpec['value'] = $RawArgSpec;
            }

            [bool]$HasSetIf      = ($ArgSpec.Contains('set_if') -and $null -ne $ArgSpec['set_if']);
            [bool]$HasValueField = ($ArgSpec.Contains('value') -and $null -ne $ArgSpec['value']);

            # Evaluate set_if condition first when defined
            if ($HasSetIf) {
                [hashtable]$ExpandedSetIf = Expand-IcingaProtocolMacroValue -Expression $ArgSpec['set_if'] -MacroMap $MacroMap -MacroIgnoreCase $MacroMapIgnoreCase;
                if (-not $ExpandedSetIf['IsSet']) {
                    $OriginalIndex++;
                    continue;
                }

                [bool]$SetIfActive = ConvertFrom-ModuleBoolean -Value $ExpandedSetIf['Value'];
                if (-not $SetIfActive) {
                    $OriginalIndex++;
                    continue;
                }
            }

            # Evaluate value field or handle valueless CLI flags / PowerShell switches
            [bool]$ValueIsSet      = $false;
            [object]$ResolvedValue = $null;

            if ($HasValueField) {
                [hashtable]$ExpandedVal = Expand-IcingaProtocolMacroValue -Expression $ArgSpec['value'] -MacroMap $MacroMap -MacroIgnoreCase $MacroMapIgnoreCase;
                $ValueIsSet             = [bool]$ExpandedVal['IsSet'];
                $ResolvedValue          = $ExpandedVal['Value'];
            } elseif ($IsStructuredSpec) {
                # Structured entry with omitted 'value' or serialized '"value": null' (e.g. '-4' = {} or '-NoPerfData' = { set_if = ... }):
                # treat as a valueless CLI flag on binaries or as $true on PowerShell [switch] parameters
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

                # Unknown parameter in ifw_api_arguments: skip unpopulated empty values ("", [], {}),
                # but raise IWKB001001 if the user actively populated a non-empty value for a non-existent parameter
                if (-not $ParamLookup.ContainsKey($CleanParamName)) {
                    [bool]$IsEmptyStr = ($ResolvedValue -is [string] -and $ResolvedValue.Length -eq 0);
                    [bool]$IsEmptyArr = ($ResolvedValue -is [System.Collections.IList] -and $ResolvedValue -isnot [string] -and $ResolvedValue.Count -eq 0);
                    [bool]$IsEmptyMap = ($ResolvedValue -is [System.Collections.IDictionary] -and $ResolvedValue.Count -eq 0);
                    [bool]$IsEmptyObj = ($ResolvedValue -is [PSCustomObject] -and @($ResolvedValue.PSObject.Properties).Count -eq 0);

                    if ($IsEmptyStr -or $IsEmptyArr -or $IsEmptyMap -or $IsEmptyObj) {
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
                # Binary argument specification: parse 'order' (InvariantCulture), 'skip_key' and 'repeat_key'
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

                $OrderValue    = [System.Math]::Max(-1e15, [System.Math]::Min(1e15, $OrderValue));

                [bool]$SkipKey = $false;
                if ($ArgSpec.Contains('skip_key') -and $null -ne $ArgSpec['skip_key']) {
                    $SkipKey = ConvertFrom-ModuleBoolean -Value $ArgSpec['skip_key'];
                }

                [bool]$RepeatKey = $true;
                if ($ArgSpec.Contains('repeat_key') -and $null -ne $ArgSpec['repeat_key']) {
                    $RepeatKey = ConvertFrom-ModuleBoolean -Value $ArgSpec['repeat_key'];
                }

                $OrderedBinarySpecs += @{
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

        # Sort binary arguments stably by (Order, OriginalIndex) and expand CLI tokens according to skip_key / repeat_key
        if ($Kind -eq 'Binary' -and $OrderedBinarySpecs.Count -gt 0) {
            [array]$SortedSpecs = ConvertTo-IcingaSortedArray -InputObject $OrderedBinarySpecs -Property @( 'Order', 'Index' );
            [array]$BuiltArgs   = @();

            foreach ($Spec in $SortedSpecs) {
                if (-not $Spec['HasValueField']) {
                    if (-not $Spec['SkipKey']) {
                        $BuiltArgs += [string]$Spec['Key'];
                    }
                    continue;
                }

                [object]$SpecValue = $Spec['Value'];

                if ($SpecValue -is [System.Collections.IList] -and $SpecValue -isnot [string]) {
                    if ($SpecValue.Count -gt 0) {
                        if ($Spec['SkipKey']) {
                            foreach ($Item in $SpecValue) {
                                $BuiltArgs += [string]$Item;
                            }
                        } elseif ($Spec['RepeatKey']) {
                            foreach ($Item in $SpecValue) {
                                $BuiltArgs += [string]$Spec['Key'];
                                $BuiltArgs += [string]$Item;
                            }
                        } else {
                            $BuiltArgs += [string]$Spec['Key'];
                            foreach ($Item in $SpecValue) {
                                $BuiltArgs += [string]$Item;
                            }
                        }
                    }
                } else {
                    if (-not $Spec['SkipKey']) {
                        $BuiltArgs += [string]$Spec['Key'];
                    }
                    $BuiltArgs += [string]$SpecValue;
                }
            }

            $BinaryArguments = [string[]]$BuiltArgs;
        }
    } else {
        # -------------------------------------------------------------------
        # Mode B: Fallback mode without ifw-api (macros.ifw_api_arguments absent)
        # -------------------------------------------------------------------
        if ($Kind -eq 'PowerShell') {
            # Match either direct parameter/alias names or IcingaCheck<Name>_<DataType>_<ParamName>
            [string]$PluginNamespace  = ($CommandName -replace '^Invoke-', '');
            [string]$NamespacePattern = ('^{0}_[A-Za-z0-9]+_(?<ParamName>.+)$' -f [regex]::Escape($PluginNamespace));
            [array]$UnmappedVariables = @();

            foreach ($MacroKey in $MacroMap.Keys) {
                [string]$MacroKeyStr = [string]$MacroKey;
                if ($MacroKeyStr.StartsWith('ifw_api_', [System.StringComparison]::OrdinalIgnoreCase) -or $MacroKeyStr.StartsWith('IcingaPowerShellBase_', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue;
                }

                [string]$DirectCandidate = $MacroKeyStr -replace '^-', '';
                $MatchedMeta             = $null;

                if ($ParamLookup.ContainsKey($DirectCandidate)) {
                    $MatchedMeta = $ParamLookup[$DirectCandidate];
                } elseif ($MacroKeyStr -match $NamespacePattern) {
                    [string]$ExtractedParam = $Matches['ParamName'];
                    if ($ParamLookup.ContainsKey($ExtractedParam)) {
                        $MatchedMeta = $ParamLookup[$ExtractedParam];
                    }
                }

                if ($null -eq $MatchedMeta) {
                    $UnmappedVariables += $MacroKeyStr;
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
            # Without ifw_api_arguments, binary custom variables must start with '-' or '/' (IWKB001002)
            [array]$InvalidBinaryVars = @();
            [array]$FallbackBinArgs   = @();

            foreach ($MacroKey in $MacroMap.Keys) {
                [string]$BinKeyStr = [string]$MacroKey;
                if ($BinKeyStr.StartsWith('ifw_api_', [System.StringComparison]::OrdinalIgnoreCase) -or $BinKeyStr.StartsWith('IcingaPowerShellBase_', [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue;
                }

                if (-not ($BinKeyStr.StartsWith('-') -or $BinKeyStr.StartsWith('/'))) {
                    $InvalidBinaryVars += $BinKeyStr;
                    continue;
                }

                [object]$BinVal = $MacroMap[$MacroKey];
                if ($null -eq $BinVal) {
                    continue;
                }

                if ($BinVal -is [bool]) {
                    if ($BinVal) {
                        $FallbackBinArgs += $BinKeyStr;
                    }
                } elseif ($BinVal -is [System.Collections.IList] -and $BinVal -isnot [string]) {
                    foreach ($Elem in $BinVal) {
                        $FallbackBinArgs += $BinKeyStr;
                        $FallbackBinArgs += [string]$Elem;
                    }
                } else {
                    $FallbackBinArgs += $BinKeyStr;
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
                [hashtable]$Coerced    = ConvertTo-ModuleParameterValue -ParameterMetadata $ParamMeta -RawValue $Binding['Value'];

                if ($Coerced['Status'] -eq 'Error') {
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

                if ($Coerced['Status'] -eq 'Skipped') {
                    continue;
                }

                if ($null -ne $Coerced['AllocatedSecret']) {
                    $AllocatedSecureStrings += $Coerced['AllocatedSecret'];
                }

                $PowerShellArguments[$CanonicalName] = $Coerced['Value'];

                if ($Coerced['IsSecret']) {
                    $MaskedParameters[$CanonicalName] = $true;
                }
            }

            # Render a deterministic, human-readable PowerShell invocation string for CheckResult.command
            # and debug logs while masking all SecureString values as '********'
            [array]$CmdParts  = @( $CommandName );
            [array]$ParamKeys = ConvertTo-IcingaSortedArray -InputObject @($PowerShellArguments.Keys);

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
            $RenderedCommandLine = Format-ModuleCommandLineArguments -Arguments (@( $BinaryPath ) + $BinaryArguments);
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

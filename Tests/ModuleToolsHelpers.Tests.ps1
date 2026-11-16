$ModulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Shared Module Tools and Protocol Helpers' {
    BeforeAll {
        $script:IcingaModule = Get-Module -Name 'IcingaForWindows' -All |
            Where-Object { $_.ModuleType -eq 'Script' } |
            Select-Object -First 1;
    }

    Context 'Get-ModuleObjectValue' {
        It 'reads keys case-insensitively across Hashtable, Dictionary[string, object], OrderedDictionary and PSCustomObject' {
            [hashtable]$Outcome = & $script:IcingaModule {
                $Ht                   = @{ 'Check_Timeout' = 45; };
                $Dict                 = New-Object 'System.Collections.Generic.Dictionary[string, object]';
                $Dict['check_timeout'] = 10;
                $Dict['CHECK_TIMEOUT'] = 25;
                $Ord                  = New-Object System.Collections.Specialized.OrderedDictionary([System.StringComparer]::Ordinal);
                $Ord['-p']            = 'lower';
                $Ord['-P']            = 'upper';
                $Obj                  = [PSCustomObject]@{ 'Service' = 'CPU Load'; };

                $EmptyArrSource       = @{ 'Items' = @(); 'Single' = @( 'only' ); };
                $EmptyArrVal          = Get-ModuleObjectValue -InputObject $EmptyArrSource -Name 'items';
                $SingleArrVal         = Get-ModuleObjectValue -InputObject $EmptyArrSource -Name 'single';

                return @{
                    'HtVal'         = (Get-ModuleObjectValue -InputObject $Ht -Name 'check_timeout' -DefaultValue 60);
                    'ExactDictVal'  = (Get-ModuleObjectValue -InputObject $Dict -Name 'CHECK_TIMEOUT' -DefaultValue 60);
                    'CiDictVal'     = (Get-ModuleObjectValue -InputObject $Dict -Name 'Check_Timeout' -DefaultValue 60);
                    'OrdLower'      = (Get-ModuleObjectValue -InputObject $Ord -Name '-p');
                    'OrdUpper'      = (Get-ModuleObjectValue -InputObject $Ord -Name '-P');
                    'ObjVal'        = (Get-ModuleObjectValue -InputObject $Obj -Name 'service');
                    'MissingVal'    = (Get-ModuleObjectValue -InputObject $Obj -Name 'missing' -DefaultValue 'fallback');
                    'NullObjVal'    = (Get-ModuleObjectValue -InputObject $null -Name 'any' -DefaultValue 99);
                    'EmptyArrIsArr' = ($EmptyArrVal -is [array] -and $EmptyArrVal.Count -eq 0);
                    'SingleIsArr'   = ($SingleArrVal -is [array] -and $SingleArrVal.Count -eq 1);
                };
            };

            $Outcome['HtVal']         | Should -Be 45;
            $Outcome['ExactDictVal']  | Should -Be 25;
            $Outcome['CiDictVal']     | Should -Be 10;
            $Outcome['OrdLower']      | Should -Be 'lower';
            $Outcome['OrdUpper']      | Should -Be 'upper';
            $Outcome['ObjVal']        | Should -Be 'CPU Load';
            $Outcome['MissingVal']    | Should -Be 'fallback';
            $Outcome['NullObjVal']    | Should -Be 99;
            $Outcome['EmptyArrIsArr'] | Should -BeTrue;
            $Outcome['SingleIsArr']   | Should -BeTrue;
        }
    }

    Context 'ConvertTo-ModuleOrderedDictionary' {
        It 'converts dictionaries and PSCustomObjects with ordinal key comparison and optional empty-key skipping' {
            [hashtable]$Outcome = & $script:IcingaModule {
                $Src       = New-Object 'System.Collections.Generic.Dictionary[string, object]';
                $Src['']   = '$';
                $Src['  '] = '$';
                $Src['-p'] = '80';
                $Src['-P'] = '443';

                $Kept      = ConvertTo-ModuleOrderedDictionary -InputObject $Src;
                $Skipped   = ConvertTo-ModuleOrderedDictionary -InputObject $Src -SkipEmptyKeys;
                $FromObj   = ConvertTo-ModuleOrderedDictionary -InputObject ([PSCustomObject]@{ 'Alpha' = 1; 'Beta' = 2; });

                return @{
                    'KeptCount'    = $Kept.Count;
                    'SkippedCount' = $Skipped.Count;
                    'LowerP'       = $Skipped['-p'];
                    'UpperP'       = $Skipped['-P'];
                    'ObjKeys'      = (@($FromObj.Keys) -join ',');
                };
            };

            $Outcome['KeptCount']    | Should -Be 4;
            $Outcome['SkippedCount'] | Should -Be 2;
            $Outcome['LowerP']       | Should -Be '80';
            $Outcome['UpperP']       | Should -Be '443';
            $Outcome['ObjKeys']      | Should -Be 'Alpha,Beta';
        }
    }

    Context 'Format-ModuleCommandLineArguments' {
        It 'escapes empty strings, spaces, trailing backslashes and embedded quotes per CommandLineToArgvW' {
            [hashtable]$Outcome = & $script:IcingaModule {
                return @{
                    'Empty'   = (Format-ModuleCommandLineArguments -Arguments @());
                    'Complex' = (Format-ModuleCommandLineArguments -Arguments @( 'simple', '', 'has space', 'C:\Dir\', 'C:\My Dir\', 'say "hi"', 'C:\Path\"quoted"' ));
                };
            };

            $Outcome['Empty']   | Should -Be '';
            $Outcome['Complex'] | Should -Be 'simple "" "has space" C:\Dir\ "C:\My Dir\\" "say \"hi\"" "C:\Path\\\"quoted\""';
        }
    }

    Context 'Get-ModuleCommandParameterMap and ConvertTo-ModuleParameterValue' {
        It 'filters CommonParameters, resolves aliases, orders positional parameters and coerces edge-case values' {
            [hashtable]$Outcome = & $script:IcingaModule {
                function Test-SampleTargetCmd()
                {
                    [CmdletBinding(SupportsShouldProcess = $true)]
                    param (
                        [Parameter(Position = 1)]
                        [Alias('SecondAlias')]
                        [int]$SecondParam         = 5,
                        [Parameter(Position = 0)]
                        [string[]]$FirstList      = @( '*' ),
                        [ValidateSet('Ok', 'Critical')]
                        [string]$Mode             = 'Ok',
                        [securestring]$SecretVal  = $null,
                        [Parameter(ValueFromRemainingArguments = $true)]
                        [string[]]$RemainingItems = @()
                    );

                    return 0;
                }

                $CmdMeta                  = Get-Command -Name 'Test-SampleTargetCmd' -CommandType Function;
                [hashtable]$Map           = Get-ModuleCommandParameterMap -Parameters $CmdMeta.Parameters;
                [hashtable]$Lookup        = $Map['Lookup'];
                [array]$Positional        = $Map['Positional'];

                [hashtable]$SkipEmptyList = ConvertTo-ModuleParameterValue -ParameterMetadata $Lookup['FirstList'] -RawValue @();
                [hashtable]$BoundList     = ConvertTo-ModuleParameterValue -ParameterMetadata $Lookup['FirstList'] -RawValue @( '*.log', '*.json' );
                [hashtable]$SkipEmptyNum  = ConvertTo-ModuleParameterValue -ParameterMetadata $Lookup['SecondAlias'] -RawValue @( );
                [hashtable]$BoundNum      = ConvertTo-ModuleParameterValue -ParameterMetadata $Lookup['SecondAlias'] -RawValue '42';
                [hashtable]$SkipBlankSet  = ConvertTo-ModuleParameterValue -ParameterMetadata $Lookup['Mode'] -RawValue '   ';
                [hashtable]$BoundSecret   = ConvertTo-ModuleParameterValue -ParameterMetadata $Lookup['SecretVal'] -RawValue 'MyToken!';

                try {
                    return @{
                        'HasVerbose'     = $Lookup.ContainsKey('Verbose');
                        'HasWhatIf'      = $Lookup.ContainsKey('WhatIf');
                        'HasAlias'       = $Lookup.ContainsKey('SecondAlias');
                        'PosOrder'       = ((@($Positional) | ForEach-Object { [string]$_.Name }) -join ',');
                        'SkipEmptyList'  = $SkipEmptyList['Status'];
                        'BoundListVal'   = ($BoundList['Value'] -join ',');
                        'SkipEmptyNum'   = $SkipEmptyNum['Status'];
                        'BoundNumVal'    = $BoundNum['Value'];
                        'SkipBlankSet'   = $SkipBlankSet['Status'];
                        'SecretIsSecure' = ($BoundSecret['Value'] -is [System.Security.SecureString]);
                    };
                } finally {
                    if ($null -ne $BoundSecret['AllocatedSecret']) {
                        $BoundSecret['AllocatedSecret'].Dispose();
                    }
                }
            };

            $Outcome['HasVerbose']     | Should -BeFalse;
            $Outcome['HasWhatIf']      | Should -BeFalse;
            $Outcome['HasAlias']       | Should -BeTrue;
            $Outcome['PosOrder']       | Should -Be 'FirstList,SecondParam,Mode,SecretVal';
            $Outcome['SkipEmptyList']  | Should -Be 'Skipped';
            $Outcome['BoundListVal']   | Should -Be '*.log,*.json';
            $Outcome['SkipEmptyNum']   | Should -Be 'Skipped';
            $Outcome['BoundNumVal']    | Should -Be 42;
            $Outcome['SkipBlankSet']   | Should -Be 'Skipped';
            $Outcome['SecretIsSecure'] | Should -BeTrue;
        }
    }

    Context 'Invoke-ModulePowerShellCommand and Add-IcingaRPCMessageToWorker' {
        It 'resets ActiveCheckCommand in finally even when a check throws before Compile' {
            [hashtable]$Outcome = & $script:IcingaModule {
                function Invoke-IcingaCheckAbortMidway()
                {
                    [void](New-IcingaPlugin 'Partial' 10 '%').CheckRange();
                    throw 'Aborted before Compile';
                }

                [hashtable]$Res = Invoke-ModulePowerShellCommand -Command 'Invoke-IcingaCheckAbortMidway';
                $GlobalVar      = Get-GlobalRuntimeVariable;

                return @{
                    'ExitCode'           = $Res['ExitCode'];
                    'Output'             = $Res['Output'];
                    'ActiveAfterFailure' = $GlobalVar.Private.Icinga.ActiveCheckCommand;
                    'ResultAfterFailure' = $GlobalVar.Private.Icinga.CheckResult;
                };
            };

            $Outcome['ExitCode']           | Should -Be 3;
            $Outcome['Output']             | Should -Match 'Aborted before Compile';
            $Outcome['ActiveAfterFailure'] | Should -BeNullOrEmpty;
            $Outcome['ResultAfterFailure'] | Should -BeNullOrEmpty;
        }

        It 'drops malformed JSON cleanly in Add-IcingaRPCMessageToWorker and preserves empty-key stripping' {
            [hashtable]$Outcome = & $script:IcingaModule {
                $GlobalVar      = Get-GlobalRuntimeVariable;
                $PrevQueue      = $GlobalVar.Public.IcingaProtocol.WorkerQueue;
                $PrevCount      = $GlobalVar.Public.IcingaProtocol.Config.WorkerCount;
                $PrevLastWorker = $GlobalVar.Private.TCP.LastWorkerId;
                $TestQueue      = New-Object 'System.Collections.Concurrent.BlockingCollection[PSObject]';
                $QueueList      = [System.Collections.ArrayList]::new();
                [void]$QueueList.Add($TestQueue);

                try {
                    $GlobalVar.Public.IcingaProtocol.Config.WorkerCount = 1;
                    $GlobalVar.Public.IcingaProtocol.WorkerQueue        = $QueueList;
                    $GlobalVar.Private.TCP.LastWorkerId                 = -1;

                    [void](Add-IcingaRPCMessageToWorker -Message '{invalid-json');
                    [int]$AfterInvalid = $TestQueue.Count;

                    [void](Add-IcingaRPCMessageToWorker -Message '{"jsonrpc":"2.0","method":"event::ExecuteCommand","params":{"macros":{"":"$","ifw_api_command":"uptime"}}}');
                    [int]$AfterValid   = $TestQueue.Count;
                    $QueuedItem        = $TestQueue.Take();

                    return @{
                        'AfterInvalid' = $AfterInvalid;
                        'AfterValid'   = $AfterValid;
                        'QueuedMethod' = (Get-ModuleObjectValue -InputObject $QueuedItem.Message -Name 'method');
                    };
                } finally {
                    $TestQueue.Dispose();
                    $GlobalVar.Public.IcingaProtocol.WorkerQueue        = $PrevQueue;
                    $GlobalVar.Public.IcingaProtocol.Config.WorkerCount = $PrevCount;
                    $GlobalVar.Private.TCP.LastWorkerId                 = $PrevLastWorker;
                }
            };

            $Outcome['AfterInvalid'] | Should -Be 0;
            $Outcome['AfterValid']   | Should -Be 1;
            $Outcome['QueuedMethod'] | Should -Be 'event::ExecuteCommand';
        }

        It 'accumulates repeated -Param:Value colon arguments on array parameters in Invoke-IcingaProtocolExternalScript' {
            [string]$ColonScript  = Join-Path -Path $TestDrive -ChildPath 'check_colon_array.ps1';
            [System.IO.File]::WriteAllText($ColonScript, "param([string[]]`$Tags = @()); Write-Output (`$Tags -join ','); exit 0;`n", (New-Object System.Text.UTF8Encoding($false)));

            [hashtable]$ScriptRes = & $script:IcingaModule {
                param ($Path);
                return (Invoke-IcingaProtocolExternalScript -ScriptPath $Path -CommandName 'check_colon_array.ps1' -BinaryArguments @( '-Tags:alpha', '-Tags:beta' ));
            } $ColonScript;

            $ScriptRes['ExitCode'] | Should -Be 0;
            $ScriptRes['Output']   | Should -Be 'alpha,beta';
        }
    }
}

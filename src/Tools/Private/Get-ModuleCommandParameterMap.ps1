<#
.SYNOPSIS
Build a parameter lookup table and ordered positional parameter list for a command

.DESCRIPTION
Get-ModuleCommandParameterMap inspects the Parameters dictionary of a PowerShell
CommandInfo object, filters out the 14 built-in PowerShell common and
ShouldProcess parameters, registers every canonical parameter name and alias in
a case-insensitive Lookup hashtable, and produces an ordered Positional list
excluding ValueFromRemainingArguments parameters (honoring explicit non-negative
Position attributes first and declaration order thereafter).

.PARAMETER Parameters
| Name       | Type          | Description                                               | Default |
|------------|---------------|-----------------------------------------------------------|---------|
| Parameters | System.Object | CommandInfo.Parameters dictionary to index and normalize. | $null   |

.OUTPUTS
System.Collections.Hashtable -- Hashtable containing Lookup (Hashtable of
canonical and alias names to ParameterMetadata) and Positional (Array of
ordered ParameterMetadata entries).

.EXAMPLE
PS> $cmd = Get-Command -Name 'Invoke-IcingaCheckDirectory'
PS> $map = Get-ModuleCommandParameterMap -Parameters $cmd.Parameters

Builds the canonical/alias lookup map and positional list for the command.

.NOTES
Pure metadata helper with no external dependencies or side effects.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Get-ModuleCommandParameterMap()
{
    param (
        [object]$Parameters = $null
    );

    # Exclude PowerShell's 14 built-in CommonParameters / ShouldProcess parameters so user macros
    # cannot hijack cmdlet infrastructure switches such as -ErrorAction, -OutVariable or -WhatIf
    [hashtable]$Lookup           = @{ };
    [hashtable]$ExcludedCommon   = @{ };
    [array]$CommonParameterNames = @(
        'Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction',
        'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable',
        'OutBuffer', 'PipelineVariable', 'ProgressAction', 'WhatIf', 'Confirm'
    );

    foreach ($CommonName in $CommonParameterNames) {
        $ExcludedCommon[$CommonName] = $true;
    }

    if ($null -eq $Parameters) {
        return @{
            'Lookup'     = $Lookup;
            'Positional' = @();
        };
    }

    [array]$PositionalSpecs = @();
    [int]$DeclarationIndex  = 0;

    foreach ($ParamEntry in $Parameters.GetEnumerator()) {
        $ParamMeta = $ParamEntry.Value;

        if ($null -eq $ParamMeta -or $ExcludedCommon.ContainsKey([string]$ParamMeta.Name)) {
            continue;
        }

        [string]$CanonName  = [string]$ParamMeta.Name;
        $Lookup[$CanonName] = $ParamMeta;

        if ($null -ne $ParamMeta.Aliases) {
            foreach ($AliasName in $ParamMeta.Aliases) {
                if (-not [string]::IsNullOrWhiteSpace([string]$AliasName)) {
                    $Lookup[[string]$AliasName] = $ParamMeta;
                }
            }
        }

        # Determine positional binding priority: explicit [Parameter(Position = N)] comes before
        # declaration order, while ValueFromRemainingArguments catch-all parameters are excluded
        [bool]$TakesRemaining = $false;
        [int]$ExplicitPos     = 2147483647;

        if ($null -ne $ParamMeta.ParameterSets) {
            foreach ($ParamSetMeta in $ParamMeta.ParameterSets.Values) {
                if ($ParamSetMeta.ValueFromRemainingArguments) {
                    $TakesRemaining = $true;
                    break;
                }

                if ($ParamSetMeta.Position -ge 0 -and $ParamSetMeta.Position -lt $ExplicitPos) {
                    $ExplicitPos = [int]$ParamSetMeta.Position;
                }
            }
        }

        if (-not $TakesRemaining) {
            $PositionalSpecs += @{
                'ExplicitPos' = $ExplicitPos;
                'DeclIndex'   = $DeclarationIndex;
                'Meta'        = $ParamMeta;
            };
        }

        $DeclarationIndex++;
    }

    [array]$Positional = @();

    if ($PositionalSpecs.Count -gt 0) {
        [array]$SortedSpecs = ConvertTo-IcingaSortedArray -InputObject $PositionalSpecs -Property @( 'ExplicitPos', 'DeclIndex' );

        foreach ($Spec in $SortedSpecs) {
            $Positional += $Spec['Meta'];
        }
    }

    return @{
        'Lookup'     = $Lookup;
        'Positional' = $Positional;
    };
}

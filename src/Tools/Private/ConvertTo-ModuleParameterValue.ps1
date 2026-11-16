<#
.SYNOPSIS
Coerce a raw JSON or macro value to match a PowerShell ParameterMetadata target

.DESCRIPTION
ConvertTo-ModuleParameterValue centralizes parameter type coercion across native
Invoke-IcingaCheck* plugins and approved external PowerShell scripts (.ps1):
- SwitchParameter and Boolean values are converted deterministically through
  ConvertFrom-ModuleBoolean.
- SecureString values are copied (when already a SecureString) or converted via
  ConvertTo-ModuleSecureString and returned in AllocatedSecret for deterministic
  disposal by the caller.
- Typed and untyped array parameters skip empty strings and empty IList
  collections (@()), while coercing value-type and enum elements on typed arrays.
- Scalar numeric (12 .NET integer/floating-point types) and enum parameters skip
  whitespace/empty strings and empty IList values before coercing with '-as'.
- String parameters carrying ValidateSet or ValidatePattern attributes skip
  empty or whitespace values that are not explicitly listed as valid.

.PARAMETER ParameterMetadata
| Name              | Type          | Description                                               | Default |
|-------------------|---------------|-----------------------------------------------------------|---------|
| ParameterMetadata | System.Object | PowerShell ParameterMetadata describing the target param. | $null   |

.PARAMETER RawValue
| Name     | Type          | Description                                      | Default |
|----------|---------------|--------------------------------------------------|---------|
| RawValue | System.Object | Raw JSON, CLI or macro value to coerce and bind. | $null   |

.OUTPUTS
System.Collections.Hashtable -- Hashtable containing Status ('Bound', 'Skipped'
or 'Error'), Value, IsSecret, AllocatedSecret and ErrorReason.

.EXAMPLE
PS> $cmd = Get-Command -Name 'Invoke-IcingaCheckDirectory'
PS> ConvertTo-ModuleParameterValue -ParameterMetadata $cmd.Parameters['Verbosity'] -RawValue '2'

Coerces the string '2' into Int32 2 with Status 'Bound'.

.NOTES
Callers must call Dispose() on AllocatedSecret when non-null once command
execution completes.
#>
function ConvertTo-ModuleParameterValue()
{
    param (
        [object]$ParameterMetadata = $null,
        [object]$RawValue          = $null
    );

    if ($null -eq $ParameterMetadata) {
        return @{
            'Status'          = 'Bound';
            'Value'           = $RawValue;
            'IsSecret'        = $false;
            'AllocatedSecret' = $null;
            'ErrorReason'     = '';
        };
    }

    [type]$ParamType       = $ParameterMetadata.ParameterType;
    [bool]$IsSwitchOrBool  = ($ParamType -eq [switch] -or $ParamType -eq [System.Management.Automation.SwitchParameter] -or $ParamType -eq [bool]);
    [bool]$IsSecureString  = ($ParamType -eq [System.Security.SecureString]);
    [bool]$IsArrayParam    = ($ParamType.IsArray -or $ParamType -eq [array]);
    [bool]$IsNumericOrEnum = ($ParamType.IsEnum -or $ParamType -eq [int] -or $ParamType -eq [long] -or $ParamType -eq [double] -or $ParamType -eq [decimal] -or $ParamType -eq [single] -or $ParamType -eq [int16] -or $ParamType -eq [byte] -or $ParamType -eq [uint32] -or $ParamType -eq [uint64] -or $ParamType -eq [sbyte] -or $ParamType -eq [uint16]);

    # 1. SwitchParameter and Boolean coercion via ConvertFrom-ModuleBoolean
    #    (prevents PowerShell from treating non-empty strings like 'False' or '0' as $true)
    if ($IsSwitchOrBool) {
        return @{
            'Status'          = 'Bound';
            'Value'           = (ConvertFrom-ModuleBoolean -Value $RawValue);
            'IsSecret'        = $false;
            'AllocatedSecret' = $null;
            'ErrorReason'     = '';
        };
    }

    # 2. SecureString conversion: copy existing SecureString instances or convert plain-text values,
    #    returning the allocated instance so the caller can Dispose() it after command execution
    if ($IsSecureString) {
        $SecureInstance = $null;

        if ($RawValue -is [System.Security.SecureString]) {
            $SecureInstance = $RawValue.Copy();
        } else {
            $SecureInstance = ConvertTo-ModuleSecureString -InputObject $RawValue;
        }

        if ($null -eq $SecureInstance) {
            return @{
                'Status'          = 'Error';
                'Value'           = $null;
                'IsSecret'        = $true;
                'AllocatedSecret' = $null;
                'ErrorReason'     = 'SecureStringConversionFailed';
            };
        }

        return @{
            'Status'          = 'Bound';
            'Value'           = $SecureInstance;
            'IsSecret'        = $true;
            'AllocatedSecret' = $SecureInstance;
            'ErrorReason'     = '';
        };
    }

    # 3. Array coercion ([array], [string[]], [int[]], [IcingaServiceStatus[]], ...):
    #    skip unset null/""/empty [] values so declared plugin default arrays remain intact
    if ($IsArrayParam) {
        if ($null -eq $RawValue -or ($RawValue -is [string] -and $RawValue.Length -eq 0)) {
            return @{
                'Status'          = 'Skipped';
                'Value'           = $null;
                'IsSecret'        = $false;
                'AllocatedSecret' = $null;
                'ErrorReason'     = '';
            };
        }

        [type]$ElemType = $null;
        if ($ParamType.IsArray) {
            $ElemType = $ParamType.GetElementType();
        }

        [bool]$IsTypedValueOrEnum = ($null -ne $ElemType -and ($ElemType.IsEnum -or $ElemType.IsValueType));

        # Array coercion: skip empty [] lists so plugin default arrays remain intact,
        # and coerce individual elements for typed value/enum arrays (int[], IcingaServiceStatus[], etc.).
        if ($RawValue -is [System.Collections.IList] -and $RawValue -isnot [string]) {
            if ($RawValue.Count -eq 0) {
                return @{
                    'Status'          = 'Skipped';
                    'Value'           = $null;
                    'IsSecret'        = $false;
                    'AllocatedSecret' = $null;
                    'ErrorReason'     = '';
                };
            }

            if (-not $IsTypedValueOrEnum) {
                if ($ElemType -eq [string]) {
                    [array]$CastStrings = @();
                    foreach ($StrElem in $RawValue) {
                        $CastStrings += [string]$StrElem;
                    }

                    return @{
                        'Status'          = 'Bound';
                        'Value'           = $CastStrings;
                        'IsSecret'        = $false;
                        'AllocatedSecret' = $null;
                        'ErrorReason'     = '';
                    };
                }

                return @{
                    'Status'          = 'Bound';
                    'Value'           = @($RawValue);
                    'IsSecret'        = $false;
                    'AllocatedSecret' = $null;
                    'ErrorReason'     = '';
                };
            }

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

            if ($FilteredItems.Count -eq 0) {
                return @{
                    'Status'          = 'Skipped';
                    'Value'           = $null;
                    'IsSecret'        = $false;
                    'AllocatedSecret' = $null;
                    'ErrorReason'     = '';
                };
            }

            return @{
                'Status'          = 'Bound';
                'Value'           = $FilteredItems;
                'IsSecret'        = $false;
                'AllocatedSecret' = $null;
                'ErrorReason'     = '';
            };
        }

        if ($IsTypedValueOrEnum -and $RawValue -is [string] -and [string]::IsNullOrWhiteSpace($RawValue)) {
            return @{
                'Status'          = 'Skipped';
                'Value'           = $null;
                'IsSecret'        = $false;
                'AllocatedSecret' = $null;
                'ErrorReason'     = '';
            };
        }

        [array]$SingleWrapped = @( $RawValue );

        if ($IsTypedValueOrEnum) {
            if ($ElemType -eq [bool]) {
                $SingleWrapped = @( (ConvertFrom-ModuleBoolean -Value $RawValue) );
            } else {
                $ConvertedSingle = $RawValue -as $ElemType;
                if ($null -ne $ConvertedSingle) {
                    $SingleWrapped = @( $ConvertedSingle );
                }
            }
        } elseif ($ElemType -eq [string] -and $RawValue -isnot [string]) {
            $SingleWrapped = @( [string]$RawValue );
        }

        return @{
            'Status'          = 'Bound';
            'Value'           = $SingleWrapped;
            'IsSecret'        = $false;
            'AllocatedSecret' = $null;
            'ErrorReason'     = '';
        };
    }

    # 4. Scalar numeric & enum coercion: skip blank strings and empty [] lists before converting via '-as'
    if ($IsNumericOrEnum) {
        [bool]$IsEmptyNumericList = ($RawValue -is [System.Collections.IList] -and $RawValue -isnot [string] -and $RawValue.Count -eq 0);

        if ($null -eq $RawValue -or $IsEmptyNumericList -or ($RawValue -is [string] -and [string]::IsNullOrWhiteSpace($RawValue))) {
            return @{
                'Status'          = 'Skipped';
                'Value'           = $null;
                'IsSecret'        = $false;
                'AllocatedSecret' = $null;
                'ErrorReason'     = '';
            };
        }

        $ConvertedNumeric = $RawValue -as $ParamType;
        [object]$NumVal   = $RawValue;

        if ($null -ne $ConvertedNumeric) {
            $NumVal = $ConvertedNumeric;
        }

        return @{
            'Status'          = 'Bound';
            'Value'           = $NumVal;
            'IsSecret'        = $false;
            'AllocatedSecret' = $null;
            'ErrorReason'     = '';
        };
    }

    # 5. Scalar string / object fallback: skip empty [] lists and blank values that violate ValidateSet / ValidatePattern
    [bool]$IsEmptyScalarList = ($RawValue -is [System.Collections.IList] -and $RawValue -isnot [string] -and $RawValue.Count -eq 0);
    if ($IsEmptyScalarList) {
        return @{
            'Status'          = 'Skipped';
            'Value'           = $null;
            'IsSecret'        = $false;
            'AllocatedSecret' = $null;
            'ErrorReason'     = '';
        };
    }

    if ($RawValue -is [string] -and [string]::IsNullOrWhiteSpace($RawValue) -and $null -ne $ParameterMetadata.Attributes) {
        [bool]$SkipBlankConstrained = $false;

        foreach ($Attr in $ParameterMetadata.Attributes) {
            if ($Attr -is [System.Management.Automation.ValidateSetAttribute] -and ($Attr.ValidValues -notcontains $RawValue)) {
                $SkipBlankConstrained = $true;
                break;
            }

            if ($Attr -is [System.Management.Automation.ValidatePatternAttribute]) {
                $SkipBlankConstrained = $true;
                break;
            }
        }

        if ($SkipBlankConstrained) {
            return @{
                'Status'          = 'Skipped';
                'Value'           = $null;
                'IsSecret'        = $false;
                'AllocatedSecret' = $null;
                'ErrorReason'     = '';
            };
        }
    }

    [object]$FinalValue = $RawValue;
    if ($ParamType -eq [string] -and $null -ne $RawValue -and $RawValue -isnot [string]) {
        $FinalValue = [string]$RawValue;
    }

    return @{
        'Status'          = 'Bound';
        'Value'           = $FinalValue;
        'IsSecret'        = $false;
        'AllocatedSecret' = $null;
        'ErrorReason'     = '';
    };
}

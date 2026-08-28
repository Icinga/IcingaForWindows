<#
.SYNOPSIS
Structured error object returned by data collection functions instead of throwing

.DESCRIPTION
IcingaError describes why a data collection step failed, so a function that
gathers data for a plugin (for example Get-IcingaWindowsInformation) can return
it in place of the data instead of throwing. The caller checks the result with
Test-IcingaError and hands it to IcingaPlugin.SetError, which puts the node into
UNKNOWN with the error message.

Message holds the final, human-readable text. It can be built from a format
string and arguments in the style of [string]::Format ('Failed to query {0}',
'Win32_Service'). ReturnCode carries the semantic key of the return-code table
(Set-InternalExitCodes) when the error went through Write-FunctionReturnValue,
and Data holds the context values of the failure.

.OUTPUTS
IcingaError — Error object with message, return code and context data.

.EXAMPLE
PS> ('IcingaError' -as [type])::new('Failed to query the class {0}: {1}', @('Win32_Service', 'Access denied'))

Creates an error with the message 'Failed to query the class Win32_Service:
Access denied'.

.NOTES
Pure data object without external dependencies. Defined before IcingaPlugin in
the kernel, so IcingaPlugin may use it as a parameter type.

Functions create and test errors through the type of the current runspace
(('IcingaError' -as [type]) and Test-IcingaError), never with an [IcingaError]
literal. Every runspace shares the compiled kernel, so the literal resolves to
the type of the main runspace; inside a background thread the error would then
not match the thread's own IcingaError type that IcingaPlugin.SetError expects.
#>
class IcingaError
{
    [string]$Message    = '';
    [string]$ReturnCode = '';
    [hashtable]$Data    = @{ };

    <#
    .SYNOPSIS
    Create an error from a plain message

    .DESCRIPTION
    Creates an error whose message is used verbatim, without format processing,
    so braces such as those of volume GUIDs are kept as they are.

    .PARAMETER Message
    | Name    | Type          | Description                  | Default |
    |---------|---------------|------------------------------|---------|
    | Message | System.String | Human-readable error message. |        |

    .OUTPUTS
    IcingaError — The error object.

    .EXAMPLE
    PS> ('IcingaError' -as [type])::new('The performance counter category is missing')

    .NOTES
    No format processing is applied.
    #>
    IcingaError([string]$Message)
    {
        $this.Message = $Message;
    }

    <#
    .SYNOPSIS
    Create an error from a format string and its arguments

    .DESCRIPTION
    Creates an error whose message is the format string with its placeholders
    ('{0}', '{1}', ...) replaced by the arguments, like [string]::Format.

    .PARAMETER Message
    | Name    | Type          | Description                                 | Default |
    |---------|---------------|---------------------------------------------|---------|
    | Message | System.String | Format string with '{0}'-style placeholders. |        |

    .PARAMETER Arguments
    | Name      | Type            | Description                          | Default |
    |-----------|-----------------|--------------------------------------|---------|
    | Arguments | System.Object[] | Values inserted into the placeholders. |       |

    .OUTPUTS
    IcingaError — The error object.

    .EXAMPLE
    PS> ('IcingaError' -as [type])::new('Failed to query {0}', @('Win32_Volume'))

    .NOTES
    See FormatMessage for the handling of invalid format strings.
    #>
    IcingaError([string]$Message, [object[]]$Arguments)
    {
        $this.Message = [IcingaError]::FormatMessage($Message, $Arguments);
    }

    <#
    .SYNOPSIS
    Create an error that belongs to a return code of the return-code table

    .DESCRIPTION
    Creates an error with a semantic return code key (as used by
    Write-FunctionReturnValue), the final message and the context data of the
    failure.

    .PARAMETER ReturnCode
    | Name       | Type          | Description                                   | Default |
    |------------|---------------|-----------------------------------------------|---------|
    | ReturnCode | System.String | Semantic key of the return-code table entry.  |         |

    .PARAMETER Message
    | Name    | Type          | Description                   | Default |
    |---------|---------------|-------------------------------|---------|
    | Message | System.String | Human-readable error message. |         |

    .PARAMETER Data
    | Name | Type                         | Description                     | Default |
    |------|------------------------------|---------------------------------|---------|
    | Data | System.Collections.Hashtable | Context values of the failure.  |         |

    .OUTPUTS
    IcingaError — The error object.

    .EXAMPLE
    PS> ('IcingaError' -as [type])::new('WindowsInformationClassUnknown', 'The class Foo is unknown', @{ 'ClassName' = 'Foo'; })

    .NOTES
    A $null Data value is stored as an empty hashtable.
    #>
    IcingaError([string]$ReturnCode, [string]$Message, [hashtable]$Data)
    {
        $this.ReturnCode = $ReturnCode;
        $this.Message    = $Message;

        if ($null -ne $Data) {
            $this.Data = $Data;
        }
    }

    <#
    .SYNOPSIS
    Format a message with its arguments without ever throwing

    .DESCRIPTION
    Replaces the '{0}'-style placeholders of the message with the arguments. A
    message without arguments is returned unchanged. When the message is no valid
    format string (for example a literal '{' with arguments given), the arguments
    are appended to the message instead, so an error report never fails itself.

    .PARAMETER Message
    | Name    | Type          | Description                                  | Default |
    |---------|---------------|----------------------------------------------|---------|
    | Message | System.String | Format string with '{0}'-style placeholders. |         |

    .PARAMETER Arguments
    | Name      | Type            | Description                            | Default |
    |-----------|-----------------|----------------------------------------|---------|
    | Arguments | System.Object[] | Values inserted into the placeholders. |         |

    .OUTPUTS
    System.String — The formatted message.

    .EXAMPLE
    PS> ('IcingaError' -as [type])::FormatMessage('Failed to query {0}', @('Win32_Volume'))

    .NOTES
    Shared by IcingaError and IcingaPlugin.SetError.
    #>
    static [string] FormatMessage([string]$Message, [object[]]$Arguments)
    {
        if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
            return $Message;
        }

        try {
            return [string]::Format($Message, [object[]]$Arguments);
        } catch {
            $Error.Clear();
        }

        return ([string]::Format('{0} ({1})', $Message, ($Arguments -join ', ')));
    }

    <#
    .SYNOPSIS
    Return the error message

    .DESCRIPTION
    Returns the message, so the error renders as its text in strings and logs.

    .OUTPUTS
    System.String — The error message.

    .EXAMPLE
    PS> [string]$IcingaError

    .NOTES
    Overrides Object.ToString.
    #>
    [string] ToString()
    {
        return $this.Message;
    }
}

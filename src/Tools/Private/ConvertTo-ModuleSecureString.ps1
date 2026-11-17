<#
.SYNOPSIS
Convert plain-text or existing secret input into a SecureString safely

.DESCRIPTION
ConvertTo-ModuleSecureString converts plain-text strings delivered through
Icinga 2 command macros into read-only System.Security.SecureString instances
via direct character population (AppendChar + MakeReadOnly), avoiding both
ConvertTo-SecureString -AsPlainText analyzer errors and empty-string
ParameterBindingException failures on Windows PowerShell 5.1. Null values
return $null, existing SecureString instances are returned unchanged, and
conversion errors emit SecureStringConversionFailed via
Write-FunctionReturnValue and return $null.

.PARAMETER InputObject
| Name        | Type          | Description                                                 | Default |
|-------------|---------------|-------------------------------------------------------------|---------|
| InputObject | System.Object | Plain-text string, SecureString or null value to normalize. | $null   |

.OUTPUTS
System.Security.SecureString -- Converted SecureString instance, or $null when
InputObject is $null or conversion fails (SecureStringConversionFailed).

.EXAMPLE
PS> $secret = ConvertTo-ModuleSecureString -InputObject 'MySecretValue'

Converts the plain-text string into a SecureString instance.

.NOTES
Compatible with Windows PowerShell 5.1 and PowerShell 7+. Callers that allocate
temporary SecureString instances for check execution should call Dispose() once
the check finishes.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function ConvertTo-ModuleSecureString()
{
    param (
        [object]$InputObject = $null
    );

    if ($null -eq $InputObject) {
        return $null;
    }

    if ($InputObject -is [System.Security.SecureString]) {
        return $InputObject;
    }

    # Populate SecureString character-by-character and seal with MakeReadOnly() so empty strings work
    # on Windows PowerShell 5.1 without triggering ConvertTo-SecureString -AsPlainText analyzer errors
    [string]$PlainText  = [string]$InputObject;
    $SecureStringResult = New-Object System.Security.SecureString;

    try {
        for ($i = 0; $i -lt $PlainText.Length; $i++) {
            $SecureStringResult.AppendChar($PlainText[$i]);
        }

        $SecureStringResult.MakeReadOnly();
        return $SecureStringResult;
    } catch {
        # Dispose partially populated instance and log via Write-FunctionReturnValue without exposing the secret text
        $SecureStringResult.Dispose();
        return (Write-FunctionReturnValue -ReturnValue 'SecureStringConversionFailed' -Data @{ 'ExceptionMessage' = $_.Exception.Message; } -OverrideReturn $null);
    }
}

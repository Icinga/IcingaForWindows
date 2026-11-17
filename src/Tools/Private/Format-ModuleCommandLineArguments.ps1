<#
.SYNOPSIS
Format an array of CLI tokens using Windows CommandLineToArgvW quoting rules

.DESCRIPTION
Format-ModuleCommandLineArguments escapes and space-joins an array of argument
tokens according to the Windows C runtime and CommandLineToArgvW specification:
empty tokens become '""', tokens without whitespace or double quotes remain
unquoted, and tokens containing whitespace or double quotes are wrapped in
double quotes with preceding backslashes doubled before embedded quotes and
before the closing quote.

.PARAMETER Arguments
| Name      | Type         | Description                                    | Default |
|-----------|--------------|------------------------------------------------|---------|
| Arguments | System.Array | Ordered CLI argument tokens to quote and join. | @()     |

.OUTPUTS
System.String -- Space-joined, CommandLineToArgvW-compliant argument string.

.EXAMPLE
PS> Format-ModuleCommandLineArguments -Arguments @('-H', 'X-Test: 1', 'C:\Trailing\')
-H "X-Test: 1" C:\Trailing\

Quotes tokens containing spaces or quotes while leaving simple tokens intact.

.NOTES
Pure string formatter with no external dependencies or global state access.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Format-ModuleCommandLineArguments()
{
    param (
        [array]$Arguments = @()
    );

    if ($null -eq $Arguments -or $Arguments.Count -eq 0) {
        return '';
    }

    [array]$QuotedTokens = @();

    foreach ($Token in $Arguments) {
        [string]$TextToken = [string]$Token;

        if ($TextToken.Length -eq 0) {
            $QuotedTokens += '""';
        } elseif ($TextToken -notmatch '[\s"]') {
            $QuotedTokens += $TextToken;
        } else {
            # CommandLineToArgvW rule: backslashes only require doubling immediately before '"' or the closing '"'
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

    return ($QuotedTokens -join ' ');
}

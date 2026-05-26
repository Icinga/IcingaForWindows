<#
.SYNOPSIS
Format a markup-colored logging message for console output.

.DESCRIPTION
`Format-LoggingConsoleMessage` parses simple color markup tokens (e.g. [Red]...[/Red])
and returns either a formatted string or writes the colored message to the host.

.PARAMETER Message
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Message | System.String | Message containing optional color tags | |

.PARAMETER GetMsgObj
| Name | Type | Description | Default |
|------|------|-------------|---------|
| GetMsgObj | System.SwitchParameter | When set the function returns the formatted string instead of writing to host | `$false` |

.OUTPUTS
System.String — The formatted message string when `-GetMsgObj` is set; otherwise None, the message is written directly to the host.

.EXAMPLE
PS> Format-LoggingConsoleMessage -Message '[Green]OK[/Green] Completed' -GetMsgObj

.NOTES
Supports escaping and validates color names against `System.ConsoleColor`.
#>
function Format-LoggingConsoleMessage()
{
    param (
        [string]$Message   = $null,
        [switch]$GetMsgObj = $false
    );

    # Do nothing if the message is empty
    if ([string]::IsNullOrEmpty($Message)) {
        if ($GetMsgObj) {
            return $null;
        }

        return;
    }

    $StringBuilder = New-Object System.Text.StringBuilder;

    # Allowed colors (optional restriction)
    $validColors  = [enum]::GetNames([System.ConsoleColor]);
    $currentIndex = 0

    while ($currentIndex -lt $Message.Length) {
        # Find next opening tag: [color]
        $openMatch = [regex]::Match(
            $Message.Substring($currentIndex),
            '^\[([a-zA-Z]+)\]|(?<!\\)\[([a-zA-Z]+)\]'
        );

        # Check if we found an opening tag
        if (-not $openMatch.Success) {
            # No more tags: output the rest normally
            if ($GetMsgObj) {
                $StringBuilder.Append($Message.Substring($currentIndex)) | Out-Null;
            } else {
                Write-Host ($Message.Substring($currentIndex)) -NoNewline;
            }
            break;
        }

        # Calculate absolute index of the match in the original string
        $openIndex  = $currentIndex + $openMatch.Index;
        $openLength = $openMatch.Length;
        $colorName  = '';

        # Determine the color name from the correct capturing group
        if ($openMatch.Groups[1].Value -ne '') {
            $colorName = $openMatch.Groups[1].Value
        } else {
            $colorName = $openMatch.Groups[2].Value
        }

        # Output text before the opening tag
        if ($openIndex -gt $currentIndex) {
            $plain = $Message.Substring($currentIndex, $openIndex - $currentIndex);
            if ($GetMsgObj) {
                $StringBuilder.Append($plain) | Out-Null;
            } else {
                Write-Host $plain -NoNewline;
            }
        }

        # Invalid color -> output tag as text only
        if ($validColors -notcontains $colorName) {
            if ($GetMsgObj) {
                $StringBuilder.Append($Message.Substring($openIndex, $openLength)) | Out-Null;
            } else {
                Write-Host ($Message.Substring($openIndex, $openLength)) -NoNewline;
            }
            $currentIndex = $openIndex + $openLength;
            continue;
        }

        # Find the closing tag: [/color]
        $closeTag   = [string]::Format('[/{0}]', $colorName);
        $closeIndex = $Message.IndexOf($closeTag, $openIndex + $openLength);

        # Check if we found a closing tag
        if ($closeIndex -lt 0) {
            # No closing tag: output opening tag as text
            if ($GetMsgObj) {
                $StringBuilder.Append($Message.Substring($openIndex, $openLength)) | Out-Null;
            } else {
                Write-Host ($Message.Substring($openIndex, $openLength)) -NoNewline;
            }
            $currentIndex = $openIndex + $openLength;
            continue;
        }

        # Output content between the tags in color
        $contentStart  = $openIndex + $openLength;
        $contentLength = $closeIndex - $contentStart;
        $content       = $Message.Substring($contentStart, $contentLength);

        # Output content between the tags in color
        if ($contentLength -gt 0) {
            if ($GetMsgObj) {
                $StringBuilder.Append($content) | Out-Null;
            } else {
                Write-Host $content -ForegroundColor $colorName -NoNewline;
            }
        }

        # Set index behind the closing tag
        $currentIndex = $closeIndex + $closeTag.Length;
    }

    # Line break at the end
    if ($GetMsgObj) {
        return $StringBuilder.ToString().Trim();
    } else {
        Write-Host;
    }
}

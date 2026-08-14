<#
.SYNOPSIS
Render complex objects into a readable, colorized console representation.

.DESCRIPTION
`Format-LoggingConsoleObjects` handles arrays, hashtables, PSCustomObjects and
several special CLR types (TcpClient, SslStream, X509Certificate2, TcpListener)
and returns a string with structured, colorized output for logging.

.PARAMETER Object
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Object | System.Object | The object to format for console output | |

.PARAMETER Level
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Level | System.Int32 | Indentation/nesting level for pretty printing | 0 |

.OUTPUTS
System.String — A formatted multi-line representation of the object.

.EXAMPLE
PS> Format-LoggingConsoleObjects -Object $response -Level 1

.NOTES
This function delegates to other helpers (scalar, properties, nested access)
and is the central place for human-friendly logging formatting.
#>
function Format-LoggingConsoleObjects()
{
    param (
        $Object     = $null,
        [int]$Level = 0
    );

    [string]$Indent = ' ' * ($Level * 4);
    [string]$Prefix = '';

    # Only add tree prefix for levels > 0
    if ($Level -eq 0) {
        $Prefix = '';
    } else {
        $Prefix = '└── '
    };

    # Compute current indentation
    $Indent        = [string]::Format('{0}{1}', $Indent, $Prefix);
    $StringBuilder = New-Object System.Text.StringBuilder;

    # Add a leading newline for top-level calls for better separation
    if ($Level -eq 0) {
        $StringBuilder.AppendLine('') | Out-Null;
    }

    # Return formatted null value
    if ($null -eq $Object) {
        return (Format-LoggingConsoleNullValue -Indent $Indent);
    }

    # Arrays / Collections, but not strings or hashtables
    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string]) -and -not ($Object -is [System.Collections.IDictionary])) {
        [int]$index = 0;

        foreach ($item in $Object) {
            if ($Level -gt 0) {
                # If our intent is greater than 0, we show the index
                $StringBuilder.AppendLine(
                    [string]::Format(
                        '{0} [{1}]Item[{2}][/{1}]:',
                        $Indent,
                        (Get-LoggingConsoleColorForObjectType -IsParameter),
                        $index
                    )
                ) | Out-Null;
            }

            # Recursively format the child object
            $child = Format-LoggingConsoleObjects -Object $item -Level ($Level + 1);
            $lines = $child.TrimEnd("`r","`n").Split("`n");

            # Append each line of the child with proper indentation
            foreach ($line in $lines) {
                $StringBuilder.AppendLine($line.TrimEnd()) | Out-Null;
            }

            # Increment index for next item
            $index++;
        }

        # return the built string
        return $StringBuilder.ToString();
    }

    # Hashtable
    if ($Object -is [System.Collections.IDictionary]) {
        # Handle exceptions, as those are stored as hashtable
        if ($Object.ContainsKey('Exception')) {
            # Format the exception specifically, but keep the hashtable structure
            # Also append other keys in the hashtable later on
            $StringBuilder.Append(
                (Format-LoggingConsoleException -Exception $Object['Exception'] -Indent $Indent)
            ) | Out-Null;
        }

        foreach ($key in $Object.Keys) {
            $value = $Object[$key];

            # Check if the value is iterable (PSObject)
            if (Test-LoggingConsoleNextObjectIterable -Value $value) {
                # If it is iterable, print key and then recurse
                $StringBuilder.AppendLine(
                    [string]::Format(
                        '{0} [{1}]{2}[/{1}]:',
                        $Indent,
                        (Get-LoggingConsoleColorForObjectType -IsParameter),
                        $key
                    )
                ) | Out-Null;

                # Write the value recursively
                $child = Format-LoggingConsoleObjects -Object $value -Level ($Level + 1);
                $lines = $child.TrimEnd("`r","`n").Split("`n");

                # Append each line of the child with proper indentation
                foreach ($line in $lines) {
                    $StringBuilder.AppendLine($line.TrimEnd()) | Out-Null;
                }
            } else {
                # Simply print key: value in one line
                $StringBuilder.AppendLine(
                    [string]::Format(
                        '{0} [{1}]{2}[/{1}]: {3}',
                        $Indent,
                        (Get-LoggingConsoleColorForObjectType -IsParameter),
                        $key,
                        (Format-LoggingConsoleScalar -Object $value -Indent '').Trim()
                    )
                ) | Out-Null;
            }
        }

        return $StringBuilder.ToString();
    }

    # PSCustomObject and general objects (but not TcpClient or SslStream)
    if ($Object -is [PSObject] -and -not ($Object -is [System.Net.Sockets.TcpClient]) -and -not ($Object -is [System.Net.Security.SslStream]) -and -not ($Object -is [System.Security.Cryptography.X509Certificates.X509Certificate2]) -and -not ($Object -is [System.Net.Sockets.TcpListener])) {

        # Get all properties from the object efficiently without array reallocation
        $Properties = foreach ($prop in $Object.PSObject.Properties) {
            if ($prop.MemberType -eq 'NoteProperty' -or $prop.MemberType -eq 'Property') {
                $prop;
            }
        }

        foreach ($p in $Properties) {
            $value = $p.Value;

            if (Test-LoggingConsoleNextObjectIterable -Value $value) {
                $StringBuilder.AppendLine(
                    [string]::Format(
                        '{0} [{1}]{2}[/{1}]:',
                        $Indent,
                        (Get-LoggingConsoleColorForObjectType -IsParameter),
                        $p.Name
                    )
                ) | Out-Null;

                $child = Format-LoggingConsoleObjects -Object $value -Level ($Level + 1);
                $lines = $child.TrimEnd("`r","`n").Split("`n");

                # Append each line of the child with proper indentation
                foreach ($line in $lines) {
                    $StringBuilder.AppendLine($line.TrimEnd()) | Out-Null;
                }
            } else {
                # Simply print property: value in one line
                $StringBuilder.AppendLine(
                    [string]::Format(
                        '{0} [{1}]{2}[/{1}]: {3}',
                        $Indent,
                        (Get-LoggingConsoleColorForObjectType -IsParameter),
                        $p.Name,
                        (Format-LoggingConsoleScalar -Object $value -Indent '').Trim()
                    )
                ) | Out-Null;
            }
        }

        return $StringBuilder.ToString();
    }

    # TcpClient
    if ($Object -is [System.Net.Sockets.TcpClient]) {
        $StringBuilder.Append(
            (Format-LoggingConsoleTcpClient -Client $Object -Indent $Indent)
        ) | Out-Null;

        return $StringBuilder.ToString();
    }

    # SslStream
    if ($Object -is [System.Net.Security.SslStream]) {
        $StringBuilder.Append(
            (Format-LoggingConsoleSslStream -Stream $Object -Indent $Indent)
        ) | Out-Null;

        return $StringBuilder.ToString();
    }

    # TcpListener
    if ($Object -is [System.Net.Sockets.TcpListener]) {
        $StringBuilder.Append(
            (Format-LoggingConsoleTcpListener -TcpListener $Object -Indent $Indent)
        ) | Out-Null;

        return $StringBuilder.ToString();
    }

    # X509Certificate2
    if ($Object -is [System.Security.Cryptography.X509Certificates.X509Certificate2]) {
        $StringBuilder.Append(
            (Format-LoggingConsoleTlsCertificate -Certificate $Object -Indent $Indent)
        ) | Out-Null;

        return $StringBuilder.ToString();
    }

    # Fallback: scalar
    $StringBuilder.AppendLine(
        (Format-LoggingConsoleScalar -Object $Object -Indent $Indent)
    ) | Out-Null;

    # return the built string
    return $StringBuilder.ToString();
}

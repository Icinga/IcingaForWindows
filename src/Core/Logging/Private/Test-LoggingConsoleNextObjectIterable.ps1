<#
.SYNOPSIS
Determine whether an object should be treated as iterable for logging.

.DESCRIPTION
`Test-LoggingConsoleNextObjectIterable` inspects the provided value and returns
`$true` if the logging formatter should iterate its child elements, or `$false`
for scalar values such as strings.

.PARAMETER Value
| Name | Type | Description | Default |
|------|------|-------------|---------|
| Value | System.Object | The value to test for iterable printing | |

.OUTPUTS
System.Boolean — `$true` when the value is considered iterable for logging.

.EXAMPLE
PS> Test-LoggingConsoleNextObjectIterable -Value $arr

.NOTES
Strings and certain CLR types are intentionally excluded from iteration.
#>
function Test-LoggingConsoleNextObjectIterable()
{
    param (
        $Value = $null
    );

    # If the value is null, return false
    if ($null -eq $Value) {
        return $false;
    }

    # Strings are not iterable in this context
    if ($Value -is [string]) {
        return $false;
    }

    # PSObjects are iterable unless they are specifically excluded
    if ($Value -is [psobject]) {
        return $true;
    }

    # TcpClient and SsslStream are not iterable, but have child properties we want to print
    if ($Value -is [System.Net.Sockets.TcpClient] -or $Value -is [System.Net.Security.SslStream]) {
        return $true;
    }

    # X509Certificate2 is not iterable, but has child properties we want to print
    if ($Value -is [System.Security.Cryptography.X509Certificates.X509Certificate2]) {
        return $true;
    }

    # TcpListener is not iterable, but has child properties we want to print
    if ($Value -is [System.Net.Sockets.TcpListener]) {
        return $true;
    }

    # Dictionaries are iterable in this context
    if ($Value -is [System.Collections.IDictionary]) {
        return $true;
    }

    # PSObjects are considered iterable
    if ($Value -is [System.Collections.IEnumerable]) {
        return $true;
    }

    # Everything else is not iterable
    return $false;
}

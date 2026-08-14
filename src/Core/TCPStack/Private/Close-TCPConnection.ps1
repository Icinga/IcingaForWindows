<#
.SYNOPSIS
Close and dispose the active TCP client and SSL stream

.DESCRIPTION
`Close-TCPConnection` safely closes and disposes the current TCP client and
associated SSL stream stored in the global runtime variable, if present.

.OUTPUTS
None — Clears the SSL stream, TCP client and their references in the global state.

.EXAMPLE
PS> Close-TCPConnection

.NOTES
This is idempotent and swallows disposal exceptions.
#>
function Close-TCPConnection()
{
    $GlobalVariable = Get-GlobalRuntimeVariable;

    if ($null -eq $GlobalVariable.Private.TCP.Client -And $null -eq $GlobalVariable.Private.TCP.Stream) {
        return;
    }

    try {
        if ($null -ne $GlobalVariable.Private.TCP.Stream) {
            $GlobalVariable.Private.TCP.Stream.Close();
            $GlobalVariable.Private.TCP.Stream.Dispose();
        }
        $GlobalVariable.Private.TCP.Stream = $null;
    } catch {
        $GlobalVariable.Private.TCP.Stream = $null;
    }

    try {
        if ($null -ne $GlobalVariable.Private.TCP.Client) {
            $GlobalVariable.Private.TCP.Client.Close();
            $GlobalVariable.Private.TCP.Client.Dispose();
        }
        $GlobalVariable.Private.TCP.Client = $null;
    } catch {
        $GlobalVariable.Private.TCP.Client = $null;
    }
}

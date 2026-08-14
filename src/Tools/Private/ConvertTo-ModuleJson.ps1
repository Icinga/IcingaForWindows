<#
.SYNOPSIS
Converts an object to a JSON formatted string safely across PowerShell versions.

.DESCRIPTION
ConvertTo-ModuleJson provides a cross-platform, cross-version safe way to serialize
objects into JSON strings. It addresses memory leaks in Windows PowerShell 5.1
associated with the native ConvertTo-Json cmdlet when called rapidly by falling
back to System.Web.Script.Serialization.JavaScriptSerializer. In PowerShell 6
and higher, it uses the native ConvertTo-Json cmdlet.

.PARAMETER InputObject
| Name        | Type          | Description                                | Default |
|-------------|---------------|--------------------------------------------|---------|
| InputObject | System.Object | The object to serialize.                   | $null   |

.OUTPUTS
System.String — Returns a JSON string representation of the object.
Returns an empty string if the input is null or serialization fails.

.EXAMPLE
PS> $json = ConvertTo-ModuleJson -InputObject @{ key = "value" }

.NOTES
In Windows PowerShell 5.1, this function dynamically loads the System.Web.Extensions
assembly if it is not already loaded.
#>
function ConvertTo-ModuleJson()
{
    param (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $InputObject
    );

    if ($null -eq $InputObject) {
        return '';
    }

    try {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            # In PS 6+, the native cmdlet is safe and fast
            return (ConvertTo-Json -InputObject $InputObject -Depth 100 -Compress);
        } else {
            if (-not ('System.Web.Script.Serialization.JavaScriptSerializer' -as [type])) {
                Add-Type -AssemblyName System.Web.Extensions;
            }

            $Serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer;
            $Serializer.MaxJsonLength = 2147483647;
            
            return $Serializer.Serialize($InputObject);
        }
    } catch {
        Write-LoggingEntry -Message 'Failed to serialize object to JSON string' -Level 'Error' -Data @{ 'ExceptionMessage' = $_.Exception.Message; };
    }

    return '';
}

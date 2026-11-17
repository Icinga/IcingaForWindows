<#
.SYNOPSIS
Check whether a RestApi space exposes an ApiCommandExecution field.

.DESCRIPTION
Validates that a provided space configuration contains an `ApiCommandExecution`
entry which indicates that an executable API command is configured for the
space. Returns boolean-like structured return codes via
`Write-FunctionReturnValue`.

.PARAMETER Space
| Name  | Type           | Description                            | Default |
|-------|----------------|----------------------------------------|---------|
| Space | PSCustomObject | Space configuration object to inspect. |         |

.OUTPUTS
System.Boolean -- `$true` when `ApiCommandExecution` is present, `$false` otherwise,
wrapped via `Write-FunctionReturnValue`.

.EXAMPLE
PS> Test-RestApiCommandExecutionField -Space $space

.NOTES
Used by routing logic to decide whether to invoke a command or render
sub-endpoints for a space.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Test-RestApiCommandExecutionField()
{
    param (
        [PSCustomObject]$Space = $null
    );

    if ($null -eq $Space) {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiSpaceMissing' -OverrideReturn $false);
    };

    try {
        # Check if ApiCommandExecution field exists in the provided segments object
        if ($null -ne $Space.ApiCommandExecution) {
            return (Write-FunctionReturnValue -ReturnValue 'RestApiApiCommandExecutionFieldExists' -Data @{ 'Space' = $Space; } -OverrideReturn $true);
        } else {
            return (Write-FunctionReturnValue -ReturnValue 'RestApiApiCommandExecutionFieldNotFound' -Data @{ 'Space' = $Space; } -OverrideReturn $false);
        };
    } catch {
        return (Write-FunctionReturnValue -ReturnValue 'RestApiApiCommandExecutionFieldTestError' -Data @{ 'Space' = $_.Exception; } -OverrideReturn $false);
    };
}

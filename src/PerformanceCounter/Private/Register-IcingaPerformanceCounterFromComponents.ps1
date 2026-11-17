<#
.SYNOPSIS
Discover component-declared performance counters by scanning the compiled kernel

.DESCRIPTION
`Register-IcingaPerformanceCounterFromComponents` parses the compiled module kernel
(`lib\IcingaForWindows.Kernel.ps1`, which contains every source file concatenated) and
finds all calls to `New-IcingaPerformanceCounter`. For each call it extracts the literal
counter paths passed to the `-Counter` parameter and registers them in the global store.
No component code is executed -- the declaration is read statically from the syntax tree.

This runs once during performance-counter environment initialization so that every
counter any component declares is warmed as soon as the daemon starts.

.OUTPUTS
None -- Populates `(Get-GlobalRuntimeVariable).Public.PerformanceCounter.Registered`.

.EXAMPLE
PS> Register-IcingaPerformanceCounterFromComponents

.NOTES
Only literal array/string arguments are discoverable. The kernel file is produced by
`Build-ModuleProject`; if it is missing the discovery step is skipped.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Register-IcingaPerformanceCounterFromComponents()
{
    $Store = (Get-GlobalRuntimeVariable).Public.PerformanceCounter;

    if ($null -eq $Store) {
        return;
    }

    [string]$KernelPath = Join-Path -Path (Get-ModuleRootDirectory) -ChildPath (Join-Path -Path 'lib' -ChildPath 'IcingaForWindows.Kernel.ps1');

    if (-not (Test-Path -Path $KernelPath)) {
        return;
    }

    $Tokens        = $null;
    $Errors        = $null;
    $Ast           = [System.Management.Automation.Language.Parser]::ParseFile($KernelPath, [ref]$Tokens, [ref]$Errors);
    $Calls         = $Ast.FindAll(
        {
            param ($Node)
            $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'New-IcingaPerformanceCounter'
        },
        $true
    );
    [datetime]$Now = (Get-Date);

    foreach ($Call in $Calls) {
        $Elements = $Call.CommandElements;

        for ($Index = 0; $Index -lt $Elements.Count; $Index++) {
            $Element = $Elements[$Index];

            if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) {
                continue;
            }

            if ($Element.ParameterName -ine 'Counter') {
                continue;
            }

            # The argument can be attached to the parameter (-Counter:@(...)) or be the
            # following command element (-Counter @(...)).
            $Argument = $Element.Argument;

            if ($null -eq $Argument -and ($Index + 1) -lt $Elements.Count) {
                $Argument = $Elements[$Index + 1];
            }

            foreach ($Path in (Get-IcingaPerformanceCounterLiteral -Argument $Argument)) {
                if (-not [string]::IsNullOrEmpty($Path)) {
                    $Store.Registered[$Path] = $Now;
                }
            }
        }
    }
}

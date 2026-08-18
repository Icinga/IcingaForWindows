@{
    # PSScriptAnalyzer configuration for Icinga for Windows.
    #
    # Picked up automatically by the CI code-style gate
    # (build/Invoke-ScriptAnalysis.ps1) and by editor integrations such as the
    # VS Code PowerShell extension.
    #
    # The full default rule set runs, EXCEPT the rules below. Each exclusion
    # reflects a deliberate decision from the documented house style or runtime
    # design (see CLAUDE.md) — keeping them on would only produce noise.
    #
    # Note: a small set of rules is additionally treated as build-breaking
    # ERRORS by Invoke-ScriptAnalysis.ps1 (PSUseApprovedVerbs,
    # PSAvoidUsingCmdletAliases). PSScriptAnalyzer settings cannot change a
    # rule's severity, so that elevation lives in the runner script.
    ExcludeRules = @(
        # House style is UTF-8 *without* BOM (the build writer uses UTF8Encoding($false)).
        'PSUseBOMForUnicodeEncodedFile',

        # $Global:IcingaForWindows is the documented, synchronized runtime state
        # shared across threads. Global scope here is intentional, not a smell.
        'PSAvoidGlobalVars',

        # Bootstrap functions in IcingaForWindows.psm1 are intentionally declared
        # in the Global: scope so they are available before the module is fully loaded.
        'PSAvoidGlobalFunctions',

        # The module does not use the ShouldProcess / -WhatIf pattern. New-/Set-/Remove-
        # functions manage internal runtime state, not user-facing resources.
        'PSUseShouldProcessForStateChangingFunctions',

        # Show-*s and other collection-returning helpers use plural nouns on purpose.
        'PSUseSingularNouns',

        # Write-Host is used by design in the build scripts and the logging console
        # formatter. The "no Write-Host in source" rule from CLAUDE.md is enforced by
        # review for the remaining source, not by the analyzer.
        'PSAvoidUsingWriteHost',
        # OutputType attributes are omitted on build and internal helper functions.
        'PSUseOutputTypeCorrectly'
    );
}

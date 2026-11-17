<#
.SYNOPSIS
Fast Pester unit test suite for the Icinga for Windows code-styling and SPDX validator

.DESCRIPTION
Validates the parser, AST, function-scope, vertical-alignment, encoding, manifest,
and SPDX license enforcement logic of `build/Test-ModuleCodeStyling.ps1` against
synthetic `$TestDrive` fixtures. Repository-wide scanning executes once via
`build/Test-ModuleCodeStyling.ps1` in the CI `analyze` job so `Invoke-ModuleTests.ps1`
never scans the repository tree a second time.

.NOTES
Calls `build/Test-ModuleCodeStyling.ps1` with `-PassThru` against `$TestDrive`.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>

$ModulePath = Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..') -ChildPath 'IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Test-ModuleCodeStyling Validator Rules' {
    BeforeAll {
        $script:ModuleRoot  = [System.IO.Path]::GetFullPath((Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath);
        $script:StyleScript = Join-Path -Path (Join-Path -Path $script:ModuleRoot -ChildPath 'build') -ChildPath 'Test-ModuleCodeStyling.ps1';
        $script:Utf8NoBom   = New-Object System.Text.UTF8Encoding($false);
    }

    Context 'Compliant synthetic files across src/, build/, psd1, and lib/' {
        It 'accepts compliant src/ function and class files with .NOTES and SPDX headers' {
            [string]$SandboxRoot = Join-Path -Path $TestDrive -ChildPath 'CompliantRepo';
            [string]$SrcPubDir   = Join-Path -Path (Join-Path -Path $SandboxRoot -ChildPath 'src') -ChildPath 'Public';
            [string]$SrcClsDir   = Join-Path -Path (Join-Path -Path $SandboxRoot -ChildPath 'src') -ChildPath 'Classes';
            [string]$BuildDir    = Join-Path -Path $SandboxRoot -ChildPath 'build';
            [string]$LibDir      = Join-Path -Path $SandboxRoot -ChildPath 'lib';

            foreach ($Dir in @( $SrcPubDir, $SrcClsDir, $BuildDir, $LibDir )) {
                New-Item -Path $Dir -ItemType Directory -Force | Out-Null;
            }

            [string]$GoodFnFile  = Join-Path -Path $SrcPubDir -ChildPath 'Get-IcingaSample.ps1';
            [string]$GoodFnBody  = @(
                '<#',
                '.SYNOPSIS',
                'Return a sample value for unit testing',
                '',
                '.PARAMETER Name',
                '| Name | Type          | Description     | Default |',
                '|------|---------------|-----------------|---------|',
                '| Name | System.String | Sample name key | $null   |',
                '',
                '.NOTES',
                'Synthetic unit test fixture.',
                '',
                'SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                'SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                'function Get-IcingaSample()',
                '{',
                '    param (',
                '        [string]$Name = $null',
                '    );',
                '',
                '    [int]$Short   = 1;',
                '    [string]$Long = $Name;',
                '',
                '    if ([string]::IsNullOrEmpty($Long)) {',
                '        return $Short;',
                '    }',
                '',
                '    return $Long;',
                '}',
                ''
            ) -join "`n";

            [string]$GoodClsFile = Join-Path -Path $SrcClsDir -ChildPath 'SampleStatus.ps1';
            [string]$GoodClsBody = @(
                '<#',
                '.SYNOPSIS',
                'Sample status enum for unit testing',
                '',
                '.NOTES',
                'Synthetic enum fixture.',
                '',
                'SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                'SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                'enum SampleStatus',
                '{',
                '    Ok       = 0;',
                '    Critical = 2;',
                '}',
                ''
            ) -join "`n";

            [string]$GoodBldFile = Join-Path -Path $BuildDir -ChildPath 'Invoke-SampleBuild.ps1';
            [string]$GoodBldBody = @(
                '<#',
                '.SYNOPSIS',
                'Sample build script permitting helper and nested functions',
                '',
                '.NOTES',
                'Build scripts allow multiple and nested functions.',
                '',
                'SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                'SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                'function Invoke-OuterBuildHelper()',
                '{',
                '    function Invoke-NestedBuildHelper()',
                '    {',
                '        return $true;',
                '    }',
                '',
                '    return (Invoke-NestedBuildHelper);',
                '}',
                '',
                'function Invoke-SecondBuildHelper()',
                '{',
                '    return (Invoke-OuterBuildHelper);',
                '}',
                ''
            ) -join "`n";

            [string]$GoodPsd1    = Join-Path -Path $SandboxRoot -ChildPath 'IcingaForWindows.psd1';
            [string]$GoodPsdBody = @(
                '@{',
                '    ModuleVersion = ''27.0.0'';',
                '    Copyright     = ''(c) 2026 Icinga GmbH | GPL-3.0-or-later'';',
                '    PrivateData   = @{',
                '        Endpoint = '''';',
                '        SPDX     = '''';',
                '        # SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                '        # SPDX-License-Identifier: GPL-3.0-or-later',
                '    };',
                '}',
                ''
            ) -join "`n";

            [string]$GoodLibFile = Join-Path -Path $LibDir -ChildPath 'IcingaForWindows.Kernel.ps1';
            [string]$GoodLibBody = @(
                '<#',
                '.SYNOPSIS',
                '    Icinga for Windows - Kernel Module',
                '.NOTES',
                '    Source: src',
                '',
                '    SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                '    SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($GoodFnFile, $GoodFnBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($GoodClsFile, $GoodClsBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($GoodBldFile, $GoodBldBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($GoodPsd1, $GoodPsdBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($GoodLibFile, $GoodLibBody, $script:Utf8NoBom);

            [array]$Violations   = & $script:StyleScript -ModuleBasePath $SandboxRoot -PassThru;
            $Violations | Should -BeNullOrEmpty -Because ($Violations -join "`n");
        }
    }

    Context 'Function scope enforcement (src/ vs. build/) and SPDX header checks' {
        It 'forbids nested functions and multiple top-level functions under src/ and standalone functions under src/Classes/' {
            [string]$ScopeRoot = Join-Path -Path $TestDrive -ChildPath 'ScopeRepo';
            [string]$SrcPrvDir = Join-Path -Path (Join-Path -Path $ScopeRoot -ChildPath 'src') -ChildPath 'Private';
            [string]$SrcClsDir = Join-Path -Path (Join-Path -Path $ScopeRoot -ChildPath 'src') -ChildPath 'Classes';

            New-Item -Path $SrcPrvDir -ItemType Directory -Force | Out-Null;
            New-Item -Path $SrcClsDir -ItemType Directory -Force | Out-Null;

            [string]$BadSrcFn  = Join-Path -Path $SrcPrvDir -ChildPath 'Invoke-BadSrc.ps1';
            [string]$BadFnBody = @(
                '<#',
                '.SYNOPSIS',
                'Invalid src file with nested and extra functions',
                '',
                '.NOTES',
                'SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                'SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                'function Invoke-BadSrc()',
                '{',
                '    function Invoke-ForbiddenInner()',
                '    {',
                '        return 1;',
                '    }',
                '',
                '    return (Invoke-ForbiddenInner);',
                '}',
                '',
                'function Invoke-SecondTopLevel()',
                '{',
                '    return 2;',
                '}',
                ''
            ) -join "`n";

            [string]$BadClsFn  = Join-Path -Path $SrcClsDir -ChildPath 'BadClassFile.ps1';
            [string]$BadClsTxt = @(
                '<#',
                '.SYNOPSIS',
                'Class file with forbidden standalone function',
                '',
                '.NOTES',
                'SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                'SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                'class BadClassFile',
                '{',
                '}',
                '',
                'function Get-ForbiddenInClasses()',
                '{',
                '    return $null;',
                '}',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($BadSrcFn, $BadFnBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($BadClsFn, $BadClsTxt, $script:Utf8NoBom);

            [array]$Violations = & $script:StyleScript -ModuleBasePath $ScopeRoot -Path @( $BadSrcFn, $BadClsFn ) -PassThru;
            [string]$Joined    = ($Violations -join "`n");

            $Joined | Should -Match 'Multiple top-level functions';
            $Joined | Should -Match 'Nested function "Invoke-ForbiddenInner"';
            $Joined | Should -Match 'Standalone function "Get-ForbiddenInClasses" is forbidden under src/Classes/';
        }

        It 'rejects missing .NOTES or missing SPDX lines in source, manifest, and compiled lib files' {
            [string]$SpdxRoot     = Join-Path -Path $TestDrive -ChildPath 'SpdxRepo';
            [string]$SrcDir       = Join-Path -Path (Join-Path -Path $SpdxRoot -ChildPath 'src') -ChildPath 'Private';
            [string]$LibDir       = Join-Path -Path $SpdxRoot -ChildPath 'lib';

            New-Item -Path $SrcDir -ItemType Directory -Force | Out-Null;
            New-Item -Path $LibDir -ItemType Directory -Force | Out-Null;

            [string]$NoSpdxSrc    = Join-Path -Path $SrcDir -ChildPath 'Get-NoSpdx.ps1';
            [string]$NoSpdxBody   = @(
                '<#',
                '.SYNOPSIS',
                'Missing SPDX lines inside .NOTES',
                '',
                '.NOTES',
                'Only prose notes without SPDX lines.',
                '#>',
                'function Get-NoSpdx()',
                '{',
                '    return $true;',
                '}',
                ''
            ) -join "`n";

            [string]$BadPsd1      = Join-Path -Path $SpdxRoot -ChildPath 'IcingaForWindows.psd1';
            [string]$BadPsdBody   = @(
                '@{',
                '    ModuleVersion = ''27.0.0'';',
                '    Copyright     = ''(c) 2026 Icinga GmbH | MIT'';',
                '    PrivateData   = @{',
                '        Endpoint = '''';',
                '    };',
                '}',
                ''
            ) -join "`n";

            [string]$BadLib       = Join-Path -Path $LibDir -ChildPath 'IcingaForWindows.Classes.ps1';
            [string]$BadLibBody   = @(
                '<#',
                '.SYNOPSIS',
                '    Missing SPDX header at top of lib file',
                '#>',
                ''
            ) -join "`n";

            [string]$BadSlashSrc  = Join-Path -Path $SrcDir -ChildPath 'Get-SlashSpdx.ps1';
            [string]$BadSlashBody = @(
                '<#',
                '.SYNOPSIS',
                'Rejects C-style double-slash SPDX prefix inside .NOTES',
                '',
                '.NOTES',
                ('/' + '/ SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>'),
                ('/' + '/ SPDX-License-Identifier: GPL-3.0-or-later'),
                '#>',
                'function Get-SlashSpdx()',
                '{',
                '    return $true;',
                '}',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($NoSpdxSrc, $NoSpdxBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($BadSlashSrc, $BadSlashBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($BadPsd1, $BadPsdBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($BadLib, $BadLibBody, $script:Utf8NoBom);

            [array]$Violations    = & $script:StyleScript -ModuleBasePath $SpdxRoot -Path @( $NoSpdxSrc, $BadSlashSrc, $BadPsd1, $BadLib ) -PassThru;
            [string]$Joined       = ($Violations -join "`n");

            $Joined | Should -Match 'Get-NoSpdx\.ps1.*SPDX-FileCopyrightText';
            $Joined | Should -Match 'Get-SlashSpdx\.ps1.*SPDX-FileCopyrightText';
            $Joined | Should -Match 'Copyright must specify GPL-3\.0-or-later';
            $Joined | Should -Match 'PrivateData must include "SPDX = '''';"';
            $Joined | Should -Match 'Compiled lib artifact header block: missing mandatory \.NOTES';
        }

        It 'rejects stray classes or missing functions outside src/Classes/, non-manifest .psd1 without SPDX, and indented build help missing SPDX' {
            [string]$GuardRoot    = Join-Path -Path $TestDrive -ChildPath 'GuardRepo';
            [string]$SrcPrvDir    = Join-Path -Path (Join-Path -Path $GuardRoot -ChildPath 'src') -ChildPath 'Private';
            [string]$BuildDir     = Join-Path -Path $GuardRoot -ChildPath 'build';

            New-Item -Path $SrcPrvDir -ItemType Directory -Force | Out-Null;
            New-Item -Path $BuildDir -ItemType Directory -Force | Out-Null;

            [string]$StrayTypeSrc = Join-Path -Path $SrcPrvDir -ChildPath 'StrayType.ps1';
            [string]$StrayBody    = @(
                'class MisplacedClass',
                '{',
                '}',
                ''
            ) -join "`n";

            [string]$SettingsPsd1 = Join-Path -Path $GuardRoot -ChildPath 'PSScriptAnalyzerSettings.psd1';
            [string]$SettingsBody = @(
                '@{',
                '    ExcludeRules = @();',
                '}',
                ''
            ) -join "`n";

            [string]$IndentedBld  = Join-Path -Path $BuildDir -ChildPath 'Invoke-BadHelperDoc.ps1';
            [string]$IndentedBody = @(
                '<#',
                '.SYNOPSIS',
                'Top-level build script with valid SPDX',
                '',
                '.NOTES',
                'SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                'SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                'function Invoke-HelperMissingSpdx()',
                '{',
                '    <#',
                '    .SYNOPSIS',
                '    Indented helper help block missing .NOTES and SPDX',
                '    #>',
                '    return $true;',
                '}',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($StrayTypeSrc, $StrayBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($SettingsPsd1, $SettingsBody, $script:Utf8NoBom);
            [System.IO.File]::WriteAllText($IndentedBld, $IndentedBody, $script:Utf8NoBom);

            [array]$Violations    = & $script:StyleScript -ModuleBasePath $GuardRoot -PassThru;
            [string]$Joined       = ($Violations -join "`n");

            $Joined | Should -Match 'Class or enum "MisplacedClass" is forbidden outside src/Classes/';
            $Joined | Should -Match 'must define a top-level function';
            $Joined | Should -Match 'PowerShell data file \(\.psd1\) must include "# SPDX-FileCopyrightText';
            $Joined | Should -Match 'Invoke-BadHelperDoc\.ps1:11 -- Help block: missing mandatory \.NOTES';
        }
    }

    Context 'Encoding, whitespace, AST brace, condition, and alignment violation detection' {
        It 'detects UTF-8/UTF-16 BOMs, missing or duplicate trailing newlines, non-4-space indentation, Unicode dashes, and non-ASCII characters' {
            [string]$BadFile        = Join-Path -Path $TestDrive -ChildPath 'BadBasic.ps1';
            [string]$Body           = @(
                'function Test-BadBasic()',
                '{',
                ('  [string]$Dash  = ''bad ' + [char]0x2014 + ' dash'';'),
                ('    [string]$Arrow = ''bad ' + [char]0x2192 + ' arrow'';'),
                '    return $Dash;',
                '}'
            ) -join "`n";

            # Write WITH UTF-8 BOM and WITHOUT trailing newline
            [System.IO.File]::WriteAllText($BadFile, $Body, (New-Object System.Text.UTF8Encoding($true)));
            [array]$Violations      = & $script:StyleScript -ModuleBasePath $TestDrive -Path @( $BadFile ) -PassThru;

            ($Violations -join "`n") | Should -Match 'UTF-8 BOM';
            ($Violations -join "`n") | Should -Match 'single trailing newline';
            ($Violations -join "`n") | Should -Match 'multiples of 4 spaces';
            ($Violations -join "`n") | Should -Match 'em-dash';
            ($Violations -join "`n") | Should -Match 'U\+2192';

            # Write WITH two trailing newlines
            [System.IO.File]::WriteAllText($BadFile, ($Body + "`n`n"), $script:Utf8NoBom);
            [array]$DupNlViolations = & $script:StyleScript -ModuleBasePath $TestDrive -Path @( $BadFile ) -PassThru;
            ($DupNlViolations -join "`n") | Should -Match 'multiple trailing blank lines';

            # Write WITH UTF-16 LE BOM (default of Out-File on Windows PowerShell 5.1)
            [System.IO.File]::WriteAllText($BadFile, ($Body + "`n"), [System.Text.Encoding]::Unicode);
            [array]$Utf16Violations = & $script:StyleScript -ModuleBasePath $TestDrive -Path @( $BadFile ) -PassThru;
            ($Utf16Violations -join "`n") | Should -Match 'UTF-16/UTF-32 BOM';
        }

        It 'detects K&R braces on function/class/enum, multiline if conditions, single-entry hashtable spacing, 4th-row table pipes, and string <# safety' {
            [string]$BadAstFile = Join-Path -Path $TestDrive -ChildPath 'BadAst.ps1';
            [string]$AstBody    = @(
                '<#',
                '.PARAMETER Demo',
                '| Name | Type          | Description | Default |',
                '|------|---------------|-------------|---------|',
                '| Demo | System.String | First row   | $null   |',
                '|      |               | Broken row |         |',
                '',
                '.NOTES',
                'SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>',
                'SPDX-License-Identifier: GPL-3.0-or-later',
                '#>',
                'enum BadEnum {',
                '    First  =  1',
                '}',
                'class BadClass {',
                '}',
                'function Test-BadFunc {',
                '    [string]$Marker = ''<# not a real comment'';',
                '    [int]$BadAlign      = 1;',
                '    [hashtable]$Single = @{',
                '        ''OnlyKey''   =  ''Val'';',
                '    };',
                '    if (@( 1, 2 ) | Where-Object {',
                '        $_ -gt 1;',
                '    }) {',
                '        return $Single;',
                '    }',
                '    return $Single;',
                '}',
                ''
            ) -join "`n";

            [System.IO.File]::WriteAllText($BadAstFile, $AstBody, $script:Utf8NoBom);
            [array]$Violations  = & $script:StyleScript -ModuleBasePath $TestDrive -Path @( $BadAstFile ) -PassThru;
            [string]$Joined     = ($Violations -join "`n");

            $Joined | Should -Match '\.PARAMETER table "\|" pipes';
            $Joined | Should -Match '"enum BadEnum"';
            $Joined | Should -Match '"class BadClass"';
            $Joined | Should -Match 'Function declaration must use "function Name\(\)"';
            $Joined | Should -Match '"if/elseif" condition must be on a single line';
            $Joined | Should -Match 'Single-entry hashtable';
            $Joined | Should -Match 'Assignment "=" alignment';
        }
    }
}

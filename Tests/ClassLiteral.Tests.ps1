$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\IcingaForWindows.psd1';
if (-not (Get-Module -Name 'IcingaForWindows')) {
    Import-Module -Name $ModulePath -Force -Global;
}

Describe 'Class literals in functions' {
    BeforeAll {
        # Every runspace shares the compiled kernel, so a class literal inside a
        # function resolves to the class type of the main runspace. In a thread on
        # Windows PowerShell 5.1 every method of such an object waits for the main
        # runspace, and type checks no longer match the thread's own objects.
        # Functions therefore use New-IcingaPlugin, Test-IcingaError or a runtime
        # lookup ('Name' -as [type]); only the class files themselves and enums may
        # use literals.
        $script:SourceRoot           = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\src'));
        [string[]]$script:ClassNames = @();

        foreach ($File in (Get-ChildItem -Path (Join-Path -Path $script:SourceRoot -ChildPath 'Classes') -Filter '*.ps1' -Recurse)) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null);

            foreach ($Definition in $Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.TypeDefinitionAst] -and $Node.IsClass }, $true)) {
                $script:ClassNames += $Definition.Name;
            }
        }
    }

    It 'reads the class names from the class files' {
        $script:ClassNames | Should -Contain 'IcingaPlugin';
        $script:ClassNames | Should -Contain 'IcingaError';
        $script:ClassNames | Should -Contain 'IcingaPerformanceCounter';
        $script:ClassNames | Should -Contain 'IcingaUnit';
    }

    It 'finds no class literal in a function outside src/Classes' {
        [string[]]$Violations = @();
        [string[]]$Skipped    = @(
            (Join-Path -Path $script:SourceRoot -ChildPath 'Classes'),
            (Join-Path -Path $script:SourceRoot -ChildPath 'analyze')
        );

        foreach ($File in (Get-ChildItem -Path $script:SourceRoot -Filter '*.ps1' -Recurse)) {
            [bool]$Skip = $false;

            foreach ($Folder in $Skipped) {
                if ($File.FullName.StartsWith($Folder + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $Skip = $true;
                }
            }

            if ($Skip) {
                continue;
            }

            $Ast   = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null);
            $Nodes = $Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.TypeExpressionAst] -or $Node -is [System.Management.Automation.Language.TypeConstraintAst] }, $true);

            foreach ($Node in $Nodes) {
                $TypeName = $Node.TypeName;

                while ($TypeName -is [System.Management.Automation.Language.ArrayTypeName]) {
                    $TypeName = $TypeName.ElementType;
                }

                if ($script:ClassNames -contains $TypeName.Name) {
                    $Violations += ('{0}:{1} [{2}]' -f $File.FullName.Substring($script:SourceRoot.Length + 1), $Node.Extent.StartLineNumber, $TypeName.Name);
                }
            }
        }

        $Violations | Should -BeNullOrEmpty -Because ("functions must not use class literals:`n" + ($Violations -join "`n"));
    }

    It 'finds no PowerShell class literal inside IcingaPerformanceCounter.ps1' {
        [string]$PerfClassFile = Join-Path -Path $script:SourceRoot -ChildPath 'Classes\Icinga\IcingaPerformanceCounter.ps1';
        [string[]]$Violations  = @();
        $Ast                   = [System.Management.Automation.Language.Parser]::ParseFile($PerfClassFile, [ref]$null, [ref]$null);
        $Nodes                 = $Ast.FindAll({ param ($Node) $Node -is [System.Management.Automation.Language.TypeExpressionAst] -or $Node -is [System.Management.Automation.Language.TypeConstraintAst] }, $true);

        foreach ($Node in $Nodes) {
            $TypeName = $Node.TypeName;

            while ($TypeName -is [System.Management.Automation.Language.ArrayTypeName]) {
                $TypeName = $TypeName.ElementType;
            }

            if ($script:ClassNames -contains $TypeName.Name) {
                $Violations += ('IcingaPerformanceCounter.ps1:{0} [{1}]' -f $Node.Extent.StartLineNumber, $TypeName.Name);
            }

            if ($TypeName -is [System.Management.Automation.Language.GenericTypeName]) {
                foreach ($GenArg in $TypeName.GenericArguments) {
                    if ($script:ClassNames -contains $GenArg.Name) {
                        $Violations += ('IcingaPerformanceCounter.ps1:{0} [{1}]' -f $Node.Extent.StartLineNumber, $GenArg.Name);
                    }
                }
            }
        }

        $Violations | Should -BeNullOrEmpty -Because ("IcingaPerformanceCounter.ps1 must use runtime lookups ('...' -as [type]) for PS 5.1 runspace isolation:`n" + ($Violations -join "`n"));
    }
}

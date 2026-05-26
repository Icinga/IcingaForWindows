@{
    ModuleVersion     = '27.0.0'
    GUID              = '7e6278de-6948-4180-b1fe-731648db1289'
    Author            = 'Lord Hepipud'
    CompanyName       = 'Icinga GmbH'
    Copyright         = '(c) 2026 Icinga GmbH | MIT'
    Description       = 'Icinga for Windows monitoring solution.'
    PowerShellVersion = '5.1'
    NestedModules     = @(
        'IcingaForWindows.psm1'
    )
    FunctionsToExport = '*'
    CmdletsToExport   = @()
    VariablesToExport = '*'
    AliasesToExport   = '*'
    PrivateData       = @{
        PSData   = @{
            Tags         = @( 'icinga', 'icinga2', 'windows', 'monitoring', 'opensource', 'Icinga for Windows' );
            LicenseUri   = 'https://github.com/Icinga/IcingaForWindows/blob/master/LICENSE'
            ProjectUri   = 'https://github.com/Icinga/IcingaForWindows'
            ReleaseNotes = 'https://github.com/Icinga/IcingaForWindows/releases'
        };
        Version  = 'v27.0.0';
        Name     = 'Icinga for Windows';
        Type     = 'core';
        Function = '';
        Endpoint = '';
    }
    HelpInfoURI       = 'https://github.com/Icinga/IcingaForWindows'
}

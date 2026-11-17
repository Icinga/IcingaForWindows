<#
.SYNOPSIS
Load RestApi space definitions from the data directory.

.DESCRIPTION
Reads all JSON files under `data/restapi/` and populates the global
private RestApi `Spaces` hashtable with parsed space configurations keyed
by filename (lowercase). Logs per-file parse results using `Write-FunctionReturnValue`.

.OUTPUTS
None -- populates `(Get-GlobalRuntimeVariable).Private.RestApi.Spaces`.

.EXAMPLE
PS> Read-RestApiSpacesConfig

.NOTES
Each space file must contain a valid JSON object describing routes,
handlers and optional access control for that API space.

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Read-RestApiSpacesConfig()
{
    $RestApiDirectory                      = Join-Path -Path (Get-ModuleRootDirectory) -ChildPath 'data\restapi\';
    $ApiSpaceFiles                         = Get-SecureChildItem -Path $RestApiDirectory -Filter '*.json' -Recurse -File;
    $GlobalVariable                        = Get-GlobalRuntimeVariable;

    $GlobalVariable.Private.RestApi.Spaces = @{ };

    foreach ($space in $ApiSpaceFiles) {
        $FileContent = Read-SecureFile -File $space.FullName;

        if ($null -eq $FileContent) {
            Write-FunctionReturnValue -ReturnValue 'RestApiSpaceFileEmpty' -Data @{ 'SpaceFile' = $space.FullName; } | Out-Null;
            continue;
        }

        try {
            $SpaceObject = $FileContent | ConvertFrom-Json -ErrorAction Stop;
        } catch {
            Write-FunctionReturnValue -ReturnValue 'RestApiSpaceFileParseError' -Data @{ 'SpaceFile' = $space.FullName; 'Exception' = $_.Exception } | Out-Null;
            continue;
        }

        $GlobalVariable.Private.RestApi.Spaces[$space.BaseName.ToLower()] = $SpaceObject;

        Write-FunctionReturnValue -ReturnValue 'RestApiSpaceFileParsedSuccessfully' -Data @{
            'SpaceFile' = $space.FullName;
            'SpaceName' = $space.BaseName.ToLower();
            'Config'    = $GlobalVariable.Private.RestApi.Spaces[$space.BaseName.ToLower()];
        } | Out-Null;
    }
}

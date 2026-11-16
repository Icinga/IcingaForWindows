<#
.SYNOPSIS
Resolve and validate an Icinga ExecuteCommand target against approved plugins and binaries

.DESCRIPTION
Resolve-IcingaProtocolCommand inspects macros.ifw_api_command from an incoming
Icinga 2 event::ExecuteCommand payload and resolves it deterministically without
consulting $env:PATH or guessing from params.command. If ifw_api_command is
missing or blank, Status is returned as CommandMissing (IWKB001003). Control
characters (0x00..0x1F), NTFS Alternate Data Stream colons, drive-relative paths,
directory separators and parent-directory traversal segments are validated and
normalized against Get-ModuleBinaryDirectory, returning BinaryPathRejected
(IWKB001003) whenever invalid or escaping that directory. Explicit
Invoke-IcingaCheck* names are resolved via Get-Command against loaded functions
and cmdlets. Bare names and relative filenames are probed strictly inside
Get-ModuleBinaryDirectory via System.IO.File.Exists (exact match when a known
executable extension is present, or probing .exe, .cmd, .bat, .com, .ps1 when
extensionless or carrying a non-executable dotted suffix such as check_app_v1.2).
If no binary exists in Get-ModuleBinaryDirectory and the name has neither path
separators nor an extension, shorthand PowerShell check names such as 'cpu' or
'IcingaCheckCPU' are expanded to 'Invoke-IcingaCheck*' and resolved as
PowerShell check commands.

.PARAMETER Macros
| Name   | Type          | Description                                                           | Default |
|--------|---------------|-----------------------------------------------------------------------|---------|
| Macros | System.Object | Deserialized macros dictionary or object from event::ExecuteCommand.  | $null   |

.PARAMETER CheckCommand
| Name         | Type          | Description                                                                   | Default |
|--------------|---------------|-------------------------------------------------------------------------------|---------|
| CheckCommand | System.String | Optional Icinga CheckCommand object name (params.command) for error context.  | ''      |

.OUTPUTS
System.Collections.Hashtable -- Resolution descriptor containing Status, Kind,
CommandName, BinaryPath, Parameters, Message, KnowledgeBaseId and ReturnCodeKey.

.EXAMPLE
PS> Resolve-IcingaProtocolCommand -Macros @{ 'ifw_api_command' = 'Invoke-IcingaCheckDirectory' }

Resolves the PowerShell check command and returns its parameter metadata.

.EXAMPLE
PS> Resolve-IcingaProtocolCommand -Macros @{ 'ifw_api_command' = 'cpu' }

Expands the shorthand 'cpu' to Invoke-IcingaCheckCPU when no cpu binary exists
in Get-ModuleBinaryDirectory.

.NOTES
Never searches $env:PATH for binaries or scripts. External executables must
reside inside Get-ModuleBinaryDirectory.
#>
function Resolve-IcingaProtocolCommand()
{
    param (
        [object]$Macros       = $null,
        [string]$CheckCommand = ''
    );

    [object]$RawCommandObj = $null;

    if ($Macros -is [System.Collections.IDictionary]) {
        foreach ($Key in $Macros.Keys) {
            if ([string]::Equals([string]$Key, 'ifw_api_command', [System.StringComparison]::OrdinalIgnoreCase)) {
                $RawCommandObj = $Macros[$Key];
                break;
            }
        }
    } elseif ($null -ne $Macros) {
        foreach ($Prop in $Macros.PSObject.Properties) {
            if ([string]::Equals([string]$Prop.Name, 'ifw_api_command', [System.StringComparison]::OrdinalIgnoreCase)) {
                $RawCommandObj = $Prop.Value;
                break;
            }
        }
    }

    [string]$RawCommand = '';
    if ($null -ne $RawCommandObj -and -not [string]::IsNullOrWhiteSpace([string]$RawCommandObj)) {
        $RawCommand = ([string]$RawCommandObj).Trim(' ');
    }

    # 1. Require macros.ifw_api_command explicitly (never guess from params.command)
    if ([string]::IsNullOrWhiteSpace($RawCommand)) {
        [string]$MissingMessage = '[UNKNOWN] Missing required macro "ifw_api_command" in ExecuteCommand payload. Ensure the CheckCommand imports "ifw-api" and defines "vars.ifw_api_command" (IWKB001003)';
        if (-not [string]::IsNullOrWhiteSpace($CheckCommand)) {
            $MissingMessage = ('[UNKNOWN] Missing required macro "ifw_api_command" for Icinga CheckCommand "{0}". Ensure the CheckCommand imports "ifw-api" and defines "vars.ifw_api_command" (IWKB001003)' -f $CheckCommand);
        }

        return @{
            'Status'          = 'CommandMissing';
            'Kind'            = '';
            'CommandName'     = '';
            'BinaryPath'      = '';
            'Parameters'      = $null;
            'Message'         = $MissingMessage;
            'KnowledgeBaseId' = 'IWKB001003';
            'ReturnCodeKey'   = 'IcingaProtocolCommandMissing';
        };
    }

    [string]$BinaryRootRaw    = Get-ModuleBinaryDirectory;
    [string]$BinaryRoot       = [System.IO.Path]::GetFullPath($BinaryRootRaw).TrimEnd('\', '/');
    [char]$DirSep             = [System.IO.Path]::DirectorySeparatorChar;
    [string]$BinaryRootPrefix = $BinaryRoot + $DirSep;

    # Reject ASCII control characters (0x00..0x1F), cross-platform invalid chars, NTFS ADS colons and drive-relative colons
    [bool]$HasPathIndicator   = ($RawCommand.IndexOf('\') -ge 0 -or $RawCommand.IndexOf('/') -ge 0 -or $RawCommand.IndexOf(':') -ge 0 -or $RawCommand.Contains('..'));
    [char[]]$InvalidChars     = [System.IO.Path]::GetInvalidPathChars();
    [bool]$HasControlChar     = ($RawCommand -match '[\x00-\x1F"<>|]');
    [bool]$HasInvalidColon    = ($RawCommand.IndexOf(':') -ge 0 -and ($RawCommand -notmatch '^[A-Za-z]:[\\/]' -or $RawCommand.IndexOf(':', 2) -ge 0));

    if ($HasControlChar -or $HasInvalidColon -or $RawCommand.IndexOfAny($InvalidChars) -ge 0) {
        return @{
            'Status'          = 'BinaryPathRejected';
            'Kind'            = '';
            'CommandName'     = '';
            'BinaryPath'      = '';
            'Parameters'      = $null;
            'Message'         = ('[UNKNOWN] Binary command path "{0}" contains invalid path characters or is outside "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
            'KnowledgeBaseId' = 'IWKB001003';
            'ReturnCodeKey'   = 'IcingaProtocolBinaryPathRejected';
        };
    }

    # Reject wildcards before Path.GetFullPath (which throws ArgumentException on '*'/'?' in .NET Framework 4.8 / PS 5.1)
    [bool]$HasWildcard = ($RawCommand.IndexOf('*') -ge 0 -or $RawCommand.IndexOf('?') -ge 0);

    if ($HasWildcard) {
        if ($HasPathIndicator) {
            return @{
                'Status'          = 'BinaryPathRejected';
                'Kind'            = '';
                'CommandName'     = '';
                'BinaryPath'      = '';
                'Parameters'      = $null;
                'Message'         = ('[UNKNOWN] Binary command path "{0}" contains invalid path characters or is outside "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
                'KnowledgeBaseId' = 'IWKB001003';
                'ReturnCodeKey'   = 'IcingaProtocolBinaryPathRejected';
            };
        }

        return @{
            'Status'          = 'CommandNotFound';
            'Kind'            = '';
            'CommandName'     = $RawCommand;
            'BinaryPath'      = '';
            'Parameters'      = $null;
            'Message'         = ('[UNKNOWN] Check command "{0}" could not be resolved as an "Invoke-IcingaCheck*" PowerShell plugin or as an executable inside "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
            'KnowledgeBaseId' = 'IWKB001003';
            'ReturnCodeKey'   = 'IcingaProtocolCommandNotFound';
        };
    }

    [bool]$IsForeignDrive = ($RawCommand -match '^[A-Za-z]:' -and $BinaryRoot -notmatch '^[A-Za-z]:');
    [bool]$IsUncPath      = ($RawCommand.StartsWith('\\') -or $RawCommand.StartsWith('//'));

    # 2. Enforce strict boundary inside Get-ModuleBinaryDirectory for any path/traversal input
    if ($IsForeignDrive -or ($IsUncPath -and -not $BinaryRoot.StartsWith('\\'))) {
        return @{
            'Status'          = 'BinaryPathRejected';
            'Kind'            = '';
            'CommandName'     = '';
            'BinaryPath'      = '';
            'Parameters'      = $null;
            'Message'         = ('[UNKNOWN] Binary command path "{0}" is outside the approved Icinga for Windows binaries directory "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
            'KnowledgeBaseId' = 'IWKB001003';
            'ReturnCodeKey'   = 'IcingaProtocolBinaryPathRejected';
        };
    }

    [string]$NormalizedInput   = $RawCommand.Replace('\', [string]$DirSep).Replace('/', [string]$DirSep);
    [string]$CandidateFullPath = '';

    try {
        if ([System.IO.Path]::IsPathRooted($NormalizedInput)) {
            $CandidateFullPath = [System.IO.Path]::GetFullPath($NormalizedInput);
        } else {
            $CandidateFullPath = [System.IO.Path]::GetFullPath((Join-Path -Path $BinaryRoot -ChildPath $NormalizedInput));
        }
    } catch {
        return @{
            'Status'          = 'BinaryPathRejected';
            'Kind'            = '';
            'CommandName'     = '';
            'BinaryPath'      = '';
            'Parameters'      = $null;
            'Message'         = ('[UNKNOWN] Binary command path "{0}" could not be normalized inside "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
            'KnowledgeBaseId' = 'IWKB001003';
            'ReturnCodeKey'   = 'IcingaProtocolBinaryPathRejected';
        };
    }

    [bool]$IsInsideBinaryRoot = ($CandidateFullPath.StartsWith($BinaryRootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and $CandidateFullPath.Length -gt $BinaryRootPrefix.Length);

    if (-not $IsInsideBinaryRoot) {
        return @{
            'Status'          = 'BinaryPathRejected';
            'Kind'            = '';
            'CommandName'     = '';
            'BinaryPath'      = '';
            'Parameters'      = $null;
            'Message'         = ('[UNKNOWN] Binary command path "{0}" is outside the approved Icinga for Windows binaries directory "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
            'KnowledgeBaseId' = 'IWKB001003';
            'ReturnCodeKey'   = 'IcingaProtocolBinaryPathRejected';
        };
    }

    # 3. Explicit PowerShell plugin check (Invoke-IcingaCheck*) without wildcards
    if (-not $HasPathIndicator -and $RawCommand -match '^Invoke-IcingaCheck[A-Za-z0-9_-]+$') {
        $CommandInfo = $null;
        try {
            $CommandInfo = Get-Command -Name $RawCommand -CommandType Function, Cmdlet -ErrorAction Stop | Select-Object -First 1;
        } catch {
            $CommandInfo = $null;
        }

        if ($null -ne $CommandInfo) {
            return @{
                'Status'          = 'Ok';
                'Kind'            = 'PowerShell';
                'CommandName'     = [string]$CommandInfo.Name;
                'BinaryPath'      = '';
                'Parameters'      = $CommandInfo.Parameters;
                'Message'         = '';
                'KnowledgeBaseId' = '';
                'ReturnCodeKey'   = '';
            };
        }
    }

    # 4. Strict full-path lookup inside Get-ModuleBinaryDirectory (never via $env:PATH)
    [string]$Extension        = [System.IO.Path]::GetExtension($CandidateFullPath);
    [string]$MatchedBinPath   = '';
    [array]$ExtensionsToProbe = @( '.exe', '.cmd', '.bat', '.com', '.ps1' );

    if (-not [string]::IsNullOrEmpty($Extension)) {
        if ([System.IO.File]::Exists($CandidateFullPath)) {
            $MatchedBinPath = $CandidateFullPath;
        } elseif ($ExtensionsToProbe -notcontains $Extension.ToLowerInvariant()) {
            foreach ($ProbeExt in $ExtensionsToProbe) {
                [string]$DottedProbed = $CandidateFullPath + $ProbeExt;
                if ($DottedProbed.StartsWith($BinaryRootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.File]::Exists($DottedProbed)) {
                    $MatchedBinPath = $DottedProbed;
                    break;
                }
            }
        }
    } else {
        foreach ($ProbeExt in $ExtensionsToProbe) {
            [string]$ProbedFile = $CandidateFullPath + $ProbeExt;
            if ($ProbedFile.StartsWith($BinaryRootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.File]::Exists($ProbedFile)) {
                $MatchedBinPath = $ProbedFile;
                break;
            }
        }

        if ([string]::IsNullOrEmpty($MatchedBinPath) -and [System.IO.File]::Exists($CandidateFullPath)) {
            $MatchedBinPath = $CandidateFullPath;
        }
    }

    if (-not [string]::IsNullOrEmpty($MatchedBinPath)) {
        return @{
            'Status'          = 'Ok';
            'Kind'            = 'Binary';
            'CommandName'     = [System.IO.Path]::GetFileName($MatchedBinPath);
            'BinaryPath'      = $MatchedBinPath;
            'Parameters'      = $null;
            'Message'         = '';
            'KnowledgeBaseId' = '';
            'ReturnCodeKey'   = '';
        };
    }

    # 5. Shorthand PowerShell check resolution (e.g. 'cpu' -> 'Invoke-IcingaCheckCPU')
    if (-not $HasPathIndicator -and [string]::IsNullOrEmpty($Extension) -and $RawCommand -match '^[A-Za-z0-9_-]+$') {
        [string]$ExpandedName = '';

        if ($RawCommand.StartsWith('Invoke-IcingaCheck', [System.StringComparison]::OrdinalIgnoreCase)) {
            $ExpandedName = $RawCommand;
        } elseif ($RawCommand.StartsWith('IcingaCheck', [System.StringComparison]::OrdinalIgnoreCase)) {
            $ExpandedName = 'Invoke-' + $RawCommand;
        } else {
            $ExpandedName = 'Invoke-IcingaCheck' + $RawCommand;
        }

        if ($ExpandedName -match '^Invoke-IcingaCheck[A-Za-z0-9_-]+$') {
            $ShortCommandInfo = $null;
            try {
                $ShortCommandInfo = Get-Command -Name $ExpandedName -CommandType Function, Cmdlet -ErrorAction Stop | Select-Object -First 1;
            } catch {
                $ShortCommandInfo = $null;
            }

            if ($null -ne $ShortCommandInfo) {
                return @{
                    'Status'          = 'Ok';
                    'Kind'            = 'PowerShell';
                    'CommandName'     = [string]$ShortCommandInfo.Name;
                    'BinaryPath'      = '';
                    'Parameters'      = $ShortCommandInfo.Parameters;
                    'Message'         = '';
                    'KnowledgeBaseId' = '';
                    'ReturnCodeKey'   = '';
                };
            }
        }
    }

    # 6. Command neither exists as an Invoke-IcingaCheck* function nor inside Binaries
    return @{
        'Status'          = 'CommandNotFound';
        'Kind'            = '';
        'CommandName'     = $RawCommand;
        'BinaryPath'      = '';
        'Parameters'      = $null;
        'Message'         = ('[UNKNOWN] Check command "{0}" could not be resolved as an "Invoke-IcingaCheck*" PowerShell plugin or as an executable inside "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
        'KnowledgeBaseId' = 'IWKB001003';
        'ReturnCodeKey'   = 'IcingaProtocolCommandNotFound';
    };
}

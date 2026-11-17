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
and cmdlets (preferring Icinga* module commands). Bare names and relative
filenames are probed strictly inside Get-ModuleBinaryDirectory via
System.IO.File.Exists (exact match when a known executable extension is present,
or probing .exe, .cmd, .bat, .com, .ps1 when extensionless or carrying a
non-executable dotted suffix such as check_app_v1.2). If no binary exists in
Get-ModuleBinaryDirectory and the name has neither path separators nor an
extension, shorthand PowerShell check names such as 'cpu' or 'IcingaCheckCPU'
are expanded to 'Invoke-IcingaCheck*' and resolved as PowerShell check commands.

.PARAMETER Macros
| Name   | Type          | Description                                                          | Default |
|--------|---------------|----------------------------------------------------------------------|---------|
| Macros | System.Object | Deserialized macros dictionary or object from event::ExecuteCommand. | $null   |

.PARAMETER CheckCommand
| Name         | Type          | Description                                                                  | Default |
|--------------|---------------|------------------------------------------------------------------------------|---------|
| CheckCommand | System.String | Optional Icinga CheckCommand object name (params.command) for error context. | ''      |

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

SPDX-FileCopyrightText: 2026 Icinga GmbH <https://icinga.com>
SPDX-License-Identifier: GPL-3.0-or-later
#>
function Resolve-IcingaProtocolCommand()
{
    param (
        [object]$Macros       = $null,
        [string]$CheckCommand = ''
    );

    [object]$RawCommandObj = Get-ModuleObjectValue -InputObject $Macros -Name 'ifw_api_command';
    [string]$RawCommand    = '';

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

    # 2. Reject ASCII control chars (0x00..0x1F), cross-platform invalid path chars, NTFS ADS / drive-relative colons,
    #    wildcards before Path.GetFullPath (.NET Framework 4.8 / PS 5.1 throws ArgumentException on '*'/'?'), and paths escaping Binaries
    [bool]$HasPathIndicator   = ($RawCommand.IndexOf('\') -ge 0 -or $RawCommand.IndexOf('/') -ge 0 -or $RawCommand.IndexOf(':') -ge 0 -or $RawCommand.Contains('..'));
    [char[]]$InvalidChars     = [System.IO.Path]::GetInvalidPathChars();
    [bool]$HasControlChar     = ($RawCommand -match '[\x00-\x1F"<>|]');
    [bool]$HasInvalidColon    = ($RawCommand.IndexOf(':') -ge 0 -and ($RawCommand -notmatch '^[A-Za-z]:[\\/]' -or $RawCommand.IndexOf(':', 2) -ge 0));
    [bool]$HasWildcard        = ($RawCommand.IndexOf('*') -ge 0 -or $RawCommand.IndexOf('?') -ge 0);
    [bool]$IsForeignDrive     = ($RawCommand -match '^[A-Za-z]:' -and $BinaryRoot -notmatch '^[A-Za-z]:');
    [bool]$IsUncPath          = ($RawCommand.StartsWith('\\') -or $RawCommand.StartsWith('//'));
    [string]$RejectedMessage  = '';
    [string]$CandidateBinPath = '';

    if ($HasControlChar -or $HasInvalidColon -or $RawCommand.IndexOfAny($InvalidChars) -ge 0 -or ($HasWildcard -and $HasPathIndicator)) {
        $RejectedMessage = ('[UNKNOWN] Binary command path "{0}" contains invalid path characters or is outside "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
    } elseif (-not $HasWildcard) {
        if ($IsForeignDrive -or ($IsUncPath -and -not $BinaryRoot.StartsWith('\\'))) {
            $RejectedMessage = ('[UNKNOWN] Binary command path "{0}" is outside the approved Icinga for Windows binaries directory "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
        } else {
            [string]$NormalizedInput = $RawCommand.Replace('\', [string]$DirSep).Replace('/', [string]$DirSep);

            try {
                if ([System.IO.Path]::IsPathRooted($NormalizedInput)) {
                    $CandidateBinPath = [System.IO.Path]::GetFullPath($NormalizedInput);
                } else {
                    $CandidateBinPath = [System.IO.Path]::GetFullPath((Join-Path -Path $BinaryRoot -ChildPath $NormalizedInput));
                }
            } catch {
                $RejectedMessage = ('[UNKNOWN] Binary command path "{0}" could not be normalized inside "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
            }

            if ([string]::IsNullOrEmpty($RejectedMessage) -and -not ($CandidateBinPath.StartsWith($BinaryRootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and $CandidateBinPath.Length -gt $BinaryRootPrefix.Length)) {
                $RejectedMessage = ('[UNKNOWN] Binary command path "{0}" is outside the approved Icinga for Windows binaries directory "{1}" (IWKB001003)' -f $RawCommand, $BinaryRoot);
            }
        }
    }

    if (-not [string]::IsNullOrEmpty($RejectedMessage)) {
        return @{
            'Status'          = 'BinaryPathRejected';
            'Kind'            = '';
            'CommandName'     = '';
            'BinaryPath'      = '';
            'Parameters'      = $null;
            'Message'         = $RejectedMessage;
            'KnowledgeBaseId' = 'IWKB001003';
            'ReturnCodeKey'   = 'IcingaProtocolBinaryPathRejected';
        };
    }

    if (-not $HasWildcard) {
        [string]$Extension = [System.IO.Path]::GetExtension($CandidateBinPath);

        # Two-pass resolution sharing a single Get-Command lookup:
        # - Pass 0: Explicit Invoke-IcingaCheck* names take priority as PowerShell check plugins.
        # - Pass 1: Strict full-path binary lookup inside Get-ModuleBinaryDirectory (never $env:PATH),
        #           followed by shorthand expansion (e.g. 'cpu' -> 'Invoke-IcingaCheckCPU') when no binary exists.
        for ($pass = 0; $pass -lt 2; $pass++) {
            [string]$CandidateCheck = '';

            if ($pass -eq 0) {
                # 3. Explicit PowerShell plugin check (Invoke-IcingaCheck*) without wildcards
                if (-not $HasPathIndicator -and $RawCommand -match '^Invoke-IcingaCheck[A-Za-z0-9_-]+$') {
                    $CandidateCheck = $RawCommand;
                }
            } else {
                # 4. Strict full-path lookup inside Get-ModuleBinaryDirectory (never via $env:PATH)
                [string]$MatchedBinPath   = '';
                [array]$ExtensionsToProbe = @( '.exe', '.cmd', '.bat', '.com', '.ps1' );

                if (-not [string]::IsNullOrEmpty($Extension)) {
                    if ([System.IO.File]::Exists($CandidateBinPath)) {
                        $MatchedBinPath = $CandidateBinPath;
                    } elseif ($ExtensionsToProbe -notcontains $Extension.ToLowerInvariant()) {
                        # Handle dotted base names such as check_app_v1.2 -> check_app_v1.2.exe
                        foreach ($ProbeExt in $ExtensionsToProbe) {
                            [string]$DottedProbed = $CandidateBinPath + $ProbeExt;
                            if ($DottedProbed.StartsWith($BinaryRootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.File]::Exists($DottedProbed)) {
                                $MatchedBinPath = $DottedProbed;
                                break;
                            }
                        }
                    }
                } else {
                    foreach ($ProbeExt in $ExtensionsToProbe) {
                        [string]$ProbedFile = $CandidateBinPath + $ProbeExt;
                        if ($ProbedFile.StartsWith($BinaryRootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and [System.IO.File]::Exists($ProbedFile)) {
                            $MatchedBinPath = $ProbedFile;
                            break;
                        }
                    }

                    if ([string]::IsNullOrEmpty($MatchedBinPath) -and [System.IO.File]::Exists($CandidateBinPath)) {
                        $MatchedBinPath = $CandidateBinPath;
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
                    if ($RawCommand.StartsWith('Invoke-IcingaCheck', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $CandidateCheck = $RawCommand;
                    } elseif ($RawCommand.StartsWith('IcingaCheck', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $CandidateCheck = 'Invoke-' + $RawCommand;
                    } else {
                        $CandidateCheck = 'Invoke-IcingaCheck' + $RawCommand;
                    }

                    if ($CandidateCheck -notmatch '^Invoke-IcingaCheck[A-Za-z0-9_-]+$') {
                        $CandidateCheck = '';
                    }
                }
            }

            # Resolve PowerShell check command, preferring loaded Icinga* module functions
            if (-not [string]::IsNullOrEmpty($CandidateCheck)) {
                [array]$MatchesFound = @();
                try {
                    $MatchesFound = @(Get-Command -Name $CandidateCheck -CommandType Function, Cmdlet -All -ErrorAction Stop);
                } catch {
                    $MatchesFound = @();
                }

                if ($MatchesFound.Count -gt 0) {
                    $SelectedCmd = $MatchesFound[0];
                    foreach ($CandidateMatch in $MatchesFound) {
                        if ([string]$CandidateMatch.ModuleName -like 'Icinga*' -or [string]$CandidateMatch.Source -like 'Icinga*') {
                            $SelectedCmd = $CandidateMatch;
                            break;
                        }
                    }

                    return @{
                        'Status'          = 'Ok';
                        'Kind'            = 'PowerShell';
                        'CommandName'     = [string]$SelectedCmd.Name;
                        'BinaryPath'      = '';
                        'Parameters'      = $SelectedCmd.Parameters;
                        'Message'         = '';
                        'KnowledgeBaseId' = '';
                        'ReturnCodeKey'   = '';
                    };
                }
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

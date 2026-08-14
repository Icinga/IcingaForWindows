<#
.SYNOPSIS
    Tests background daemons in Icinga for Windows for memory leaks caused by un-nulled local variables inside endless loops,
    and ensures that objects implementing IDisposable are properly disposed.

.DESCRIPTION
    Scans the provided source folder for PowerShell scripts and parses their Abstract Syntax Tree (AST).
    It identifies 'while' or 'do-while' loops that run indefinitely (typically checking 'Test-ThreadRunning').
    Inside these loops, it monitors all variable assignments. If a variable is assigned a value but is not
    explicitly set to $null anywhere within the same loop (or its finally block), it reports a memory leak.
    Native types like [bool], [switch], [int], etc., are exempt because they cannot be set to $null.

    Additionally, it tracks assignments of known IDisposable objects (like TcpClient, FileStream, etc.) and
    verifies if a corresponding `.Dispose()` method is called on the variable within the loop.
    If an IDisposable is passed to another function intentionally, you can suppress the check by adding
    `# [IcingaIgnoreDisposeCheck] $VariableName` as a comment inside the loop.

.PARAMETER SourceFolder
    The source folder containing the PowerShell module files to test. Default is the 'src' directory relative to the script.
#>
function Test-ModuleDaemonMemoryLeak()
{
    param (
        [string]$SourceFolder = (Join-Path $PSScriptRoot '..\src')
    )

    [bool]$Success = $true
    $Files = Get-ChildItem -Path $SourceFolder -Recurse -Include *.ps1,*.psm1

    # Native types that do not accept $null or are immediately GCed
    $ExemptTypes = @(
        'bool', 'System.Boolean', 'switch', 'System.Management.Automation.SwitchParameter',
        'int', 'System.Int32', 'long', 'System.Int64', 'double', 'System.Double',
        'float', 'System.Single', 'decimal', 'System.Decimal', 'datetime', 'System.DateTime',
        'char', 'System.Char', 'byte', 'System.Byte'
    )

    $DisposableTypes = @(
        'System.Net.Sockets.TcpClient',
        'System.Diagnostics.PerformanceCounter',
        'System.Threading.CancellationTokenSource',
        'System.IO.FileStream',
        'System.Security.Cryptography.X509Certificates.X509Certificate2',
        'Security.Cryptography.X509Certificates.X509Certificate2',
        'System.Security.Cryptography.X509Certificates.X509Store',
        'System.Net.Security.SslStream',
        'System.Net.WebSockets.ClientWebSocket',
        'System.Diagnostics.EventLog'
    )

    foreach ($File in $Files) {
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$Errors)

        # Find endless loops used by our daemons
        $DaemonLoops = $Ast.FindAll({
            ($args[0] -is [System.Management.Automation.Language.WhileStatementAst] -or
             $args[0] -is [System.Management.Automation.Language.DoWhileStatementAst] -or
             $args[0] -is [System.Management.Automation.Language.DoUntilStatementAst]) -and
            $args[0].Condition.Extent.Text -match 'Test-ThreadRunning'
        }, $true)

        foreach ($Loop in $DaemonLoops) {
            $AssignedVars = @{}
            $NulledVars = @{}

            $Assignments = $Loop.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)

            foreach ($Assign in $Assignments) {
                $Left = $Assign.Left
                $Right = $Assign.Right

                $VarName = $null
                $IsExemptType = $false

                if ($Left -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                    if ($Left.Child -is [System.Management.Automation.Language.VariableExpressionAst]) {
                        $VarName = $Left.Child.VariablePath.UserPath
                        $TypeName = $Left.Type.TypeName.Name
                        if ($ExemptTypes -contains $TypeName) {
                            $IsExemptType = $true
                        }
                    }
                } elseif ($Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $VarName = $Left.VariablePath.UserPath
                }

                if ($null -ne $VarName) {
                    if ($VarName -match '^(global|script|env|local|private):') { continue }
                    if ($VarName -eq '_' -or $VarName -eq 'this' -or $VarName -match '^args$') { continue }

                    # Null check tracking
                    if (-not $IsExemptType) {
                        $IsNull = $false
                        if ($Right -is [System.Management.Automation.Language.VariableExpressionAst] -and $Right.VariablePath.UserPath -eq 'null') {
                            $IsNull = $true
                        } elseif ($Right.Extent.Text -match '^\$null$') {
                            $IsNull = $true
                        }

                        if ($IsNull) {
                            $NulledVars[$VarName] = $true
                        } else {
                            $AssignedVars[$VarName] = $Assign.Extent.StartLineNumber
                        }
                    }
                }
            }

            foreach ($VarName in $AssignedVars.Keys) {
                if (-not $NulledVars.ContainsKey($VarName)) {
                    Write-Host "[ERROR] Memory Leak detected in $($File.Name) at line $($AssignedVars[$VarName]): Variable `$$VarName` is assigned but never set to `$null inside the Daemon loop!" -ForegroundColor Red
                    $Success = $false
                }
            }
        }

        # ---------------------------------------------------------
        # IDisposable Tracking (Entire File Scope)
        # ---------------------------------------------------------
        $DisposableVars = @{}
        $DisposedVars = @{}

        $AllAssignments = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)

        foreach ($Assign in $AllAssignments) {
            $Left = $Assign.Left
            $Right = $Assign.Right

            $VarName = $null
            if ($Left -is [System.Management.Automation.Language.ConvertExpressionAst]) {
                if ($Left.Child -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $VarName = $Left.Child.VariablePath.UserPath
                }
            } elseif ($Left -is [System.Management.Automation.Language.VariableExpressionAst]) {
                $VarName = $Left.VariablePath.UserPath
            }

            if ($null -ne $VarName) {
                if ($VarName -match '^(global|script|env|local|private):') { continue }
                if ($VarName -eq '_' -or $VarName -eq 'this' -or $VarName -match '^args$') { continue }

                $IsDisposableAssignment = $false

                $NewObjCmd = $Right.Find({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -eq 'New-Object' }, $true)
                if ($null -ne $NewObjCmd) {
                    foreach ($elem in $NewObjCmd.CommandElements) {
                        if ($elem -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                            if ($DisposableTypes -contains $elem.Value) {
                                $IsDisposableAssignment = $true
                                break
                            }
                        }
                    }
                }

                $InvokeMemberCmd = $Right.Find({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $args[0].Member.Extent.Text -match '^new$|^Create$' }, $true)
                if ($null -ne $InvokeMemberCmd) {
                    $TypeName = $InvokeMemberCmd.Expression.Extent.Text -replace '\[|\]',''
                    if ($DisposableTypes -contains $TypeName) {
                        $IsDisposableAssignment = $true
                    }
                }

                if ($IsDisposableAssignment) {
                    $DisposableVars[$VarName] = $Assign.Extent.StartLineNumber
                }
            }
        }

        # Find all Dispose() calls in the entire file
        $MemberInvocations = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)
        foreach ($Invoke in $MemberInvocations) {
            if ($Invoke.Member.Extent.Text -match '^Dispose$') {
                if ($Invoke.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
                    $DisposedVars[$Invoke.Expression.VariablePath.UserPath] = $true
                }
            }
        }

        $FileLines = $Ast.Extent.Text -split "`r?`n"

        foreach ($VarName in $DisposableVars.Keys) {
            if (-not $DisposedVars.ContainsKey($VarName)) {
                $StartLine = $DisposableVars[$VarName]
                $IsOptedOut = $false

                # Check line exactly before the assignment
                if ($StartLine -gt 1) {
                    $PrevLine = $FileLines[$StartLine - 2]
                    if ($PrevLine -match '#\s*\[IcingaIgnoreDisposeCheck\]') {
                        $IsOptedOut = $true
                    }
                }

                # Fallback: Check for Opt-Out comment with variable name anywhere in the file text
                if (-not $IsOptedOut) {
                    $OptOutString = "# [IcingaIgnoreDisposeCheck] `$$VarName"
                    if ($Ast.Extent.Text -match [regex]::Escape($OptOutString)) {
                        $IsOptedOut = $true
                    }
                }

                if ($IsOptedOut) {
                    Write-Host "[INFO] Ignored Dispose check for `$$VarName` in $($File.Name) due to Opt-Out comment." -ForegroundColor Yellow
                    continue
                }
                Write-Host "[ERROR] IDisposable Leak detected in $($File.Name) at line $($DisposableVars[$VarName]): Variable `$$VarName` is assigned a Disposable object but `.Dispose()` is never called in this file!" -ForegroundColor Red
                $Success = $false
            }
        }
    }
    return $Success
}

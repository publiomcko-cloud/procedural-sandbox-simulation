[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AssertionCount = 0
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:TempRoot = Join-Path $env:TEMP ('F2-G1-DiagnosticSynthetic-' + [guid]::NewGuid().ToString('N'))
$script:PowerShell51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Assert-F2Diagnostic {
    param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Name)
    $script:AssertionCount++
    if ($Condition) {
        Write-Output ('ASSERT=PASS;' + $Name)
    } else {
        Write-Output ('ASSERT=FAIL;' + $Name)
        $script:Failures.Add($Name)
    }
}

function Start-F2SyntheticChild {
    param([Parameter(Mandatory)][string]$Code,[Parameter(Mandatory)][string]$Name)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
    $stdout = Join-Path $script:TempRoot ($Name + '.stdout')
    $stderr = Join-Path $script:TempRoot ($Name + '.stderr')
    $process = Start-Process -FilePath $script:PowerShell51 -ArgumentList @(
        '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded
    ) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
    return [pscustomobject]@{
        Process = $process
        StdoutPath = $stdout
        StderrPath = $stderr
        Stdout = if (Test-Path -LiteralPath $stdout) { [IO.File]::ReadAllText($stdout) } else { '' }
        Stderr = if (Test-Path -LiteralPath $stderr) { [IO.File]::ReadAllText($stderr) } else { '' }
    }
}

function Get-F2SyntheticDiagnosticClass {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedNonce,[Parameter(Mandatory)][int]$ActualExitCode)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'DIAGNOSTIC_MISSING' }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return 'DIAGNOSTIC_REPARSE' }
    if ($item.Length -lt 1 -or $item.Length -gt 4096) { return 'DIAGNOSTIC_SIZE_INVALID' }
    try { $record = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop } catch { return 'DIAGNOSTIC_MALFORMED' }
    if ($record.Schema -cne 'f2-install-diagnostic-v1' -or $record.Nonce -cne $ExpectedNonce) { return 'DIAGNOSTIC_IDENTITY_INVALID' }
    if ($record.Stage -notin @('Bootstrap','Preflight','CreateStagingDirectories','CopyCreateNewPackageFiles','PrePublishAttestation','PublishCreateNewDirectories','PostInstallAttestation')) { return 'DIAGNOSTIC_STAGE_INVALID' }
    if ($record.ErrorCode -notmatch '^[A-Z][A-Z0-9_]{0,63}$') { return 'DIAGNOSTIC_CODE_INVALID' }
    if ($ActualExitCode -ne 0) { return 'CHILD_FAILURE' }
    if ($record.Outcome -eq 'INSTALL_COMPLETE') { return 'CHILD_CLAIM_ONLY' }
    return 'ZERO_EXIT_WITHOUT_SUCCESS_ATTESTATION'
}

try {
    [void][IO.Directory]::CreateDirectory($script:TempRoot)

    $startProcess = Get-Command Start-Process -ErrorAction Stop
    $verbSets = @($startProcess.ParameterSets | Where-Object { $_.Parameters.Name -contains 'Verb' })
    $verbSetHasRedirect = @($verbSets | Where-Object {
        $_.Parameters.Name -contains 'RedirectStandardOutput' -or $_.Parameters.Name -contains 'RedirectStandardError'
    }).Count -gt 0
    Assert-F2Diagnostic (-not $verbSetHasRedirect) 'PS51-StartProcess-Verb-set-excludes-stdout-stderr-redirection'

    $rootCauseFixture = @'
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($MyInvocation.InvocationName -ne '.') {
    if ($args.Count -ne 0) { exit 2 }
    [Console]::Out.WriteLine('UNEXPECTED-GUARD-PASS')
}
'@
    $guardRun = Start-F2SyntheticChild -Code $rootCauseFixture -Name 'strict-args-guard'
    Assert-F2Diagnostic ($guardRun.Process.ExitCode -eq 1) 'PS51-strict-args-guard-exits-1'
    Assert-F2Diagnostic ($guardRun.Stderr -match 'VariableIsUndefined') 'PS51-strict-args-guard-reports-VariableIsUndefined'
    Assert-F2Diagnostic (-not $guardRun.Stdout.Contains('UNEXPECTED-GUARD-PASS')) 'PS51-strict-args-guard-fails-before-main-body'

    $safeGuardFixture = @'
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$unbound = @($MyInvocation.UnboundArguments)
if ($unbound.Count -ne 0) { exit 2 }
[Console]::Out.WriteLine('SAFE-GUARD-PASS')
'@
    $safeGuardRun = Start-F2SyntheticChild -Code $safeGuardFixture -Name 'unbound-args-guard'
    Assert-F2Diagnostic ($safeGuardRun.Process.ExitCode -eq 0) 'PS51-unbound-arguments-guard-exits-0'
    Assert-F2Diagnostic ($safeGuardRun.Stdout.Contains('SAFE-GUARD-PASS')) 'PS51-unbound-arguments-guard-reaches-body'

    $redirectionFixture = @'
[Console]::Out.WriteLine('SYNTHETIC-STDOUT')
[Console]::Error.WriteLine('SYNTHETIC-STDERR')
exit 17
'@
    $redirectRun = Start-F2SyntheticChild -Code $redirectionFixture -Name 'ordinary-child-redirect'
    Assert-F2Diagnostic ($redirectRun.Process.ExitCode -eq 17) 'ordinary-child-real-exit-code-captured'
    Assert-F2Diagnostic ($redirectRun.Stdout.Trim() -eq 'SYNTHETIC-STDOUT') 'ordinary-child-stdout-captured'
    Assert-F2Diagnostic ($redirectRun.Stderr.Trim() -eq 'SYNTHETIC-STDERR') 'ordinary-child-stderr-captured'

    $mailboxDirectory = Join-Path $script:TempRoot ('mailbox-' + [guid]::NewGuid().ToString('N'))
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $directorySecurity = [Security.AccessControl.DirectorySecurity]::new()
    $directorySecurity.SetSecurityDescriptorSddlForm(('O:{0}D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;{0})' -f $currentSid))
    [void][IO.Directory]::CreateDirectory($mailboxDirectory, $directorySecurity)
    $mailboxAcl = Get-Acl -LiteralPath $mailboxDirectory
    Assert-F2Diagnostic ($mailboxAcl.AreAccessRulesProtected) 'synthetic-mailbox-dacl-is-protected'
    Assert-F2Diagnostic ($mailboxAcl.Owner -eq [Security.Principal.WindowsIdentity]::GetCurrent().Name) 'synthetic-mailbox-owner-is-requester'

    $nonce = [guid]::NewGuid().ToString('N')
    $diagnosticPath = Join-Path $mailboxDirectory 'result.json'
    $pathLiteral = ConvertTo-Json -InputObject $diagnosticPath -Compress
    $nonceLiteral = ConvertTo-Json -InputObject $nonce -Compress
    $fileDropFixture = @"
`$path = $pathLiteral
`$nonce = $nonceLiteral
`$record = [ordered]@{ Schema='f2-install-diagnostic-v1'; Nonce=`$nonce; Component='Installer'; Outcome='INSTALL_BLOCKED'; Stage='Preflight'; ErrorCode='SYNTHETIC_PREFLIGHT_FAILURE' }
`$bytes = [Text.UTF8Encoding]::new(`$false).GetBytes((`$record | ConvertTo-Json -Compress -Depth 3))
`$stream = [IO.File]::Open(`$path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try { `$stream.Write(`$bytes,0,`$bytes.Length); `$stream.Flush(`$true) } finally { `$stream.Dispose() }
exit 1
"@
    $fileDropRun = Start-F2SyntheticChild -Code $fileDropFixture -Name 'synthetic-status-file'
    Assert-F2Diagnostic ($fileDropRun.Process.ExitCode -eq 1) 'status-file-child-exit-code-is-observed-separately'
    Assert-F2Diagnostic ((Get-F2SyntheticDiagnosticClass -Path $diagnosticPath -ExpectedNonce $nonce -ActualExitCode $fileDropRun.Process.ExitCode) -eq 'CHILD_FAILURE') 'valid-sanitized-status-file-correlates-to-child-failure'
    $parsed = [IO.File]::ReadAllText($diagnosticPath) | ConvertFrom-Json
    Assert-F2Diagnostic ($parsed.Stage -eq 'Preflight' -and $parsed.ErrorCode -eq 'SYNTHETIC_PREFLIGHT_FAILURE') 'status-file-preserves-allowlisted-stage-and-error-code'

    Assert-F2Diagnostic ((Get-F2SyntheticDiagnosticClass -Path (Join-Path $mailboxDirectory 'missing.json') -ExpectedNonce $nonce -ActualExitCode 1) -eq 'DIAGNOSTIC_MISSING') 'missing-status-fails-closed'
    $badJson = Join-Path $mailboxDirectory 'malformed.json'
    [IO.File]::WriteAllText($badJson,'{not-json')
    Assert-F2Diagnostic ((Get-F2SyntheticDiagnosticClass -Path $badJson -ExpectedNonce $nonce -ActualExitCode 1) -eq 'DIAGNOSTIC_MALFORMED') 'malformed-status-fails-closed'
    $large = Join-Path $mailboxDirectory 'oversize.json'
    [IO.File]::WriteAllText($large,('x' * 4097))
    Assert-F2Diagnostic ((Get-F2SyntheticDiagnosticClass -Path $large -ExpectedNonce $nonce -ActualExitCode 1) -eq 'DIAGNOSTIC_SIZE_INVALID') 'oversized-status-fails-closed'
    $wrongNonce = Join-Path $mailboxDirectory 'wrong-nonce.json'
    $wrongRecord = [ordered]@{Schema='f2-install-diagnostic-v1';Nonce=([guid]::NewGuid().ToString('N'));Component='Installer';Outcome='INSTALL_BLOCKED';Stage='Preflight';ErrorCode='SYNTHETIC_FAILURE'}
    [IO.File]::WriteAllText($wrongNonce,($wrongRecord | ConvertTo-Json -Compress))
    Assert-F2Diagnostic ((Get-F2SyntheticDiagnosticClass -Path $wrongNonce -ExpectedNonce $nonce -ActualExitCode 1) -eq 'DIAGNOSTIC_IDENTITY_INVALID') 'wrong-nonce-status-fails-closed'
    $fakeSuccess = Join-Path $mailboxDirectory 'fake-success.json'
    $fakeRecord = [ordered]@{Schema='f2-install-diagnostic-v1';Nonce=$nonce;Component='Installer';Outcome='INSTALL_COMPLETE';Stage='PostInstallAttestation';ErrorCode='NONE'}
    [IO.File]::WriteAllText($fakeSuccess,($fakeRecord | ConvertTo-Json -Compress))
    Assert-F2Diagnostic ((Get-F2SyntheticDiagnosticClass -Path $fakeSuccess -ExpectedNonce $nonce -ActualExitCode 1) -eq 'CHILD_FAILURE') 'child-success-claim-cannot-override-nonzero-process-exit'
    Assert-F2Diagnostic ((Get-F2SyntheticDiagnosticClass -Path $fakeSuccess -ExpectedNonce $nonce -ActualExitCode 0) -eq 'CHILD_CLAIM_ONLY') 'child-success-claim-is-not-install-attestation'

    if ($script:Failures.Count -eq 0) {
        Write-Output ('RESULT=PASS;ASSERTIONS=' + $script:AssertionCount + ';FAILURES=0;POWERSHELL=' + $PSVersionTable.PSVersion)
    } else {
        Write-Output ('RESULT=FAIL;ASSERTIONS=' + $script:AssertionCount + ';FAILURES=' + $script:Failures.Count)
        foreach ($failure in $script:Failures) { Write-Output ('FAILURE=' + $failure) }
        exit 1
    }
} catch {
    Write-Output ('RESULT=ERROR;ASSERTIONS=' + $script:AssertionCount + ';ERROR=' + $_.Exception.GetType().FullName + ':' + $_.Exception.Message)
    exit 1
} finally {
    if (Test-Path -LiteralPath $script:TempRoot) {
        Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

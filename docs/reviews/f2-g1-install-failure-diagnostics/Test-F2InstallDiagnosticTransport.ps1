[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:TempRoot = Join-Path $env:TEMP ('F2-G1-DiagnosticSynthetic-' + [guid]::NewGuid().ToString('N'))
$script:PowerShell51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:BootstrapPath = Join-Path $PSScriptRoot '..\f2-g1-capture-id-contract\Invoke-F2VerifiedInstaller.ps1'
$script:InstallerPath = Join-Path $PSScriptRoot '..\f2-g1-capture-id-contract\Install-F2IcaclsProtectedPackage.ps1'
$script:LauncherPath = Join-Path $PSScriptRoot 'Start-F2VerifiedInstall.ps1'

function Assert-F2Diagnostic {
    param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Name)
    $script:AssertionCount++
    if ($Condition) { Write-Output ('ASSERT=PASS;' + $Name) } else { Write-Output ('ASSERT=FAIL;' + $Name); $script:Failures.Add($Name) }
}

function Start-F2SyntheticEncodedChild {
    param([Parameter(Mandatory)][string]$Encoded,[Parameter(Mandatory)][string]$Name,[string[]]$ExtraArguments=@())
    $stdout=Join-Path $script:TempRoot ($Name+'.stdout');$stderr=Join-Path $script:TempRoot ($Name+'.stderr')
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$Encoded)+$ExtraArguments
    $process=Start-Process -FilePath $script:PowerShell51 -ArgumentList $arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
    return [pscustomobject]@{Process=$process;StdoutPath=$stdout;StderrPath=$stderr;Stdout=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout)}else{''};Stderr=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr)}else{''}}
}

function Start-F2SyntheticFileChild {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Name,[string[]]$ExtraArguments=@())
    $stdout=Join-Path $script:TempRoot ($Name+'.stdout');$stderr=Join-Path $script:TempRoot ($Name+'.stderr')
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$Path)+$ExtraArguments
    $process=Start-Process -FilePath $script:PowerShell51 -ArgumentList $arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
    return [pscustomobject]@{Process=$process;Stdout=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout)}else{''};Stderr=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr)}else{''}}
}

function Start-F2SyntheticCommandChild {
    param([Parameter(Mandatory)][string]$Command,[Parameter(Mandatory)][string]$Name)
    $stdout=Join-Path $script:TempRoot ($Name+'.stdout');$stderr=Join-Path $script:TempRoot ($Name+'.stderr')
    $quoted='"'+$Command.Replace('"','`"')+'"'
    $process=Start-Process -FilePath $script:PowerShell51 -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',$quoted) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -Wait -PassThru
    return [pscustomobject]@{Process=$process;Stdout=if(Test-Path -LiteralPath $stdout){[IO.File]::ReadAllText($stdout)}else{''};Stderr=if(Test-Path -LiteralPath $stderr){[IO.File]::ReadAllText($stderr)}else{''}}
}

function New-F2SyntheticMailbox {
    param([Parameter(Mandatory)][string]$OwnerSid)
    return New-F2InstallDiagnosticMailbox -OwnerSid $OwnerSid
}

function Write-F2SyntheticInstaller {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][bool]$Success,[Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$ErrorCode,[switch]$Throw)
    if($Throw){$source="throw 'PRIVATE_SYNTHETIC_DETAIL'"}else{$successLiteral=if($Success){'$true'}else{'$false'};$source="function Invoke-F2InstallMain { return [pscustomobject]@{ Success=$successLiteral; Stage='$Stage'; ErrorCode='$ErrorCode' } }"}
    [IO.File]::WriteAllText($Path,$source,[Text.UTF8Encoding]::new($false))
    return Get-F2BootstrapHashBytes -Bytes ([IO.File]::ReadAllBytes($Path))
}

try {
    [void][IO.Directory]::CreateDirectory($script:TempRoot)
    . $script:BootstrapPath
    . $script:LauncherPath

    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$sid=$identity.User.Value
    $bootstrapText=[IO.File]::ReadAllText((Resolve-Path $script:BootstrapPath).Path)
    $bootstrapBytes=[IO.File]::ReadAllBytes((Resolve-Path $script:BootstrapPath).Path)

    # Exercise the real encoded-command source entrypoint with no script args and
    # a ScriptBlock invocation with an unexpected unbound argument.
    $bootstrapLiteral=(Resolve-Path $script:BootstrapPath).Path.Replace("'","''")
    $zeroHarness="`$block=[ScriptBlock]::Create([IO.File]::ReadAllText('$bootstrapLiteral')); & `$block"
    $zeroEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($zeroHarness))
    $zeroRun=Start-F2SyntheticEncodedChild -Encoded $zeroEncoded -Name 'bootstrap-encoded-zero'
    Assert-F2Diagnostic ($zeroRun.Process.ExitCode -eq 1 -and $zeroRun.Stderr -match 'BOOTSTRAP_REVIEWED_LAUNCHER_REQUIRED' -and $zeroRun.Stderr -notmatch 'VariableIsUndefined') 'real-bootstrap-encoded-zero-arguments-is-controlled-and-caught'
    $extraHarness="`$block=[ScriptBlock]::Create([IO.File]::ReadAllText('$bootstrapLiteral')); try { & `$block unexpected } catch { [Console]::Error.WriteLine(`$_.Exception.Message); exit 1 }; exit 0"
    $extraRun=Start-F2SyntheticEncodedChild -Encoded ([Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($extraHarness))) -Name 'bootstrap-encoded-extra'
    Assert-F2Diagnostic ($extraRun.Process.ExitCode -eq 1 -and $extraRun.Stderr -match 'BOOTSTRAP_ARGUMENTS_NOT_ACCEPTED') 'real-bootstrap-encoded-extra-argument-is-caught'
    $extraFileRun=Start-F2SyntheticFileChild -Path (Resolve-Path $script:BootstrapPath).Path -Name 'bootstrap-file-extra' -ExtraArguments @('unexpected')
    Assert-F2Diagnostic ($extraFileRun.Process.ExitCode -eq 1 -and $extraFileRun.Stderr -match 'BOOTSTRAP_ARGUMENTS_NOT_ACCEPTED') 'real-bootstrap-file-extra-argument-is-caught'

    $installer=Join-Path $script:TempRoot 'synthetic-installer.ps1'
    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $failHash=Write-F2SyntheticInstaller -Path $installer -Success $false -Stage 'Preflight' -ErrorCode 'BASELINE_PIN_MISMATCH'
    $result=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $failHash -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $mailbox.Nonce
    Assert-F2Diagnostic ($result.ChildExitCode -eq 1 -and $result.DiagnosticPublished -and $result.Stage -eq 'Preflight' -and $result.ErrorCode -eq 'BASELINE_PIN_MISMATCH') 'installer-preflight-status-is-exported-through-verified-scriptblock-scope'
    $status=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $result.ChildExitCode
    if($status.Status-ne 'CHILD_FAILURE'){
        $directoryCheck='PASS';try{Test-F2InstallMailboxDirectory -Path $mailbox.Directory -OwnerSid $sid|Out-Null}catch{$directoryCheck=[string]$_.Exception.Message}
        $filePath=Join-Path $mailbox.Directory 'result.json';$fileCheck='MISSING';$aceSummary=@()
        if(Test-Path -LiteralPath $filePath){$fileCheck='PRESENT';$fileAcl=Get-Acl -LiteralPath $filePath;$fileRaw=[Security.AccessControl.RawSecurityDescriptor]::new($fileAcl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner-bor[Security.AccessControl.AccessControlSections]::Access));$fileCheck='OwnerMatches='+($fileRaw.Owner.Value-ceq$sid)+';Protected='+([bool]($fileRaw.ControlFlags-band[Security.AccessControl.ControlFlags]::DiscretionaryAclProtected))+';AceCount='+@($fileRaw.DiscretionaryAcl).Count;foreach($ace in $fileRaw.DiscretionaryAcl){$category=if($ace.SecurityIdentifier.Value-eq'S-1-5-18'){'SYSTEM'}elseif($ace.SecurityIdentifier.Value-eq$sid){'REQUESTER'}else{'OTHER'};$aceSummary+=('{0}:Qualifier={1};Mask=0x{2:X8};Flags=0x{3:X2}'-f$category,$ace.AceQualifier,[uint32]$ace.AccessMask,[int]$ace.AceFlags)}}
        Write-Output ('SYNTHETIC_DIAGNOSTIC_TRACE;Status='+$status.Status+';Error='+$status.ErrorCode+';DirectoryCheck='+$directoryCheck+';File='+$fileCheck+';Aces='+($aceSummary-join'|'))
    }
    Assert-F2Diagnostic ($status.Status -eq 'CHILD_FAILURE' -and $status.Record.Component -eq 'Installer' -and $status.Record.Stage -eq 'Preflight') 'requester-validates-installer-failure-record-and-child-exit-separately'
    Assert-F2Diagnostic ($status.Sha256 -match '^[0-9a-f]{64}$') 'diagnostic-record-hash-is-calculated-after-bounded-read'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $missingStageSource="function Invoke-F2InstallMain { return [pscustomobject]@{ Success=`$false; ErrorCode='BASELINE_PIN_MISMATCH' } }"
    [IO.File]::WriteAllText($installer,$missingStageSource,[Text.UTF8Encoding]::new($false))
    $missingStageHash=Get-F2BootstrapHashBytes -Bytes ([IO.File]::ReadAllBytes($installer))
    $missingStageResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $missingStageHash -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $mailbox.Nonce
    $missingStageStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $missingStageResult.ChildExitCode
    Assert-F2Diagnostic ($missingStageResult.ChildExitCode -eq 1 -and $missingStageStatus.Status -eq 'CHILD_FAILURE' -and $missingStageStatus.Record.Stage -eq 'Preflight' -and $missingStageStatus.Record.ErrorCode -eq 'BASELINE_PIN_MISMATCH') 'missing-installer-stage-field-uses-safe-preflight-fallback-and-preserves-allowlisted-error'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $stageHash=Write-F2SyntheticInstaller -Path $installer -Success $false -Stage 'CopyCreateNewPackageFiles' -ErrorCode 'INSTALL_SOURCE_SHORT_READ'
    $stageResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $stageHash -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $mailbox.Nonce
    $stageStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $stageResult.ChildExitCode
    Assert-F2Diagnostic ($stageStatus.Status -eq 'CHILD_FAILURE' -and $stageStatus.Record.Stage -eq 'CopyCreateNewPackageFiles') 'staged-package-failure-stage-is-preserved'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    # The installer path is read once, then the verified in-memory ScriptBlock
    # is executed even if the backing file changes during that execution.
    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $replacementText="throw 'REPLACEMENT_MUST_NOT_EXECUTE'"
    $escapedPath=$installer.Replace("'","''");$escapedReplacement=$replacementText.Replace("'","''")
    $selfModifyingSource="[IO.File]::WriteAllText('$escapedPath','$escapedReplacement'); function Invoke-F2InstallMain { return [pscustomobject]@{ Success=`$true; Stage='PostInstallAttestation'; ErrorCode='NONE' } }"
    [IO.File]::WriteAllText($installer,$selfModifyingSource,[Text.UTF8Encoding]::new($false))
    $selfModifyingHash=Get-F2BootstrapHashBytes -Bytes ([IO.File]::ReadAllBytes($installer))
    $selfModifyingResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $selfModifyingHash -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $mailbox.Nonce
    $selfModifyingStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $selfModifyingResult.ChildExitCode
    Assert-F2Diagnostic ($selfModifyingResult.ChildExitCode -eq 0 -and $selfModifyingStatus.Status -eq 'CHILD_CLAIM_ONLY' -and [IO.File]::ReadAllText($installer) -ceq $replacementText) 'installer-is-read-once-hash-checked-and-executes-identical-in-memory-bytes-after-path-replacement'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $successHash=Write-F2SyntheticInstaller -Path $installer -Success $true -Stage 'PostInstallAttestation' -ErrorCode 'NONE'
    $successResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $successHash -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $mailbox.Nonce
    $successStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $successResult.ChildExitCode
    Assert-F2Diagnostic ($successStatus.Status -eq 'CHILD_CLAIM_ONLY' -and $successStatus.Record.Outcome -eq 'INSTALL_COMPLETE') 'zero-exit-child-success-remains-explicitly-nonauthoritative'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $badHashRejected=$false
    try { $tamperResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 ('0'*64) -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $mailbox.Nonce } catch { $badHashRejected=$true }
    Assert-F2Diagnostic ($badHashRejected -or ($tamperResult.ChildExitCode -eq 1 -and $tamperResult.ErrorCode -eq 'BOOTSTRAP_INSTALLER_HASH_MISMATCH' -and $tamperResult.DiagnosticPublished)) 'modified-or-wrong-installer-hash-fails-before-execution'
    $badHashStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode 1
    Assert-F2Diagnostic ($badHashStatus.Status -eq 'CHILD_FAILURE' -and $badHashStatus.Record.Stage -eq 'BootstrapSourceVerification') 'bootstrap-hash-failure-is-published-with-stage-and-code'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $throwHash=Write-F2SyntheticInstaller -Path $installer -Success $false -Stage 'Preflight' -ErrorCode 'INSTALL_OPERATION_FAILED' -Throw
    $throwResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $throwHash -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $mailbox.Nonce
    $throwStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode 1
    Assert-F2Diagnostic ($throwResult.ChildExitCode -eq 1 -and $throwStatus.Status -eq 'CHILD_FAILURE' -and $throwStatus.Record.Component -eq 'Bootstrap' -and $throwStatus.Record.ErrorCode -eq 'BOOTSTRAP_EXECUTION_FAILED' -and [IO.File]::ReadAllText((Join-Path $mailbox.Directory 'result.json')) -notmatch 'PRIVATE_SYNTHETIC_DETAIL') 'bootstrap-catches-scriptblock-exception-and-publishes-sanitized-code'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    $successHash=Write-F2SyntheticInstaller -Path $installer -Success $true -Stage 'PostInstallAttestation' -ErrorCode 'NONE'
    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $wrongNonce='0'*32
    $nonceResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $successHash -DiagnosticDirectory $mailbox.Directory -CorrelationNonce $wrongNonce
    $nonceStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $nonceResult.ChildExitCode
    Assert-F2Diagnostic ($nonceStatus.Status -eq 'DIAGNOSTIC_CONTENT_INVALID' -and $nonceResult.DiagnosticPublished) 'nonce-mismatched-record-is-rejected-by-requester'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    # Wrong owner/DACL is refused before reading/executing synthetic installer bytes.
    $badMailboxPath=Join-Path $script:TempRoot ('F2-G1-Install-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($badMailboxPath)
    $badMailboxRejected=$false
    try { Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $successHash -DiagnosticDirectory $badMailboxPath -CorrelationNonce ([guid]::NewGuid().ToString('N')) | Out-Null } catch { $badMailboxRejected=$true }
    $badMailboxResult=Invoke-F2VerifiedInstallerCore -InstallerPath $installer -ExpectedSha256 $successHash -DiagnosticDirectory $badMailboxPath -CorrelationNonce ([guid]::NewGuid().ToString('N'))
    Assert-F2Diagnostic ($badMailboxRejected -or ($badMailboxResult.ChildExitCode -eq 1 -and -not $badMailboxResult.DiagnosticPublished)) 'inaccessible-or-unprotected-mailbox-fails-closed-before-installer'
    Remove-Item -LiteralPath $badMailboxPath -Recurse -Force

    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $nonce=$mailbox.Nonce;$recordPath=Join-Path $mailbox.Directory 'result.json'
    Assert-F2Diagnostic ((Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 1).Status -eq 'DIAGNOSTIC_MISSING') 'missing-record-fails-closed'
    $missingNextStep=Get-F2InstallNextStep -LaunchDisposition 'CHILD_EXITED' -DiagnosticStatus 'DIAGNOSTIC_MISSING' -Outcome 'BLOCKED_CHILD_FAILURE'
    Assert-F2Diagnostic ($missingNextStep -match 'original requester account' -and $missingNextStep -match 'no success may be inferred') 'missing-cross-account-mailbox-gives-actionable-nonauthoritative-guidance'
    [IO.File]::WriteAllText($recordPath,'{bad-json')
    Assert-F2Diagnostic ((Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 1).Status -eq 'DIAGNOSTIC_MALFORMED_OR_SECURITY_INVALID') 'malformed-record-fails-closed'
    Remove-Item -LiteralPath $recordPath -Force
    [IO.File]::WriteAllText($recordPath,('x'*4097))
    Assert-F2Diagnostic ((Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 1).Status -eq 'DIAGNOSTIC_SIZE_INVALID') 'oversized-record-fails-closed'
    Remove-Item -LiteralPath $recordPath -Force
    $wrongNonce=[ordered]@{Schema='f2-install-diagnostic-v1';Nonce=([guid]::NewGuid().ToString('N'));Component='Installer';Outcome='INSTALL_BLOCKED';Stage='Preflight';ErrorCode='SYNTHETIC_FAILURE'}
    [IO.File]::WriteAllText($recordPath,($wrongNonce|ConvertTo-Json -Compress))
    Assert-F2Diagnostic ((Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 1).Status -eq 'DIAGNOSTIC_CONTENT_INVALID') 'wrong-nonce-record-fails-closed'
    Remove-Item -LiteralPath $recordPath -Force
    $extraProperty=[ordered]@{Schema='f2-install-diagnostic-v1';Nonce=$nonce;Component='Installer';Outcome='INSTALL_BLOCKED';Stage='Preflight';ErrorCode='SYNTHETIC_FAILURE';PrivateData='must-not-be-accepted'}
    [IO.File]::WriteAllText($recordPath,($extraProperty|ConvertTo-Json -Compress))
    Assert-F2Diagnostic ((Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 1).Status -eq 'DIAGNOSTIC_CONTENT_INVALID') 'unexpected-diagnostic-field-fails-closed'
    Remove-Item -LiteralPath $recordPath -Force
    $falseSuccess=[ordered]@{Schema='f2-install-diagnostic-v1';Nonce=$nonce;Component='Installer';Outcome='INSTALL_COMPLETE';Stage='PostInstallAttestation';ErrorCode='NONE'}
    [IO.File]::WriteAllText($recordPath,($falseSuccess|ConvertTo-Json -Compress))
    Assert-F2Diagnostic ((Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 1).Status -eq 'CHILD_STATUS_CONFLICT') 'false-success-claim-conflicts-with-nonzero-real-child-exit'
    Remove-Item -LiteralPath $recordPath -Force
    [IO.File]::WriteAllText($recordPath,($falseSuccess|ConvertTo-Json -Compress))
    $successOnly=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 0
    Assert-F2Diagnostic ($successOnly.Status -eq 'CHILD_CLAIM_ONLY' -and $successOnly.Record.Outcome -eq 'INSTALL_COMPLETE') 'success-diagnostic-cannot-replace-independent-installation-attestation'
    [IO.File]::WriteAllText((Join-Path $mailbox.Directory '.result-leftover.tmp'),'incomplete publication')
    Assert-F2Diagnostic ((Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $nonce -OwnerSid $sid -ChildExitCode 0).Status -eq 'DIAGNOSTIC_DIRECTORY_CONTENTS_INVALID') 'leftover-atomic-publication-file-rejects-the-entire-diagnostic'
    Remove-Item -LiteralPath (Join-Path $mailbox.Directory '.result-leftover.tmp') -Force
    $beforeCollision=[IO.File]::ReadAllBytes($recordPath)
    $duplicateRejected=$false
    try { Publish-F2InstallDiagnostic -Directory $mailbox.Directory -Nonce $nonce -Component Installer -Outcome INSTALL_COMPLETE -Stage PostInstallAttestation -ErrorCode NONE } catch { $duplicateRejected=$_.Exception.Message -eq 'BOOTSTRAP_DIAGNOSTIC_PUBLICATION_FAILED' }
    $afterCollision=[IO.File]::ReadAllBytes($recordPath)
    Assert-F2Diagnostic ($duplicateRejected -and [Convert]::ToBase64String($beforeCollision) -ceq [Convert]::ToBase64String($afterCollision)) 'create-new-diagnostic-collision-never-overwrites-the-first-record'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    # Run the real elevated command builder and bootstrap in a normal synthetic
    # Windows PowerShell child. The fixture installer performs no host writes.
    $syntheticBootstrap=$bootstrapText.Replace("C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1",$installer)
    $syntheticHash=Write-F2SyntheticInstaller -Path $installer -Success $false -Stage 'Preflight' -ErrorCode 'INSTALL_PARENT_DACL_UNSAFE'
    $successHash=$syntheticHash
    $syntheticBootstrap=$syntheticBootstrap.Replace('cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118',$syntheticHash)
    $mailbox=New-F2SyntheticMailbox -OwnerSid $sid
    $syntheticBootstrapBytes=[Text.Encoding]::UTF8.GetBytes($syntheticBootstrap)
    $script:F2InstallBootstrapSha256=Get-F2InstallLauncherHash -Bytes $syntheticBootstrapBytes
    $encoded=New-F2InstallElevatedCommand -BootstrapBytes $syntheticBootstrapBytes -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce
    $integrationRun=Start-F2SyntheticCommandChild -Command $encoded -Name 'actual-child-command-integration'
    $integrationStatus=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $integrationRun.Process.ExitCode
    Assert-F2Diagnostic ($integrationRun.Process.ExitCode -eq 1 -and $integrationStatus.Status -eq 'CHILD_FAILURE' -and $integrationStatus.Record.ErrorCode -eq 'INSTALL_PARENT_DACL_UNSAFE') 'actual-encoded-coordinator-to-bootstrap-to-installer-boundary-reports-child-exit-and-stage'
    Remove-Item -LiteralPath $mailbox.Directory -Recurse -Force

    # Validate that the real production launcher consumes the exact pins and
    # creates only a requester/SYSTEM protected mailbox before its injectable
    # process boundary. The provider runs the encoded child unelevated.
    $launcherBootstrapHash=Get-F2InstallLauncherHash -Bytes $syntheticBootstrapBytes
    $installerBytes=[IO.File]::ReadAllBytes($installer)
    $installerHash=Get-F2InstallLauncherHash -Bytes $installerBytes
    $syntheticBootstrapPath=Join-Path $script:TempRoot 'synthetic-bootstrap.ps1'
    $syntheticLauncherBootstrap=$bootstrapText.Replace("C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1",$installer).Replace('cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118',$successHash)
    [IO.File]::WriteAllText($syntheticBootstrapPath,$syntheticLauncherBootstrap,[Text.UTF8Encoding]::new($false))
    $script:F2InstallBootstrapPath=$syntheticBootstrapPath
    $script:F2InstallBootstrapSha256=Get-F2InstallLauncherHash -Bytes ([IO.File]::ReadAllBytes($syntheticBootstrapPath))
    $script:F2InstallInstallerPath=$installer
    $script:F2InstallInstallerSha256=$successHash
    $script:F2InstallStartProcessProvider={param($exe,$command) Start-F2SyntheticCommandChild -Command $command -Name 'launcher-injected-child'|ForEach-Object{$_.Process}}.GetNewClosure()
    $launchResult=Invoke-F2InstallLaunch
    Assert-F2Diagnostic ($launchResult.ChildExitCode -eq 1 -and $launchResult.LaunchDisposition -eq 'CHILD_EXITED' -and $launchResult.DiagnosticStatus -eq 'CHILD_FAILURE' -and $launchResult.Outcome -eq 'BLOCKED_CHILD_FAILURE') 'actual-launcher-parent-boundary-retains-real-child-exit-and-diagnostic-without-uac-provider'
    Assert-F2Diagnostic ($launchResult.DiagnosticIsNonAuthoritative -and $launchResult.IndependentInstallationAttestationRequired) 'launch-result-explicitly-requires-independent-installation-attestation'
    if($null-ne$launchResult.MailboxPath-and(Test-Path -LiteralPath $launchResult.MailboxPath)){Remove-Item -LiteralPath $launchResult.MailboxPath -Recurse -Force}

    $global:F2ProviderCalls=0
    $pinnedSyntheticBootstrapHash=Get-F2InstallLauncherHash -Bytes ([IO.File]::ReadAllBytes($syntheticBootstrapPath))
    $tamperedBootstrapPath=Join-Path $script:TempRoot 'tampered-bootstrap.ps1'
    [IO.File]::WriteAllBytes($tamperedBootstrapPath,[IO.File]::ReadAllBytes($syntheticBootstrapPath))
    [IO.File]::AppendAllText($tamperedBootstrapPath,'#tampered')
    $script:F2InstallBootstrapPath=$tamperedBootstrapPath
    $script:F2InstallBootstrapSha256=$pinnedSyntheticBootstrapHash
    $script:F2InstallStartProcessProvider={param($exe,$command)$global:F2ProviderCalls++;throw 'SYNTHETIC_UAC_CANCEL'}.GetNewClosure()
    $tamperedLaunch=Invoke-F2InstallLaunch
    Assert-F2Diagnostic ($tamperedLaunch.LaunchDisposition -eq 'NOT_LAUNCHED' -and $tamperedLaunch.DiagnosticErrorCode -eq 'BOOTSTRAP_HASH_MISMATCH' -and $tamperedLaunch.ChildExitCode -eq $null -and $global:F2ProviderCalls -eq 0) 'bootstrap-source-tamper-fails-before-uac-or-mailbox-creation'

    $script:F2InstallBootstrapPath=$syntheticBootstrapPath
    $script:F2InstallBootstrapSha256=$pinnedSyntheticBootstrapHash
    $tamperedInstallerPath=Join-Path $script:TempRoot 'tampered-installer.ps1'
    [IO.File]::WriteAllBytes($tamperedInstallerPath,[IO.File]::ReadAllBytes($installer))
    [IO.File]::AppendAllText($tamperedInstallerPath,'#tampered')
    $script:F2InstallInstallerPath=$tamperedInstallerPath
    $installerTamperedLaunch=Invoke-F2InstallLaunch
    Assert-F2Diagnostic ($installerTamperedLaunch.LaunchDisposition -eq 'NOT_LAUNCHED' -and $installerTamperedLaunch.DiagnosticErrorCode -eq 'INSTALLER_HASH_MISMATCH' -and $installerTamperedLaunch.ChildExitCode -eq $null -and $global:F2ProviderCalls -eq 0) 'installer-source-tamper-fails-before-uac-or-mailbox-creation'
    $script:F2InstallInstallerPath=$installer
    $script:F2InstallStartProcessProvider={param($exe,$command)$global:F2ProviderCalls++;throw 'SYNTHETIC_UAC_CANCEL'}.GetNewClosure()
    $cancelled=Invoke-F2InstallLaunch
    Assert-F2Diagnostic ($cancelled.LaunchDisposition -eq 'UAC_CANCELLED_OR_LAUNCH_ERROR' -and $cancelled.ChildPid -eq $null -and $cancelled.ChildExitCode -eq $null -and $cancelled.DiagnosticStatus -eq 'NOT_AVAILABLE' -and $global:F2ProviderCalls -eq 1) 'uac-cancel-or-shell-launch-failure-has-no-fabricated-child-exit-and-no-retry'
    if($null-ne$cancelled.MailboxPath-and(Test-Path -LiteralPath $cancelled.MailboxPath)){Assert-F2Diagnostic (@(Get-ChildItem -LiteralPath $cancelled.MailboxPath -Force).Count-eq 0) 'cancelled-attempt-retains-empty-protected-mailbox-for-evidence';Remove-Item -LiteralPath $cancelled.MailboxPath -Recurse -Force}

    $launcherLiteral=(Resolve-Path $script:LauncherPath).Path.Replace("'","''")
    $extraLauncher=Start-F2SyntheticFileChild -Path (Resolve-Path $script:LauncherPath).Path -Name 'launcher-file-extra' -ExtraArguments @('unexpected')
    Assert-F2Diagnostic ($extraLauncher.Process.ExitCode -eq 1 -and $extraLauncher.Stderr -match 'LAUNCHER_ARGUMENTS_NOT_ACCEPTED') 'launcher-rejects-extra-arguments-before-uac'

    $launcherSource=[IO.File]::ReadAllText((Resolve-Path $script:LauncherPath).Path)
    Assert-F2Diagnostic ($launcherSource -match '-Verb RunAs' -and $launcherSource -notmatch 'RedirectStandardOutput|RedirectStandardError') 'production-launcher-uses-normal-uac-and-does-not-assume-redirect-support'
    $publishedLauncherHash=Get-F2InstallLauncherHash -Bytes ([IO.File]::ReadAllBytes((Resolve-Path $script:LauncherPath).Path))
    $reviewUpdate=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'F2_G1_DIAGNOSTIC_INSTALL_REVIEW_UPDATE.md'))
    $publishedHashGuard="-cne '"+$publishedLauncherHash+"'"
    $outerBlock=[regex]::Match($reviewUpdate,'(?s)```powershell\s*(?<body>.*?)\s*```')
    $outerCommandMatch=[regex]::Match($outerBlock.Groups['body'].Value,'-EncodedCommand (?<encoded>[A-Za-z0-9+/=]+)')
    $outerSource=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($outerCommandMatch.Groups['encoded'].Value))
    Assert-F2Diagnostic ($outerBlock.Success -and $outerCommandMatch.Success -and $outerSource.Contains($publishedHashGuard) -and $outerSource.Contains('$sha.ComputeHash($bytes)') -and $outerSource.Contains('& $verified')) 'documented-standard-token-command-pins-launcher-and-executes-the-hashed-byte-array'
    $outerFixture=Join-Path $script:TempRoot 'outer-launcher-fixture.ps1';$outerMarker=Join-Path $script:TempRoot 'outer-launcher-marker.txt';[IO.File]::WriteAllText($outerFixture,"[IO.File]::WriteAllText('$outerMarker','OUTER_PINNED_LAUNCH_FIXTURE')",[Text.UTF8Encoding]::new($false))
    $outerFixtureHash=Get-F2InstallLauncherHash -Bytes ([IO.File]::ReadAllBytes($outerFixture))
    $outerSyntheticSource=$outerSource.Replace('C:\Dev\f2-g1-protected-install-prep\Start-F2VerifiedInstall.ps1',$outerFixture).Replace($publishedLauncherHash,$outerFixtureHash)
    $outerSyntheticEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($outerSyntheticSource))
    $outerRun=Start-F2SyntheticEncodedChild -Encoded $outerSyntheticEncoded -Name 'documented-outer-command'
    $outerExit=$outerRun.Process.ExitCode;$outerMarkerText=if(Test-Path -LiteralPath $outerMarker){[IO.File]::ReadAllText($outerMarker)}else{''}
    Assert-F2Diagnostic ($outerBlock.Success -and $outerCommandMatch.Success -and $outerExit -eq 0 -and $outerMarkerText -ceq 'OUTER_PINNED_LAUNCH_FIXTURE') 'documented-launch-command-executes-only-the-pinned-in-memory-fixture-in-ps51'
    $built=New-F2InstallElevatedCommand -BootstrapBytes $syntheticBootstrapBytes -MailboxDirectory (Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')) ('F2-G1-Install-'+[guid]::NewGuid().ToString('N'))) -Nonce ([guid]::NewGuid().ToString('N'))
    Assert-F2Diagnostic ($built.Length -lt 30000 -and $built -match 'ScriptBlock]::Create' -and $built -match 'FromBase64String') 'bounded-command-embeds-and-rehashes-approved-bootstrap-bytes'

    $script:F2InstallStartProcessProvider=$null
    Remove-Variable -Name F2ProviderCalls -Scope Global -ErrorAction SilentlyContinue
    if($script:Failures.Count-eq 0){Write-Output ('RESULT=PASS;ASSERTIONS='+$script:AssertionCount+';FAILURES=0;POWERSHELL='+$PSVersionTable.PSVersion)}else{Write-Output ('RESULT=FAIL;ASSERTIONS='+$script:AssertionCount+';FAILURES='+$script:Failures.Count);foreach($failure in $script:Failures){Write-Output ('FAILURE='+$failure)};exit 1}
} catch {
    Write-Output ('RESULT=ERROR;ASSERTIONS='+$script:AssertionCount+';ERROR='+$_.Exception.GetType().FullName+':'+$_.Exception.Message)
    exit 1
} finally {
    if(Test-Path -LiteralPath $script:TempRoot){Remove-Item -LiteralPath $script:TempRoot -Recurse -Force -ErrorAction SilentlyContinue}
}

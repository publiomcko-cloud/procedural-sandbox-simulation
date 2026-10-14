[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseContract.V4.SourceOnly.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseIntegration.V4.SourceOnly.psm1') -Force -ErrorAction Stop
$script:assertions=0
$script:failures=[Collections.Generic.List[string]]::new()
function Assert-Integration([bool]$condition,[string]$label) {
    $script:assertions++
    if(-not $condition){$script:failures.Add($label);Write-Output ('FAIL: '+$label)}
    else{Write-Output ('PASS: '+$label)}
}
$actors=@(Get-F2V4IntegrationRoles)
Assert-Integration ($actors.Count -eq 6 -and @($actors | Sort-Object -Unique).Count -eq 6) 'six independent integration roles and no duplicates'
$exported=@((Get-Module F2ReleaseIntegration.V4.SourceOnly).ExportedCommands.Keys)
Assert-Integration ($exported.Count -eq 4 -and $exported -contains 'Test-F2V4IntegrationBoundary' -and $exported -contains 'Test-F2V4RecoveryObservation') 'only four read-only contract functions exported'

$commitSha='1234567890abcdef1234567890abcdef12345678'
$packageHome='C:\F2SyntheticV4\PackageHome'
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$packageNames=@(Get-F2V4PackageNames)
$packageRows=@(foreach($name in $packageNames) {
    $file=Join-Path $PSScriptRoot $name
    $digest=(Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    [pscustomobject]@{Name=$name;Sha256=$digest}
})
$pinIcacls=[string](@($packageRows | Where-Object {$_.Name -ceq 'F2_ICACLS_SOURCE_PINS_V2.json'})[0].Sha256)
$pinOldIcacls=[string](@($packageRows | Where-Object {$_.Name -ceq 'F2_ICACLS_SOURCE_PINS.json'})[0].Sha256)
$pinAcl=[string](@($packageRows | Where-Object {$_.Name -ceq 'F2_ACL_SOURCE_PINS_V2.json'})[0].Sha256)
$pinOldAcl=[string](@($packageRows | Where-Object {$_.Name -ceq 'F2_ACL_SOURCE_PINS.json'})[0].Sha256)
$sourceManifest=[ordered]@{
    Schema='f2-icacls-runtime-release-v4'
    Status='SOURCE_ONLY_NOT_RELEASE_APPROVED'
    ReviewedCommitSha=$commitSha
    PackageRoot=(Join-Path (Join-Path $packageHome 'releases') $commitSha)
    BaselineMailboxId='ecb6deeb424e40feb5354d18908986df'
    BaselinePayloadCaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211'
    BaselinePayloadSha256='1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
    BaselineIntegritySha256='02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
    SourcePinsManifestSha256=$pinIcacls
    LegacySourcePinsManifestSha256=$pinOldIcacls
    CollectorPinsManifestSha256=$pinAcl
    LegacyCollectorPinsManifestSha256=$pinOldAcl
    Files=$packageRows
}
function Get-ManifestBytes($obj) {
    return [Text.UTF8Encoding]::new($false).GetBytes(($obj | ConvertTo-Json -Depth 10 -Compress))
}
$bytes=[byte[]](Get-ManifestBytes $sourceManifest)
$manifestSha=Get-F2V4Sha256 -Bytes $bytes
function Invoke-RoleTest {
    param([string]$Actor,[string]$Operation='Inspect',[byte[]]$Payload=$bytes,[string]$ManifestDigest=$manifestSha,[string]$PinDigest=$pinIcacls,[string]$TrustedCommit=$commitSha,[string]$ReportedCommit=$commitSha,[string]$Root=$sourceRoot,[switch]$DisableByteVerification)
    $callParams=@{Role=$Actor;Action=$Operation;ManifestBytes=$Payload;ExpectedManifestSha256=$ManifestDigest;ExpectedActivePinsSha256=$PinDigest;ExpectedCommitSha=$TrustedCommit;ActualCommitSha=$ReportedCommit;ExpectedPackageHome=$packageHome;SourceRoot=$Root}
    if(-not $DisableByteVerification){$callParams.VerifySourceBytes=$true}
    return Test-F2V4IntegrationBoundary @callParams
}
$operations=@{Collector='Capture';Runtime='Run';Coordinator='Launch';Launcher='Launch';Updater='Install';Recovery='ResumeForward'}
foreach($actor in $actors) {
    $desc=Get-F2V4IntegrationDescriptor -Role $actor
    Assert-Integration ($desc.Role -ceq $actor -and $desc.AllowedAction -ceq 'Inspect' -and -not $desc.V4RuntimeDispatchAllowed -and -not $desc.V4InstallAllowed -and -not $desc.V4RecoveryAllowed) ('actor '+$actor+' has exact inspect-only contract')
    $good=Invoke-RoleTest -Actor $actor
    Assert-Integration ($good.Pass -and $good.SourceBytesVerified -and $good.Disposition -ceq 'INSPECTION_ONLY' -and -not $good.CanCapture -and -not $good.CanLaunch -and -not $good.CanInstall -and -not $good.CanActivate -and -not $good.CanRollback -and -not $good.CanResumeForward -and -not $good.HasSideEffects -and -not $good.GitCommitIndependentlyAuthenticated -and -not $good.ManifestIndependentlyApproved) ('actor '+$actor+' accepts real checkout bytes without authorizing actions')
    $blocked=Invoke-RoleTest -Actor $actor -Operation $operations[$actor]
    Assert-Integration (-not $blocked.Pass -and $blocked.Disposition -ceq 'REJECTED' -and -not $blocked.CanInstall -and -not $blocked.CanResumeForward -and -not $blocked.HasSideEffects) ('actor '+$actor+' cannot dispatch protected action')
}
Assert-Integration (-not (Invoke-RoleTest -Actor 'Updater' -PinDigest ('0'*64)).Pass) 'incorrect v2 pin digest rejected'
Assert-Integration (-not (Invoke-RoleTest -Actor 'Runtime' -ManifestDigest ('0'*64)).Pass) 'incorrect external manifest digest rejected'
Assert-Integration (-not (Invoke-RoleTest -Actor 'Collector' -ReportedCommit ('0'*40)).Pass) 'mismatched Git HEAD report rejected'
Assert-Integration (-not (Invoke-RoleTest -Actor 'Launcher' -DisableByteVerification).Pass) 'manifest-only inspection cannot pass actor boundary'
Assert-Integration (-not (Invoke-RoleTest -Actor 'Coordinator' -Root 'G:\NotAllowed').Pass) 'G: source root rejected'
$mutant=$sourceManifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutant.Status='RELEASE_APPROVED'
$mutantBytes=[byte[]](Get-ManifestBytes $mutant)
Assert-Integration (-not (Invoke-RoleTest -Actor 'Updater' -Payload $mutantBytes -ManifestDigest (Get-F2V4Sha256 -Bytes $mutantBytes)).Pass) 'release-approved status spoof rejected'
$mutant=$sourceManifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutant.Schema='f2-icacls-runtime-release-v3'
$mutantBytes=[byte[]](Get-ManifestBytes $mutant)
Assert-Integration (-not (Invoke-RoleTest -Actor 'Runtime' -Payload $mutantBytes -ManifestDigest (Get-F2V4Sha256 -Bytes $mutantBytes)).Pass) 'v3/v4 cross-version substitution rejected'
$mutant=$sourceManifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$mutant.Files[0].Sha256=('0'*64)
$mutantBytes=[byte[]](Get-ManifestBytes $mutant)
Assert-Integration (-not (Invoke-RoleTest -Actor 'Collector' -Payload $mutantBytes -ManifestDigest (Get-F2V4Sha256 -Bytes $mutantBytes)).Pass) 'tampered source member pin rejected'

# Synthetic observation only; NEVER invoke real transaction recovery.
$txId='0123456789abcdef0123456789abcdef'
$oldSha='b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9'
$oldCommit='5741ffe90a3abd02a08563e6431e8a0b9b63eeb1'
$observation=[pscustomobject]@{
    Schema='f2-v4-recovery-observation-v1'
    ContractStatus='SOURCE_ONLY_NOT_RELEASE_APPROVED'
    TransactionId=$txId
    ReviewedCommitSha=$commitSha
    CandidateManifestSha256=$manifestSha
    OldManifestSha256=$oldSha
    OldReleaseCommitSha=$oldCommit
    ActiveManifestSha256=$oldSha
    LegacyBackupPreserved=$true
    ProtectedOperationOccurred=$false
    Phases=@('INVENTORY_OBSERVED','RETAINED_V2_PIN_VERIFIED','V4_SOURCE_VERIFIED','PROTECTED_OPERATION_NOT_STARTED')
}
function Invoke-RecoveryCheck {
    param($Envelope=$observation,[string]$Action='Inspect',[string]$OldDigest=$oldSha,[string]$ManifestDigest=$manifestSha,[string]$Commit=$commitSha,[string]$Transaction=$txId)
    return Test-F2V4RecoveryObservation -Action $Action -Observation $Envelope -ExpectedTransactionId $Transaction -ExpectedCommitSha $Commit -ExpectedCandidateManifestSha256 $ManifestDigest -ExpectedOldManifestSha256 $OldDigest
}
$inspect=Invoke-RecoveryCheck
Assert-Integration ($inspect.Pass -and $inspect.Disposition -ceq 'OBSERVATION_ACCEPTED_NO_RECOVERY' -and $inspect.LegacyReleasePreserved -and -not $inspect.MayPerformProtectedRecovery -and -not $inspect.MayRollback -and -not $inspect.MayResumeForward -and -not $inspect.MayActivate -and -not $inspect.HasSideEffects) 'valid recovery observation never authorizes recovery'
foreach($action in @('Rollback','ResumeForward','Activate')){
    $bad=Invoke-RecoveryCheck -Action $action
    Assert-Integration (-not $bad.Pass -and -not $bad.MayPerformProtectedRecovery -and -not $bad.HasSideEffects) ('protected recovery action '+$action+' denied')
}
Assert-Integration (-not (Invoke-RecoveryCheck -OldDigest ('0'*64)).Pass) 'wrong externally pinned old manifest rejected'
function Copy-Observation {return ($observation | ConvertTo-Json -Depth 8 | ConvertFrom-Json)}
$o=Copy-Observation;$o.ActiveManifestSha256=('0'*64)
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'unknown active release digest rejected'
$o=Copy-Observation;$o.OldReleaseCommitSha=('0'*40)
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'modified old-release commit rejected'
$o=Copy-Observation;$o.ProtectedOperationOccurred=$true
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'observed protected side effects rejected'
$o=Copy-Observation;$o.LegacyBackupPreserved=$false
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'missing historical backup rejected'
$o=Copy-Observation;$o.Phases[1]=$o.Phases[0]
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'duplicate recovery observation phase rejected'
$o=Copy-Observation;$o.Phases=@($o.Phases[1],$o.Phases[0],$o.Phases[2],$o.Phases[3])
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'out-of-order recovery phase rejected'
$o=Copy-Observation;$o.Phases=@($o.Phases[0],$o.Phases[1])
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'incomplete recovery phase sequence rejected'
$o=Copy-Observation;$o.ContractStatus='RELEASE_APPROVED'
Assert-Integration (-not (Invoke-RecoveryCheck -Envelope $o).Pass) 'forged approval rejected'
Assert-Integration (-not (Invoke-RecoveryCheck -Commit ('f'*40)).Pass) 'recovery reviewed commit mismatch rejected'
Assert-Integration (-not (Invoke-RecoveryCheck -ManifestDigest ('f'*64)).Pass) 'recovery manifest digest mismatch rejected'
Assert-Integration (-not (Invoke-RecoveryCheck -Transaction ('f'*32)).Pass) 'recovery transaction ID mismatch rejected'

# Static compatibility checks only. Never import or invoke production entrypoints.
$runtimeSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1'))
$coordSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2IcaclsProtectedCoordinator.ps1'))
$updaterSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2ProtectedReleaseUpdate.ps1'))
$launchSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Start-F2ProtectedReleaseUpdate.ps1'))
$collectorSource=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2AclReadOnlyCapture.ps1'))
Assert-Integration ($runtimeSource.Contains("'f2-icacls-runtime-release-v3'") -and -not $runtimeSource.Contains("'f2-icacls-runtime-release-v4'")) 'runtime dispatch remains v3-only'
Assert-Integration ($coordSource.Contains("'f2-icacls-runtime-release-v3'") -and -not $coordSource.Contains("'f2-icacls-runtime-release-v4'")) 'protected coordinator remains v3-only'
Assert-Integration ($updaterSource.Contains("[ValidateSet('v2','v3')]") -and -not $updaterSource.Contains("[ValidateSet('v2','v3','v4')]")) 'updater retains v2/v3-only gate'
Assert-Integration ($launchSource.Contains("'f2-icacls-runtime-release-v3'") -and -not $launchSource.Contains("'f2-icacls-runtime-release-v4'")) 'UAC launcher cannot dispatch v4'
Assert-Integration ($collectorSource.Contains("'f2-acl-source-pins-v1'") -and -not $collectorSource.Contains("'f2-acl-source-pins-v2'")) 'collector continues using v1 source pins'

Write-Output ("Assertions={0};Failures={1}" -f $script:assertions,$script:failures.Count)
if($script:failures.Count -gt 0){exit 1}

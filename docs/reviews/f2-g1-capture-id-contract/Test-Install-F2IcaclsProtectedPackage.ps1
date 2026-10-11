[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Install-F2IcaclsProtectedPackage.ps1')

$script:assertions=0;$script:failures=New-Object 'System.Collections.Generic.List[string]'
function Assert-Install([bool]$Condition,[string]$Name){$script:assertions++;if(-not $Condition){$script:failures.Add($Name);Write-Host ('FAIL: '+$Name)}else{Write-Host ('PASS: '+$Name)}}

. (Join-Path $PSScriptRoot 'Invoke-F2VerifiedInstaller.ps1')
Assert-Install (($script:F2ApprovedInstallerPath -ceq 'C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1') -and ($script:F2ApprovedInstallerSha256 -ceq 'ca4d5a213615b1ce74d8fc7df17e7bb65ccfbcacd9dd7de2c9a6c36d42842d2d')) 'production bootstrap pins the approved source installer path and digest'

$repo='C:\Dev\f2-g1-capture-id-contract-source'
$sourceAcl=Join-Path $repo 'scripts\f2-acl'
$originalAdmin=$script:F2InstallAdminSid
$testOwnerSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$script:F2InstallAdminSid=$testOwnerSid
$script:F2InstallReparseProvider=$null
$testFiles=@($script:F2InstallFiles.Keys)
$sourcePin=Get-F2InstallHashBytes -Bytes ([IO.File]::ReadAllBytes((Join-Path $sourceAcl 'F2_ICACLS_SOURCE_PINS.json')))
$syntheticProject='G:\F2-G1-Isolated-Disposable'
$syntheticPaths=@(Get-F2InstallExpectedPaths -ProjectRoot $syntheticProject)
$requester='S-1-5-21-101010101-202020202-303030303-1001'
$system=$script:F2InstallSystemSid;$admin=$script:F2InstallAdminSid
$safeParent=('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})(A;;0x001200A9;;;AU)' -f $admin)
$programDataParent=('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})(A;;0x001200A9;;;AU)(A;OICI;0x00000116;;;BU)' -f $admin)

function New-InstallFixture {
    $root=Join-Path $env:TEMP ('F2 install synthetic '+[guid]::NewGuid().ToString('N'))
    $pf=Join-Path $root 'ProgramFiles';$pd=Join-Path $root 'ProgramData';$src=Join-Path $root 'Source';$srcAcl=Join-Path $src 'scripts\f2-acl';$baselineDir=Join-Path $pd ('F2-G1-ACL-Evidence-'+$script:F2InstallBaselineMailboxId)
    foreach($dir in @($pf,$pd,$srcAcl)){[void][IO.Directory]::CreateDirectory($dir)}
    foreach($name in $script:F2InstallFiles.Keys){Copy-Item -LiteralPath (Join-Path $sourceAcl $name) -Destination (Join-Path $srcAcl $name)}
    $pinBytes=[IO.File]::ReadAllBytes((Join-Path $srcAcl 'F2_ICACLS_SOURCE_PINS.json'))
    $baselineSddl=('O:{0}D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;{0})(A;OICI;0x001200A9;;;S-1-3-4)(A;OICI;0x001200A9;;;{1})' -f $admin,$requester)
    $baselineAcl=[Security.AccessControl.DirectorySecurity]::new();$baselineAcl.SetSecurityDescriptorSddlForm($baselineSddl)
    [void][IO.Directory]::CreateDirectory($baselineDir,$baselineAcl)
    $baseline=[ordered]@{Schema='f2-acl-baseline-v1';CaptureId=$script:F2InstallBaselinePayloadCaptureId;Complete=$true;VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable';VmState='Off';Manifest=[pscustomobject]@{ExpectedCount=11;ExpectedPaths=$syntheticPaths};Records=@(foreach($path in $syntheticPaths){[pscustomobject]@{Path=$path;Status='PASS';Aces=@()}})}
    $payload=[Text.UTF8Encoding]::new($false).GetBytes(($baseline|ConvertTo-Json -Depth 8 -Compress))
    $integrity=[ordered]@{Schema='f2-acl-integrity-v1';PayloadFile='acl-baseline.json';PayloadBytes=$payload.Length;PayloadSha256=(Get-F2InstallHashBytes $payload);CollectorScriptSha256=$script:F2InstallFiles['Invoke-F2AclReadOnlyCapture.ps1'];ProtocolModuleSha256=$script:F2InstallFiles['F2AclCapture.Protocol.psm1'];ProjectVolumeGuid='\\?\Volume{11111111-1111-1111-1111-111111111111}\';EvidenceVolumeGuid='\\?\Volume{22222222-2222-2222-2222-222222222222}\';SeparateFromProjectVolume=$true}
    $integrityBytes=[Text.UTF8Encoding]::new($false).GetBytes(($integrity|ConvertTo-Json -Depth 6 -Compress))
    [IO.File]::WriteAllBytes((Join-Path $baselineDir 'acl-baseline.json'),$payload);[IO.File]::WriteAllBytes((Join-Path $baselineDir 'integrity.json'),$integrityBytes)
    $context=@{SourceRoot=$src;ProgramFilesParent=$pf;CommonApplicationData=$pd;PackageFinal=(Join-Path $pf 'F2-G1-Icacls');ReleaseDirectoryFinal=(Join-Path $pd 'F2-G1-Icacls');BaselineDirectory=$baselineDir;BaselineMailboxId=$script:F2InstallBaselineMailboxId;BaselinePayloadCaptureId=$script:F2InstallBaselinePayloadCaptureId;BaselinePayloadSha256=(Get-F2InstallHashBytes $payload);BaselineIntegritySha256=(Get-F2InstallHashBytes $integrityBytes);SourcePinsSha256=(Get-F2InstallHashBytes $pinBytes);RequesterSid=$requester;ParentSddlProvider=$null}
    $context.ParentSddlProvider={param($path)if([string]::Equals($path,$context.CommonApplicationData,[StringComparison]::OrdinalIgnoreCase)){$programDataParent}else{$safeParent}}.GetNewClosure()
    return [pscustomobject]@{Root=$root;Context=$context;PayloadPath=(Join-Path $baselineDir 'acl-baseline.json');PackageFinal=$context.PackageFinal;ReleaseFinal=$context.ReleaseDirectoryFinal}
}

function Set-InstallFixturePayload([object]$Fixture,[byte[]]$PayloadBytes) {
    [IO.File]::WriteAllBytes($Fixture.PayloadPath,$PayloadBytes)
    $integrityPath=Join-Path (Split-Path -Parent $Fixture.PayloadPath) 'integrity.json'
    $integrity=Get-Content -LiteralPath $integrityPath -Raw|ConvertFrom-Json
    $integrity.PayloadBytes=$PayloadBytes.Length;$integrity.PayloadSha256=Get-F2InstallHashBytes -Bytes $PayloadBytes
    $integrityBytes=[Text.UTF8Encoding]::new($false).GetBytes(($integrity|ConvertTo-Json -Depth 6 -Compress))
    [IO.File]::WriteAllBytes($integrityPath,$integrityBytes)
    $Fixture.Context.BaselinePayloadSha256=Get-F2InstallHashBytes -Bytes $PayloadBytes
    $Fixture.Context.BaselineIntegritySha256=Get-F2InstallHashBytes -Bytes $integrityBytes
}

$fixture=$null
try {
    $fixture=New-InstallFixture
    $success=Invoke-F2InstallCore -Context $fixture.Context
    if(-not $success.Success){Write-Host ('SyntheticInstallFailure=' + ($success | ConvertTo-Json -Compress -Depth 4));throw 'Synthetic install fixture failed before assertion evaluation.'}
    Assert-Install ($success.Success -and $success.Outcome -eq 'INSTALL_COMPLETE') 'synthetic install succeeds in temporary directories without elevation'
    Assert-Install ($success.InstalledFileCount -eq 7 -and $success.Attestation.Count -eq 12) 'attestation covers four directories and seven package files plus the release manifest'
    Assert-Install ((Test-Path -LiteralPath $success.PackagePath) -and (Test-Path -LiteralPath $success.ReleaseManifestPath)) 'package and external release manifest publish at the required relative layout'
    $manifest=Get-Content -LiteralPath $success.ReleaseManifestPath -Raw|ConvertFrom-Json
    Assert-Install ($manifest.Schema -ceq 'f2-icacls-runtime-release-v2' -and $manifest.ReviewedCommitSha -eq $script:F2InstallReviewedCommit -and $manifest.BaselineMailboxId -eq $script:F2InstallBaselineMailboxId -and $manifest.BaselinePayloadCaptureId -eq $script:F2InstallBaselinePayloadCaptureId -and $manifest.Files.Count -eq 7) 'versioned release manifest binds reviewed SHA, distinct baseline IDs and exactly seven package files'
    Assert-Install ($manifest.BaselinePayloadSha256 -eq $fixture.Context.BaselinePayloadSha256 -and $manifest.BaselineIntegritySha256 -eq $fixture.Context.BaselineIntegritySha256 -and $manifest.SourcePinsManifestSha256 -eq $fixture.Context.SourcePinsSha256) 'release manifest pins both evidence files and the source pin manifest'
    $baselineRead=Read-F2InstallBaseline -Context $fixture.Context
    Assert-Install ($baselineRead.MailboxId -ceq $script:F2InstallBaselineMailboxId -and $baselineRead.PayloadCaptureId -ceq $script:F2InstallBaselinePayloadCaptureId) 'installer baseline reader accepts producer-compatible distinct mailbox and payload IDs'
    $wrongMailboxContext=$fixture.Context.Clone();$wrongMailboxContext.BaselineMailboxId='ffffffffffffffffffffffffffffffff';$wrongMailboxRejected=$false
    try{[void](Read-F2InstallBaseline -Context $wrongMailboxContext)}catch{$wrongMailboxRejected=$true}
    Assert-Install $wrongMailboxRejected 'installer rejects a wrong mailbox ID without relaxing directory or four-ACE checks'
    $wrongPayloadPinContext=$fixture.Context.Clone();$wrongPayloadPinContext.BaselinePayloadCaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7210';$wrongPayloadPinRejected=$false
    try{[void](Read-F2InstallBaseline -Context $wrongPayloadPinContext)}catch{$wrongPayloadPinRejected=$true}
    Assert-Install $wrongPayloadPinRejected 'installer rejects a wrong independently pinned payload CaptureId'
    $payloadObject=Get-Content -LiteralPath $fixture.PayloadPath -Raw|ConvertFrom-Json;$payloadObject.CaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7210'
    $changedPayload=[Text.UTF8Encoding]::new($false).GetBytes(($payloadObject|ConvertTo-Json -Depth 8 -Compress));[IO.File]::WriteAllBytes($fixture.PayloadPath,$changedPayload)
    $integrityPath=Join-Path (Split-Path -Parent $fixture.PayloadPath) 'integrity.json';$integrityObject=Get-Content -LiteralPath $integrityPath -Raw|ConvertFrom-Json;$integrityObject.PayloadBytes=$changedPayload.Length;$integrityObject.PayloadSha256=Get-F2InstallHashBytes -Bytes $changedPayload;$changedIntegrity=[Text.UTF8Encoding]::new($false).GetBytes(($integrityObject|ConvertTo-Json -Depth 6 -Compress));[IO.File]::WriteAllBytes($integrityPath,$changedIntegrity)
    $changedPayloadContext=$fixture.Context.Clone();$changedPayloadContext.BaselinePayloadSha256=Get-F2InstallHashBytes -Bytes $changedPayload;$changedPayloadContext.BaselineIntegritySha256=Get-F2InstallHashBytes -Bytes $changedIntegrity;$changedEmbeddedIdRejected=$false
    try{[void](Read-F2InstallBaseline -Context $changedPayloadContext)}catch{$changedEmbeddedIdRejected=$true}
    Assert-Install $changedEmbeddedIdRejected 'installer rejects a wrong embedded payload CaptureId even after payload and integrity digests are consistently recomputed'
    $validPayload=[Text.UTF8Encoding]::new($false).GetBytes((([ordered]@{Schema='f2-acl-baseline-v1';CaptureId=$script:F2InstallBaselinePayloadCaptureId;Complete=$true;VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable';VmState='Off';Manifest=[pscustomobject]@{ExpectedCount=11;ExpectedPaths=$syntheticPaths};Records=@(foreach($path in $syntheticPaths){[pscustomobject]@{Path=$path;Status='PASS';Aces=@()}})}|ConvertTo-Json -Depth 8 -Compress)))
    Set-InstallFixturePayload -Fixture $fixture -PayloadBytes $validPayload
    $tamperedIntegrityPath=Join-Path (Split-Path -Parent $fixture.PayloadPath) 'integrity.json';[IO.File]::AppendAllText($tamperedIntegrityPath,' ');$integrityHashRejected=$false
    try{[void](Read-F2InstallBaseline -Context $fixture.Context)}catch{$integrityHashRejected=$true}
    Assert-Install $integrityHashRejected 'modified integrity file bytes fail their externally pinned hash'
    Set-InstallFixturePayload -Fixture $fixture -PayloadBytes $validPayload
    $missingPayloadBytes=[IO.File]::ReadAllBytes($fixture.PayloadPath);[IO.File]::Delete($fixture.PayloadPath);$missingPayloadRejected=$false
    try{[void](Read-F2InstallBaseline -Context $fixture.Context)}catch{$missingPayloadRejected=$true}
    Assert-Install $missingPayloadRejected 'missing baseline payload fails installer preflight'
    Set-InstallFixturePayload -Fixture $fixture -PayloadBytes $validPayload
    $malformedPayload=[Text.Encoding]::UTF8.GetBytes('{');Set-InstallFixturePayload -Fixture $fixture -PayloadBytes $malformedPayload;$malformedRejected=$false
    try{[void](Read-F2InstallBaseline -Context $fixture.Context)}catch{$malformedRejected=$true}
    Assert-Install $malformedRejected 'malformed baseline JSON fails even when its synthetic integrity digest is recomputed'
    $duplicateDocument=[Text.Encoding]::UTF8.GetString($validPayload)|ConvertFrom-Json;$duplicateDocument.Records[0].Path=$duplicateDocument.Records[1].Path
    $duplicatePayload=[Text.UTF8Encoding]::new($false).GetBytes(($duplicateDocument|ConvertTo-Json -Depth 8 -Compress));Set-InstallFixturePayload -Fixture $fixture -PayloadBytes $duplicatePayload;$duplicateRejected=$false
    try{[void](Read-F2InstallBaseline -Context $fixture.Context)}catch{$duplicateRejected=$true}
    Assert-Install $duplicateRejected 'duplicate baseline object paths fail installer preflight'
    $allSecure=$true
    foreach($entry in $success.Attestation){$kind=if($entry.Type -eq 'Directory'){'Directory'}else{'File'};if(-not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl $entry.Path) -Kind $kind) -or $entry.ReparsePoint){$allSecure=$false}}
    Assert-Install $allSecure 'all published files and directories have exact protected ACLs and no reparse attributes'
    Assert-Install (Test-F2InstallSafeParentSddl -Sddl $programDataParent -AllowProgramDataCreateMask) 'observed benign ProgramData child-create mask is accepted when isolated by protected child DACL'
    Assert-Install (-not (Test-F2InstallSafeParentSddl -Sddl ('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})(A;OICI;0x00000040;;;BU)' -f $admin) -AllowProgramDataCreateMask)) 'parent DELETE_CHILD grant is rejected'
    Assert-Install (-not (Test-F2InstallSafeParentSddl -Sddl ('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})(A;OICI;0x00040000;;;BU)' -f $admin) -AllowProgramDataCreateMask)) 'parent WRITE_DAC grant is rejected'
    Assert-Install (-not (Test-F2InstallSafeParentSddl -Sddl ('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})(A;OICI;0x00080000;;;BU)' -f $admin) -AllowProgramDataCreateMask)) 'parent WRITE_OWNER grant is rejected'
    Assert-Install (-not (Test-F2InstallSafeParentSddl -Sddl ('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})(A;OICI;0x10000000;;;BU)' -f $admin) -AllowProgramDataCreateMask)) 'parent GENERIC_ALL grant is rejected'
    Assert-Install (-not (Test-F2InstallSafeParentSddl -Sddl ('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})(A;OICI;0x01000000;;;BU)' -f $admin))) 'unrecognized ordinary-user parent access mask is rejected'
    Assert-Install (-not (Test-F2InstallExactDacl -Sddl ((Get-F2InstallExpectedSddl -Kind File).Replace('D:P','D:')) -Kind File)) 'inheriting/unprotected file DACL fixture is rejected'
    $script:F2InstallReparseProvider={param($path)[string]::Equals($path,$fixture.Root,[StringComparison]::OrdinalIgnoreCase)}.GetNewClosure()
    $reparseRejected=$false;try{Test-F2InstallNoReparseChain -Path (Join-Path $fixture.Root 'missing-child')|Out-Null}catch{$reparseRejected=$_.Exception.Message -eq 'INSTALL_REPARSE_POINT'}
    Assert-Install $reparseRejected 'synthetic reparse ancestor is rejected'
    $script:F2InstallReparseProvider=$null
} finally {
    $script:F2InstallReparseProvider=$null
    if($fixture -and (Test-Path -LiteralPath $fixture.Root)){Remove-Item -LiteralPath $fixture.Root -Recurse -Force}
}

$fixture=New-InstallFixture
try {
    [void][IO.Directory]::CreateDirectory($fixture.PackageFinal)
    $marker=Join-Path $fixture.PackageFinal 'owner-data.txt';[IO.File]::WriteAllText($marker,'preserve')
    $collision=Invoke-F2InstallCore -Context $fixture.Context
    Assert-Install (-not $collision.Success -and [IO.File]::ReadAllText($marker) -ceq 'preserve') 'preexisting destination collision fails closed without overwriting existing content'
} finally { if(Test-Path -LiteralPath $fixture.Root){Remove-Item -LiteralPath $fixture.Root -Recurse -Force} }

$fixture=New-InstallFixture
try {
    $tamper=Join-Path $fixture.Context.SourceRoot 'scripts\f2-acl\F2AclIcacls.Runtime.psm1';[IO.File]::AppendAllText($tamper,'#tamper')
    $result=Invoke-F2InstallCore -Context $fixture.Context
    Assert-Install (-not $result.Success -and -not (Test-Path -LiteralPath $fixture.PackageFinal)) 'modified source package fails before publishing any protected destination'
} finally { if(Test-Path -LiteralPath $fixture.Root){Remove-Item -LiteralPath $fixture.Root -Recurse -Force} }

$fixture=New-InstallFixture
try {
    [IO.File]::AppendAllText($fixture.PayloadPath,' ')
    $result=Invoke-F2InstallCore -Context $fixture.Context
    Assert-Install (-not $result.Success -and -not (Test-Path -LiteralPath $fixture.PackageFinal)) 'changed baseline evidence fails before publishing any protected destination'
} finally { if(Test-Path -LiteralPath $fixture.Root){Remove-Item -LiteralPath $fixture.Root -Recurse -Force} }

$script:F2InstallAdminSid=$originalAdmin

# The mailbox contract binds its fourth ACE to the baseline requester SID. A
# different Administrator UAC identity must fail in preflight; it is not
# silently substituted into or broadened beyond the exact four-ACE DACL.
$fixture=New-InstallFixture
try {
    $fixture.Context.RequesterSid='S-1-5-21-404040404-505050505-606060606-1002'
    $differentRequester=Invoke-F2InstallCore -Context $fixture.Context
    $staging=@(Get-ChildItem -LiteralPath $fixture.Context.ProgramFilesParent -Force | Where-Object Name -like '.F2-G1-Icacls-stage-*')
    Assert-Install (-not $differentRequester.Success -and $differentRequester.Stage -eq 'Preflight') 'different Administrator requester SID fails closed before staging'
    Assert-Install (-not (Test-Path -LiteralPath $fixture.PackageFinal) -and -not (Test-Path -LiteralPath $fixture.ReleaseFinal) -and $staging.Count -eq 0) 'different requester SID causes no package, release, or staging writes'
} finally { if(Test-Path -LiteralPath $fixture.Root){Remove-Item -LiteralPath $fixture.Root -Recurse -Force} }

# Exercise the actual bootstrap function boundary without elevation or protected
# directories. These temporary files are synthetic and live only under TEMP.
$bootstrapRoot=Join-Path $env:TEMP ('F2 verified bootstrap synthetic '+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($bootstrapRoot)
try {
    $installerPath=Join-Path $bootstrapRoot 'synthetic-installer.ps1'
    $markerPath=Join-Path $bootstrapRoot 'protected-write-marker.txt'
    $tamperSource='$p='''+$markerPath.Replace("'","''")+''';[IO.File]::WriteAllText($p,''executed'')'
    [IO.File]::WriteAllText($installerPath,$tamperSource,[Text.UTF8Encoding]::new($false))
    $approvedHash=Get-F2InstallHashBytes -Bytes ([IO.File]::ReadAllBytes($installerPath))
    [IO.File]::AppendAllText($installerPath,'#tampered')
    $tamperRejected=$false
    try { Invoke-F2VerifiedInstallerCore -InstallerPath $installerPath -ExpectedSha256 $approvedHash | Out-Null }
    catch { $tamperRejected=$_.Exception.Message -eq 'BOOTSTRAP_INSTALLER_HASH_MISMATCH' }
    Assert-Install ($tamperRejected -and -not (Test-Path -LiteralPath $markerPath)) 'modified installer is rejected before its synthetic protected write'

    $selfModifyingSource='if($MyInvocation.InvocationName -ne ''.''){$p='''+$installerPath.Replace("'","''")+''';$m='''+$markerPath.Replace("'","''")+''';[IO.File]::WriteAllText($p,''changed after verification'');[IO.File]::WriteAllText($m,''executed verified bytes'')}'
    [IO.File]::WriteAllText($installerPath,$selfModifyingSource,[Text.UTF8Encoding]::new($false))
    $selfModifyingHash=Get-F2InstallHashBytes -Bytes ([IO.File]::ReadAllBytes($installerPath))
    Invoke-F2VerifiedInstallerCore -InstallerPath $installerPath -ExpectedSha256 $selfModifyingHash | Out-Null
    Assert-Install ([IO.File]::ReadAllText($markerPath) -ceq 'executed verified bytes' -and [IO.File]::ReadAllText($installerPath) -ceq 'changed after verification') 'bootstrap invokes script entrypoint from verified bytes after backing path changes'

    $badHashRejected=$false
    try { Invoke-F2VerifiedInstallerCore -InstallerPath $installerPath -ExpectedSha256 'not-a-sha256' | Out-Null }
    catch { $badHashRejected=$_.Exception.Message -eq 'BOOTSTRAP_EXPECTED_HASH_INVALID' }
    Assert-Install $badHashRejected 'bootstrap rejects malformed pinned hashes'
} finally { if(Test-Path -LiteralPath $bootstrapRoot){Remove-Item -LiteralPath $bootstrapRoot -Recurse -Force} }

"Assertions=$script:assertions;Failures=$($script:failures.Count)"
if($script:failures.Count -gt 0){$script:failures|ForEach-Object{Write-Error $_};exit 1}

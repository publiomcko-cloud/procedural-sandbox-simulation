[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$testCount=0;$failures=New-Object 'System.Collections.Generic.List[string]'
function Assert-Icacl([bool]$Condition,[string]$Message){$script:testCount++;if(-not $Condition){$script:failures.Add($Message);Write-Host ('FAIL: '+$Message)}else{Write-Host ('PASS: '+$Message)}}
function New-CommandResult([string]$Path,[int]$Code=0,[string]$Stdout='',[string]$Stderr='',[bool]$Timeout=$false,[bool]$Complete=$true,[bool]$Cleanup=$true,[bool]$Truncated=$false){[pscustomobject]@{Path=$Path;ProcessId=1234;ExitCode=$Code;TimedOut=$Timeout;CleanupComplete=$Cleanup;OutputComplete=$Complete;Truncated=$Truncated;Stdout=$Stdout;Stderr=$Stderr;ReaderError=$null;ElapsedMilliseconds=15;StdoutBytes=[Text.Encoding]::UTF8.GetByteCount($Stdout);StderrBytes=[Text.Encoding]::UTF8.GetByteCount($Stderr);StdoutSha256='a';StderrSha256='b'}}

$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptDir 'F2AclIcacls.Corroboration.psm1') -Force
Import-Module (Join-Path $scriptDir 'F2AclCapture.Protocol.psm1') -Force
$script:corroborationModule=Get-Module F2AclIcacls.Corroboration
$script:privateProcessInvocation=[scriptblock]::Create('param($file,$arguments,$timeout,$cleanup,$drain,$maxBytes) Invoke-F2IcaclsProcessCore -FilePath $file -Arguments $arguments -TimeoutSeconds $timeout -CleanupGraceMilliseconds $cleanup -DrainGraceMilliseconds $drain -MaxBytesPerStream $maxBytes')
function Invoke-TestIcaclsProcess([string]$FilePath,[string]$Arguments,[int]$TimeoutSeconds=15,[int]$CleanupGraceMilliseconds=1000,[int]$DrainGraceMilliseconds=1000,[int]$MaxBytesPerStream=262144){return $script:corroborationModule.Invoke($script:privateProcessInvocation,@($FilePath,$Arguments,$TimeoutSeconds,$CleanupGraceMilliseconds,$DrainGraceMilliseconds,$MaxBytesPerStream))}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $scriptDir '..\..'))
$pinPath=Join-Path $scriptDir 'F2_ICACLS_SOURCE_PINS.json'
$pinHash=Get-F2IcaclsFileSha256 -Path $pinPath
$sourceCommit=(& git -C $repoRoot rev-parse HEAD).Trim()
$baselinePinIntegrity=[pscustomobject]@{CollectorScriptSha256='bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b';ProtocolModuleSha256='42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'}
$actualPins=Test-F2IcaclsSourcePins -RepositoryRoot $repoRoot -Integrity $baselinePinIntegrity -ExpectedPinManifestSha256 $pinHash -ExpectedCommitSha $sourceCommit -ActualCommitSha $sourceCommit
Assert-Icacl $actualPins.Pass 'actual repository helper pins match source files and retained collector provenance'

$projectRoot='C:\F2Synthetic\F2-G1-Isolated-Disposable'
$paths=@(Get-F2IcaclsExpectedPaths -ProjectRoot $projectRoot)
$projectVolume='\\?\Volume{11111111-1111-1111-1111-111111111111}\'
$evidenceVolume='\\?\Volume{22222222-2222-2222-2222-222222222222}\'
$sha='a' * 64;$sourceSha='b' * 64;$moduleSha='c' * 64
$records=@();foreach($path in $paths){$records+=@([pscustomobject]@{Path=$path;Status='PASS';Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type='Allow';AccessMask='0x001F01FF';InheritanceFlags='None';PropagationFlags='None';Inherited=$false})})}
$baseline=[pscustomobject]@{Complete=$true;VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable';VmState='Off';CaptureId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';Manifest=[pscustomobject]@{ExpectedCount=11;ExpectedPaths=$paths;RecordCount=11;UniquePathCount=11;ProjectVolumeGuid=$evidenceVolume};Records=$records}
$integrity=[pscustomobject]@{PayloadSha256=$sha;ProjectVolumeGuid=$projectVolume;EvidenceVolumeGuid=$evidenceVolume;SeparateFromProjectVolume=$true}
$storage=[pscustomobject]@{Win32MatchCount=1;DiskMatchCount=1;PhysicalMatchCount=1;Win32Serial='152D20337A0C';DiskSerial='152D20337A0C';PhysicalSerial='152D20337A0C';Win32Model='KINGSTON  SA400S37240G USB Device';DiskFriendlyName='KINGSTON SA400S37240G';DiskModel=' SA400S37240G   ';BusType='USB';DiskHealth='Healthy';PhysicalHealth='Healthy';DiskOperationalStatus='Online';PartitionDiskNumber=2;DiskNumber=2;Win32Index=2;GDriveLetter='G:';VolumeFileSystem='NTFS';GVolumeGuid=$projectVolume}
$observation=[pscustomobject]@{VmId=$baseline.VmId;VmName=$baseline.VmName;VmState='Off';NicCount=0;Storage=$storage;GVolumeGuid=$projectVolume;EvidenceVolumeGuid=$evidenceVolume;PathChecks=@($paths|%{[pscustomobject]@{Path=$_;Exists=$true;ReparsePoint=$false;ParentChainClear=$true}});EvidenceDirectory=[pscustomobject]@{Protected=$true;OwnerSid='S-1-5-32-544';NoUnexpectedPrincipals=$true;SeparateFromG=$true}}
$preflightArgs=@{Baseline=$baseline;Integrity=$integrity;Observation=$observation;BaselineSha256=$sha;ExpectedBaselineSha256=$sha;ExpectedScriptSha256=$sourceSha;ActualScriptSha256=$sourceSha;ExpectedModuleSha256=$moduleSha;ActualModuleSha256=$moduleSha;ProjectRoot=$projectRoot}
$preflight=Test-F2IcaclsPreflight @preflightArgs -Verbose
if(-not $preflight.Pass){$preflight.Gates|ForEach-Object{Write-Host ("PreflightGate={0};Pass={1};Detail={2}" -f $_.Name,$_.Pass,$_.Detail)}}
Assert-Icacl $preflight.Pass 'all pre-elevation synthetic identity, manifest, volume, path, pin and evidence gates pass'
Assert-Icacl ($preflight.ExpectedPaths.Count -eq 11 -and @($preflight.ExpectedPaths|Sort-Object -Unique).Count -eq 11) 'expected allowlist contains exactly 11 unique objects'
function Invoke-PreflightOverride([string]$Key,$Value){$copy=@{};foreach($k in $preflightArgs.Keys){$copy[$k]=$preflightArgs[$k]};$copy[$Key]=$Value;return Test-F2IcaclsPreflight @copy}
$bad=$observation.PSObject.Copy();$bad.NicCount=1
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $bad).Pass) 'unexpected NIC fails before any coordinator can launch'
$badStorage=$storage.PSObject.Copy();$badStorage.Win32Model='OTHER USB DEVICE';$badObs=$observation.PSObject.Copy();$badObs.Storage=$badStorage
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'incorrect Kingston model fails closed'
$badStorage=$storage.PSObject.Copy();$badStorage.PhysicalMatchCount=2;$badObs=$observation.PSObject.Copy();$badObs.Storage=$badStorage
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'ambiguous disk identity fails closed'
$badIntegrity=$integrity.PSObject.Copy();$badIntegrity.ProjectVolumeGuid=$evidenceVolume
Assert-Icacl (-not (Invoke-PreflightOverride 'Integrity' $badIntegrity).Pass) 'evidence volume GUID cannot be substituted for ProjectVolumeGuid'
$badIntegrity=$integrity.PSObject.Copy();$badIntegrity.ProjectVolumeGuid='\\?\Volume{33333333-3333-3333-3333-333333333333}\'
Assert-Icacl (-not (Invoke-PreflightOverride 'Integrity' $badIntegrity).Pass) 'wrong G: volume identity fails closed'
$badIntegrity=$integrity.PSObject.Copy();$badIntegrity.PayloadSha256='0'*64
Assert-Icacl (-not (Invoke-PreflightOverride 'Integrity' $badIntegrity).Pass) 'baseline integrity digest mismatch fails closed'
$badObs=$observation.PSObject.Copy();$badObs.PathChecks=@($observation.PathChecks);$badObs.PathChecks[5].ReparsePoint=$true
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'reparse path fails before UAC'
$badObs=$observation.PSObject.Copy();$badObs.PathChecks=@($observation.PathChecks);$badObs.PathChecks[7].ParentChainClear=$false
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'reparse or alias in an ancestor chain fails before UAC'
$badObs=$observation.PSObject.Copy();$badObs.PathChecks=@($observation.PathChecks|Select-Object -First 10)
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'missing path check fails before UAC'
$badObs=$observation.PSObject.Copy();$badEvidence=$observation.EvidenceDirectory.PSObject.Copy();$badEvidence.SeparateFromG=$false;$badObs.EvidenceDirectory=$badEvidence
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'evidence storage on G: is rejected'
Assert-Icacl (-not (Invoke-PreflightOverride 'ActualScriptSha256' ('0'*64)).Pass) 'source pin mismatch fails before UAC'
$badBaseline=$baseline.PSObject.Copy();$badBaseline.PSObject.Properties.Remove('Manifest')
Assert-Icacl (-not (Invoke-PreflightOverride 'Baseline' $badBaseline).Pass) 'missing baseline fields return a closed preflight failure rather than throwing'
$badBaseline=$baseline.PSObject.Copy();$badRecords=@($baseline.Records);$badRecord=$badRecords[0].PSObject.Copy();$badRecord.Path=Join-Path (Split-Path -Parent $badRecord.Path) ('.\'+(Split-Path -Leaf $badRecord.Path));$badRecords[0]=$badRecord;$badBaseline.Records=$badRecords
Assert-Icacl (-not (Invoke-PreflightOverride 'Baseline' $badBaseline).Pass) 'non-canonical path spelling is rejected as an alias even when it resolves to an approved object'

$pinRoot=Join-Path $env:TEMP ('F2 Icacls Pin Fixture '+[guid]::NewGuid().ToString('N'));$pinAcl=Join-Path $pinRoot 'scripts\f2-acl';[void][IO.Directory]::CreateDirectory($pinAcl)
try{
    $moduleFixture=Join-Path $pinAcl 'F2AclIcacls.Corroboration.psm1';$captureFixture=Join-Path $pinAcl 'Invoke-F2AclReadOnlyCapture.ps1';$protocolFixture=Join-Path $pinAcl 'F2AclCapture.Protocol.psm1'
    [IO.File]::WriteAllText($moduleFixture,'module fixture');[IO.File]::WriteAllText($captureFixture,'capture fixture');[IO.File]::WriteAllText($protocolFixture,'protocol fixture')
    $fixturePins=[pscustomobject]@{Schema='f2-icacls-corroboration-pins-v1';ReviewedCollectorBaseSha='a62773f0553dff4a05055b18fa10834f7488ae55';CorroborationModuleSha256=(Get-F2IcaclsFileSha256 $moduleFixture);CollectorScriptSha256=(Get-F2IcaclsFileSha256 $captureFixture);ProtocolModuleSha256=(Get-F2IcaclsFileSha256 $protocolFixture)}
    $pinBytes=[Text.UTF8Encoding]::new($false).GetBytes(($fixturePins|ConvertTo-Json -Depth 4));[IO.File]::WriteAllBytes((Join-Path $pinAcl 'F2_ICACLS_SOURCE_PINS.json'),$pinBytes)
    $fixtureIntegrity=[pscustomobject]@{CollectorScriptSha256=$fixturePins.CollectorScriptSha256;ProtocolModuleSha256=$fixturePins.ProtocolModuleSha256}
    $pinDigest=Get-F2IcaclsSha256 -Bytes $pinBytes
    $pinCheck=Test-F2IcaclsSourcePins -RepositoryRoot $pinRoot -Integrity $fixtureIntegrity -ExpectedPinManifestSha256 $pinDigest -ExpectedCommitSha ('d'*40) -ActualCommitSha ('d'*40)
    Assert-Icacl $pinCheck.Pass 'source pin verifier reads the pin manifest and hashes spaced file paths with correct PowerShell 5.1 parameter binding'
    [IO.File]::WriteAllText($moduleFixture,'modified module fixture')
    Assert-Icacl (-not (Test-F2IcaclsSourcePins -RepositoryRoot $pinRoot -Integrity $fixtureIntegrity -ExpectedPinManifestSha256 $pinDigest -ExpectedCommitSha ('d'*40) -ActualCommitSha ('d'*40)).Pass) 'source pin verifier rejects modified helper source'
    Assert-Icacl (-not (Test-F2IcaclsSourcePins -RepositoryRoot $pinRoot -Integrity $fixtureIntegrity -ExpectedPinManifestSha256 $pinDigest -ExpectedCommitSha ('d'*40) -ActualCommitSha ('e'*40)).Pass) 'source pin verifier rejects a commit mismatch'
}finally{if(Test-Path $pinRoot){Remove-Item -LiteralPath $pinRoot -Recurse -Force}}

$goodText=@($paths[0],'S-1-5-32-544:(F)') -join "`r`n"
$spec=Get-F2IcaclsCommandSpec -Target $paths[0] -ProjectRoot $projectRoot
Assert-Icacl ($spec.FilePath -eq (Join-Path $env:SystemRoot 'System32\icacls.exe') -and $spec.Arguments -ceq ('"'+$paths[0]+'"') -and $spec.Switches.Count -eq 0) 'production command spec pins system icacls and uses one quoted allowlisted path without switches'
$specRejected=$false;try{Get-F2IcaclsCommandSpec -Target 'C:\F2Synthetic\outside.txt' -ProjectRoot $projectRoot|Out-Null}catch{$specRejected=$true}
Assert-Icacl $specRejected 'command spec rejects non-allowlisted paths before process creation'
$parsed=ConvertFrom-F2IcaclsText -Text $goodText -ExpectedPath $paths[0]
Assert-Icacl ($parsed.PathMatched -and $parsed.Aces.Count -eq 1 -and $parsed.Aces[0].Mask -eq [uint32]0x001F01FF) 'synthetic icacls full-control text parses to exact mask'
$goodComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 0 $goodText)
Assert-Icacl ($goodComparison.Classification -eq 'PASS') 'matching synthetic object is classified PASS'
$wrongText=@($paths[0],'S-1-5-32-544:(R)') -join "`r`n"
$wrongComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 0 $wrongText)
Assert-Icacl ($wrongComparison.Classification -eq 'MISMATCH') 'fully parsed different rights classify MISMATCH'
$unknownText=@($paths[0],'S-1-5-32-544:(QZ)') -join "`r`n"
$unknownComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 0 $unknownText)
Assert-Icacl ($unknownComparison.Classification -eq 'INDETERMINATE') 'unsupported icacls rights are INDETERMINATE'
$failedComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 5 '' 'Access is denied.')
Assert-Icacl ($failedComparison.Classification -eq 'INDETERMINATE') 'failed native invocation cannot classify an ACL'

$calls=0;$elevationCalls=0
$runner={param($target)$script:calls++;New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}
$coordinator={param($failedPaths)$script:elevationCalls++;[pscustomobject]@{Complete=$true;Runs=@()}}
$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl ($plan.Complete -and $plan.Runs.Count -eq 11 -and $plan.ElevationLaunches -eq 0 -and $script:calls -eq 11) 'end-to-end all-11 standard success makes zero coordinator launches'
$beforeCalls=$script:calls;$scopeTargets=@($paths[0..9]);$scopeTargets+=@('C:\F2Synthetic\outside.txt');$scopePlan=Invoke-F2IcaclsPlan -Targets $scopeTargets -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $scopePlan.Complete -and $scopePlan.ElevationLaunches -eq 0 -and $script:calls -eq $beforeCalls) 'out-of-scope target set fails before standard child or coordinator launch'

$accessDeniedTarget=$paths[3];$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$coordinator={param($failedPaths)$script:elevationCalls++;$runs=@();foreach($target in $failedPaths){$runs+=@([pscustomobject]@{Path=$target;Result=(New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n"))})};[pscustomobject]@{Complete=$true;Runs=$runs}}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl ($plan.Complete -and $plan.ElevationLaunches -eq 1 -and $script:elevationCalls -eq ($before+1)) 'access-denied-only set triggers exactly one coordinator launch'
$elevatedRuns=@($plan.Runs|Where-Object{$_.Mode -eq 'Elevated'})
Assert-Icacl ($elevatedRuns.Count -eq 1 -and $elevatedRuns[0].Path -ceq $accessDeniedTarget) 'coordinator retries only the denied target'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 1 '' 'synthetic generic failure'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 0 -and $script:elevationCalls -eq $before) 'non-access-denied failure never launches UAC'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.' -Timeout $true -Complete $false -Cleanup $false}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 0 -and $script:elevationCalls -eq $before) 'timeout or incomplete stream prevents UAC retry and completion'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$coordinator={param($failedPaths)$script:elevationCalls++;[pscustomobject]@{Complete=$false;Runs=@()}}
$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 1 -and $plan.Outcome -eq 'INDETERMINATE') 'missing elevated evidence fails closed'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$coordinator={param($failedPaths)$script:elevationCalls++;throw 'synthetic coordinator startup failure'}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 1 -and $plan.Outcome -eq 'INDETERMINATE' -and $script:elevationCalls -eq ($before+1)) 'coordinator exception is bounded, reported and never retried'

$psExe=Join-Path $PSHOME 'powershell.exe'
$okArgs='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''fixture-stdout'');[Console]::Error.WriteLine(''fixture-stderr'');exit 0"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $okArgs -TimeoutSeconds 5
Assert-Icacl ($proc.Started -and $proc.ExitCode -eq 0 -and $proc.OutputComplete -and $proc.CleanupComplete -and $proc.Stdout -match 'fixture-stdout' -and $proc.Stderr -match 'fixture-stderr' -and $proc.StdoutSha256 -match '^[0-9a-f]{64}$' -and $proc.StderrSha256 -match '^[0-9a-f]{64}$') 'bounded process runner captures stdout, stderr, PID, exit and hashes'
$quietArgs='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''quiet-stdout'');exit 0"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $quietArgs -TimeoutSeconds 5
Assert-Icacl ($proc.ExitCode -eq 0 -and $proc.OutputComplete -and $proc.StderrBytes -eq 0 -and $proc.StderrSha256 -match '^[0-9a-f]{64}$') 'successful command with empty stderr receives the SHA-256 of the empty byte stream'
$failArgs='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''fixture-fail-out'');[Console]::Error.WriteLine(''fixture-fail-err'');exit 23"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $failArgs -TimeoutSeconds 5
Assert-Icacl ($proc.ExitCode -eq 23 -and $proc.OutputComplete -and $proc.Stdout -match 'fixture-fail-out' -and $proc.Stderr -match 'fixture-fail-err') 'nonzero child exit retains complete separate streams'
$hangArgs='-NoProfile -NonInteractive -Command "while($true){[Console]::Out.WriteLine(''tick'');Start-Sleep -Milliseconds 25}"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $hangArgs -TimeoutSeconds 1 -CleanupGraceMilliseconds 500 -DrainGraceMilliseconds 250
Assert-Icacl ($proc.TimedOut -and -not $proc.OutputComplete -and $proc.ElapsedMilliseconds -lt 5000) 'hanging child returns bounded timeout with incomplete status'
$largeArgs='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''x'' * 20000);exit 0"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $largeArgs -TimeoutSeconds 5 -MaxBytesPerStream 1024
Assert-Icacl ($proc.Truncated -and -not $proc.OutputComplete -and $proc.Stdout.Length -le 1024 -and $proc.StdoutBytes -gt 1024 -and $proc.ExitCode -eq 0) 'oversized output is drained with bounded retention and cannot be complete'
$leftoverEvents=@(Get-EventSubscriber|Where-Object{$_.SourceIdentifier -like 'F2IcaclsOut-*' -or $_.SourceIdentifier -like 'F2IcaclsErr-*'})
Assert-Icacl ($leftoverEvents.Count -eq 0) 'process runner removes its event subscriptions after success, failure and timeout'

$tempRoot=Join-Path $env:TEMP ('F2Icacls-Synthetic-'+[guid]::NewGuid().ToString('N'));$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
try{
    $testDir=Join-Path $tempRoot 'evidence';[void][IO.Directory]::CreateDirectory($tempRoot)
    $testEvidenceGuid=[F2Acl.NativeDirectory]::GetVolumeGuidForPath($tempRoot)
    $testProjectPath=$null
    foreach($driveInfo in [IO.DriveInfo]::GetDrives()){if(-not $driveInfo.IsReady){continue};try{$candidate=[F2Acl.NativeDirectory]::GetVolumeGuidForPath($driveInfo.RootDirectory.FullName);if($candidate -cne $testEvidenceGuid){$testProjectPath=$driveInfo.RootDirectory.FullName;break}}catch{}}
    if([string]::IsNullOrWhiteSpace($testProjectPath)){throw 'Synthetic evidence publication requires a second local volume; no project data is read or written.'}
    $testProjectGuid=[F2Acl.NativeDirectory]::GetVolumeGuidForPath($testProjectPath)
    $module=Get-Module F2AclIcacls.Corroboration
    $resolver={param($path)if([string]::Equals([IO.Path]::GetPathRoot($path),[IO.Path]::GetPathRoot($testProjectPath),[StringComparison]::OrdinalIgnoreCase)){$testProjectGuid}else{$testEvidenceGuid}}
    $module.SessionState.PSVariable.Set('F2IcaclsVolumeResolver',$resolver)
    $safeDir=New-F2AclRestrictedDirectory -Path $testDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $acl=Test-F2AclRestrictedDirectory -Path $safeDir -OwnerSid $owner
    $inputDir=Join-Path $tempRoot 'baseline-input';$inputSafe=New-F2AclRestrictedDirectory -Path $inputDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $payloadBytes=[Text.UTF8Encoding]::new($false).GetBytes(($baseline|ConvertTo-Json -Depth 14))
    [IO.File]::WriteAllBytes((Join-Path $inputSafe 'acl-baseline.json'),$payloadBytes)
    $inputIntegrity=[pscustomobject]@{Schema='f2-acl-integrity-v1';PayloadFile='acl-baseline.json';PayloadBytes=$payloadBytes.Length;PayloadSha256=(Get-F2IcaclsSha256 -Bytes $payloadBytes);ProjectVolumeGuid=$projectVolume;EvidenceVolumeGuid=$evidenceVolume;SeparateFromProjectVolume=$true}
    [IO.File]::WriteAllText((Join-Path $inputSafe 'integrity.json'),($inputIntegrity|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    $loaded=Read-F2IcaclsBaselineEvidence -EvidenceDirectory $inputSafe -ExpectedCaptureId $baseline.CaptureId -ExpectedOwnerSid $owner
    Assert-Icacl ($loaded.Pass -and $loaded.Integrity.ProjectVolumeGuid -eq $projectVolume -and $loaded.Integrity.ProjectVolumeGuid -ne $loaded.Baseline.Manifest.ProjectVolumeGuid -and $loaded.Integrity.EvidenceVolumeGuid -eq $evidenceVolume) 'baseline loader sources ProjectVolumeGuid from integrity.json and keeps EvidenceVolumeGuid separate'
    [IO.File]::WriteAllText((Join-Path $inputSafe 'acl-baseline.json'),'tampered payload',[Text.UTF8Encoding]::new($false))
    Assert-Icacl (-not (Read-F2IcaclsBaselineEvidence -EvidenceDirectory $inputSafe -ExpectedCaptureId $baseline.CaptureId -ExpectedOwnerSid $owner).Pass) 'baseline payload tampering fails its integrity.json digest'
    $runs=@();$comparisons=@();foreach($path in $paths){$txt=@($path,'S-1-5-32-544:(F)') -join "`r`n";$r=New-CommandResult $path 0 $txt;$runs+=@([pscustomobject]@{Path=$path;Result=$r;Mode='Synthetic'});$comparisons+=@([pscustomobject]@{Path=$path;Classification='PASS';Reason='SyntheticFixture'})}
    $package=Write-F2IcaclsEvidencePackage -Directory $safeDir -OwnerSid $owner -Targets $paths -Runs $runs -Comparisons $comparisons -ProjectVolumePath $testProjectPath -ProjectVolumeGuid $testProjectGuid -EvidenceVolumeGuid $testEvidenceGuid
    Assert-Icacl ($package.Complete -and $package.TargetCount -eq 11 -and $package.RunCount -eq 11 -and (Test-Path (Join-Path $safeDir 'integrity.json'))) '11-object synthetic evidence package is atomically create-new in protected directory'
    $integrityDoc=Get-Content -Raw (Join-Path $safeDir 'integrity.json')|ConvertFrom-Json
    $verified=$true;foreach($row in $integrityDoc.Results){$file=Join-Path $safeDir $row.Name;$verified=$verified -and (Get-Item $file).Length -eq $row.Bytes -and (Get-F2IcaclsSha256 -Bytes ([IO.File]::ReadAllBytes($file))) -eq $row.Sha256}
    Assert-Icacl $verified 'synthetic evidence file hashes and byte counts verify'
    Assert-Icacl (Test-F2AclRestrictedDirectory -Path $safeDir -OwnerSid $owner).Protected 'evidence DACL remains protected after publication'
    $retryRuns=@($runs);$retryRuns+=@([pscustomobject]@{Path=$paths[0];Result=(New-CommandResult $paths[0] 5 '' 'Access is denied.');Mode='Standard'})
    $retryDir=Join-Path $tempRoot 'retry-evidence';$retrySafe=New-F2AclRestrictedDirectory -Path $retryDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $retryPackage=Write-F2IcaclsEvidencePackage -Directory $retrySafe -OwnerSid $owner -Targets $paths -Runs $retryRuns -Comparisons $comparisons -ProjectVolumePath $testProjectPath -ProjectVolumeGuid $testProjectGuid -EvidenceVolumeGuid $testEvidenceGuid
    $retryManifest=Get-Content -Raw (Join-Path $retrySafe 'integrity.json')|ConvertFrom-Json
    Assert-Icacl ($retryPackage.Complete -and $retryManifest.RunCount -eq 12 -and -not $retryManifest.AllCommandsSuccessful -and $retryManifest.AllComparisonsPass) 'evidence completeness allows a standard denial plus one elevated retry without hiding the failed attempt'
    $badRuns=@($runs);$badRuns[0]=$badRuns[0].PSObject.Copy();$badRuns[0].Result=New-CommandResult $paths[0] 5 '' 'Access is denied.'
    $badComparisons=@($comparisons);$badComparisons[0]=[pscustomobject]@{Path=$paths[0];Classification='INDETERMINATE';Reason='AccessDenied'}
    $failedDir=Join-Path $tempRoot 'failed-evidence';$failedSafe=New-F2AclRestrictedDirectory -Path $failedDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $failedPackage=Write-F2IcaclsEvidencePackage -Directory $failedSafe -OwnerSid $owner -Targets $paths -Runs $badRuns -Comparisons $badComparisons -ProjectVolumePath $testProjectPath -ProjectVolumeGuid $testProjectGuid -EvidenceVolumeGuid $testEvidenceGuid
    $failedRecord=Get-Content -Raw (Join-Path $failedSafe 'icacls-01.json')|ConvertFrom-Json
    $failedManifest=Get-Content -Raw (Join-Path $failedSafe 'integrity.json')|ConvertFrom-Json
    Assert-Icacl ($failedPackage.Complete -and -not $failedManifest.AllCommandsSuccessful -and -not $failedManifest.AllComparisonsPass -and $failedRecord.Result.ExitCode -eq 5 -and $failedRecord.Result.Stderr -eq 'Access is denied.') 'failing icacls output and exit status are published as complete diagnostic evidence, never a pass'
}finally{if(Test-Path $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}}

Write-Host ("Assertions={0}; Failures={1}" -f $testCount,$failures.Count)
if($failures.Count -gt 0){$failures|ForEach-Object{Write-Error $_};exit 1}
exit 0

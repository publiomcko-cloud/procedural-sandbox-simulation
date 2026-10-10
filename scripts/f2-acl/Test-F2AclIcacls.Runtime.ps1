[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:assertions=0;$script:failures=New-Object 'System.Collections.Generic.List[string]'
function Assert-Runtime([bool]$Condition,[string]$Message){$script:assertions++;if(-not $Condition){$script:failures.Add($Message);Write-Host ('FAIL: '+$Message)}else{Write-Host ('PASS: '+$Message)}}

$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot=[IO.Path]::GetFullPath((Join-Path $scriptDir '..\..'))
Import-Module (Join-Path $scriptDir 'F2AclIcacls.Runtime.psm1') -Force
Import-Module (Join-Path $scriptDir 'F2AclIcacls.Corroboration.psm1') -Force
Import-Module (Join-Path $scriptDir 'F2AclCapture.Protocol.psm1') -Force
$runtimeModule=Get-Module F2AclIcacls.Runtime
$script:runtimeModule=$runtimeModule
$script:helperModule=@($runtimeModule.NestedModules|Where-Object{$_.Name -eq 'F2AclIcacls.Corroboration'})[0]
function Set-RuntimeState([string]$Name,$Value){$script:runtimeModule.SessionState.PSVariable.Set($Name,$Value)}
function Invoke-RuntimePrivate([string]$Name,[object[]]$Arguments=@()) {
    $script:runtimeModule.SessionState.PSVariable.Set('__F2TestFunction',$Name)
    $script:runtimeModule.SessionState.PSVariable.Set('__F2TestArguments',$Arguments)
    $call=[scriptblock]::Create('& $script:__F2TestFunction @script:__F2TestArguments')
    return @($script:runtimeModule.Invoke($call,@()))[0]
}

$capture='0123456789abcdef0123456789abcdef'
$requester='S-1-5-21-111111111-222222222-333333333-1001'
$coordinator='S-1-5-21-111111111-222222222-333333333-500'
$projectGuid='\\?\Volume{11111111-1111-1111-1111-111111111111}\'
$evidenceGuid='\\?\Volume{22222222-2222-2222-2222-222222222222}\'
$script:paths=@(Get-F2IcaclsExpectedPaths)
$script:payloadSha='a'*64;$script:integritySha='b'*64
$script:records=@(foreach($path in $script:paths){[pscustomobject]@{Path=$path;Status='PASS';Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type='Allow';AccessMask='0x001F01FF';InheritanceFlags='None';PropagationFlags='None';Inherited=$false})}})
$script:baseline=[pscustomobject]@{Complete=$true;CaptureId='ecb6deeb424e40feb5354d18908986df';VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable';VmState='Off';Manifest=[pscustomobject]@{ExpectedCount=11;ExpectedPaths=$script:paths;RecordCount=11;UniquePathCount=11};Records=$script:records}
$script:baselineIntegrity=[pscustomobject]@{PayloadSha256=$script:payloadSha;ProjectVolumeGuid=$projectGuid;EvidenceVolumeGuid=$evidenceGuid;CollectorScriptSha256='c'*64;ProtocolModuleSha256='d'*64}
$script:storage=[pscustomobject]@{Win32MatchCount=1;DiskMatchCount=1;PhysicalMatchCount=1;Win32Serial='152D20337A0C';DiskSerial='152D20337A0C';PhysicalSerial='152D20337A0C';Win32Model='KINGSTON  SA400S37240G USB Device';DiskFriendlyName='KINGSTON SA400S37240G';DiskModel=' SA400S37240G   ';BusType='USB';DiskHealth='Healthy';PhysicalHealth='Healthy';DiskOperationalStatus=@('Online');GPartitionCount=1;PartitionDiskNumber=2;DiskNumber=2;Win32Index=2;GDriveLetter='G:';VolumeFileSystem='NTFS';VolumeHealth='Healthy';GVolumeGuid=$projectGuid}
$script:mailboxRoot=Join-Path $env:TEMP ('F2 Runtime Evidence '+[guid]::NewGuid().ToString('N'))
$script:packageRoot=Join-Path $env:TEMP ('F2 Runtime Package '+[guid]::NewGuid().ToString('N'))
$script:state=[pscustomobject]@{WorkerCalls=0;UacCalls=0;ObservationCalls=0}
[void][IO.Directory]::CreateDirectory($script:mailboxRoot)
$packageAcl=Join-Path $script:packageRoot 'scripts\f2-acl';[void][IO.Directory]::CreateDirectory($packageAcl)
$releaseNames=@('F2AclCapture.Protocol.psm1','F2AclIcacls.Corroboration.psm1','F2AclIcacls.Runtime.psm1','Invoke-F2IcaclsCapture.ps1','Invoke-F2IcaclsProtectedCoordinator.ps1','F2_ICACLS_SOURCE_PINS.json','Invoke-F2AclReadOnlyCapture.ps1')
foreach($name in $releaseNames){Copy-Item -LiteralPath (Join-Path $scriptDir $name) -Destination (Join-Path $packageAcl $name) -Force}
$filePins=@(foreach($name in $releaseNames){[pscustomobject]@{Name=$name;Sha256=(Get-F2IcaclsFileSha256 -Path (Join-Path $packageAcl $name))}})
$pinsPath=Join-Path $scriptDir 'F2_ICACLS_SOURCE_PINS.json'
$script:manifest=[pscustomobject]@{Schema='f2-icacls-runtime-release-v1';ReviewedCommitSha=('a'*40);BaselineCaptureId='ecb6deeb424e40feb5354d18908986df';BaselinePayloadSha256=$script:payloadSha;BaselineIntegritySha256=$script:integritySha;SourcePinsManifestSha256=(Get-F2IcaclsFileSha256 -Path $pinsPath);Files=$filePins}
$mailboxSddl=Get-F2AclCoordinatorMailboxSddl -RequesterSid $requester
$module=$script:helperModule
$mailboxRootValue=$script:mailboxRoot;$projectGuidValue=$projectGuid;$evidenceGuidValue=$evidenceGuid;$mailboxSddlValue=$mailboxSddl
$module.SessionState.PSVariable.Set('F2IcaclsMailboxPathResolver',{param($id)Join-Path $mailboxRootValue ([string]$id)}.GetNewClosure())
$module.SessionState.PSVariable.Set('F2IcaclsMailboxDescriptorResolver',{param($path,$id)$mailboxSddlValue}.GetNewClosure())
$module.SessionState.PSVariable.Set('F2IcaclsVolumeResolver',{param($path)if($path -match '^[Gg]:\\'){$projectGuidValue}else{$evidenceGuidValue}}.GetNewClosure())
$script:currentMailbox=$null

$expectedPathsValue=$script:paths;$storageValue=$script:storage
$expectedDirectoriesValue=@($script:paths[0],$script:paths[1],$script:paths[2],$script:paths[3],$script:paths[9],$script:paths[10])
$runtimeState=$script:state
$observationProvider={
    param($evidencePath,$requesterSid,$captureId)
    $runtimeState.ObservationCalls++
    $pathChecks=@(foreach($path in $expectedPathsValue){[pscustomobject]@{Path=$path;Exists=$true;IsDirectory=($path -in $expectedDirectoriesValue);ReparsePoint=$false;ParentChainClear=$true}})
    return [pscustomobject]@{VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable';VmState='Off';NicCount=0;Storage=$storageValue;GVolumeGuid=$projectGuidValue;EvidenceVolumeGuid=$evidenceGuidValue;PathChecks=$pathChecks;EvidenceDirectory=[pscustomobject]@{Protected=$true;OwnerSid='S-1-5-32-544';NoUnexpectedPrincipals=$true;SeparateFromG=$true}}
}.GetNewClosure()
$runtimeState=$script:state
$worker={
    param($path,$timeout)
    $runtimeState.WorkerCalls++
    $text=$path+" S-1-5-32-544:(F)"
    return [pscustomobject]@{Started=$true;ProcessId=(2000+$runtimeState.WorkerCalls);ProcessStartUtc=[DateTime]::UtcNow.ToString('o');ExitCode=0;TimedOut=$false;CleanupComplete=$true;OutputComplete=$true;Truncated=$false;Stdout=$text;Stderr='';StdoutBytes=[Text.Encoding]::UTF8.GetByteCount($text);StderrBytes=0;StdoutSha256=(Get-F2IcaclsSha256 -Bytes ([Text.Encoding]::UTF8.GetBytes($text)));StderrSha256=(Get-F2IcaclsSha256 -Bytes ([byte[]]@()));ElapsedMilliseconds=1;ReaderError=$null;Path=$path;Command='icacls.exe "<approved-path>"'}
}.GetNewClosure()
$requestProvider={param($id,$sid)[pscustomobject]@{Path='synthetic-request';Sha256=('e'*64)}}
$requesterValue=$requester
$requestReader={param($id)[pscustomobject]@{CaptureId=$id;RequesterSid=$requesterValue;Path='synthetic-request';RequestSha256=('e'*64)}}.GetNewClosure()
$baselineValue=$script:baseline;$baselineIntegrityValue=$script:baselineIntegrity;$payloadShaValue=$script:payloadSha
$baselineProvider={param($m,$sid)[pscustomobject]@{Pass=$true;Baseline=$baselineValue;Integrity=$baselineIntegrityValue;PayloadSha256=$payloadShaValue}}.GetNewClosure()
$mailboxRootCapture=$script:mailboxRoot
$mailboxCreator={param($id,$sid)$path=Join-Path $mailboxRootCapture $id;[void][IO.Directory]::CreateDirectory($path);return $path}.GetNewClosure()

function Reset-RuntimeHooks {
    $manifestValue=$script:manifest;$packageRootValue=$script:packageRoot;$coordinatorValue=$coordinator;$captureValue=$capture
    Set-RuntimeState 'F2RuntimeReleaseProvider' {return $manifestValue}.GetNewClosure()
    Set-RuntimeState 'F2RuntimeObservationProvider' $observationProvider
    Set-RuntimeState 'F2RuntimeNativeWorker' $worker
    Set-RuntimeState 'F2RuntimeCurrentCommitProvider' {return ('a'*40)}
    Set-RuntimeState 'F2RuntimeRequestProvider' $requestProvider
    Set-RuntimeState 'F2RuntimeRequestReader' $requestReader
    Set-RuntimeState 'F2RuntimeBaselineProvider' $baselineProvider
    Set-RuntimeState 'F2RuntimeMailboxCreator' $mailboxCreator
    Set-RuntimeState 'F2RuntimePackageRootProvider' {return $packageRootValue}.GetNewClosure()
    Set-RuntimeState 'F2RuntimeTrustRootProvider' {return $true}
    Set-RuntimeState 'F2RuntimeIdentityProvider' {return [pscustomobject]@{UserSid=$coordinatorValue;IsAdministrator=$true}}.GetNewClosure()
    Set-RuntimeState 'F2RuntimeCoordinatorDeadlineSeconds' 300
    Set-RuntimeState 'F2RuntimeCaptureIdProvider' {return $captureValue}.GetNewClosure()
    $requesterValue=$requester
    Set-RuntimeState 'F2RuntimeRequesterSidProvider' {return $requesterValue}.GetNewClosure()
}

try {
    Reset-RuntimeHooks
    $tampered=$script:manifest.PSObject.Copy();$badFiles=@($tampered.Files);$badFiles[0]=$badFiles[0].PSObject.Copy();$badFiles[0].Sha256='0'*64;$tampered.Files=$badFiles
    $tamperingRejected=$false;try{[void](Invoke-RuntimePrivate 'Test-F2RuntimeReleasePackage' @($tampered,'Source'))}catch{$tamperingRejected=$true}
    Assert-Runtime $tamperingRejected 'source tampering is rejected before any coordinator launch'
    Reset-RuntimeHooks
    $tamperedManifest=$tampered;$state=$script:state
    Set-RuntimeState 'F2RuntimeReleaseProvider' {return $tamperedManifest}.GetNewClosure()
    $badUacStarter={param($id,$timeout)$state.UacCalls++;throw 'UacMustNotStart'}.GetNewClosure()
    Set-RuntimeState 'F2RuntimeUacStarter' $badUacStarter
    $tamperedLaunch=Invoke-RuntimePrivate 'Invoke-F2IcaclsCaptureLauncher' @()
    Assert-Runtime (-not $tamperedLaunch.Success -and $tamperedLaunch.ElevationLaunches -eq 0 -and $script:state.UacCalls -eq 0) 'tampered release package fails before UAC launch'
    Reset-RuntimeHooks
    $directoryMasks=@{'S-1-5-18'=[uint32]0x001F01FF;'S-1-5-32-544'=[uint32]0x001F01FF;'S-1-5-11'=[uint32]0x001200A9}
    $goodDirectorySddl='O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200A9;;;AU)'
    $goodManifestSddl='O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200A9;;;AU)'
    $inheritFlags=[int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
    Assert-Runtime ([bool](Invoke-RuntimePrivate 'Test-F2RuntimeTrustedDaclSddl' @($goodDirectorySddl,$directoryMasks,$inheritFlags))) 'protected package directory ACL fixture matches exact owner, principals, rights and inheritance'
    Assert-Runtime ([bool](Invoke-RuntimePrivate 'Test-F2RuntimeTrustedDaclSddl' @($goodManifestSddl,$directoryMasks,0))) 'external release manifest ACL fixture is admin-owned, protected and non-inheriting'
    foreach($unsafeSddl in @(
        'O:BAG:BAD:(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200A9;;;AU)',
        'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1301BF;;;AU)',
        'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200A9;;;AU)(A;OICI;FA;;;WD)',
        'O:SYG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200A9;;;AU)')){
        $rejected=$false;try{[void](Invoke-RuntimePrivate 'Test-F2RuntimeTrustedDaclSddl' @($unsafeSddl,$directoryMasks,$inheritFlags))}catch{$rejected=$true}
        Assert-Runtime $rejected 'unprotected, writable, unexpected-principal or unexpected-owner release ACL is rejected'
    }

    $scopeObs=& $observationProvider 'x' $requester $capture;$scopeObs.NicCount=1
    $scopeObservation=$scopeObs
    Set-RuntimeState 'F2RuntimeObservationProvider' {param($e,$r,$c)$scopeObservation}.GetNewClosure()
    $mailboxRootValue=$script:mailboxRoot;$runtimeState=$script:state
    Set-RuntimeState 'F2RuntimeMailboxCreator' {param($id,$sid)$path=Join-Path $mailboxRootValue $id;[void][IO.Directory]::CreateDirectory($path);$path}.GetNewClosure()
    Set-RuntimeState 'F2RuntimeNativeWorker' {param($p,$t)$runtimeState.WorkerCalls++;throw 'MustNotRun'}.GetNewClosure()
    $scopeResult=Invoke-RuntimePrivate 'Invoke-F2IcaclsProtectedCoordinator' @($capture)
    Assert-Runtime (-not $scopeResult.Success -and $scopeResult.Stage -eq 'Preflight' -and $script:state.WorkerCalls -eq 0) 'scope mismatch fails before the first ACL command'
    Remove-Item -LiteralPath (Join-Path $script:mailboxRoot $capture) -Recurse -Force -ErrorAction SilentlyContinue

    Reset-RuntimeHooks
    $badIdentityObservation=& $observationProvider 'x' $requester $capture
    $badIdentityStorage=$badIdentityObservation.Storage.PSObject.Copy();$badIdentityStorage.Win32Serial='NOT-THE-PINNED-SERIAL';$badIdentityObservation.Storage=$badIdentityStorage
    Set-RuntimeState 'F2RuntimeObservationProvider' {param($e,$r,$c)$badIdentityObservation}.GetNewClosure()
    $identityResult=Invoke-RuntimePrivate 'Invoke-F2IcaclsProtectedCoordinator' @($capture)
    Assert-Runtime (-not $identityResult.Success -and $identityResult.Stage -eq 'Preflight' -and $script:state.WorkerCalls -eq 0) 'storage identity mismatch fails before the first ACL command'
    Remove-Item -LiteralPath (Join-Path $script:mailboxRoot $capture) -Recurse -Force -ErrorAction SilentlyContinue

    Reset-RuntimeHooks
    Set-RuntimeState 'F2RuntimeIdentityProvider' {return [pscustomobject]@{UserSid=$coordinator;IsAdministrator=$false}}.GetNewClosure()
    $tokenResult=Invoke-RuntimePrivate 'Invoke-F2IcaclsProtectedCoordinator' @($capture)
    Assert-Runtime (-not $tokenResult.Success -and $tokenResult.Stage -eq 'PackageValidation' -and $script:state.WorkerCalls -eq 0) 'non-administrator coordinator identity is rejected before request or ACL reads'

    Reset-RuntimeHooks
    Set-RuntimeState 'F2RuntimeUacStarter' {param($id,$timeout)throw [System.ComponentModel.Win32Exception]::new(1223)}
    $cancelResult=Invoke-RuntimePrivate 'Invoke-F2IcaclsCaptureLauncher' @()
    Assert-Runtime (-not $cancelResult.Success -and $cancelResult.Outcome -eq 'UAC_CANCELLED' -and $cancelResult.ElevationLaunches -eq 1) 'UAC cancellation is reported and is not retried'

    Reset-RuntimeHooks
    $runtimeState=$script:state
    Set-RuntimeState 'F2RuntimeUacStarter' {
        param($id,$timeout)
        $runtimeState.UacCalls++
        return [pscustomobject]@{Id=4111;StartTime=[DateTime]::UtcNow;HasExited=$true;ExitCode=0}
    }.GetNewClosure()
    Set-RuntimeState 'F2RuntimeCoordinatorWaitProvider' {param($p,$t)[pscustomobject]@{Exited=$true;ExitCode=[int]$p.ExitCode;CleanupComplete=$true;ProcessQueryFailed=$false}}
    $coordinatorResult=Invoke-RuntimePrivate 'Invoke-F2IcaclsProtectedCoordinator' @($capture)
    Assert-Runtime ($coordinatorResult.Success -and $coordinatorResult.ExitCode -eq 0 -and $script:state.WorkerCalls -eq 11) 'coordinator preflight and eleven bounded reads publish a complete synthetic mailbox'
    $happy=Invoke-RuntimePrivate 'Invoke-F2IcaclsCaptureLauncher' @()
    Assert-Runtime ($happy.Success -and $happy.ActualCoordinatorExitCode -eq 0 -and $happy.ElevationLaunches -eq 1 -and $happy.Comparisons.Count -eq 11 -and @($happy.Comparisons|Where-Object{$_.Classification -ne 'PASS'}).Count -eq 0) 'one UAC launch coordinates the real production path for all 11 objects and verifies returned evidence'
    Assert-Runtime ($script:state.WorkerCalls -eq 11 -and $script:state.UacCalls -eq 1 -and $happy.ManifestSha256 -match '^[0-9a-f]{64}$') 'successful integration has exactly 11 workers, one launch and a verified integrity digest'

    Reset-RuntimeHooks
    Set-RuntimeState 'F2RuntimeCoordinatorWaitProvider' {param($p,$t)[pscustomobject]@{Exited=$false;ExitCode=$null;CleanupComplete=$false;ProcessQueryFailed=$false}}
    Set-RuntimeState 'F2RuntimeUacStarter' {param($id,$timeout)$runtimeState.UacCalls++;[pscustomobject]@{Id=4222;StartTime=[DateTime]::UtcNow;HasExited=$false;ExitCode=$null}}.GetNewClosure()
    $deadline=Invoke-RuntimePrivate 'Invoke-F2IcaclsCaptureLauncher' @()
    Assert-Runtime (-not $deadline.Success -and $deadline.Outcome -eq 'CoordinatorDeadlineExceeded' -and -not $deadline.CoordinatorCleanupComplete -and $deadline.ElevationLaunches -eq 1) 'coordinator timeout and failed cleanup return bounded incomplete status without relaunch'

    foreach($failureMode in @('IncompleteOutput','Timeout','CleanupFailure')){
        Reset-RuntimeHooks
        $runtimeState=$script:state
        Set-RuntimeState 'F2RuntimeNativeWorker' {
            param($path,$timeout)
            $runtimeState.WorkerCalls++
            $text=$path+' S-1-5-32-544:(F)'
            $r=[pscustomobject]@{Started=$true;ProcessId=5000;ProcessStartUtc=[DateTime]::UtcNow.ToString('o');ExitCode=0;TimedOut=$false;CleanupComplete=$true;OutputComplete=$true;Truncated=$false;Stdout=$text;Stderr='';StdoutBytes=$text.Length;StderrBytes=0;StdoutSha256=('f'*64);StderrSha256=('e'*64);ElapsedMilliseconds=1;ReaderError=$null;Path=$path;Command='icacls.exe "<approved-path>"'}
            if($failureMode -eq 'IncompleteOutput'){$r.OutputComplete=$false}
            if($failureMode -eq 'Timeout'){$r.TimedOut=$true}
            if($failureMode -eq 'CleanupFailure'){$r.CleanupComplete=$false}
            return $r
        }.GetNewClosure()
        $badId=[guid]::NewGuid().ToString('N')
        $badRun=Invoke-RuntimePrivate 'Invoke-F2IcaclsProtectedCoordinator' @($badId)
        Assert-Runtime (-not $badRun.Success -and $badRun.Outcome -eq 'INCOMPLETE' -and $badRun.CoordinatorExitCode -eq 1 -and $badRun.Stage -eq 'IcaclsReads') ("$failureMode prevents complete publication and returns exit 1")
    }

    $launcherAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptDir 'Invoke-F2IcaclsCapture.ps1'),[ref]$null,[ref]$null)
    Assert-Runtime ($launcherAst.ParamBlock.Parameters.Count -eq 0) 'production host launcher exposes no runtime override parameters'
    $coordinatorAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scriptDir 'Invoke-F2IcaclsProtectedCoordinator.ps1'),[ref]$null,[ref]$null)
    Assert-Runtime ($coordinatorAst.ParamBlock.Parameters.Count -eq 1 -and $coordinatorAst.ParamBlock.Parameters[0].Name.VariablePath.UserPath -eq 'CaptureId') 'protected coordinator accepts only the validated one-use capture identifier'
    $powershellExe=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
    $launcherPath=Join-Path $scriptDir 'Invoke-F2IcaclsCapture.ps1'
    $launcherProcess=Start-Process -FilePath $powershellExe -ArgumentList ('-NoProfile -File "'+$launcherPath+'" unexpected') -PassThru -Wait -NoNewWindow -RedirectStandardError (Join-Path $script:mailboxRoot 'launcher-arg-error.txt') -RedirectStandardOutput (Join-Path $script:mailboxRoot 'launcher-arg-output.txt')
    Assert-Runtime ($launcherProcess.ExitCode -ne 0) 'actual launcher script rejects unexpected runtime arguments before any host query or UAC'
    $coordinatorPath=Join-Path $scriptDir 'Invoke-F2IcaclsProtectedCoordinator.ps1'
    $coordinatorProcess=Start-Process -FilePath $powershellExe -ArgumentList ('-NoProfile -File "'+$coordinatorPath+'" '+$capture) -PassThru -Wait -NoNewWindow
    Assert-Runtime ($coordinatorProcess.ExitCode -eq 2) 'actual coordinator script rejects an uninstalled source path before loading or querying host state'
}
finally {
    foreach($name in @('F2RuntimeReleaseProvider','F2RuntimeObservationProvider','F2RuntimeNativeWorker','F2RuntimeUacStarter','F2RuntimeCurrentCommitProvider','F2RuntimeClockProvider','F2RuntimeRequestProvider','F2RuntimeRequestReader','F2RuntimeBaselineProvider','F2RuntimeMailboxCreator','F2RuntimeResultReader','F2RuntimePackageRootProvider','F2RuntimeTrustRootProvider','F2RuntimeIdentityProvider','F2RuntimeCoordinatorWaitProvider','F2RuntimeCaptureIdProvider','F2RuntimeRequesterSidProvider')){Set-RuntimeState $name $null}
    try{Remove-Item -LiteralPath $script:mailboxRoot -Recurse -Force -ErrorAction SilentlyContinue}catch{}
    try{Remove-Item -LiteralPath $script:packageRoot -Recurse -Force -ErrorAction SilentlyContinue}catch{}
}

Write-Host ("Assertions={0};Failures={1}" -f $script:assertions,$script:failures.Count)
if($script:failures.Count -gt 0){$script:failures|ForEach-Object{Write-Error $_};exit 1}

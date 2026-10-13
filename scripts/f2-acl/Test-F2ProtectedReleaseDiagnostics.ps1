[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
trap { Write-Host ('ERROR=' + $_.Exception.Message); Write-Host ('TRACE=' + $_.ScriptStackTrace); exit 1 }

function Assert-Diagnostic([bool]$Condition, [string]$Name) {
    $script:Assertions++
    if (-not $Condition) { $script:Failures.Add($Name); Write-Host ('FAIL: ' + $Name) }
    else { Write-Host ('PASS: ' + $Name) }
}

$launcherPath = Join-Path $PSScriptRoot 'Start-F2ProtectedReleaseUpdate.ps1'
$protocolPath = Join-Path $PSScriptRoot 'F2ProtectedRelease.Diagnostics.ps1'
$launcherText = [IO.File]::ReadAllText($launcherPath)
Assert-Diagnostic ($launcherText.Contains('Receive-F2UpdateDiagnosticRecord')) 'production launcher consumes a bounded child diagnostic record'
Assert-Diagnostic ([IO.File]::Exists($protocolPath)) 'shared diagnostic protocol is present for real cross-process testing'

if (-not [IO.File]::Exists($protocolPath)) {
    Write-Output ('Assertions=' + $script:Assertions + ';Failures=' + $script:Failures.Count)
    exit 1
}

. $launcherPath
$safeKnownCode = Get-F2UpdateLauncherSafeErrorCode -Code 'UPDATE_SOURCE_COMMIT_MISMATCH'
$safeSidCode = Get-F2UpdateLauncherSafeErrorCode -Code 'S-1-5-21-111-222-333-1001'
$safeTokenLikeCode = Get-F2UpdateLauncherSafeErrorCode -Code 'UPDATE_PRIVATE_VALUE-123'
Assert-Diagnostic ($safeKnownCode -ceq 'UPDATE_SOURCE_COMMIT_MISMATCH') 'requester diagnostics preserve an exact approved stable error code'
Assert-Diagnostic ($safeSidCode -ceq 'UPDATE_UNCLASSIFIED_FAILURE' -and $safeTokenLikeCode -ceq 'UPDATE_UNCLASSIFIED_FAILURE') 'requester diagnostics reject raw SID and arbitrary token-like exception text'
$protocolBytes = [IO.File]::ReadAllBytes($protocolPath)
$protocolHash = Get-F2UpdateLauncherSha256 -Bytes $protocolBytes
$expectedProtocolHash = [regex]::Match($launcherText, "F2UpdateDiagnosticProtocolSha256\s*=\s*'([0-9a-f]{64})'").Groups[1].Value
Assert-Diagnostic ($protocolHash -ceq $expectedProtocolHash) 'launcher pins exact diagnostic protocol bytes'
. ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($protocolBytes)))
$updaterSourcePath=Join-Path $PSScriptRoot 'Invoke-F2ProtectedReleaseUpdate.ps1'
$updaterSourceBytes=[IO.File]::ReadAllBytes($updaterSourcePath)
. ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($updaterSourceBytes)))
$prelockStageNames=@('CandidateManifestValidation','SourceGitValidation','SourcePackagePinValidation','ParentAclValidation','InstalledV2Validation','TransactionCollisionValidation')
Assert-Diagnostic (@($prelockStageNames | Where-Object { $_ -notin $script:F2UpdateDiagnosticStages }).Count -eq 0) 'pipe protocol allowlist includes all six fixed pre-lock diagnostic substages'
$stageContext=[pscustomobject]@{DiagnosticStage='UpdaterInvocation'}
$stageSetPass=$true
foreach($fixedStage in $prelockStageNames){try{[void](Set-F2UpdateDiagnosticStage -Context $stageContext -Stage $fixedStage);if($stageContext.DiagnosticStage -cne $fixedStage){$stageSetPass=$false}}catch{$stageSetPass=$false}}
Assert-Diagnostic $stageSetPass 'production updater accepts and stores every fixed pre-lock stage label'
$unlistedStageRejected=$false
try{Set-F2UpdateDiagnosticStage -Context $stageContext -Stage 'C:\private\path' | Out-Null}catch{$unlistedStageRejected=$true}
Assert-Diagnostic ($unlistedStageRejected -and (Normalize-F2UpdateDiagnosticStage -Stage 'C:\private\path') -ceq 'UpdaterInvocation') 'unlisted stage labels are rejected at the updater boundary and normalized to a fixed non-sensitive fallback'
function Add-Type { throw 'SYNTHETIC_NATIVE_COMPILER_FAILURE' }
$nativeCompileCode=$null
try { New-F2UpdateNativeSupport } catch { $nativeCompileCode=[string]$_.Exception.Message }
Remove-Item Function:\Add-Type -ErrorAction SilentlyContinue
Assert-Diagnostic ($nativeCompileCode -ceq 'UPDATE_NATIVE_HELPER_COMPILE_FAILED') 'actual updater native-helper wrapper converts a synthetic compiler failure to its stable safe code'

$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sidHash = Get-F2UpdateDiagnosticSidHash -Sid $sid
$requester = [Diagnostics.Process]::GetCurrentProcess()
$request = New-F2UpdateDiagnosticRequest -SourceCommit ('a' * 40) -LauncherSha256 ('b' * 64) -UpdaterSha256 ('c' * 64) -CandidateManifestSha256 ('d' * 64) -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
Assert-Diagnostic ($request.RequestId -match '^[0-9a-f]{32}$' -and $request.Nonce -match '^[0-9a-f]{64}$') 'request uses fresh fixed-format identifiers'
Assert-Diagnostic ($request.RequesterSidSha256 -ceq $sidHash) 'request binds the requester by a digest without putting the SID in the record'
function Invoke-SyntheticBrokenDiagnosticServer {
    param($Request)
    function New-F2UpdateDiagnosticServer { throw 'S-1-5-21-111-222-333-1001' }
    New-F2UpdateLauncherDiagnosticServer -Request $Request
}
$wrappedServerError = $null
try { Invoke-SyntheticBrokenDiagnosticServer -Request $request | Out-Null } catch { $wrappedServerError = [string]$_.Exception.Message }
Assert-Diagnostic ($wrappedServerError -ceq 'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE') 'launcher maps diagnostic server initialization exceptions to a stable non-sensitive error code'

$channelFailureRequest=New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
$channelFailureServer=New-F2UpdateDiagnosticServer -Request $channelFailureRequest
$channelFailureServer.Dispose()
$channelChildStart=New-Object Diagnostics.ProcessStartInfo
$channelChildStart.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$channelChildStart.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 250; exit 7"'
$channelChildStart.UseShellExecute=$false;$channelChildStart.CreateNoWindow=$true
$channelChild=New-Object Diagnostics.Process;$channelChild.StartInfo=$channelChildStart
if(-not $channelChild.Start()){throw 'SYNTHETIC_CHANNEL_CHILD_START_FAILED'}
$channelChildTicks=$channelChild.StartTime.ToUniversalTime().Ticks
$channelFailureResult=Receive-F2UpdateDiagnosticRecord -Server $channelFailureServer -Request $channelFailureRequest -ChildProcess $channelChild -ChildCreationUtcTicks $channelChildTicks -TimeoutSeconds 5 -PostExitWaitMilliseconds 250 -RecordTimeoutMilliseconds 1000
Assert-Diagnostic ($channelFailureResult.DiagnosticStatus -ceq 'CHANNEL_FAILED' -and $channelFailureResult.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE' -and $channelFailureResult.ActualChildExitCode -eq 7 -and -not $channelFailureResult.TimedOut) 'diagnostic channel initialization failure remains bounded while retaining the real child exit'
$channelChild.Dispose();$channelFailureServer.Dispose()

function Invoke-SyntheticDiagnosticWorker {
    param($Request,[string]$Stage='UpdaterInvocation',[string]$Code='UPDATE_UNCLASSIFIED_FAILURE',[int]$ExitCode=1,[int]$RecordExitCode=-1,[switch]$Duplicate,[switch]$Tamper,[switch]$Oversize,[switch]$Stall,[switch]$WrongRequest,[switch]$UnknownStage,[Diagnostics.Process]$ExpectedChildProcess)
    $pipeName = $Request.PipeName
    $requestJson = $Request | ConvertTo-Json -Compress -Depth 4
    $requestB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($requestJson))
    $worker = @'
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$protocolBytes=[IO.File]::ReadAllBytes('__PROTOCOL_PATH__')
. ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($protocolBytes)))
$request=([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__REQUEST__'))|ConvertFrom-Json -ErrorAction Stop)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$process=[Diagnostics.Process]::GetCurrentProcess()
$stage='__STAGE__';$code='__CODE__';$exit=__EXIT__;$recordExit=__RECORD_EXIT__
if('__WRONG__' -eq '1'){$request.Nonce=('0'*64)}
if('__OVERSIZE__' -eq '1'){$frame=[byte[]](0xFF,0xFF,0xFF,0x7F);$client=New-Object IO.Pipes.NamedPipeClientStream('.', $request.PipeName, [IO.Pipes.PipeDirection]::Out);$client.Connect(3000);$client.Write($frame,0,$frame.Length);$client.Dispose()}
elseif('__TAMPER__' -eq '1' -or '__DUPLICATE__' -eq '1'){$record=New-F2UpdateDiagnosticRecord -Request $request -ChildPid $PID -ChildCreationUtcTicks $process.StartTime.ToUniversalTime().Ticks -ChildExitCode $recordExit -Stage $stage -ErrorCode $code;$frame=New-F2UpdateDiagnosticFrame -Record $record;if('__TAMPER__' -eq '1'){$frame[$frame.Length-1]=$frame[$frame.Length-1] -bxor 1};$client=New-Object IO.Pipes.NamedPipeClientStream('.', $request.PipeName, [IO.Pipes.PipeDirection]::Out);$client.Connect(3000);$client.Write($frame,0,$frame.Length);if('__DUPLICATE__' -eq '1'){$client.Write($frame,0,$frame.Length)};$client.Dispose()}
elseif('__STALL__' -eq '1'){$client=New-Object IO.Pipes.NamedPipeClientStream('.', $request.PipeName, [IO.Pipes.PipeDirection]::Out);$client.Connect(3000);$client.WriteByte(0);$client.Flush();Start-Sleep -Seconds 8;$client.Dispose()}
elseif('__UNKNOWN_STAGE__' -eq '1'){$record=New-F2UpdateDiagnosticRecord -Request $request -ChildPid $PID -ChildCreationUtcTicks $process.StartTime.ToUniversalTime().Ticks -ChildExitCode $recordExit -Stage $stage -ErrorCode $code;$record['Stage']='UNLISTED_DIAGNOSTIC_STAGE';$frame=New-F2UpdateDiagnosticFrame -Record $record;$client=New-Object IO.Pipes.NamedPipeClientStream('.', $request.PipeName, [IO.Pipes.PipeDirection]::Out);$client.Connect(3000);$client.Write($frame,0,$frame.Length);$client.Dispose()}
elseif('__NO_MESSAGE__' -ne '1'){$null=Send-F2UpdateDiagnosticRecord -Request $request -Stage $stage -ErrorCode $code -ChildExitCode $recordExit -ConnectTimeoutMilliseconds 3000}
exit $exit
'@
    $wrongFlag = if($WrongRequest.IsPresent){1}else{0}; $duplicateFlag = if($Duplicate.IsPresent){1}else{0}; $tamperFlag = if($Tamper.IsPresent){1}else{0}; $oversizeFlag = if($Oversize.IsPresent){1}else{0}; $stallFlag = if($Stall.IsPresent){1}else{0}; $unknownStageFlag = if($UnknownStage.IsPresent){1}else{0}
    $noMessage = [int]($Stage -eq 'NO_MESSAGE')
    if($RecordExitCode -eq -1){$RecordExitCode=$ExitCode}
    $worker = $worker.Replace('__PROTOCOL_PATH__',$protocolPath.Replace("'","''")).Replace('__REQUEST__',$requestB64).Replace('__STAGE__',$Stage).Replace('__CODE__',$Code).Replace('__EXIT__',[string]$ExitCode).Replace('__RECORD_EXIT__',[string]$RecordExitCode).Replace('__WRONG__',[string]$wrongFlag).Replace('__DUPLICATE__',[string]$duplicateFlag).Replace('__TAMPER__',[string]$tamperFlag).Replace('__OVERSIZE__',[string]$oversizeFlag).Replace('__STALL__',[string]$stallFlag).Replace('__UNKNOWN_STAGE__',[string]$unknownStageFlag).Replace('__NO_MESSAGE__',[string]$noMessage)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($worker))
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $start.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true; $start.RedirectStandardError = $true; $start.RedirectStandardOutput = $true
    $process = New-Object Diagnostics.Process; $process.StartInfo=$start
    if(-not $process.Start()){throw 'SYNTHETIC_WORKER_START_FAILED'}
    $ticks=$process.StartTime.ToUniversalTime().Ticks
    $expectedProcess=$process;$expectedTicks=$ticks
    if($null -ne $ExpectedChildProcess){$expectedProcess=$ExpectedChildProcess;$expectedTicks=$ExpectedChildProcess.StartTime.ToUniversalTime().Ticks}
    $result=Receive-F2UpdateDiagnosticRecord -Server $script:Server -Request $Request -ChildProcess $expectedProcess -ChildCreationUtcTicks $expectedTicks -TimeoutSeconds 10 -PostExitWaitMilliseconds 500 -RecordTimeoutMilliseconds 1500
    $workerStdout=$process.StandardOutput.ReadToEnd();$workerStderr=$process.StandardError.ReadToEnd()
    [pscustomobject]@{Result=$result;Process=$process;ExpectedProcess=$expectedProcess;ExpectedExit=$ExitCode;WorkerStdout=$workerStdout;WorkerStderr=$workerStderr}
}

function New-SyntheticUpdaterText {
    param([string]$Stage,[string]$Code,[switch]$IdentityFailure)
    if($IdentityFailure){return @'
function Test-F2UpdateElevationIdentity { param($ExpectedRequesterSid); throw 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH' }
function Get-F2UpdateManifestObject { param($Bytes,$ExpectedSchema,$ExpectedHash); return [pscustomobject]@{ReviewedCommitSha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'} }
function Invoke-F2ProtectedReleaseUpdate { return [pscustomobject]@{Success=$false;Stage='UpdaterInvocation';ErrorCode='UPDATE_UNCLASSIFIED_FAILURE';FailureType=''} }
'@}
    return @'
function Test-F2UpdateElevationIdentity { param($ExpectedRequesterSid) }
function Get-F2UpdateManifestObject { param($Bytes,$ExpectedSchema,$ExpectedHash); return [pscustomobject]@{ReviewedCommitSha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'} }
function Invoke-F2ProtectedReleaseUpdate { return [pscustomobject]@{Success=$false;Stage='__STAGE__';ErrorCode='__CODE__';FailureType=''} }
'@.Replace('__STAGE__',$Stage).Replace('__CODE__',$Code)
}

function Invoke-ProductionChildFixture {
    param($Request,[string]$TempRoot,[string]$ProtocolFile,[string]$UpdaterFile,[string]$CandidateFile,[string]$ExpectedUpdaterHash,[string]$ExpectedCandidateHash,[string]$ExpectedStage,[string]$ExpectedCode,[switch]$ExpectMissing)
    $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $Request
    $proc=[Diagnostics.Process]::GetCurrentProcess()
    $childScript=New-F2UpdateElevatedChildScript -UpdaterPath $UpdaterFile -CandidatePath $CandidateFile -SourceRoot $TempRoot -ExpectedSourceCommit ('a'*40) -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $ExpectedUpdaterHash -ExpectedCandidateManifestSha256 $ExpectedCandidateHash -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $proc.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $Request -DiagnosticProtocolPath $ProtocolFile -DiagnosticProtocolBytes $protocolBytes
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    if($encoded.Length -gt 32767){throw 'SYNTHETIC_CHILD_COMMAND_TOO_LARGE'}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardError=$true;$start.RedirectStandardOutput=$true
    $child=New-Object Diagnostics.Process;$child.StartInfo=$start
    if(-not $child.Start()){throw 'SYNTHETIC_PRODUCTION_CHILD_START_FAILED'}
    $ticks=$child.StartTime.ToUniversalTime().Ticks
    $result=Receive-F2UpdateDiagnosticRecord -Server $script:Server -Request $Request -ChildProcess $child -ChildCreationUtcTicks $ticks -TimeoutSeconds 10 -PostExitWaitMilliseconds 300 -RecordTimeoutMilliseconds 1500
    $null=$child.StandardOutput.ReadToEnd();$null=$child.StandardError.ReadToEnd()
    $passed=if($ExpectMissing){$result.DiagnosticStatus -ceq 'MISSING' -and $result.ActualChildExitCode -eq 1}else{$result.DiagnosticStatus -ceq 'VALIDATED' -and $result.ActualChildExitCode -eq 1 -and $result.Record.Stage -ceq $ExpectedStage -and $result.Record.ErrorCode -ceq $ExpectedCode}
    [pscustomobject]@{Passed=[bool]$passed;Result=$result;Process=$child;EncodedLength=$encoded.Length}
}

function New-PrelockSourceFixture {
    param([string]$Root)
    $sourceRoot=Join-Path $Root 'source-checkout'
    $sourceAcl=Join-Path $sourceRoot 'scripts\f2-acl'
    [void][IO.Directory]::CreateDirectory($sourceAcl)
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $names=@($script:F2UpdateOldPins.Keys)
    foreach($name in $names){Copy-Item -LiteralPath (Join-Path (Join-Path $repoRoot 'scripts\f2-acl') $name) -Destination (Join-Path $sourceAcl $name)}
    if([IO.File]::Exists((Join-Path $repoRoot '.gitattributes'))){Copy-Item -LiteralPath (Join-Path $repoRoot '.gitattributes') -Destination (Join-Path $sourceRoot '.gitattributes')}
    $git=Get-Command git.exe -ErrorAction Stop
    & $git.Source -C $sourceRoot init --quiet
    if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_SOURCE_GIT_INIT_FAILED'}
    & $git.Source -C $sourceRoot config core.autocrlf false
    & $git.Source -C $sourceRoot config user.name 'F2 Prelock Synthetic'
    & $git.Source -C $sourceRoot config user.email 'f2-prelock@example.invalid'
    & $git.Source -C $sourceRoot remote add origin 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
    & $git.Source -C $sourceRoot add -- .gitattributes scripts/f2-acl
    if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_SOURCE_GIT_ADD_FAILED'}
    & $git.Source -C $sourceRoot commit --quiet -m 'synthetic source validation fixture'
    if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_SOURCE_GIT_COMMIT_FAILED'}
    $commit=(& $git.Source -C $sourceRoot rev-parse HEAD 2>$null | Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$'){throw 'SYNTHETIC_SOURCE_GIT_HEAD_FAILED'}
    $sourcePins=@{}
    $pinBytes=$null
    foreach($name in $names){
        $bytes=[IO.File]::ReadAllBytes((Join-Path $sourceAcl $name))
        if($name -ceq 'F2_ICACLS_SOURCE_PINS.json'){$pinBytes=$bytes}
        $sourcePins[$name]=Get-F2UpdateDiagnosticSha256 -Bytes $bytes
    }
    return [pscustomobject]@{Root=$sourceRoot;AclRoot=$sourceAcl;Commit=$commit;Names=$names;SourcePins=$sourcePins;PinManifestSha256=(Get-F2UpdateDiagnosticSha256 -Bytes $pinBytes)}
}

function New-PrelockOldReleaseFixture {
    param([string]$Root)
    $repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $archivePath=Join-Path $Root 'old-v2-source.zip'
    $git=Get-Command git.exe -ErrorAction Stop
    & $git.Source -C $repoRoot archive --format=zip "--output=$archivePath" $script:F2UpdateOldCommit 'scripts/f2-acl'
    if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($archivePath)){throw 'SYNTHETIC_OLD_RELEASE_ARCHIVE_FAILED'}
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($archivePath)
    $files=@{}
    try{
        foreach($name in @($script:F2UpdateOldPins.Keys)){
            $entry=$zip.GetEntry(('scripts/f2-acl/'+$name))
            if($null -eq $entry -or $entry.Length -gt 4194304){throw 'SYNTHETIC_OLD_RELEASE_ENTRY_INVALID'}
            $input=$entry.Open();$memory=New-Object IO.MemoryStream
            try{$input.CopyTo($memory);$bytes=$memory.ToArray()}finally{$input.Dispose();$memory.Dispose()}
            if($name -ceq 'F2AclCapture.Protocol.psm1' -and (Get-F2UpdateDiagnosticSha256 -Bytes $bytes) -cne $script:F2UpdateOldPins[$name]){
                $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
                $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($text -replace "`r?`n","`r`n"))
            }
            if((Get-F2UpdateDiagnosticSha256 -Bytes $bytes) -cne $script:F2UpdateOldPins[$name]){throw 'SYNTHETIC_OLD_RELEASE_PIN_MISMATCH'}
            $files[$name]=$bytes
        }
    }finally{$zip.Dispose()}
    $manifest=[ordered]@{
        Schema='f2-icacls-runtime-release-v2'
        ReviewedCommitSha=$script:F2UpdateOldCommit
        BaselineMailboxId=$script:F2UpdateBaselineMailboxId
        BaselinePayloadCaptureId=$script:F2UpdateBaselineCaptureId
        BaselinePayloadSha256=$script:F2UpdateBaselinePayloadSha256
        BaselineIntegritySha256=$script:F2UpdateBaselineIntegritySha256
        SourcePinsManifestSha256=$script:F2UpdateOldPins['F2_ICACLS_SOURCE_PINS.json']
        Files=@(foreach($name in $script:F2UpdateOldPins.Keys){[pscustomobject]@{Name=$name;Sha256=$script:F2UpdateOldPins[$name]}})
    }
    $manifestBytes=[Text.UTF8Encoding]::new($false).GetBytes(($manifest|ConvertTo-Json -Compress -Depth 6))
    if((Get-F2UpdateDiagnosticSha256 -Bytes $manifestBytes) -cne $script:F2UpdateOldManifestSha256){throw 'SYNTHETIC_OLD_RELEASE_MANIFEST_PIN_MISMATCH'}
    return [pscustomobject]@{Files=$files;ManifestBytes=$manifestBytes}
}

function New-PrelockCandidateBytes {
    param($Source,[string]$PackageHome,[ValidateSet('Valid','WrongPackageRoot','WrongPackagePin','MalformedCandidate','MissingIdentity')][string]$Fault='Valid')
    if($Fault -eq 'MalformedCandidate'){return ,[Text.UTF8Encoding]::new($false).GetBytes('{invalid-json')}
    $files=@(foreach($name in $Source.Names){$sha=[string]$Source.SourcePins[$name];if($Fault -eq 'WrongPackagePin' -and $name -ceq $Source.Names[0]){$sha='0'*64};[pscustomobject]@{Name=$name;Sha256=$sha}})
    $packageRoot=Join-Path (Join-Path $PackageHome 'releases') $Source.Commit
    if($Fault -eq 'WrongPackageRoot'){$packageRoot=Join-Path ([IO.Path]::GetTempPath()) 'unrelated-release-root'}
    $candidate=[ordered]@{
        Schema='f2-icacls-runtime-release-v3'
        ReviewedCommitSha=$Source.Commit
        PackageRoot=$packageRoot
        BaselineMailboxId=$script:F2UpdateBaselineMailboxId
        BaselinePayloadCaptureId=$script:F2UpdateBaselineCaptureId
        BaselinePayloadSha256=$script:F2UpdateBaselinePayloadSha256
        BaselineIntegritySha256=$script:F2UpdateBaselineIntegritySha256
        SourcePinsManifestSha256=$Source.PinManifestSha256
        Files=$files
    }
    if($Fault -eq 'MissingIdentity'){$candidate.Remove('BaselineMailboxId')}
    return ,[Text.UTF8Encoding]::new($false).GetBytes(($candidate|ConvertTo-Json -Compress -Depth 6))
}

function New-PrelockInstallTree {
    param([string]$Root,$OldRelease)
    $fakeC=Join-Path $Root 'C'
    $packageHome=Join-Path (Join-Path $fakeC 'Program Files') 'F2-G1-Icacls'
    $oldAcl=Join-Path $packageHome 'scripts\f2-acl'
    $programDataRoot=Join-Path (Join-Path $fakeC 'ProgramData') 'F2-G1-Icacls'
    [void][IO.Directory]::CreateDirectory($oldAcl)
    [void][IO.Directory]::CreateDirectory($programDataRoot)
    foreach($name in $script:F2UpdateOldPins.Keys){[IO.File]::WriteAllBytes((Join-Path $oldAcl $name),[byte[]]$OldRelease.Files[$name])}
    $active=Join-Path $programDataRoot 'approved-release.json'
    [IO.File]::WriteAllBytes($active,[byte[]]$OldRelease.ManifestBytes)
    return [pscustomobject]@{PackageHome=$packageHome;ProgramDataRoot=$programDataRoot;ActiveManifestPath=$active}
}

function Invoke-PrelockProductionChildFixture {
    param([string]$UpdaterFile,[string]$CandidateFile,[string]$SourceRoot,[string]$SourceCommit,[string]$PackageHome,[string]$ProgramDataRoot,[string]$ActiveManifestPath,[bool]$ParentAclPass,[string]$ExpectedStage,[string]$ExpectedCode)
    $spec=[ordered]@{PackageHome=$PackageHome;ProgramDataRoot=$ProgramDataRoot;ActiveManifestPath=$ActiveManifestPath;ParentAclPass=$ParentAclPass}
    $specBytes=[Text.UTF8Encoding]::new($false).GetBytes(($spec|ConvertTo-Json -Compress -Depth 3))
    $specB64=[Convert]::ToBase64String($specBytes)
    $productionUpdater=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'Invoke-F2ProtectedReleaseUpdate.ps1'))
    $fixtureEntrypoint=@'
function Test-F2UpdateElevationIdentity { param($ExpectedRequesterSid) return $true }
function Invoke-F2ProtectedReleaseUpdate {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$CandidateManifestBytes,[Parameter(Mandatory)][string]$CandidateManifestSha256,[Parameter(Mandatory)][string]$ExpectedUpdaterSha256,[Parameter(Mandatory)][string]$ExpectedLauncherSha256,[Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][string]$ExpectedRequesterSid,[Parameter(Mandatory)][int]$RequesterLauncherProcessId,[Parameter(Mandatory)][long]$RequesterLauncherCreationUtcTicks)
    $spec=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CASE_SPEC_B64__'))|ConvertFrom-Json -ErrorAction Stop
    $parentPass=[bool]$spec.ParentAclPass
    $candidateManifest=Get-F2UpdateManifestObject -Bytes $CandidateManifestBytes -ExpectedSchema v3 -ExpectedHash $CandidateManifestSha256
    $hooks=[pscustomobject]@{
        AclCheck={param($path,$kind)return $true}
        ParentChainCheck={param($context)return $parentPass}.GetNewClosure()
    }
    $context=[pscustomobject]@{
        SourceRoot=[IO.Path]::GetFullPath($SourceRoot);ExpectedSourceCommit=[string]$candidateManifest.ReviewedCommitSha
        CandidateManifestBytes=$CandidateManifestBytes;CandidateManifestSha256=$CandidateManifestSha256;Manifest=$candidateManifest
        PackageHome=[string]$spec.PackageHome;ProgramDataRoot=[string]$spec.ProgramDataRoot;ActiveManifestPath=[string]$spec.ActiveManifestPath
        Hooks=$hooks;TransactionState=$null;DiagnosticStage='UpdaterInvocation'
    }
    return Invoke-F2UpdateTransaction -Context $context
}
'@.Replace('__CASE_SPEC_B64__',$specB64)
    $updaterText=[Text.UTF8Encoding]::new($false,$true).GetString($productionUpdater)+"`r`n"+$fixtureEntrypoint
    $updaterBytes=[Text.UTF8Encoding]::new($false).GetBytes($updaterText)
    [IO.File]::WriteAllBytes($UpdaterFile,$updaterBytes)
    $updaterHash=Get-F2UpdateDiagnosticSha256 -Bytes $updaterBytes
    $candidateBytes=[IO.File]::ReadAllBytes($CandidateFile)
    $candidateHash=Get-F2UpdateDiagnosticSha256 -Bytes $candidateBytes
    $requesterProcess=[Diagnostics.Process]::GetCurrentProcess()
    $request=New-F2UpdateDiagnosticRequest -SourceCommit $SourceCommit -LauncherSha256 ('b'*64) -UpdaterSha256 $updaterHash -CandidateManifestSha256 $candidateHash -RequesterPid $PID -RequesterCreationUtcTicks $requesterProcess.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $request
    $childScript=New-F2UpdateElevatedChildScript -UpdaterPath $UpdaterFile -CandidatePath $CandidateFile -SourceRoot $SourceRoot -ExpectedSourceCommit $SourceCommit -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $updaterHash -ExpectedCandidateManifestSha256 $candidateHash -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $requesterProcess.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $request -DiagnosticProtocolPath $protocolPath -DiagnosticProtocolBytes $protocolBytes
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    if($encoded.Length -gt 32767){throw 'SYNTHETIC_CHILD_COMMAND_TOO_LARGE'}
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $child=New-Object Diagnostics.Process;$child.StartInfo=$start
    if(-not $child.Start()){throw 'SYNTHETIC_PRELOCK_CHILD_START_FAILED'}
    $ticks=$child.StartTime.ToUniversalTime().Ticks
    $result=Receive-F2UpdateDiagnosticRecord -Server $script:Server -Request $request -ChildProcess $child -ChildCreationUtcTicks $ticks -TimeoutSeconds 25 -PostExitWaitMilliseconds 500 -RecordTimeoutMilliseconds 5000
    $stdout=$child.StandardOutput.ReadToEnd();$stderr=$child.StandardError.ReadToEnd()
    $passed=$result.DiagnosticStatus -ceq 'VALIDATED' -and $result.ActualChildExitCode -eq 1 -and $result.Record.Stage -ceq $ExpectedStage -and $result.Record.ErrorCode -ceq $ExpectedCode -and -not $result.TimedOut
    [pscustomobject]@{Passed=[bool]$passed;Request=$request;Result=$result;Process=$child;Stdout=$stdout;Stderr=$stderr;UpdaterSha256=$updaterHash;CandidateSha256=$candidateHash;EncodedLength=$encoded.Length}
}

function Invoke-F2ManifestValidationChildFixture {
    param([byte[]]$CandidateBytes,[string]$ExpectedSourceCommit,[string]$ExpectedStage,[string]$ExpectedCode)
    $fixtureId=[guid]::NewGuid().ToString('N')
    $updaterFile=Join-Path $syntheticRoot ('manifest-child-updater-'+$fixtureId+'.ps1')
    $candidateFile=Join-Path $syntheticRoot ('manifest-child-candidate-'+$fixtureId+'.json')
    $protocolFile=Join-Path $syntheticRoot ('manifest-child-protocol-'+$fixtureId+'.ps1')
    $productionUpdaterBytes=[IO.File]::ReadAllBytes($updaterSourcePath)
    $productionUpdaterText=[Text.UTF8Encoding]::new($false,$true).GetString($productionUpdaterBytes)
    $testOnlyEntrypoint=@'
function Test-F2UpdateElevationIdentity { param($ExpectedRequesterSid) return $true }
function Invoke-F2ProtectedReleaseUpdate {
    param($CandidateManifestBytes,$CandidateManifestSha256,$ExpectedUpdaterSha256,$ExpectedLauncherSha256,$SourceRoot,$ExpectedRequesterSid,$RequesterLauncherProcessId,$RequesterLauncherCreationUtcTicks)
    return [pscustomobject]@{Success=$false;Stage='SourceGitValidation';ErrorCode='UPDATE_SOURCE_GIT_UNAVAILABLE';FailureType=''}
}
'@
    $updaterFixtureBytes=[Text.UTF8Encoding]::new($false).GetBytes($productionUpdaterText+"`r`n"+$testOnlyEntrypoint)
    $candidateSha=Get-F2UpdateDiagnosticSha256 -Bytes $CandidateBytes
    [IO.File]::WriteAllBytes($updaterFile,$updaterFixtureBytes)
    [IO.File]::WriteAllBytes($candidateFile,$CandidateBytes)
    [IO.File]::WriteAllBytes($protocolFile,$protocolBytes)
    $updaterSha=Get-F2UpdateDiagnosticSha256 -Bytes $updaterFixtureBytes
    $requesterProcess=[Diagnostics.Process]::GetCurrentProcess()
    $childRequest=New-F2UpdateDiagnosticRequest -SourceCommit $ExpectedSourceCommit -LauncherSha256 ('b'*64) -UpdaterSha256 $updaterSha -CandidateManifestSha256 $candidateSha -RequesterPid $PID -RequesterCreationUtcTicks $requesterProcess.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $childRequest
    $childScript=New-F2UpdateElevatedChildScript -UpdaterPath $updaterFile -CandidatePath $candidateFile -SourceRoot $syntheticRoot -ExpectedSourceCommit $ExpectedSourceCommit -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $updaterSha -ExpectedCandidateManifestSha256 $candidateSha -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $requesterProcess.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $childRequest -DiagnosticProtocolPath $protocolFile -DiagnosticProtocolBytes $protocolBytes
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    if($encoded.Length -gt 32767){throw 'SYNTHETIC_MANIFEST_CHILD_COMMAND_TOO_LARGE'}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $child=New-Object Diagnostics.Process;$child.StartInfo=$start
    if(-not $child.Start()){throw 'SYNTHETIC_MANIFEST_CHILD_START_FAILED'}
    $ticks=$child.StartTime.ToUniversalTime().Ticks
    $result=Receive-F2UpdateDiagnosticRecord -Server $script:Server -Request $childRequest -ChildProcess $child -ChildCreationUtcTicks $ticks -TimeoutSeconds 10 -PostExitWaitMilliseconds 300 -RecordTimeoutMilliseconds 1500
    $stdout=$child.StandardOutput.ReadToEnd();$stderr=$child.StandardError.ReadToEnd()
    $passed=$result.DiagnosticStatus -ceq 'VALIDATED' -and $result.ActualChildExitCode -eq 1 -and $result.Record.Stage -ceq $ExpectedStage -and $result.Record.ErrorCode -ceq $ExpectedCode -and -not $result.TimedOut
    [pscustomobject]@{Passed=[bool]$passed;Result=$result;Process=$child;Stdout=$stdout;Stderr=$stderr;UpdaterSha256=$updaterSha;CandidateSha256=$candidateSha;EncodedLength=$encoded.Length}
}

$script:Server = New-F2UpdateDiagnosticServer -Request $request
$syntheticRoot=$null
try {
    $tempBase=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $syntheticRoot=Join-Path $tempBase ('F2G1-Diagnostic-Test-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($syntheticRoot)
    $updaterFixture=Join-Path $syntheticRoot 'synthetic-updater.ps1'
    $candidateFixture=Join-Path $syntheticRoot 'synthetic-candidate.json'
    $badProtocolFixture=Join-Path $syntheticRoot 'bad-diagnostic-protocol.ps1'
    $commitFixture='a'*40
    $candidateFixtureBytes=[Text.Encoding]::UTF8.GetBytes('{"Schema":"f2-icacls-runtime-release-v3","ReviewedCommitSha":"'+$commitFixture+'"}')
    [IO.File]::WriteAllBytes($candidateFixture,$candidateFixtureBytes)
    $candidateFixtureHash=Get-F2UpdateDiagnosticSha256 -Bytes $candidateFixtureBytes
    $prelockSource=New-PrelockSourceFixture -Root $syntheticRoot
    $prelockOld=New-PrelockOldReleaseFixture -Root $syntheticRoot
    Assert-Diagnostic ($prelockSource.Commit -match '^[0-9a-f]{40}$' -and $prelockSource.SourcePins.Count -eq 7 -and $prelockOld.Files.Count -eq 7 -and (Get-F2UpdateDiagnosticSha256 -Bytes $prelockOld.ManifestBytes) -ceq $script:F2UpdateOldManifestSha256) 'pre-lock child fixtures use a clean temporary Git source and exact pinned old-v2 manifest and files'

    $reviewCandidatePath=(Resolve-Path (Join-Path $PSScriptRoot '..\..\docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json')).Path
    $reviewCandidateBytes=[IO.File]::ReadAllBytes($reviewCandidatePath)
    $reviewCandidateHash=Get-F2UpdateSha256 -Bytes $reviewCandidateBytes
    $reviewCandidate=Get-F2UpdateManifestObject -Bytes $reviewCandidateBytes -ExpectedSchema v3 -ExpectedHash $reviewCandidateHash
    Assert-Diagnostic ($reviewCandidateHash -match '^[0-9a-f]{64}$' -and $reviewCandidate.Schema -ceq 'f2-icacls-runtime-release-v3' -and $reviewCandidate.ReviewedCommitSha -match '^[0-9a-f]{40}$' -and @($reviewCandidate.Files).Count -eq 7) 'actual reviewed candidate bytes pass the exact production manifest loader in the Windows PowerShell 5.1 suite'

    function New-F2ManifestBytesOmittingProperty {
        param($Manifest,[string]$OmittedName)
        $document=[ordered]@{}
        foreach($property in $Manifest.PSObject.Properties){if($property.Name -cne $OmittedName){$document[$property.Name]=$property.Value}}
        return ,[Text.UTF8Encoding]::new($false).GetBytes(($document|ConvertTo-Json -Compress -Depth 8))
    }
    function Get-F2ManifestTestErrorCode {
        param([AllowEmptyCollection()][byte[]]$Bytes)
        $hash=Get-F2UpdateSha256 -Bytes $Bytes
        try{$null=Get-F2UpdateManifestObject -Bytes $Bytes -ExpectedSchema v3 -ExpectedHash $hash;return 'UNEXPECTED_PASS'}
        catch{return Normalize-F2UpdateDiagnosticCode -Code ([string]$_.Exception.Message) -Stage CandidateManifestValidation -ExceptionType ([string]$_.Exception.GetType().FullName)}
    }
    $reviewCandidateObject=[Text.Encoding]::UTF8.GetString($reviewCandidateBytes)|ConvertFrom-Json -ErrorAction Stop
    $missingIdentityBytes=New-F2ManifestBytesOmittingProperty -Manifest $reviewCandidateObject -OmittedName 'BaselineMailboxId'
    $missingFilesBytes=New-F2ManifestBytesOmittingProperty -Manifest $reviewCandidateObject -OmittedName 'Files'
    $missingPackageRootBytes=New-F2ManifestBytesOmittingProperty -Manifest $reviewCandidateObject -OmittedName 'PackageRoot'
    Assert-Diagnostic ((Get-F2ManifestTestErrorCode -Bytes ([Text.Encoding]::UTF8.GetBytes('[]'))) -ceq 'UPDATE_MANIFEST_JSON_INVALID') 'manifest arrays are rejected as non-object roots with a fixed safe code'
    Assert-Diagnostic ((Get-F2ManifestTestErrorCode -Bytes $missingIdentityBytes) -ceq 'UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID') 'missing required baseline identity field returns its allowlisted stable code instead of a StrictMode exception'
    Assert-Diagnostic ((Get-F2ManifestTestErrorCode -Bytes $missingFilesBytes) -ceq 'UPDATE_MANIFEST_FILE_SET_INVALID') 'missing Files property returns the fixed file-set code'
    Assert-Diagnostic ((Get-F2ManifestTestErrorCode -Bytes $missingPackageRootBytes) -ceq 'UPDATE_MANIFEST_PACKAGE_ROOT_INVALID') 'missing v3 PackageRoot returns the fixed package-root code'

    $badPinDocument=[ordered]@{}
    $badPinFiles=New-Object 'System.Collections.Generic.List[object]'
    foreach($property in $reviewCandidateObject.PSObject.Properties){
        if($property.Name -ceq 'Files'){
            $index=0
            foreach($file in $property.Value){if($index -eq 0){$badPinFiles.Add([pscustomobject]@{Name=[string]$file.Name})}else{$badPinFiles.Add($file)};$index++}
            $badPinDocument['Files']=$badPinFiles.ToArray()
        }else{$badPinDocument[$property.Name]=$property.Value}
    }
    $badFilePinBytes=[Text.UTF8Encoding]::new($false).GetBytes(($badPinDocument|ConvertTo-Json -Compress -Depth 8))
    Assert-Diagnostic ((Get-F2ManifestTestErrorCode -Bytes $badFilePinBytes) -ceq 'UPDATE_MANIFEST_FILE_PIN_INVALID') 'missing per-file SHA field returns the fixed file-pin code'

    function Get-F2InjectedManifestHashFailureCode {
        param([byte[]]$Bytes)
        function Get-F2UpdateSha256 { throw 'SYNTHETIC_PRIVATE_EXCEPTION_MARKER' }
        try{$null=Get-F2UpdateManifestObject -Bytes $Bytes -ExpectedSchema v3 -ExpectedHash ('0'*64);return 'UNEXPECTED_PASS'}
        catch{return Normalize-F2UpdateDiagnosticCode -Code ([string]$_.Exception.Message) -Stage CandidateManifestValidation -ExceptionType ([string]$_.Exception.GetType().FullName)}
    }
    $hashFailureCode=Get-F2InjectedManifestHashFailureCode -Bytes $reviewCandidateBytes
    Assert-Diagnostic ($hashFailureCode -ceq 'UPDATE_MANIFEST_HASH_MISMATCH' -and $hashFailureCode -notmatch 'SYNTHETIC|EXCEPTION') 'unexpected hash-operation exceptions are classified to a fixed category without leaking exception text'

    $validManifestChild=Invoke-F2ManifestValidationChildFixture -CandidateBytes $reviewCandidateBytes -ExpectedSourceCommit $reviewCandidate.ReviewedCommitSha -ExpectedStage SourceGitValidation -ExpectedCode UPDATE_SOURCE_GIT_UNAVAILABLE
    Assert-Diagnostic ($validManifestChild.Passed -and $validManifestChild.EncodedLength -le 32767) 'real child process executes the production bootstrap and production manifest loader, passes the exact candidate, then reaches a no-write synthetic updater stub'
    $validManifestChild.Process.Dispose()
    $malformedManifestChild=Invoke-F2ManifestValidationChildFixture -CandidateBytes $missingIdentityBytes -ExpectedSourceCommit $reviewCandidate.ReviewedCommitSha -ExpectedStage CandidateManifestValidation -ExpectedCode UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID
    Assert-Diagnostic ($malformedManifestChild.Passed -and $malformedManifestChild.Result.Record.ErrorCode -cne 'UPDATE_UNCLASSIFIED_FAILURE') 'real child process reports malformed-manifest validation failure through the authenticated pipe with a fixed allowlisted code'
    $malformedManifestChild.Process.Dispose()

    $prelockUpdaterFixture=Join-Path $syntheticRoot 'production-updater-with-test-entrypoint.ps1'
    $prelockCandidateFixture=Join-Path $syntheticRoot 'prelock-candidate.json'
    $prelockCases=@(
        @{Name='candidate manifest parse';Fault='MalformedCandidate';Stage='CandidateManifestValidation';Code='UPDATE_MANIFEST_JSON_INVALID';ParentPass=$true},
        @{Name='candidate manifest missing required identity field';Fault='MissingIdentity';Stage='CandidateManifestValidation';Code='UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID';ParentPass=$true},
        @{Name='candidate manifest';Fault='WrongPackageRoot';Stage='CandidateManifestValidation';Code='UPDATE_CANDIDATE_PACKAGE_ROOT_MISMATCH';ParentPass=$true},
        @{Name='source Git';Fault='WrongOrigin';Stage='SourceGitValidation';Code='UPDATE_SOURCE_ORIGIN_MISMATCH';ParentPass=$true},
        @{Name='source package pin';Fault='WrongPackagePin';Stage='SourcePackagePinValidation';Code='UPDATE_SOURCE_PACKAGE_HASH_MISMATCH';ParentPass=$true},
        @{Name='parent ACL';Fault='ParentReject';Stage='ParentAclValidation';Code='UPDATE_PARENT_CHAIN_UNSAFE';ParentPass=$false},
        @{Name='installed v2';Fault='CorruptOldFile';Stage='InstalledV2Validation';Code='UPDATE_FILE_HASH_MISMATCH';ParentPass=$true},
        @{Name='transaction collision';Fault='BadLockBytes';Stage='TransactionCollisionValidation';Code='UPDATE_FILE_TYPE_OR_SIZE_INVALID';ParentPass=$true}
    )
    foreach($prelockCase in $prelockCases){
        $caseRoot=Join-Path $syntheticRoot ('prelock-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($caseRoot)
        $installTree=New-PrelockInstallTree -Root $caseRoot -OldRelease $prelockOld
        $candidateFault=if($prelockCase.Fault -eq 'WrongPackageRoot'){'WrongPackageRoot'}elseif($prelockCase.Fault -eq 'WrongPackagePin'){'WrongPackagePin'}elseif($prelockCase.Fault -eq 'MalformedCandidate'){'MalformedCandidate'}elseif($prelockCase.Fault -eq 'MissingIdentity'){'MissingIdentity'}else{'Valid'}
        $prelockCandidateBytes=New-PrelockCandidateBytes -Source $prelockSource -PackageHome $installTree.PackageHome -Fault $candidateFault
        [IO.File]::WriteAllBytes($prelockCandidateFixture,$prelockCandidateBytes)
        $fixtureGit=Get-Command git.exe -ErrorAction Stop
        if($prelockCase.Fault -eq 'WrongOrigin'){
            & $fixtureGit.Source -C $prelockSource.Root remote set-url origin 'https://example.invalid/wrong-origin.git'
            if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_SOURCE_GIT_REMOTE_MUTATION_FAILED'}
        }elseif($prelockCase.Fault -eq 'CorruptOldFile'){
            [IO.File]::WriteAllText($installTree.ActiveManifestPath,'synthetic active-manifest corruption')
        }elseif($prelockCase.Fault -eq 'BadLockBytes'){
            [IO.File]::WriteAllText((Join-Path $installTree.ProgramDataRoot 'release.lock'),'non-empty synthetic collision')
        }
        $childCase=Invoke-PrelockProductionChildFixture -UpdaterFile $prelockUpdaterFixture -CandidateFile $prelockCandidateFixture -SourceRoot $prelockSource.Root -SourceCommit $prelockSource.Commit -PackageHome $installTree.PackageHome -ProgramDataRoot $installTree.ProgramDataRoot -ActiveManifestPath $installTree.ActiveManifestPath -ParentAclPass $prelockCase.ParentPass -ExpectedStage $prelockCase.Stage -ExpectedCode $prelockCase.Code
        if($prelockCase.Fault -eq 'WrongOrigin'){
            & $fixtureGit.Source -C $prelockSource.Root remote set-url origin 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
            if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_SOURCE_GIT_REMOTE_RESTORE_FAILED'}
        }
        $recordNames=if($null -ne $childCase.Result.Record){@($childCase.Result.Record.PSObject.Properties|ForEach-Object Name)}else{@()}
        $expectedRecordNames=@('Schema','Authority','RequestId','Nonce','SourceCommit','LauncherSha256','UpdaterSha256','CandidateManifestSha256','RequesterPid','RequesterCreationUtcTicks','RequesterSidSha256','ChildPid','ChildCreationUtcTicks','ChildExitCode','Stage','ErrorCode')
        $recordShape=$recordNames.Count -eq $expectedRecordNames.Count -and @(Compare-Object $expectedRecordNames $recordNames -CaseSensitive).Count -eq 0
        $safeRecord=$childCase.Passed -and $childCase.Result.Record.Authority -ceq 'NON_AUTHORITATIVE_DIAGNOSTIC' -and $childCase.Result.Record.Stage -ceq $prelockCase.Stage -and $childCase.Result.Record.ErrorCode -ceq $prelockCase.Code -and $recordShape -and $childCase.Stdout.Length -le 4096 -and $childCase.Stderr.Length -le 4096
        if(-not $safeRecord){$observedStage=if($null -ne $childCase.Result.Record){[string]$childCase.Result.Record.Stage}else{'<missing>'};$observedCode=if($null -ne $childCase.Result.Record){[string]$childCase.Result.Record.ErrorCode}else{$childCase.Result.DiagnosticErrorCode};Write-Host ('PRELOCK_CASE='+$prelockCase.Name+';Status='+$childCase.Result.DiagnosticStatus+';Stage='+$observedStage+';Code='+$observedCode+';ChildExit='+$childCase.Result.ActualChildExitCode+';Timeout='+$childCase.Result.TimedOut)}
        Assert-Diagnostic $safeRecord ("production child builder and authenticated pipe report {0} failure as {1}/{2} in the fixed sanitized schema" -f $prelockCase.Name,$prelockCase.Stage,$prelockCase.Code)
        $noTransactionRoots= -not [IO.Directory]::Exists((Join-Path $installTree.PackageHome 'releases')) -and -not [IO.Directory]::Exists((Join-Path $installTree.ProgramDataRoot 'updates')) -and -not [IO.Directory]::Exists((Join-Path $installTree.ProgramDataRoot 'backups'))
        if($prelockCase.Fault -eq 'BadLockBytes'){$noTransactionRoots=$noTransactionRoots -and [IO.File]::ReadAllText((Join-Path $installTree.ProgramDataRoot 'release.lock')) -ceq 'non-empty synthetic collision'}else{$noTransactionRoots=$noTransactionRoots -and -not [IO.File]::Exists((Join-Path $installTree.ProgramDataRoot 'release.lock'))}
        Assert-Diagnostic $noTransactionRoots ("{0} failure preserves the TEMP-only old release and creates no transaction objects" -f $prelockCase.Name)
        $childCase.Process.Dispose()
    }
    $fixtureUpdaterText=New-SyntheticUpdaterText -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_GIT_UNAVAILABLE'
    $fixtureUpdaterBytes=[Text.UTF8Encoding]::new($false).GetBytes($fixtureUpdaterText)
    [IO.File]::WriteAllBytes($updaterFixture,$fixtureUpdaterBytes)
    $fixtureUpdaterHash=Get-F2UpdateDiagnosticSha256 -Bytes $fixtureUpdaterBytes

    $validChildRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $fixtureUpdaterHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    [IO.File]::WriteAllBytes($badProtocolFixture,[Text.Encoding]::UTF8.GetBytes('Set-StrictMode -Version Latest'))
    $bootstrapChild=Invoke-ProductionChildFixture -Request $validChildRequest -TempRoot $syntheticRoot -ProtocolFile $badProtocolFixture -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $fixtureUpdaterHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage '' -ExpectedCode '' -ExpectMissing
    Assert-Diagnostic ($bootstrapChild.Passed -and $bootstrapChild.Result.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_MISSING' -and $bootstrapChild.Result.ActualChildExitCode -eq 1) 'real child script retains exact exit when protocol bootstrap fails before a trusted sender is available'
    $bootstrapChild.Process.Dispose()

    $hashRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $fixtureUpdaterHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $hashChild=Invoke-ProductionChildFixture -Request $hashRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash ('f'*64) -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage 'UpdaterAndCandidateHashValidation' -ExpectedCode 'UPDATE_UPDATER_HASH_MISMATCH'
    Assert-Diagnostic $hashChild.Passed 'real child script reports updater hash validation failure through the pipe'
    $hashChild.Process.Dispose()

    $invalidUpdaterBytes=[Text.UTF8Encoding]::new($false).GetBytes('function This-Script-Is-Not-Closed {')
    [IO.File]::WriteAllBytes($updaterFixture,$invalidUpdaterBytes)
    $invalidUpdaterHash=Get-F2UpdateDiagnosticSha256 -Bytes $invalidUpdaterBytes
    $parseRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $invalidUpdaterHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $parseChild=Invoke-ProductionChildFixture -Request $parseRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $invalidUpdaterHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage 'UpdaterScriptLoading' -ExpectedCode 'UPDATE_UPDATER_SCRIPT_LOAD_FAILED'
    Assert-Diagnostic $parseChild.Passed 'real child script reports updater parsing/loading failure through the pipe'
    $parseChild.Process.Dispose()

    $identityBytes=[Text.UTF8Encoding]::new($false).GetBytes((New-SyntheticUpdaterText -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_GIT_UNAVAILABLE' -IdentityFailure))
    [IO.File]::WriteAllBytes($updaterFixture,$identityBytes)
    $identityHash=Get-F2UpdateDiagnosticSha256 -Bytes $identityBytes
    $identityRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $identityHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $identityChild=Invoke-ProductionChildFixture -Request $identityRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $identityHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage 'ElevatedIdentityValidation' -ExpectedCode 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH'
    Assert-Diagnostic $identityChild.Passed 'real child script reports identity validation failure without invoking transaction code'
    $identityChild.Process.Dispose()

    $invokeCases=@(
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_SOURCE_GIT_UNAVAILABLE';Name='source Git resolution'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_PROGRAM_FILES_PARENT_DACL_UNSAFE';Name='parent ACL validation'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_OLD_RELEASE_PIN_MISMATCH';Name='old installed-release validation'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_NATIVE_HELPER_COMPILE_FAILED';Name='native helper compilation'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_RELEASE_LOCK_CREATE_FAILED';Name='initial release-lock creation'}
    )
    foreach($invokeCase in $invokeCases){
        $fixtureBytes=[Text.UTF8Encoding]::new($false).GetBytes((New-SyntheticUpdaterText -Stage $invokeCase.Stage -Code $invokeCase.Code))
        [IO.File]::WriteAllBytes($updaterFixture,$fixtureBytes)
        $fixtureHash=Get-F2UpdateDiagnosticSha256 -Bytes $fixtureBytes
        $caseRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $fixtureHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
        $childCase=Invoke-ProductionChildFixture -Request $caseRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $fixtureHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage $invokeCase.Stage -ExpectedCode $invokeCase.Code
        Assert-Diagnostic $childCase.Passed ("real production child reports synthetic failure for {0}" -f $invokeCase.Name)
        $childCase.Process.Dispose()
    }

    $sizeProbe=New-F2UpdateElevatedChildScript -UpdaterPath $updaterFixture -CandidatePath $candidateFixture -SourceRoot $syntheticRoot -ExpectedSourceCommit $commitFixture -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $fixtureHash -ExpectedCandidateManifestSha256 $candidateFixtureHash -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $caseRequest -DiagnosticProtocolPath $protocolPath -DiagnosticProtocolBytes $protocolBytes
    $encodedSize=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($sizeProbe)).Length
    Assert-Diagnostic ($encodedSize + 100 -lt 32767) 'production child command and fixed PowerShell arguments stay below the Windows command-line limit'
    Write-Output ('ProductionChildEncodedCommandCharacters='+$encodedSize+';FixedArgumentReserve=100;Limit=32767')

    $cases = @(
        @{Stage='ChildBootstrapInitialization';Code='UPDATE_CHILD_BOOTSTRAP_INITIALIZATION_FAILED'},
        @{Stage='UpdaterScriptLoading';Code='UPDATE_UPDATER_SCRIPT_LOAD_FAILED'},
        @{Stage='ElevatedIdentityValidation';Code='UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH'},
        @{Stage='UpdaterAndCandidateHashValidation';Code='UPDATE_UPDATER_HASH_MISMATCH'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_SOURCE_GIT_UNAVAILABLE'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_PROGRAM_FILES_PARENT_DACL_UNSAFE'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_OLD_RELEASE_PIN_MISMATCH'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_NATIVE_HELPER_COMPILE_FAILED'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_RELEASE_LOCK_CREATE_FAILED'}
    )
    foreach($case in $cases){
        $one=New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
        $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $one
        $worker=Invoke-SyntheticDiagnosticWorker -Request $one -Stage $case.Stage -Code $case.Code
        $ok=$worker.Result.DiagnosticStatus -ceq 'VALIDATED' -and $worker.Result.Record.Stage -ceq $case.Stage -and $worker.Result.Record.ErrorCode -ceq $case.Code -and $worker.Result.ActualChildExitCode -eq 1 -and -not $worker.Result.TimedOut
        Assert-Diagnostic $ok ("cross-process report preserves {0}/{1} with child exit 1" -f $case.Stage,$case.Code)
        $worker.Process.Dispose()
    }

    foreach($negative in @(
        @{Name='stale or replayed nonce';Args=@{WrongRequest=$true};Expected='INVALID'},
        @{Name='tampered payload digest';Args=@{Tamper=$true};Expected='INVALID'},
        @{Name='unlisted diagnostic stage';Args=@{UnknownStage=$true};Expected='INVALID'},
        @{Name='duplicate diagnostic frame';Args=@{Duplicate=$true};Expected='INVALID'},
        @{Name='oversized frame';Args=@{Oversize=$true};Expected='INVALID'},
        @{Name='unavailable diagnostic record';Args=@{Stage='NO_MESSAGE'};Expected='MISSING'},
        @{Name='stalled partial frame';Args=@{Stall=$true};Expected='INVALID'}
    )){
        $one=New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
        $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $one
        $negativeArgs = $negative.Args
        $worker=Invoke-SyntheticDiagnosticWorker -Request $one @negativeArgs
        Assert-Diagnostic ($worker.Result.DiagnosticStatus -ceq $negative.Expected -and $worker.Result.ActualChildExitCode -eq 1) ("rejects {0} while retaining child exit (status={1};code={2};exit={3})" -f $negative.Name,$worker.Result.DiagnosticStatus,$worker.Result.DiagnosticErrorCode,$worker.Result.ActualChildExitCode)
        $worker.Process.Dispose()
    }

    $exitMismatch = New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $exitMismatch
    $exitMismatchWorker=Invoke-SyntheticDiagnosticWorker -Request $exitMismatch -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_GIT_UNAVAILABLE' -ExitCode 2 -RecordExitCode 1
    Assert-Diagnostic ($exitMismatchWorker.Result.DiagnosticStatus -ceq 'INVALID' -and $exitMismatchWorker.Result.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH' -and $exitMismatchWorker.Result.ActualChildExitCode -eq 2 -and $null -eq $exitMismatchWorker.Result.Record) 'rejects a diagnostic claim that conflicts with the independently observed child exit'
    $exitMismatchWorker.Process.Dispose()

    $falseSuccessRequest = New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $falseSuccessRequest
    $falseSuccessWorker=Invoke-SyntheticDiagnosticWorker -Request $falseSuccessRequest -Stage 'Complete' -Code 'NONE' -ExitCode 1 -RecordExitCode 0
    Assert-Diagnostic ($falseSuccessWorker.Result.DiagnosticStatus -ceq 'INVALID' -and $falseSuccessWorker.Result.ActualChildExitCode -eq 1 -and $null -eq $falseSuccessWorker.Result.Record) 'rejects a forged Complete/zero diagnostic when the observed child actually failed'
    $falseSuccessWorker.Process.Dispose()

    $badPid = New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $script:Server.Dispose();$script:Server=New-F2UpdateDiagnosticServer -Request $badPid
    $targetStart=New-Object Diagnostics.ProcessStartInfo
    $targetStart.FileName=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $targetStart.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 5000; exit 1"'
    $targetStart.UseShellExecute=$false;$targetStart.CreateNoWindow=$true;$targetStart.RedirectStandardOutput=$true;$targetStart.RedirectStandardError=$true
    $target=New-Object Diagnostics.Process;$target.StartInfo=$targetStart
    if(-not $target.Start()){throw 'SYNTHETIC_EXPECTED_PROCESS_START_FAILED'}
    $wrongWorker=Invoke-SyntheticDiagnosticWorker -Request $badPid -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_COMMIT_MISMATCH' -ExpectedChildProcess $target
    $wrongClientPass = $wrongWorker.Result.DiagnosticStatus -ceq 'INVALID' -and $wrongWorker.Result.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH' -and $wrongWorker.Result.ActualChildExitCode -eq 1
    if (-not $wrongClientPass) { Write-Host ('WrongClientResult=' + ($wrongWorker.Result | ConvertTo-Json -Compress -Depth 4)) }
    Assert-Diagnostic $wrongClientPass 'rejects a distinct connected process while retaining the independently observed target exit'
    $wrongWorker.Process.Dispose();$target.Dispose()
}
finally {
    if($null -ne $script:Server){$script:Server.Dispose()}
    if($null -ne $syntheticRoot -and [IO.Path]::GetFullPath($syntheticRoot).StartsWith(([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($syntheticRoot) -match '^F2G1-Diagnostic-Test-[0-9a-f]{32}$'){
        $tempItem=Get-Item -LiteralPath $syntheticRoot -Force -ErrorAction SilentlyContinue
        if($null -ne $tempItem -and ($tempItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){Remove-Item -LiteralPath $syntheticRoot -Recurse -Force -ErrorAction Stop}
    }
}

Write-Output ('Assertions=' + $script:Assertions + ';Failures=' + $script:Failures.Count)
if($script:Failures.Count -gt 0){exit 1}
exit 0

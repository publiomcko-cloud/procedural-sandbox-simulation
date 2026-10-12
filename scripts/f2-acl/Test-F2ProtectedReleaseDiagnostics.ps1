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
    param($Request,[string]$Stage='UpdaterInvocation',[string]$Code='UPDATE_UNCLASSIFIED_FAILURE',[int]$ExitCode=1,[int]$RecordExitCode=-1,[switch]$Duplicate,[switch]$Tamper,[switch]$Oversize,[switch]$Stall,[switch]$WrongRequest,[Diagnostics.Process]$ExpectedChildProcess)
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
elseif('__NO_MESSAGE__' -ne '1'){$null=Send-F2UpdateDiagnosticRecord -Request $request -Stage $stage -ErrorCode $code -ChildExitCode $recordExit -ConnectTimeoutMilliseconds 3000}
exit $exit
'@
    $wrongFlag = if($WrongRequest.IsPresent){1}else{0}; $duplicateFlag = if($Duplicate.IsPresent){1}else{0}; $tamperFlag = if($Tamper.IsPresent){1}else{0}; $oversizeFlag = if($Oversize.IsPresent){1}else{0}; $stallFlag = if($Stall.IsPresent){1}else{0}
    $noMessage = [int]($Stage -eq 'NO_MESSAGE')
    if($RecordExitCode -eq -1){$RecordExitCode=$ExitCode}
    $worker = $worker.Replace('__PROTOCOL_PATH__',$protocolPath.Replace("'","''")).Replace('__REQUEST__',$requestB64).Replace('__STAGE__',$Stage).Replace('__CODE__',$Code).Replace('__EXIT__',[string]$ExitCode).Replace('__RECORD_EXIT__',[string]$RecordExitCode).Replace('__WRONG__',[string]$wrongFlag).Replace('__DUPLICATE__',[string]$duplicateFlag).Replace('__TAMPER__',[string]$tamperFlag).Replace('__OVERSIZE__',[string]$oversizeFlag).Replace('__STALL__',[string]$stallFlag).Replace('__NO_MESSAGE__',[string]$noMessage)
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

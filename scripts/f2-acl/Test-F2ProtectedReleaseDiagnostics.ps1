[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:F2TraceCaseId = 'BOOTSTRAP'
$script:F2TraceClock = [Diagnostics.Stopwatch]::StartNew()
$script:F2TraceRecordCount = 0
$script:F2TraceLimitReported = $false
$script:F2TraceRecordLimit = 1024
$script:Server = $null
trap { [Console]::Error.WriteLine('F2FIXTURE_FAILURE ErrorClass=UNCLASSIFIED'); exit 1 }

function Assert-Diagnostic([bool]$Condition, [string]$Name) {
    $script:Assertions++
    if (-not $Condition) { $script:Failures.Add($Name); Write-Host ('FAIL: ' + $Name) }
    else { Write-Host ('PASS: ' + $Name) }
}

# TEMP-fixture-only trace. Values are finite labels/numbers; never include paths,
# command lines, pipe names, identities, nonces, captured streams or exceptions.
function Start-F2FixtureTraceCase {
    param([ValidateSet('CHANNEL_FAILURE','MANIFEST_VALID','MANIFEST_MALFORMED','PRELOCK_CANDIDATE_PARSE','PRELOCK_CANDIDATE_IDENTITY','PRELOCK_CANDIDATE_ROOT','PRELOCK_CANDIDATE_PIN','PRELOCK_SOURCE_GIT','PRELOCK_PARENT_ACL','PRELOCK_OLD_RELEASE','PRELOCK_TRANSACTION_COLLISION','PROTOCOL_BOOTSTRAP_FAILURE','UPDATER_HASH_FAILURE','UPDATER_PARSE_FAILURE','IDENTITY_FAILURE','INVOKE_SOURCE_GIT','INVOKE_PARENT_ACL','INVOKE_OLD_RELEASE','INVOKE_NATIVE_HELPER','INVOKE_RELEASE_LOCK','DIAGNOSTIC_VALID','DIAGNOSTIC_BOOTSTRAP','DIAGNOSTIC_SCRIPT_LOADING','DIAGNOSTIC_IDENTITY','DIAGNOSTIC_HASH','DIAGNOSTIC_SOURCE_GIT','DIAGNOSTIC_PARENT_ACL','DIAGNOSTIC_OLD_RELEASE','DIAGNOSTIC_NATIVE_HELPER','DIAGNOSTIC_RELEASE_LOCK','DIAGNOSTIC_BAD_NONCE','DIAGNOSTIC_TAMPERED','DIAGNOSTIC_UNKNOWN_STAGE','DIAGNOSTIC_DUPLICATE','DIAGNOSTIC_OVERSIZE','DIAGNOSTIC_MISSING','DIAGNOSTIC_STALL','CHILD_EXIT_MISMATCH','FALSE_SUCCESS','WRONG_CLIENT','TEMP_CLEANUP')][string]$CaseId)
    $script:F2TraceCaseId = $CaseId
    $script:F2TraceClock = [Diagnostics.Stopwatch]::StartNew()
    Write-F2FixtureTrace -Event CASE_START -Status STARTED
    return $script:F2TraceClock
}

function Write-F2FixtureTrace {
    param(
        [ValidateSet('CASE_START','PIPE_CREATE','SERVER_DISPOSE','PROCESS_OBJECT_CREATE','PROCESS_START','PROCESS_START_TIME','RECEIVER','EXIT_OBSERVATION','STDOUT_DRAIN','STDERR_DRAIN','PROCESS_DISPOSE','TEMP_CLEANUP','TRACE_LIMIT_REACHED')][string]$Event,
        [ValidateSet('STARTED','BEGIN','COMPLETE','FAILED','RETURNED_FALSE','OBSERVED','NOT_OBSERVED','VALIDATED','INVALID','MISSING','CHANNEL_FAILED','TIMEOUT','SKIPPED','REPARSE_BLOCKED')][string]$Status,
        [int]$ProcessId = 0,
        [int]$ChildExitCode = -2147483648,
        [ValidateSet('NONE','PIPE_CREATE','SERVER_DISPOSE','PROCESS_START','PROCESS_START_TIME','RECEIVER','STDOUT_DRAIN','STDERR_DRAIN','PROCESS_DISPOSE','TEMP_CLEANUP','UNCLASSIFIED')][string]$ErrorClass = 'NONE'
    )
    if ($script:F2TraceRecordCount -ge $script:F2TraceRecordLimit) {
        if (-not $script:F2TraceLimitReported) {
            $script:F2TraceLimitReported = $true
            try { [Console]::Out.WriteLine('F2FIXTURETRACE {"Schema":"f2-diagnostic-fixture-trace-v1","CaseId":"TRACE_LIMIT","Event":"TRACE_LIMIT_REACHED","ElapsedMs":0,"Status":"SKIPPED","ErrorClass":"NONE","Pid":null,"ChildExitCode":null}') } catch { }
        }
        return
    }
    $script:F2TraceRecordCount++
    try {
        $elapsed = if ($null -ne $script:F2TraceClock) { [long]$script:F2TraceClock.ElapsedMilliseconds } else { [long]0 }
        $record = [ordered]@{
            Schema = 'f2-diagnostic-fixture-trace-v1'
            CaseId = $script:F2TraceCaseId
            Event = $Event
            ElapsedMs = $elapsed
            Status = $Status
            ErrorClass = $ErrorClass
            Pid = if ($ProcessId -gt 0) { $ProcessId } else { $null }
            ChildExitCode = if ($ChildExitCode -ne -2147483648) { $ChildExitCode } else { $null }
        }
        $json = ConvertTo-Json -InputObject $record -Compress -Depth 3
        if ($json.Length -le 512) { [Console]::Out.WriteLine('F2FIXTURETRACE ' + $json) }
    } catch { }
}

function Reset-F2FixtureServer {
    param($Request,[ValidateSet('CHANNEL_FAILURE','MANIFEST_VALID','MANIFEST_MALFORMED','PRELOCK_CANDIDATE_PARSE','PRELOCK_CANDIDATE_IDENTITY','PRELOCK_CANDIDATE_ROOT','PRELOCK_CANDIDATE_PIN','PRELOCK_SOURCE_GIT','PRELOCK_PARENT_ACL','PRELOCK_OLD_RELEASE','PRELOCK_TRANSACTION_COLLISION','PROTOCOL_BOOTSTRAP_FAILURE','UPDATER_HASH_FAILURE','UPDATER_PARSE_FAILURE','IDENTITY_FAILURE','INVOKE_SOURCE_GIT','INVOKE_PARENT_ACL','INVOKE_OLD_RELEASE','INVOKE_NATIVE_HELPER','INVOKE_RELEASE_LOCK','DIAGNOSTIC_VALID','DIAGNOSTIC_BOOTSTRAP','DIAGNOSTIC_SCRIPT_LOADING','DIAGNOSTIC_IDENTITY','DIAGNOSTIC_HASH','DIAGNOSTIC_SOURCE_GIT','DIAGNOSTIC_PARENT_ACL','DIAGNOSTIC_OLD_RELEASE','DIAGNOSTIC_NATIVE_HELPER','DIAGNOSTIC_RELEASE_LOCK','DIAGNOSTIC_BAD_NONCE','DIAGNOSTIC_TAMPERED','DIAGNOSTIC_UNKNOWN_STAGE','DIAGNOSTIC_DUPLICATE','DIAGNOSTIC_OVERSIZE','DIAGNOSTIC_MISSING','DIAGNOSTIC_STALL','CHILD_EXIT_MISMATCH','FALSE_SUCCESS','WRONG_CLIENT')][string]$CaseId)
    [void](Start-F2FixtureTraceCase -CaseId $CaseId)
    if ($null -ne $script:Server) {
        Write-F2FixtureTrace -Event SERVER_DISPOSE -Status BEGIN
        try { $script:Server.Dispose(); $script:Server = $null; Write-F2FixtureTrace -Event SERVER_DISPOSE -Status COMPLETE }
        catch { Write-F2FixtureTrace -Event SERVER_DISPOSE -Status FAILED -ErrorClass SERVER_DISPOSE; throw }
    }
    Write-F2FixtureTrace -Event PIPE_CREATE -Status BEGIN
    try { $script:Server = New-F2UpdateDiagnosticServer -Request $Request; Write-F2FixtureTrace -Event PIPE_CREATE -Status COMPLETE }
    catch { Write-F2FixtureTrace -Event PIPE_CREATE -Status FAILED -ErrorClass PIPE_CREATE; throw }
}

function New-F2FixtureProcess {
    param([Diagnostics.ProcessStartInfo]$StartInfo)
    Write-F2FixtureTrace -Event PROCESS_OBJECT_CREATE -Status BEGIN
    try { $process = New-Object Diagnostics.Process; $process.StartInfo = $StartInfo; Write-F2FixtureTrace -Event PROCESS_OBJECT_CREATE -Status COMPLETE; return $process }
    catch { Write-F2FixtureTrace -Event PROCESS_OBJECT_CREATE -Status FAILED -ErrorClass UNCLASSIFIED; throw }
}

function Get-F2FixtureProcessId {
    param([Diagnostics.Process]$Process)
    try { return [int]$Process.Id } catch { return 0 }
}

function Start-F2FixtureProcess {
    param([Diagnostics.Process]$Process,[string]$FailureLabel)
    Write-F2FixtureTrace -Event PROCESS_START -Status BEGIN
    $startReturnedFalse = $false
    try {
        if (-not $Process.Start()) { $startReturnedFalse = $true; Write-F2FixtureTrace -Event PROCESS_START -Status RETURNED_FALSE -ErrorClass PROCESS_START; throw $FailureLabel }
        Write-F2FixtureTrace -Event PROCESS_START -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $Process)
    } catch { if (-not $startReturnedFalse) { Write-F2FixtureTrace -Event PROCESS_START -Status FAILED -ErrorClass PROCESS_START }; throw }
    $pidValue = Get-F2FixtureProcessId -Process $Process
    Write-F2FixtureTrace -Event PROCESS_START_TIME -Status BEGIN -ProcessId $pidValue
    try { $ticks = $Process.StartTime.ToUniversalTime().Ticks; Write-F2FixtureTrace -Event PROCESS_START_TIME -Status COMPLETE -ProcessId $pidValue; return $ticks }
    catch { Write-F2FixtureTrace -Event PROCESS_START_TIME -Status FAILED -ProcessId $pidValue -ErrorClass PROCESS_START_TIME; throw }
}

function Receive-F2FixtureDiagnostic {
    param($Server,$Request,[Diagnostics.Process]$Process,[long]$ChildCreationUtcTicks,[int]$TimeoutSeconds,[int]$PostExitWaitMilliseconds,[int]$RecordTimeoutMilliseconds)
    $pidValue = Get-F2FixtureProcessId -Process $Process
    Write-F2FixtureTrace -Event RECEIVER -Status BEGIN -ProcessId $pidValue
    try {
        $result = Receive-F2UpdateDiagnosticRecord -Server $Server -Request $Request -ChildProcess $Process -ChildCreationUtcTicks $ChildCreationUtcTicks -TimeoutSeconds $TimeoutSeconds -PostExitWaitMilliseconds $PostExitWaitMilliseconds -RecordTimeoutMilliseconds $RecordTimeoutMilliseconds
        $safeStatus = switch ([string]$result.DiagnosticStatus) { 'VALIDATED' {'VALIDATED'} 'INVALID' {'INVALID'} 'MISSING' {'MISSING'} 'CHANNEL_FAILED' {'CHANNEL_FAILED'} 'TIMEOUT' {'TIMEOUT'} default {$null} }
        if ($null -eq $safeStatus) { Write-F2FixtureTrace -Event RECEIVER -Status FAILED -ProcessId $pidValue -ErrorClass UNCLASSIFIED }
        else { Write-F2FixtureTrace -Event RECEIVER -Status $safeStatus -ProcessId $pidValue }
        if ($null -eq $result.ActualChildExitCode) { Write-F2FixtureTrace -Event EXIT_OBSERVATION -Status NOT_OBSERVED -ProcessId $pidValue }
        else { Write-F2FixtureTrace -Event EXIT_OBSERVATION -Status OBSERVED -ProcessId $pidValue -ChildExitCode ([int]$result.ActualChildExitCode) }
        return ,$result
    } catch { Write-F2FixtureTrace -Event RECEIVER -Status FAILED -ProcessId $pidValue -ErrorClass RECEIVER; throw }
}

function Dispose-F2FixtureProcess {
    param([Diagnostics.Process]$Process)
    $pidValue = 0; try { $pidValue = $Process.Id } catch { }
    Write-F2FixtureTrace -Event PROCESS_DISPOSE -Status BEGIN -ProcessId $pidValue
    try { $Process.Dispose(); Write-F2FixtureTrace -Event PROCESS_DISPOSE -Status COMPLETE -ProcessId $pidValue }
    catch { Write-F2FixtureTrace -Event PROCESS_DISPOSE -Status FAILED -ProcessId $pidValue -ErrorClass PROCESS_DISPOSE; throw }
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
[void](Start-F2FixtureTraceCase -CaseId 'CHANNEL_FAILURE')
Write-F2FixtureTrace -Event PIPE_CREATE -Status BEGIN
try{$channelFailureServer=New-F2UpdateDiagnosticServer -Request $channelFailureRequest;Write-F2FixtureTrace -Event PIPE_CREATE -Status COMPLETE}catch{Write-F2FixtureTrace -Event PIPE_CREATE -Status FAILED -ErrorClass PIPE_CREATE;throw}
Write-F2FixtureTrace -Event SERVER_DISPOSE -Status BEGIN
try{$channelFailureServer.Dispose();Write-F2FixtureTrace -Event SERVER_DISPOSE -Status COMPLETE}catch{Write-F2FixtureTrace -Event SERVER_DISPOSE -Status FAILED -ErrorClass SERVER_DISPOSE;throw}
$channelChildStart=New-Object Diagnostics.ProcessStartInfo
$channelChildStart.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$channelChildStart.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 250; exit 7"'
$channelChildStart.UseShellExecute=$false;$channelChildStart.CreateNoWindow=$true
$channelChild=New-F2FixtureProcess -StartInfo $channelChildStart
$channelChildTicks=Start-F2FixtureProcess -Process $channelChild -FailureLabel 'SYNTHETIC_CHANNEL_CHILD_START_FAILED'
$channelFailureResult=Receive-F2FixtureDiagnostic -Server $channelFailureServer -Request $channelFailureRequest -Process $channelChild -ChildCreationUtcTicks $channelChildTicks -TimeoutSeconds 5 -PostExitWaitMilliseconds 250 -RecordTimeoutMilliseconds 1000
Assert-Diagnostic ($channelFailureResult.DiagnosticStatus -ceq 'CHANNEL_FAILED' -and $channelFailureResult.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE' -and $channelFailureResult.ActualChildExitCode -eq 7 -and -not $channelFailureResult.TimedOut) 'diagnostic channel initialization failure remains bounded while retaining the real child exit'
Dispose-F2FixtureProcess -Process $channelChild
Write-F2FixtureTrace -Event SERVER_DISPOSE -Status BEGIN
try{$channelFailureServer.Dispose();Write-F2FixtureTrace -Event SERVER_DISPOSE -Status COMPLETE}catch{Write-F2FixtureTrace -Event SERVER_DISPOSE -Status FAILED -ErrorClass SERVER_DISPOSE;throw}

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
    $process = New-F2FixtureProcess -StartInfo $start
    $ticks=Start-F2FixtureProcess -Process $process -FailureLabel 'SYNTHETIC_WORKER_START_FAILED'
    $expectedProcess=$process;$expectedTicks=$ticks
    if($null -ne $ExpectedChildProcess){$expectedProcess=$ExpectedChildProcess;$expectedPid=Get-F2FixtureProcessId -Process $ExpectedChildProcess;Write-F2FixtureTrace -Event PROCESS_START_TIME -Status BEGIN -ProcessId $expectedPid;try{$expectedTicks=$ExpectedChildProcess.StartTime.ToUniversalTime().Ticks;Write-F2FixtureTrace -Event PROCESS_START_TIME -Status COMPLETE -ProcessId $expectedPid}catch{Write-F2FixtureTrace -Event PROCESS_START_TIME -Status FAILED -ProcessId $expectedPid -ErrorClass PROCESS_START_TIME;throw}}
    $result=Receive-F2FixtureDiagnostic -Server $script:Server -Request $Request -Process $expectedProcess -ChildCreationUtcTicks $expectedTicks -TimeoutSeconds 10 -PostExitWaitMilliseconds 500 -RecordTimeoutMilliseconds 1500
    Write-F2FixtureTrace -Event STDOUT_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $process)
    try{$workerStdout=$process.StandardOutput.ReadToEnd();Write-F2FixtureTrace -Event STDOUT_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $process)}catch{Write-F2FixtureTrace -Event STDOUT_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $process) -ErrorClass STDOUT_DRAIN;throw}
    Write-F2FixtureTrace -Event STDERR_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $process)
    try{$workerStderr=$process.StandardError.ReadToEnd();Write-F2FixtureTrace -Event STDERR_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $process)}catch{Write-F2FixtureTrace -Event STDERR_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $process) -ErrorClass STDERR_DRAIN;throw}
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
    param($Request,[string]$TempRoot,[string]$ProtocolFile,[string]$UpdaterFile,[string]$CandidateFile,[string]$ExpectedUpdaterHash,[string]$ExpectedCandidateHash,[string]$ExpectedStage,[string]$ExpectedCode,[string]$TraceCaseId,[switch]$ExpectMissing)
    Reset-F2FixtureServer -Request $Request -CaseId $TraceCaseId
    $proc=[Diagnostics.Process]::GetCurrentProcess()
    $childScript=New-F2UpdateElevatedChildScript -UpdaterPath $UpdaterFile -CandidatePath $CandidateFile -SourceRoot $TempRoot -ExpectedSourceCommit ('a'*40) -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $ExpectedUpdaterHash -ExpectedCandidateManifestSha256 $ExpectedCandidateHash -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $proc.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $Request -DiagnosticProtocolPath $ProtocolFile -DiagnosticProtocolBytes $protocolBytes
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    if($encoded.Length -gt 32767){throw 'SYNTHETIC_CHILD_COMMAND_TOO_LARGE'}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardError=$true;$start.RedirectStandardOutput=$true
    $child=New-F2FixtureProcess -StartInfo $start
    $ticks=Start-F2FixtureProcess -Process $child -FailureLabel 'SYNTHETIC_PRODUCTION_CHILD_START_FAILED'
    $result=Receive-F2FixtureDiagnostic -Server $script:Server -Request $Request -Process $child -ChildCreationUtcTicks $ticks -TimeoutSeconds 10 -PostExitWaitMilliseconds 300 -RecordTimeoutMilliseconds 1500
    Write-F2FixtureTrace -Event STDOUT_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $child)
    try{$null=$child.StandardOutput.ReadToEnd();Write-F2FixtureTrace -Event STDOUT_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $child)}catch{Write-F2FixtureTrace -Event STDOUT_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $child) -ErrorClass STDOUT_DRAIN;throw}
    Write-F2FixtureTrace -Event STDERR_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $child)
    try{$null=$child.StandardError.ReadToEnd();Write-F2FixtureTrace -Event STDERR_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $child)}catch{Write-F2FixtureTrace -Event STDERR_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $child) -ErrorClass STDERR_DRAIN;throw}
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
    param([string]$UpdaterFile,[string]$CandidateFile,[string]$SourceRoot,[string]$SourceCommit,[string]$PackageHome,[string]$ProgramDataRoot,[string]$ActiveManifestPath,[bool]$ParentAclPass,[string]$ExpectedStage,[string]$ExpectedCode,[string]$TraceCaseId)
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
    Reset-F2FixtureServer -Request $request -CaseId $TraceCaseId
    $childScript=New-F2UpdateElevatedChildScript -UpdaterPath $UpdaterFile -CandidatePath $CandidateFile -SourceRoot $SourceRoot -ExpectedSourceCommit $SourceCommit -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $updaterHash -ExpectedCandidateManifestSha256 $candidateHash -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $requesterProcess.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $request -DiagnosticProtocolPath $protocolPath -DiagnosticProtocolBytes $protocolBytes
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    if($encoded.Length -gt 32767){throw 'SYNTHETIC_CHILD_COMMAND_TOO_LARGE'}
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe';$start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $child=New-F2FixtureProcess -StartInfo $start
    $ticks=Start-F2FixtureProcess -Process $child -FailureLabel 'SYNTHETIC_PRELOCK_CHILD_START_FAILED'
    $result=Receive-F2FixtureDiagnostic -Server $script:Server -Request $request -Process $child -ChildCreationUtcTicks $ticks -TimeoutSeconds 25 -PostExitWaitMilliseconds 500 -RecordTimeoutMilliseconds 5000
    Write-F2FixtureTrace -Event STDOUT_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $child)
    try{$stdout=$child.StandardOutput.ReadToEnd();Write-F2FixtureTrace -Event STDOUT_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $child)}catch{Write-F2FixtureTrace -Event STDOUT_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $child) -ErrorClass STDOUT_DRAIN;throw}
    Write-F2FixtureTrace -Event STDERR_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $child)
    try{$stderr=$child.StandardError.ReadToEnd();Write-F2FixtureTrace -Event STDERR_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $child)}catch{Write-F2FixtureTrace -Event STDERR_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $child) -ErrorClass STDERR_DRAIN;throw}
    $passed=$result.DiagnosticStatus -ceq 'VALIDATED' -and $result.ActualChildExitCode -eq 1 -and $result.Record.Stage -ceq $ExpectedStage -and $result.Record.ErrorCode -ceq $ExpectedCode -and -not $result.TimedOut
    [pscustomobject]@{Passed=[bool]$passed;Request=$request;Result=$result;Process=$child;Stdout=$stdout;Stderr=$stderr;UpdaterSha256=$updaterHash;CandidateSha256=$candidateHash;EncodedLength=$encoded.Length}
}

function Invoke-F2ManifestValidationChildFixture {
    param([byte[]]$CandidateBytes,[string]$ExpectedSourceCommit,[string]$ExpectedStage,[string]$ExpectedCode,[string]$TraceCaseId)
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
    Reset-F2FixtureServer -Request $childRequest -CaseId $TraceCaseId
    $childScript=New-F2UpdateElevatedChildScript -UpdaterPath $updaterFile -CandidatePath $candidateFile -SourceRoot $syntheticRoot -ExpectedSourceCommit $ExpectedSourceCommit -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $updaterSha -ExpectedCandidateManifestSha256 $candidateSha -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $requesterProcess.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $childRequest -DiagnosticProtocolPath $protocolFile -DiagnosticProtocolBytes $protocolBytes
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    if($encoded.Length -gt 32767){throw 'SYNTHETIC_MANIFEST_CHILD_COMMAND_TOO_LARGE'}
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $start.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encoded
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $child=New-F2FixtureProcess -StartInfo $start
    $ticks=Start-F2FixtureProcess -Process $child -FailureLabel 'SYNTHETIC_MANIFEST_CHILD_START_FAILED'
    $result=Receive-F2FixtureDiagnostic -Server $script:Server -Request $childRequest -Process $child -ChildCreationUtcTicks $ticks -TimeoutSeconds 10 -PostExitWaitMilliseconds 300 -RecordTimeoutMilliseconds 1500
    Write-F2FixtureTrace -Event STDOUT_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $child)
    try{$stdout=$child.StandardOutput.ReadToEnd();Write-F2FixtureTrace -Event STDOUT_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $child)}catch{Write-F2FixtureTrace -Event STDOUT_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $child) -ErrorClass STDOUT_DRAIN;throw}
    Write-F2FixtureTrace -Event STDERR_DRAIN -Status BEGIN -ProcessId (Get-F2FixtureProcessId -Process $child)
    try{$stderr=$child.StandardError.ReadToEnd();Write-F2FixtureTrace -Event STDERR_DRAIN -Status COMPLETE -ProcessId (Get-F2FixtureProcessId -Process $child)}catch{Write-F2FixtureTrace -Event STDERR_DRAIN -Status FAILED -ProcessId (Get-F2FixtureProcessId -Process $child) -ErrorClass STDERR_DRAIN;throw}
    $passed=$result.DiagnosticStatus -ceq 'VALIDATED' -and $result.ActualChildExitCode -eq 1 -and $result.Record.Stage -ceq $ExpectedStage -and $result.Record.ErrorCode -ceq $ExpectedCode -and -not $result.TimedOut
    [pscustomobject]@{Passed=[bool]$passed;Result=$result;Process=$child;Stdout=$stdout;Stderr=$stderr;UpdaterSha256=$updaterSha;CandidateSha256=$candidateSha;EncodedLength=$encoded.Length}
}

    Reset-F2FixtureServer -Request $request -CaseId 'DIAGNOSTIC_VALID'
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

    $validManifestChild=Invoke-F2ManifestValidationChildFixture -CandidateBytes $reviewCandidateBytes -ExpectedSourceCommit $reviewCandidate.ReviewedCommitSha -ExpectedStage SourceGitValidation -ExpectedCode UPDATE_SOURCE_GIT_UNAVAILABLE -TraceCaseId MANIFEST_VALID
    Assert-Diagnostic ($validManifestChild.Passed -and $validManifestChild.EncodedLength -le 32767) 'real child process executes the production bootstrap and production manifest loader, passes the exact candidate, then reaches a no-write synthetic updater stub'
    Dispose-F2FixtureProcess -Process $validManifestChild.Process
    $malformedManifestChild=Invoke-F2ManifestValidationChildFixture -CandidateBytes $missingIdentityBytes -ExpectedSourceCommit $reviewCandidate.ReviewedCommitSha -ExpectedStage CandidateManifestValidation -ExpectedCode UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID -TraceCaseId MANIFEST_MALFORMED
    Assert-Diagnostic ($malformedManifestChild.Passed -and $malformedManifestChild.Result.Record.ErrorCode -cne 'UPDATE_UNCLASSIFIED_FAILURE') 'real child process reports malformed-manifest validation failure through the authenticated pipe with a fixed allowlisted code'
    Dispose-F2FixtureProcess -Process $malformedManifestChild.Process

    $prelockUpdaterFixture=Join-Path $syntheticRoot 'production-updater-with-test-entrypoint.ps1'
    $prelockCandidateFixture=Join-Path $syntheticRoot 'prelock-candidate.json'
    $prelockCases=@(
        @{Name='candidate manifest parse';Fault='MalformedCandidate';Stage='CandidateManifestValidation';Code='UPDATE_MANIFEST_JSON_INVALID';ParentPass=$true;TraceCaseId='PRELOCK_CANDIDATE_PARSE'},
        @{Name='candidate manifest missing required identity field';Fault='MissingIdentity';Stage='CandidateManifestValidation';Code='UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID';ParentPass=$true;TraceCaseId='PRELOCK_CANDIDATE_IDENTITY'},
        @{Name='candidate manifest';Fault='WrongPackageRoot';Stage='CandidateManifestValidation';Code='UPDATE_CANDIDATE_PACKAGE_ROOT_MISMATCH';ParentPass=$true;TraceCaseId='PRELOCK_CANDIDATE_ROOT'},
        @{Name='source Git';Fault='WrongOrigin';Stage='SourceGitValidation';Code='UPDATE_SOURCE_ORIGIN_MISMATCH';ParentPass=$true;TraceCaseId='PRELOCK_SOURCE_GIT'},
        @{Name='source package pin';Fault='WrongPackagePin';Stage='SourcePackagePinValidation';Code='UPDATE_SOURCE_PACKAGE_HASH_MISMATCH';ParentPass=$true;TraceCaseId='PRELOCK_CANDIDATE_PIN'},
        @{Name='parent ACL';Fault='ParentReject';Stage='ParentAclValidation';Code='UPDATE_PARENT_CHAIN_UNSAFE';ParentPass=$false;TraceCaseId='PRELOCK_PARENT_ACL'},
        @{Name='installed v2';Fault='CorruptOldFile';Stage='InstalledV2Validation';Code='UPDATE_FILE_HASH_MISMATCH';ParentPass=$true;TraceCaseId='PRELOCK_OLD_RELEASE'},
        @{Name='transaction collision';Fault='BadLockBytes';Stage='TransactionCollisionValidation';Code='UPDATE_FILE_TYPE_OR_SIZE_INVALID';ParentPass=$true;TraceCaseId='PRELOCK_TRANSACTION_COLLISION'}
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
        $childCase=Invoke-PrelockProductionChildFixture -UpdaterFile $prelockUpdaterFixture -CandidateFile $prelockCandidateFixture -SourceRoot $prelockSource.Root -SourceCommit $prelockSource.Commit -PackageHome $installTree.PackageHome -ProgramDataRoot $installTree.ProgramDataRoot -ActiveManifestPath $installTree.ActiveManifestPath -ParentAclPass $prelockCase.ParentPass -ExpectedStage $prelockCase.Stage -ExpectedCode $prelockCase.Code -TraceCaseId $prelockCase.TraceCaseId
        if($prelockCase.Fault -eq 'WrongOrigin'){
            & $fixtureGit.Source -C $prelockSource.Root remote set-url origin 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
            if($LASTEXITCODE -ne 0){throw 'SYNTHETIC_SOURCE_GIT_REMOTE_RESTORE_FAILED'}
        }
        $recordNames=if($null -ne $childCase.Result.Record){@($childCase.Result.Record.PSObject.Properties|ForEach-Object Name)}else{@()}
        $expectedRecordNames=@('Schema','Authority','RequestId','Nonce','SourceCommit','LauncherSha256','UpdaterSha256','CandidateManifestSha256','RequesterPid','RequesterCreationUtcTicks','RequesterSidSha256','ChildPid','ChildCreationUtcTicks','ChildExitCode','Stage','ErrorCode')
        $recordShape=$recordNames.Count -eq $expectedRecordNames.Count -and @(Compare-Object $expectedRecordNames $recordNames -CaseSensitive).Count -eq 0
        $safeRecord=$childCase.Passed -and $childCase.Result.Record.Authority -ceq 'NON_AUTHORITATIVE_DIAGNOSTIC' -and $childCase.Result.Record.Stage -ceq $prelockCase.Stage -and $childCase.Result.Record.ErrorCode -ceq $prelockCase.Code -and $recordShape -and $childCase.Stdout.Length -le 4096 -and $childCase.Stderr.Length -le 4096
        if(-not $safeRecord){Write-Host 'PRELOCK_CASE=FAIL;ErrorClass=RESULT_SHAPE_MISMATCH'}
        Assert-Diagnostic $safeRecord ("production child builder and authenticated pipe report {0} failure as {1}/{2} in the fixed sanitized schema" -f $prelockCase.Name,$prelockCase.Stage,$prelockCase.Code)
        $noTransactionRoots= -not [IO.Directory]::Exists((Join-Path $installTree.PackageHome 'releases')) -and -not [IO.Directory]::Exists((Join-Path $installTree.ProgramDataRoot 'updates')) -and -not [IO.Directory]::Exists((Join-Path $installTree.ProgramDataRoot 'backups'))
        if($prelockCase.Fault -eq 'BadLockBytes'){$noTransactionRoots=$noTransactionRoots -and [IO.File]::ReadAllText((Join-Path $installTree.ProgramDataRoot 'release.lock')) -ceq 'non-empty synthetic collision'}else{$noTransactionRoots=$noTransactionRoots -and -not [IO.File]::Exists((Join-Path $installTree.ProgramDataRoot 'release.lock'))}
        Assert-Diagnostic $noTransactionRoots ("{0} failure preserves the TEMP-only old release and creates no transaction objects" -f $prelockCase.Name)
        Dispose-F2FixtureProcess -Process $childCase.Process
    }
    $fixtureUpdaterText=New-SyntheticUpdaterText -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_GIT_UNAVAILABLE'
    $fixtureUpdaterBytes=[Text.UTF8Encoding]::new($false).GetBytes($fixtureUpdaterText)
    [IO.File]::WriteAllBytes($updaterFixture,$fixtureUpdaterBytes)
    $fixtureUpdaterHash=Get-F2UpdateDiagnosticSha256 -Bytes $fixtureUpdaterBytes

    $validChildRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $fixtureUpdaterHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    [IO.File]::WriteAllBytes($badProtocolFixture,[Text.Encoding]::UTF8.GetBytes('Set-StrictMode -Version Latest'))
    $bootstrapChild=Invoke-ProductionChildFixture -Request $validChildRequest -TempRoot $syntheticRoot -ProtocolFile $badProtocolFixture -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $fixtureUpdaterHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage '' -ExpectedCode '' -TraceCaseId PROTOCOL_BOOTSTRAP_FAILURE -ExpectMissing
    Assert-Diagnostic ($bootstrapChild.Passed -and $bootstrapChild.Result.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_MISSING' -and $bootstrapChild.Result.ActualChildExitCode -eq 1) 'real child script retains exact exit when protocol bootstrap fails before a trusted sender is available'
    Dispose-F2FixtureProcess -Process $bootstrapChild.Process

    $hashRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $fixtureUpdaterHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $hashChild=Invoke-ProductionChildFixture -Request $hashRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash ('f'*64) -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage 'UpdaterAndCandidateHashValidation' -ExpectedCode 'UPDATE_UPDATER_HASH_MISMATCH' -TraceCaseId UPDATER_HASH_FAILURE
    Assert-Diagnostic $hashChild.Passed 'real child script reports updater hash validation failure through the pipe'
    Dispose-F2FixtureProcess -Process $hashChild.Process

    $invalidUpdaterBytes=[Text.UTF8Encoding]::new($false).GetBytes('function This-Script-Is-Not-Closed {')
    [IO.File]::WriteAllBytes($updaterFixture,$invalidUpdaterBytes)
    $invalidUpdaterHash=Get-F2UpdateDiagnosticSha256 -Bytes $invalidUpdaterBytes
    $parseRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $invalidUpdaterHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $parseChild=Invoke-ProductionChildFixture -Request $parseRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $invalidUpdaterHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage 'UpdaterScriptLoading' -ExpectedCode 'UPDATE_UPDATER_SCRIPT_LOAD_FAILED' -TraceCaseId UPDATER_PARSE_FAILURE
    Assert-Diagnostic $parseChild.Passed 'real child script reports updater parsing/loading failure through the pipe'
    Dispose-F2FixtureProcess -Process $parseChild.Process

    $identityBytes=[Text.UTF8Encoding]::new($false).GetBytes((New-SyntheticUpdaterText -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_GIT_UNAVAILABLE' -IdentityFailure))
    [IO.File]::WriteAllBytes($updaterFixture,$identityBytes)
    $identityHash=Get-F2UpdateDiagnosticSha256 -Bytes $identityBytes
    $identityRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $identityHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    $identityChild=Invoke-ProductionChildFixture -Request $identityRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $identityHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage 'ElevatedIdentityValidation' -ExpectedCode 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH' -TraceCaseId IDENTITY_FAILURE
    Assert-Diagnostic $identityChild.Passed 'real child script reports identity validation failure without invoking transaction code'
    Dispose-F2FixtureProcess -Process $identityChild.Process

    $invokeCases=@(
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_SOURCE_GIT_UNAVAILABLE';Name='source Git resolution';TraceCaseId='INVOKE_SOURCE_GIT'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_PROGRAM_FILES_PARENT_DACL_UNSAFE';Name='parent ACL validation';TraceCaseId='INVOKE_PARENT_ACL'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_OLD_RELEASE_PIN_MISMATCH';Name='old installed-release validation';TraceCaseId='INVOKE_OLD_RELEASE'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_NATIVE_HELPER_COMPILE_FAILED';Name='native helper compilation';TraceCaseId='INVOKE_NATIVE_HELPER'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_RELEASE_LOCK_CREATE_FAILED';Name='initial release-lock creation';TraceCaseId='INVOKE_RELEASE_LOCK'}
    )
    foreach($invokeCase in $invokeCases){
        $fixtureBytes=[Text.UTF8Encoding]::new($false).GetBytes((New-SyntheticUpdaterText -Stage $invokeCase.Stage -Code $invokeCase.Code))
        [IO.File]::WriteAllBytes($updaterFixture,$fixtureBytes)
        $fixtureHash=Get-F2UpdateDiagnosticSha256 -Bytes $fixtureBytes
        $caseRequest=New-F2UpdateDiagnosticRequest -SourceCommit $commitFixture -LauncherSha256 ('b'*64) -UpdaterSha256 $fixtureHash -CandidateManifestSha256 $candidateFixtureHash -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
        $childCase=Invoke-ProductionChildFixture -Request $caseRequest -TempRoot $syntheticRoot -ProtocolFile $protocolPath -UpdaterFile $updaterFixture -CandidateFile $candidateFixture -ExpectedUpdaterHash $fixtureHash -ExpectedCandidateHash $candidateFixtureHash -ExpectedStage $invokeCase.Stage -ExpectedCode $invokeCase.Code -TraceCaseId $invokeCase.TraceCaseId
        Assert-Diagnostic $childCase.Passed ("real production child reports synthetic failure for {0}" -f $invokeCase.Name)
        Dispose-F2FixtureProcess -Process $childCase.Process
    }

    $sizeProbe=New-F2UpdateElevatedChildScript -UpdaterPath $updaterFixture -CandidatePath $candidateFixture -SourceRoot $syntheticRoot -ExpectedSourceCommit $commitFixture -ExpectedLauncherSha256 ('b'*64) -ExpectedUpdaterSha256 $fixtureHash -ExpectedCandidateManifestSha256 $candidateFixtureHash -ExpectedRequesterSid $sid -RequesterLauncherProcessId $PID -RequesterLauncherCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -DiagnosticRequest $caseRequest -DiagnosticProtocolPath $protocolPath -DiagnosticProtocolBytes $protocolBytes
    $encodedSize=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($sizeProbe)).Length
    Assert-Diagnostic ($encodedSize + 100 -lt 32767) 'production child command and fixed PowerShell arguments stay below the Windows command-line limit'
    Write-Output ('ProductionChildEncodedCommandCharacters='+$encodedSize+';FixedArgumentReserve=100;Limit=32767')

    $cases = @(
        @{Stage='ChildBootstrapInitialization';Code='UPDATE_CHILD_BOOTSTRAP_INITIALIZATION_FAILED';TraceCaseId='DIAGNOSTIC_BOOTSTRAP'},
        @{Stage='UpdaterScriptLoading';Code='UPDATE_UPDATER_SCRIPT_LOAD_FAILED';TraceCaseId='DIAGNOSTIC_SCRIPT_LOADING'},
        @{Stage='ElevatedIdentityValidation';Code='UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH';TraceCaseId='DIAGNOSTIC_IDENTITY'},
        @{Stage='UpdaterAndCandidateHashValidation';Code='UPDATE_UPDATER_HASH_MISMATCH';TraceCaseId='DIAGNOSTIC_HASH'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_SOURCE_GIT_UNAVAILABLE';TraceCaseId='DIAGNOSTIC_SOURCE_GIT'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_PROGRAM_FILES_PARENT_DACL_UNSAFE';TraceCaseId='DIAGNOSTIC_PARENT_ACL'},
        @{Stage='CandidateAndSourceValidation';Code='UPDATE_OLD_RELEASE_PIN_MISMATCH';TraceCaseId='DIAGNOSTIC_OLD_RELEASE'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_NATIVE_HELPER_COMPILE_FAILED';TraceCaseId='DIAGNOSTIC_NATIVE_HELPER'},
        @{Stage='AcquireReleaseBarrier';Code='UPDATE_RELEASE_LOCK_CREATE_FAILED';TraceCaseId='DIAGNOSTIC_RELEASE_LOCK'}
    )
    foreach($case in $cases){
        $one=New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
        Reset-F2FixtureServer -Request $one -CaseId $case.TraceCaseId
        $worker=Invoke-SyntheticDiagnosticWorker -Request $one -Stage $case.Stage -Code $case.Code
        $ok=$worker.Result.DiagnosticStatus -ceq 'VALIDATED' -and $worker.Result.Record.Stage -ceq $case.Stage -and $worker.Result.Record.ErrorCode -ceq $case.Code -and $worker.Result.ActualChildExitCode -eq 1 -and -not $worker.Result.TimedOut
        Assert-Diagnostic $ok ("cross-process report preserves {0}/{1} with child exit 1" -f $case.Stage,$case.Code)
        Dispose-F2FixtureProcess -Process $worker.Process
    }

    foreach($negative in @(
        @{Name='stale or replayed nonce';Args=@{WrongRequest=$true};Expected='INVALID';TraceCaseId='DIAGNOSTIC_BAD_NONCE'},
        @{Name='tampered payload digest';Args=@{Tamper=$true};Expected='INVALID';TraceCaseId='DIAGNOSTIC_TAMPERED'},
        @{Name='unlisted diagnostic stage';Args=@{UnknownStage=$true};Expected='INVALID';TraceCaseId='DIAGNOSTIC_UNKNOWN_STAGE'},
        @{Name='duplicate diagnostic frame';Args=@{Duplicate=$true};Expected='INVALID';TraceCaseId='DIAGNOSTIC_DUPLICATE'},
        @{Name='oversized frame';Args=@{Oversize=$true};Expected='INVALID';TraceCaseId='DIAGNOSTIC_OVERSIZE'},
        @{Name='unavailable diagnostic record';Args=@{Stage='NO_MESSAGE'};Expected='MISSING';TraceCaseId='DIAGNOSTIC_MISSING'},
        @{Name='stalled partial frame';Args=@{Stall=$true};Expected='INVALID';TraceCaseId='DIAGNOSTIC_STALL'}
    )){
        $one=New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
        Reset-F2FixtureServer -Request $one -CaseId $negative.TraceCaseId
        $negativeArgs = $negative.Args
        $worker=Invoke-SyntheticDiagnosticWorker -Request $one @negativeArgs
        Assert-Diagnostic ($worker.Result.DiagnosticStatus -ceq $negative.Expected -and $worker.Result.ActualChildExitCode -eq 1) ("rejects {0} while retaining child exit (status={1};code={2};exit={3})" -f $negative.Name,$worker.Result.DiagnosticStatus,$worker.Result.DiagnosticErrorCode,$worker.Result.ActualChildExitCode)
        Dispose-F2FixtureProcess -Process $worker.Process
    }

    $exitMismatch = New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    Reset-F2FixtureServer -Request $exitMismatch -CaseId CHILD_EXIT_MISMATCH
    $exitMismatchWorker=Invoke-SyntheticDiagnosticWorker -Request $exitMismatch -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_GIT_UNAVAILABLE' -ExitCode 2 -RecordExitCode 1
    Assert-Diagnostic ($exitMismatchWorker.Result.DiagnosticStatus -ceq 'INVALID' -and $exitMismatchWorker.Result.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH' -and $exitMismatchWorker.Result.ActualChildExitCode -eq 2 -and $null -eq $exitMismatchWorker.Result.Record) 'rejects a diagnostic claim that conflicts with the independently observed child exit'
    Dispose-F2FixtureProcess -Process $exitMismatchWorker.Process

    $falseSuccessRequest = New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    Reset-F2FixtureServer -Request $falseSuccessRequest -CaseId FALSE_SUCCESS
    $falseSuccessWorker=Invoke-SyntheticDiagnosticWorker -Request $falseSuccessRequest -Stage 'Complete' -Code 'NONE' -ExitCode 1 -RecordExitCode 0
    Assert-Diagnostic ($falseSuccessWorker.Result.DiagnosticStatus -ceq 'INVALID' -and $falseSuccessWorker.Result.ActualChildExitCode -eq 1 -and $null -eq $falseSuccessWorker.Result.Record) 'rejects a forged Complete/zero diagnostic when the observed child actually failed'
    Dispose-F2FixtureProcess -Process $falseSuccessWorker.Process

    $badPid = New-F2UpdateDiagnosticRequest -SourceCommit $request.SourceCommit -LauncherSha256 $request.LauncherSha256 -UpdaterSha256 $request.UpdaterSha256 -CandidateManifestSha256 $request.CandidateManifestSha256 -RequesterPid $PID -RequesterCreationUtcTicks $requester.StartTime.ToUniversalTime().Ticks -RequesterSid $sid
    Reset-F2FixtureServer -Request $badPid -CaseId WRONG_CLIENT
    $targetStart=New-Object Diagnostics.ProcessStartInfo
    $targetStart.FileName=(Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
    $targetStart.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 5000; exit 1"'
    $targetStart.UseShellExecute=$false;$targetStart.CreateNoWindow=$true;$targetStart.RedirectStandardOutput=$true;$targetStart.RedirectStandardError=$true
    $target=New-F2FixtureProcess -StartInfo $targetStart
    [void](Start-F2FixtureProcess -Process $target -FailureLabel 'SYNTHETIC_EXPECTED_PROCESS_START_FAILED')
    $wrongWorker=Invoke-SyntheticDiagnosticWorker -Request $badPid -Stage 'CandidateAndSourceValidation' -Code 'UPDATE_SOURCE_COMMIT_MISMATCH' -ExpectedChildProcess $target
    $wrongClientPass = $wrongWorker.Result.DiagnosticStatus -ceq 'INVALID' -and $wrongWorker.Result.DiagnosticErrorCode -ceq 'UPDATE_DIAGNOSTIC_IDENTITY_MISMATCH' -and $wrongWorker.Result.ActualChildExitCode -eq 1
    if (-not $wrongClientPass) { Write-Host 'WrongClientResult=FAIL;ErrorClass=ASSERTION_FAILED' }
    Assert-Diagnostic $wrongClientPass 'rejects a distinct connected process while retaining the independently observed target exit'
    Dispose-F2FixtureProcess -Process $wrongWorker.Process;Dispose-F2FixtureProcess -Process $target
}
finally {
    if($null -ne $script:Server){Write-F2FixtureTrace -Event SERVER_DISPOSE -Status BEGIN;try{$script:Server.Dispose();$script:Server=$null;Write-F2FixtureTrace -Event SERVER_DISPOSE -Status COMPLETE}catch{Write-F2FixtureTrace -Event SERVER_DISPOSE -Status FAILED -ErrorClass SERVER_DISPOSE;throw}}
    if($null -ne $syntheticRoot -and [IO.Path]::GetFullPath($syntheticRoot).StartsWith(([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($syntheticRoot) -match '^F2G1-Diagnostic-Test-[0-9a-f]{32}$'){
        $tempItem=Get-Item -LiteralPath $syntheticRoot -Force -ErrorAction SilentlyContinue
        if($null -ne $tempItem -and ($tempItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){[void](Start-F2FixtureTraceCase -CaseId TEMP_CLEANUP);Write-F2FixtureTrace -Event TEMP_CLEANUP -Status BEGIN;try{Remove-Item -LiteralPath $syntheticRoot -Recurse -Force -ErrorAction Stop;Write-F2FixtureTrace -Event TEMP_CLEANUP -Status COMPLETE}catch{Write-F2FixtureTrace -Event TEMP_CLEANUP -Status FAILED -ErrorClass TEMP_CLEANUP;throw}}
        elseif($null -eq $tempItem){[void](Start-F2FixtureTraceCase -CaseId TEMP_CLEANUP);Write-F2FixtureTrace -Event TEMP_CLEANUP -Status SKIPPED}
        else{[void](Start-F2FixtureTraceCase -CaseId TEMP_CLEANUP);Write-F2FixtureTrace -Event TEMP_CLEANUP -Status REPARSE_BLOCKED}
    }
}

Write-Output ('Assertions=' + $script:Assertions + ';Failures=' + $script:Failures.Count)
if($script:Failures.Count -gt 0){exit 1}
exit 0

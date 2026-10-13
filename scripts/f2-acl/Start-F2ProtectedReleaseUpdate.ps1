Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:F2UpdateDiagnosticProtocolSha256 = '66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'

function Get-F2UpdateLauncherSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2UpdateLauncherSafeErrorCode {
    param([AllowNull()][string]$Code)
    $approvedCodes = @(
        'UPDATE_RECOVERY_TRANSACTION_ID_REQUIRED','UPDATE_REQUESTER_MUST_BE_STANDARD_TOKEN',
        'UPDATE_REQUESTER_IDENTITY_UNVERIFIABLE','UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN',
        'UPDATE_REPARSE_INPUT_REJECTED','UPDATE_SOURCE_COMMIT_MISMATCH','UPDATE_SOURCE_ORIGIN_MISMATCH',
        'UPDATE_SOURCE_WORKTREE_NOT_CLEAN','UPDATE_DIAGNOSTIC_PROTOCOL_SIZE_INVALID',
        'UPDATE_DIAGNOSTIC_PROTOCOL_HASH_MISMATCH','UPDATE_DIAGNOSTIC_PROTOCOL_PARSE_FAILED',
        'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE','UPDATE_INPUT_TYPE_OR_SIZE_INVALID',
        'UPDATE_UPDATER_HASH_MISMATCH','UPDATE_CANDIDATE_HASH_MISMATCH',
        'UPDATE_CANDIDATE_IDENTITY_MISMATCH','WINDOWS_POWERSHELL_51_UNAVAILABLE',
        'UPDATE_ELEVATED_BOOTSTRAP_SCRIPT_PARSE_FAILED'
    )
    if ($Code -cin $approvedCodes) { return $Code }
    return 'UPDATE_UNCLASSIFIED_FAILURE'
}

function New-F2UpdateLauncherDiagnosticServer {
    param([Parameter(Mandatory)]$Request)
    try { return New-F2UpdateDiagnosticServer -Request $Request }
    catch { throw 'UPDATE_DIAGNOSTIC_CHANNEL_FAILURE' }
}

function New-F2UpdateElevatedChildScript {
    param(
        [Parameter(Mandatory)][string]$UpdaterPath,
        [Parameter(Mandatory)][string]$CandidatePath,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedLauncherSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedUpdaterSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedCandidateManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^S-1-[0-9]+(-[0-9]+)+$')][string]$ExpectedRequesterSid,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$RequesterLauncherProcessId,
        [Parameter(Mandatory)][ValidateRange(1,9223372036854775807)][long]$RequesterLauncherCreationUtcTicks,
        [Parameter(Mandatory)]$DiagnosticRequest,
        [Parameter(Mandatory)][string]$DiagnosticProtocolPath,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$DiagnosticProtocolBytes,
        [ValidatePattern('^(?:[0-9a-f]{32})?$')][string]$RecoveryTransactionId='',
        [switch]$ResumeForward
    )
    $requestWire = [ordered]@{}
    foreach ($name in @('Schema','RequestId','Nonce','PipeName','SourceCommit','LauncherSha256','UpdaterSha256','CandidateManifestSha256','RequesterPid','RequesterCreationUtcTicks','RequesterSidSha256')) { $requestWire[$name] = $DiagnosticRequest.$name }
    $requestB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $requestWire -Depth 3 -Compress)))
    if ((Get-F2UpdateLauncherSha256 -Bytes $DiagnosticProtocolBytes) -cne $script:F2UpdateDiagnosticProtocolSha256) { throw 'UPDATE_DIAGNOSTIC_PROTOCOL_HASH_MISMATCH' }
    $resumeLiteral = if ($ResumeForward.IsPresent) { '$true' } else { '$false' }
    $childScript = @'
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$updaterPath='__UPDATER_PATH__'
$candidatePath='__CANDIDATE_PATH__'
$sourceRoot='__SOURCE_ROOT__'
$expectedSourceCommit='__SOURCE_COMMIT__'
$expectedUpdater='__UPDATER_SHA__'
$expectedLauncher='__LAUNCHER_SHA__'
$expectedCandidate='__CANDIDATE_SHA__'
$expectedDiagnosticProtocol='__DIAGNOSTIC_PROTOCOL_SHA__'
$expectedRequesterSid='__REQUESTER_SID__'
$requesterLauncherPid=__REQUESTER_LAUNCHER_PID__
$requesterLauncherCreationUtcTicks=__REQUESTER_LAUNCHER_CREATION_TICKS__
$recoveryTransactionId='__RECOVERY_TRANSACTION_ID__'
$resumeForward=__RESUME_FORWARD__
$diagnosticProtocolPath='__DIAGNOSTIC_PROTOCOL_PATH__'
$diagRequestB64='__DIAGNOSTIC_REQUEST_B64__'
$diagStage='ChildBootstrapInitialization'
$diagCode='UPDATE_CHILD_BOOTSTRAP_INITIALIZATION_FAILED'
$childExitCode=1
$diagRequest=$null
function Get-ChildSha([byte[]]$Bytes){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Test-ChildNoReparse([string]$Path){$current=[IO.Path]::GetFullPath($Path);while(-not [string]::IsNullOrEmpty($current)){if([IO.File]::Exists($current)-or[IO.Directory]::Exists($current)){$item=Get-Item -LiteralPath $current -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'UPDATE_REPARSE_INPUT_REJECTED'}};$parent=[IO.Directory]::GetParent($current);if($null -eq $parent){break};$current=$parent.FullName}}
try {
  Test-ChildNoReparse $diagnosticProtocolPath
  $protocolBytes=[IO.File]::ReadAllBytes($diagnosticProtocolPath)
  if((Get-ChildSha $protocolBytes) -cne $expectedDiagnosticProtocol){throw 'UPDATE_DIAGNOSTIC_PROTOCOL_HASH_MISMATCH'}
  $protocolText=[Text.UTF8Encoding]::new($false,$true).GetString($protocolBytes)
  . ([scriptblock]::Create($protocolText))
  $diagRequest=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($diagRequestB64)) | ConvertFrom-Json -ErrorAction Stop
  $diagStage='UpdaterAndCandidateHashValidation';$diagCode='UPDATE_CANDIDATE_MANIFEST_INVALID'
  Test-ChildNoReparse $updaterPath;Test-ChildNoReparse $candidatePath
  $updaterItem=Get-Item -LiteralPath $updaterPath -Force -ErrorAction Stop
  $candidateItem=Get-Item -LiteralPath $candidatePath -Force -ErrorAction Stop
  if($updaterItem.PSIsContainer-or$updaterItem.Length-gt 4194304-or$candidateItem.PSIsContainer-or$candidateItem.Length-lt 1-or$candidateItem.Length-gt 65536){throw 'UPDATE_INPUT_TYPE_OR_SIZE_INVALID'}
  $updaterBytes=[IO.File]::ReadAllBytes($updaterPath)
  if((Get-ChildSha $updaterBytes) -cne $expectedUpdater){throw 'UPDATE_UPDATER_HASH_MISMATCH'}
  $candidateBytes=[IO.File]::ReadAllBytes($candidatePath)
  if((Get-ChildSha $candidateBytes) -cne $expectedCandidate){throw 'UPDATE_CANDIDATE_HASH_MISMATCH'}
  $diagStage='UpdaterScriptLoading';$diagCode='UPDATE_UPDATER_SCRIPT_LOAD_FAILED'
  $text=[Text.UTF8Encoding]::new($false,$true).GetString($updaterBytes)
  try{$verifiedScript=[scriptblock]::Create($text)}catch{throw 'UPDATE_UPDATER_SCRIPT_LOAD_FAILED'}
  try{. $verifiedScript}catch{throw 'UPDATE_UPDATER_SCRIPT_LOAD_FAILED'}
  $diagStage='ElevatedIdentityValidation';$diagCode='UPDATE_ELEVATED_REQUESTER_IDENTITY_UNVERIFIABLE'
  Test-F2UpdateElevationIdentity -ExpectedRequesterSid $expectedRequesterSid | Out-Null
  $diagStage='UpdaterAndCandidateHashValidation';$diagCode='UPDATE_CANDIDATE_MANIFEST_INVALID'
  $parsedCandidate=Get-F2UpdateManifestObject -Bytes $candidateBytes -ExpectedSchema v3 -ExpectedHash $expectedCandidate
  if($parsedCandidate.ReviewedCommitSha -cne $expectedSourceCommit){throw 'UPDATE_CANDIDATE_COMMIT_MISMATCH'}
  $diagStage='UpdaterInvocation';$diagCode='UPDATE_UNCLASSIFIED_FAILURE'
  if(-not [string]::IsNullOrWhiteSpace($recoveryTransactionId)){
    $result=Invoke-F2ProtectedReleaseRecovery -CandidateManifestBytes $candidateBytes -CandidateManifestSha256 $expectedCandidate -ExpectedUpdaterSha256 $expectedUpdater -ExpectedLauncherSha256 $expectedLauncher -SourceRoot $sourceRoot -ExpectedRequesterSid $expectedRequesterSid -RequesterLauncherProcessId ([int]$requesterLauncherPid) -RequesterLauncherCreationUtcTicks ([long]$requesterLauncherCreationUtcTicks) -TransactionId $recoveryTransactionId -ResumeForward:$resumeForward
  }else{
    $result=Invoke-F2ProtectedReleaseUpdate -CandidateManifestBytes $candidateBytes -CandidateManifestSha256 $expectedCandidate -ExpectedUpdaterSha256 $expectedUpdater -ExpectedLauncherSha256 $expectedLauncher -SourceRoot $sourceRoot -ExpectedRequesterSid $expectedRequesterSid -RequesterLauncherProcessId ([int]$requesterLauncherPid) -RequesterLauncherCreationUtcTicks ([long]$requesterLauncherCreationUtcTicks)
  }
  if($result.Success){$diagStage='Complete';$diagCode='NONE';$childExitCode=0}else{$diagStage=Normalize-F2UpdateDiagnosticStage -Stage ([string]$result.Stage);$diagCode=Normalize-F2UpdateDiagnosticCode -Code ([string]$result.ErrorCode) -Stage $diagStage -ExceptionType ([string]$result.FailureType);$childExitCode=1}
} catch {
  $exceptionType=$_.Exception.GetType().FullName
  $diagCode=Normalize-F2UpdateDiagnosticCode -Code ([string]$_.Exception.Message) -Stage $diagStage -ExceptionType $exceptionType
  $childExitCode=1
} finally {
  if($null -ne $diagRequest -and (Get-Command Send-F2UpdateDiagnosticRecord -ErrorAction SilentlyContinue)){
    try{$null=Send-F2UpdateDiagnosticRecord -Request $diagRequest -Stage $diagStage -ErrorCode $diagCode -ChildExitCode $childExitCode -ConnectTimeoutMilliseconds 3000}catch{}
  }
}
exit $childExitCode
'@
    return $childScript.Replace('__UPDATER_PATH__',$UpdaterPath).Replace('__CANDIDATE_PATH__',$CandidatePath).Replace('__SOURCE_ROOT__',$SourceRoot).Replace('__SOURCE_COMMIT__',$ExpectedSourceCommit).Replace('__UPDATER_SHA__',$ExpectedUpdaterSha256).Replace('__LAUNCHER_SHA__',$ExpectedLauncherSha256).Replace('__CANDIDATE_SHA__',$ExpectedCandidateManifestSha256).Replace('__DIAGNOSTIC_PROTOCOL_SHA__',$script:F2UpdateDiagnosticProtocolSha256).Replace('__REQUESTER_SID__',$ExpectedRequesterSid).Replace('__REQUESTER_LAUNCHER_PID__',[string]$RequesterLauncherProcessId).Replace('__REQUESTER_LAUNCHER_CREATION_TICKS__',[string]$RequesterLauncherCreationUtcTicks).Replace('__RECOVERY_TRANSACTION_ID__',[string]$RecoveryTransactionId).Replace('__RESUME_FORWARD__',$resumeLiteral).Replace('__DIAGNOSTIC_PROTOCOL_PATH__',$DiagnosticProtocolPath.Replace("'","''")).Replace('__DIAGNOSTIC_REQUEST_B64__',$requestB64)
}

function Invoke-F2ProtectedReleaseUpdateLauncher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedSourceCommit,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedLauncherSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedUpdaterSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedCandidateManifestSha256,
        [ValidatePattern('^[0-9a-f]{32}$')][string]$RecoveryTransactionId,
        [switch]$ResumeForward
    )
    $elevationStarted = $false
    $uacLaunchAttempted = $false
    $child = $null
    $diagnosticServer = $null
    $diagnosticRequest = $null
    $diagnosticProtocolBytes = $null
    $parentStage = 'RequesterPreflight'
    try {
        if ($ResumeForward -and [string]::IsNullOrWhiteSpace($RecoveryTransactionId)) { throw 'UPDATE_RECOVERY_TRANSACTION_ID_REQUIRED' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'UPDATE_REQUESTER_MUST_BE_STANDARD_TOKEN' }
        $requesterSid = [string]$identity.User.Value
        $identity.Dispose()
        if ($requesterSid -notmatch '^S-1-[0-9]+(-[0-9]+)+$') { throw 'UPDATE_REQUESTER_IDENTITY_UNVERIFIABLE' }
        $requesterLauncherPid = [int]$PID
        try {
            $requesterProcess = @(Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId=' + $requesterLauncherPid) -ErrorAction Stop)
            if ($requesterProcess.Count -ne 1 -or $requesterProcess[0].Name -cne 'powershell.exe' -or $null -eq $requesterProcess[0].CreationDate) { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
            $requesterLauncherCreationUtcTicks = ([datetime]$requesterProcess[0].CreationDate).ToUniversalTime().Ticks
        } catch { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }

        $sourceRoot = 'C:\Dev\f2-g1-protected-updater-source'
        $reviewRoot = 'C:\Dev\f2-g1-protected-updater'
        $updaterPath = Join-Path $sourceRoot 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'
        $diagnosticProtocolPath = Join-Path $sourceRoot 'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1'
        $candidatePath = Join-Path $reviewRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
        foreach ($path in @($sourceRoot,$updaterPath,$diagnosticProtocolPath,$reviewRoot,$candidatePath)) {
            $current = [IO.Path]::GetFullPath($path)
            while (-not [string]::IsNullOrEmpty($current)) {
                if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
                    $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'UPDATE_REPARSE_INPUT_REJECTED' }
                }
                $parent = [IO.Directory]::GetParent($current)
                if ($null -eq $parent) { break }
                $current = $parent.FullName
            }
        }
        $git = Get-Command git.exe -ErrorAction Stop
        $head = (& $git.Source -C $sourceRoot rev-parse HEAD 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $head -cne $ExpectedSourceCommit) { throw 'UPDATE_SOURCE_COMMIT_MISMATCH' }
        $origin = (& $git.Source -C $sourceRoot remote get-url origin 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $origin -cne 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git') { throw 'UPDATE_SOURCE_ORIGIN_MISMATCH' }
        $status = @(& $git.Source -C $sourceRoot status --porcelain --untracked-files=all 2>$null)
        if ($LASTEXITCODE -ne 0 -or $status.Count -ne 0) { throw 'UPDATE_SOURCE_WORKTREE_NOT_CLEAN' }

        $parentStage = 'DiagnosticProtocolValidation'
        $protocolItem = Get-Item -LiteralPath $diagnosticProtocolPath -Force -ErrorAction Stop
        if ($protocolItem.PSIsContainer -or $protocolItem.Length -lt 1 -or $protocolItem.Length -gt 262144) { throw 'UPDATE_DIAGNOSTIC_PROTOCOL_SIZE_INVALID' }
        $diagnosticProtocolBytes = [IO.File]::ReadAllBytes($diagnosticProtocolPath)
        if ((Get-F2UpdateLauncherSha256 -Bytes $diagnosticProtocolBytes) -cne $script:F2UpdateDiagnosticProtocolSha256) { throw 'UPDATE_DIAGNOSTIC_PROTOCOL_HASH_MISMATCH' }
        $diagnosticProtocolText = [Text.UTF8Encoding]::new($false,$true).GetString($diagnosticProtocolBytes)
        $diagTokens=$null;$diagParseErrors=$null
        [void][Management.Automation.Language.Parser]::ParseInput($diagnosticProtocolText,[ref]$diagTokens,[ref]$diagParseErrors)
        if ($diagParseErrors.Count -ne 0) { throw 'UPDATE_DIAGNOSTIC_PROTOCOL_PARSE_FAILED' }
        . ([scriptblock]::Create($diagnosticProtocolText))

        # Each input is read once here for non-elevated screening. The elevated
        # child independently reads each once, hashes those exact bytes, then
        # executes the verified updater bytes in memory and passes the exact
        # verified candidate bytes to it.
        $updaterItem = Get-Item -LiteralPath $updaterPath -Force -ErrorAction Stop
        $candidateItem = Get-Item -LiteralPath $candidatePath -Force -ErrorAction Stop
        if ($updaterItem.PSIsContainer -or $updaterItem.Length -gt 4194304 -or $candidateItem.PSIsContainer -or $candidateItem.Length -lt 1 -or $candidateItem.Length -gt 65536) { throw 'UPDATE_INPUT_TYPE_OR_SIZE_INVALID' }
        $updaterBytes = [IO.File]::ReadAllBytes($updaterPath)
        if ((Get-F2UpdateLauncherSha256 -Bytes $updaterBytes) -cne $ExpectedUpdaterSha256) { throw 'UPDATE_UPDATER_HASH_MISMATCH' }
        $candidateBytes = [IO.File]::ReadAllBytes($candidatePath)
        if ((Get-F2UpdateLauncherSha256 -Bytes $candidateBytes) -cne $ExpectedCandidateManifestSha256) { throw 'UPDATE_CANDIDATE_HASH_MISMATCH' }
        $candidate = [Text.Encoding]::UTF8.GetString($candidateBytes) | ConvertFrom-Json -ErrorAction Stop
        if ($candidate.Schema -cne 'f2-icacls-runtime-release-v3' -or $candidate.ReviewedCommitSha -cne $ExpectedSourceCommit) { throw 'UPDATE_CANDIDATE_IDENTITY_MISMATCH' }

        $windowsPowerShell = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
        if (-not [IO.File]::Exists($windowsPowerShell)) { throw 'WINDOWS_POWERSHELL_51_UNAVAILABLE' }
        $parentStage = 'DiagnosticChannelInitialization'
        $diagnosticRequest = New-F2UpdateDiagnosticRequest -SourceCommit $ExpectedSourceCommit -LauncherSha256 $ExpectedLauncherSha256 -UpdaterSha256 $ExpectedUpdaterSha256 -CandidateManifestSha256 $ExpectedCandidateManifestSha256 -RequesterPid $requesterLauncherPid -RequesterCreationUtcTicks $requesterLauncherCreationUtcTicks -RequesterSid $requesterSid
        $diagnosticServer = New-F2UpdateLauncherDiagnosticServer -Request $diagnosticRequest
        $childScript = New-F2UpdateElevatedChildScript -UpdaterPath $updaterPath -CandidatePath $candidatePath -SourceRoot $sourceRoot -ExpectedSourceCommit $ExpectedSourceCommit -ExpectedLauncherSha256 $ExpectedLauncherSha256 -ExpectedUpdaterSha256 $ExpectedUpdaterSha256 -ExpectedCandidateManifestSha256 $ExpectedCandidateManifestSha256 -ExpectedRequesterSid $requesterSid -RequesterLauncherProcessId $requesterLauncherPid -RequesterLauncherCreationUtcTicks $requesterLauncherCreationUtcTicks -DiagnosticRequest $diagnosticRequest -DiagnosticProtocolPath $diagnosticProtocolPath -DiagnosticProtocolBytes $diagnosticProtocolBytes -RecoveryTransactionId $RecoveryTransactionId -ResumeForward:$ResumeForward
        $childTokens=$null;$childParseErrors=$null
        [void][Management.Automation.Language.Parser]::ParseInput($childScript,[ref]$childTokens,[ref]$childParseErrors)
        if ($childParseErrors.Count -ne 0) { throw 'UPDATE_ELEVATED_BOOTSTRAP_SCRIPT_PARSE_FAILED' }
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        $parentStage = 'UacLaunch'
        $uacLaunchAttempted = $true
        $child = Start-Process -FilePath $windowsPowerShell -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -Verb RunAs -PassThru -ErrorAction Stop
        $elevationStarted = $true
        $parentStage = 'ChildExecutionAndDiagnosticReceive'
        $childCreationTicks = 0L
        try { $childCreationTicks = $child.StartTime.ToUniversalTime().Ticks } catch { }
        $childResult = Receive-F2UpdateDiagnosticRecord -Server $diagnosticServer -Request $diagnosticRequest -ChildProcess $child -ChildCreationUtcTicks $childCreationTicks -TimeoutSeconds 600 -PostExitWaitMilliseconds 2500 -RecordTimeoutMilliseconds 5000
        $diagnosticSummary = [ordered]@{
            Authority='NON_AUTHORITATIVE_DIAGNOSTIC'
            Status=[string]$childResult.DiagnosticStatus
            ErrorCode=[string]$childResult.DiagnosticErrorCode
            RequestId=[string]$diagnosticRequest.RequestId
            Stage=if($null -ne $childResult.Record){[string]$childResult.Record.Stage}else{$null}
            ChildErrorCode=if($null -ne $childResult.Record){[string]$childResult.Record.ErrorCode}else{$null}
            RecordSha256=[string]$childResult.RecordSha256
        }
        if ($childResult.TimedOut) {
            [Console]::Out.WriteLine((@{Success=$false;Outcome='UPDATE_CHILD_STATUS_UNKNOWN';ElevationLaunches=1;ChildProcessId=$child.Id;ActualChildExitCode=$null;TimeoutSeconds=600;ChildTerminated=$false;Diagnostic=$diagnosticSummary} | ConvertTo-Json -Depth 5 -Compress))
            return 124
        }
        [Console]::Out.WriteLine((@{Success=($childResult.ActualChildExitCode -eq 0);Outcome=if($childResult.ActualChildExitCode -eq 0){'UPDATE_CHILD_EXIT_ZERO_REQUIRES_POST_ATTESTATION'}else{'UPDATE_CHILD_FAILED'};ElevationLaunches=1;ChildProcessId=$child.Id;ActualChildExitCode=$childResult.ActualChildExitCode;TimeoutSeconds=600;ChildTerminated=$false;Diagnostic=$diagnosticSummary} | ConvertTo-Json -Depth 5 -Compress))
        return [int]$childResult.ActualChildExitCode
    } catch {
        $code = if ($_.Exception.HResult -band 0xFFFF) { [int]($_.Exception.HResult -band 0xFFFF) } else { 1 }
        $outcome = if ($uacLaunchAttempted -and $code -eq 1223) { 'UAC_CANCELLED' } elseif ($uacLaunchAttempted) { 'UPDATE_LAUNCH_OR_WAIT_FAILURE' } else { 'UPDATE_NON_ELEVATED_PREFLIGHT_FAILURE' }
        $safeErrorCode = Get-F2UpdateLauncherSafeErrorCode -Code ([string]$_.Exception.Message)
        $childExited = $false;$childExitCode=$null;$childPid=$null
        if($null -ne $child){$childPid=$child.Id;try{$child.Refresh();$childExited=$child.HasExited;if($childExited){$childExitCode=[int]$child.ExitCode}}catch{}}
        [Console]::Out.WriteLine((@{Success=$false;Outcome=$outcome;ElevationLaunches=[int]$uacLaunchAttempted;ChildProcessId=$childPid;ChildExited=$childExited;ActualChildExitCode=$childExitCode;Stage=$parentStage;ErrorCode=$safeErrorCode;DiagnosticStatus=if($uacLaunchAttempted){'CHANNEL_OR_WAIT_FAILURE'}else{'NOT_STARTED'}} | ConvertTo-Json -Compress))
        return 1
    } finally {
        if ($null -ne $diagnosticServer) { try { [F2UpdateDiagnostics.NativePipe]::CancelPendingIo($diagnosticServer.SafePipeHandle);$diagnosticServer.Dispose() } catch {} }
        if ($null -ne $child) { $child.Dispose() }
    }
}

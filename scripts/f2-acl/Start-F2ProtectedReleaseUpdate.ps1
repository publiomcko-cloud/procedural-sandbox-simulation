Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-F2UpdateLauncherSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
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
        $candidatePath = Join-Path $reviewRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
        foreach ($path in @($sourceRoot,$updaterPath,$reviewRoot,$candidatePath)) {
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
        $childScript = @'
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$updaterPath='__UPDATER_PATH__'
$candidatePath='__CANDIDATE_PATH__'
$expectedUpdater='__UPDATER_SHA__'
$expectedLauncher='__LAUNCHER_SHA__'
$expectedCandidate='__CANDIDATE_SHA__'
$expectedRequesterSid='__REQUESTER_SID__'
$requesterLauncherPid='__REQUESTER_LAUNCHER_PID__'
$requesterLauncherCreationUtcTicks='__REQUESTER_LAUNCHER_CREATION_TICKS__'
$recoveryTransactionId='__RECOVERY_TRANSACTION_ID__'
$resumeForward=__RESUME_FORWARD__
$sourceRoot='__SOURCE_ROOT__'
function Get-ChildSha([byte[]]$Bytes){$h=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Test-ChildNoReparse([string]$Path){$current=[IO.Path]::GetFullPath($Path);while(-not [string]::IsNullOrEmpty($current)){if([IO.File]::Exists($current)-or[IO.Directory]::Exists($current)){$item=Get-Item -LiteralPath $current -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'UPDATE_REPARSE_INPUT_REJECTED'}};$parent=[IO.Directory]::GetParent($current);if($null -eq $parent){break};$current=$parent.FullName}}
try {
  Test-ChildNoReparse $updaterPath
  Test-ChildNoReparse $candidatePath
  $updaterItem=Get-Item -LiteralPath $updaterPath -Force -ErrorAction Stop
  $candidateItem=Get-Item -LiteralPath $candidatePath -Force -ErrorAction Stop
  if($updaterItem.PSIsContainer-or$updaterItem.Length-gt 4194304-or$candidateItem.PSIsContainer-or$candidateItem.Length-lt 1-or$candidateItem.Length-gt 65536){throw 'UPDATE_INPUT_TYPE_OR_SIZE_INVALID'}
  $updaterBytes=[IO.File]::ReadAllBytes($updaterPath)
  if((Get-ChildSha $updaterBytes) -cne $expectedUpdater){throw 'UPDATE_UPDATER_HASH_MISMATCH'}
  $candidateBytes=[IO.File]::ReadAllBytes($candidatePath)
  if((Get-ChildSha $candidateBytes) -cne $expectedCandidate){throw 'UPDATE_CANDIDATE_HASH_MISMATCH'}
  $text=[Text.UTF8Encoding]::new($false,$true).GetString($updaterBytes)
  $verifiedScript=[scriptblock]::Create($text)
  . $verifiedScript
  Test-F2UpdateElevationIdentity -ExpectedRequesterSid $expectedRequesterSid | Out-Null
  if(-not [string]::IsNullOrWhiteSpace($recoveryTransactionId)){
    $result=Invoke-F2ProtectedReleaseRecovery -CandidateManifestBytes $candidateBytes -CandidateManifestSha256 $expectedCandidate -ExpectedUpdaterSha256 $expectedUpdater -ExpectedLauncherSha256 $expectedLauncher -SourceRoot $sourceRoot -ExpectedRequesterSid $expectedRequesterSid -RequesterLauncherProcessId ([int]$requesterLauncherPid) -RequesterLauncherCreationUtcTicks ([long]$requesterLauncherCreationUtcTicks) -TransactionId $recoveryTransactionId -ResumeForward:$resumeForward
  }else{
    $result=Invoke-F2ProtectedReleaseUpdate -CandidateManifestBytes $candidateBytes -CandidateManifestSha256 $expectedCandidate -ExpectedUpdaterSha256 $expectedUpdater -ExpectedLauncherSha256 $expectedLauncher -SourceRoot $sourceRoot -ExpectedRequesterSid $expectedRequesterSid -RequesterLauncherProcessId ([int]$requesterLauncherPid) -RequesterLauncherCreationUtcTicks ([long]$requesterLauncherCreationUtcTicks)
  }
  [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 8 -Compress))
  if($result.Success){exit 0}else{exit 1}
} catch {
  [Console]::Out.WriteLine((@{Success=$false;Outcome='UPDATE_BOOTSTRAP_BLOCKED';ErrorCode=if($_.Exception.Message -match '^[A-Z0-9_:.\-]{1,100}$'){$_.Exception.Message}else{'UPDATE_UNCLASSIFIED_FAILURE'}} | ConvertTo-Json -Compress))
  exit 1
}
'@
        $resumeLiteral = if ($ResumeForward.IsPresent) { '$true' } else { '$false' }
        $childScript = $childScript.Replace('__UPDATER_PATH__',$updaterPath).Replace('__CANDIDATE_PATH__',$candidatePath).Replace('__UPDATER_SHA__',$ExpectedUpdaterSha256).Replace('__LAUNCHER_SHA__',$ExpectedLauncherSha256).Replace('__CANDIDATE_SHA__',$ExpectedCandidateManifestSha256).Replace('__SOURCE_ROOT__',$sourceRoot).Replace('__REQUESTER_SID__',$requesterSid).Replace('__REQUESTER_LAUNCHER_PID__',[string]$requesterLauncherPid).Replace('__REQUESTER_LAUNCHER_CREATION_TICKS__',[string]$requesterLauncherCreationUtcTicks).Replace('__RECOVERY_TRANSACTION_ID__',[string]$RecoveryTransactionId).Replace('__RESUME_FORWARD__',$resumeLiteral)
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        $uacLaunchAttempted = $true
        $child = Start-Process -FilePath $windowsPowerShell -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -Verb RunAs -PassThru -ErrorAction Stop
        $elevationStarted = $true
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while (-not $child.HasExited -and $clock.Elapsed.TotalSeconds -lt 600) { Start-Sleep -Milliseconds 250; $child.Refresh() }
        if (-not $child.HasExited) {
            [Console]::Out.WriteLine((@{Success=$false;Outcome='UPDATE_CHILD_STATUS_UNKNOWN';ElevationLaunches=1;ChildProcessId=$child.Id;ActualChildExitCode=$null;TimeoutSeconds=600;ChildTerminated=$false} | ConvertTo-Json -Compress))
            return 124
        }
        [Console]::Out.WriteLine((@{Success=($child.ExitCode -eq 0);Outcome=if($child.ExitCode -eq 0){'UPDATE_CHILD_EXIT_ZERO_REQUIRES_POST_ATTESTATION'}else{'UPDATE_CHILD_FAILED'};ElevationLaunches=1;ChildProcessId=$child.Id;ActualChildExitCode=$child.ExitCode;TimeoutSeconds=600;ChildTerminated=$false} | ConvertTo-Json -Compress))
        return [int]$child.ExitCode
    } catch {
        $code = if ($_.Exception.HResult -band 0xFFFF) { [int]($_.Exception.HResult -band 0xFFFF) } else { 1 }
        $outcome = if ($uacLaunchAttempted -and $code -eq 1223) { 'UAC_CANCELLED' } elseif ($uacLaunchAttempted) { 'UPDATE_LAUNCH_OR_WAIT_FAILURE' } else { 'UPDATE_NON_ELEVATED_PREFLIGHT_FAILURE' }
        [Console]::Out.WriteLine((@{Success=$false;Outcome=$outcome;ElevationLaunches=[int]$uacLaunchAttempted;ActualChildExitCode=$null;ErrorCode=if($_.Exception.Message -match '^[A-Z0-9_:.\-]{1,100}$'){$_.Exception.Message}else{'UPDATE_UNCLASSIFIED_FAILURE'}} | ConvertTo-Json -Compress))
        return 1
    } finally { if ($null -ne $child) { $child.Dispose() } }
}

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedLaunchCommitSha,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedLauncherSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedLaunchModuleSha256,
    [switch]$ExecuteApprovedProbe
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:launchAttempts=0
$script:launchRoot='C:\Dev\f2-g1-diagnostic-elevation-plan-source'
$script:sourceRoot='C:\Dev\f2-g1-protected-updater-source'
$script:candidateRoot='C:\Dev\f2-g1-protected-updater'
$script:expectedRemote='https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$script:expectedSourceCommit='396c44965c90c08292ad2835f8317e81b6b9daaf'
$script:expectedCandidateCommit='7f99bc10f3e2258d2340cea4e7ba1352022cbb6d'
$script:expectedProbeModuleSha256='4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee'
$script:expectedWrapperSha256='194eda47254eb0ea981253a60c60aeae0f34265801dbbee929e75d97d934df6a'
$script:expectedChildSha256='be01af0937ae644749a0b9b3f2755e788e780079be3bfd27f3e08d18e3c54757'
$script:expectedUpdaterSha256='d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2'
$script:expectedHistoricalLauncherSha256='9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
$script:expectedProtocolSha256='66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'
$script:expectedCandidateSha256='b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
$script:stage='RequesterPreflight'
$process=$null
$pipe=$null
$script:result=[pscustomobject][ordered]@{
    Schema='f2-g1-diagnostic-launch-result-v1';Authority='NON_AUTHORITATIVE_DIAGNOSTIC_ONLY';Status='FAIL'
    Stage='RequesterPreflight';ErrorCode='LAUNCH_NOT_STARTED';UacAttempted=$false;ChildPid=$null;ChildExitCode=$null;ChildMayRemain=$false
    DiagnosticStatus='MISSING';DiagnosticStage='UNKNOWN';DiagnosticErrorCode='UNKNOWN';Stdout='';StderrCodes=@()
    WrapperSha256=$script:expectedWrapperSha256;ModuleSha256=$script:expectedProbeModuleSha256
    UpdaterEntrypointInvoked=$false;RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false
}
$script:exitCode=1

function New-F2LaunchResult {
    param([string]$Status,[string]$Stage,[string]$Code,[bool]$UacAttempted,
          [Nullable[int]]$ChildPid,[Nullable[int]]$ChildExitCode,[bool]$ChildMayRemain,
          [string]$DiagnosticStatus,[string]$DiagnosticStage,[string]$DiagnosticErrorCode,
          [string]$Stdout,[string[]]$StderrCodes)
    return [pscustomobject][ordered]@{
        Schema='f2-g1-diagnostic-launch-result-v1';Authority='NON_AUTHORITATIVE_DIAGNOSTIC_ONLY'
        Status=$Status;Stage=$Stage;ErrorCode=$Code;UacAttempted=$UacAttempted
        ChildPid=$ChildPid;ChildExitCode=$ChildExitCode;ChildMayRemain=$ChildMayRemain;DiagnosticStatus=$DiagnosticStatus
        DiagnosticStage=$DiagnosticStage;DiagnosticErrorCode=$DiagnosticErrorCode
        Stdout=$Stdout;StderrCodes=@($StderrCodes);WrapperSha256=$script:expectedWrapperSha256
        ModuleSha256=$script:expectedProbeModuleSha256;UpdaterEntrypointInvoked=$false
        RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false
    }
}

function Read-F2LaunchPipeFrame {
    param([Parameter(Mandatory)][System.IO.Pipes.NamedPipeServerStream]$Pipe,
          [Parameter(Mandatory)][Diagnostics.Stopwatch]$Clock,
          [Parameter(Mandatory)][int]$DeadlineMs)
    $header=New-Object byte[] 4;$offset=0
    while($offset -lt 4){$remaining=$DeadlineMs-[int]$Clock.ElapsedMilliseconds;if($remaining -le 0){throw 'LAUNCH_PIPE_TIMEOUT'};$async=$Pipe.BeginRead($header,$offset,4-$offset,$null,$null);if(-not $async.AsyncWaitHandle.WaitOne($remaining)){throw 'LAUNCH_PIPE_TIMEOUT'};$n=$Pipe.EndRead($async);if($n -le 0){throw 'LAUNCH_PIPE_EOF'};$offset+=$n}
    $length=[BitConverter]::ToInt32($header,0)
    if($length -lt 2 -or $length -gt 8192){throw 'LAUNCH_FRAME_SIZE_INVALID'}
    $body=New-Object byte[] $length;$offset=0
    while($offset -lt $length){$remaining=$DeadlineMs-[int]$Clock.ElapsedMilliseconds;if($remaining -le 0){throw 'LAUNCH_PIPE_TIMEOUT'};$async=$Pipe.BeginRead($body,$offset,$length-$offset,$null,$null);if(-not $async.AsyncWaitHandle.WaitOne($remaining)){throw 'LAUNCH_PIPE_TIMEOUT'};$n=$Pipe.EndRead($async);if($n -le 0){throw 'LAUNCH_PIPE_EOF'};$offset+=$n}
    return (New-Object System.Text.UTF8Encoding($false,$true)).GetString($body)
}

function Get-F2LaunchSafeCode {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$Record)
    $head=([string]$Record.FullyQualifiedErrorId).Split(',')[0]
    $safe=@('LAUNCH_PS_VERSION_INVALID','LAUNCH_PS_ARCH_INVALID','LAUNCH_UNEXPECTED_ARGUMENTS','LAUNCH_APPROVAL_SWITCH_REQUIRED','LAUNCH_REQUESTER_TOKEN_REQUIRED','LAUNCH_CHECKOUT_MISMATCH','LAUNCH_GIT_PATH_REJECTED','LAUNCH_GIT_START_FAILED','LAUNCH_GIT_TIMEOUT','LAUNCH_GIT_OUTPUT_LIMIT','LAUNCH_GIT_DRAIN_INCOMPLETE','LAUNCH_GIT_QUERY_FAILED','LAUNCH_CHECKOUT_METADATA_REJECTED','LAUNCH_FILE_TYPE_OR_SIZE_INVALID','LAUNCH_FILE_HASH_MISMATCH','LAUNCH_CHILD_HASH_MISMATCH','LAUNCH_WRAPPER_HASH_MISMATCH','LAUNCH_MODULE_HASH_MISMATCH','LAUNCH_SOURCE_INPUT_HASH_MISMATCH','LAUNCH_UAC_CANCELLED_OR_LAUNCH_FAILED','LAUNCH_CHILD_PROCESS_UNKNOWN','LAUNCH_CHILD_PEER_MISMATCH','LAUNCH_CHILD_TOKEN_MISMATCH','LAUNCH_CHILD_COMMAND_MISMATCH','LAUNCH_CHILD_EXIT_BEFORE_CONNECT','LAUNCH_PIPE_TIMEOUT','LAUNCH_PIPE_EOF','LAUNCH_FRAME_SIZE_INVALID','LAUNCH_FRAME_LENGTH_INVALID','LAUNCH_RESPONSE_INVALID','LAUNCH_CHILD_EXIT_TIMEOUT','LAUNCH_CHILD_EXIT_MISMATCH','LAUNCH_SOURCE_PATH_REJECTED','LAUNCH_PIPE_CREATE_FAILED','LAUNCH_PIPE_DACL_INVALID','LAUNCH_REQUEST_INVALID','LAUNCH_OUTPUT_BOUND_EXCEEDED')
    if($safe -ccontains $head){return $head}
    return 'LAUNCH_UNCLASSIFIED_FAILURE'
}

try {
    if(@($MyInvocation.UnboundArguments).Count -ne 0){throw 'LAUNCH_UNEXPECTED_ARGUMENTS'}
    if(-not $ExecuteApprovedProbe){throw 'LAUNCH_APPROVAL_SWITCH_REQUIRED'}
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'LAUNCH_PS_VERSION_INVALID'}
    if(-not [Environment]::Is64BitProcess){throw 'LAUNCH_PS_ARCH_INVALID'}

    $launchModulePath=Join-Path $script:launchRoot 'scripts\f2-acl\F2HistoricalManifestLaunch.psm1'
    $moduleCurrent=[IO.Path]::GetFullPath($launchModulePath)
    while(-not [string]::IsNullOrEmpty($moduleCurrent)){$moduleItem=Get-Item -LiteralPath $moduleCurrent -Force -ErrorAction Stop;if(($moduleItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'LAUNCH_SOURCE_PATH_REJECTED'};$moduleParent=[IO.Path]::GetDirectoryName($moduleCurrent);if([string]::IsNullOrEmpty($moduleParent)-or$moduleParent -ceq $moduleCurrent){break};$moduleCurrent=$moduleParent}
    $moduleBytes=[IO.File]::ReadAllBytes($launchModulePath)
    $moduleSha=(Get-F2LaunchSha256 -Bytes $moduleBytes)
    if($moduleSha -cne $ExpectedLaunchModuleSha256){throw 'LAUNCH_MODULE_HASH_MISMATCH'}
    $moduleText=(New-Object System.Text.UTF8Encoding($false,$true)).GetString($moduleBytes)
    $moduleInfo=New-Module -Name 'F2HistoricalManifestLaunchRequester' -ScriptBlock ([scriptblock]::Create($moduleText)) -Force
    Import-Module -ModuleInfo $moduleInfo -Force -ErrorAction Stop | Out-Null
    Initialize-F2LaunchNative | Out-Null

    $script:stage='LaunchCheckoutValidation'
    $currentScriptPath=Join-Path $script:launchRoot 'scripts\f2-acl\Start-F2HistoricalManifestDiagnostic.ps1'
    $scriptBytes=Read-F2LaunchPinnedFile -Path $currentScriptPath -ExpectedSha256 $ExpectedLauncherSha256 -MaximumBytes 262144
    $launchFacts=Get-F2LaunchRepositoryFacts -GitPath 'C:\Program Files\Git\cmd\git.exe' -ExpectedGitSha256 '7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364' -Repository $script:launchRoot -ExpectedRoot $script:launchRoot -ExpectedHead $ExpectedLaunchCommitSha
    if(-not $launchFacts.Pass){throw 'LAUNCH_CHECKOUT_MISMATCH'}

    $script:stage='TokenValidation'
    $token=Get-F2LaunchTokenFacts
    if($token.IsAdministrator -or $token.IsElevated -or $token.IntegrityRid -ge 0x3000){throw 'LAUNCH_REQUESTER_TOKEN_REQUIRED'}
    $gitPath='C:\Program Files\Git\cmd\git.exe'
    [void](Test-F2LaunchNoReparsePath -Path $gitPath)
    $gitSha='7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364'
    [void](Read-F2LaunchPinnedFile -Path $gitPath -ExpectedSha256 $gitSha -MaximumBytes 67108864)
    $script:stage='SourceIdentityValidation'
    $sourceFacts=Get-F2LaunchRepositoryFacts -GitPath $gitPath -ExpectedGitSha256 $gitSha -Repository $script:sourceRoot -ExpectedRoot $script:sourceRoot -ExpectedHead $script:expectedSourceCommit
    $candidateFacts=Get-F2LaunchRepositoryFacts -GitPath $gitPath -ExpectedGitSha256 $gitSha -Repository $script:candidateRoot -ExpectedRoot $script:candidateRoot -ExpectedHead $script:expectedCandidateCommit
    if(-not $sourceFacts.Pass -or -not $candidateFacts.Pass){throw 'LAUNCH_CHECKOUT_MISMATCH'}

    $script:stage='InputIntegrityValidation'
    $wrapperPath=Join-Path $script:launchRoot 'scripts\f2-acl\Invoke-F2HistoricalManifestDiagnostic.ps1'
    $probeModulePath=Join-Path $script:launchRoot 'scripts\f2-acl\F2HistoricalManifestDiagnostic.psm1'
    $childPath=Join-Path $script:launchRoot 'scripts\f2-acl\Invoke-F2HistoricalManifestDiagnosticChild.ps1'
    $wrapperBytes=Read-F2LaunchPinnedFile -Path $wrapperPath -ExpectedSha256 $script:expectedWrapperSha256 -MaximumBytes 262144
    $probeModuleBytes=Read-F2LaunchPinnedFile -Path $probeModulePath -ExpectedSha256 $script:expectedProbeModuleSha256 -MaximumBytes 131072
    $childBytes=Read-F2LaunchPinnedFile -Path $childPath -ExpectedSha256 $script:expectedChildSha256 -MaximumBytes 262144
    $sourceInputMap=[ordered]@{
        'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'=$script:expectedUpdaterSha256
        'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'=$script:expectedHistoricalLauncherSha256
        'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1'=$script:expectedProtocolSha256
    }
    foreach($relative in $sourceInputMap.Keys){[void](Read-F2LaunchPinnedFile -Path (Join-Path $script:sourceRoot $relative) -ExpectedSha256 $sourceInputMap[$relative] -MaximumBytes 4194304)}
    [void](Read-F2LaunchPinnedFile -Path (Join-Path $script:candidateRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json') -ExpectedSha256 $script:expectedCandidateSha256 -MaximumBytes 65536)

    $script:stage='RequesterPreflightComplete'
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {$requesterSid=$identity.User.Value} finally {$identity.Dispose()}
    $requesterProcess=[Diagnostics.Process]::GetCurrentProcess()
    try {$requesterPid=$requesterProcess.Id;$requesterStartTicks=$requesterProcess.StartTime.ToUniversalTime().Ticks} finally {$requesterProcess.Dispose()}
    $request=New-F2LaunchRequest -RequesterSid $requesterSid -RequesterPid $requesterPid -RequesterStartUtcTicks $requesterStartTicks -GitPath $gitPath -GitSha256 $gitSha -LaunchCommitSha $ExpectedLaunchCommitSha -LaunchModuleSha256 $ExpectedLaunchModuleSha256 -WrapperSha256 $script:expectedWrapperSha256 -ModuleSha256 $script:expectedProbeModuleSha256
    if(-not (Test-F2LaunchRequest $request)){throw 'LAUNCH_REQUEST_INVALID'}
    $shortPipe='F2D_'+[guid]::NewGuid().ToString('N')
    $pipe=New-F2LaunchServerStream -ShortName $shortPipe -RequesterSid $requesterSid
    $launchModuleSha=$ExpectedLaunchModuleSha256
    $childTemplatePath=$childPath
    $childHash=$script:expectedChildSha256
    $childLoader=@"
`$env:PSModulePath=`$PSHOME+'\Modules';`$ErrorActionPreference='Stop';`$path='$childTemplatePath';`$expected='$childHash';`$current=[IO.Path]::GetFullPath(`$path);while(-not [string]::IsNullOrEmpty(`$current)){if(-not([IO.File]::Exists(`$current)-or[IO.Directory]::Exists(`$current))){exit 80};`$item=Get-Item -LiteralPath `$current -Force -ErrorAction Stop;if((`$item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){exit 81};`$parent=[IO.Path]::GetDirectoryName(`$current);if([string]::IsNullOrEmpty(`$parent)-or`$parent -ceq `$current){break};`$current=`$parent};`$s=[IO.File]::Open(`$path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);try{if(`$s.Length -lt 1 -or `$s.Length -gt 262144){exit 82};`$b=New-Object byte[] ([int]`$s.Length);`$o=0;while(`$o -lt `$b.Length){`$n=`$s.Read(`$b,`$o,`$b.Length-`$o);if(`$n -le 0){exit 83};`$o+=`$n}}finally{`$s.Dispose()};`$h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(`$b)).Replace('-','').ToLowerInvariant();if(`$h -cne `$expected){exit 84};`$t=(New-Object System.Text.UTF8Encoding(`$false,`$true)).GetString(`$b);`$scriptBlock=[scriptblock]::Create(`$t);& `$scriptBlock -PipeName '$shortPipe' -ExpectedParentPid $requesterPid -ExpectedParentStartUtcTicks $requesterStartTicks -ExpectedLaunchCommitSha '$ExpectedLaunchCommitSha';exit `$LASTEXITCODE
"@
    $childEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childLoader))
    if($childEncoded.Length -gt 28000){throw 'LAUNCH_OUTPUT_BOUND_EXCEEDED'}
    $powershellPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    [void](Test-F2LaunchNoReparsePath -Path $powershellPath)
    $process=$null
    $script:launchAttempts=1
    $script:result=[pscustomobject][ordered]@{Schema='f2-g1-diagnostic-launch-result-v1';Authority='NON_AUTHORITATIVE_DIAGNOSTIC_ONLY';Status='RUNNING';Stage='UacLaunch';ErrorCode='NONE';UacAttempted=$true;ChildPid=$null;ChildExitCode=$null;ChildMayRemain=$false;DiagnosticStatus='MISSING';DiagnosticStage='UNKNOWN';DiagnosticErrorCode='UNKNOWN';Stdout='';StderrCodes=@();WrapperSha256=$script:expectedWrapperSha256;ModuleSha256=$script:expectedProbeModuleSha256;UpdaterEntrypointInvoked=$false;RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false}
    $script:stage='UacLaunch'
    $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$childEncoded
    try {$process=Start-Process -FilePath $powershellPath -ArgumentList $arguments -Verb RunAs -PassThru -WindowStyle Hidden -ErrorAction Stop}
    catch {throw 'LAUNCH_UAC_CANCELLED_OR_LAUNCH_FAILED'}
    $childPid=$process.Id
    $childStart=[long]$process.StartTime.ToUniversalTime().Ticks
    $script:result.ChildPid=$childPid
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $accept=$pipe.BeginWaitForConnection($null,$null)
    $connectDeadline=[Diagnostics.Stopwatch]::StartNew()
    while(-not $accept.AsyncWaitHandle.WaitOne(250)){
        if($connectDeadline.ElapsedMilliseconds -ge 20000){throw 'LAUNCH_PIPE_TIMEOUT'}
        if($process.HasExited){$script:result.ChildExitCode=[int]$process.ExitCode;throw 'LAUNCH_CHILD_EXIT_BEFORE_CONNECT'}
    }
    $pipe.EndWaitForConnection($accept)
    $script:stage='ChildAuthentication'
    $pipePeerPid=[int][F2HistoricalLaunchNative]::ClientPid($pipe.SafePipeHandle.DangerousGetHandle())
    $peer=Get-F2LaunchProcessIdentity -ProcessId $pipePeerPid
    $commandLineMatches=Test-F2LaunchProcessCommandLine -ProcessId $childPid -ExpectedImagePath $powershellPath -ExpectedEncodedCommand $childEncoded
    if(-not (Test-F2LaunchPeerFacts -ExpectedPid $childPid -ExpectedStartUtcTicks $childStart -ObservedPid $peer.ProcessId -ObservedStartUtcTicks $peer.StartUtcTicks -CommandLineMatches $commandLineMatches -TokenMatches $true)){throw 'LAUNCH_CHILD_COMMAND_MISMATCH'}
    if([IO.Path]::GetFullPath($peer.ImagePath) -cne [IO.Path]::GetFullPath($powershellPath)){throw 'LAUNCH_CHILD_PEER_MISMATCH'}
    $helloJson=Read-F2LaunchPipeFrame -Pipe $pipe -Clock $clock -DeadlineMs 90000
    $hello=$helloJson|ConvertFrom-Json -ErrorAction Stop
    if(-not (Test-F2LaunchHello -Hello $hello -ExpectedPid $childPid -ExpectedStartUtcTicks $childStart)){throw 'LAUNCH_CHILD_PEER_MISMATCH'}
    $peerBox=@{Identity=$null}
    $pipe.RunAsClient({
        $i=[Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $p=New-Object Security.Principal.WindowsPrincipal($i)
            $native=[F2HistoricalLaunchNative]::TokenIsElevated($i.Token)
            $integrity=[F2HistoricalLaunchNative]::TokenIntegrityRid($i.Token)
            $peerBox.Identity=[pscustomobject]@{Sid=$i.User.Value;Admin=$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);Elevated=$native;Integrity=$integrity}
        } finally {$i.Dispose()}
    }.GetNewClosure())
    $peerIdentity=$peerBox.Identity
    if($null -eq $peerIdentity -or -not (Test-F2LaunchTokenFacts -RequiredClass ELEVATED -UserSid $peerIdentity.Sid -IsElevated $peerIdentity.Elevated -IsAdministrator $peerIdentity.Admin -IntegrityRid $peerIdentity.Integrity -ExpectedUserSid $requesterSid)){throw 'LAUNCH_CHILD_TOKEN_MISMATCH'}
    $requestJson=ConvertTo-Json -InputObject $request -Depth 5 -Compress
    $requestFrame=ConvertTo-F2LaunchFrame -Json $requestJson
    $pipe.Write($requestFrame,0,$requestFrame.Length);$pipe.Flush()
    $responseJson=Read-F2LaunchPipeFrame -Pipe $pipe -Clock $clock -DeadlineMs 90000
    $response=$responseJson|ConvertFrom-Json -ErrorAction Stop
    $remaining=90000-[int]$clock.ElapsedMilliseconds
    if($remaining -le 0 -or -not $process.WaitForExit($remaining)){throw 'LAUNCH_CHILD_EXIT_TIMEOUT'}
    $actualExit=[int]$process.ExitCode
    $script:stage='ResultValidation'
    if(-not (Test-F2LaunchResponse -Response $response -Request $request -PipePeerPid $pipePeerPid -PipePeerStartUtcTicks $childStart -ActualExitCode $actualExit)){throw 'LAUNCH_RESPONSE_INVALID'}
    $script:result=New-F2LaunchResult -Status $(if($response.Status -ceq 'PASS' -and $actualExit -eq 0){'PASS'}else{'FAIL'}) -Stage 'Complete' -Code $response.ErrorCode -UacAttempted $true -ChildPid $childPid -ChildExitCode $actualExit -ChildMayRemain $false -DiagnosticStatus $response.Status -DiagnosticStage $response.Stage -DiagnosticErrorCode $response.ErrorCode -Stdout $response.Stdout -StderrCodes $response.StderrCodes
    if($script:result.Status -ceq 'PASS'){$script:exitCode=0}
} catch {
    $safeCode=Get-F2LaunchSafeCode -Record $_
    $childPidValue=$null;$childExitValue=$null
    $childMayRemain=$false
    if($null -ne $process){
        try {$childPidValue=$process.Id;if($process.HasExited){$childExitValue=[int]$process.ExitCode}else{$childMayRemain=$true}}
        catch {$childMayRemain=$true}
    }
    $script:result=New-F2LaunchResult -Status FAIL -Stage $script:stage -Code $safeCode -UacAttempted ($script:launchAttempts -eq 1) -ChildPid $childPidValue -ChildExitCode $childExitValue -ChildMayRemain $childMayRemain -DiagnosticStatus 'MISSING_OR_INVALID' -DiagnosticStage 'UNKNOWN' -DiagnosticErrorCode 'UNKNOWN' -Stdout '' -StderrCodes @()
    $script:exitCode=1
} finally {
    if($null -ne $pipe){$pipe.Dispose()}
    if($null -ne $process){$process.Dispose()}
}

$json=ConvertTo-Json -InputObject $script:result -Depth 6 -Compress
if($json.Length -gt 8192){$json='{"Schema":"f2-g1-diagnostic-launch-result-v1","Authority":"NON_AUTHORITATIVE_DIAGNOSTIC_ONLY","Status":"FAIL","Stage":"Serialization","ErrorCode":"LAUNCH_OUTPUT_BOUND_EXCEEDED","UacAttempted":false,"ChildPid":null,"ChildExitCode":null,"ChildMayRemain":false,"DiagnosticStatus":"MISSING","DiagnosticStage":"UNKNOWN","DiagnosticErrorCode":"UNKNOWN","Stdout":"","StderrCodes":[],"UpdaterEntrypointInvoked":false,"RecoveryEntrypointInvoked":false,"ProtectedWritePerformed":false}';$script:exitCode=1}
Write-Output $json
exit $script:exitCode

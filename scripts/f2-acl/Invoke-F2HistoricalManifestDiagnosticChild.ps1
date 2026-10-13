[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^F2D_[0-9a-f]{32}$')][string]$PipeName,
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$ExpectedParentPid,
    [Parameter(Mandatory)][ValidateRange(1,[long]::MaxValue)][long]$ExpectedParentStartUtcTicks,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedLaunchCommitSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:stage='ChildBootstrap'
$script:safeCode='LAUNCH_CHILD_BOOTSTRAP_FAILED'
$script:request=$null
$script:pipe=$null
$script:exitCode=1
$script:launchRoot='C:\Dev\f2-g1-diagnostic-launch-runtime'
$script:sourceRoot='C:\Dev\f2-g1-protected-updater-source'
$script:candidateRoot='C:\Dev\f2-g1-protected-updater'
$script:expectedGitPath='C:\Program Files\Git\mingw64\bin\git.exe'
$script:expectedGitSha256='1a0043555d254618f2d56c936c3d9a1fbfb878bc878416a133c346bc7835eda9'
$script:launchModuleSha256='06f117c6be29e3e150149087cb19323e83df20601b8d134f0bb02ec7335867d2'
$script:probeModuleSha256='4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee'
$script:wrapperSha256='99505626679c75511e16d524c39dfd0ff0cbd27b3a0bd36d631cbadf2c1c9536'
$script:updaterSha256='d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2'
$script:historicalLauncherSha256='9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
$script:protocolSha256='66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'
$script:candidateSha256='b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
$script:responseStdout=''
$script:stderrCodes=New-Object 'System.Collections.Generic.List[string]'

function Get-ChildSafeCode {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$Record)
    $head=([string]$Record.FullyQualifiedErrorId).Split(',')[0]
    $allowed=@('LAUNCH_PS_VERSION_INVALID','LAUNCH_ELEVATED_TOKEN_REQUIRED','LAUNCH_PATH_UNAVAILABLE','LAUNCH_REPARSE_PATH_REJECTED','LAUNCH_FILE_TYPE_OR_SIZE_INVALID','LAUNCH_FILE_CHANGED_DURING_READ','LAUNCH_FILE_TRUNCATED','LAUNCH_FILE_HASH_MISMATCH','LAUNCH_GIT_PATH_REJECTED','LAUNCH_GIT_START_FAILED','LAUNCH_GIT_TIMEOUT','LAUNCH_GIT_OUTPUT_LIMIT','LAUNCH_GIT_QUERY_FAILED','LAUNCH_GIT_DRAIN_INCOMPLETE','LAUNCH_CHECKOUT_METADATA_REJECTED','LAUNCH_PIPE_NAME_INVALID','LAUNCH_RECORD_SIZE_INVALID','LAUNCH_FRAME_SIZE_INVALID','LAUNCH_FRAME_LENGTH_INVALID','LAUNCH_FRAME_TRUNCATED','LAUNCH_PIPE_SERVER_PID_MISMATCH','LAUNCH_PIPE_SERVER_START_MISMATCH','LAUNCH_REQUEST_INVALID','LAUNCH_REQUEST_PARENT_MISMATCH','LAUNCH_REQUEST_PARENT_SID_MISMATCH','LAUNCH_SOURCE_PIN_MISMATCH','LAUNCH_REQUESTER_IDENTITY_MISMATCH','LAUNCH_ELEVATED_TOKEN_REQUIRED','LAUNCH_SOURCE_CHECKOUT_MISMATCH','LAUNCH_PROBE_SOURCE_PIN_MISMATCH','LAUNCH_DIAGNOSTIC_OUTPUT_INVALID','PropertyNotFoundStrict','PROBE_SOURCE_PARSE_FAILED','PROBE_SOURCE_FUNCTION_SHAPE_INVALID','PROBE_CANDIDATE_HASH_MISMATCH','PROBE_UPDATER_HASH_MISMATCH','PROBE_LAUNCHER_HASH_MISMATCH','PROBE_PROTOCOL_HASH_MISMATCH','PROBE_CANDIDATE_COMMIT_MISMATCH')
    if($allowed -ccontains $head){return $head}
    return 'UNLISTED'
}

function Read-ChildFrame {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream,[Parameter(Mandatory)][int]$MaximumBytes)
    $header=New-Object byte[] 4
    $offset=0
    while($offset -lt 4){$n=$Stream.Read($header,$offset,4-$offset);if($n -le 0){throw 'LAUNCH_FRAME_TRUNCATED'};$offset+=$n}
    $length=[BitConverter]::ToInt32($header,0)
    if($length -lt 2 -or $length -gt $MaximumBytes){throw 'LAUNCH_FRAME_SIZE_INVALID'}
    $body=New-Object byte[] $length;$offset=0
    while($offset -lt $length){$n=$Stream.Read($body,$offset,$length-$offset);if($n -le 0){throw 'LAUNCH_FRAME_TRUNCATED'};$offset+=$n}
    $utf8=New-Object System.Text.UTF8Encoding($false,$true)
    return $utf8.GetString($body)
}

function Test-ChildNoReparsePath {
    param([Parameter(Mandatory)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while(-not [string]::IsNullOrEmpty($current)){
        if(-not ([IO.File]::Exists($current)-or[IO.Directory]::Exists($current))){throw 'LAUNCH_PATH_UNAVAILABLE'}
        $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'LAUNCH_REPARSE_PATH_REJECTED'}
        $parent=[IO.Path]::GetDirectoryName($current)
        if([string]::IsNullOrEmpty($parent)-or$parent -ceq $current){break}
        $current=$parent
    }
}

function Get-ChildByteSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}

function Read-ChildPinnedFile {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$ExpectedSha256,
          [Parameter(Mandatory)][int]$MaximumBytes)
    Test-ChildNoReparsePath -Path $Path
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt $MaximumBytes){throw 'LAUNCH_FILE_TYPE_OR_SIZE_INVALID'}
    $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($stream.Length -ne $item.Length){throw 'LAUNCH_FILE_CHANGED_DURING_READ'}
        $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
        while($offset -lt $bytes.Length){$read=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($read -le 0){throw 'LAUNCH_FILE_TRUNCATED'};$offset+=$read}
    }finally{$stream.Dispose()}
    if((Get-ChildByteSha256 -Bytes $bytes) -cne $ExpectedSha256){throw 'LAUNCH_FILE_HASH_MISMATCH'}
    return ,$bytes
}

function Send-ChildResponse {
    param([Parameter(Mandatory)][string]$Status,[Parameter(Mandatory)][string]$Stage,
          [Parameter(Mandatory)][string]$ErrorCode,[Parameter(Mandatory)][string]$Stdout,
          [Parameter(Mandatory)][string[]]$StderrCodes)
    if($null -eq $script:pipe -or -not $script:pipe.IsConnected -or $null -eq $script:request){return}
    $process=[Diagnostics.Process]::GetCurrentProcess()
    try {$startTicks=$process.StartTime.ToUniversalTime().Ticks} finally {$process.Dispose()}
    $response=[pscustomobject][ordered]@{
        Schema='f2-g1-diagnostic-launch-response-v1';RequestId=$script:request.RequestId;Nonce=$script:request.Nonce
        ChildPid=$PID;ChildStartUtcTicks=$startTicks;Status=$Status;Stage=$Stage;ErrorCode=$ErrorCode
        Stdout=$Stdout;StderrCodes=@($StderrCodes);LaunchModuleSha256=$script:launchModuleSha256
        WrapperSha256=$script:wrapperSha256;ModuleSha256=$script:probeModuleSha256
        UpdaterEntrypointInvoked=$false;RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false
    }
    $json=ConvertTo-Json -InputObject $response -Depth 5 -Compress
    $frame=ConvertTo-F2LaunchFrame -Json $json
    $script:pipe.Write($frame,0,$frame.Length);$script:pipe.Flush()
}

try {
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'LAUNCH_PS_VERSION_INVALID'}
    $script:pipe=New-Object System.IO.Pipes.NamedPipeClientStream('.', $PipeName,[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::None)
    $script:pipe.Connect(15000)

    $script:stage='TokenValidation'
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'LAUNCH_ELEVATED_TOKEN_REQUIRED'}
        $elevatedSid=$identity.User.Value
    } finally {$identity.Dispose()}

    $script:stage='SourceIdentityValidation'
    $nativeModulePath=Join-Path $script:launchRoot 'scripts\f2-acl\F2HistoricalManifestLaunch.psm1'
    $moduleBytes=Read-ChildPinnedFile -Path $nativeModulePath -ExpectedSha256 $script:launchModuleSha256 -MaximumBytes 262144
    $moduleText=(New-Object System.Text.UTF8Encoding($false,$true)).GetString($moduleBytes)
    $moduleInfo=New-Module -Name 'F2HistoricalManifestLaunchChild' -ScriptBlock ([scriptblock]::Create($moduleText)) -Force
    Import-Module -ModuleInfo $moduleInfo -Force -ErrorAction Stop | Out-Null
    Initialize-F2LaunchNative | Out-Null

    $serverPid=[F2HistoricalLaunchNative]::ServerPid($script:pipe.SafePipeHandle.DangerousGetHandle())
    if([int]$serverPid -ne $ExpectedParentPid){throw 'LAUNCH_PIPE_SERVER_PID_MISMATCH'}
    $parentProcess=[Diagnostics.Process]::GetProcessById([int]$serverPid)
    try {if($parentProcess.StartTime.ToUniversalTime().Ticks -ne $ExpectedParentStartUtcTicks){throw 'LAUNCH_PIPE_SERVER_START_MISMATCH'}} finally {$parentProcess.Dispose()}

    $childProcess=[Diagnostics.Process]::GetCurrentProcess()
    try {$hello=[pscustomobject][ordered]@{Schema='f2-g1-diagnostic-launch-hello-v1';ProcessId=$childProcess.Id;StartUtcTicks=$childProcess.StartTime.ToUniversalTime().Ticks}} finally {$childProcess.Dispose()}
    $helloFrame=ConvertTo-F2LaunchFrame -Json (ConvertTo-Json -InputObject $hello -Compress)
    $script:pipe.Write($helloFrame,0,$helloFrame.Length);$script:pipe.Flush()

    $script:request=Read-ChildFrame -Stream $script:pipe -MaximumBytes 8192 | ConvertFrom-Json -ErrorAction Stop
    if(-not (Test-F2LaunchRequest $script:request)){throw 'LAUNCH_REQUEST_INVALID'}
    if([int]$script:request.RequesterPid -ne $ExpectedParentPid -or [long]$script:request.RequesterStartUtcTicks -ne $ExpectedParentStartUtcTicks){throw 'LAUNCH_REQUEST_PARENT_MISMATCH'}
    if([F2HistoricalLaunchNative]::ProcessSid([uint32]$ExpectedParentPid) -cne [string]$script:request.RequesterSid){throw 'LAUNCH_REQUEST_PARENT_SID_MISMATCH'}
    if([string]$script:request.LaunchCommitSha -cne $ExpectedLaunchCommitSha -or [string]$script:request.LaunchModuleSha256 -cne $script:launchModuleSha256){throw 'LAUNCH_SOURCE_PIN_MISMATCH'}
    if([string]$script:request.RequesterSid -cne $elevatedSid){throw 'LAUNCH_REQUESTER_IDENTITY_MISMATCH'}
    $script:stage='TokenValidation'
    $tokenFacts=Get-F2LaunchTokenFacts
    if(-not (Test-F2LaunchTokenFacts -RequiredClass ELEVATED -UserSid $tokenFacts.UserSid -IsElevated $tokenFacts.IsElevated -IsAdministrator $tokenFacts.IsAdministrator -IntegrityRid $tokenFacts.IntegrityRid -ExpectedUserSid $script:request.RequesterSid)){throw 'LAUNCH_ELEVATED_TOKEN_REQUIRED'}

    $script:stage='SourceIdentityValidation'
    $gitBytes=Read-F2LaunchPinnedFile -Path $script:request.GitPath -ExpectedSha256 $script:request.GitSha256 -MaximumBytes 67108864
    $gitPath=[IO.Path]::GetFullPath($script:request.GitPath)
    if($gitPath -cne [IO.Path]::GetFullPath($script:expectedGitPath) -or [string]$script:request.GitSha256 -cne $script:expectedGitSha256){throw 'LAUNCH_GIT_PATH_REJECTED'}
    $launchFacts=Get-F2LaunchRepositoryFacts -GitPath $gitPath -ExpectedGitSha256 $script:expectedGitSha256 -Repository $script:launchRoot -ExpectedRoot $script:launchRoot -ExpectedHead $script:request.LaunchCommitSha
    $sourceFacts=Get-F2LaunchRepositoryFacts -GitPath $gitPath -ExpectedGitSha256 $script:expectedGitSha256 -Repository $script:sourceRoot -ExpectedRoot $script:sourceRoot -ExpectedHead '396c44965c90c08292ad2835f8317e81b6b9daaf'
    $candidateFacts=Get-F2LaunchRepositoryFacts -GitPath $gitPath -ExpectedGitSha256 $script:expectedGitSha256 -Repository $script:candidateRoot -ExpectedRoot $script:candidateRoot -ExpectedHead '7f99bc10f3e2258d2340cea4e7ba1352022cbb6d'
    if(-not $launchFacts.Pass -or -not $sourceFacts.Pass -or -not $candidateFacts.Pass){throw 'LAUNCH_SOURCE_CHECKOUT_MISMATCH'}

    $script:stage='InputIntegrityValidation'
    $inputs=@(
        @{Path=(Join-Path $script:sourceRoot 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1');Sha=$script:updaterSha256;Max=4194304},
        @{Path=(Join-Path $script:sourceRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1');Sha=$script:historicalLauncherSha256;Max=4194304},
        @{Path=(Join-Path $script:sourceRoot 'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1');Sha=$script:protocolSha256;Max=4194304},
        @{Path=(Join-Path $script:candidateRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json');Sha=$script:candidateSha256;Max=65536}
    )
    foreach($input in $inputs){[void](Read-F2LaunchPinnedFile -Path $input.Path -ExpectedSha256 $input.Sha -MaximumBytes $input.Max)}
    $probeModulePath=Join-Path $script:launchRoot 'scripts\f2-acl\F2HistoricalManifestDiagnostic.psm1'
    $wrapperPath=Join-Path $script:launchRoot 'scripts\f2-acl\Invoke-F2HistoricalManifestDiagnostic.ps1'
    $launchModuleBytes=Read-F2LaunchPinnedFile -Path $nativeModulePath -ExpectedSha256 $script:launchModuleSha256 -MaximumBytes 262144
    $probeModuleBytes=Read-F2LaunchPinnedFile -Path $probeModulePath -ExpectedSha256 $script:probeModuleSha256 -MaximumBytes 131072
    $wrapperBytes=Read-F2LaunchPinnedFile -Path $wrapperPath -ExpectedSha256 $script:wrapperSha256 -MaximumBytes 262144
    if([string]$script:request.ModuleSha256 -cne $script:probeModuleSha256 -or [string]$script:request.WrapperSha256 -cne $script:wrapperSha256){throw 'LAUNCH_PROBE_SOURCE_PIN_MISMATCH'}
    $wrapperText=(New-Object System.Text.UTF8Encoding($false,$true)).GetString($wrapperBytes)

    $script:stage='CandidateManifestValidation'
    $runspace=[runspacefactory]::CreateRunspace()
    $runner=[powershell]::Create()
    try {
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable('F2HistoricalVerifiedModuleBytes',[byte[]]$probeModuleBytes)
        $runner.Runspace=$runspace
        $null=$runner.AddScript($wrapperText)
        $output=@($runner.Invoke())
        $rawErrors=@($runner.Streams.Error)
        if($rawErrors.Count -gt 16){throw 'LAUNCH_OUTPUT_BOUND_EXCEEDED'}
        $safeErrors=@($rawErrors|ForEach-Object{([string]$_.FullyQualifiedErrorId).Split(',')[0]}|ForEach-Object{if($_ -in @('PropertyNotFoundStrict','PROBE_SOURCE_PARSE_FAILED','PROBE_SOURCE_FUNCTION_SHAPE_INVALID','PROBE_CANDIDATE_HASH_MISMATCH','PROBE_UPDATER_HASH_MISMATCH','PROBE_LAUNCHER_HASH_MISMATCH','PROBE_PROTOCOL_HASH_MISMATCH')){$_}else{'UNLISTED'}})
    } finally {$runner.Dispose();$runspace.Dispose()}
    if($output.Count -ne 1 -or $output[0] -isnot [string]){throw 'LAUNCH_DIAGNOSTIC_OUTPUT_INVALID'}
    if(([string]$output[0]).Length -gt 4096 -or [string]$output[0] -match '(?i)([A-Z]:\\|S-1-|BaselineMailboxId|ExceptionMessage|SDDL)'){throw 'LAUNCH_DIAGNOSTIC_OUTPUT_INVALID'}
    $probeResult=[string]$output[0]|ConvertFrom-Json -ErrorAction Stop
    if($probeResult.Schema -cne 'f2-g1-historical-manifest-diagnostic-v1' -or $probeResult.Authority -cne 'NON_AUTHORITATIVE_DIAGNOSTIC_ONLY' -or $probeResult.UpdaterEntrypointInvoked -ne $false -or $probeResult.RecoveryEntrypointInvoked -ne $false -or $probeResult.ProtectedWritePerformed -ne $false){throw 'LAUNCH_DIAGNOSTIC_RESULT_INVALID'}
    $script:responseStdout=[string]$output[0]
    $script:stderrCodes=$safeErrors
    $status=[string]$probeResult.Status
    $responseStage=[string]$probeResult.Stage
    $responseCode=[string]$probeResult.ErrorCode
    if($status -ceq 'PASS'){$script:exitCode=0}else{$script:exitCode=1}
    Send-ChildResponse -Status $status -Stage $responseStage -ErrorCode $responseCode -Stdout $script:responseStdout -StderrCodes $script:stderrCodes
} catch {
    $code=Get-ChildSafeCode -Record $_
    $validStages=@('ChildBootstrap','TokenValidation','SourceIdentityValidation','InputIntegrityValidation','CandidateManifestValidation','DiagnosticSerialization')
    $safeStage=if($script:stage -in $validStages){$script:stage}else{'ChildBootstrap'}
    $diag=[pscustomobject][ordered]@{Schema='f2-g1-historical-manifest-diagnostic-v1';Authority='NON_AUTHORITATIVE_DIAGNOSTIC_ONLY';Status='FAIL';Stage=$safeStage;OperationClassification='LaunchPreflight';ExceptionCategory='SAFE_LAUNCH_FAILURE';FullyQualifiedErrorId=$code;ErrorCode=$code;TokenClass='ELEVATED';HistoricalSourceCommit='396c44965c90c08292ad2835f8317e81b6b9daaf';HistoricalUpdaterSha256=$script:updaterSha256;HistoricalLauncherSha256=$script:historicalLauncherSha256;HistoricalCandidateSha256=$script:candidateSha256;UpdaterEntrypointInvoked=$false;RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false}
    $diagJson=ConvertTo-Json -InputObject $diag -Depth 5 -Compress
    try {Send-ChildResponse -Status FAIL -Stage $safeStage -ErrorCode $code -Stdout $diagJson -StderrCodes @($code)} catch {}
    $script:exitCode=1
} finally {if($null -ne $script:pipe){$script:pipe.Dispose()}}
exit $script:exitCode

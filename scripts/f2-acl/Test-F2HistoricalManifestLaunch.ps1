[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$assertions = 0
$failures = New-Object 'System.Collections.Generic.List[string]'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $PSScriptRoot 'F2HistoricalManifestLaunch.psm1'
$startPath = Join-Path $PSScriptRoot 'Start-F2HistoricalManifestDiagnostic.ps1'
$childPath = Join-Path $PSScriptRoot 'Invoke-F2HistoricalManifestDiagnosticChild.ps1'
$wrapperPath = Join-Path $PSScriptRoot 'Invoke-F2HistoricalManifestDiagnostic.ps1'
$probeModulePath = Join-Path $PSScriptRoot 'F2HistoricalManifestDiagnostic.psm1'
$outerBootstrapPath = Join-Path $repoRoot 'docs\reviews\f2-g1-elevated-diagnostic-launch\OUTER_BOOTSTRAP.ps1'

function Assert-F2Launch {
    param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Name)
    $script:assertions++
    if (-not $Condition) { $script:failures.Add($Name) }
}

function Get-TestFileSha {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-TestLiteralPin {
    param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string]$Pattern)
    $match=[regex]::Match($Text,$Pattern)
    if(-not $match.Success){return ''}
    return $match.Groups[1].Value
}

function Get-F2LaunchAst {
    param([Parameter(Mandatory)][string]$Path)
    $tokens=$null; $parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    Assert-F2Launch -Condition ($null -ne $ast -and $parseErrors.Count -eq 0) -Name ('Parse:'+[IO.Path]::GetFileName($Path))
    return $ast
}

function Get-ChildCode {
    param([Parameter(Mandatory)][string]$Path)
    $text=[IO.File]::ReadAllText($Path)
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    $assignment=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$childBootstrapTemplate'},$true))
    if($assignment.Count -ne 1){return ''}
    return [string]$assignment[0].Right.SafeGetValue()
}

try {
    Assert-F2Launch -Condition ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1) -Name 'WindowsPowerShell51'
    Import-Module $modulePath -Force -ErrorAction Stop
    $moduleBytes=[IO.File]::ReadAllBytes($modulePath)
    $moduleText=(New-Object System.Text.UTF8Encoding($false,$true)).GetString($moduleBytes)
    $moduleInfo=New-Module -Name 'F2HistoricalManifestLaunchTest' -ScriptBlock ([scriptblock]::Create($moduleText)) -Force
    Import-Module -ModuleInfo $moduleInfo -Force -ErrorAction Stop | Out-Null

    $standardFacts=@{RequiredClass='STANDARD';UserSid='S-1-5-21-100-200-300-1001';IsElevated=$false;IsAdministrator=$false;IntegrityRid=8192;ExpectedUserSid='S-1-5-21-100-200-300-1001'}
    Assert-F2Launch -Condition (Test-F2LaunchTokenFacts @standardFacts) -Name 'StandardTokenAccepted'
    $badToken=@{}+$standardFacts;$badToken.IsElevated=$true
    Assert-F2Launch -Condition (-not (Test-F2LaunchTokenFacts @badToken)) -Name 'ElevatedParentRejected'
    $highFacts=@{RequiredClass='ELEVATED';UserSid='S-1-5-21-100-200-300-1001';IsElevated=$true;IsAdministrator=$true;IntegrityRid=12288;ExpectedUserSid='S-1-5-21-100-200-300-1001'}
    Assert-F2Launch -Condition (Test-F2LaunchTokenFacts @highFacts) -Name 'ElevatedSameRequesterAccepted'
    $otherAdmin=@{}+$highFacts;$otherAdmin.UserSid='S-1-5-21-101-201-301-1002'
    Assert-F2Launch -Condition (-not (Test-F2LaunchTokenFacts @otherAdmin)) -Name 'AlternateAdministratorIdentityRejected'
    $mediumAdmin=@{}+$highFacts;$mediumAdmin.IsElevated=$false;$mediumAdmin.IntegrityRid=8192
    Assert-F2Launch -Condition (-not (Test-F2LaunchTokenFacts @mediumAdmin)) -Name 'FilteredAdministratorRejected'

    $repoFacts=@{CanonicalRoot='C:\Dev\f2-g1-protected-updater-source';ExpectedRoot='C:\Dev\f2-g1-protected-updater-source';Origin='https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git';ExpectedOrigin='https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git';Head='396c44965c90c08292ad2835f8317e81b6b9daaf';ExpectedHead='396c44965c90c08292ad2835f8317e81b6b9daaf';Clean=$true;ReparseFree=$true}
    Assert-F2Launch -Condition (Test-F2LaunchRepositoryFacts @repoFacts) -Name 'ExactCheckoutFactsAccepted'
    foreach($field in @('CanonicalRoot','Origin','Head')){$bad=@{}+$repoFacts;$bad[$field]='C:\Temp\wrong';Assert-F2Launch -Condition (-not (Test-F2LaunchRepositoryFacts @bad)) -Name ('CheckoutMismatchRejected:'+ $field)}
    $dirty=@{}+$repoFacts;$dirty.Clean=$false
    Assert-F2Launch -Condition (-not (Test-F2LaunchRepositoryFacts @dirty)) -Name 'DirtyCheckoutRejected'
    $alias=@{}+$repoFacts;$alias.ReparseFree=$false
    Assert-F2Launch -Condition (-not (Test-F2LaunchRepositoryFacts @alias)) -Name 'ReparseCheckoutRejected'

    $expectedHashes=[ordered]@{one='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';two='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'}
    $observedHashes=[ordered]@{one=$expectedHashes.one;two=$expectedHashes.two}
    Assert-F2Launch -Condition (Test-F2LaunchHashSet -Observed $observedHashes -Expected $expectedHashes) -Name 'ExactHashSetAccepted'
    $badHashes=[ordered]@{one=$expectedHashes.one;two=('c'*64)}
    Assert-F2Launch -Condition (-not (Test-F2LaunchHashSet -Observed $badHashes -Expected $expectedHashes)) -Name 'ModifiedHashRejected'
    $allGates=@{PowerShellMajor=5;PowerShellMinor=1;StandardTokenPass=$true;SourceCheckoutPass=$true;CandidateCheckoutPass=$true;FixedPathsAndNoReparse=$true;SourceHashesPass=$true;CandidateHashPass=$true;WrapperAndModuleHashesPass=$true;HistoricalPinsPass=$true;PriorLaunchCount=0}
    Assert-F2Launch -Condition ((Test-F2LaunchPreflightFacts $allGates).Pass) -Name 'AllPreflightGatesAllowOneLaunch'
    $failedGate=@{}+$allGates;$failedGate.CandidateHashPass=$false
    $failedDecision=Test-F2LaunchPreflightFacts $failedGate
    Assert-F2Launch -Condition (-not $failedDecision.Pass -and $failedDecision.LaunchCountAfterDecision -eq 0) -Name 'CandidateTamperBlocksUac'
    $spent=@{}+$allGates;$spent.PriorLaunchCount=1
    Assert-F2Launch -Condition (-not (Test-F2LaunchPreflightFacts $spent).Pass) -Name 'SecondLaunchRejected'

    $request=New-F2LaunchRequest -RequesterSid 'S-1-5-21-100-200-300-1001' -RequesterPid 1234 -RequesterStartUtcTicks 638900000000000000 -GitPath 'C:\Program Files\Git\cmd\git.exe' -GitSha256 '7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364' -LaunchCommitSha ('e'*40) -LaunchModuleSha256 ('c'*64) -WrapperSha256 ('f'*64) -ModuleSha256 ('a'*64)
    Assert-F2Launch -Condition (Test-F2LaunchRequest $request) -Name 'RequestSchemaAccepted'
    $extraRequest=[pscustomobject]($request|Select-Object *)
    Add-Member -InputObject $extraRequest -NotePropertyName Extra -NotePropertyValue 'reject'
    Assert-F2Launch -Condition (-not (Test-F2LaunchRequest $extraRequest)) -Name 'UnexpectedRequestFieldRejected'
    $wrongAttempt=[pscustomobject]($request|Select-Object *)
    $wrongAttempt.UacAttempt=2
    Assert-F2Launch -Condition (-not (Test-F2LaunchRequest $wrongAttempt)) -Name 'RequestReplayRejected'

    $safeDiag='{"Schema":"f2-g1-historical-manifest-diagnostic-v1","Authority":"NON_AUTHORITATIVE_DIAGNOSTIC_ONLY","Status":"PASS","Stage":"CandidateManifestValidation","OperationClassification":"ManifestParseAndReviewedCommitComparison","ExceptionCategory":"NONE","FullyQualifiedErrorId":"NONE","ErrorCode":"NONE","TokenClass":"ELEVATED","HistoricalSourceCommit":"396c44965c90c08292ad2835f8317e81b6b9daaf","HistoricalUpdaterSha256":"d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2","HistoricalLauncherSha256":"9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9","HistoricalCandidateSha256":"b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022","ParsedReviewedCommitSha":"396c44965c90c08292ad2835f8317e81b6b9daaf","UpdaterEntrypointInvoked":false,"RecoveryEntrypointInvoked":false,"ProtectedWritePerformed":false}'
    $response=[pscustomobject][ordered]@{Schema='f2-g1-diagnostic-launch-response-v1';RequestId=$request.RequestId;Nonce=$request.Nonce;ChildPid=2222;ChildStartUtcTicks=638900000000000111;Status='PASS';Stage='CandidateManifestValidation';ErrorCode='NONE';Stdout=$safeDiag;StderrCodes=@();LaunchModuleSha256=$request.LaunchModuleSha256;WrapperSha256=$request.WrapperSha256;ModuleSha256=$request.ModuleSha256;UpdaterEntrypointInvoked=$false;RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false}
    Assert-F2Launch -Condition (Test-F2LaunchResponse -Response $response -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0) -Name 'AuthenticatedPassResponseAccepted'
    $badNonce=[pscustomobject]($response|Select-Object *);$badNonce.Nonce=('0'*64)
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $badNonce -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'NonceMismatchRejected'
    $badPeer=@{ExpectedPid=2222;ExpectedStartUtcTicks=638900000000000111;ObservedPid=2223;ObservedStartUtcTicks=638900000000000111;CommandLineMatches=$true;TokenMatches=$true}
    Assert-F2Launch -Condition (-not (Test-F2LaunchPeerFacts @badPeer)) -Name 'WrongPeerPidRejected'
    $badStart=@{}+$badPeer;$badStart.ObservedPid=2222;$badStart.ObservedStartUtcTicks=638900000000000112
    Assert-F2Launch -Condition (-not (Test-F2LaunchPeerFacts @badStart)) -Name 'ReusedPeerPidRejected'
    $hello=[pscustomobject][ordered]@{Schema='f2-g1-diagnostic-launch-hello-v1';ProcessId=2222;StartUtcTicks=638900000000000111}
    Assert-F2Launch -Condition (Test-F2LaunchHello -Hello $hello -ExpectedPid 2222 -ExpectedStartUtcTicks 638900000000000111) -Name 'PeerHelloBoundToPidAndCreationTime'
    $badHello=[pscustomobject]@{Schema=$hello.Schema;ProcessId=2223;StartUtcTicks=$hello.StartUtcTicks;Extra='reject'}
    Assert-F2Launch -Condition (-not (Test-F2LaunchHello -Hello $badHello -ExpectedPid 2222 -ExpectedStartUtcTicks 638900000000000111)) -Name 'BadPeerHelloRejected'
    $badStdout=[pscustomobject]($response|Select-Object *);$badStdout.Stdout='{"path":"C:\ProgramData\sensitive"}'
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $badStdout -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'PathLeakRejected'
    $falseSuccess=[pscustomobject]($response|Select-Object *);$falseSuccess.ProtectedWritePerformed=$true
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $falseSuccess -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'FalseSafetyClaimRejected'
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $response -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 1)) -Name 'ConflictingExitRejected'
    $badDiagnostic=[pscustomobject]($response|Select-Object *);$badDiagnostic.Stdout=$safeDiag.Replace('ManifestParseAndReviewedCommitComparison','WrongOperation')
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $badDiagnostic -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'NestedDiagnosticMismatchRejected'
    $rawFqid=[pscustomobject]($response|Select-Object *);$rawFqid.Stdout=$safeDiag.Replace('"FullyQualifiedErrorId":"NONE"','"FullyQualifiedErrorId":"RawSensitiveValue"')
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $rawFqid -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'UnlistedNestedErrorIdRejected'
    $validFailure=[ordered]@{Schema='f2-g1-historical-manifest-diagnostic-v1';Authority='NON_AUTHORITATIVE_DIAGNOSTIC_ONLY';Status='FAIL';Stage='CandidateManifestValidation';OperationClassification='ReviewedCommitShaComparison';ExceptionCategory='REVIEWED_COMMIT_MISMATCH';FullyQualifiedErrorId='UPDATE_CANDIDATE_COMMIT_MISMATCH';ErrorCode='UPDATE_CANDIDATE_COMMIT_MISMATCH';TokenClass='ELEVATED';HistoricalSourceCommit='396c44965c90c08292ad2835f8317e81b6b9daaf';HistoricalUpdaterSha256='d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2';HistoricalLauncherSha256='9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9';HistoricalCandidateSha256='b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022';UpdaterEntrypointInvoked=$false;RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false}
    $validFailureResponse=[pscustomobject][ordered]@{Schema='f2-g1-diagnostic-launch-response-v1';RequestId=$request.RequestId;Nonce=$request.Nonce;ChildPid=2222;ChildStartUtcTicks=638900000000000111;Status='FAIL';Stage='CandidateManifestValidation';ErrorCode='UPDATE_CANDIDATE_COMMIT_MISMATCH';Stdout=(ConvertTo-Json -InputObject $validFailure -Compress);StderrCodes=@('UPDATE_CANDIDATE_COMMIT_MISMATCH');LaunchModuleSha256=$request.LaunchModuleSha256;WrapperSha256=$request.WrapperSha256;ModuleSha256=$request.ModuleSha256;UpdaterEntrypointInvoked=$false;RecoveryEntrypointInvoked=$false;ProtectedWritePerformed=$false}
    Assert-F2Launch -Condition (Test-F2LaunchResponse -Response $validFailureResponse -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 1) -Name 'SanitizedStructuredFailureAccepted'
    $failureWithPassField=[ordered]@{}+$validFailure;$failureWithPassField.ParsedReviewedCommitSha='arbitrary-value'
    $failureWithPassResponse=[pscustomobject]($validFailureResponse|Select-Object *);$failureWithPassResponse.Stdout=ConvertTo-Json -InputObject $failureWithPassField -Compress
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $failureWithPassResponse -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 1)) -Name 'FailureCannotPublishOptionalPassOnlyField'
    $falsePass=[pscustomobject]($response|Select-Object *);$falsePass.ErrorCode='UPDATE_MANIFEST_JSON_INVALID'
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $falsePass -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'PassRequiresNoneErrorCode'
    $largeDiagnostic=[pscustomobject]($response|Select-Object *);$largeDiagnostic.Stdout='{' + ('x'*4096) + '}'
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $largeDiagnostic -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'DiagnosticStdoutLimitEnforced'
    $manyErrors=[pscustomobject]($response|Select-Object *);$manyErrors.StderrCodes=@('UNLISTED')*17
    Assert-F2Launch -Condition (-not (Test-F2LaunchResponse -Response $manyErrors -Request $request -PipePeerPid 2222 -PipePeerStartUtcTicks 638900000000000111 -ActualExitCode 0)) -Name 'DiagnosticStderrCountLimitEnforced'

    $frame=ConvertTo-F2LaunchFrame -Json $safeDiag
    Assert-F2Launch -Condition ((Read-F2LaunchFrameBytes -Frame $frame) -ceq $safeDiag) -Name 'FrameRoundTrip'
    $trailing=New-Object byte[] ($frame.Length+1);[Array]::Copy($frame,$trailing,$frame.Length)
    $badFrameCaught=$false;try{Read-F2LaunchFrameBytes -Frame $trailing|Out-Null}catch{$badFrameCaught=$true}
    Assert-F2Launch -Condition $badFrameCaught -Name 'TrailingFrameBytesRejected'
    $tooLongCaught=$false;try{ConvertTo-F2LaunchFrame -Json ('x'*8193)|Out-Null}catch{$tooLongCaught=$true}
    Assert-F2Launch -Condition $tooLongCaught -Name 'OversizedFrameRejected'

    Assert-F2Launch -Condition ($null -ne (Get-Command -Name 'Test-F2LaunchRequest' -ErrorAction SilentlyContinue)) -Name 'ProductionModuleImported'
    $tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('F2LaunchFixture-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($tempRoot)|Out-Null
    try {
        $file=Join-Path $tempRoot 'fixture.bin';[IO.File]::WriteAllBytes($file,[byte[]](1,2,3,4))
        $pin=Get-TestFileSha -Path $file
        $loaded=Read-F2LaunchPinnedFile -Path $file -ExpectedSha256 $pin -MaximumBytes 64
        Assert-F2Launch -Condition ((Get-F2LaunchSha256 -Bytes $loaded) -ceq $pin) -Name 'PinnedReadUsesExactBytes'
        $memoryPath=Join-Path $tempRoot 'verified.ps1';$oldText="Write-Output 'verified-bytes'"
        [IO.File]::WriteAllText($memoryPath,$oldText,(New-Object Text.UTF8Encoding($false)))
        $oldBytes=Read-F2LaunchPinnedFile -Path $memoryPath -ExpectedSha256 (Get-TestFileSha $memoryPath) -MaximumBytes 128
        [IO.File]::WriteAllText($memoryPath,"Write-Output 'substituted-bytes'",(New-Object Text.UTF8Encoding($false)))
        $verifiedBlock=ConvertTo-F2LaunchVerifiedScriptBlock -Bytes $oldBytes -ExpectedSha256 (Get-F2LaunchSha256 -Bytes $oldBytes) -MaximumBytes 128
        $verifiedOutput=@(& $verifiedBlock)
        Assert-F2Launch -Condition ($verifiedOutput.Count -eq 1 -and $verifiedOutput[0] -ceq 'verified-bytes') -Name 'VerifiedInMemoryBytesResistPostReadFileSubstitution'
        $launchBlockTamperRejected=$false;try{ConvertTo-F2LaunchVerifiedScriptBlock -Bytes $oldBytes -ExpectedSha256 ('0'*64) -MaximumBytes 128|Out-Null}catch{$launchBlockTamperRejected=([string]$_.FullyQualifiedErrorId -match 'LAUNCH_FILE_HASH_MISMATCH')}
        Assert-F2Launch -Condition $launchBlockTamperRejected -Name 'VerifiedScriptBlockRejectsTamperedBytesBeforeCreation'
        $invalidScriptBytes=[Text.Encoding]::UTF8.GetBytes("if (`$x) {`n")
        $invalidScriptRejected=$false;try{ConvertTo-F2LaunchVerifiedScriptBlock -Bytes $invalidScriptBytes -ExpectedSha256 (Get-F2LaunchSha256 -Bytes $invalidScriptBytes) -MaximumBytes 128|Out-Null}catch{$invalidScriptRejected=([string]$_.FullyQualifiedErrorId -match 'LAUNCH_SCRIPT_PARSE_REJECTED')}
        Assert-F2Launch -Condition $invalidScriptRejected -Name 'VerifiedScriptBlockRejectsMalformedScript'
        $tamperCaught=$false;try{Read-F2LaunchPinnedFile -Path $file -ExpectedSha256 ('0'*64) -MaximumBytes 64|Out-Null}catch{$tamperCaught=$true}
        Assert-F2Launch -Condition $tamperCaught -Name 'PinnedReadTamperRejected'
        Assert-F2Launch -Condition (Test-F2LaunchNoReparsePath -Path $file) -Name 'TempPathNoReparsePass'
        $target=Join-Path $tempRoot 'target';$alias=Join-Path $tempRoot 'alias'
        [IO.Directory]::CreateDirectory($target)|Out-Null
        $junctionStart=New-Object Diagnostics.ProcessStartInfo;$junctionStart.FileName=Join-Path $env:SystemRoot 'System32\cmd.exe';$junctionStart.Arguments='/d /c mklink /J "'+$alias+'" "'+$target+'" >NUL 2>&1';$junctionStart.UseShellExecute=$false;$junctionStart.CreateNoWindow=$true
        $junctionProcess=New-Object Diagnostics.Process;$junctionProcess.StartInfo=$junctionStart
        try{[void]$junctionProcess.Start();$junctionFinished=$junctionProcess.WaitForExit(5000);if($junctionFinished -and $junctionProcess.ExitCode -eq 0){$reparseCaught=$false;try{Test-F2LaunchNoReparsePath -Path $alias|Out-Null}catch{$reparseCaught=$true};Assert-F2Launch -Condition $reparseCaught -Name 'DirectoryJunctionRejected'}else{Assert-F2Launch -Condition (-not (Test-Path -LiteralPath $alias)) -Name 'UnavailableJunctionFixtureNotTrusted'}}finally{$junctionProcess.Dispose()}
    } finally { if(Test-Path -LiteralPath $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force} }

    $nativeSource=Initialize-F2LaunchNative
    Assert-F2Launch -Condition ($null -ne ('F2HistoricalLaunchNative' -as [type]) -and $nativeSource.Length -gt 1000) -Name 'ExactPipeNativeHelperCompiles'
    $token=Get-F2LaunchTokenFacts
    Assert-F2Launch -Condition ($token.IntegrityRid -ge 0x1000 -and $token.UserSid -match '^S-1-[0-9-]+$') -Name 'LiveTokenProbeReturnsClassificationOnly'
    Assert-F2Launch -Condition ([F2HistoricalLaunchNative]::ProcessSid([uint32]$PID) -ceq $token.UserSid) -Name 'NativeProcessSidMatchesCurrentSyntheticPeer'
    $pipeSecurity=New-F2LaunchPipeSecurity -RequesterSid $token.UserSid
    $rules=@($pipeSecurity.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    Assert-F2Launch -Condition ($pipeSecurity.AreAccessRulesProtected -and $rules.Count -eq 3) -Name 'OneShotPipeUsesProtectedThreePrincipalDacl'
    $allowedSids=@($rules|ForEach-Object{$_.IdentityReference.Value})
    Assert-F2Launch -Condition (@($allowedSids|Where-Object{$_ -notin @($token.UserSid,'S-1-5-32-544','S-1-5-18')}).Count -eq 0) -Name 'PipeAclHasNoBroadPrincipal'
    Assert-F2Launch -Condition ($nativeSource.Contains('PIPE_REJECT_REMOTE_CLIENTS') -and $nativeSource.Contains('FILE_FLAG_FIRST_PIPE_INSTANCE')) -Name 'LocalFirstInstanceRejectsRemotePipeClients'
    $pipeName='F2D_'+[guid]::NewGuid().ToString('N')
    $server=New-F2LaunchServerStream -ShortName $pipeName -RequesterSid $token.UserSid
    $pipeTestChild=$null
    try {
        $childCode='$c=New-Object System.IO.Pipes.NamedPipeClientStream(".","'+$pipeName+'",[IO.Pipes.PipeDirection]::InOut,[IO.Pipes.PipeOptions]::None);$c.Connect(5000);$b=[Text.Encoding]::UTF8.GetBytes("fixture");$c.Write($b,0,$b.Length);$c.Flush();$a=New-Object byte[] 1;$null=$c.Read($a,0,1);$c.Dispose();exit 0'
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCode))
        $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$powershell;$start.Arguments='-NoProfile -NonInteractive -EncodedCommand '+$encoded;$start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $pipeTestChild=New-Object Diagnostics.Process;$pipeTestChild.StartInfo=$start
        $accept=$server.BeginWaitForConnection($null,$null)
        [void]$pipeTestChild.Start()
        Assert-F2Launch -Condition ($accept.AsyncWaitHandle.WaitOne(8000)) -Name 'SameTokenTestChildConnected'
        if($accept.IsCompleted){
            $server.EndWaitForConnection($accept)
            $peer=[F2HistoricalLaunchNative]::ClientPid($server.SafePipeHandle.DangerousGetHandle())
            $peerSid=[F2HistoricalLaunchNative]::ProcessSid([uint32]$peer)
            $buf=New-Object byte[] 16;$read=$server.Read($buf,0,$buf.Length);$txt=[Text.Encoding]::UTF8.GetString($buf,0,$read)
            $impersonationBox=@{Facts=$null}
            $impersonationCallback={
                $id=[Security.Principal.WindowsIdentity]::GetCurrent()
                try{$p=New-Object Security.Principal.WindowsPrincipal($id);$impersonationBox.Facts=[pscustomobject]@{Sid=$id.User.Value;Admin=$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}}finally{$id.Dispose()}
            }.GetNewClosure()
            $server.RunAsClient($impersonationCallback)
            $ack=[byte[]](1);$server.Write($ack,0,1);$server.Flush()
            $null=$pipeTestChild.WaitForExit(5000)
            Assert-F2Launch -Condition ($peer -eq $pipeTestChild.Id -and $pipeTestChild.ExitCode -eq 0 -and $txt -ceq 'fixture') -Name 'SameTokenPeerPidAndBoundedPipePayload'
            Assert-F2Launch -Condition ($peerSid -ceq $token.UserSid) -Name 'SameTokenNamedPipeClientProcessSid'
            Assert-F2Launch -Condition ($null -ne $impersonationBox.Facts -and $impersonationBox.Facts.Sid -ceq $token.UserSid) -Name 'PipePeerImpersonationIdentityCaptured'
        }
    } finally {if($null -ne $pipeTestChild){$pipeTestChild.Dispose()};$server.Dispose()}

    $expectedImage=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $encodedFixture='QQBCQw=='
    $cmdRecord=[pscustomobject]@{ProcessId=2222;Name='powershell.exe';ExecutablePath=$expectedImage;CommandLine='"'+$expectedImage+'" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand '+$encodedFixture}
    Assert-F2Launch -Condition (Test-F2LaunchCommandLineRecord -Instances @($cmdRecord) -ExpectedProcessId 2222 -ExpectedImagePath $expectedImage -ExpectedEncodedCommand $encodedFixture) -Name 'ExactChildCommandLineAccepted'
    foreach($badRecord in @(
        [pscustomobject]@{ProcessId=2222;Name='powershell.exe';ExecutablePath=$expectedImage;CommandLine=$null},
        [pscustomobject]@{ProcessId=2222;Name='powershell.exe';ExecutablePath=$expectedImage;CommandLine=$cmdRecord.CommandLine+' -File evil.ps1'},
        [pscustomobject]@{ProcessId=2222;Name='powershell.exe';ExecutablePath='C:\Temp\powershell.exe';CommandLine=$cmdRecord.CommandLine},
        [pscustomobject]@{ProcessId=2223;Name='powershell.exe';ExecutablePath=$expectedImage;CommandLine=$cmdRecord.CommandLine}
    )){Assert-F2Launch -Condition (-not (Test-F2LaunchCommandLineRecord -Instances @($badRecord) -ExpectedProcessId 2222 -ExpectedImagePath $expectedImage -ExpectedEncodedCommand $encodedFixture)) -Name 'WrongOrUnavailableChildCommandLineRejected'}
    Assert-F2Launch -Condition (-not (Test-F2LaunchCommandLineRecord -Instances @($cmdRecord,$cmdRecord) -ExpectedProcessId 2222 -ExpectedImagePath $expectedImage -ExpectedEncodedCommand $encodedFixture)) -Name 'AmbiguousChildCommandLineRejected'

    $runspace=[runspacefactory]::CreateRunspace();$runner=[powershell]::Create()
    try{$runspace.Open();$runner.Runspace=$runspace;$null=$runner.AddScript("Write-Output 'bounded synthetic output'; exit 0");$runOutput=@($runner.Invoke());Assert-F2Launch -Condition ($runOutput.Count -eq 1 -and $runOutput[0] -ceq 'bounded synthetic output' -and $runner.InvocationStateInfo.State -eq [Management.Automation.PSInvocationState]::Completed) -Name 'ScriptBlockExitRemainsInsideDedicatedRunspace'}finally{$runner.Dispose();$runspace.Dispose()}

    $pinnedGitPath='C:\Program Files\Git\cmd\git.exe';$pinnedGitHash='7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364'
    if(Test-Path -LiteralPath $pinnedGitPath -PathType Leaf){
        if((Get-TestFileSha $pinnedGitPath) -ceq $pinnedGitHash){
            $actualHead=(& $pinnedGitPath -C $repoRoot rev-parse HEAD).Trim()
            $realRepo=Get-F2LaunchRepositoryFacts -GitPath $pinnedGitPath -ExpectedGitSha256 $pinnedGitHash -Repository $repoRoot -ExpectedRoot $repoRoot -ExpectedHead $actualHead
            Assert-F2Launch -Condition ($realRepo.RootMatches -and $realRepo.Head -ceq $actualHead) -Name 'PinnedGitReadOnlyRepositoryInspection'
        }else{
            $gitPinRejected=$false;try{Get-F2LaunchRepositoryFacts -GitPath $pinnedGitPath -ExpectedGitSha256 $pinnedGitHash -Repository $repoRoot -ExpectedRoot $repoRoot -ExpectedHead ('0'*40)|Out-Null}catch{$gitPinRejected=([string]$_.FullyQualifiedErrorId -match 'LAUNCH_GIT_PATH_REJECTED')}
            Assert-F2Launch -Condition $gitPinRejected -Name 'UnrecognizedGitBinaryRejected'
        }
    }else{Assert-F2Launch -Condition $true -Name 'PinnedGitBinaryUnavailableFailsClosedByPathGate'}

    foreach($productionFile in @($modulePath,$startPath,$childPath,$wrapperPath,$probeModulePath,$outerBootstrapPath)) { if(Test-Path -LiteralPath $productionFile){[void](Get-F2LaunchAst -Path $productionFile)} }
    $productionFiles=@($modulePath,$startPath,$childPath,$wrapperPath,$probeModulePath,$outerBootstrapPath)
    if(@($productionFiles|Where-Object{Test-Path -LiteralPath $_}).Count -eq $productionFiles.Count){
        Assert-F2Launch -Condition (Test-F2LaunchNoForbiddenOperations -SourcePaths $productionFiles) -Name 'ProductionAstExcludesProtectedOperations'
    } else { Assert-F2Launch -Condition $false -Name 'ProductionLaunchFilesPresent' }
    $productionText=($productionFiles|ForEach-Object{[IO.File]::ReadAllText($_)}) -join "`n"
    Assert-F2Launch -Condition ($productionText -notmatch '(?i)C:\\Program Files\\F2-G1-Icacls|C:\\ProgramData\\F2-G1-Icacls|G:\\|F2-G1-Isolated-Disposable') -Name 'NoProtectedPathLiteral'
    Assert-F2Launch -Condition ($productionText -match '(?i)PIPE_REJECT_REMOTE_CLIENTS' -and $productionText -match '(?i)FILE_FLAG_FIRST_PIPE_INSTANCE' -and $productionText -match '(?i)-Verb\s+RunAs') -Name 'OneShotLocalAuthenticatedUacBoundaryPresent'
    $startAst=Get-F2LaunchAst -Path $startPath
    $startCommands=@($startAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|Where-Object{$_.GetCommandName() -ceq 'Start-Process'})
    Assert-F2Launch -Condition ($startCommands.Count -eq 1) -Name 'ExactlyOneUacLaunchSite'
    $childCommands=@((Get-F2LaunchAst -Path $childPath).FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|Where-Object{$_.GetCommandName() -ceq 'Start-Process'})
    Assert-F2Launch -Condition ($childCommands.Count -eq 0) -Name 'ElevatedChildCannotLaunchAnotherProcess'
    $outerAst=Get-F2LaunchAst -Path $outerBootstrapPath
    $outerStartCommands=@($outerAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|Where-Object{$_.GetCommandName() -ceq 'Start-Process'})
    Assert-F2Launch -Condition ($outerStartCommands.Count -eq 0 -and [IO.File]::ReadAllText($outerBootstrapPath) -match 'ConvertTo-F2LaunchVerifiedScriptBlock' -and [IO.File]::ReadAllText($outerBootstrapPath) -match 'Get-F2LaunchRepositoryFacts') -Name 'OuterBootstrapOnlyExecutesPinnedInMemoryLauncherAfterCheckoutGate'
    $outerLaunchSource=[IO.File]::ReadAllText($outerBootstrapPath);$startLaunchSource=[IO.File]::ReadAllText($startPath)
    Assert-F2Launch -Condition ($outerLaunchSource.IndexOf('$env:PSModulePath', [StringComparison]::Ordinal) -lt $outerLaunchSource.IndexOf('Get-Item', [StringComparison]::Ordinal) -and $startLaunchSource.Contains('`$env:PSModulePath=`$PSHOME+''\Modules''')) -Name 'OuterAndElevatedProcessExcludeRequesterModuleSearchPaths'
    $nativeSourceNoWrites=($nativeSource -notmatch '(?is)(File\.Write(All)?Bytes|File\.WriteAllText|Directory\.CreateDirectory|SetAccessControl|SetSecurityDescriptor|Set-Acl|icacls|Get-VM|Start-VM|Invoke-F2ProtectedReleaseUpdate|Invoke-F2ProtectedReleaseRecovery)')
    Assert-F2Launch -Condition $nativeSourceNoWrites -Name 'NativeHelperHasNoProtectedMutationOrUpdaterCode'
    Assert-F2Launch -Condition ($nativeSource -match 's\.FileName=fileName' -and $moduleText -match 'F2LaunchExpectedGitPath') -Name 'OnlyPinnedGitHelperProcessIsSpawned'
    $childText=[IO.File]::ReadAllText($childPath)
    $wrapperText=[IO.File]::ReadAllText($wrapperPath)
    Assert-F2Launch -Condition ($childText -match 'function Read-ChildPinnedFile' -and $childText -notmatch '\[IO\.File\]::ReadAllBytes') -Name 'ElevatedChildUsesBoundedSingleReadForPinnedModule'
    Assert-F2Launch -Condition ($moduleText -match "ValidateSet\('Top','Origin','Head','Status'\)" -and $moduleText -match 'RunGitBounded\(\$GitPath,\$arguments,\$Repository' -and $moduleText -match 'GIT_OPTIONAL_LOCKS') -Name 'GitChildInvocationIsFixedReadOnlyQuerySet'
    $wrapperFunctionNames=@('Test-F2ProbeNoReparsePath','Get-F2ProbeModuleBytes')
    $wrapperFunctionAsts=@((Get-F2LaunchAst -Path $wrapperPath).FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $wrapperFunctionNames -contains $n.Name},$true))
    $wrapperFunctionBundle=($wrapperFunctionAsts|Sort-Object Name|ForEach-Object{$_.Extent.Text}) -join "`n"
    $moduleReaderTemp=Join-Path ([IO.Path]::GetTempPath()) ('F2ProbeModuleReader-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($moduleReaderTemp)|Out-Null
    $moduleReaderRunspace=[runspacefactory]::CreateRunspace();$moduleReaderRunner=[powershell]::Create()
    try {
        $moduleReaderRunspace.Open();$moduleReaderRunspace.SessionStateProxy.SetVariable('fixtureModuleBytes',[IO.File]::ReadAllBytes($probeModulePath));$moduleReaderRunspace.SessionStateProxy.SetVariable('fixtureScriptRoot','')
        $moduleReaderRunner.Runspace=$moduleReaderRunspace
        $emptyScriptRootJoinFailed=$false;try{Join-Path '' 'F2HistoricalManifestDiagnostic.psm1'|Out-Null}catch{$emptyScriptRootJoinFailed=$true}
        Assert-F2Launch -Condition $emptyScriptRootJoinFailed -Name 'WindowsPowerShell51EmptyScriptRootJoinPathHazardReproduced'
        $null=$moduleReaderRunner.AddScript($wrapperFunctionBundle+"`n`$resolved=Get-F2ProbeModuleBytes -InMemoryModuleBytes `$fixtureModuleBytes -ScriptRoot `$fixtureScriptRoot; ,`$resolved")
        $moduleReaderOutput=@($moduleReaderRunner.Invoke())
        Assert-F2Launch -Condition ($moduleReaderOutput.Count -eq 1 -and $moduleReaderOutput[0] -is [byte[]] -and (Get-F2LaunchSha256 -Bytes ([byte[]]$moduleReaderOutput[0])) -ceq '4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee') -Name 'ActualWrapperModuleReaderUsesPinnedMemoryBytesWithEmptyScriptRoot'
        $moduleReaderRunspace.SessionStateProxy.SetVariable('fixtureModuleBytes','not-byte-array')
        $moduleReaderRunner.Commands.Clear();$null=$moduleReaderRunner.AddScript("try{Get-F2ProbeModuleBytes -InMemoryModuleBytes `$fixtureModuleBytes -ScriptRoot ''|Out-Null;'NOT_REJECTED'}catch{([string]`$_.FullyQualifiedErrorId).Split(',')[0]}")
        $badMemoryOutput=@($moduleReaderRunner.Invoke())
        Assert-F2Launch -Condition ($badMemoryOutput.Count -eq 1 -and $badMemoryOutput[0] -ceq 'PROBE_MODULE_INPUT_INVALID') -Name 'ActualWrapperModuleReaderRejectsNonByteInMemoryInput'
        $moduleReaderRunspace.SessionStateProxy.SetVariable('fixtureModuleBytes',[byte[]]@())
        $moduleReaderRunner.Commands.Clear();$null=$moduleReaderRunner.AddScript("try{Get-F2ProbeModuleBytes -InMemoryModuleBytes `$fixtureModuleBytes -ScriptRoot ''|Out-Null;'NOT_REJECTED'}catch{([string]`$_.FullyQualifiedErrorId).Split(',')[0]}")
        $emptyMemoryOutput=@($moduleReaderRunner.Invoke())
        Assert-F2Launch -Condition ($emptyMemoryOutput.Count -eq 1 -and $emptyMemoryOutput[0] -ceq 'PROBE_MODULE_INPUT_INVALID') -Name 'ActualWrapperModuleReaderRejectsEmptyInMemoryBytes'
        $moduleReaderRunspace.SessionStateProxy.SetVariable('fixtureModuleBytes',[byte[]]::new(131073))
        $moduleReaderRunner.Commands.Clear();$null=$moduleReaderRunner.AddScript("try{Get-F2ProbeModuleBytes -InMemoryModuleBytes `$fixtureModuleBytes -ScriptRoot ''|Out-Null;'NOT_REJECTED'}catch{([string]`$_.FullyQualifiedErrorId).Split(',')[0]}")
        $oversizeMemoryOutput=@($moduleReaderRunner.Invoke())
        Assert-F2Launch -Condition ($oversizeMemoryOutput.Count -eq 1 -and $oversizeMemoryOutput[0] -ceq 'PROBE_MODULE_INPUT_INVALID') -Name 'ActualWrapperModuleReaderRejectsOversizedInMemoryBytes'
        $tempModulePath=Join-Path $moduleReaderTemp 'F2HistoricalManifestDiagnostic.psm1';$tempBytes=[byte[]](5,6,7,8);[IO.File]::WriteAllBytes($tempModulePath,$tempBytes)
        $moduleReaderRunspace.SessionStateProxy.SetVariable('fixtureModuleBytes',$null);$moduleReaderRunspace.SessionStateProxy.SetVariable('fixtureScriptRoot',$moduleReaderTemp)
        $moduleReaderRunner.Commands.Clear();$null=$moduleReaderRunner.AddScript($wrapperFunctionBundle+"`n`$resolved=Get-F2ProbeModuleBytes -InMemoryModuleBytes `$fixtureModuleBytes -ScriptRoot `$fixtureScriptRoot; ,`$resolved")
        $fallbackOutput=@($moduleReaderRunner.Invoke())
        Assert-F2Launch -Condition ($fallbackOutput.Count -eq 1 -and $fallbackOutput[0] -is [byte[]] -and [BitConverter]::ToString([byte[]]$fallbackOutput[0]) -ceq '05-06-07-08') -Name 'ActualWrapperModuleReaderUsesBoundedDiskFallbackOnlyWhenMemoryAbsent'
    } finally {$moduleReaderRunner.Dispose();$moduleReaderRunspace.Dispose();if(Test-Path -LiteralPath $moduleReaderTemp){Remove-Item -LiteralPath $moduleReaderTemp -Recurse -Force}}
    $childFunctionNames=@('Test-ChildNoReparsePath','Get-ChildByteSha256','Read-ChildPinnedFile')
    $childFunctionAsts=@((Get-F2LaunchAst -Path $childPath).FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $childFunctionNames -contains $n.Name},$true))
    $childFunctionBundle=($childFunctionAsts|Sort-Object Name|ForEach-Object{$_.Extent.Text}) -join "`n"
    $childFunctionHarness=[scriptblock]::Create($childFunctionBundle+"`n`$readResult=Read-ChildPinnedFile -Path `$fixturePath -ExpectedSha256 `$fixtureSha -MaximumBytes 64; if((Get-ChildByteSha256 -Bytes `$readResult) -cne `$fixtureSha){throw 'FIXTURE_HASH_MISMATCH'}; ,`$readResult")
    $childReadRoot=Join-Path ([IO.Path]::GetTempPath()) ('F2ChildRead-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($childReadRoot)|Out-Null
    try {
        $childReadFile=Join-Path $childReadRoot 'module.bin';$childReadBytes=[byte[]](11,22,33,44);[IO.File]::WriteAllBytes($childReadFile,$childReadBytes);$childReadSha=Get-TestFileSha $childReadFile
        $childReadBlock=[scriptblock]::Create('$fixturePath=$args[0];$fixtureSha=$args[1];'+$childFunctionHarness.ToString())
        $childReadOutput=@(& $childReadBlock $childReadFile $childReadSha)
        Assert-F2Launch -Condition ($childReadOutput.Count -eq 1 -and (Get-F2LaunchSha256 -Bytes ([byte[]]$childReadOutput[0])) -ceq $childReadSha) -Name 'ChildProductionPinnedReaderAcceptsExactTemporaryFixture'
        $childBadHashBlock=[scriptblock]::Create('$fixturePath=$args[0];$fixtureSha=("0"*64);'+$childFunctionHarness.ToString())
        $childBadHashRejected=$false;try{& $childBadHashBlock $childReadFile $childReadSha|Out-Null}catch{$childBadHashRejected=([string]$_.FullyQualifiedErrorId -match 'LAUNCH_FILE_HASH_MISMATCH')}
        Assert-F2Launch -Condition $childBadHashRejected -Name 'ChildProductionPinnedReaderRejectsTamperedTemporaryFixture'
        $childOversizeRejected=$false;try{& ([scriptblock]::Create('$fixturePath=$args[0];$fixtureSha=$args[1];'+$childFunctionBundle+"`nRead-ChildPinnedFile -Path `$fixturePath -ExpectedSha256 `$fixtureSha -MaximumBytes 3")) $childReadFile $childReadSha|Out-Null}catch{$childOversizeRejected=([string]$_.FullyQualifiedErrorId -match 'LAUNCH_FILE_TYPE_OR_SIZE_INVALID')}
        Assert-F2Launch -Condition $childOversizeRejected -Name 'ChildProductionPinnedReaderRejectsOversizeTemporaryFixture'
    } finally {if(Test-Path -LiteralPath $childReadRoot){Remove-Item -LiteralPath $childReadRoot -Recurse -Force}}
    $dangerousFixture=Join-Path ([IO.Path]::GetTempPath()) ('F2LaunchDanger-'+[guid]::NewGuid().ToString('N')+'.ps1')
    try {
        [IO.File]::WriteAllText($dangerousFixture,"Set-Acl -Path 'x' -AclObject 'y'`r`n[IO.File]::WriteAllBytes('x',[byte[]](1))",(New-Object Text.UTF8Encoding($false)))
        Assert-F2Launch -Condition (-not (Test-F2LaunchNoForbiddenOperations -SourcePaths @($dangerousFixture))) -Name 'MutationFixtureRejectedBySourcePolicy'
    } finally { if(Test-Path -LiteralPath $dangerousFixture){Remove-Item -LiteralPath $dangerousFixture -Force} }

    $startText=[IO.File]::ReadAllText($startPath);$childText=[IO.File]::ReadAllText($childPath);$wrapperText=[IO.File]::ReadAllText($wrapperPath);$probeText=[IO.File]::ReadAllText($probeModulePath);$outerText=[IO.File]::ReadAllText($outerBootstrapPath)
    $wrapperSha=Get-TestFileSha $wrapperPath;$launchModuleSha=Get-TestFileSha $modulePath;$probeSha=Get-TestFileSha $probeModulePath;$childSha=Get-TestFileSha $childPath;$launcherSha=Get-TestFileSha $startPath
    Assert-F2Launch -Condition ((Get-TestLiteralPin $moduleText "F2LaunchExpectedWrapperSha256\s*=\s*'([0-9a-f]{64})'") -ceq $wrapperSha) -Name 'LaunchModulePinsExactWrapperWorkingBytes'
    Assert-F2Launch -Condition ((Get-TestLiteralPin $moduleText "F2LaunchExpectedProbeModuleSha256\s*=\s*'([0-9a-f]{64})'") -ceq $probeSha) -Name 'LaunchModulePinsExactDiagnosticModuleBytes'
    Assert-F2Launch -Condition ((Get-TestLiteralPin $startText "expectedWrapperSha256\s*=\s*'([0-9a-f]{64})'") -ceq $wrapperSha -and (Get-TestLiteralPin $startText "expectedChildSha256\s*=\s*'([0-9a-f]{64})'") -ceq $childSha) -Name 'RequesterPinsExactWrapperAndChildBytes'
    Assert-F2Launch -Condition ((Get-TestLiteralPin $childText "launchModuleSha256\s*=\s*'([0-9a-f]{64})'") -ceq $launchModuleSha -and (Get-TestLiteralPin $childText "wrapperSha256\s*=\s*'([0-9a-f]{64})'") -ceq $wrapperSha -and (Get-TestLiteralPin $childText "probeModuleSha256\s*=\s*'([0-9a-f]{64})'") -ceq $probeSha) -Name 'ElevatedChildPinsExactLaunchWrapperAndProbeModuleBytes'
    Assert-F2Launch -Condition ((Get-TestLiteralPin $wrapperText "moduleSha256\s*-cne\s*'([0-9a-f]{64})'") -ceq $probeSha) -Name 'WrapperPinsExactDiagnosticModuleBytes'
    Assert-F2Launch -Condition ((Get-TestLiteralPin $outerText "expectedLaunchModuleSha256\s*=\s*'([0-9a-f]{64})'") -ceq $launchModuleSha -and (Get-TestLiteralPin $outerText "expectedLauncherSha256\s*=\s*'([0-9a-f]{64})'") -ceq $launcherSha) -Name 'OuterBootstrapPinsExactModuleAndLauncherBytes'
    Assert-F2Launch -Condition ($outerText -notmatch '__[A-Z0-9_]+__' -and $startText -notmatch '__[A-Z0-9_]+__' -and $childText -notmatch '__[A-Z0-9_]+__' -and $moduleText -notmatch '__[A-Z0-9_]+__') -Name 'PublishedProductionPinsHaveNoUnresolvedPlaceholders'
    $commandPath=Join-Path (Split-Path $outerBootstrapPath -Parent) 'EXACT_UAC_COMMAND.txt'
    if(Test-Path -LiteralPath $commandPath){
        $commandText=[IO.File]::ReadAllText($commandPath)
        $encodedMatch=[regex]::Match($commandText,'-EncodedCommand\s+(?<encoded>[A-Za-z0-9+/=]+)')
        $decodedOuter=if($encodedMatch.Success){[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encodedMatch.Groups['encoded'].Value))}else{''}
        Assert-F2Launch -Condition ($encodedMatch.Success -and $decodedOuter -ceq $outerText) -Name 'PublishedEncodedCommandMatchesReviewedBootstrapSource'
    }else{Assert-F2Launch -Condition $false -Name 'ExactUacCommandPublished'}
    $hashManifestPath=Join-Path (Split-Path $outerBootstrapPath -Parent) 'FILE_SHA256_MANIFEST.txt'
    if(Test-Path -LiteralPath $hashManifestPath){
        $expectedManifestPaths=@('.gitattributes','.github/workflows/f2-acl-source-only.yml','docs/reviews/f2-g1-elevated-diagnostic-launch/OUTER_BOOTSTRAP.ps1','docs/reviews/f2-g1-elevated-diagnostic-launch/README.md','docs/reviews/f2-g1-elevated-diagnostic-launch/SECURITY_BOUNDARIES.md','docs/reviews/f2-g1-elevated-diagnostic-launch/DEVELOPER_HANDOFF.md','docs/reviews/f2-g1-elevated-diagnostic-launch/VALIDATION_RESULTS.md','docs/reviews/f2-g1-elevated-diagnostic-launch/EXACT_UAC_COMMAND.txt','scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1','scripts/f2-acl/F2HistoricalManifestLaunch.psm1','scripts/f2-acl/Invoke-F2HistoricalManifestDiagnosticChild.ps1','scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1','scripts/f2-acl/Test-F2HistoricalManifestLaunch.ps1')
        $manifestRecords=@();$manifestMalformed=$false
        foreach($line in Get-Content -LiteralPath $hashManifestPath){$match=[regex]::Match([string]$line,'^(?<hash>[0-9a-f]{64})  (?<path>[^\s][^\r\n]*)$');if(-not $match.Success){$manifestMalformed=$true;break};$manifestRecords+=([pscustomobject]@{Sha256=$match.Groups['hash'].Value;Path=$match.Groups['path'].Value})}
        $manifestNames=@($manifestRecords|ForEach-Object{$_.Path})
        $manifestPathDiff=@(Compare-Object ($manifestNames|Sort-Object) ($expectedManifestPaths|Sort-Object) -CaseSensitive)
        $manifestShapePass=(-not $manifestMalformed -and $manifestRecords.Count -eq $expectedManifestPaths.Count -and @($manifestNames|Select-Object -Unique).Count -eq $expectedManifestPaths.Count -and $manifestPathDiff.Count -eq 0)
        $manifestHashesPass=$manifestShapePass
        if($manifestHashesPass){foreach($entry in $manifestRecords){$candidateFile=Join-Path $repoRoot ($entry.Path.Replace('/','\'));if(-not(Test-Path -LiteralPath $candidateFile -PathType Leaf)){ $manifestHashesPass=$false;break };try{Test-F2LaunchNoReparsePath -Path $candidateFile|Out-Null;if((Get-TestFileSha $candidateFile) -cne $entry.Sha256){$manifestHashesPass=$false;break}}catch{$manifestHashesPass=$false;break}}}
        Assert-F2Launch -Condition ($manifestShapePass -and $manifestHashesPass) -Name 'PublishedReviewFileManifestExactlyMatchesWorkingBytes'
    }else{Assert-F2Launch -Condition $false -Name 'PublishedReviewFileHashManifestPresent'}

    Write-Output ('Assertions=' + $assertions + ';Failures=' + $failures.Count)
    foreach($failure in $failures){Write-Output ('ASSERTION_FAILED:'+ $failure)}
    if($failures.Count -gt 0){exit 1}
    exit 0
} catch {
    Write-Output ('F2_HISTORICAL_MANIFEST_LAUNCH_TEST_FAILED:'+([string]$_.FullyQualifiedErrorId).Split(',')[0]+':line='+$_.InvocationInfo.ScriptLineNumber)
    exit 1
}

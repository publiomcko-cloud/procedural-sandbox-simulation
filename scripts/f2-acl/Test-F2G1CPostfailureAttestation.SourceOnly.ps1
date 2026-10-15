[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$script:Failures = New-Object 'System.Collections.Generic.List[string]'

function Assert-Case {
    param([bool]$Condition,[string]$Name)
    $script:Assertions++
    if (-not $Condition) { $script:Failures.Add($Name); Write-Output ('FAIL: '+$Name) }
    else { Write-Output ('PASS: '+$Name) }
}

function Get-BytesSha256 {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-Utf8Bytes {
    param([string]$Text)
    return ,([Text.UTF8Encoding]::new($false)).GetBytes($Text)
}

function New-Fixture {
    param([string]$Root,[string]$Fault='',[string]$FaultPath='',[string]$ManifestOverride='',[switch]$MutatePackage,[switch]$AddUnexpected,[switch]$Incomplete,[switch]$Admin,[switch]$AdministratorGroup)
    $pkg='C:\Program Files\F2-G1-Icacls\scripts\f2-acl'
    $data='C:\ProgramData\F2-G1-Icacls'
    $mailbox='C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df'
    $userSid='S-1-5-21-111-222-333-1001'
    $fileNames=@('F2AclCapture.Protocol.psm1','F2AclIcacls.Corroboration.psm1','F2AclIcacls.Runtime.psm1','Invoke-F2IcaclsCapture.ps1','Invoke-F2IcaclsProtectedCoordinator.ps1','F2_ICACLS_SOURCE_PINS.json','Invoke-F2AclReadOnlyCapture.ps1')
    $mailNames=@('acl-baseline.frame','acl-baseline.json','coordinator-status.json','integrity.json','powershell-streams.json','worker-stderr.json','worker-stdout.json')
    $dirs=@('C:\','C:\Program Files','C:\ProgramData','C:\Program Files\F2-G1-Icacls','C:\Program Files\F2-G1-Icacls\scripts',$pkg,$data)
    $parents=@{
        'C:\'='O:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x4;;;AU)(A;OICIIO;0xe0010000;;;AU)'
        'C:\Program Files'='O:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)'
        'C:\ProgramData'='O:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;CI;0x116;;;BU)'
    }
    $installDirSddl='O:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x001200a9;;;AU)'
    $installFileSddl='O:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x001200a9;;;AU)'
    $mailSddl='O:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x001200a9;;;OW)(A;OICI;0x001200a9;;;S-1-5-21-111-222-333-1001)'
    $paths=New-Object 'System.Collections.Generic.List[object]'
    foreach($d in $dirs){$sddl=if($parents.ContainsKey($d)){$parents[$d]}else{$installDirSddl};$paths.Add([pscustomobject]@{Path=$d;Exists=$true;Kind='Directory';Reparse=$false;Length=0;Sddl=$sddl})}
    $files=New-Object 'System.Collections.Generic.List[object]'
    $children=New-Object 'System.Collections.Generic.List[object]'
    $packageBytes=@{}
    foreach($n in $fileNames){$body=ConvertTo-Utf8Bytes ('synthetic package content:'+ $n);$packageBytes[$n]=$body}
    $packagePins=@();foreach($n in $fileNames){$packagePins+=@{Name=$n;Sha256=(Get-BytesSha256 $packageBytes[$n])}}
    if($MutatePackage){$packageBytes[$fileNames[0]]=ConvertTo-Utf8Bytes 'mutated synthetic package content'}
    $baselineRecords=@();$recordPaths=@();$count=11;if($Incomplete){$count=10};for($i=0;$i -lt $count;$i++){$recordPath='synthetic-object-'+$i;$baselineRecords+=@{Path=$recordPath};$recordPaths+=$recordPath}
    $payloadObj=[ordered]@{CaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211';Complete=$true;VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable';Records=$baselineRecords;Manifest=@{ExpectedPaths=$recordPaths;ExpectedCount=$count;RecordCount=$count;UniquePathCount=$count}}
    $payloadBytes=ConvertTo-Utf8Bytes ($payloadObj|ConvertTo-Json -Depth 8 -Compress)
    $streamsBytes=ConvertTo-Utf8Bytes '{"Schema":"f2-acl-powershell-streams-v1","Complete":true,"ExitCode":0}'
    $shaForFrame=[Security.Cryptography.SHA256]::Create();try{$frameDigest=$shaForFrame.ComputeHash($payloadBytes)}finally{$shaForFrame.Dispose()}
    $frameHeader=[byte[]](0x46,0x32,0x41,0x43,0x4c,0x01,0x0d,0x0a);$frameLength=[BitConverter]::GetBytes([int]$payloadBytes.Length);$frameBytes=New-Object byte[] (44+$payloadBytes.Length);[Buffer]::BlockCopy($frameHeader,0,$frameBytes,0,8);[Buffer]::BlockCopy($frameLength,0,$frameBytes,8,4);[Buffer]::BlockCopy($payloadBytes,0,$frameBytes,12,$payloadBytes.Length);[Buffer]::BlockCopy($frameDigest,0,$frameBytes,12+$payloadBytes.Length,32)
    $workerDiagnostics=@(@{Name='worker-stderr.json';Bytes=(ConvertTo-Utf8Bytes '{"synthetic":"stderr"}').Length;Sha256=(Get-BytesSha256 (ConvertTo-Utf8Bytes '{"synthetic":"stderr"}'))},@{Name='worker-stdout.json';Bytes=(ConvertTo-Utf8Bytes '{"synthetic":"stdout"}').Length;Sha256=(Get-BytesSha256 (ConvertTo-Utf8Bytes '{"synthetic":"stdout"}'))})
    $integrityObj=[ordered]@{Schema='f2-acl-integrity-v1';PayloadFile='acl-baseline.json';PayloadBytes=$payloadBytes.Length;PayloadSha256=(Get-BytesSha256 $payloadBytes);ProjectVolumeGuid='\\?\Volume{11111111-1111-4111-8111-111111111111}\';EvidenceVolumeGuid='\\?\Volume{22222222-2222-4222-8222-222222222222}\';SeparateFromProjectVolume=$true;ChildExitCode=0;CollectorScriptSha256='bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b';ProtocolModuleSha256='42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728';PowerShellStreamsFile='powershell-streams.json';PowerShellStreamsBytes=$streamsBytes.Length;PowerShellStreamsSha256=(Get-BytesSha256 $streamsBytes);WorkerDiagnosticFiles=$workerDiagnostics}
    $integrityBytes=ConvertTo-Utf8Bytes ($integrityObj|ConvertTo-Json -Depth 6 -Compress)
    $mailContents=@{
        'acl-baseline.frame'=$frameBytes
        'acl-baseline.json'=$payloadBytes
        'coordinator-status.json'=(ConvertTo-Utf8Bytes '{"synthetic":true}')
        'integrity.json'=$integrityBytes
        'powershell-streams.json'=$streamsBytes
        'worker-stderr.json'=(ConvertTo-Utf8Bytes '{"synthetic":"stderr"}')
        'worker-stdout.json'=(ConvertTo-Utf8Bytes '{"synthetic":"stdout"}')
    }
    $manifestObj=[ordered]@{Schema='f2-icacls-runtime-release-v2';ReviewedCommitSha='5741ffe90a3abd02a08563e6431e8a0b9b63eeb1';BaselineMailboxId='ecb6deeb424e40feb5354d18908986df';BaselinePayloadCaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211';BaselinePayloadSha256=(Get-BytesSha256 $payloadBytes);BaselineIntegritySha256=(Get-BytesSha256 $integrityBytes);SourcePinsManifestSha256='bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7';Files=$packagePins}
    $manifestBytes=if($ManifestOverride){ConvertTo-Utf8Bytes $ManifestOverride}else{ConvertTo-Utf8Bytes ($manifestObj|ConvertTo-Json -Depth 8 -Compress)}
    foreach($n in $fileNames){$path=Join-Path $pkg $n;$files.Add([pscustomobject]@{Path=$path;Base64=[Convert]::ToBase64String($packageBytes[$n])});$paths.Add([pscustomobject]@{Path=$path;Exists=$true;Kind='File';Reparse=$false;Length=$packageBytes[$n].Length;Sddl=$installFileSddl})}
    $manifestPath=Join-Path $data 'approved-release.json';$files.Add([pscustomobject]@{Path=$manifestPath;Base64=[Convert]::ToBase64String($manifestBytes)});$paths.Add([pscustomobject]@{Path=$manifestPath;Exists=$true;Kind='File';Reparse=$false;Length=$manifestBytes.Length;Sddl=$installFileSddl})
    foreach($n in $mailNames){$body=$mailContents[$n];$path=Join-Path $mailbox $n;$files.Add([pscustomobject]@{Path=$path;Base64=[Convert]::ToBase64String($body)});$paths.Add([pscustomobject]@{Path=$path;Exists=$true;Kind='File';Reparse=$false;Length=$body.Length;Sddl=$installFileSddl})}
    $paths.Add([pscustomobject]@{Path=$mailbox;Exists=$true;Kind='Directory';Reparse=$false;Length=0;Sddl=$mailSddl})
    $statusObj=[ordered]@{Schema='f2-acl-elevated-coordinator-v1';Outcome='COMPLETE_READ_ONLY_ACL_BASELINE';RequesterSid=$userSid;CoordinatorSid='S-1-5-21-111-222-333-1002';AdministratorRoleVerified=$true;WorkerExitCode=0;ExpectedProcessExitCode=0;Errors=@();WorkerDiagnosticFallback=$null;WorkerExpectedFiles=@(@{Name='acl-baseline.frame';Exists=$true;Length=$frameBytes.Length},@{Name='powershell-streams.json';Exists=$true;Length=$streamsBytes.Length});WorkerDiagnosticFiles=$workerDiagnostics;WorkerDiagnostics=@{Started=$true;State='Exited';TimedOut=$false;ExitCode=0;OutputComplete=$true;CleanupComplete=$true;StdoutTruncated=$false;StderrTruncated=$false;FatalError=$null;ReaderErrors=@();Stages=@('EntrypointReached','InvocationStarted','SourceVerified','MailboxVerified','CollectorEntered','FramePublished','StreamPublished','InvocationReturned')}}
    $mailContents['coordinator-status.json']=ConvertTo-Utf8Bytes ($statusObj|ConvertTo-Json -Depth 8 -Compress)
    $statusPath=Join-Path $mailbox 'coordinator-status.json';$statusRow=@($files|Where-Object{$_.Path -eq $statusPath})|Select-Object -First 1;$statusRow.Base64=[Convert]::ToBase64String($mailContents['coordinator-status.json'])
    $statusPathRow=@($paths|Where-Object{$_.Path -eq $statusPath})|Select-Object -First 1;$statusPathRow.Length=$mailContents['coordinator-status.json'].Length
    if($Fault -eq 'MissingObject'){$row=@($paths|Where-Object{$_.Path -eq $FaultPath})|Select-Object -First 1;if($row){$row.Exists=$false}}
    if($Fault -eq 'Reparse'){$row=@($paths|Where-Object{$_.Path -eq $FaultPath})|Select-Object -First 1;if($row){$row.Reparse=$true}}
    $children.Add([pscustomobject]@{Path='C:\Program Files\F2-G1-Icacls';Entries=@(@{Name='scripts';Kind='Directory';Reparse=$false})})
    $children.Add([pscustomobject]@{Path='C:\Program Files\F2-G1-Icacls\scripts';Entries=@(@{Name='f2-acl';Kind='Directory';Reparse=$false})})
    $pkgEntries=@();foreach($n in $fileNames){$pkgEntries+=@{Name=$n;Kind='File';Reparse=$false}}
    if($AddUnexpected){$pkgEntries+=@{Name='unexpected.bin';Kind='File';Reparse=$false}}
    $children.Add([pscustomobject]@{Path=$pkg;Entries=$pkgEntries})
    $children.Add([pscustomobject]@{Path=$data;Entries=@(@{Name='approved-release.json';Kind='File';Reparse=$false})})
    $children.Add([pscustomobject]@{Path=$mailbox;Entries=@($mailNames|ForEach-Object{@{Name=$_;Kind='File';Reparse=$false}})})
    $faultValue=if($Fault -eq 'AccessDenied'){'AccessDenied'}else{''}
$fixture=[ordered]@{Fault=$faultValue;FaultPath=$FaultPath;IsAdministrator=[bool]$Admin;AdministratorGroupPresent=[bool]$AdministratorGroup;UserSid=$userSid;Expected=@{ManifestSha256=(Get-BytesSha256 $manifestBytes);ReviewedCommitSha='5741ffe90a3abd02a08563e6431e8a0b9b63eeb1';BaselineMailboxId='ecb6deeb424e40feb5354d18908986df';BaselinePayloadCaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211';RecordPaths=@($recordPaths)};Paths=@($paths.ToArray());Files=@($files.ToArray());Children=@($children.ToArray())}
    $fixturePath=Join-Path $Root 'fixture.json'
    $json=$fixture|ConvertTo-Json -Depth 16 -Compress
    [IO.File]::WriteAllText($fixturePath,$json,(New-Object Text.UTF8Encoding($false)))
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $scriptRoot 'F2G1CPostfailureAttestation.psm1'
$inspectorPath = Join-Path $scriptRoot 'Invoke-F2G1CPostfailureAttestation.ps1'
$sourcePaths = @($modulePath,$inspectorPath)
foreach($path in $sourcePaths){
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    Assert-Case ($parseErrors.Count -eq 0) ('PS51 parser: '+[IO.Path]::GetFileName($path))
}
if($script:Failures.Count -gt 0){Write-Output ('ASSERTIONS='+$script:Assertions+' FAILURES='+$script:Failures.Count);exit 1}

$sourceText=[IO.File]::ReadAllText($modulePath)
 $sourceTokens=$null;$sourceParseErrors=$null
 $sourceAst=[Management.Automation.Language.Parser]::ParseFile($modulePath,[ref]$sourceTokens,[ref]$sourceParseErrors)
 $forbiddenCommands=@($sourceAst.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in @('Set-Acl','Remove-Item','Start-Process','Invoke-Expression','icacls','icacls.exe','Start-Job')},$true))
Assert-Case ($forbiddenCommands.Count -eq 0) 'inspector contains no mutator, process launcher, eval or icacls command'
Assert-Case ($sourceText -notmatch 'C:\\Dev|git\.exe|Get-Command') 'inspector has no checkout or Git remote checks'
Assert-Case ($sourceText.Contains('EXACT_ISSUE_48_COMMENT_REFERENCE_REQUIRED') -and $sourceText.Contains('PREVIOUS_OWNER_AUTHORIZATION_NOT_REUSABLE')) 'live mode requires a fresh Issue 48 comment reference and rejects the spent authorization'
Assert-Case ($sourceText.Contains('$script:PackageHome = ''C:\Program Files\F2-G1-Icacls''') -and $sourceText.Contains("Join-Path `$script:PackageHome 'scripts'") -and $sourceText.Contains("Join-Path `$script:PackageScriptDir 'f2-acl'")) 'package path is pinned'
Assert-Case ($sourceText -match [regex]::Escape('C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df')) 'mailbox path is pinned'

Import-Module -Name $modulePath -Force -ErrorAction Stop
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$root=Join-Path $temp ('F2G1-CPostfailure-'+[guid]::NewGuid().ToString())
[void][IO.Directory]::CreateDirectory($root)
try {
    $manifestPath='C:\ProgramData\F2-G1-Icacls\approved-release.json'
    New-Fixture -Root $root
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    if($r.Verdict -ne 'SYNTHETIC_FIXTURE_PASS'){Write-Output ('DEBUG_PASS_FIXTURE='+(@($r.Gates|ForEach-Object{if($null -ne $_.Data -and $_.Data.ContainsKey('Code')){$_.Name+':'+$_.Result+':'+$_.Data['Code']+':'+[string]$_.Data['ErrorClass']+'@'+[string]$_.Data['ErrorLine']}else{$_.Name+':'+$_.Result}}) -join '|'))}
    Assert-Case ($r.Verdict -eq 'SYNTHETIC_FIXTURE_PASS') 'complete synthetic baseline passes core gates without a host PASS verdict'
    Assert-Case (@($r.Gates|Where-Object{$_.Name -like 'PackageFile:*' -and $_.Result -eq 'PASS'}).Count -eq 7) 'all seven synthetic package files hashed'
    Assert-Case (@($r.Gates|Where-Object{$_.Name -eq 'BaselineEvidence' -and $_.Data.UniqueRecordCount -eq 11}).Count -eq 1) 'eleven unique synthetic records required'

    New-Fixture -Root $root -Fault AccessDenied -FaultPath $manifestPath
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case ($r.Verdict -eq 'BLOCKED_WITH_EVIDENCE' -and @($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'READ_FAILED'}).Count -eq 1) 'simulated access denied blocks closed'

    New-Fixture -Root $root -Fault MissingObject -FaultPath $manifestPath
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case ($r.Verdict -eq 'BLOCKED_WITH_EVIDENCE') 'missing required object blocks closed'

    New-Fixture -Root $root -AddUnexpected
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case (@($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'UNEXPECTED_CHILD'}).Count -eq 1) 'unexpected immediate child blocks closed'

    New-Fixture -Root $root -ManifestOverride '{'
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case (@($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'MANIFEST_JSON_INVALID'}).Count -eq 1) 'malformed manifest blocks closed'

    New-Fixture -Root $root -MutatePackage
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case (@($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'PACKAGE_HASH_MISMATCH'}).Count -eq 1) 'package hash mismatch blocks closed'

    New-Fixture -Root $root -Incomplete
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case (@($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'CAPTURE_ID_OR_ELEVEN_RECORD_COMPLETENESS_INVALID'}).Count -eq 1) 'incomplete baseline output blocks closed'

    New-Fixture -Root $root -Admin
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case (@($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'ADMINISTRATOR_TOKEN_OR_GROUP_MEMBERSHIP'}).Count -eq 1) 'Administrator token blocks before path inspection'

    New-Fixture -Root $root -AdministratorGroup
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case (@($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'ADMINISTRATOR_TOKEN_OR_GROUP_MEMBERSHIP'}).Count -eq 1) 'filtered administrator group membership blocks before path inspection'

    New-Fixture -Root $root -Fault Reparse -FaultPath 'C:\Program Files\F2-G1-Icacls\scripts\f2-acl'
    $r=Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $root
    Assert-Case (@($r.Gates|Where-Object{$null -ne $_.Data -and $_.Data.ContainsKey('Code') -and $_.Data['Code'] -eq 'MISSING_OR_REPARSE'}).Count -eq 1) 'reparse object blocks closed'
}
finally {
    $fullRoot=[IO.Path]::GetFullPath($root).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($fullRoot) -ne $temp -or [IO.Path]::GetFileName($fullRoot) -notmatch '^F2G1-CPostfailure-[0-9a-fA-F-]{36}$'){throw 'TEMP cleanup path guard failed.'}
    if([IO.Directory]::Exists($fullRoot)){[IO.Directory]::Delete($fullRoot,$true)}
    Remove-Module F2G1CPostfailureAttestation -ErrorAction SilentlyContinue
}

Write-Output ('ASSERTIONS='+$script:Assertions+' FAILURES='+$script:Failures.Count)
if($script:Failures.Count -gt 0){$script:Failures|ForEach-Object{Write-Output ('FAILURE='+$_)};exit 1}
exit 0

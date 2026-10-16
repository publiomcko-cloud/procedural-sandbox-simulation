[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:GITHUB_REPOSITORY -cne 'publiomcko-cloud/procedural-sandbox-simulation') {throw 'LT2_DISPOSABLE_WINDOWS_CI_ONLY'}
Import-Module (Join-Path $PSScriptRoot '..\lt1\F2G1LT1.Synthetic.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'F2G1LT2.Fixture.psm1') -Force -ErrorAction Stop
$script:Count=0;$script:Fail=0
function Assert([bool]$Ok,[string]$Label) {
    $script:Count++
    if(-not $Ok){$script:Fail++;[Console]::Out.WriteLine('FAIL: '+$Label)}
    else{[Console]::Out.WriteLine('PASS: '+$Label)}
}
function Bytes([string]$Text){return ,([Text.UTF8Encoding]::new($false)).GetBytes($Text)}
function Hash([byte[]]$Data){
    $sha=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($sha.ComputeHash($Data))).Replace('-','').ToLowerInvariant()}
    finally {$sha.Dispose()}
}
function JsonBytes($Obj){return ,(Bytes (ConvertTo-Json -InputObject $Obj -Compress -Depth 12))}
function FilePath([string]$Root,[string]$Label) {
    if($Label -ceq 'C:\'){return (Join-Path $Root 'C')}
    return (Join-Path (Join-Path $Root 'C') $Label.Substring(3))
}
function WriteFixture([string]$Root) {
    $scope=Get-F2G1LT1Scope
    foreach($d in $scope.Directories){[void][IO.Directory]::CreateDirectory((FilePath $Root $d))}
    $pkg='C:\Program Files\F2-G1-Icacls\scripts\f2-acl\'
    $mail='C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\'
    $data='C:\ProgramData\F2-G1-Icacls\approved-release.json'
    $pins=@()
    foreach($file in @($scope.Files|Where-Object {$_.Path.StartsWith($pkg,[StringComparison]::Ordinal)})){
        $body=Bytes ('LT2-CI-ONLY|'+$file.Path)
        [IO.File]::WriteAllBytes((FilePath $Root $file.Path),$body)
        $pins+=@{Name=$file.Path.Substring($pkg.Length);Sha256=(Hash $body)}
    }
    $records=@(0..10|ForEach-Object {@{Path=('synthetic-evidence-record-'+$_)}})
    $paths=@($records|ForEach-Object {$_.Path})
    $payload=JsonBytes ([ordered]@{
        CaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211';Complete=$true
        VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable'
        Records=$records;Manifest=@{ExpectedPaths=$paths;ExpectedCount=11;RecordCount=11;UniquePathCount=11}
    })
    $streams=Bytes '{"Schema":"f2-acl-powershell-streams-v1","Complete":true,"ExitCode":0}'
    $integrity=JsonBytes ([ordered]@{
        Schema='f2-acl-integrity-v1';PayloadFile='acl-baseline.json'
        PayloadBytes=$payload.Length;PayloadSha256=(Hash $payload)
        PowerShellStreamsFile='powershell-streams.json'
        PowerShellStreamsBytes=$streams.Length;PowerShellStreamsSha256=(Hash $streams)
    })
    $frame=New-Object byte[] (44+$payload.Length)
    $header=[byte[]](0x46,0x32,0x41,0x43,0x4c,0x01,0x0d,0x0a)
    [Buffer]::BlockCopy($header,0,$frame,0,8)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([int]$payload.Length),0,$frame,8,4)
    [Buffer]::BlockCopy($payload,0,$frame,12,$payload.Length)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$digest=$sha.ComputeHash($payload)}finally {$sha.Dispose()}
    [Buffer]::BlockCopy($digest,0,$frame,12+$payload.Length,32)
    $mailData=@{
        'acl-baseline.frame'=$frame
        'acl-baseline.json'=$payload
        'integrity.json'=$integrity
        'powershell-streams.json'=$streams
        'coordinator-status.json'=(Bytes '{"synthetic":true}')
        'worker-stderr.json'=(Bytes '{"synthetic":"stderr"}')
        'worker-stdout.json'=(Bytes '{"synthetic":"stdout"}')
    }
    foreach($name in @($mailData.Keys)) {[IO.File]::WriteAllBytes((FilePath $Root ($mail+$name)),$mailData[$name])}
    $manifest=JsonBytes ([ordered]@{
        Schema='f2-icacls-runtime-release-v2';ReviewedCommitSha='5741ffe90a3abd02a08563e6431e8a0b9b63eeb1'
        BaselineMailboxId='ecb6deeb424e40feb5354d18908986df'
        BaselinePayloadCaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211'
        BaselinePayloadSha256=(Hash $payload);BaselineIntegritySha256=(Hash $integrity)
        Files=@($pins)
    })
    [IO.File]::WriteAllBytes((FilePath $Root $data),$manifest)
}

# Modify the semantic fields, then rebuild ALL dependent hashes/frame.
# A rejection must be semantic, not merely caused by stale SHA-256 values.
function RewriteSemanticFixture([string]$Root,[scriptblock]$Mutation) {
    $manifestPath=FilePath $Root 'C:\ProgramData\F2-G1-Icacls\approved-release.json'
    $mail='C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\'
    $payloadPath=FilePath $Root ($mail+'acl-baseline.json')
    $integrityPath=FilePath $Root ($mail+'integrity.json')
    $streamsPath=FilePath $Root ($mail+'powershell-streams.json')
    $framePath=FilePath $Root ($mail+'acl-baseline.frame')
    $manifest=[IO.File]::ReadAllText($manifestPath)|ConvertFrom-Json
    $payload=[IO.File]::ReadAllText($payloadPath)|ConvertFrom-Json
    $integrity=[IO.File]::ReadAllText($integrityPath)|ConvertFrom-Json
    $streams=[IO.File]::ReadAllText($streamsPath)|ConvertFrom-Json
    & $Mutation $manifest $payload $integrity $streams
    $newPayload=JsonBytes $payload
    $newStreams=JsonBytes $streams
    $integrity.PayloadBytes=$newPayload.Length
    $integrity.PayloadSha256=Hash $newPayload
    $integrity.PowerShellStreamsBytes=$newStreams.Length
    $integrity.PowerShellStreamsSha256=Hash $newStreams
    $newIntegrity=JsonBytes $integrity
    $manifest.BaselinePayloadSha256=Hash $newPayload
    $manifest.BaselineIntegritySha256=Hash $newIntegrity
    $newManifest=JsonBytes $manifest
    $frame=New-Object byte[] (44+$newPayload.Length)
    [Buffer]::BlockCopy([byte[]](0x46,0x32,0x41,0x43,0x4c,0x01,0x0d,0x0a),0,$frame,0,8)
    [Buffer]::BlockCopy([BitConverter]::GetBytes([int]$newPayload.Length),0,$frame,8,4)
    [Buffer]::BlockCopy($newPayload,0,$frame,12,$newPayload.Length)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$digest=$sha.ComputeHash($newPayload)}finally{$sha.Dispose()}
    [Buffer]::BlockCopy($digest,0,$frame,12+$newPayload.Length,32)
    [IO.File]::WriteAllBytes($payloadPath,$newPayload)
    [IO.File]::WriteAllBytes($streamsPath,$newStreams)
    [IO.File]::WriteAllBytes($integrityPath,$newIntegrity)
    [IO.File]::WriteAllBytes($manifestPath,$newManifest)
    [IO.File]::WriteAllBytes($framePath,$frame)
}

function Fingerprint([string]$Root) {
    $list=New-Object 'System.Collections.Generic.List[string]'
    foreach($file in @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)){
        $b=[IO.File]::ReadAllBytes($file.FullName)
        $list.Add(($file.FullName.Substring($Root.Length))+':'+(Hash $b)+':'+(Get-Acl -LiteralPath $file.FullName).Sddl)
    }
    return ($list -join '|')
}
function RunCase([string]$Name,[scriptblock]$Fault,[string]$ExpectedCode='') {
    $root=Join-Path $env:RUNNER_TEMP ('F2G1-LT2-'+[guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($root)
    try {
        WriteFixture $root
        if($null -ne $Fault){& $Fault $root}
        $snapshot=Fingerprint $root
        $result=Test-F2G1LT2Physical -FixtureRoot $root
        $unchanged=(Fingerprint $root) -ceq $snapshot
        $expected=$Name -ceq 'clean'
        Assert (($result.Verdict -ceq $(if($expected){'SYNTHETIC_FIXTURE_PASS'}else{'BLOCKED_WITH_EVIDENCE'})) -and
           $result.ProtectedReads -eq 0 -and $result.HistoricalV2 -ceq 'NOT_ATTESTED_SYNTHETIC_BYTES' -and
           $result.LinkAndAds -ceq 'LINK_ADS_NOT_ATTESTED' -and
           ([string]::IsNullOrEmpty($ExpectedCode) -or $result.Code -ceq $ExpectedCode) -and
           $unchanged) ("real Windows fixture "+$Name+"; no mutations")
        if($expected){
            Assert ($result.FixtureObjects -eq 23 -and $result.FixtureFiles -eq 15 -and $result.Inventories -eq 5) '23 objects, 15 read files, 5 real inventories'
            $token=Get-F2G1LT2RealToken
            $strict=Test-F2G1LT2Physical -FixtureRoot $root -RequireStandardToken
            Assert (($strict.Verdict -ceq $(if($token.Allowed){'SYNTHETIC_FIXTURE_PASS'}else{'BLOCKED_WITH_EVIDENCE'})) -and
               $strict.ProtectedReads -eq 0) 'real non-elevated token policy blocks or allows matching process'
            Assert ($token.Kind -in @('BLOCKED','STANDARD','FILTERED_LIMITED')) 'real GetTokenInformation returns sanitized classification'
        }
    } finally {
        # Fixture creation/deletion belongs only to this CI TEST SCRIPT, not observer.
        if([IO.Path]::GetDirectoryName($root) -cne [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') -or
           [IO.Path]::GetFileName($root) -notmatch '^F2G1-LT2-[0-9a-fA-F-]{36}$'){throw 'FIXTURE_DELETE_GUARD'}
        if([IO.Directory]::Exists($root)){[IO.Directory]::Delete($root,$true)}
    }
}
$files=@((Join-Path $PSScriptRoot 'F2G1LT2.Fixture.psm1'),$MyInvocation.MyCommand.Path)
foreach($file in $files){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    Assert ($errors.Count -eq 0) ('PowerShell 5.1 parser '+[IO.Path]::GetFileName($file))
}
RunCase 'clean' $null
RunCase 'altered-package' {param($root) [IO.File]::WriteAllBytes((FilePath $root 'C:\Program Files\F2-G1-Icacls\scripts\f2-acl\F2AclCapture.Protocol.psm1'),(Bytes 'tampered'))}
RunCase 'altered-payload' {param($root) [IO.File]::WriteAllBytes((FilePath $root 'C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\acl-baseline.json'),(Bytes '{}'))}
RunCase 'altered-frame' {param($root) $path=FilePath $root 'C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\acl-baseline.frame';$b=[IO.File]::ReadAllBytes($path);$b[12]=([byte]($b[12] -bxor 1));[IO.File]::WriteAllBytes($path,$b)}
RunCase 'extra-child' {param($root) [IO.File]::WriteAllText((FilePath $root 'C:\ProgramData\F2-G1-Icacls\unexpected.bin'),'extra')}
RunCase 'missing-file' {param($root) [IO.File]::Delete((FilePath $root 'C:\ProgramData\F2-G1-Icacls\approved-release.json'))}
RunCase 'unexpected-reparse' {param($root)
    $path=FilePath $root 'C:\Program Files\F2-G1-Icacls\scripts\f2-acl\F2AclCapture.Protocol.psm1'
    [IO.File]::Delete($path)
    [void](New-Item -ItemType SymbolicLink -Path $path -Target (FilePath $root 'C:\ProgramData\F2-G1-Icacls\approved-release.json') -ErrorAction Stop)
}
# Semantic negatives remain internally hash-consistent after each mutation.
RunCase 'duplicate-manifest-pin' {
    param($root)
    RewriteSemanticFixture $root {
        param($m,$p,$i,$s)
        $m.Files[1].Name=$m.Files[0].Name
        $m.Files[1].Sha256=$m.Files[0].Sha256
    }
} 'PACKAGE_PIN_SET_INVALID'
RunCase 'malformed-manifest-pin' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $m.Files[0].Sha256='not-a-sha256'}
} 'PACKAGE_HASH_INVALID'
RunCase 'record-path-set-mismatch' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $p.Manifest.ExpectedPaths[0]='synthetic-evidence-not-in-records'}
} 'EVIDENCE_RECORD_SET_INVALID'
RunCase 'record-path-duplicates' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $p.Manifest.ExpectedPaths[1]=$p.Manifest.ExpectedPaths[0]}
} 'EVIDENCE_RECORD_SET_INVALID'
RunCase 'expected-count-mismatch' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $p.Manifest.ExpectedCount=10}
} 'EVIDENCE_INTEGRITY_INVALID'
RunCase 'record-count-mismatch' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $p.Manifest.RecordCount=10}
} 'EVIDENCE_INTEGRITY_INVALID'
RunCase 'unique-count-mismatch' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $p.Manifest.UniquePathCount=10}
} 'EVIDENCE_INTEGRITY_INVALID'
RunCase 'stream-nonzero-exit' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $s.ExitCode=7}
} 'STREAM_INTEGRITY_INVALID'
RunCase 'integrity-stream-filename' {
    param($root)
    RewriteSemanticFixture $root {param($m,$p,$i,$s) $i.PowerShellStreamsFile='different.json'}
} 'STREAM_INTEGRITY_INVALID'

$badRoot=Join-Path $env:RUNNER_TEMP 'not-an-approved-fixture'
$r=Test-F2G1LT2Physical -FixtureRoot $badRoot
Assert ($r.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $r.ProtectedReads -eq 0) 'unapproved fixture root blocks before path traversal'
[Console]::Out.WriteLine('LT2_ASSERTIONS='+$script:Count+' FAILURES='+$script:Fail)
if($script:Fail -ne 0){exit 1}
exit 0

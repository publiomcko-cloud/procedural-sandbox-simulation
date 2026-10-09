[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'F2AclCapture.Protocol.psm1') -Force

$pinManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'F2_ACL_SOURCE_PINS.json') -Raw | ConvertFrom-Json
$launcherDigest = Get-F2AclSha256 ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'Invoke-F2AclReadOnlyCapture.ps1')))
$moduleDigest = Get-F2AclSha256 ([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'F2AclCapture.Protocol.psm1')))

$script:Assertions = 0
$script:Failures = [Collections.Generic.List[string]]::new()

function Assert-F2Acl {
    param([bool]$Condition, [string]$Name)
    $script:Assertions++
    if (-not $Condition) { $script:Failures.Add($Name) }
}

function Assert-F2AclReject {
    param([scriptblock]$Action, [string]$Name)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-F2Acl $rejected $Name
}

function New-F2AclFixtureRecord {
    param([string]$Path)
    $ace = [ordered]@{
        Principal = 'NT AUTHORITY\SYSTEM'
        Sid = 'S-1-5-18'
        Type = 'Allow'
        Rights = 'FullControl'
        AccessMask = '0x001F01FF'
        InheritanceFlags = 'ContainerInherit,ObjectInherit'
        PropagationFlags = 'None'
        Inherited = $false
    }
    return [ordered]@{
        Path = $Path
        Owner = 'BUILTIN\Administrators'
        OwnerSid = 'S-1-5-32-544'
        Sddl = 'O:BAD:AI(A;;FA;;;SY)'
        DaclProtected = $true
        Status = 'PASS'
        Error = ''
        AceCount = 1
        Aces = @($ace)
    }
}

function New-F2AclFixtureDocument {
    param([string[]]$Paths)
    $records = @($Paths | ForEach-Object { New-F2AclFixtureRecord $_ })
    $metadata = [ordered]@{
        Gates = @([ordered]@{Name='synthetic_identity';Pass=$true;Detail='synthetic preflight passed'})
        Disk = [ordered]@{SerialMatched=$true;Serial='152D20337A0C';Model='KINGSTON SA400S37240G';DriveLetter='G:';FileSystem='NTFS';BusType='USB';Health='Healthy';PhysicalHealth='Healthy';VolumeHealth='Healthy';DiskNumber=1;Win32Index=1;PartitionDisk=1}
    }
    return New-F2AclEvidenceDocument -VmId $script:VmId -VmName $script:VmName -ExpectedPaths $script:Paths -Records $records -Metadata $metadata
}

function Convert-F2AclFixtureToBytes {
    param($Document)
    return ConvertTo-F2AclUtf8Bytes (ConvertTo-Json -InputObject $Document -Depth 20 -Compress)
}

function Test-F2AclFixturePayload {
    param([byte[]]$Payload, [string]$Sha256, [int]$ChildExitCode)
    return Test-F2AclEvidenceDocument -Payload $Payload -PayloadSha256 $Sha256 -ChildExitCode $ChildExitCode -ExpectedVmId $script:VmId -ExpectedVmName $script:VmName -ExpectedDiskSerial '152D20337A0C' -ExpectedDiskModel 'KINGSTON SA400S37240G' -ExpectedPaths $script:Paths
}

$script:VmId = '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1'
$script:VmName = 'F2-G1-Isolated-Disposable'
$root = 'G:\F2-G1-Isolated-Disposable'
$id = '6F8D61CE-7C08-4C48-82D9-5FA7FE40A7B1'
$config = Join-Path $root 'F2-G1-Isolated-Disposable'
$configVm = Join-Path $config 'Virtual Machines'
$rootVm = Join-Path $root 'Virtual Machines'
$script:Paths = @(
    $root,
    $config,
    $configVm,
    (Join-Path $configVm $id),
    (Join-Path $configVm ($id + '.vmcx')),
    (Join-Path $configVm ($id + '.vmgs')),
    (Join-Path $configVm ($id + '.VMRS')),
    (Join-Path $root 'F2-G1-OS.vhdx'),
    (Join-Path $root 'F2-G1-Scratch.vhdx'),
    $rootVm,
    (Join-Path $rootVm $id)
)
Assert-F2Acl ($pinManifest.Schema -eq 'f2-acl-source-pins-v1' -and $pinManifest.ScriptSha256 -ceq $launcherDigest) 'committed source pin matches the launcher hash'
Assert-F2Acl ($pinManifest.ModuleSha256 -ceq $moduleDigest) 'committed source pin matches the protocol module hash'

$validDocument = New-F2AclFixtureDocument -Paths $script:Paths
$validBytes = Convert-F2AclFixtureToBytes $validDocument
$validHash = Get-F2AclSha256 $validBytes
$valid = Test-F2AclFixturePayload $validBytes $validHash 0
if (-not $valid.Pass) { $valid.Errors | ForEach-Object { Write-Output ("VALID_FIXTURE_ERROR=" + $_) } }
Assert-F2Acl ($valid.Pass -and $valid.Document.Manifest.RecordCount -eq 11) 'complete 11-path fixture accepted'
Assert-F2Acl ((ConvertTo-F2AclWindowsArgument 'C:\Dev\Space Path\capture.ps1') -eq '"C:\Dev\Space Path\capture.ps1"') 'quoted child path preserves spaces'
Assert-F2Acl ((ConvertTo-F2AclWindowsArgument 'C:\tail\') -eq '"C:\tail\\"') 'quoted child path doubles trailing slash'

$frameStream = [IO.MemoryStream]::new()
Write-F2AclFrame -Stream $frameStream -Payload $validBytes
$frameStream.Position = 0
$frame = Read-F2AclFrame -Stream $frameStream
Assert-F2Acl ($frame.PayloadSha256 -eq $validHash -and $frame.PayloadLength -eq $validBytes.Length) 'valid bounded frame round-trips with digest'

$openFrameName = 'f2acltest_' + [guid]::NewGuid().ToString('N')
$openFrameServer = [IO.Pipes.NamedPipeServerStream]::new($openFrameName, [IO.Pipes.PipeDirection]::In, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
$base64Frame = [Convert]::ToBase64String($frameStream.ToArray())
$openFrameCommand = '$c=[IO.Pipes.NamedPipeClientStream]::new(''.'',''' + $openFrameName + ''',[IO.Pipes.PipeDirection]::Out);$c.Connect(5000);$b=[Convert]::FromBase64String(''' + $base64Frame + ''');$c.Write($b,0,$b.Length);$c.Flush();Start-Sleep -Seconds 3;$c.Dispose()'
$openFrameInfo = [Diagnostics.ProcessStartInfo]::new()
$openFrameInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$openFrameInfo.Arguments = '-NoProfile -NonInteractive -Command ' + (ConvertTo-F2AclWindowsArgument $openFrameCommand)
$openFrameInfo.UseShellExecute = $false; $openFrameInfo.CreateNoWindow = $true
$openFrameChild = [Diagnostics.Process]::new(); $openFrameChild.StartInfo = $openFrameInfo
try {
    if (-not $openFrameChild.Start()) { throw 'Synthetic complete-frame child did not start.' }
    $openFrameServer.WaitForConnection()
    $openTimer = [Diagnostics.Stopwatch]::StartNew()
    Assert-F2AclReject { Read-F2AclFrame -Stream $openFrameServer -TimeoutSeconds 1 } 'complete frame with child keeping pipe open is rejected by bounded EOF probe'
    Assert-F2Acl ($openTimer.Elapsed.TotalSeconds -lt 3) 'bounded EOF probe returns while child pipe remains open'
}
finally {
    if ($openFrameChild -and -not $openFrameChild.HasExited) { $openFrameChild.Kill() }
    $openFrameServer.Dispose()
    if ($openFrameChild) { $openFrameChild.Dispose() }
}

$aceSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$standardAce = [Security.AccessControl.CommonAce]::new([Security.AccessControl.AceFlags]::ContainerInherit, [Security.AccessControl.AceQualifier]::AccessAllowed, [int][Security.AccessControl.FileSystemRights]::Read, $aceSid, $false, $null)
$callbackAce = [Security.AccessControl.CommonAce]::new([Security.AccessControl.AceFlags]::None, [Security.AccessControl.AceQualifier]::AccessAllowed, [int][Security.AccessControl.FileSystemRights]::Read, $aceSid, $true, [byte[]](1,2,3,4))
$objectAce = [Security.AccessControl.ObjectAce]::new([Security.AccessControl.AceFlags]::None, [Security.AccessControl.AceQualifier]::AccessAllowed, [int][Security.AccessControl.FileSystemRights]::Read, $aceSid, [Security.AccessControl.ObjectAceFlags]::ObjectAceTypePresent, [guid]::NewGuid(), [guid]::Empty, $false, $null)
$auditFlagAce = [Security.AccessControl.CommonAce]::new([Security.AccessControl.AceFlags]::SuccessfulAccess, [Security.AccessControl.AceQualifier]::AccessAllowed, [int][Security.AccessControl.FileSystemRights]::Read, $aceSid, $false, $null)
Assert-F2Acl ([bool](Assert-F2AclSupportedAce $standardAce)) 'plain supported common allow ACE accepted'
Assert-F2AclReject { Assert-F2AclSupportedAce $callbackAce } 'callback ACE rejected instead of dropping condition data'
Assert-F2AclReject { Assert-F2AclSupportedAce $objectAce } 'object ACE rejected instead of dropping object GUIDs'
Assert-F2AclReject { Assert-F2AclSupportedAce $auditFlagAce } 'unsupported ACE flag rejected'

$oversizeWriter = [IO.MemoryStream]::new()
Assert-F2AclReject { Write-F2AclFrame -Stream $oversizeWriter -Payload ([byte[]]::new(65)) -MaxPayloadBytes 64 } 'oversized frame rejected by writer'
$oversizeReader = [IO.MemoryStream]::new()
$bw = [IO.BinaryWriter]::new($oversizeReader)
$bw.Write([byte[]](0x46, 0x32, 0x41, 0x43, 0x4C, 0x01, 0x0D, 0x0A)); $bw.Write([int]65); $bw.Flush(); $oversizeReader.Position = 0
Assert-F2AclReject { Read-F2AclFrame -Stream $oversizeReader -MaxPayloadBytes 64 } 'oversized frame rejected by reader'

$corruptStream = [IO.MemoryStream]::new()
Write-F2AclFrame -Stream $corruptStream -Payload $validBytes
$corruptBytes = $corruptStream.ToArray(); $corruptBytes[12] = $corruptBytes[12] -bxor 0x01
$corruptInput = [IO.MemoryStream]::new($corruptBytes)
Assert-F2AclReject { Read-F2AclFrame -Stream $corruptInput } 'corrupted payload rejected by frame hash'

$partialFrame = [IO.MemoryStream]::new([byte[]](0x46, 0x32, 0x41, 0x43))
Assert-F2AclReject { Read-F2AclFrame -Stream $partialFrame } 'partial frame rejected'

$stalledName = 'f2acltest_' + [guid]::NewGuid().ToString('N')
$stalledServer = [IO.Pipes.NamedPipeServerStream]::new($stalledName, [IO.Pipes.PipeDirection]::In, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
$pipeClientCommand = '$c=[IO.Pipes.NamedPipeClientStream]::new(''.'',''' + $stalledName + ''',[IO.Pipes.PipeDirection]::Out);$c.Connect(5000);$b=[byte[]](0x46,0x32,0x41,0x43);$c.Write($b,0,$b.Length);$c.Flush();Start-Sleep -Seconds 3;$c.Dispose()'
$pipeClientInfo = [Diagnostics.ProcessStartInfo]::new()
$pipeClientInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$pipeClientInfo.Arguments = '-NoProfile -NonInteractive -Command ' + (ConvertTo-F2AclWindowsArgument $pipeClientCommand)
$pipeClientInfo.UseShellExecute = $false; $pipeClientInfo.CreateNoWindow = $true
$pipeClient = [Diagnostics.Process]::new(); $pipeClient.StartInfo = $pipeClientInfo
try {
    Write-Host 'Stage=bounded_partial_pipe_read'
    if (-not $pipeClient.Start()) { throw 'Synthetic partial-frame child did not start.' }
    $stalledServer.WaitForConnection()
    $stallTimer = [Diagnostics.Stopwatch]::StartNew()
    Assert-F2AclReject { Read-F2AclFrame -Stream $stalledServer -TimeoutSeconds 1 } 'connected child that stalls after partial header is bounded by read timeout'
    Assert-F2Acl ($stallTimer.Elapsed.TotalSeconds -lt 3) 'stalled frame timeout returns within bound'
}
finally {
    $stalledServer.Dispose()
    if ($pipeClient -and -not $pipeClient.HasExited) { $pipeClient.Kill() }
    if ($pipeClient) { $pipeClient.Dispose() }
}

$missingDocument = New-F2AclFixtureDocument -Paths $script:Paths[0..9]
$missingBytes = Convert-F2AclFixtureToBytes $missingDocument
$missingResult = Test-F2AclFixturePayload $missingBytes (Get-F2AclSha256 $missingBytes) 0
Assert-F2Acl (-not $missingResult.Pass -and $missingResult.Errors -contains 'DocumentIncomplete') 'missing record fails closed'

$duplicatePaths = @($script:Paths[0..9]) + @($script:Paths[0])
$duplicateDocument = New-F2AclFixtureDocument -Paths $duplicatePaths
$duplicateBytes = Convert-F2AclFixtureToBytes $duplicateDocument
$duplicateResult = Test-F2AclFixturePayload $duplicateBytes (Get-F2AclSha256 $duplicateBytes) 0
Assert-F2Acl (-not $duplicateResult.Pass -and ($duplicateResult.Errors -match 'RecordCountOrDuplicatePath')) 'duplicate path fails closed'

$malformedBytes = ConvertTo-F2AclUtf8Bytes '{bad json'
$malformedResult = Test-F2AclFixturePayload $malformedBytes (Get-F2AclSha256 $malformedBytes) 0
Assert-F2Acl (-not $malformedResult.Pass -and $malformedResult.Errors[0] -like 'MalformedJson:*') 'malformed JSON fails closed'
$missingEnvelopeBytes = ConvertTo-F2AclUtf8Bytes '{}'
$missingEnvelope = Test-F2AclFixturePayload $missingEnvelopeBytes (Get-F2AclSha256 $missingEnvelopeBytes) 0
Assert-F2Acl (-not $missingEnvelope.Pass -and $missingEnvelope.Errors -contains 'RequiredTopLevelFieldMissing') 'missing envelope fields fail closed'

$missingRecordText = [Text.Encoding]::UTF8.GetString($validBytes).Replace('"OwnerSid":"S-1-5-32-544",', '')
$missingRecordBytes = ConvertTo-F2AclUtf8Bytes $missingRecordText
$missingRecordResult = Test-F2AclFixturePayload $missingRecordBytes (Get-F2AclSha256 $missingRecordBytes) 0
Assert-F2Acl (-not $missingRecordResult.Pass -and ($missingRecordResult.Errors -contains 'RequiredRecordFieldMissing')) 'missing ACL record field fails closed'

$childFailure = Test-F2AclFixturePayload $validBytes $validHash 23
Assert-F2Acl (-not $childFailure.Pass -and $childFailure.Errors -contains 'ChildExitCode=23') 'nonzero child exit fails closed'

$badHash = Test-F2AclFixturePayload $validBytes ('0' * 64) 0
Assert-F2Acl (-not $badHash.Pass -and $badHash.Errors -contains 'PayloadSha256Mismatch') 'payload digest mismatch fails closed'

$badRecord = New-F2AclFixtureRecord $script:Paths[0]
$badRecord.Sddl = ''
$partialRecords = @((New-F2AclFixtureDocument -Paths $script:Paths).Records)
$partialDocument = New-F2AclEvidenceDocument -VmId $script:VmId -VmName $script:VmName -ExpectedPaths $script:Paths -Records (@($badRecord) + @($partialRecords[1..10])) -Metadata $validDocument.Metadata
$partialBytes = Convert-F2AclFixtureToBytes $partialDocument
$partialResult = Test-F2AclFixturePayload $partialBytes (Get-F2AclSha256 $partialBytes) 0
Assert-F2Acl (-not $partialResult.Pass -and ($partialResult.Errors -match 'RecordIncomplete:*')) 'partial ACL record fails closed'

$emptyDocument = New-F2AclEvidenceDocument -VmId $script:VmId -VmName $script:VmName -ExpectedPaths $script:Paths -Records @() -Metadata $validDocument.Metadata -Errors @('synthetic preflight stop')
$emptyBytes = Convert-F2AclFixtureToBytes $emptyDocument
$emptyResult = Test-F2AclFixturePayload $emptyBytes (Get-F2AclSha256 $emptyBytes) 1
Assert-F2Acl (-not $emptyResult.Pass -and $emptyResult.Errors -contains 'DocumentIncomplete' -and $emptyResult.Document.Manifest.RecordCount -eq 0) 'preflight failure with no ACL rows remains structured and incomplete'

$psi = [Diagnostics.ProcessStartInfo]::new()
Write-Output 'Stage=child_stdout_stderr_exit'
$psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$psi.Arguments = '-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''fixture-out''); [Console]::Error.WriteLine(''fixture-err''); exit 23"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$process = [Diagnostics.Process]::new(); $process.StartInfo = $psi
if (-not $process.Start()) { throw 'Synthetic child process did not start.' }
$stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit(); $stdout = $stdoutTask.Result.Trim(); $stderr = $stderrTask.Result.Trim(); $exitCode = $process.ExitCode
Assert-F2Acl ($stdout -eq 'fixture-out' -and $stderr -eq 'fixture-err' -and $exitCode -eq 23) 'host child stdout stderr and exit captured independently'
$process.Dispose()

$sleepInfo = [Diagnostics.ProcessStartInfo]::new()
Write-Output 'Stage=child_timeout'
$sleepInfo.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$sleepInfo.Arguments = '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 10"'
$sleepInfo.UseShellExecute = $false; $sleepInfo.CreateNoWindow = $true
$sleepChild = [Diagnostics.Process]::new(); $sleepChild.StartInfo = $sleepInfo
if (-not $sleepChild.Start()) { throw 'Synthetic timeout child process did not start.' }
$timeoutResult = Wait-F2AclProcessExit -Process $sleepChild -TimeoutSeconds 1 -PollMilliseconds 25
Assert-F2Acl ($timeoutResult.TimedOut -and $sleepChild.HasExited) 'timed out child is stopped and actual exit observed'
$sleepChild.Dispose()

$testAclParent = [IO.Path]::GetFullPath($env:LOCALAPPDATA)
Write-Output 'Stage=restricted_local_evidence_directory'
$normalPath = Join-Path $testAclParent 'F2Acl-Nonexistent-Path-Check'
try { Test-F2AclNoReparseAncestors -Path $normalPath; Assert-F2Acl $true 'ordinary evidence path ancestors accepted' }
catch { Assert-F2Acl $false ('ordinary evidence path ancestor check: ' + $_.Exception.Message) }
$junctionTarget = Join-Path $testAclParent ('F2Acl-Junction-Target-' + [guid]::NewGuid().ToString('N'))
$junctionPath = Join-Path $testAclParent ('F2Acl-Junction-Test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($junctionTarget)
try {
    $mklinkOutput = & $env:ComSpec /d /c ('mklink /J "{0}" "{1}"' -f $junctionPath, $junctionTarget) 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Could not create synthetic junction: ' + ($mklinkOutput -join ' ')) }
    Assert-F2AclReject { Test-F2AclNoReparseAncestors -Path (Join-Path $junctionPath 'missing-child') } 'ancestor junction is rejected'
}
finally {
    if (Test-Path -LiteralPath $junctionPath) {
        $junctionItem = Get-Item -LiteralPath $junctionPath -Force
        if (($junctionItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -or [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($junctionPath)) -ne $testAclParent) { throw 'Refusing to remove unexpected synthetic junction.' }
        & $env:ComSpec /d /c ('rmdir "{0}"' -f $junctionPath) | Out-Null
    }
    if (Test-Path -LiteralPath $junctionTarget) {
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($junctionTarget)) -ne $testAclParent -or @(Get-ChildItem -LiteralPath $junctionTarget -Force).Count -ne 0) { throw 'Refusing to remove unexpected synthetic junction target.' }
        Remove-Item -LiteralPath $junctionTarget -Force
    }
}
$testAclPath = Join-Path $testAclParent ('F2Acl-Protocol-Test-' + [guid]::NewGuid().ToString('N'))
try {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    [void](New-F2AclRestrictedDirectory -Path $testAclPath -OwnerSid $currentSid)
    $aclCheck = Test-F2AclRestrictedDirectory -Path $testAclPath -OwnerSid $currentSid
    Assert-F2Acl ($aclCheck.Protected -and $aclCheck.AceCount -eq 3 -and $aclCheck.AllowedSids -contains $currentSid) 'restricted evidence directory owner and DACL verified'
}
catch { Assert-F2Acl $false ('restricted evidence directory: ' + $_.Exception.Message) }
finally {
    if (Test-Path -LiteralPath $testAclPath) {
        $testFull = [IO.Path]::GetFullPath($testAclPath)
        $testItem = Get-Item -LiteralPath $testFull -Force
        if ([IO.Path]::GetDirectoryName($testFull) -ne $testAclParent -or [IO.Path]::GetFileName($testFull) -notlike 'F2Acl-Protocol-Test-*' -or ($testItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing to remove unexpected synthetic evidence directory.' }
        if (@(Get-ChildItem -LiteralPath $testFull -Force).Count -ne 0) { throw 'Synthetic evidence directory is not empty; refusing cleanup.' }
        Remove-Item -LiteralPath $testFull -Force
    }
}

$badAclPath = Join-Path $testAclParent ('F2Acl-Bad-Dacl-Test-' + [guid]::NewGuid().ToString('N'))
$badAclSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$badAclSddl = 'O:' + $badAclSid + 'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;SY)(A;OICI;FA;;;' + $badAclSid + ')'
try {
    [F2Acl.NativeDirectory]::CreateWithSddl($badAclPath, $badAclSddl)
    Assert-F2AclReject { Test-F2AclRestrictedDirectory -Path $badAclPath -OwnerSid $badAclSid } 'duplicate or missing restricted-directory principal fails closed'
}
finally {
    if (Test-Path -LiteralPath $badAclPath) {
        $badItem = Get-Item -LiteralPath $badAclPath -Force
        if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($badAclPath)) -ne $testAclParent -or [IO.Path]::GetFileName($badAclPath) -notlike 'F2Acl-Bad-Dacl-Test-*' -or ($badItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or @(Get-ChildItem -LiteralPath $badAclPath -Force).Count -ne 0) { throw 'Refusing to remove unexpected bad-DACL fixture.' }
        Remove-Item -LiteralPath $badAclPath -Force
    }
}

$otherSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-11')
$readOnlyRule = [Security.AccessControl.FileSystemAccessRule]::new($otherSid, [Security.AccessControl.FileSystemRights]::ReadAndExecute, [Security.AccessControl.AccessControlType]::Allow)
$writeRule = [Security.AccessControl.FileSystemAccessRule]::new($otherSid, [Security.AccessControl.FileSystemRights]::WriteData, [Security.AccessControl.AccessControlType]::Allow)
$writeAttributesRule = [Security.AccessControl.FileSystemAccessRule]::new($otherSid, [Security.AccessControl.FileSystemRights]::WriteAttributes, [Security.AccessControl.AccessControlType]::Allow)
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Assert-F2Acl (@(Get-F2AclUnexpectedWritableSids -Rules @($readOnlyRule) -OwnerSid $currentSid).Count -eq 0) 'read-only parent ACE is allowed'
Assert-F2Acl (@(Get-F2AclUnexpectedWritableSids -Rules @($writeRule) -OwnerSid $currentSid) -contains 'S-1-5-11') 'unexpected parent writer is rejected by SID'
Assert-F2Acl (@(Get-F2AclUnexpectedWritableSids -Rules @($writeAttributesRule) -OwnerSid $currentSid) -contains 'S-1-5-11') 'write-attributes parent ACE is rejected'
$boundedRecords = [Collections.Generic.List[object]]::new()
$boundedState = [pscustomobject]@{Bytes=0}
Add-F2AclBoundedStreamRecord -Records $boundedRecords -State $boundedState -Stream 'Warning' -Message 'synthetic warning'
Assert-F2Acl ($boundedRecords.Count -eq 1 -and $boundedState.Bytes -gt 0 -and $boundedState.Bytes -le 65536) 'bounded stream collector accounts serialized records'
$beforeOversizeCount = $boundedRecords.Count; $beforeOversizeBytes = $boundedState.Bytes
Assert-F2AclReject { Add-F2AclBoundedStreamRecord -Records $boundedRecords -State $boundedState -Stream 'Error' -Message ('x' * 70000) } 'oversized PowerShell stream record rejected before append'
Assert-F2Acl ($boundedRecords.Count -eq $beforeOversizeCount -and $boundedState.Bytes -eq $beforeOversizeBytes) 'oversized stream leaves bounded collection unchanged'

Write-Output "Assertions=$script:Assertions;Failures=$($script:Failures.Count)"
if ($script:Failures.Count -gt 0) {
    $script:Failures | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output 'Cases=source_pins,complete,argument_quoting,frame_roundtrip,bounded_eof_probe,standard_ace,callback_ace_rejection,object_ace_rejection,unknown_ace_flag_rejection,ancestor_junction_rejection,oversized_writer,oversized_reader,corrupt,partial_frame,stalled_partial_header,missing,duplicate,malformed_json,missing_envelope,missing_record_field,child_exit,sha256,partial_record,empty_preflight_failure,stdout_stderr,timeout,restricted_evidence_directory,exact_acl_principals,read_only_parent_ace,write_parent_ace,write_attributes_parent_ace,bounded_stream_accounting,oversized_stream_rejection'
[Environment]::Exit(0)

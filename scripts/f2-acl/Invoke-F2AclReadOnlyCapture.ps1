[CmdletBinding()]
param(
    [switch]$CollectorChild,
    [string]$PipeName,
    [string]$OutputDirectory,
    [string]$ExpectedScriptSha256,
    [string]$ExpectedModuleSha256,
    [string]$ExpectedCommitSha,
    [ValidateRange(1, 3600)][int]$WaitSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$vmId = '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1'
$vmName = 'F2-G1-Isolated-Disposable'
$volumeRoot = 'G:\'
$projectRoot = 'G:\F2-G1-Isolated-Disposable'
$expectedSerial = '152D20337A0C'
$expectedModel = 'KINGSTON SA400S37240G'
$expectedCapabilitySid = 'S-1-15-3-1024-2268835264-3721307629-241982045-173645152-1490879176-104643441-2915960892-1612460704'
$protocolPath = Join-Path $PSScriptRoot 'F2AclCapture.Protocol.psm1'

function ConvertTo-F2AclQuotedArgument {
    param([string]$Value)
    return ConvertTo-F2AclWindowsArgument -Value $Value
}

function Get-F2AclLocalSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function ConvertTo-F2AclPowerShellLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Open-F2AclPinnedSource {
    param([Parameter(Mandatory)][string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $digest = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $stream.Position = 0
        return [pscustomobject]@{Stream=$stream;Sha256=$digest;Path=$Path}
    }
    catch { $stream.Dispose(); throw }
}

function Add-F2AclGate {
    param([Collections.Generic.List[object]]$Gates, [Collections.Generic.List[string]]$Errors, [string]$Name, [bool]$Pass, [string]$Detail)
    $Gates.Add([ordered]@{Name=$Name;Pass=$Pass;Detail=$Detail})
    if (-not $Pass) { $Errors.Add("GateFailed:${Name}:${Detail}") }
}

function Get-F2AclSerialKey {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return ($Value -replace '\s', '').ToUpperInvariant()
}

function Test-F2AclNoReparsePath {
    param([string]$Path, [string]$StopAt)
    $current = [IO.Path]::GetFullPath($Path)
    $stop = [IO.Path]::GetFullPath($StopAt).TrimEnd('\')
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "ReparsePoint:$current" }
        if ([string]::Equals($current.TrimEnd('\'), $stop, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw "PathEscapedBoundary:$Path" }
        $current = $parent.FullName
        if (-not ($current.StartsWith($stop + '\', [StringComparison]::OrdinalIgnoreCase))) { throw "PathEscapedBoundary:$Path" }
    }
}

function Get-F2AclRecord {
    param([string]$Path)
    $errorText = ''
    $sddl = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try { $sddl = [F2Acl.NativeDirectory]::GetSddl($Path); break }
        catch { $errorText = $_.Exception.Message; if ($attempt -lt 2) { Start-Sleep -Milliseconds 200 } }
    }
    if ([string]::IsNullOrWhiteSpace($sddl)) {
        return [ordered]@{Path=$Path;Owner='';OwnerSid='';Sddl='';DaclProtected=$false;Status='FAIL';Error=$errorText;AceCount=0;Aces=@()}
    }
    try {
        $raw = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
        if ($null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0) { throw 'Object has a missing or null DACL.' }
        $ownerSid = $raw.Owner.Value
        try { $ownerName = $raw.Owner.Translate([Security.Principal.NTAccount]).Value } catch { $ownerName = $ownerSid }
        $aces = @()
        foreach ($ace in $raw.DiscretionaryAcl) {
            Assert-F2AclSupportedAce -Ace $ace | Out-Null
            $type = if ($ace.AceType -eq [Security.AccessControl.AceType]::AccessAllowed) { 'Allow' } else { 'Deny' }
            $sid = $ace.SecurityIdentifier
            try { $principal = $sid.Translate([Security.Principal.NTAccount]).Value } catch { $principal = $sid.Value }
            $aceFlags = $ace.AceFlags
            $inheritance = @()
            if (($aceFlags -band [Security.AccessControl.AceFlags]::ObjectInherit) -ne 0) { $inheritance += 'ObjectInherit' }
            if (($aceFlags -band [Security.AccessControl.AceFlags]::ContainerInherit) -ne 0) { $inheritance += 'ContainerInherit' }
            $propagation = @()
            if (($aceFlags -band [Security.AccessControl.AceFlags]::NoPropagateInherit) -ne 0) { $propagation += 'NoPropagateInherit' }
            if (($aceFlags -band [Security.AccessControl.AceFlags]::InheritOnly) -ne 0) { $propagation += 'InheritOnly' }
            $aces += [ordered]@{
                Principal = [string]$principal
                Sid = $sid.Value
                Type = $type
                Rights = [string]([Security.AccessControl.FileSystemRights]$ace.AccessMask)
                AccessMask = ('0x{0:X8}' -f ([int]$ace.AccessMask -band 0xFFFFFFFF))
                InheritanceFlags = if ($inheritance.Count) { $inheritance -join ',' } else { 'None' }
                PropagationFlags = if ($propagation.Count) { $propagation -join ',' } else { 'None' }
                Inherited = (($aceFlags -band [Security.AccessControl.AceFlags]::Inherited) -ne 0)
            }
        }
        if ([string]::IsNullOrWhiteSpace($sddl) -or [string]::IsNullOrWhiteSpace($ownerSid)) { throw 'Owner or SDDL was empty.' }
        return [ordered]@{
            Path = [IO.Path]::GetFullPath($Path)
            Owner = [string]$ownerName
            OwnerSid = $ownerSid
            Sddl = [string]$sddl
            DaclProtected = (($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0)
            Status = 'PASS'
            Error = ''
            AceCount = $aces.Count
            Aces = $aces
        }
    }
    catch {
        return [ordered]@{Path=$Path;Owner='';OwnerSid='';Sddl=[string]$sddl;DaclProtected=$false;Status='FAIL';Error=$_.Exception.Message;AceCount=0;Aces=@()}
    }
}

function Get-F2AclExpectedPaths {
    param([string]$Root, [string]$VmGuid)
    $config = Join-Path $Root $vmName
    $configVm = Join-Path $config 'Virtual Machines'
    $rootVm = Join-Path $Root 'Virtual Machines'
    return @(
        $Root,
        $config,
        $configVm,
        (Join-Path $configVm $VmGuid),
        (Join-Path $configVm ($VmGuid + '.vmcx')),
        (Join-Path $configVm ($VmGuid + '.vmgs')),
        (Join-Path $configVm ($VmGuid + '.VMRS')),
        (Join-Path $Root 'F2-G1-OS.vhdx'),
        (Join-Path $Root 'F2-G1-Scratch.vhdx'),
        $rootVm,
        (Join-Path $rootVm $VmGuid)
    ) | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ }
}

function Invoke-F2AclCollectorChild {
    param([string]$TargetPipe)

    $gates = [Collections.Generic.List[object]]::new()
    $errors = [Collections.Generic.List[string]]::new()
    $records = [Collections.Generic.List[object]]::new()
    $diskMetadata = [ordered]@{SerialMatched=$false;Serial=$expectedSerial;Model='';DriveLetter='G:';FileSystem='';BusType='';Health='';PhysicalHealth='';VolumeHealth='';DiskNumber=$null;Win32Index=$null;PartitionDisk=$null;Matches=@{Win32=0;Disk=0;Physical=0}}
    $metadata = [ordered]@{Gates=@();Disk=$diskMetadata;ConfiguredPaths=@{};VmNicCount=$null}
    $paths = Get-F2AclExpectedPaths -Root $projectRoot -VmGuid $vmId.ToUpperInvariant()

    try {
        if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Windows PowerShell Desktop edition is required.' }
        Import-Module Hyper-V -ErrorAction Stop
        $vm = Get-VM -Id ([guid]$vmId) -ErrorAction Stop
        Add-F2AclGate $gates $errors 'VmImmutableIdentityAndOff' ($vm.Id.ToString().ToLowerInvariant() -eq $vmId -and $vm.Name -eq $vmName -and $vm.State.ToString() -eq 'Off') ('id/name/state matched; state=' + $vm.State)

        $win32Matches = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Where-Object { (Get-F2AclSerialKey ([string]$_.SerialNumber)) -eq $expectedSerial })
        $diskMatches = @(Get-Disk -ErrorAction Stop | Where-Object { (Get-F2AclSerialKey ([string]$_.SerialNumber)) -eq $expectedSerial })
        $physicalMatches = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { (Get-F2AclSerialKey ([string]$_.SerialNumber)) -eq $expectedSerial })
        $diskMetadata.Matches = @{Win32=$win32Matches.Count;Disk=$diskMatches.Count;Physical=$physicalMatches.Count}
        $oneEach = $win32Matches.Count -eq 1 -and $diskMatches.Count -eq 1 -and $physicalMatches.Count -eq 1
        Add-F2AclGate $gates $errors 'KingstonSerialUniqueAcrossInterfaces' $oneEach ('matches Win32/Disk/Physical=' + $win32Matches.Count + '/' + $diskMatches.Count + '/' + $physicalMatches.Count)
        if ($oneEach) {
            $win32Disk = $win32Matches[0]; $disk = $diskMatches[0]; $physical = $physicalMatches[0]
            $modelPass = ([string]$win32Disk.Model).Trim() -eq $expectedModel
            $transportPass = $disk.BusType.ToString() -eq 'USB'
            $healthPass = $disk.HealthStatus.ToString() -eq 'Healthy' -and $disk.OperationalStatus -contains 'Online' -and $physical.HealthStatus.ToString() -eq 'Healthy'
            Add-F2AclGate $gates $errors 'KingstonModelTransportAndHealth' ($modelPass -and $transportPass -and $healthPass) ('model=' + [string]$win32Disk.Model + ';bus=' + $disk.BusType + ';health=' + $disk.HealthStatus)
            $volume = Get-Volume -DriveLetter G -ErrorAction Stop
            $partitions = @(Get-Partition -DriveLetter G -ErrorAction Stop)
            $mapped = $partitions.Count -eq 1 -and $partitions[0].DiskNumber -eq $disk.Number -and $win32Disk.Index -eq $disk.Number
            $volumePass = $mapped -and $volume.FileSystem -eq 'NTFS' -and $volume.HealthStatus.ToString() -eq 'Healthy'
            Add-F2AclGate $gates $errors 'GVolumeMapsToSerialSelectedDevice' $volumePass ('partition count=' + $partitions.Count + ';disk number=' + $disk.Number + ';filesystem=' + $volume.FileSystem + ';volume health=' + $volume.HealthStatus)
            $diskMetadata.SerialMatched = $mapped
            $diskMetadata.Model = ([string]$win32Disk.Model).Trim()
            $diskMetadata.FileSystem = [string]$volume.FileSystem
            $diskMetadata.BusType = $disk.BusType.ToString()
            $diskMetadata.Health = $disk.HealthStatus.ToString()
            $diskMetadata.PhysicalHealth = $physical.HealthStatus.ToString()
            $diskMetadata.VolumeHealth = $volume.HealthStatus.ToString()
            $diskMetadata.DiskNumber = [int]$disk.Number
            $diskMetadata.Win32Index = [int]$win32Disk.Index
            $diskMetadata.PartitionDisk = [int]$partitions[0].DiskNumber
        }

        $config = ConvertTo-F2AclCanonicalPath ([string]$vm.ConfigurationLocation)
        $snapshots = ConvertTo-F2AclCanonicalPath ([string]$vm.SnapshotFileLocation)
        $paging = ConvertTo-F2AclCanonicalPath ([string]$vm.SmartPagingFilePath)
        $vhdPaths = @(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop | ForEach-Object { ConvertTo-F2AclCanonicalPath ([string]$_.Path) })
        $expectedConfig = ConvertTo-F2AclCanonicalPath (Join-Path $projectRoot $vmName)
        $expectedVhds = @((Join-Path $projectRoot 'F2-G1-OS.vhdx'), (Join-Path $projectRoot 'F2-G1-Scratch.vhdx') | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
        $configPass = $config -eq $expectedConfig -and $snapshots -eq (ConvertTo-F2AclCanonicalPath $projectRoot) -and $paging -eq (ConvertTo-F2AclCanonicalPath $projectRoot) -and $vhdPaths.Count -eq 2 -and @((Compare-Object ($vhdPaths | Sort-Object) ($expectedVhds | Sort-Object))).Count -eq 0
        Add-F2AclGate $gates $errors 'ConfiguredStoragePathsExact' $configPass 'configuration, checkpoint, smart-paging, and two VHDX paths checked'
        $nicCount = @(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop).Count
        $metadata.VmNicCount = $nicCount
        Add-F2AclGate $gates $errors 'ZeroVirtualNetworkAdapters' ($nicCount -eq 0) ('adapter count=' + $nicCount)
        $metadata.ConfiguredPaths = [ordered]@{Configuration=$config;Snapshots=$snapshots;SmartPaging=$paging;Vhdx=$vhdPaths}
        $capabilityCache = 'HKLM:\SOFTWARE\Microsoft\SecurityManager\CapabilityClasses\AllCachedCapabilities'
        try {
            $cacheData = Get-ItemProperty -LiteralPath $capabilityCache -ErrorAction Stop
            $cacheText = @($cacheData.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { [string]$_.Value }) -join "`n"
            $metadata.CapabilitySidRegistryCheck = [ordered]@{Status='READ';ExactSidPresent=($cacheText.IndexOf($expectedCapabilitySid, [StringComparison]::OrdinalIgnoreCase) -ge 0);Source=$capabilityCache;Scope='Exact SID membership only; no registry value data retained'}
        }
        catch { $metadata.CapabilitySidRegistryCheck = [ordered]@{Status='UNKNOWN';ExactSidPresent=$null;Source=$capabilityCache;Error=$_.Exception.Message} }

        $canonicalPaths = @($paths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
        $uniquePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($path in $canonicalPaths) { [void]$uniquePaths.Add($path) }
        Add-F2AclGate $gates $errors 'ExactlyElevenUniqueKnownPaths' ($canonicalPaths.Count -eq 11 -and $uniquePaths.Count -eq 11) ('expected=' + $canonicalPaths.Count + ';unique=' + $uniquePaths.Count)
        foreach ($path in $canonicalPaths) {
            try { Test-F2AclNoReparsePath -Path $path -StopAt $volumeRoot }
            catch { $errors.Add('PathSafety:' + $_.Exception.Message) }
        }
        Add-F2AclGate $gates $errors 'AllExpectedPathsExistWithoutReparsePoints' (@($errors | Where-Object { $_ -like 'PathSafety:*' }).Count -eq 0) ('checked path count=' + $canonicalPaths.Count)
        if (@($gates | Where-Object { -not $_.Pass }).Count -gt 0) { throw 'One or more preflight gates failed; ACL reads were not started.' }

        foreach ($path in $canonicalPaths) {
            Test-F2AclNoReparsePath -Path $path -StopAt $volumeRoot
            $records.Add((Get-F2AclRecord $path))
        }
        foreach ($record in $records) { if ($record.Status -ne 'PASS') { $errors.Add('AclRecordFailed:' + $record.Path + ':' + $record.Error) } }
    }
    catch {
        $errors.Add('CollectorException:' + $_.Exception.Message)
    }

    $metadata.Gates = @($gates)
    $metadata.Disk.CapabilitySid = $expectedCapabilitySid
    $document = New-F2AclEvidenceDocument -VmId $vmId -VmName $vmName -ExpectedPaths $paths -Records @($records) -Metadata $metadata -Errors @($errors)
    $payload = Get-F2AclJsonBytes $document
    $client = $null
    try {
        $client = [IO.Pipes.NamedPipeClientStream]::new('.', $TargetPipe, [IO.Pipes.PipeDirection]::Out, [IO.Pipes.PipeOptions]::None)
        $client.Connect(30000)
        Write-F2AclFrame -Stream $client -Payload $payload
        if ($document.Complete) { return 0 }
        return 1
    }
    finally { if ($null -ne $client) { $client.Dispose() } }
}

function Save-F2AclEvidence {
    param([byte[]]$Payload, [string]$PayloadSha256, [byte[]]$StreamBytes, [string]$StreamSha256, [int]$ChildExitCode, [string]$EvidencePath, [string]$ScriptSha256, [string]$ModuleSha256)
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $dirCheck = Test-F2AclRestrictedDirectory -Path $EvidencePath -OwnerSid $currentSid
    $volumeProof = Test-F2AclEvidenceVolumeSeparateFromG -Path $EvidencePath
    $payloadPath = Join-Path $EvidencePath 'acl-baseline.json'
    $integrityPath = Join-Path $EvidencePath 'integrity.json'
    $payloadTemp = Join-Path $EvidencePath '.acl-baseline.json.pending'
    $integrityTemp = Join-Path $EvidencePath '.integrity.json.pending'
    $streamPath = Join-Path $EvidencePath 'powershell-streams.json'
    $streamOnDisk = [IO.File]::ReadAllBytes($streamPath)
    if ((Get-F2AclSha256 $streamOnDisk) -cne $StreamSha256 -or $streamOnDisk.Length -ne $StreamBytes.Length) { throw 'PowerShell stream log changed during validation.' }
    $integrity = [ordered]@{Schema='f2-acl-integrity-v1';PayloadFile='acl-baseline.json';PayloadBytes=$Payload.Length;PayloadSha256=$PayloadSha256;PowerShellStreamsFile='powershell-streams.json';PowerShellStreamsBytes=$StreamBytes.Length;PowerShellStreamsSha256=$StreamSha256;ChildExitCode=$ChildExitCode;CollectorScriptSha256=$ScriptSha256;ProtocolModuleSha256=$ModuleSha256;EvidenceVolumeGuid=$volumeProof.EvidenceVolumeGuid;ProjectVolumeGuid=$volumeProof.ProjectVolumeGuid;SeparateFromProjectVolume=$volumeProof.Separate;CreatedUtc=[DateTime]::UtcNow.ToString('o')}
    $integrityBytes = Get-F2AclJsonBytes $integrity
    $payloadPublished = $false; $integrityPublished = $false
    try {
        foreach ($file in @([pscustomobject]@{Path=$payloadTemp;Bytes=$Payload},[pscustomobject]@{Path=$integrityTemp;Bytes=$integrityBytes})) {
            $stream = [IO.File]::Open($file.Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $stream.Write($file.Bytes, 0, $file.Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        }
        if ((Get-F2AclSha256 ([IO.File]::ReadAllBytes($payloadTemp))) -cne $PayloadSha256 -or (Get-F2AclSha256 ([IO.File]::ReadAllBytes($integrityTemp))) -cne (Get-F2AclSha256 $integrityBytes)) { throw 'Temporary evidence bytes failed integrity recheck.' }
        [IO.File]::Move($payloadTemp, $payloadPath); $payloadPublished = $true
        [IO.File]::Move($integrityTemp, $integrityPath); $integrityPublished = $true
        [void](Test-F2AclRestrictedDirectory -Path $EvidencePath -OwnerSid $currentSid)
        return [ordered]@{Directory=$EvidencePath;Payload=$payloadPath;Streams=$streamPath;Integrity=$integrityPath}
    }
    catch {
        foreach ($temporary in @($payloadTemp,$integrityTemp)) { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
        if ($integrityPublished -and [IO.File]::Exists($integrityPath) -and (Get-F2AclSha256 ([IO.File]::ReadAllBytes($integrityPath))) -ceq (Get-F2AclSha256 $integrityBytes)) { [IO.File]::Delete($integrityPath) }
        if ($payloadPublished -and [IO.File]::Exists($payloadPath) -and (Get-F2AclSha256 ([IO.File]::ReadAllBytes($payloadPath))) -ceq $PayloadSha256) { [IO.File]::Delete($payloadPath) }
        throw
    }
}

if ($CollectorChild) {
    $streamLog = [Collections.Generic.List[object]]::new()
    $streamState = [pscustomobject]@{Bytes=0;ExitCode=3}
    $childExit = 3
    try {
        if ($ExpectedScriptSha256 -notmatch '^[0-9a-f]{64}$' -or $ExpectedModuleSha256 -notmatch '^[0-9a-f]{64}$') { throw 'Pinned source digests are missing or malformed.' }
        $actualScriptSha = Get-F2AclLocalSha256 ([IO.File]::ReadAllBytes($PSCommandPath))
        $actualModuleSha = Get-F2AclLocalSha256 ([IO.File]::ReadAllBytes($protocolPath))
        if ($actualScriptSha -cne $ExpectedScriptSha256 -or $actualModuleSha -cne $ExpectedModuleSha256) { throw 'Elevated source hash mismatch; collector was not run.' }
        & {
            Import-Module $protocolPath -Force -ErrorAction Stop
            if ($PipeName -notmatch '^f2acl_[0-9a-f]{32}$') { throw 'Invalid internal pipe name.' }
            if ([string]::IsNullOrWhiteSpace($OutputDirectory) -or -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw 'Restricted output directory is missing.' }
            Test-F2AclEvidenceVolumeSeparateFromG -Path $OutputDirectory | Out-Null
            Invoke-F2AclCollectorChild -TargetPipe $PipeName
        } *>&1 | ForEach-Object {
            $entry = $_
            if ($entry -is [int] -or $entry -is [long]) { $streamState.ExitCode = [int]$entry; return }
            $kind = 'Success'
            if ($entry -is [Management.Automation.ErrorRecord]) { $kind = 'Error' }
            elseif ($entry -is [Management.Automation.WarningRecord]) { $kind = 'Warning' }
            elseif ($entry -is [Management.Automation.VerboseRecord]) { $kind = 'Verbose' }
            elseif ($entry -is [Management.Automation.DebugRecord]) { $kind = 'Debug' }
            elseif ($entry -is [Management.Automation.InformationRecord]) { $kind = 'Information' }
            Add-F2AclBoundedStreamRecord -Records $streamLog -State $streamState -Stream $kind -Message ([string]$entry)
        }
        $childExit = [int]$streamState.ExitCode
    }
    catch {
        $childExit = 3
        $streamState.ExitCode = 3
        try { Add-F2AclBoundedStreamRecord -Records $streamLog -State $streamState -Stream 'Error' -Message ([string]$_.Exception.Message) } catch { }
    }
    try {
        $logDocument = [ordered]@{Schema='f2-acl-powershell-streams-v1';Complete=($streamLog.Count -eq 0 -and $childExit -in @(0,1));ExitCode=$childExit;Records=@($streamLog)}
        $logBytes = Get-F2AclJsonBytes $logDocument
        if ($logBytes.Length -gt 65536) { throw 'Captured PowerShell streams exceed the 64 KiB cap.' }
        $logPath = Join-Path $OutputDirectory 'powershell-streams.json'
        Test-F2AclEvidenceVolumeSeparateFromG -Path $OutputDirectory | Out-Null
        $logFile = [IO.File]::Open($logPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $logFile.Write($logBytes, 0, $logBytes.Length); $logFile.Flush($true) } finally { $logFile.Dispose() }
    }
    catch { [Console]::Error.WriteLine('StreamCaptureFailure:' + $_.Exception.Message); exit 4 }
    exit $childExit
}

$summary = [ordered]@{Outcome='INCOMPLETE';ActualChildExitCode=$null;PayloadSha256=$null;PayloadLength=$null;PowerShellStreamsSha256=$null;StructuredErrors=@();Evidence=$null;WorkingDirectory=$null;Errors=@()}
$server = $null; $child = $null; $pinnedSources = @()
try {
    Import-Module $protocolPath -Force -ErrorAction Stop
    if ($ExpectedCommitSha -notmatch '^[0-9a-f]{40}$') { throw 'Expected reviewed commit SHA is required.' }
    $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $gitExe = (Get-Command git.exe -ErrorAction Stop).Source
    $actualCommit = (& $gitExe -C $repoRoot rev-parse HEAD 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $actualCommit -cne $ExpectedCommitSha) { throw 'Current HEAD does not match the explicitly reviewed commit.' }
    $summary.ReviewedCommit = $actualCommit
    $gitStatus = @(& $gitExe -C $repoRoot status --porcelain 2>&1)
    if ($LASTEXITCODE -ne 0 -or $gitStatus.Count -ne 0) { throw 'Worktree must be clean before the authorized capture.' }
    $pinPath = Join-Path $PSScriptRoot 'F2_ACL_SOURCE_PINS.json'
    $pinnedScript = Open-F2AclPinnedSource -Path $PSCommandPath
    $pinnedModule = Open-F2AclPinnedSource -Path $protocolPath
    $pinnedIndex = Open-F2AclPinnedSource -Path $pinPath
    $pinnedSources = @($pinnedScript, $pinnedModule, $pinnedIndex)
    $pinDocument = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($pinPath)) | ConvertFrom-Json -ErrorAction Stop
    if ($pinDocument.Schema -ne 'f2-acl-source-pins-v1' -or $pinDocument.ScriptSha256 -cne $pinnedScript.Sha256 -or $pinDocument.ModuleSha256 -cne $pinnedModule.Sha256) { throw 'Reviewed source pin manifest does not match the collector source.' }
    $captureId = [guid]::NewGuid().ToString('D')
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $summary.WorkingDirectory = New-F2AclRestrictedDirectory -Path (Join-Path $env:LOCALAPPDATA ('F2-G1-ACL-Evidence-' + $captureId)) -OwnerSid $currentSid
    $summary.EvidenceVolume = Test-F2AclEvidenceVolumeSeparateFromG -Path $summary.WorkingDirectory
    $pipe = 'f2acl_' + [guid]::NewGuid().ToString('N')
    $pipeOptions = [IO.Pipes.PipeOptions]::Asynchronous -bor [IO.Pipes.PipeOptions]::CurrentUserOnly
    $server = [IO.Pipes.NamedPipeServerStream]::new($pipe, [IO.Pipes.PipeDirection]::In, 1, [IO.Pipes.PipeTransmissionMode]::Byte, $pipeOptions)
    $powerShellExe = Join-Path $PSHOME 'powershell.exe'
    $summary.SourcePins = [ordered]@{ReviewedCommit=$actualCommit;ScriptSha256=$pinnedScript.Sha256;ModuleSha256=$pinnedModule.Sha256;PinManifestSha256=$pinnedIndex.Sha256}
    $childCommand = '& ' + (ConvertTo-F2AclPowerShellLiteral $PSCommandPath) + ' -CollectorChild -PipeName ' + (ConvertTo-F2AclPowerShellLiteral $pipe) + ' -OutputDirectory ' + (ConvertTo-F2AclPowerShellLiteral $summary.WorkingDirectory) + ' -ExpectedScriptSha256 ' + (ConvertTo-F2AclPowerShellLiteral $pinnedScript.Sha256) + ' -ExpectedModuleSha256 ' + (ConvertTo-F2AclPowerShellLiteral $pinnedModule.Sha256)
    $encodedChildCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
    $childArgs = @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-EncodedCommand',$encodedChildCommand)
    $childArgumentLine = (@($childArgs | ForEach-Object { ConvertTo-F2AclQuotedArgument ([string]$_) })) -join ' '
    $child = Start-Process -FilePath $powerShellExe -Verb RunAs -ArgumentList $childArgumentLine -PassThru -ErrorAction Stop
    $connectTask = $server.WaitForConnectionAsync()
    $deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
    while (-not $connectTask.IsCompleted) {
        if ($child.HasExited) { $summary.ActualChildExitCode = $child.ExitCode; throw 'Elevated child exited before connecting to the evidence pipe.' }
        if ([DateTime]::UtcNow -ge $deadline) {
            $waitResult = Wait-F2AclProcessExit -Process $child -TimeoutSeconds 1
            $summary.ActualChildExitCode = $waitResult.ExitCode
            throw "CaptureTimeoutAfterSeconds:$WaitSeconds"
        }
        Start-Sleep -Milliseconds 100
    }
    $connectTask.GetAwaiter().GetResult()
    $frame = Read-F2AclFrame -Stream $server -TimeoutSeconds $WaitSeconds
    $summary.PayloadSha256 = $frame.PayloadSha256
    $summary.PayloadLength = $frame.PayloadLength
    $waitResult = Wait-F2AclProcessExit -Process $child -TimeoutSeconds 15
    if (-not $waitResult.Completed) {
        $summary.ActualChildExitCode = $waitResult.ExitCode
        throw 'Elevated child did not exit after closing the evidence frame.'
    }
    $summary.ActualChildExitCode = $waitResult.ExitCode
    $streamPath = Join-Path $summary.WorkingDirectory 'powershell-streams.json'
    if (-not (Test-Path -LiteralPath $streamPath -PathType Leaf)) { throw 'PowerShell stream capture file is missing.' }
    $streamInfo = Get-Item -LiteralPath $streamPath -Force
    if (($streamInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $streamInfo.Length -gt 65536) { throw 'PowerShell stream capture file is unsafe or oversized.' }
    $streamBytes = [IO.File]::ReadAllBytes($streamPath)
    $summary.PowerShellStreamsSha256 = Get-F2AclSha256 $streamBytes
    $streamDocument = [Text.Encoding]::UTF8.GetString($streamBytes) | ConvertFrom-Json -ErrorAction Stop
    if ($streamDocument.Schema -ne 'f2-acl-powershell-streams-v1' -or $streamDocument.Complete -ne $true -or $streamDocument.ExitCode -ne $waitResult.ExitCode) { throw 'PowerShell stream capture is incomplete or inconsistent.' }
    $validation = Test-F2AclEvidenceDocument -Payload $frame.Payload -PayloadSha256 $frame.PayloadSha256 -ChildExitCode $waitResult.ExitCode -ExpectedVmId $vmId -ExpectedVmName $vmName -ExpectedDiskSerial $expectedSerial -ExpectedDiskModel $expectedModel -ExpectedPaths (Get-F2AclExpectedPaths $projectRoot $vmId.ToUpperInvariant())
    if ($null -ne $validation.Document) { $summary.StructuredErrors = @($validation.Document.Manifest.Errors) }
    if (-not $validation.Pass) { $summary.Errors = @($validation.Errors); throw 'Evidence failed completeness or integrity validation.' }
    $summary.Evidence = Save-F2AclEvidence -Payload $frame.Payload -PayloadSha256 $frame.PayloadSha256 -StreamBytes $streamBytes -StreamSha256 $summary.PowerShellStreamsSha256 -ChildExitCode $waitResult.ExitCode -EvidencePath $summary.WorkingDirectory -ScriptSha256 $summary.SourcePins.ScriptSha256 -ModuleSha256 $summary.SourcePins.ModuleSha256
    $summary.Outcome = 'COMPLETE_READ_ONLY_ACL_BASELINE'
}
catch {
    $summary.Errors = @($summary.Errors) + @($_.Exception.Message)
    if ($null -ne $child) {
        try {
            if (-not $child.HasExited) { $waitResult = Wait-F2AclProcessExit -Process $child -TimeoutSeconds 2; $summary.ActualChildExitCode = $waitResult.ExitCode }
            elseif ($summary.ActualChildExitCode -eq $null) { $summary.ActualChildExitCode = $child.ExitCode }
        }
        catch { $summary.Errors = @($summary.Errors) + @('ChildStatusCapture:' + $_.Exception.Message) }
    }
}
finally {
    if ($null -ne $server) { $server.Dispose() }
    if ($null -ne $child) { $child.Dispose() }
    foreach ($sourcePin in $pinnedSources) { if ($null -ne $sourcePin.Stream) { $sourcePin.Stream.Dispose() } }
}

$summary | ConvertTo-Json -Depth 10 -Compress
if ($summary.Outcome -ne 'COMPLETE_READ_ONLY_ACL_BASELINE') { exit 1 }
exit 0

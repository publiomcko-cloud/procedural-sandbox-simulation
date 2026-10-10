[CmdletBinding()]
param(
    [switch]$CollectorChild,
    [switch]$ElevatedCoordinator,
    [string]$OutputDirectory,
    [string]$CaptureId,
    [string]$RequesterSid,
    [string]$CoordinatorSid,
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

function Get-F2AclStorageObservation {
    $win32Matches = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Where-Object { (Get-F2AclSerialKey ([string]$_.SerialNumber)) -eq $expectedSerial })
    $diskMatches = @(Get-Disk -ErrorAction Stop | Where-Object { (Get-F2AclSerialKey ([string]$_.SerialNumber)) -eq $expectedSerial })
    $physicalMatches = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { (Get-F2AclSerialKey ([string]$_.SerialNumber)) -eq $expectedSerial })
    $win32Disk = if ($win32Matches.Count -eq 1) { $win32Matches[0] } else { $null }
    $disk = if ($diskMatches.Count -eq 1) { $diskMatches[0] } else { $null }
    $physical = if ($physicalMatches.Count -eq 1) { $physicalMatches[0] } else { $null }
    $partitions = @(Get-Partition -DriveLetter G -ErrorAction Stop)
    $volume = Get-Volume -DriveLetter G -ErrorAction Stop
    return [ordered]@{
        Win32MatchCount=$win32Matches.Count;DiskMatchCount=$diskMatches.Count;PhysicalMatchCount=$physicalMatches.Count
        Win32Serial=if($null -ne $win32Disk){[string]$win32Disk.SerialNumber}else{$null}
        DiskSerial=if($null -ne $disk){[string]$disk.SerialNumber}else{$null}
        PhysicalSerial=if($null -ne $physical){[string]$physical.SerialNumber}else{$null}
        Win32Model=if($null -ne $win32Disk){[string]$win32Disk.Model}else{$null}
        DiskFriendlyName=if($null -ne $disk){[string]$disk.FriendlyName}else{$null}
        DiskModel=if($null -ne $disk){[string]$disk.Model}else{$null}
        BusType=if($null -ne $disk){$disk.BusType.ToString()}else{$null}
        DiskHealth=if($null -ne $disk){$disk.HealthStatus.ToString()}else{$null}
        DiskOperationalStatus=if($null -ne $disk){@($disk.OperationalStatus | ForEach-Object {$_.ToString()})}else{$null}
        PhysicalHealth=if($null -ne $physical){$physical.HealthStatus.ToString()}else{$null}
        GPartitionCount=$partitions.Count
        PartitionDiskNumber=if($partitions.Count -eq 1){[int]$partitions[0].DiskNumber}else{$null}
        DiskNumber=if($null -ne $disk){[int]$disk.Number}else{$null}
        Win32Index=if($null -ne $win32Disk){[int]$win32Disk.Index}else{$null}
        VolumeFileSystem=[string]$volume.FileSystem
        VolumeHealth=$volume.HealthStatus.ToString()
    }
}

function Add-F2AclStorageObservation {
    param([Collections.Generic.List[object]]$Gates,[Collections.Generic.List[string]]$Errors,[System.Collections.IDictionary]$DiskMetadata,[System.Collections.IDictionary]$Observation)
    $result = Test-F2AclKingstonStorageIdentity -Observation $Observation
    Add-F2AclGate $Gates $Errors 'KingstonSerialUniqueAcrossInterfaces' $result.SerialPass ('matches Win32/Disk/Physical=' + $Observation.Win32MatchCount + '/' + $Observation.DiskMatchCount + '/' + $Observation.PhysicalMatchCount)
    Add-F2AclGate $Gates $Errors 'KingstonModelFieldsMatch' $result.ModelPass ('Win32=' + $Observation.Win32Model + ';FriendlyName=' + $Observation.DiskFriendlyName + ';DiskModel=' + $Observation.DiskModel + ';canonical=' + $result.CanonicalModel)
    Add-F2AclGate $Gates $Errors 'KingstonUSBTransport' $result.TransportPass ('bus=' + $Observation.BusType)
    Add-F2AclGate $Gates $Errors 'KingstonDiskHealthAndOnline' $result.HealthPass ('disk=' + $Observation.DiskHealth + ';operational=' + (@($Observation.DiskOperationalStatus) -join ',') + ';physical=' + $Observation.PhysicalHealth)
    Add-F2AclGate $Gates $Errors 'GVolumeMapsToSerialSelectedDevice' $result.MappingPass ('partition count=' + $Observation.GPartitionCount + ';partition disk=' + $Observation.PartitionDiskNumber + ';disk number=' + $Observation.DiskNumber + ';filesystem=' + $Observation.VolumeFileSystem + ';volume health=' + $Observation.VolumeHealth)

    $DiskMetadata.SerialMatched = $result.SerialPass -and $result.MappingPass
    $DiskMetadata.Serial = $expectedSerial
    $DiskMetadata.Model = $result.CanonicalModel
    $DiskMetadata.RawWin32Model = $result.RawWin32Model
    $DiskMetadata.NormalizedWin32Model = $result.NormalizedWin32Model
    $DiskMetadata.RawDiskFriendlyName = $result.RawDiskFriendlyName
    $DiskMetadata.NormalizedDiskFriendlyName = $result.NormalizedDiskFriendlyName
    $DiskMetadata.RawDiskModel = $result.RawDiskModel
    $DiskMetadata.NormalizedDiskModel = $result.NormalizedDiskModel
    $DiskMetadata.DriveLetter = 'G:'
    $DiskMetadata.FileSystem = [string]$Observation.VolumeFileSystem
    $DiskMetadata.BusType = [string]$Observation.BusType
    $DiskMetadata.Health = [string]$Observation.DiskHealth
    $DiskMetadata.PhysicalHealth = [string]$Observation.PhysicalHealth
    $DiskMetadata.VolumeHealth = [string]$Observation.VolumeHealth
    $DiskMetadata.DiskNumber = $Observation.DiskNumber
    $DiskMetadata.Win32Index = $Observation.Win32Index
    $DiskMetadata.PartitionDisk = $Observation.PartitionDiskNumber
    foreach ($key in $Observation.Keys) { $DiskMetadata[$key] = $Observation[$key] }
    return $result
}

function Get-F2AclVmStorageSnapshot {
    param([Parameter(Mandatory)]$Vm)
    $configuration = ConvertTo-F2AclCanonicalPath ([string]$Vm.ConfigurationLocation)
    $checkpoints = ConvertTo-F2AclCanonicalPath ([string]$Vm.SnapshotFileLocation)
    $smartPaging = ConvertTo-F2AclCanonicalPath ([string]$Vm.SmartPagingFilePath)
    $vhdPaths = @(Get-VMHardDiskDrive -VM $Vm -ErrorAction Stop | ForEach-Object { ConvertTo-F2AclCanonicalPath ([string]$_.Path) })
    $nicCount = @(Get-VMNetworkAdapter -VM $Vm -ErrorAction Stop).Count
    $expectedConfiguration = ConvertTo-F2AclCanonicalPath (Join-Path $projectRoot $vmName)
    $expectedVhds = @((Join-Path $projectRoot 'F2-G1-OS.vhdx'), (Join-Path $projectRoot 'F2-G1-Scratch.vhdx') | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
    $validation = Test-F2AclVmStorageSnapshot -VmId $Vm.Id.ToString() -VmName $Vm.Name -VmState $Vm.State.ToString() -ExpectedVmId $vmId -ExpectedVmName $vmName -ExpectedConfiguration $expectedConfiguration -ExpectedCheckpoints $projectRoot -ExpectedSmartPaging $projectRoot -ExpectedVhdPaths $expectedVhds -Configuration $configuration -Checkpoints $checkpoints -SmartPaging $smartPaging -VhdPaths $vhdPaths -NicCount $nicCount
    return [pscustomobject]@{Validation=$validation;Configuration=$configuration;Checkpoints=$checkpoints;SmartPaging=$smartPaging;VhdPaths=$vhdPaths;NicCount=$nicCount;VmId=$Vm.Id.ToString().ToLowerInvariant();VmName=$Vm.Name;VmState=$Vm.State.ToString()}
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

    $gates = [Collections.Generic.List[object]]::new()
    $errors = [Collections.Generic.List[string]]::new()
    $records = [Collections.Generic.List[object]]::new()
    $finalVmState = 'Unknown'
    $diskMetadata = [ordered]@{SerialMatched=$false;Serial=$expectedSerial;Model='';RawWin32Model='';NormalizedWin32Model='';RawDiskFriendlyName='';NormalizedDiskFriendlyName='';RawDiskModel='';NormalizedDiskModel='';DriveLetter='G:';FileSystem='';BusType='';Health='';PhysicalHealth='';VolumeHealth='';DiskNumber=$null;Win32Index=$null;PartitionDisk=$null}
    $metadata = [ordered]@{Gates=@();Disk=$diskMetadata;ConfiguredPaths=@{};VmNicCount=$null}
    $paths = Get-F2AclExpectedPaths -Root $projectRoot -VmGuid $vmId.ToUpperInvariant()

    try {
        if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Windows PowerShell Desktop edition is required.' }
        Import-Module Hyper-V -ErrorAction Stop
        $vm = Get-VM -Id ([guid]$vmId) -ErrorAction Stop
        $initialVmIdentityPass = $vm.Id.ToString().ToLowerInvariant() -eq $vmId -and $vm.Name -eq $vmName -and $vm.State.ToString() -eq 'Off'
        Add-F2AclGate $gates $errors 'VmImmutableIdentityAndOff' $initialVmIdentityPass ('id/name/state matched=' + $initialVmIdentityPass + '; state=' + $vm.State)

        $storageObservation = Get-F2AclStorageObservation
        [void](Add-F2AclStorageObservation -Gates $gates -Errors $errors -DiskMetadata $diskMetadata -Observation $storageObservation)

        $initialSnapshot = Get-F2AclVmStorageSnapshot -Vm $vm
        Add-F2AclGate $gates $errors 'ConfiguredStoragePathsExact' $initialSnapshot.Validation.PathsPass 'configuration, checkpoint, smart-paging, and two VHDX paths checked'
        Add-F2AclGate $gates $errors 'ZeroVirtualNetworkAdapters' $initialSnapshot.Validation.NicPass ('adapter count=' + $initialSnapshot.NicCount)
        $metadata.VmNicCount = $initialSnapshot.NicCount
        $metadata.ConfiguredPaths = [ordered]@{Configuration=$initialSnapshot.Configuration;Snapshots=$initialSnapshot.Checkpoints;SmartPaging=$initialSnapshot.SmartPaging;Vhdx=$initialSnapshot.VhdPaths}
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

        try {
            $postVm = Get-VM -Id ([guid]$vmId) -ErrorAction Stop
            $finalVmState = $postVm.State.ToString()
            $postSnapshot = Get-F2AclVmStorageSnapshot -Vm $postVm
            Add-F2AclGate $gates $errors 'PostCollectionVmIdentityAndOff' $postSnapshot.Validation.IdentityPass ('id/name/state=' + $postVm.Id + '/' + $postVm.Name + '/' + $postVm.State)
            Add-F2AclGate $gates $errors 'PostCollectionStoragePathsUnchanged' $postSnapshot.Validation.PathsPass 'configuration, checkpoint, smart-paging, and VHDX paths re-read after ACL collection'
            Add-F2AclGate $gates $errors 'PostCollectionZeroVirtualNetworkAdapters' $postSnapshot.Validation.NicPass ('adapter count=' + $postSnapshot.NicCount)

            $postStorage = Get-F2AclStorageObservation
            $postStorageValidation = Test-F2AclKingstonStorageIdentity -Observation $postStorage
            Add-F2AclGate $gates $errors 'PostCollectionKingstonStorageIdentityUnchanged' $postStorageValidation.Pass ('serial/model/USB/health/G: mapping re-read; canonical model=' + $postStorageValidation.CanonicalModel)
            $metadata.PostCollection = [ordered]@{VmId=$postVm.Id.ToString().ToLowerInvariant();VmName=$postVm.Name;VmState=$postVm.State.ToString();Paths=$postSnapshot;Storage=$postStorage;StorageValidation=$postStorageValidation}

            foreach ($path in $canonicalPaths) {
                try { Test-F2AclNoReparsePath -Path $path -StopAt $volumeRoot }
                catch { $errors.Add('PostCollectionPathSafety:' + $_.Exception.Message) }
            }
            $postPathSafetyPass = @($errors | Where-Object { $_ -like 'PostCollectionPathSafety:*' }).Count -eq 0
            Add-F2AclGate $gates $errors 'PostCollectionNoReparsePoints' $postPathSafetyPass ('rechecked target path count=' + $canonicalPaths.Count)
        }
        catch {
            Add-F2AclGate $gates $errors 'PostCollectionRevalidationCompleted' $false $_.Exception.Message
        }
    }
    catch {
        $errors.Add('CollectorException:' + $_.Exception.Message)
    }

    $metadata.Gates = @($gates)
    $metadata.Disk.CapabilitySid = $expectedCapabilitySid
    $document = New-F2AclEvidenceDocument -VmId $vmId -VmName $vmName -ExpectedPaths $paths -Records @($records) -Metadata $metadata -Errors @($errors) -VmState $finalVmState
    $payload = Get-F2AclJsonBytes $document
    $frameStream = [IO.MemoryStream]::new()
    try {
        Write-F2AclFrame -Stream $frameStream -Payload $payload
        $framePath = Join-Path $OutputDirectory 'acl-baseline.frame'
        [void](Write-F2AclAtomicCreateNewFile -Path $framePath -Bytes $frameStream.ToArray() -MaxBytes 262188)
        [Console]::Out.WriteLine('F2ACL_STAGE:FramePublished')
        if ($document.Complete) { return 0 }
        return 1
    }
    finally { $frameStream.Dispose() }
}

function Save-F2AclEvidence {
    param([byte[]]$Payload, [string]$PayloadSha256, [byte[]]$StreamBytes, [string]$StreamSha256, [int]$ChildExitCode, [string]$EvidencePath, [string]$DirectoryOwnerSid, [string]$ScriptSha256, [string]$ModuleSha256, [object[]]$WorkerDiagnosticFiles)
    $dirCheck = Test-F2AclCoordinatorMailboxDirectory -Path $EvidencePath -RequesterSid $DirectoryOwnerSid
    $volumeProof = Test-F2AclEvidenceVolumeSeparateFromG -Path $EvidencePath
    $payloadPath = Join-Path $EvidencePath 'acl-baseline.json'
    $integrityPath = Join-Path $EvidencePath 'integrity.json'
    $payloadTemp = Join-Path $EvidencePath '.acl-baseline.json.pending'
    $integrityTemp = Join-Path $EvidencePath '.integrity.json.pending'
    $streamPath = Join-Path $EvidencePath 'powershell-streams.json'
    if ($WorkerDiagnosticFiles.Count -ne 2 -or (@($WorkerDiagnosticFiles | ForEach-Object { [string]$_.Name } | Sort-Object) -join ',') -cne 'worker-stderr.json,worker-stdout.json') { throw 'Worker diagnostic file manifest is incomplete.' }
    foreach ($diagnostic in $WorkerDiagnosticFiles) {
        $diagnosticPath = Join-Path $EvidencePath ([string]$diagnostic.Name)
        $diagnosticBytes = Read-F2AclBoundedFile -Path $diagnosticPath -MaxBytes 65536
        if ($diagnosticBytes.Length -ne $diagnostic.Bytes -or (Get-F2AclSha256 $diagnosticBytes) -cne [string]$diagnostic.Sha256) { throw ('Worker diagnostic file integrity mismatch:' + [string]$diagnostic.Name) }
    }
    $streamOnDisk = Read-F2AclBoundedFile -Path $streamPath -MaxBytes 65536
    if ((Get-F2AclSha256 $streamOnDisk) -cne $StreamSha256 -or $streamOnDisk.Length -ne $StreamBytes.Length) { throw 'PowerShell stream log changed during validation.' }
    $integrity = [ordered]@{Schema='f2-acl-integrity-v1';PayloadFile='acl-baseline.json';PayloadBytes=$Payload.Length;PayloadSha256=$PayloadSha256;PowerShellStreamsFile='powershell-streams.json';PowerShellStreamsBytes=$StreamBytes.Length;PowerShellStreamsSha256=$StreamSha256;WorkerDiagnosticFiles=@($WorkerDiagnosticFiles);ChildExitCode=$ChildExitCode;CollectorScriptSha256=$ScriptSha256;ProtocolModuleSha256=$ModuleSha256;EvidenceVolumeGuid=$volumeProof.EvidenceVolumeGuid;ProjectVolumeGuid=$volumeProof.ProjectVolumeGuid;SeparateFromProjectVolume=$volumeProof.Separate;CreatedUtc=[DateTime]::UtcNow.ToString('o')}
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
        [void](Test-F2AclCoordinatorMailboxDirectory -Path $EvidencePath -RequesterSid $DirectoryOwnerSid)
        return [ordered]@{Directory=$EvidencePath;Payload=$payloadPath;Streams=$streamPath;Integrity=$integrityPath}
    }
    catch {
        foreach ($temporary in @($payloadTemp,$integrityTemp)) { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
        if ($integrityPublished -and [IO.File]::Exists($integrityPath) -and (Get-F2AclSha256 ([IO.File]::ReadAllBytes($integrityPath))) -ceq (Get-F2AclSha256 $integrityBytes)) { [IO.File]::Delete($integrityPath) }
        if ($payloadPublished -and [IO.File]::Exists($payloadPath) -and (Get-F2AclSha256 ([IO.File]::ReadAllBytes($payloadPath))) -ceq $PayloadSha256) { [IO.File]::Delete($payloadPath) }
        throw
    }
}

function Write-F2AclWorkerStreamLog {
    param([Parameter(Mandatory)][string]$OutputDirectory,[Parameter(Mandatory)][string]$CaptureId,[Parameter(Mandatory)][byte[]]$Bytes)
    if ($CaptureId -notmatch '^[0-9a-f]{32}$' -or $Bytes.Length -lt 1 -or $Bytes.Length -gt 65536) { throw 'WorkerStreamLogArgumentsInvalid.' }
    $commonData = [IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)).TrimEnd([char[]]@('\','/'))
    $expectedPath = [IO.Path]::GetFullPath((Join-Path $commonData ('F2-G1-ACL-Evidence-' + $CaptureId)))
    $actualPath = [IO.Path]::GetFullPath($OutputDirectory)
    if (-not [string]::Equals($actualPath,$expectedPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'WorkerStreamLogPathMismatch.' }
    $currentPath = $actualPath
    $volumeRootPath = [IO.Path]::GetPathRoot($actualPath)
    while ($true) {
        $directory = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
        if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'WorkerStreamLogDirectoryInvalid.' }
        if ([string]::Equals($currentPath.TrimEnd('\'),$volumeRootPath.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($currentPath)
        if ($null -eq $parent) { throw 'WorkerStreamLogParentWalkFailed.' }
        $currentPath = $parent.FullName
    }
    $finalPath = Join-Path $actualPath 'powershell-streams.json'
    if ([IO.File]::Exists($finalPath) -or [IO.Directory]::Exists($finalPath)) { throw 'WorkerStreamLogAlreadyExists.' }
    $temporaryPath = Join-Path $actualPath ('.powershell-streams.' + [guid]::NewGuid().ToString('N') + '.pending')
    try {
        $file = [IO.File]::Open($temporaryPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $file.Write($Bytes,0,$Bytes.Length); $file.Flush($true) } finally { $file.Dispose() }
        if ([IO.File]::Exists($finalPath) -or [IO.Directory]::Exists($finalPath)) { throw 'WorkerStreamLogAlreadyExists.' }
        [IO.File]::Move($temporaryPath,$finalPath)
        return $finalPath
    }
    catch {
        if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) }
        throw
    }
}

function Invoke-F2AclElevatedCoordinator {
    param([string]$OwnerSid)
    $summary = [ordered]@{Schema='f2-acl-elevated-coordinator-v1';Outcome='INCOMPLETE';CoordinatorSid=$null;RequesterSid=$OwnerSid;AdministratorRoleVerified=$false;WorkerExitCode=$null;WorkerProcessId=$null;WorkerDiagnostics=$null;WorkerExpectedFiles=@();WorkerDiagnosticFiles=@();WorkerDiagnosticFallback=$null;ExpectedProcessExitCode=1;PayloadSha256=$null;StreamsSha256=$null;Errors=@();Evidence=$null}
    $worker = $null; $pinnedSources = @()
    try {
        if ($CaptureId -notmatch '^[0-9a-f]{32}$') { throw 'Coordinator mailbox capture ID is missing or malformed.' }
        $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
        if ([string]::IsNullOrWhiteSpace($commonData)) { throw 'Coordinator mailbox common-data path is unavailable.' }
        $OutputDirectory = [IO.Path]::GetFullPath((Join-Path $commonData ('F2-G1-ACL-Evidence-' + $CaptureId)))
        Import-Module $protocolPath -Force -ErrorAction Stop
        if ($ExpectedCommitSha -notmatch '^[0-9a-f]{40}$' -or $ExpectedScriptSha256 -notmatch '^[0-9a-f]{64}$' -or $ExpectedModuleSha256 -notmatch '^[0-9a-f]{64}$') { throw 'Reviewed commit or pinned source digest is missing or malformed.' }
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $gitExe = (Get-Command git.exe -ErrorAction Stop).Source
        $actualCommit = (& $gitExe -C $repoRoot rev-parse HEAD 2>&1 | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw ('Elevated Administrator account cannot read the reviewed worktree. Retry UAC with an account that can read it; Git reported: ' + $actualCommit) }
        if ($actualCommit -cne $ExpectedCommitSha) { throw 'Elevated coordinator HEAD does not match the caller-reviewed commit.' }
        $gitStatus = @(& $gitExe -C $repoRoot status --porcelain 2>&1)
        if ($LASTEXITCODE -ne 0) { throw ('Elevated Administrator account cannot verify worktree status. Retry UAC with an account that can read it; Git reported: ' + ($gitStatus -join ' ')) }
        if ($gitStatus.Count -ne 0) { throw 'Elevated coordinator requires the same clean reviewed worktree.' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $summary.CoordinatorSid = [string]$identity.User.Value
        $summary.AdministratorRoleVerified = [Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $identityResult = Test-F2AclElevatedIdentityPair -RequesterSid $OwnerSid -CoordinatorSid $summary.CoordinatorSid -CoordinatorIsAdministrator $summary.AdministratorRoleVerified
        if (-not $identityResult.Pass) { throw ('UAC coordinator token rejected: ' + $identityResult.Reason + '. Retry with an Administrator account.') }

        $pinPath = Join-Path $PSScriptRoot 'F2_ACL_SOURCE_PINS.json'
        $pinnedScript = Open-F2AclPinnedSource -Path $PSCommandPath
        $pinnedModule = Open-F2AclPinnedSource -Path $protocolPath
        $pinnedIndex = Open-F2AclPinnedSource -Path $pinPath
        $pinnedSources = @($pinnedScript,$pinnedModule,$pinnedIndex)
        $pinDocument = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($pinPath)) | ConvertFrom-Json -ErrorAction Stop
        if ($pinDocument.Schema -cne 'f2-acl-source-pins-v1' -or $pinnedScript.Sha256 -cne $ExpectedScriptSha256 -or $pinnedModule.Sha256 -cne $ExpectedModuleSha256 -or $pinDocument.ScriptSha256 -cne $pinnedScript.Sha256 -or $pinDocument.ModuleSha256 -cne $pinnedModule.Sha256) { throw 'Elevated coordinator source pin verification failed before worker launch.' }

        $summary.SourcePins = [ordered]@{ReviewedCommit=$actualCommit;ScriptSha256=$pinnedScript.Sha256;ModuleSha256=$pinnedModule.Sha256;PinManifestSha256=$pinnedIndex.Sha256}
        [void](New-F2AclCoordinatorMailboxDirectory -CaptureId $CaptureId -RequesterSid $OwnerSid)
        $workerInvocation = '& ' + (ConvertTo-F2AclPowerShellLiteral $PSCommandPath) + ' -CollectorChild -CaptureId ' + (ConvertTo-F2AclPowerShellLiteral $CaptureId) + ' -OutputDirectory ' + (ConvertTo-F2AclPowerShellLiteral $OutputDirectory) + ' -RequesterSid ' + (ConvertTo-F2AclPowerShellLiteral $OwnerSid) + ' -CoordinatorSid ' + (ConvertTo-F2AclPowerShellLiteral $summary.CoordinatorSid) + ' -ExpectedCommitSha ' + (ConvertTo-F2AclPowerShellLiteral $actualCommit) + ' -ExpectedScriptSha256 ' + (ConvertTo-F2AclPowerShellLiteral $pinnedScript.Sha256) + ' -ExpectedModuleSha256 ' + (ConvertTo-F2AclPowerShellLiteral $pinnedModule.Sha256)
        $workerCommand = New-F2AclWorkerBootstrapCommand -Invocation $workerInvocation
        $powerShellExe = Join-Path $PSHOME 'powershell.exe'
        $waitResult = Invoke-F2AclCapturedPowerShell -PowerShellExe $powerShellExe -CommandText $workerCommand -TimeoutSeconds $WaitSeconds -MaxBytesPerStream 16384
        $summary.WorkerExitCode = $waitResult.ExitCode
        $summary.WorkerProcessId = $waitResult.ProcessId
        $framePath = Join-Path $OutputDirectory 'acl-baseline.frame'
        $streamPath = Join-Path $OutputDirectory 'powershell-streams.json'
        $expectedWorkerFiles = @(
            [pscustomobject]@{Name='acl-baseline.frame';Exists=[IO.File]::Exists($framePath);Length=if([IO.File]::Exists($framePath)){([IO.FileInfo]::new($framePath)).Length}else{$null}},
            [pscustomobject]@{Name='powershell-streams.json';Exists=[IO.File]::Exists($streamPath);Length=if([IO.File]::Exists($streamPath)){([IO.FileInfo]::new($streamPath)).Length}else{$null}}
        )
        $executionReport = New-F2AclWorkerExecutionReport -CapturedProcess $waitResult -ExpectedFiles $expectedWorkerFiles
        $summary.WorkerExpectedFiles = $executionReport.ExpectedFiles
        $summary.WorkerDiagnostics = $executionReport.Diagnostics
        $summary.Errors = @($summary.Errors) + @($executionReport.Errors)
        $stdoutBytes = Get-F2AclJsonBytes $executionReport.Stdout
        $stderrBytes = Get-F2AclJsonBytes $executionReport.Stderr
        $stdoutPath = Join-Path $OutputDirectory 'worker-stdout.json'
        $stderrPath = Join-Path $OutputDirectory 'worker-stderr.json'
        try {
            [void](Write-F2AclAtomicCreateNewFile -Path $stdoutPath -Bytes $stdoutBytes -MaxBytes 65536)
            [void](Write-F2AclAtomicCreateNewFile -Path $stderrPath -Bytes $stderrBytes -MaxBytes 65536)
            $summary.WorkerDiagnosticFiles = @(
                [pscustomobject]@{Name='worker-stdout.json';Bytes=$stdoutBytes.Length;Sha256=(Get-F2AclSha256 $stdoutBytes)},
                [pscustomobject]@{Name='worker-stderr.json';Bytes=$stderrBytes.Length;Sha256=(Get-F2AclSha256 $stderrBytes)}
            )
        }
        catch {
            $summary.Errors = @($summary.Errors) + @('WorkerDiagnosticPublicationFailed:' + (ConvertTo-F2AclSanitizedWorkerError -Message ([string]$_.Exception.Message)))
            $summary.WorkerDiagnosticFallback = [ordered]@{Schema='f2-acl-worker-diagnostic-fallback-v1';StdoutBase64=if($null -ne $waitResult.StdoutBytes){[Convert]::ToBase64String([byte[]]$waitResult.StdoutBytes)}else{''};StderrBase64=if($null -ne $waitResult.StderrBytes){[Convert]::ToBase64String([byte[]]$waitResult.StderrBytes)}else{''};StdoutSha256=$executionReport.Stdout.Sha256;StderrSha256=$executionReport.Stderr.Sha256;MaxBytesPerStream=16384;Truncated=([bool]($executionReport.Stdout.Truncated -or $executionReport.Stderr.Truncated))}
        }
        $stdoutDocument = $executionReport.Stdout
        $stderrDocument = $executionReport.Stderr
        $frame = $null
        if ([IO.File]::Exists($framePath)) {
            try {
                $frameBytes = Read-F2AclBoundedFile -Path $framePath -MaxBytes 262188
                $frameStream = [IO.MemoryStream]::new($frameBytes)
                try { $frame = Read-F2AclFrame -Stream $frameStream -TimeoutSeconds 2 } finally { $frameStream.Dispose() }
                $summary.PayloadSha256 = $frame.PayloadSha256
            }
            catch { $summary.Errors = @($summary.Errors) + @('WorkerFrameReadFailure:' + (ConvertTo-F2AclSanitizedWorkerError -Message ([string]$_.Exception.Message))) }
        }
        $streamBytes = $null
        if ([IO.File]::Exists($streamPath)) {
            try {
                $streamBytes = Read-F2AclBoundedFile -Path $streamPath -MaxBytes 65536
                $summary.StreamsSha256 = Get-F2AclSha256 $streamBytes
                $streamDocument = [Text.Encoding]::UTF8.GetString($streamBytes) | ConvertFrom-Json -ErrorAction Stop
                if ($streamDocument.Schema -cne 'f2-acl-powershell-streams-v1' -or $streamDocument.Complete -ne $true -or $streamDocument.ExitCode -ne $waitResult.ExitCode) { $summary.Errors = @($summary.Errors) + @('WorkerPowerShellStreamCaptureIncompleteOrInconsistent.') }
            }
            catch { $summary.Errors = @($summary.Errors) + @('WorkerStreamReadFailure:' + (ConvertTo-F2AclSanitizedWorkerError -Message ([string]$_.Exception.Message))) }
        }
        if ($null -ne $frame -and $null -ne $waitResult.ExitCode) {
            $validation = Test-F2AclEvidenceDocument -Payload $frame.Payload -PayloadSha256 $frame.PayloadSha256 -ChildExitCode ([int]$waitResult.ExitCode) -ExpectedVmId $vmId -ExpectedVmName $vmName -ExpectedDiskSerial $expectedSerial -ExpectedDiskModel $expectedModel -ExpectedPaths (Get-F2AclExpectedPaths $projectRoot $vmId.ToUpperInvariant())
            if ($null -ne $validation.Document) { $summary.StructuredErrors = @($validation.Document.Manifest.Errors) }
            if (-not $validation.Pass) { $summary.Errors = @($summary.Errors) + @($validation.Errors) }
        }
        if (@($summary.Errors).Count -gt 0) { throw 'Worker execution or evidence incomplete; see preserved stage, exit, artifact, stream, and ACL diagnostics.' }
        $summary.Evidence = Save-F2AclEvidence -Payload $frame.Payload -PayloadSha256 $frame.PayloadSha256 -StreamBytes $streamBytes -StreamSha256 $summary.StreamsSha256 -ChildExitCode $waitResult.ExitCode -EvidencePath $OutputDirectory -DirectoryOwnerSid $OwnerSid -ScriptSha256 $pinnedScript.Sha256 -ModuleSha256 $pinnedModule.Sha256 -WorkerDiagnosticFiles $summary.WorkerDiagnosticFiles
        $summary.Outcome = 'COMPLETE_READ_ONLY_ACL_BASELINE'
        $summary.ExpectedProcessExitCode = 0
    }
    catch {
        $summary.Errors = @($summary.Errors) + @($_.Exception.Message)
        if ($null -ne $worker) {
            try {
                if (-not $worker.HasExited) { $workerResult = Wait-F2AclProcessExit -Process $worker -TimeoutSeconds 2; $summary.WorkerExitCode = $workerResult.ExitCode }
                elseif ($null -eq $summary.WorkerExitCode) { $summary.WorkerExitCode = $worker.ExitCode }
            }
            catch { $summary.Errors = @($summary.Errors) + @('WorkerStatusCapture:' + $_.Exception.Message) }
        }
    }
    finally {
        if ($null -ne $worker) { $worker.Dispose() }
        foreach ($sourcePin in $pinnedSources) { if ($null -ne $sourcePin.Stream) { $sourcePin.Stream.Dispose() } }
    }
    $statusPath = Join-Path $OutputDirectory 'coordinator-status.json'
    try {
        $statusJson = ConvertTo-Json -InputObject $summary -Depth 12 -Compress
        $statusBytes = [Text.UTF8Encoding]::new($false).GetBytes($statusJson)
        if ($statusBytes.Length -lt 1 -or $statusBytes.Length -gt 65536) { throw 'Coordinator status exceeds its 64 KiB limit.' }
        if (Get-Command Write-F2AclAtomicCreateNewFile -ErrorAction SilentlyContinue) {
            [void](Write-F2AclAtomicCreateNewFile -Path $statusPath -Bytes $statusBytes -MaxBytes 65536)
        }
        else {
            $statusTemp = $statusPath + '.' + [guid]::NewGuid().ToString('N') + '.pending'
            $statusStream = [IO.File]::Open($statusTemp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { $statusStream.Write($statusBytes,0,$statusBytes.Length); $statusStream.Flush($true) } finally { $statusStream.Dispose() }
            [IO.File]::Move($statusTemp,$statusPath)
        }
    }
    catch { [Console]::Error.WriteLine('CoordinatorStatusWriteFailure:' + $_.Exception.Message); return 4 }
    return [int]$summary.ExpectedProcessExitCode
}

function Test-F2AclSavedEvidencePackage {
    param([string]$EvidencePath,[string]$OwnerSid,[int]$CoordinatorExitCode,[string]$ScriptSha256,[string]$ModuleSha256,[object[]]$WorkerDiagnosticFiles)
    Import-Module $protocolPath -Force -ErrorAction Stop
    [void](Test-F2AclCoordinatorMailboxDirectory -Path $EvidencePath -RequesterSid $OwnerSid)
    Test-F2AclEvidenceVolumeSeparateFromG -Path $EvidencePath | Out-Null
    $payloadPath = Join-Path $EvidencePath 'acl-baseline.json'
    $streamPath = Join-Path $EvidencePath 'powershell-streams.json'
    $integrityPath = Join-Path $EvidencePath 'integrity.json'
    if ($WorkerDiagnosticFiles.Count -ne 2) { throw 'Coordinator worker diagnostic manifest is incomplete.' }
    foreach ($diagnostic in $WorkerDiagnosticFiles) {
        $diagnosticPath = Join-Path $EvidencePath ([string]$diagnostic.Name)
        $diagnosticBytes = Read-F2AclBoundedFile -Path $diagnosticPath -MaxBytes 65536
        if ($diagnosticBytes.Length -ne $diagnostic.Bytes -or (Get-F2AclSha256 $diagnosticBytes) -cne [string]$diagnostic.Sha256) { throw ('Saved worker diagnostic integrity mismatch:' + [string]$diagnostic.Name) }
    }
    $payload = Read-F2AclBoundedFile -Path $payloadPath -MaxBytes 262144
    $streamBytes = Read-F2AclBoundedFile -Path $streamPath -MaxBytes 65536
    $integrityBytes = Read-F2AclBoundedFile -Path $integrityPath -MaxBytes 65536
    $payloadHash = Get-F2AclSha256 $payload; $streamsHash = Get-F2AclSha256 $streamBytes
    $integrity = [Text.Encoding]::UTF8.GetString($integrityBytes) | ConvertFrom-Json -ErrorAction Stop
    $integrityDiagnostics = @($integrity.WorkerDiagnosticFiles | Sort-Object Name | ForEach-Object { ([string]$_.Name) + ':' + [string]$_.Bytes + ':' + [string]$_.Sha256 }) -join '|'
    $expectedDiagnostics = @($WorkerDiagnosticFiles | Sort-Object Name | ForEach-Object { ([string]$_.Name) + ':' + [string]$_.Bytes + ':' + [string]$_.Sha256 }) -join '|'
    if ($integrity.Schema -cne 'f2-acl-integrity-v1' -or $integrity.PayloadFile -cne 'acl-baseline.json' -or $integrity.PayloadBytes -ne $payload.Length -or $integrity.PayloadSha256 -cne $payloadHash -or $integrity.PowerShellStreamsFile -cne 'powershell-streams.json' -or $integrity.PowerShellStreamsBytes -ne $streamBytes.Length -or $integrity.PowerShellStreamsSha256 -cne $streamsHash -or $integrityDiagnostics -cne $expectedDiagnostics -or $integrity.ChildExitCode -ne 0 -or $integrity.CollectorScriptSha256 -cne $ScriptSha256 -or $integrity.ProtocolModuleSha256 -cne $ModuleSha256 -or $integrity.SeparateFromProjectVolume -ne $true) { throw 'Saved evidence integrity manifest does not match its exact files or pins.' }
    $streamDocument = [Text.Encoding]::UTF8.GetString($streamBytes) | ConvertFrom-Json -ErrorAction Stop
    if ($streamDocument.Schema -cne 'f2-acl-powershell-streams-v1' -or $streamDocument.Complete -ne $true -or $streamDocument.ExitCode -ne 0) { throw 'Saved PowerShell stream evidence is incomplete or inconsistent.' }
    $validation = Test-F2AclEvidenceDocument -Payload $payload -PayloadSha256 $payloadHash -ChildExitCode 0 -ExpectedVmId $vmId -ExpectedVmName $vmName -ExpectedDiskSerial $expectedSerial -ExpectedDiskModel $expectedModel -ExpectedPaths (Get-F2AclExpectedPaths $projectRoot $vmId.ToUpperInvariant())
    if (-not $validation.Pass) { throw ('Saved ACL baseline failed parent revalidation: ' + ($validation.Errors -join ';')) }
    return [pscustomobject]@{Payload=$payloadPath;Streams=$streamPath;Integrity=$integrityPath;PayloadSha256=$payloadHash;StreamsSha256=$streamsHash;WorkerDiagnosticFiles=@($WorkerDiagnosticFiles);CoordinatorExitCode=$CoordinatorExitCode}
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
        [Console]::Out.WriteLine('F2ACL_STAGE:SourceVerified')
        & {
            Import-Module $protocolPath -Force -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace($OutputDirectory) -or -not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { throw 'Restricted output directory is missing.' }
            $childIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $childIsAdministrator = [Security.Principal.WindowsPrincipal]::new($childIdentity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            $identityGate = Test-F2AclElevatedIdentityPair -RequesterSid $RequesterSid -CoordinatorSid ([string]$childIdentity.User.Value) -CoordinatorIsAdministrator $childIsAdministrator
            if (-not $identityGate.Pass -or [string]$childIdentity.User.Value -cne $CoordinatorSid) { throw ('Elevated worker identity verification failed: ' + $identityGate.Reason) }
            [void](Test-F2AclCoordinatorMailboxDirectory -Path $OutputDirectory -RequesterSid $RequesterSid)
            Test-F2AclEvidenceVolumeSeparateFromG -Path $OutputDirectory | Out-Null
            [Console]::Out.WriteLine('F2ACL_STAGE:MailboxVerified')
            [Console]::Out.WriteLine('F2ACL_STAGE:CollectorEntered')
            Invoke-F2AclCollectorChild
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
        try {
            $message = [regex]::Replace([string]$_.Exception.Message,'[\x00-\x08\x0B\x0C\x0E-\x1F]','?')
            $message = [regex]::Replace($message,'(?i)\bS-\d-(?:\d+-?)+','[sid]')
            $message = [regex]::Replace($message,'(?i)\b[A-Z]:\\[^\s;,)]+','[path]')
            if ($message.Length -gt 4096) { $message=$message.Substring(0,4096) }
            [Console]::Error.WriteLine('F2ACL_FATAL:' + $message)
            $errorRecord = [ordered]@{Stream='Error';Message=$message}
            $recordBytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $errorRecord -Depth 8 -Compress))
            if ($recordBytes.Length -le 65536 -and [int64]$streamState.Bytes + $recordBytes.Length -le 65536) { $streamLog.Add($errorRecord); $streamState.Bytes=[int]($streamState.Bytes + $recordBytes.Length) }
        }
        catch { }
    }
    try {
        $logDocument = [ordered]@{Schema='f2-acl-powershell-streams-v1';Complete=($streamLog.Count -eq 0 -and $childExit -in @(0,1));ExitCode=$childExit;Records=@($streamLog)}
        $logBytes = [Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $logDocument -Depth 12 -Compress -ErrorAction Stop))
        if ($logBytes.Length -gt 65536) { throw 'Captured PowerShell streams exceed the 64 KiB cap.' }
        [void](Write-F2AclWorkerStreamLog -OutputDirectory $OutputDirectory -CaptureId $CaptureId -Bytes $logBytes)
        [Console]::Out.WriteLine('F2ACL_STAGE:StreamPublished')
    }
    catch { $streamError=[regex]::Replace([string]$_.Exception.Message,'[\x00-\x08\x0B\x0C\x0E-\x1F]','?'); $streamError=[regex]::Replace($streamError,'(?i)\bS-\d-(?:\d+-?)+','[sid]'); $streamError=[regex]::Replace($streamError,'(?i)\b[A-Z]:\\[^\s;,)]+','[path]'); if($streamError.Length -gt 2048){$streamError=$streamError.Substring(0,2048)}; [Console]::Error.WriteLine('F2ACL_FATAL:StreamCaptureFailure:' + $streamError); $childExit=4; $streamState.ExitCode=4 }
    return [int]$childExit
}

if ($ElevatedCoordinator) {
    $coordinatorExit = Invoke-F2AclElevatedCoordinator -OwnerSid $RequesterSid
    exit $coordinatorExit
}

$summary = [ordered]@{Outcome='INCOMPLETE';ReviewedCommit=$null;CoordinatorProcessId=$null;ActualCoordinatorExitCode=$null;CoordinatorProcessState='NotStarted';ActualWorkerExitCode=$null;WorkingDirectory=$null;SourcePins=$null;Evidence=$null;Errors=@()}
$coordinator = $null; $pinnedSources = @()
try {
    Import-Module $protocolPath -Force -ErrorAction Stop
    if ($ExpectedCommitSha -notmatch '^[0-9a-f]{40}$') { throw 'Expected reviewed commit SHA is required.' }
    $requesterIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $requesterSid = [string]$requesterIdentity.User.Value
    $requesterIsAdministrator = [Security.Principal.WindowsPrincipal]::new($requesterIdentity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($requesterIsAdministrator) { throw 'Launch this entry point from a standard, non-elevated PowerShell session; it will request UAC once and verify the resulting Administrator token.' }
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
    $pinnedSources = @($pinnedScript,$pinnedModule,$pinnedIndex)
    $pinDocument = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($pinPath)) | ConvertFrom-Json -ErrorAction Stop
    if ($pinDocument.Schema -cne 'f2-acl-source-pins-v1' -or $pinDocument.ScriptSha256 -cne $pinnedScript.Sha256 -or $pinDocument.ModuleSha256 -cne $pinnedModule.Sha256) { throw 'Reviewed source pin manifest does not match the collector source.' }
    $summary.SourcePins = [ordered]@{ReviewedCommit=$actualCommit;ScriptSha256=$pinnedScript.Sha256;ModuleSha256=$pinnedModule.Sha256;PinManifestSha256=$pinnedIndex.Sha256}
    $captureId = [guid]::NewGuid().ToString('N')
    $summary.WorkingDirectory = Get-F2AclCoordinatorMailboxPath -CaptureId $captureId
    Test-F2AclEvidenceVolumeSeparateFromG -Path ([IO.Directory]::GetParent($summary.WorkingDirectory).FullName) | Out-Null
    $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $coordinatorCommand = '& ' + (ConvertTo-F2AclPowerShellLiteral $PSCommandPath) + ' -ElevatedCoordinator -CaptureId ' + (ConvertTo-F2AclPowerShellLiteral $captureId) + ' -RequesterSid ' + (ConvertTo-F2AclPowerShellLiteral $requesterSid) + ' -ExpectedCommitSha ' + (ConvertTo-F2AclPowerShellLiteral $actualCommit) + ' -ExpectedScriptSha256 ' + (ConvertTo-F2AclPowerShellLiteral $pinnedScript.Sha256) + ' -ExpectedModuleSha256 ' + (ConvertTo-F2AclPowerShellLiteral $pinnedModule.Sha256) + ' -WaitSeconds ' + $WaitSeconds
    $encodedCoordinatorCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($coordinatorCommand))
    $coordinatorArgs = @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-EncodedCommand',$encodedCoordinatorCommand)
    $coordinatorArgumentLine = (@($coordinatorArgs | ForEach-Object { ConvertTo-F2AclQuotedArgument ([string]$_) })) -join ' '
    try { $coordinator = Start-Process -FilePath $powerShellExe -Verb RunAs -ArgumentList $coordinatorArgumentLine -PassThru -ErrorAction Stop }
    catch {
        if ($_.Exception.NativeErrorCode -eq 1223 -or $_.Exception.Message -match 'cancel|canceled|cancelled') { throw 'UACElevationCancelled: approve elevation or credentials for an Administrator account; no live collection was started.' }
        throw ('UACCoordinatorStartFailed: ' + $_.Exception.Message)
    }
    $summary.CoordinatorProcessId = $coordinator.Id
    $summary.CoordinatorProcessState = 'Running'
    $outerWaitSeconds = $WaitSeconds + 60
    $processExited = $coordinator.WaitForExit([int]($outerWaitSeconds * 1000))
    if (-not $processExited) {
        $summary.CoordinatorProcessState = 'StillRunningAtTimeout'
        throw "Elevated coordinator exceeded ${outerWaitSeconds}s; it remains running because a standard-token parent will not attempt to terminate a high-integrity process. No COMPLETE evidence is accepted."
    }
    $summary.CoordinatorProcessState = 'Exited'
    $summary.ActualCoordinatorExitCode = [int]$coordinator.ExitCode
    [void](Test-F2AclCoordinatorMailboxDirectory -Path $summary.WorkingDirectory -RequesterSid $requesterSid)
    $statusPath = Join-Path $summary.WorkingDirectory 'coordinator-status.json'
    $statusBytes = Read-F2AclBoundedFile -Path $statusPath -MaxBytes 65536
    $status = [Text.Encoding]::UTF8.GetString($statusBytes) | ConvertFrom-Json -ErrorAction Stop
    $statusCheck = Test-F2AclCoordinatorStatus -Status $status -ActualProcessExitCode $summary.ActualCoordinatorExitCode -ExpectedRequesterSid $requesterSid
    $summary.ActualWorkerExitCode = $status.WorkerExitCode
    $summary.CoordinatorStatus = $status
    if (-not $statusCheck.Pass) { throw ('Coordinator status rejected: ' + ($statusCheck.Errors -join ';')) }
    if ($status.SourcePins.ReviewedCommit -cne $actualCommit -or $status.SourcePins.ScriptSha256 -cne $pinnedScript.Sha256 -or $status.SourcePins.ModuleSha256 -cne $pinnedModule.Sha256 -or $status.SourcePins.PinManifestSha256 -cne $pinnedIndex.Sha256) { throw 'Coordinator source pin report differs from parent-held reviewed pins.' }
    $package = Test-F2AclSavedEvidencePackage -EvidencePath $summary.WorkingDirectory -OwnerSid $requesterSid -CoordinatorExitCode $summary.ActualCoordinatorExitCode -ScriptSha256 $pinnedScript.Sha256 -ModuleSha256 $pinnedModule.Sha256 -WorkerDiagnosticFiles $status.WorkerDiagnosticFiles
    if ($status.PayloadSha256 -cne $package.PayloadSha256 -or $status.StreamsSha256 -cne $package.StreamsSha256) { throw 'Coordinator status digests differ from the saved evidence package.' }
    $summary.Evidence = $package
    $summary.Outcome = 'COMPLETE_READ_ONLY_ACL_BASELINE'
}
catch {
    $summary.Errors = @($summary.Errors) + @($_.Exception.Message)
    if ($null -ne $coordinator) {
        try {
            if ($coordinator.HasExited) { $summary.ActualCoordinatorExitCode = [int]$coordinator.ExitCode; $summary.CoordinatorProcessState = 'Exited' }
            else { $summary.CoordinatorProcessState = 'StillRunningAfterFailure' }
        }
        catch { $summary.Errors += @('CoordinatorProcessStatusUnavailable:' + $_.Exception.Message) }
    }
}
finally {
    if ($null -ne $coordinator) { $coordinator.Dispose() }
    foreach ($sourcePin in $pinnedSources) { if ($null -ne $sourcePin.Stream) { $sourcePin.Stream.Dispose() } }
}

$summary | ConvertTo-Json -Depth 12 -Compress
if ($summary.Outcome -ne 'COMPLETE_READ_ONLY_ACL_BASELINE') { exit 1 }
exit 0

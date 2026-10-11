Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2RuntimeVmId = '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1'
$script:F2RuntimeVmName = 'F2-G1-Isolated-Disposable'
$script:F2RuntimeDiskSerial = '152D20337A0C'
$script:F2RuntimeBaselineMailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:F2RuntimeBaselinePayloadCaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:F2RuntimePackageRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'F2-G1-Icacls'
$script:F2RuntimeReleasePath = Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'F2-G1-Icacls') 'approved-release.json'
$script:F2RuntimeDeadlineSeconds = 360
$script:F2RuntimeCoordinatorDeadlineSeconds = 300
$script:F2RuntimeChildTimeoutSeconds = 15

# Test hooks are private module state, never production command-line or environment overrides.
$script:F2RuntimeReleaseProvider = $null
$script:F2RuntimeObservationProvider = $null
$script:F2RuntimeNativeWorker = $null
$script:F2RuntimeUacStarter = $null
$script:F2RuntimeCurrentCommitProvider = $null
$script:F2RuntimeClockProvider = $null
$script:F2RuntimeRequestProvider = $null
$script:F2RuntimeRequestReader = $null
$script:F2RuntimeBaselineProvider = $null
$script:F2RuntimeMailboxCreator = $null
$script:F2RuntimeResultReader = $null
$script:F2RuntimePackageRootProvider = $null
$script:F2RuntimeTrustRootProvider = $null
$script:F2RuntimeIdentityProvider = $null
$script:F2RuntimeCoordinatorWaitProvider = $null
$script:F2RuntimeCaptureIdProvider = $null
$script:F2RuntimeRequesterSidProvider = $null

Import-Module (Join-Path $PSScriptRoot 'F2AclCapture.Protocol.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'F2AclIcacls.Corroboration.psm1') -Force -ErrorAction Stop

function Get-F2RuntimeSha256Bytes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    return Get-F2IcaclsSha256 -Bytes $Bytes
}

function Get-F2RuntimeCommitSha {
    if ($null -ne $script:F2RuntimeCurrentCommitProvider) { return [string](& $script:F2RuntimeCurrentCommitProvider) }
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $git = Get-Command 'git.exe' -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($git.Source)) { throw 'TrustedGitExecutableUnavailable.' }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $git.Source
    $start.Arguments = ('-C "' + $root + '" rev-parse HEAD')
    $start.WorkingDirectory = $root
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'GitCommitQueryStartFailed.' }
        if (-not $process.WaitForExit(5000)) { try { $process.Kill();[void]$process.WaitForExit(1000) } catch {}; throw 'GitCommitQueryTimedOut.' }
        $out = $process.StandardOutput.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0 -or $out -notmatch '^[0-9a-f]{40}$') { throw 'GitCommitQueryFailed.' }
        return $out
    } finally { $process.Dispose() }
}

function Get-F2RuntimeReleaseManifest {
    if ($null -ne $script:F2RuntimeReleaseProvider) { return & $script:F2RuntimeReleaseProvider }
    $file = Get-Item -LiteralPath $script:F2RuntimeReleasePath -Force -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $file.Length -lt 1 -or $file.Length -gt 65536) { throw 'ReleaseManifestTypeOrSizeInvalid.' }
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $manifest = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.Schema -cne 'f2-icacls-runtime-release-v1') { throw 'ReleaseManifestSchemaInvalid.' }
    return $manifest
}

function Get-F2RuntimePackageRoot {
    if ($null -ne $script:F2RuntimePackageRootProvider) { return [string](& $script:F2RuntimePackageRootProvider) }
    return $script:F2RuntimePackageRoot
}

function Test-F2RuntimeReleasePackage {
    param([Parameter(Mandatory)]$Manifest,[Parameter(Mandatory)][ValidateSet('Source','Installed')][string]$Mode)
    $expectedFiles = @(
        'F2AclCapture.Protocol.psm1',
        'F2AclIcacls.Corroboration.psm1',
        'F2AclIcacls.Runtime.psm1',
        'Invoke-F2IcaclsCapture.ps1',
        'Invoke-F2IcaclsProtectedCoordinator.ps1',
        'F2_ICACLS_SOURCE_PINS.json',
        'Invoke-F2AclReadOnlyCapture.ps1'
    )
    if ($Manifest.Schema -cne 'f2-icacls-runtime-release-v2' -or $Manifest.ReviewedCommitSha -notmatch '^[0-9a-f]{40}$' -or $Manifest.BaselineMailboxId -cne $script:F2RuntimeBaselineMailboxId -or $Manifest.BaselinePayloadCaptureId -cne $script:F2RuntimeBaselinePayloadCaptureId -or $Manifest.BaselinePayloadSha256 -notmatch '^[0-9a-f]{64}$' -or $Manifest.BaselineIntegritySha256 -notmatch '^[0-9a-f]{64}$') { throw 'ReleaseManifestIdentityOrBaselinePinInvalid.' }
    $pins = @($Manifest.Files)
    if ($pins.Count -ne $expectedFiles.Count -or @($pins.Name | Sort-Object -Unique).Count -ne $expectedFiles.Count -or @(Compare-Object ($expectedFiles | Sort-Object) ($pins.Name | Sort-Object) -CaseSensitive).Count -ne 0) { throw 'ReleaseManifestFileSetInvalid.' }
    $base = if ($Mode -eq 'Installed') { Join-Path (Get-F2RuntimePackageRoot) 'scripts\f2-acl' } else { $PSScriptRoot }
    foreach ($pin in $pins) {
        if ($pin.Sha256 -notmatch '^[0-9a-f]{64}$') { throw 'ReleaseManifestFilePinInvalid.' }
        $path = Join-Path $base $pin.Name
        $actual = Get-F2IcaclsFileSha256 -Path $path
        if (-not [string]::Equals($actual,[string]$pin.Sha256,[StringComparison]::OrdinalIgnoreCase)) { throw ('ReleasePackageHashMismatch:' + $pin.Name) }
    }
    if ($Mode -eq 'Source') {
        $actualCommit = Get-F2RuntimeCommitSha
        if ($actualCommit -cne $Manifest.ReviewedCommitSha) { throw 'ReviewedSourceCommitMismatch.' }
    }
    return [pscustomobject]@{Pass=$true;Mode=$Mode;CommitSha=[string]$Manifest.ReviewedCommitSha;Files=$pins.Count}
}

function Test-F2RuntimeTrustedDaclSddl {
    param([Parameter(Mandatory)][string]$Sddl,[Parameter(Mandatory)][hashtable]$ExpectedMasks,[Parameter(Mandatory)][int]$ExpectedAceFlags)
    $raw=[Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    if($raw.Owner.Value -ne 'S-1-5-32-544' -or $null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or @($raw.DiscretionaryAcl).Count -ne $ExpectedMasks.Count){throw 'TrustedDaclOwnerProtectionOrCountInvalid.'}
    $seen=@{}
    foreach($ace in @($raw.DiscretionaryAcl)){
        $sid=$ace.SecurityIdentifier.Value
        if(-not $ExpectedMasks.ContainsKey($sid) -or $seen.ContainsKey($sid) -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or [uint32]$ace.AccessMask -ne [uint32]$ExpectedMasks[$sid] -or [int]$ace.AceFlags -ne $ExpectedAceFlags){throw 'TrustedDaclAceInvalid.'}
        $seen[$sid]=$true
    }
    if($seen.Count -ne $ExpectedMasks.Count){throw 'TrustedDaclPrincipalSetInvalid.'}
    return $true
}

function Test-F2RuntimeInstalledTrustRoot {
    param([Parameter(Mandatory)][string]$PackageRoot,[Parameter(Mandatory)][string]$ManifestPath)
    if ($null -ne $script:F2RuntimeTrustRootProvider) { return [bool](& $script:F2RuntimeTrustRootProvider $PackageRoot $ManifestPath) }
    $packageScriptDir=Join-Path $PackageRoot 'scripts'
    $packageAclDir=Join-Path $packageScriptDir 'f2-acl'
    foreach ($path in @($PackageRoot,$packageScriptDir,$packageAclDir,$ManifestPath)) { Test-F2AclNoReparseAncestors -Path $path | Out-Null }
    foreach ($dir in @($PackageRoot,$packageScriptDir,$packageAclDir,(Split-Path -Parent $ManifestPath))) {
        $item = Get-Item -LiteralPath $dir -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'TrustedPackagePathIsReparsePoint.' }
        $expected=@{'S-1-5-18'=[uint32]0x001F01FF;'S-1-5-32-544'=[uint32]0x001F01FF;'S-1-5-11'=[uint32]0x001200A9}
        $expectedFlags=[int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
        Test-F2RuntimeTrustedDaclSddl -Sddl ([F2Acl.NativeDirectory]::GetSddl($dir)) -ExpectedMasks $expected -ExpectedAceFlags $expectedFlags | Out-Null
    }
    $manifestItem=Get-Item -LiteralPath $ManifestPath -Force -ErrorAction Stop
    if($manifestItem.PSIsContainer -or ($manifestItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $manifestItem.Length -gt 65536){throw 'TrustedReleaseManifestFileInvalid.'}
    $manifestExpected=@{'S-1-5-18'=[uint32]0x001F01FF;'S-1-5-32-544'=[uint32]0x001F01FF;'S-1-5-11'=[uint32]0x001200A9}
    Test-F2RuntimeTrustedDaclSddl -Sddl ([F2Acl.NativeDirectory]::GetSddl($ManifestPath)) -ExpectedMasks $manifestExpected -ExpectedAceFlags 0 | Out-Null
    return $true
}

function Get-F2RuntimeCoordinatorIdentity {
    if ($null -ne $script:F2RuntimeIdentityProvider) { return & $script:F2RuntimeIdentityProvider }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    return [pscustomobject]@{UserSid=[string]$identity.User.Value;IsAdministrator=[bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
}

function Test-F2RuntimeObservationsEquivalent {
    param([Parameter(Mandatory)]$Before,[Parameter(Mandatory)]$After)
    foreach($name in @('VmId','VmName','VmState','NicCount','GVolumeGuid','EvidenceVolumeGuid')) {
        if ([string]$Before.$name -cne [string]$After.$name) { return $false }
    }
    if (-not (Test-F2AclStorageObservationsEquivalent -Initial $Before.Storage -Final $After.Storage)) { return $false }
    $beforePaths=@($Before.PathChecks | Sort-Object Path)
    $afterPaths=@($After.PathChecks | Sort-Object Path)
    if($beforePaths.Count -ne 11 -or $afterPaths.Count -ne 11){return $false}
    for($i=0;$i -lt 11;$i++){
        foreach($name in @('Path','Exists','IsDirectory','ReparsePoint','ParentChainClear')){
            if([string]$beforePaths[$i].$name -cne [string]$afterPaths[$i].$name){return $false}
        }
    }
    foreach($name in @('Protected','OwnerSid','NoUnexpectedPrincipals','SeparateFromG')){
        if([string]$Before.EvidenceDirectory.$name -cne [string]$After.EvidenceDirectory.$name){return $false}
    }
    return $true
}

function Wait-F2RuntimeCoordinator {
    param([Parameter(Mandatory)]$Process,[Parameter(Mandatory)][int]$TimeoutSeconds)
    if($null -ne $script:F2RuntimeCoordinatorWaitProvider){return & $script:F2RuntimeCoordinatorWaitProvider $Process $TimeoutSeconds}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try{
        $queryFailed=$false
        while($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds){
            try{if($Process.HasExited){return [pscustomobject]@{Exited=$true;ExitCode=[int]$Process.ExitCode;CleanupComplete=$true;ProcessQueryFailed=$false}}}
            catch{$queryFailed=$true;break}
            Start-Sleep -Milliseconds 50
        }
        $cleanup=$false
        try{$Process.Kill();$cleanup=[bool]$Process.WaitForExit(1000)}catch{$cleanup=$false}
        return [pscustomobject]@{Exited=$false;ExitCode=if($cleanup){try{[int]$Process.ExitCode}catch{$null}}else{$null};CleanupComplete=$cleanup;ProcessQueryFailed=$queryFailed}
    }finally{$clock.Stop()}
}

function Get-F2RuntimeRequesterSid {
    if($null -ne $script:F2RuntimeRequesterSidProvider){return [string](& $script:F2RuntimeRequesterSidProvider)}
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if ($null -eq $identity.User) { throw 'RequesterSidUnavailable.' }
    return $identity.User.Value
}

function Get-F2RuntimeCaptureId {
    if($null -ne $script:F2RuntimeCaptureIdProvider){return [string](& $script:F2RuntimeCaptureIdProvider)}
    return [guid]::NewGuid().ToString('N')
}

function New-F2RuntimeRequest {
    param([Parameter(Mandatory)][string]$CaptureId,[Parameter(Mandatory)][string]$RequesterSid)
    if($null -ne $script:F2RuntimeRequestProvider){return & $script:F2RuntimeRequestProvider $CaptureId $RequesterSid}
    $root = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([string]::IsNullOrWhiteSpace($root)) { throw 'CommonApplicationDataUnavailable.' }
    $path = Join-Path $root ('F2-G1-ACL-Request-' + $CaptureId)
    $path = New-F2AclRestrictedDirectory -Path $path -OwnerSid $RequesterSid -ProjectVolumePath 'G:\'
    $request = [ordered]@{Schema='f2-icacls-request-v1';CaptureId=$CaptureId;CreatedUtc=[DateTime]::UtcNow.ToString('o');RequesterSid=$RequesterSid;Intent='F2G1_READ_ONLY_ICACLS_CORROBORATION'}
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($request | ConvertTo-Json -Compress -Depth 4))
    [void](Write-F2AclAtomicCreateNewFile -Path (Join-Path $path 'request.json') -Bytes $bytes -MaxBytes 8192)
    return [pscustomobject]@{Path=$path;Sha256=(Get-F2RuntimeSha256Bytes -Bytes $bytes)}
}

function Read-F2RuntimeRequest {
    param([Parameter(Mandatory)][string]$CaptureId)
    if($null -ne $script:F2RuntimeRequestReader){return & $script:F2RuntimeRequestReader $CaptureId}
    $root = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    $path = Join-Path $root ('F2-G1-ACL-Request-' + $CaptureId)
    Test-F2AclNoReparseAncestors -Path $path | Out-Null
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'RequestDirectoryTypeInvalid.' }
    $sddl = [F2Acl.NativeDirectory]::GetSddl($path)
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
    $requesterSid = $raw.Owner.Value
    [void](Test-F2AclRestrictedDirectory -Path $path -OwnerSid $requesterSid)
    $requestPath = Join-Path $path 'request.json'
    $requestItem = Get-Item -LiteralPath $requestPath -Force -ErrorAction Stop
    if ($requestItem.PSIsContainer -or ($requestItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $requestItem.Length -lt 1 -or $requestItem.Length -gt 8192) { throw 'RequestRecordTypeOrSizeInvalid.' }
    $stream = [IO.File]::Open($requestPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try {
        $bytes = New-Object byte[] ([int]$stream.Length)
        $read = $stream.Read($bytes,0,$bytes.Length)
        if ($read -ne $bytes.Length) { throw 'RequestRecordShortRead.' }
    } finally { $stream.Dispose() }
    $request = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json -ErrorAction Stop
    if ($request.Schema -cne 'f2-icacls-request-v1' -or $request.CaptureId -cne $CaptureId -or $request.RequesterSid -cne $requesterSid -or $request.Intent -cne 'F2G1_READ_ONLY_ICACLS_CORROBORATION') { throw 'RequestRecordIdentityInvalid.' }
    return [pscustomobject]@{CaptureId=$CaptureId;RequesterSid=$requesterSid;Path=$path;RequestSha256=(Get-F2RuntimeSha256Bytes -Bytes $bytes)}
}

function Get-F2RuntimeStorageObservation {
    $serial = $script:F2RuntimeDiskSerial
    $serialKey = { param($v) if ($null -eq $v) { '' } else { ($v -replace '\s','').ToUpperInvariant() } }
    $wMatches = @(Get-CimInstance Win32_DiskDrive -ErrorAction Stop | Where-Object { (& $serialKey ([string]$_.SerialNumber)) -eq $serial })
    $dMatches = @(Get-Disk -ErrorAction Stop | Where-Object { (& $serialKey ([string]$_.SerialNumber)) -eq $serial })
    $pMatches = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { (& $serialKey ([string]$_.SerialNumber)) -eq $serial })
    if ($wMatches.Count -ne 1 -or $dMatches.Count -ne 1 -or $pMatches.Count -ne 1) { throw 'KingstonSerialNotUniqueAcrossInterfaces.' }
    $w=$wMatches[0];$d=$dMatches[0];$p=$pMatches[0]
    $parts=@(Get-Partition -DriveLetter G -ErrorAction Stop);$vol=Get-Volume -DriveLetter G -ErrorAction Stop
    $drive=[string]$vol.DriveLetter + ':'
    $volumeGuid=[string][F2Acl.NativeDirectory]::GetVolumeGuidForPath('G:\')
    return [pscustomobject]@{
        Win32MatchCount=$wMatches.Count;DiskMatchCount=$dMatches.Count;PhysicalMatchCount=$pMatches.Count
        Win32Serial=[string]$w.SerialNumber;DiskSerial=[string]$d.SerialNumber;PhysicalSerial=[string]$p.SerialNumber
        Win32Model=[string]$w.Model;DiskFriendlyName=[string]$d.FriendlyName;DiskModel=[string]$d.Model
        BusType=$d.BusType.ToString();DiskHealth=$d.HealthStatus.ToString();DiskOperationalStatus=@($d.OperationalStatus|ForEach-Object{$_.ToString()});PhysicalHealth=$p.HealthStatus.ToString()
        GPartitionCount=$parts.Count;PartitionDiskNumber=if($parts.Count -eq 1){[int]$parts[0].DiskNumber}else{$null};DiskNumber=[int]$d.Number;Win32Index=[int]$w.Index
        GDriveLetter=$drive;VolumeFileSystem=[string]$vol.FileSystem;VolumeHealth=$vol.HealthStatus.ToString();GVolumeGuid=$volumeGuid
    }
}

function Get-F2RuntimeLiveObservation {
    param([Parameter(Mandatory)][string]$EvidencePath,[Parameter(Mandatory)][string]$RequesterSid,[Parameter(Mandatory)][string]$CaptureId)
    if ($null -ne $script:F2RuntimeObservationProvider) { return & $script:F2RuntimeObservationProvider $EvidencePath $RequesterSid $CaptureId }
    $systemPowerShellModules=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\Modules'
    $hyperVManifest=Join-Path $systemPowerShellModules 'Hyper-V\Hyper-V.psd1'
    $storageManifest=Join-Path $systemPowerShellModules 'Storage\Storage.psd1'
    if(-not (Test-Path -LiteralPath $hyperVManifest -PathType Leaf) -or -not (Test-Path -LiteralPath $storageManifest -PathType Leaf)){throw 'TrustedWindowsManagementModulesUnavailable.'}
    Import-Module -Name $hyperVManifest -Force -ErrorAction Stop
    Import-Module -Name $storageManifest -Force -ErrorAction Stop
    $vmMatches=@(Get-VM -Id ([guid]$script:F2RuntimeVmId) -ErrorAction Stop)
    if ($vmMatches.Count -ne 1) { throw 'ImmutableVmIdNotUnique.' }
    $vm=$vmMatches[0]
    $config=[IO.Path]::GetFullPath([string]$vm.ConfigurationLocation)
    $checkpoints=[IO.Path]::GetFullPath([string]$vm.SnapshotFileLocation)
    $paging=[IO.Path]::GetFullPath([string]$vm.SmartPagingFilePath)
    $vhds=@(Get-VMHardDiskDrive -VM $vm -ErrorAction Stop|ForEach-Object{[IO.Path]::GetFullPath([string]$_.Path)})
    $nics=@(Get-VMNetworkAdapter -VM $vm -ErrorAction Stop)
    $expectedConfig=[IO.Path]::GetFullPath((Join-Path 'G:\F2-G1-Isolated-Disposable' $script:F2RuntimeVmName))
    $expectedVhds=@([IO.Path]::GetFullPath('G:\F2-G1-Isolated-Disposable\F2-G1-OS.vhdx'),[IO.Path]::GetFullPath('G:\F2-G1-Isolated-Disposable\F2-G1-Scratch.vhdx'))
    $vmValidation=Test-F2AclVmStorageSnapshot -VmId $vm.Id.ToString() -VmName $vm.Name -VmState $vm.State.ToString() -ExpectedVmId $script:F2RuntimeVmId -ExpectedVmName $script:F2RuntimeVmName -ExpectedConfiguration $expectedConfig -ExpectedCheckpoints 'G:\F2-G1-Isolated-Disposable' -ExpectedSmartPaging 'G:\F2-G1-Isolated-Disposable' -ExpectedVhdPaths $expectedVhds -Configuration $config -Checkpoints $checkpoints -SmartPaging $paging -VhdPaths $vhds -NicCount $nics.Count
    if (-not $vmValidation.Pass) { throw 'ImmutableVmOffZeroNicOrStoragePathGateFailed.' }
    $targets=@(Get-F2IcaclsExpectedPaths)
    $pathChecks=foreach($path in $targets){
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        Test-F2AclNoReparseAncestors -Path $path | Out-Null
        [pscustomobject]@{Path=$item.FullName;Exists=$true;IsDirectory=[bool]$item.PSIsContainer;ReparsePoint=(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0);ParentChainClear=$true}
    }
    $storage=Get-F2RuntimeStorageObservation
    $evidenceGuid=[string][F2Acl.NativeDirectory]::GetVolumeGuidForPath($EvidencePath)
    $mailbox=Test-F2IcaclsMailboxEvidenceDirectory -Path $EvidencePath -CaptureId $CaptureId -RequesterSid $RequesterSid
    return [pscustomobject]@{
        VmId=$vm.Id.ToString().ToLowerInvariant();VmName=$vm.Name;VmState=$vm.State.ToString();NicCount=$nics.Count
        Storage=$storage;GVolumeGuid=$storage.GVolumeGuid;EvidenceVolumeGuid=$evidenceGuid
        PathChecks=@($pathChecks);EvidenceDirectory=[pscustomobject]@{Protected=$mailbox.Protected;OwnerSid=$mailbox.OwnerSid;NoUnexpectedPrincipals=($mailbox.AceCount-eq 4);SeparateFromG=(-not [string]::Equals($storage.GVolumeGuid.TrimEnd('\'),$evidenceGuid.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase))}
    }
}

function Get-F2RuntimeBaseline {
    param([Parameter(Mandatory)]$Manifest,[Parameter(Mandatory)][string]$RequesterSid)
    if($null -ne $script:F2RuntimeBaselineProvider){return & $script:F2RuntimeBaselineProvider $Manifest $RequesterSid}
    $directory=Get-F2AclCoordinatorMailboxPath -CaptureId $script:F2RuntimeBaselineMailboxId
    $loaded=Read-F2IcaclsBaselineEvidence -EvidenceDirectory $directory -ExpectedMailboxId $Manifest.BaselineMailboxId -ExpectedPayloadCaptureId $Manifest.BaselinePayloadCaptureId -ExpectedRequesterSid $RequesterSid
    if (-not $loaded.Pass -or $loaded.PayloadSha256 -cne $Manifest.BaselinePayloadSha256 -or $loaded.IntegritySha256 -cne $Manifest.BaselineIntegritySha256) { throw 'PinnedBaselineEvidenceUnavailableOrChanged.' }
    return $loaded
}

function Write-F2RuntimeMailboxStatus {
    param([Parameter(Mandatory)][string]$MailboxPath,[Parameter(Mandatory)]$Status)
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($Status | ConvertTo-Json -Depth 10 -Compress))
    if ($bytes.Length -gt 65536) { throw 'RuntimeStatusExceedsLimit.' }
    Write-F2AclAtomicCreateNewFile -Path (Join-Path $MailboxPath 'coordinator-status.json') -Bytes $bytes -MaxBytes 65536
    return Get-F2RuntimeSha256Bytes -Bytes $bytes
}

function Read-F2RuntimeMailboxResult {
    param([Parameter(Mandatory)][string]$CaptureId,[Parameter(Mandatory)][string]$RequesterSid,[Parameter(Mandatory)]$Manifest,[Parameter(Mandatory)]$Baseline)
    if($null -ne $script:F2RuntimeResultReader){return & $script:F2RuntimeResultReader $CaptureId $RequesterSid $Manifest $Baseline}
    $path=Get-F2IcaclsExpectedMailboxPath -CaptureId $CaptureId
    [void](Test-F2IcaclsMailboxEvidenceDirectory -Path $path -CaptureId $CaptureId -RequesterSid $RequesterSid)
    $statusPath=Join-Path $path 'coordinator-status.json'
        $statusBytes=Read-F2AclBoundedFile -Path $statusPath -MaxBytes 65536
    $status=[Text.Encoding]::UTF8.GetString($statusBytes)|ConvertFrom-Json -ErrorAction Stop
    if($status.Schema -cne 'f2-icacls-runtime-status-v1' -or $status.CaptureId -cne $CaptureId -or $status.RequesterSid -cne $RequesterSid){throw 'CoordinatorStatusIdentityInvalid.'}
    $identity=Test-F2AclElevatedIdentityPair -RequesterSid $RequesterSid -CoordinatorSid ([string]$status.CoordinatorSid) -CoordinatorIsAdministrator ($status.CoordinatorAdministratorVerified -eq $true)
    if(-not $identity.Pass){throw 'CoordinatorStatusTrustOrIdentityInvalid.'}
    if($status.PackageComplete -eq $true -and ($status.SourcePinsManifestSha256 -cne $Manifest.SourcePinsManifestSha256 -or $status.BaselinePayloadSha256 -cne $Manifest.BaselinePayloadSha256 -or $status.BaselineIntegritySha256 -cne $Manifest.BaselineIntegritySha256)){throw 'CoordinatorStatusPinMismatch.'}
    if($status.PackageComplete -ne $true -and ($status.Outcome -cne 'INCOMPLETE' -or $status.CoordinatorExitCode -ne 1)){throw 'CoordinatorFailureStatusInvalid.'}
    if($status.PackageComplete -eq $true -and ($status.Outcome -cne 'COMPLETE_ICACLS_CORROBORATION' -or $status.CoordinatorExitCode -ne 0 -or $status.PreflightPass -ne $true -or $status.PostflightPass -ne $true -or $status.ExecutionMode -cne 'ONE_UAC_COORDINATOR_ALL_11' -or $status.TargetCount -ne 11 -or $status.RunCount -ne 11 -or $status.ComparisonCount -ne 11 -or [long]$status.ElapsedMilliseconds -gt ($script:F2RuntimeCoordinatorDeadlineSeconds*1000))){throw 'CoordinatorCompletionStatusInvalid.'}
    $comparisons=@()
    if($status.PackageComplete -eq $true){
        $integrityPath=Join-Path $path 'integrity.json';$integrityBytes=Read-F2AclBoundedFile -Path $integrityPath -MaxBytes 524288
        $integrity=[Text.Encoding]::UTF8.GetString($integrityBytes)|ConvertFrom-Json -ErrorAction Stop
        $projectGuid=[string]$integrity.ProjectVolumeGuid;$evidenceGuid=[string]$integrity.EvidenceVolumeGuid
        if($integrity.Complete -ne $true -or $integrity.AllCommandsSuccessful -ne $true -or $integrity.OwnerSid -cne $RequesterSid -or $integrity.TargetCount -ne 11 -or $integrity.RunCount -ne 11 -or $integrity.ComparisonCount -ne 11 -or $integrity.Results.Count -ne 11 -or $projectGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $evidenceGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $projectGuid.TrimEnd('\') -ieq $evidenceGuid.TrimEnd('\') -or $projectGuid -cne $Baseline.Integrity.ProjectVolumeGuid -or $evidenceGuid -cne $Baseline.Integrity.EvidenceVolumeGuid){throw 'CoordinatorEvidenceCompletenessInvalid.'}
        $targets=@(Get-F2IcaclsExpectedPaths)
        $expectedResultNames=@(1..11|ForEach-Object{'icacls-{0:D2}.json' -f $_})
        foreach($entry in @($integrity.Results)){
            if([string]$entry.Name -notin $expectedResultNames -or [string]$entry.Path -notin $targets -or $null -eq $entry.Bytes -or [long]$entry.Bytes -lt 1 -or [string]$entry.Sha256 -notmatch '^[0-9a-f]{64}$'){throw 'CoordinatorEvidenceEntryInvalid.'}
            $fileBytes=Read-F2AclBoundedFile -Path (Join-Path $path ([string]$entry.Name)) -MaxBytes 524288
            if($fileBytes.Length -ne $entry.Bytes -or (Get-F2RuntimeSha256Bytes -Bytes $fileBytes) -cne $entry.Sha256){throw 'CoordinatorEvidenceFileDigestMismatch.'}
            $run=[Text.Encoding]::UTF8.GetString($fileBytes)|ConvertFrom-Json -ErrorAction Stop
            $native=$run.Result
            $startTime=[DateTime]::MinValue
            if([string]$run.Path -cne [string]$entry.Path -or [string]$run.Mode -cne 'ElevatedCoordinator' -or [string]$native.Path -cne [string]$entry.Path -or [string]$run.Command -cne 'icacls.exe "<approved-path>"' -or [string]$native.Command -cne [string]$run.Command -or $native.ExitCode -ne 0 -or $native.OutputComplete -ne $true -or $native.CleanupComplete -ne $true -or $native.TimedOut -ne $false -or $native.Truncated -ne $false -or $null -ne $native.ReaderError -or [long]$native.ProcessId -le 0 -or -not [DateTime]::TryParse([string]$native.ProcessStartUtc,[ref]$startTime)){throw 'CoordinatorEvidenceRunInvalid.'}
            $stdoutBytes=[Text.Encoding]::UTF8.GetBytes([string]$native.Stdout);$stderrBytes=[Text.Encoding]::UTF8.GetBytes([string]$native.Stderr)
            if($native.StdoutBytes -ne $stdoutBytes.Length -or $native.StderrBytes -ne $stderrBytes.Length -or $native.StdoutBytes -gt 262144 -or $native.StderrBytes -gt 262144 -or (Get-F2RuntimeSha256Bytes -Bytes $stdoutBytes) -cne [string]$native.StdoutSha256 -or (Get-F2RuntimeSha256Bytes -Bytes $stderrBytes) -cne [string]$native.StderrSha256){throw 'CoordinatorEvidenceStreamIntegrityInvalid.'}
        }
        $resultPaths=@($integrity.Results|ForEach-Object{[string]$_.Path})
        if(@($integrity.Results.Name|Sort-Object -Unique).Count -ne 11 -or @(Compare-Object ($expectedResultNames|Sort-Object) ($integrity.Results.Name|Sort-Object) -CaseSensitive).Count -ne 0){throw 'CoordinatorEvidenceFileSetInvalid.'}
        $comparisons=@($integrity.Comparisons)
        $comparisonPaths=@($comparisons|ForEach-Object{[string]$_.Path})
        if(@($resultPaths|Sort-Object -Unique).Count -ne 11 -or @(Compare-Object ($targets|Sort-Object) ($resultPaths|Sort-Object) -CaseSensitive).Count -ne 0 -or @(Compare-Object ($targets|Sort-Object) ($comparisonPaths|Sort-Object) -CaseSensitive).Count -ne 0){throw 'CoordinatorEvidencePathSetInvalid.'}
        if($comparisons.Count -ne 11 -or @($comparisons|Where-Object{[string]$_.Classification -notin @('PASS','MISMATCH','INDETERMINATE')}).Count -ne 0){throw 'CoordinatorComparisonCountInvalid.'}
        $manifestHash=Get-F2RuntimeSha256Bytes -Bytes $integrityBytes
        if($status.PackageIntegritySha256 -cne $manifestHash){throw 'CoordinatorManifestHashMismatch.'}
        $status | Add-Member -NotePropertyName ManifestSha256 -NotePropertyValue $manifestHash -Force
    }
    return [pscustomobject]@{Status=$status;Comparisons=$comparisons;EvidencePath=$path;StatusSha256=(Get-F2RuntimeSha256Bytes -Bytes $statusBytes)}
}

function Invoke-F2IcaclsCaptureLauncher {
    [CmdletBinding()]
    param()
    $captureId=Get-F2RuntimeCaptureId;$requesterSid=Get-F2RuntimeRequesterSid;$uacAttempted=$false;$launch=$null
    try {
        if($null -eq $script:F2RuntimeReleaseProvider){Test-F2RuntimeInstalledTrustRoot -PackageRoot $script:F2RuntimePackageRoot -ManifestPath $script:F2RuntimeReleasePath|Out-Null}
        $manifest=Get-F2RuntimeReleaseManifest
        [void](Test-F2RuntimeReleasePackage -Manifest $manifest -Mode Source)
        $baseline=Get-F2RuntimeBaseline -Manifest $manifest -RequesterSid $requesterSid
        $request=New-F2RuntimeRequest -CaptureId $captureId -RequesterSid $requesterSid
        $uacAttempted=$true
        if($null -ne $script:F2RuntimeUacStarter){$launch=& $script:F2RuntimeUacStarter $captureId $script:F2RuntimeDeadlineSeconds}
        else {
            $coordinator=Join-Path (Join-Path (Get-F2RuntimePackageRoot) 'scripts\f2-acl') 'Invoke-F2IcaclsProtectedCoordinator.ps1'
            $ps=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
            $arg='-NoProfile -NonInteractive -File "'+$coordinator+'" -CaptureId '+$captureId
            $launch=Start-Process -FilePath $ps -ArgumentList $arg -WorkingDirectory (Get-F2RuntimePackageRoot) -Verb RunAs -PassThru -ErrorAction Stop
        }
        if($null -eq $launch){throw 'UacCoordinatorNotStarted.'}
        $startUtc=$null
        try{$startUtc=$launch.StartTime.ToUniversalTime()}catch{}
        $wait=Wait-F2RuntimeCoordinator -Process $launch -TimeoutSeconds $script:F2RuntimeDeadlineSeconds
        if(-not $wait.Exited){$reason=if($wait.ProcessQueryFailed){'CoordinatorProcessQueryFailed'}else{'CoordinatorDeadlineExceeded'};$coordinatorPid=$null;try{$coordinatorPid=[int]$launch.Id}catch{};$startText=if($null -ne $startUtc){$startUtc.ToString('o')}else{$null};return [pscustomobject]@{Success=$false;Outcome=$reason;CaptureId=$captureId;CoordinatorPid=$coordinatorPid;CoordinatorStartUtc=$startText;ActualCoordinatorExitCode=$wait.ExitCode;CoordinatorCleanupComplete=$wait.CleanupComplete;ElevationLaunches=1;Errors=@($reason+';NoRetry')} }
        $result=Read-F2RuntimeMailboxResult -CaptureId $captureId -RequesterSid $requesterSid -Manifest $manifest -Baseline $baseline
        $success=($wait.ExitCode -eq 0 -and $result.Status.Outcome -eq 'COMPLETE_ICACLS_CORROBORATION' -and $result.Status.PackageComplete -eq $true)
        $coordinatorPid=$null;try{$coordinatorPid=[int]$launch.Id}catch{};$startText=if($null -ne $startUtc){$startUtc.ToString('o')}else{$null}
        return [pscustomobject]@{Success=$success;Outcome=[string]$result.Status.Outcome;CaptureId=$captureId;CoordinatorPid=$coordinatorPid;CoordinatorStartUtc=$startText;ActualCoordinatorExitCode=[int]$wait.ExitCode;CoordinatorCleanupComplete=$wait.CleanupComplete;ElevationLaunches=1;EvidencePath=$result.EvidencePath;StatusSha256=$result.StatusSha256;ManifestSha256=$result.Status.ManifestSha256;Comparisons=$result.Comparisons;Errors=@($result.Status.Errors)}
    } catch {
        $code=$null
        if($_.Exception -is [System.ComponentModel.Win32Exception]){$code=[int]$_.Exception.NativeErrorCode}
        elseif($_.Exception.HResult -band 0xFFFF){$code=[int]($_.Exception.HResult -band 0xFFFF)}
        $outcome=if($code -eq 1223){'UAC_CANCELLED'}else{'LAUNCHER_PREFLIGHT_OR_COORDINATOR_FAILURE'}
        return [pscustomobject]@{Success=$false;Outcome=$outcome;CaptureId=$captureId;RequesterSid=$requesterSid;ActualCoordinatorExitCode=$null;ElevationLaunches=if($uacAttempted){1}else{0};Errors=@($outcome)}
    }
}

function Invoke-F2IcaclsProtectedCoordinator {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$CaptureId)
    $request=$null;$manifest=$null;$mailboxPath=$null;$stage='PackageValidation';$runs=@();$comparisons=@();$status=$null;$coordinatorClock=[Diagnostics.Stopwatch]::StartNew()
    try {
        $packageRoot=Get-F2RuntimePackageRoot
        $releasePath=if($null -ne $script:F2RuntimeReleaseProvider){'C:\ProgramData\F2-G1-Icacls\approved-release.json'}else{$script:F2RuntimeReleasePath}
        Test-F2RuntimeInstalledTrustRoot -PackageRoot $packageRoot -ManifestPath $releasePath | Out-Null
        $manifest=Get-F2RuntimeReleaseManifest
        [void](Test-F2RuntimeReleasePackage -Manifest $manifest -Mode Installed)
        $token=Get-F2RuntimeCoordinatorIdentity
        if(-not $token.IsAdministrator -or [string]$token.UserSid -notmatch '^S-1-'){throw 'CoordinatorTokenNotAdministrator.'}
        $request=Read-F2RuntimeRequest -CaptureId $CaptureId
        $pair=Test-F2AclElevatedIdentityPair -RequesterSid $request.RequesterSid -CoordinatorSid $token.UserSid -CoordinatorIsAdministrator $true
        if(-not $pair.Pass){throw 'CoordinatorIdentityPairRejected.'}
        if($null -ne $script:F2RuntimeMailboxCreator){$mailboxPath=[string](& $script:F2RuntimeMailboxCreator $CaptureId $request.RequesterSid)}
        else{$mailboxPath=New-F2AclCoordinatorMailboxDirectory -CaptureId $CaptureId -RequesterSid $request.RequesterSid | ForEach-Object { [string]$_.Path }}
        if([string]::IsNullOrWhiteSpace($mailboxPath)){$mailboxPath=Get-F2AclCoordinatorMailboxPath -CaptureId $CaptureId}
        $baseline=Get-F2RuntimeBaseline -Manifest $manifest -RequesterSid $request.RequesterSid
        $stage='Preflight'
        $observation=Get-F2RuntimeLiveObservation -EvidencePath $mailboxPath -RequesterSid $request.RequesterSid -CaptureId $CaptureId
        $pins=[IO.File]::ReadAllBytes((Join-Path (Join-Path $packageRoot 'scripts\f2-acl') 'F2_ICACLS_SOURCE_PINS.json'))
        $pinsHash=Get-F2RuntimeSha256Bytes -Bytes $pins
        if($pinsHash -cne $manifest.SourcePinsManifestSha256){throw 'SourcePinManifestHashMismatch.'}
        $root=Join-Path $packageRoot 'scripts\f2-acl'
        $launcherPin=[string](@($manifest.Files|Where-Object{$_.Name -eq 'Invoke-F2IcaclsCapture.ps1'})[0].Sha256)
        $protocolPin=[string](@($manifest.Files|Where-Object{$_.Name -eq 'F2AclCapture.Protocol.psm1'})[0].Sha256)
        if([string]::IsNullOrWhiteSpace($launcherPin) -or [string]::IsNullOrWhiteSpace($protocolPin)){throw 'RequiredRuntimePinsMissing.'}
        $preflight=Test-F2IcaclsPreflight -Baseline $baseline.Baseline -Integrity $baseline.Integrity -Observation $observation -BaselineSha256 $baseline.PayloadSha256 -ExpectedBaselineSha256 $manifest.BaselinePayloadSha256 -ExpectedScriptSha256 $launcherPin -ActualScriptSha256 (Get-F2IcaclsFileSha256 -Path (Join-Path $root 'Invoke-F2IcaclsCapture.ps1')) -ExpectedModuleSha256 $protocolPin -ActualModuleSha256 (Get-F2IcaclsFileSha256 -Path (Join-Path $root 'F2AclCapture.Protocol.psm1'))
        if(-not $preflight.Pass){throw ('ReadOnlyPreflightFailed:' + ($preflight.Errors -join ','))}
        $stage='IcaclsReads'
        $targets=@(Get-F2IcaclsExpectedPaths)
        foreach($target in $targets){
            if($coordinatorClock.Elapsed.TotalSeconds -ge $script:F2RuntimeCoordinatorDeadlineSeconds){throw 'CoordinatorAbsoluteDeadlineExceeded.'}
            if($null -ne $script:F2RuntimeNativeWorker){$native=& $script:F2RuntimeNativeWorker $target $script:F2RuntimeChildTimeoutSeconds}
            else {$native=Invoke-F2IcaclsObject -Target $target -TimeoutSeconds $script:F2RuntimeChildTimeoutSeconds}
            $run=[pscustomobject]@{Path=$target;Mode='ElevatedCoordinator';Command=[string]$native.Command;ProcessId=$native.ProcessId;ProcessStartUtc=$native.ProcessStartUtc;ExitCode=$native.ExitCode;TimedOut=$native.TimedOut;CleanupComplete=$native.CleanupComplete;OutputComplete=$native.OutputComplete;Truncated=$native.Truncated;Stdout=$native.Stdout;Stderr=$native.Stderr;StdoutBytes=$native.StdoutBytes;StderrBytes=$native.StderrBytes;StdoutSha256=$native.StdoutSha256;StderrSha256=$native.StderrSha256;ElapsedMilliseconds=$native.ElapsedMilliseconds;ReaderError=$native.ReaderError;Result=$native}
            $runs+=@($run)
            if($native.ExitCode -ne 0 -or $native.TimedOut -or -not $native.CleanupComplete -or -not $native.OutputComplete -or $native.Truncated){throw 'IcaclsCommandIncompleteOrFailed.'}
            $parsed=ConvertFrom-F2IcaclsText -Text ([string]$native.Stdout) -ExpectedPath $target
            $baseRecord=@($baseline.Baseline.Records|Where-Object{[string]::Equals([string]$_.Path,$target,[StringComparison]::OrdinalIgnoreCase)})
            if($baseRecord.Count -ne 1){throw 'BaselineRecordMissingOrDuplicated.'}
            $comparison=Get-F2IcaclsComparison -BaselineRecord $baseRecord[0] -CommandResult $native
            $comparisons+=@($comparison)
            $run | Add-Member -NotePropertyName Parsed -NotePropertyValue $parsed
            $run | Add-Member -NotePropertyName Comparison -NotePropertyValue $comparison
            if($coordinatorClock.Elapsed.TotalSeconds -ge $script:F2RuntimeCoordinatorDeadlineSeconds){throw 'CoordinatorAbsoluteDeadlineExceeded.'}
        }
        if($runs.Count -ne 11 -or $comparisons.Count -ne 11){throw 'IcaclsTargetCountMismatch.'}
        $stage='Postflight'
        $post=Get-F2RuntimeLiveObservation -EvidencePath $mailboxPath -RequesterSid $request.RequesterSid -CaptureId $CaptureId
        $postCheck=Test-F2IcaclsPreflight -Baseline $baseline.Baseline -Integrity $baseline.Integrity -Observation $post -BaselineSha256 $baseline.PayloadSha256 -ExpectedBaselineSha256 $manifest.BaselinePayloadSha256 -ExpectedScriptSha256 $launcherPin -ActualScriptSha256 (Get-F2IcaclsFileSha256 -Path (Join-Path $root 'Invoke-F2IcaclsCapture.ps1')) -ExpectedModuleSha256 $protocolPin -ActualModuleSha256 (Get-F2IcaclsFileSha256 -Path (Join-Path $root 'F2AclCapture.Protocol.psm1'))
        if(-not $postCheck.Pass){throw 'ReadOnlyPostflightFailed.'}
        if(-not (Test-F2RuntimeObservationsEquivalent -Before $observation -After $post)){throw 'HostObservationChangedDuringCollection.'}
        $stage='EvidencePublication'
        $projectGuid=[string]$baseline.Integrity.ProjectVolumeGuid;$evidenceGuid=[string]$baseline.Integrity.EvidenceVolumeGuid
        $package=Write-F2IcaclsEvidencePackage -Directory $mailboxPath -OwnerSid $request.RequesterSid -MailboxCaptureId $CaptureId -MailboxRequesterSid $request.RequesterSid -Targets $targets -Runs $runs -Comparisons $comparisons -ProjectVolumePath 'G:\' -ProjectVolumeGuid $projectGuid -EvidenceVolumeGuid $evidenceGuid
        if(-not $package.Complete -or $coordinatorClock.Elapsed.TotalSeconds -ge $script:F2RuntimeCoordinatorDeadlineSeconds){throw 'EvidencePackageIncompleteOrDeadlineExceeded.'}
        $status=[ordered]@{Schema='f2-icacls-runtime-status-v1';Outcome='COMPLETE_ICACLS_CORROBORATION';CaptureId=$CaptureId;RequesterSid=$request.RequesterSid;CoordinatorSid=$token.UserSid;CoordinatorAdministratorVerified=$true;ExecutionMode='ONE_UAC_COORDINATOR_ALL_11';PreflightPass=$true;PostflightPass=$true;PackageComplete=$package.Complete;PackageIntegritySha256=$package.IntegritySha256;SourcePinsManifestSha256=$manifest.SourcePinsManifestSha256;BaselinePayloadSha256=$manifest.BaselinePayloadSha256;BaselineIntegritySha256=$manifest.BaselineIntegritySha256;TargetCount=$targets.Count;RunCount=$runs.Count;ComparisonCount=$comparisons.Count;CoordinatorExitCode=0;ElapsedMilliseconds=[long]$coordinatorClock.ElapsedMilliseconds;Errors=@();CreatedUtc=[DateTime]::UtcNow.ToString('o')}
        [void](Write-F2RuntimeMailboxStatus -MailboxPath $mailboxPath -Status $status)
        return [pscustomobject]@{Success=$true;Outcome=$status.Outcome;CaptureId=$CaptureId;TargetCount=11;RunCount=11;MailboxPath=$mailboxPath;ExitCode=0}
    } catch {
        $safe='CoordinatorFailure:' + $stage
        if($null -ne $mailboxPath -and [IO.Directory]::Exists($mailboxPath)){
            try {
                if($runs.Count -gt 0){$partial=[Text.UTF8Encoding]::new($false).GetBytes(($runs|ConvertTo-Json -Depth 12));[void](Write-F2AclAtomicCreateNewFile -Path (Join-Path $mailboxPath 'incomplete-runs.json') -Bytes $partial -MaxBytes 524288);$partialHash=Get-F2RuntimeSha256Bytes -Bytes $partial}else{$partialHash=$null}
                $coordinatorSid=$null;$administratorVerified=$false;try{$failureIdentity=Get-F2RuntimeCoordinatorIdentity;$coordinatorSid=[string]$failureIdentity.UserSid;$administratorVerified=[bool]$failureIdentity.IsAdministrator}catch{}
                $failure=[ordered]@{Schema='f2-icacls-runtime-status-v1';Outcome='INCOMPLETE';CaptureId=$CaptureId;RequesterSid=if($null -ne $request){$request.RequesterSid}else{$null};CoordinatorSid=$coordinatorSid;CoordinatorAdministratorVerified=$administratorVerified;SourcePinsManifestSha256=if($null -ne $manifest){$manifest.SourcePinsManifestSha256}else{$null};BaselinePayloadSha256=if($null -ne $manifest){$manifest.BaselinePayloadSha256}else{$null};BaselineIntegritySha256=if($null -ne $manifest){$manifest.BaselineIntegritySha256}else{$null};PackageComplete=$false;TargetCount=11;RunCount=$runs.Count;ComparisonCount=$comparisons.Count;Stage=$stage;CoordinatorExitCode=1;ElapsedMilliseconds=[long]$coordinatorClock.ElapsedMilliseconds;PartialEvidenceSha256=$partialHash;Errors=@($safe);CreatedUtc=[DateTime]::UtcNow.ToString('o')}
                [void](Write-F2RuntimeMailboxStatus -MailboxPath $mailboxPath -Status $failure)
            } catch { }
        }
        return [pscustomobject]@{Success=$false;Outcome='INCOMPLETE';CaptureId=$CaptureId;MailboxPath=$mailboxPath;TargetCount=11;RunCount=$runs.Count;CoordinatorExitCode=1;Stage=$stage;ElapsedMilliseconds=[long]$coordinatorClock.ElapsedMilliseconds;Errors=@($safe)}
    }
}

Export-ModuleMember -Function Invoke-F2IcaclsCaptureLauncher,Invoke-F2IcaclsProtectedCoordinator

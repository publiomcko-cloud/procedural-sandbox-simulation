Set-StrictMode -Version Latest

$script:F2IcaclsVmId = '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1'
$script:F2IcaclsVmName = 'F2-G1-Isolated-Disposable'
$script:F2IcaclsDiskSerial = '152D20337A0C'
$script:F2IcaclsDiskModel = 'KINGSTON SA400S37240G'
$script:F2IcaclsReviewedCollectorBaseSha = 'a62773f0553dff4a05055b18fa10834f7488ae55'
$script:F2IcaclsProjectRoot = 'G:\F2-G1-Isolated-Disposable'
$script:F2IcaclsBaselineMailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:F2IcaclsBaselinePayloadCaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:F2IcaclsMaxOutputBytes = 262144
$script:F2IcaclsVolumeResolver = $null
$script:F2IcaclsMailboxPathResolver = $null
$script:F2IcaclsMailboxDescriptorResolver = $null

function Get-F2IcaclsVolumeGuid {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if($null -ne $script:F2IcaclsVolumeResolver){return [string](& $script:F2IcaclsVolumeResolver $Path)}
    return [string][F2Acl.NativeDirectory]::GetVolumeGuidForPath($Path)
}

function Get-F2IcaclsExpectedPaths {
    [CmdletBinding()]
    param([string]$ProjectRoot=$script:F2IcaclsProjectRoot,[string]$VmId=$script:F2IcaclsVmId)

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $vm = ([guid]$VmId).ToString().ToUpperInvariant()
    $config = Join-Path $root $script:F2IcaclsVmName
    $configVm = Join-Path (Join-Path $config 'Virtual Machines') $vm
    return @(
        $root,
        $config,
        (Join-Path $config 'Virtual Machines'),
        $configVm,
        ($configVm + '.vmcx'),
        ($configVm + '.vmgs'),
        ($configVm + '.VMRS'),
        (Join-Path $root 'F2-G1-OS.vhdx'),
        (Join-Path $root 'F2-G1-Scratch.vhdx'),
        (Join-Path $root 'Virtual Machines'),
        (Join-Path (Join-Path $root 'Virtual Machines') $vm)
    )
}

function Get-F2IcaclsSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2IcaclsFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path)
    $fullPath=[IO.Path]::GetFullPath($Path)
    $file=Get-FileHash -LiteralPath $fullPath -Algorithm SHA256 -ErrorAction Stop
    if($file.Algorithm -cne 'SHA256' -or $file.Hash -notmatch '^[A-Fa-f0-9]{64}$'){throw 'SourceFileHashResultInvalid.'}
    return $file.Hash.ToLowerInvariant()
}

function Get-F2IcaclsExpectedMailboxPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$CaptureId)
    if ($null -ne $script:F2IcaclsMailboxPathResolver) { return [IO.Path]::GetFullPath([string](& $script:F2IcaclsMailboxPathResolver $CaptureId)) }
    return [IO.Path]::GetFullPath((Get-F2AclCoordinatorMailboxPath -CaptureId $CaptureId))
}

function Test-F2IcaclsMailboxEvidenceDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$CaptureId,
        [Parameter(Mandatory)][string]$RequesterSid
    )
    $full = [IO.Path]::GetFullPath($Path)
    $expected = Get-F2IcaclsExpectedMailboxPath -CaptureId $CaptureId
    if (-not [string]::Equals($full,$expected,[StringComparison]::OrdinalIgnoreCase)) { throw 'EvidenceMailboxPathDoesNotMatchCaptureId.' }
    Test-F2AclNoReparseAncestors -Path $full | Out-Null
    if ($null -ne $script:F2IcaclsMailboxDescriptorResolver) {
        $sddl = [string](& $script:F2IcaclsMailboxDescriptorResolver $full $CaptureId)
        $mailbox = Test-F2AclCoordinatorMailboxSddl -Sddl $sddl -RequesterSid $RequesterSid
        $mailbox | Add-Member -NotePropertyName Path -NotePropertyValue $full
    } else {
        $mailbox = Test-F2AclCoordinatorMailboxDirectory -Path $full -RequesterSid $RequesterSid
    }
    if ($mailbox.AceCount -ne 4 -or $mailbox.OwnerSid -cne 'S-1-5-32-544' -or -not $mailbox.Protected) { throw 'EvidenceMailboxSecurityContractInvalid.' }
    return $mailbox
}

function Read-F2IcaclsBaselineEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$ExpectedMailboxId,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')][string]$ExpectedPayloadCaptureId,
        [Parameter(Mandatory)][string]$ExpectedRequesterSid
    )
    try {
        if ($ExpectedMailboxId -cne $script:F2IcaclsBaselineMailboxId -or $ExpectedPayloadCaptureId -cne $script:F2IcaclsBaselinePayloadCaptureId) { throw 'BaselineMailboxOrPayloadCapturePinMismatch.' }
        $directory=[IO.Path]::GetFullPath($EvidenceDirectory)
        [void](Test-F2IcaclsMailboxEvidenceDirectory -Path $directory -CaptureId $ExpectedMailboxId -RequesterSid $ExpectedRequesterSid)
        $integrityPath=Join-Path $directory 'integrity.json'
        $payloadPath=Join-Path $directory 'acl-baseline.json'
        foreach($path in @($integrityPath,$payloadPath)){
            $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt 1048576){throw 'EvidenceFileTypeOrSizeInvalid.'}
        }
    $integrityBytes=[IO.File]::ReadAllBytes($integrityPath)
        $integrity=[Text.Encoding]::UTF8.GetString($integrityBytes)|ConvertFrom-Json -ErrorAction Stop
        if($integrity.Schema -cne 'f2-acl-integrity-v1' -or $integrity.PayloadFile -cne 'acl-baseline.json' -or $integrity.ProjectVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $integrity.EvidenceVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$'){throw 'IntegrityManifestIdentityInvalid.'}
        $payload=[IO.File]::ReadAllBytes($payloadPath)
        $payloadHash=Get-F2IcaclsSha256 -Bytes $payload
        if($integrity.PayloadBytes -ne $payload.Length -or -not [string]::Equals([string]$integrity.PayloadSha256,$payloadHash,[StringComparison]::OrdinalIgnoreCase)){throw 'BaselinePayloadIntegrityMismatch.'}
        $baseline=[Text.Encoding]::UTF8.GetString($payload)|ConvertFrom-Json -ErrorAction Stop
        if($baseline.CaptureId -cne $ExpectedPayloadCaptureId -or $baseline.Complete -ne $true){throw 'BaselinePayloadCaptureIdentityOrCompletenessInvalid.'}
        if($baseline.VmId -cne '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1' -or $baseline.VmName -cne 'F2-G1-Isolated-Disposable' -or @($baseline.Records).Count -ne 11 -or $baseline.Manifest.ExpectedCount -ne 11){throw 'BaselineVmOrRecordCompletenessInvalid.'}
        return [pscustomobject]@{Pass=$true;Baseline=$baseline;Integrity=$integrity;MailboxId=$ExpectedMailboxId;PayloadCaptureId=$ExpectedPayloadCaptureId;PayloadSha256=$payloadHash;IntegritySha256=(Get-F2IcaclsSha256 -Bytes $integrityBytes);ErrorCode=$null}
    } catch {
        return [pscustomobject]@{Pass=$false;Baseline=$null;Integrity=$null;PayloadSha256=$null;IntegritySha256=$null;ErrorCode='BaselineEvidenceReadOrIntegrityFailure'}
    }
}

function Test-F2IcaclsSourcePins {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)]$Integrity,
        [Parameter(Mandatory)][string]$ExpectedPinManifestSha256,
        [Parameter(Mandatory)][string]$ExpectedCommitSha,
        [Parameter(Mandatory)][string]$ActualCommitSha,
        [ValidateSet(1,2)][int]$PinContractVersion=1
    )
    try {
        if($ExpectedCommitSha -notmatch '^[0-9a-f]{40}$' -or $ActualCommitSha -cne $ExpectedCommitSha){throw 'ReviewedCommitMismatch.'}
        $root=[IO.Path]::GetFullPath($RepositoryRoot)
        $pinFilename=if($PinContractVersion -eq 2){'F2_ICACLS_SOURCE_PINS_V2.json'}else{'F2_ICACLS_SOURCE_PINS.json'}
        $pinPath=Join-Path (Join-Path $root 'scripts\f2-acl') $pinFilename
        $pinsBytes=[IO.File]::ReadAllBytes($pinPath)
        $pinsHash=Get-F2IcaclsSha256 -Bytes $pinsBytes
        if($ExpectedPinManifestSha256 -notmatch '^[0-9a-f]{64}$' -or -not [string]::Equals($pinsHash,$ExpectedPinManifestSha256,[StringComparison]::OrdinalIgnoreCase)){throw 'PinManifestDigestMismatch.'}
        $pins=[Text.Encoding]::UTF8.GetString($pinsBytes)|ConvertFrom-Json -ErrorAction Stop
        if($pins.ReviewedCollectorBaseSha -cne $script:F2IcaclsReviewedCollectorBaseSha){throw 'PinManifestSchemaOrBaseInvalid.'}
        if($PinContractVersion -eq 2){
            # The original v1 receipt is immutable. Never reinterpret the retained
            # baseline's module provenance as a hash of the active implementation.
            if($pins.Schema -cne 'f2-icacls-corroboration-pins-v2' -or
                $pins.LegacyPinManifestSha256 -cne '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce' -or
                $pins.RetainedBaseline.CollectorScriptSha256 -cne 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b' -or
                $pins.RetainedBaseline.ProtocolModuleSha256 -cne '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'){
                throw 'PinManifestV2HistoricalIdentityInvalid.'
            }
            $legacyPinPath=Join-Path (Join-Path $root 'scripts\f2-acl') 'F2_ICACLS_SOURCE_PINS.json'
            if((Get-F2IcaclsFileSha256 -Path $legacyPinPath) -cne '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'){
                throw 'HistoricalPinManifestChanged.'
            }
            $activePins=$pins.Active
        }else{
            if($pins.Schema -cne 'f2-icacls-corroboration-pins-v1'){throw 'PinManifestSchemaOrBaseInvalid.'}
            $activePins=$pins
        }
        $modulePath=Join-Path $root 'scripts\f2-acl\F2AclIcacls.Corroboration.psm1'
        $capturePath=Join-Path $root 'scripts\f2-acl\Invoke-F2AclReadOnlyCapture.ps1'
        $protocolPath=Join-Path $root 'scripts\f2-acl\F2AclCapture.Protocol.psm1'
        $runtimePath=Join-Path $root 'scripts\f2-acl\F2AclIcacls.Runtime.psm1'
        $launcherPath=Join-Path $root 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1'
        $coordinatorPath=Join-Path $root 'scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1'
        $moduleHash=Get-F2IcaclsFileSha256 -Path $modulePath
        $captureHash=Get-F2IcaclsFileSha256 -Path $capturePath
        $protocolHash=Get-F2IcaclsFileSha256 -Path $protocolPath
        $runtimeHash=Get-F2IcaclsFileSha256 -Path $runtimePath
        $launcherHash=Get-F2IcaclsFileSha256 -Path $launcherPath
        $coordinatorHash=Get-F2IcaclsFileSha256 -Path $coordinatorPath
        if($activePins.CorroborationModuleSha256 -cne $moduleHash -or $activePins.CollectorScriptSha256 -cne $captureHash -or $activePins.ProtocolModuleSha256 -cne $protocolHash -or $activePins.RuntimeModuleSha256 -cne $runtimeHash -or $activePins.LauncherScriptSha256 -cne $launcherHash -or $activePins.CoordinatorScriptSha256 -cne $coordinatorHash){throw 'SourcePinOrActiveImplementationMismatch.'}
        $retainedCollector=if($PinContractVersion -eq 2){[string]$pins.RetainedBaseline.CollectorScriptSha256}else{$captureHash}
        $retainedProtocol=if($PinContractVersion -eq 2){[string]$pins.RetainedBaseline.ProtocolModuleSha256}else{$protocolHash}
        if($Integrity.CollectorScriptSha256 -cne $retainedCollector -or $Integrity.ProtocolModuleSha256 -cne $retainedProtocol){throw 'RetainedBaselineSourceProvenanceMismatch.'}
        return [pscustomobject]@{Pass=$true;PinContractVersion=$PinContractVersion;CommitSha=$ActualCommitSha;PinManifestSha256=$pinsHash;CorroborationModuleSha256=$moduleHash;CollectorScriptSha256=$captureHash;ProtocolModuleSha256=$protocolHash;RuntimeModuleSha256=$runtimeHash;LauncherScriptSha256=$launcherHash;CoordinatorScriptSha256=$coordinatorHash;ErrorCode=$null}
    } catch {
        return [pscustomobject]@{Pass=$false;CommitSha=$ActualCommitSha;PinManifestSha256=$null;CorroborationModuleSha256=$null;CollectorScriptSha256=$null;ProtocolModuleSha256=$null;ErrorCode='SourcePinVerificationFailed'}
    }
}

function Test-F2IcaclsPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Baseline,
        [Parameter(Mandatory)]$Integrity,
        [Parameter(Mandatory)]$Observation,
        [Parameter(Mandatory)][string]$BaselineSha256,
        [Parameter(Mandatory)][string]$ExpectedBaselineSha256,
        [Parameter(Mandatory)][string]$ExpectedScriptSha256,
        [Parameter(Mandatory)][string]$ActualScriptSha256,
        [Parameter(Mandatory)][string]$ExpectedModuleSha256,
        [Parameter(Mandatory)][string]$ActualModuleSha256,
        [string]$ProjectRoot=$script:F2IcaclsProjectRoot
    )

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $gates = New-Object 'System.Collections.Generic.List[object]'
    $add = { param($Name,$Pass,$Detail) $gates.Add([pscustomobject]@{Name=$Name;Pass=[bool]$Pass;Detail=[string]$Detail}); if(-not $Pass){$errors.Add([string]$Name)} }
    try {
    if($null -eq $Baseline -or $null -eq $Integrity -or $null -eq $Observation){throw 'RequiredPreflightDocumentMissing.'}
    $vmPass = ($Baseline.Complete -eq $true -and [string]$Baseline.VmId -ceq $script:F2IcaclsVmId -and [string]$Baseline.VmName -ceq $script:F2IcaclsVmName -and [string]$Baseline.VmState -ceq 'Off' -and [string]$Observation.VmId -ceq $script:F2IcaclsVmId -and [string]$Observation.VmName -ceq $script:F2IcaclsVmName -and [string]$Observation.VmState -ceq 'Off' -and $Observation.NicCount -is [int] -and $Observation.NicCount -eq 0)
    & $add 'ImmutableVmOffAndZeroNic' $vmPass 'Baseline and current observation must identify the pinned OFF VM and zero NICs.'

    $expectedPaths = @(Get-F2IcaclsExpectedPaths -ProjectRoot $ProjectRoot)
    $actualRaw=@($Baseline.Manifest.ExpectedPaths|ForEach-Object{[string]$_})
    $recordRaw=@($Baseline.Records|ForEach-Object{[string]$_.Path})
    $actualPaths = @($actualRaw | ForEach-Object { [IO.Path]::GetFullPath($_) })
    $recordPaths = @($recordRaw | ForEach-Object { [IO.Path]::GetFullPath($_) })
    $canonicalInputs=$true
    for($i=0;$i -lt $actualRaw.Count;$i++){if(-not [string]::Equals($actualRaw[$i],$actualPaths[$i],[StringComparison]::OrdinalIgnoreCase)){$canonicalInputs=$false}}
    for($i=0;$i -lt $recordRaw.Count;$i++){if(-not [string]::Equals($recordRaw[$i],$recordPaths[$i],[StringComparison]::OrdinalIgnoreCase)){$canonicalInputs=$false}}
    $pathsPass = ($canonicalInputs -and @($expectedPaths | Sort-Object -Unique).Count -eq 11 -and @($actualPaths | Sort-Object -Unique).Count -eq 11 -and @($recordPaths | Sort-Object -Unique).Count -eq 11 -and @(Compare-Object ($expectedPaths | Sort-Object) ($actualPaths | Sort-Object) -CaseSensitive).Count -eq 0 -and @(Compare-Object ($expectedPaths | Sort-Object) ($recordPaths | Sort-Object) -CaseSensitive).Count -eq 0 -and $Baseline.Manifest.ExpectedCount -eq 11 -and $Baseline.Manifest.RecordCount -eq 11 -and $Baseline.Manifest.UniquePathCount -eq 11 -and $Baseline.Records.Count -eq 11)
    & $add 'ExactElevenPathSet' $pathsPass 'Expected paths, manifest paths and records must exactly equal the 11 pinned canonical objects.'

    $projectGuid = [string]$Integrity.ProjectVolumeGuid
    $evidenceGuid = [string]$Integrity.EvidenceVolumeGuid
    $guidPass = ($projectGuid -match '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -and $evidenceGuid -match '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -and -not [string]::Equals($projectGuid.TrimEnd('\'),$evidenceGuid.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($projectGuid.TrimEnd('\'),[string]$Observation.GVolumeGuid.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($evidenceGuid.TrimEnd('\'),[string]$Observation.EvidenceVolumeGuid.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase))
    & $add 'ProjectAndEvidenceVolumeIdentity' $guidPass 'ProjectVolumeGuid must match G:; EvidenceVolumeGuid must independently match the evidence volume.'

    $payloadPass = ([string]$Integrity.PayloadSha256 -match '^[0-9a-f]{64}$' -and [string]::Equals($Integrity.PayloadSha256,$ExpectedBaselineSha256,[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($BaselineSha256,$ExpectedBaselineSha256,[StringComparison]::OrdinalIgnoreCase))
    & $add 'RetainedBaselineIntegrity' $payloadPass 'Baseline bytes and integrity manifest digest must match the reviewed capture.'

    $storage = $Observation.Storage
    $storageIdentity = Test-F2AclKingstonStorageIdentity -Observation $storage
    $storagePass = ($storageIdentity.Pass -and [int]$storage.PartitionDiskNumber -eq [int]$storage.DiskNumber -and [int]$storage.Win32Index -eq [int]$storage.DiskNumber -and [string]$storage.GDriveLetter -ceq 'G:' -and [string]$storage.VolumeFileSystem -ceq 'NTFS' -and [string]$storage.VolumeHealth -ceq 'Healthy' -and [string]::Equals([string]$storage.GVolumeGuid.TrimEnd('\'),$projectGuid.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase))
    & $add 'KingstonIdentityAndGMapping' $storagePass 'Unique serial/model/USB/health checks and G: volume mapping must all agree.'

    $pathChecks = @($Observation.PathChecks)
    $expectedDirectories=@($expectedPaths[0],$expectedPaths[1],$expectedPaths[2],$expectedPaths[3],$expectedPaths[9],$expectedPaths[10])
    $safePaths = ($pathChecks.Count -eq 11 -and @($pathChecks | Where-Object { $_.Exists -ne $true -or $_.ReparsePoint -ne $false -or $_.ParentChainClear -ne $true -or $_.IsDirectory -isnot [bool] -or ([bool]$_.IsDirectory -ne ([string]$_.Path -in $expectedDirectories)) -or -not [string]::Equals([string]$_.Path,[IO.Path]::GetFullPath([string]$_.Path),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFullPath([string]$_.Path) -notin $expectedPaths }).Count -eq 0 -and @($pathChecks.Path | Sort-Object -Unique).Count -eq 11)
    & $add 'CanonicalPathsNoReparse' $safePaths 'All 11 approved paths and their ancestor chains must exist canonically without reparse points or aliases.'

    $pinsPass = ([string]$ExpectedScriptSha256 -match '^[0-9a-f]{64}$' -and [string]$ExpectedModuleSha256 -match '^[0-9a-f]{64}$' -and [string]::Equals($ExpectedScriptSha256,$ActualScriptSha256,[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($ExpectedModuleSha256,$ActualModuleSha256,[StringComparison]::OrdinalIgnoreCase))
    & $add 'ReviewedCollectorSourcePins' $pinsPass 'Existing collector and protocol source hashes must match their reviewed pin manifest.'

    $evidence = $Observation.EvidenceDirectory
    $evidencePass = ($evidence.Protected -eq $true -and $evidence.OwnerSid -match '^S-1-' -and $evidence.NoUnexpectedPrincipals -eq $true -and $evidence.SeparateFromG -eq $true)
    & $add 'ProtectedEvidenceDestination' $evidencePass 'New evidence location must have a verified restrictive protected DACL and be off G:.'

    return [pscustomobject]@{Pass=($errors.Count -eq 0);Errors=$errors.ToArray();Gates=$gates.ToArray();ExpectedPaths=$expectedPaths;ProjectVolumeGuid=$projectGuid;EvidenceVolumeGuid=$evidenceGuid}
    } catch {
        Write-Verbose ('F2Icacls preflight detail: '+$_.Exception.Message+' line '+$_.InvocationInfo.ScriptLineNumber)
        $safeCode='MalformedOrMissingPreflightField'
        $gate=[pscustomobject]@{Name='PreflightShapeAndPathValidation';Pass=$false;Detail=$safeCode}
        return [pscustomobject]@{Pass=$false;Errors=@($safeCode);Gates=@($gate);ExpectedPaths=@();ProjectVolumeGuid=$null;EvidenceVolumeGuid=$null}
    }
}

function Get-F2IcaclsRightMask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Rights)
    $map = @{
        N=[uint32]0x00000000; F=[uint32]0x001F01FF; M=[uint32]0x001301BF; RX=[uint32]0x001200A9; R=[uint32]0x00120089; W=[uint32]0x00120116; D=[uint32]0x00010000; DE=[uint32]0x00010000
        AD=[uint32]0x00000004; AS=[uint32]0x01000000; WD=[uint32]0x00000002; RD=[uint32]0x00000001; REA=[uint32]0x00000008; WEA=[uint32]0x00000010; X=[uint32]0x00000020; DC=[uint32]0x00000040; RA=[uint32]0x00000080; WA=[uint32]0x00000100
        RC=[uint32]0x00020000; WDAC=[uint32]0x00040000; WO=[uint32]0x00080000; S=[uint32]0x00100000
        GR=[Convert]::ToUInt32('80000000',16); GW=[Convert]::ToUInt32('40000000',16); GE=[Convert]::ToUInt32('20000000',16); GA=[Convert]::ToUInt32('10000000',16); MA=[Convert]::ToUInt32('02000000',16)
    }
    [uint32]$mask=0
    foreach($right in $Rights){if(-not $map.ContainsKey($right)){return [pscustomobject]@{Supported=$false;Mask=$null;Unknown=$right}};$mask=$mask -bor [uint32]$map[$right]}
    return [pscustomobject]@{Supported=$true;Mask=$mask;Unknown=$null}
}

function ConvertFrom-F2IcaclsText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text,[Parameter(Mandatory)][string]$ExpectedPath)
    $lines=@($Text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $aces=New-Object 'System.Collections.Generic.List[object]'
    $unsupported=New-Object 'System.Collections.Generic.List[string]'
    $pathMatched=$false
    if($lines.Count -eq 0){return [pscustomobject]@{PathMatched=$false;Aces=@();Unsupported=@('MissingTargetPath')}}
    $header=$lines[0]
    if(-not $header.StartsWith($ExpectedPath,[StringComparison]::OrdinalIgnoreCase)) { return [pscustomobject]@{PathMatched=$false;Aces=@();Unsupported=@('TargetPathMismatch')} }
    if($header.Length -gt $ExpectedPath.Length -and -not [char]::IsWhiteSpace($header[$ExpectedPath.Length])) { return [pscustomobject]@{PathMatched=$false;Aces=@();Unsupported=@('AmbiguousTargetPathPrefix')} }
    $pathMatched=$true
    $firstAce=$header.Substring($ExpectedPath.Length).Trim()
    $aceLines=New-Object 'System.Collections.Generic.List[string]'
    if($firstAce.Length -gt 0){$aceLines.Add($firstAce)}
    for($i=1;$i -lt $lines.Count;$i++){$aceLines.Add($lines[$i])}
    foreach($line in $aceLines){
        if($line -match 'Successfully processed|processed successfully|failed processing|failed to process'){continue}
        if($line -notmatch '^\s*(?<principal>.+?):(?<codes>(?:\([^)]+\))+?)\s*$'){$unsupported.Add('UnparsedAclLine');continue}
        $principal=$Matches.principal.Trim();$codes=@([regex]::Matches($Matches.codes,'\((?<c>[^)]+)\)')|ForEach-Object{$_.Groups['c'].Value})
        if([string]::IsNullOrWhiteSpace($principal)){$unsupported.Add('MissingPrincipal');continue}
        if($principal -match '^\*?(S-1-\d+(?:-\d+)+)$'){ $sid=$Matches[1] } else {
            $wellKnown=@{'BUILTIN\Administrators'='S-1-5-32-544';'Administrators'='S-1-5-32-544';'NT AUTHORITY\SYSTEM'='S-1-5-18';'SYSTEM'='S-1-5-18';'CREATOR OWNER'='S-1-3-0';'OWNER RIGHTS'='S-1-3-4';'Everyone'='S-1-1-0';'NT AUTHORITY\Authenticated Users'='S-1-5-11';'BUILTIN\Users'='S-1-5-32-545'}
            if($wellKnown.ContainsKey($principal)){$sid=$wellKnown[$principal]}else{try{$sid=([Security.Principal.NTAccount]::new($principal)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{$unsupported.Add('UnresolvedPrincipal');continue}}
        }
        $aceType='Allow';$flags=New-Object 'System.Collections.Generic.List[string]';$rights=New-Object 'System.Collections.Generic.List[string]'
        foreach($codeGroup in $codes){foreach($code in ($codeGroup -split ',')){$token=$code.Trim();switch -CaseSensitive ($token){'I' {$flags.Add('Inherited')};'OI' {$flags.Add('ObjectInherit')};'CI' {$flags.Add('ContainerInherit')};'IO' {$flags.Add('InheritOnly')};'NP' {$flags.Add('NoPropagateInherit')};'DENY' {$aceType='Deny'};default {$rights.Add($token)}}}}
        $mask=Get-F2IcaclsRightMask -Rights $rights.ToArray()
        if(-not $mask.Supported){$unsupported.Add('UnsupportedRight');continue}
        $aces.Add([pscustomobject]@{Sid=$sid;Type=$aceType;Mask=$mask.Mask;Flags=@($flags.ToArray()|Sort-Object -Unique);RawRights=$rights.ToArray();HasGeneric=(($mask.Mask -band [Convert]::ToUInt32('F0000000',16)) -ne 0)})
    }
    if($aces.Count -eq 0){$unsupported.Add('NoAclEntries')}
    return [pscustomobject]@{PathMatched=$pathMatched;Aces=$aces.ToArray();Unsupported=$unsupported.ToArray()}
}

function ConvertTo-F2IcaclsSpecificMask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][uint32]$Mask)
    [uint32]$genericMask=[Convert]::ToUInt32('F0000000',16)
    [uint32]$mapped=$Mask -band (-bnot $genericMask)
    if(($Mask -band [Convert]::ToUInt32('80000000',16)) -ne 0){$mapped=$mapped -bor [uint32]0x00120089}
    if(($Mask -band [Convert]::ToUInt32('40000000',16)) -ne 0){$mapped=$mapped -bor [uint32]0x00120116}
    if(($Mask -band [Convert]::ToUInt32('20000000',16)) -ne 0){$mapped=$mapped -bor [uint32]0x001200A0}
    if(($Mask -band [Convert]::ToUInt32('10000000',16)) -ne 0){$mapped=$mapped -bor [uint32]0x001F01FF}
    [uint32]$knownMask=([Convert]::ToUInt32('F0000000',16) -bor [uint32]0x031F01FF)
    [uint32]$unknownBits=$Mask -band (-bnot $knownMask)
    return [pscustomobject]@{RawMask=$Mask;SpecificMask=$mapped;HadGeneric=(($Mask -band $genericMask) -ne 0);UnknownBits=($unknownBits -ne 0);MaximumAllowed=(($Mask -band [uint32]0x02000000) -ne 0)}
}

function Get-F2IcaclsComparison {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$BaselineRecord,[Parameter(Mandatory)]$CommandResult)
    if($CommandResult.TimedOut -or -not $CommandResult.CleanupComplete -or -not $CommandResult.OutputComplete -or $CommandResult.ExitCode -ne 0 -or $CommandResult.Truncated -or $CommandResult.ReaderError){return [pscustomobject]@{Classification='INDETERMINATE';Reason='CommandIncompleteOrFailed';Path=[string]$BaselineRecord.Path}}
    $parsed=ConvertFrom-F2IcaclsText -Text ([string]$CommandResult.Stdout) -ExpectedPath ([string]$BaselineRecord.Path)
    if(-not $parsed.PathMatched -or $parsed.Unsupported.Count -gt 0){return [pscustomobject]@{Classification='INDETERMINATE';Reason='OutputNotFullyParseable';Path=[string]$BaselineRecord.Path}}
    $expected=@();foreach($a in @($BaselineRecord.Aces)){
        try{$maskText=[string]$a.AccessMask;$mask=[uint32][Convert]::ToUInt32($maskText.Replace('0x',''),16)}catch{return [pscustomobject]@{Classification='INDETERMINATE';Reason='BaselineMaskUnsupported';Path=[string]$BaselineRecord.Path}}
        $flags=@();if($a.Inherited){$flags+='Inherited'};if($a.InheritanceFlags -match 'ObjectInherit'){$flags+='ObjectInherit'};if($a.InheritanceFlags -match 'ContainerInherit'){$flags+='ContainerInherit'};if($a.PropagationFlags -match 'InheritOnly'){$flags+='InheritOnly'};if($a.PropagationFlags -match 'NoPropagateInherit'){$flags+='NoPropagateInherit'}
        $expected+=@([pscustomobject]@{Key=([string]$a.Sid+'|'+[string]$a.Type+'|'+$mask+'|'+(@($flags|Sort-Object -Unique)-join ','));Sid=[string]$a.Sid;Type=[string]$a.Type;Mask=$mask;Flags=@($flags|Sort-Object -Unique)})
    }
    $actual=@($parsed.Aces|ForEach-Object{[pscustomobject]@{Key=([string]$_.Sid+'|'+[string]$_.Type+'|'+[uint32]$_.Mask+'|'+(@($_.Flags|Sort-Object -Unique)-join ','));Sid=[string]$_.Sid;Type=[string]$_.Type;Mask=[uint32]$_.Mask;Flags=@($_.Flags|Sort-Object -Unique)}})
    if($expected.Count -ne $actual.Count){return [pscustomobject]@{Classification='MISMATCH';Reason='ParsedAceCountDiffers';Path=[string]$BaselineRecord.Path}}
    $remaining=[Collections.Generic.List[object]]::new();foreach($a in $actual){$remaining.Add($a)}
    foreach($e in $expected){$matchIndex=-1;for($i=0;$i -lt $remaining.Count;$i++){if($remaining[$i].Key -ceq $e.Key){$matchIndex=$i;break}};if($matchIndex -ge 0){$remaining.RemoveAt($matchIndex);continue}
        $compatible=$false
        for($i=0;$i -lt $remaining.Count;$i++){$a=$remaining[$i];if($a.Sid -ceq $e.Sid -and $a.Type -ceq $e.Type -and (@(Compare-Object $e.Flags $a.Flags).Count -eq 0)){$em=ConvertTo-F2IcaclsSpecificMask -Mask $e.Mask;$am=ConvertTo-F2IcaclsSpecificMask -Mask $a.Mask;if($em.UnknownBits -or $am.UnknownBits -or $em.MaximumAllowed -or $am.MaximumAllowed){return [pscustomobject]@{Classification='INDETERMINATE';Reason='AccessMaskSemanticsUnresolved';Path=[string]$BaselineRecord.Path}};if($em.SpecificMask -eq $am.SpecificMask){$compatible=$true;$remaining.RemoveAt($i);break};if($em.HadGeneric -or $am.HadGeneric){return [pscustomobject]@{Classification='INDETERMINATE';Reason='GenericRightsMappingUnresolved';Path=[string]$BaselineRecord.Path}}}}
        if(-not $compatible){return [pscustomobject]@{Classification='MISMATCH';Reason='ParsedAceSetDiffers';Path=[string]$BaselineRecord.Path}}
    }
    if($remaining.Count -eq 0){return [pscustomobject]@{Classification='PASS';Reason='AllParsedAcesMatchOrMapEquivalently';Path=[string]$BaselineRecord.Path}}
    return [pscustomobject]@{Classification='MISMATCH';Reason='ParsedAceSetDiffers';Path=[string]$BaselineRecord.Path}
}

function Invoke-F2IcaclsProcessCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Arguments,
        [ValidateRange(1,120)][int]$TimeoutSeconds=15,
        [ValidateRange(1,5000)][int]$CleanupGraceMilliseconds=1000,
        [ValidateRange(1024,1048576)][int]$MaxBytesPerStream=$script:F2IcaclsMaxOutputBytes
    )

    $result=[ordered]@{Started=$false;ProcessId=$null;ProcessStartUtc=$null;ExitCode=$null;TimedOut=$false;CleanupComplete=$true;OutputComplete=$false;Truncated=$false;Stdout='';Stderr='';StdoutBytes=0L;StderrBytes=0L;StdoutSha256=$null;StderrSha256=$null;OutputHashEncoding='UTF-8 decoded text';ReaderError=$null;ElapsedMilliseconds=0}
    $clock=[Diagnostics.Stopwatch]::StartNew();$process=$null;$outTask=$null;$errTask=$null
    $outBuffer=[char[]]::new(4096);$errBuffer=[char[]]::new(4096)
    $outBuilder=[Text.StringBuilder]::new();$errBuilder=[Text.StringBuilder]::new()
    $outEof=$false;$errEof=$false;$outFailed=$false;$errFailed=$false;$overflow=$false
    [long]$outRetainedBytes=0;[long]$errRetainedBytes=0;[long]$outObservedBytes=0;[long]$errObservedBytes=0
    try {
        $startInfo=New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName=$FilePath;$startInfo.Arguments=$Arguments;$startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true;$startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process;$process.StartInfo=$startInfo
        if(-not $process.Start()){throw 'IcaclsChildStartReturnedFalse.'}
        $result.Started=$true;$result.ProcessId=[int]$process.Id;$result.ProcessStartUtc=$process.StartTime.ToUniversalTime().ToString('o')
        $deadline=[int64]$TimeoutSeconds*1000
        $outTask=$process.StandardOutput.ReadAsync($outBuffer,0,$outBuffer.Length)
        $errTask=$process.StandardError.ReadAsync($errBuffer,0,$errBuffer.Length)
        while($true){
            foreach($stream in @('Out','Err')){
                $task=if($stream -eq 'Out'){$outTask}else{$errTask}
                $buffer=if($stream -eq 'Out'){$outBuffer}else{$errBuffer}
                $done=if($stream -eq 'Out'){$outEof -or $outFailed}else{$errEof -or $errFailed}
                if(-not $done -and $task.IsCompleted){
                    try{
                        $count=[int]$task.GetAwaiter().GetResult()
                        if($count -le 0){if($stream -eq 'Out'){$outEof=$true}else{$errEof=$true}}
                        else{
                            $chunk=New-Object string ($buffer,0,$count)
                            $chunkBytes=[long][Text.Encoding]::UTF8.GetByteCount($chunk)
                            if($stream -eq 'Out'){$outObservedBytes+=$chunkBytes;$retained=$outRetainedBytes;$builder=$outBuilder}else{$errObservedBytes+=$chunkBytes;$retained=$errRetainedBytes;$builder=$errBuilder}
                            if($retained+$chunkBytes -le $MaxBytesPerStream){[void]$builder.Append($chunk);if($stream -eq 'Out'){$outRetainedBytes+=$chunkBytes}else{$errRetainedBytes+=$chunkBytes}}
                            else{
                                $overflow=$true
                                $available=[int][Math]::Max(0,$MaxBytesPerStream-$retained)
                                if($available -gt 0){$keep='';$used=0;for($n=0;$n -lt $chunk.Length;$n++){$one=[string]$chunk[$n];$oneBytes=[Text.Encoding]::UTF8.GetByteCount($one);if($used+$oneBytes -gt $available){break};$keep+=$one;$used+=$oneBytes};[void]$builder.Append($keep);if($stream -eq 'Out'){$outRetainedBytes+=$used}else{$errRetainedBytes+=$used}}
                            }
                            if($stream -eq 'Out'){$outTask=$process.StandardOutput.ReadAsync($outBuffer,0,$outBuffer.Length)}else{$errTask=$process.StandardError.ReadAsync($errBuffer,0,$errBuffer.Length)}
                        }
                    }catch{if($stream -eq 'Out'){$outFailed=$true}else{$errFailed=$true};$result.ReaderError='RedirectedStreamReadFailed'}
                }
            }
            $hasExited=[bool]$process.HasExited
            $streamsDone=(($outEof -or $outFailed) -and ($errEof -or $errFailed))
            if($hasExited -and $streamsDone){break}
            $remaining=$deadline-[int64]$clock.ElapsedMilliseconds
            if($remaining -le 0){$result.TimedOut=$true;break}
            $sleep=[int][Math]::Min(20,$remaining)
            if($sleep -gt 0){Start-Sleep -Milliseconds $sleep}
        }
        if($result.TimedOut -and -not $process.HasExited){
            try{$process.Kill()}catch{$result.CleanupComplete=$false;$result.ReaderError='ChildTerminationFailed'}
            try{if(-not $process.WaitForExit($CleanupGraceMilliseconds)){$result.CleanupComplete=$false}}catch{$result.CleanupComplete=$false;$result.ReaderError='ChildTerminationWaitFailed'}
        }
        if(-not $outEof -or -not $errEof -or $outFailed -or $errFailed){$result.OutputComplete=$false;$result.CleanupComplete=$false;if($null -eq $result.ReaderError){$result.ReaderError='RedirectedStreamDrainDeadlineExceeded'}}
        if($process.HasExited){$result.ExitCode=[int]$process.ExitCode}
        $result.Stdout=[string]$outBuilder.ToString();$result.Stderr=[string]$errBuilder.ToString()
        $result.StdoutBytes=$outObservedBytes;$result.StderrBytes=$errObservedBytes
        if($overflow){$result.Truncated=$true;$result.CleanupComplete=$false;$result.ReaderError='OutputLimitExceeded'}
        if($outFailed -or $errFailed){$result.CleanupComplete=$false}
        $stdoutUtf8=[Text.Encoding]::UTF8.GetBytes($result.Stdout);$stderrUtf8=[Text.Encoding]::UTF8.GetBytes($result.Stderr)
        $result.StdoutSha256=Get-F2IcaclsSha256 -Bytes $stdoutUtf8;$result.StderrSha256=Get-F2IcaclsSha256 -Bytes $stderrUtf8
        if(-not $result.TimedOut -and $result.CleanupComplete -and $process.HasExited -and $outEof -and $errEof -and -not $overflow -and -not $outFailed -and -not $errFailed){$result.OutputComplete=$true}
    }
    catch{$result.ReaderError=if($null -eq $result.ReaderError){$_.Exception.GetType().Name+': '+$_.Exception.Message}else{$result.ReaderError};$result.CleanupComplete=$false}
    finally{
        if($null -ne $process){
            try{if(-not $process.HasExited){$process.Kill();if(-not $process.WaitForExit($CleanupGraceMilliseconds)){$result.CleanupComplete=$false}}}catch{$result.CleanupComplete=$false}
            try{$process.StandardOutput.Dispose()}catch{if(-not $result.TimedOut){$result.CleanupComplete=$false}}
            try{$process.StandardError.Dispose()}catch{if(-not $result.TimedOut){$result.CleanupComplete=$false}}
            try{$process.Dispose()}catch{$result.CleanupComplete=$false}
        }
        $clock.Stop();$result.ElapsedMilliseconds=[long]$clock.ElapsedMilliseconds
    }
    return [pscustomobject]$result
}

function Test-F2IcaclsAccessDenied {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Result)
    return ($Result.ExitCode -eq 5 -and $Result.OutputComplete -eq $true -and $Result.CleanupComplete -eq $true -and ([string]$Result.Stdout+' '+[string]$Result.Stderr) -match '(?i)(access is denied|access denied|acesso negado)')
}

function Get-F2IcaclsCommandSpec {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Target,[string]$ProjectRoot=$script:F2IcaclsProjectRoot)
    $full=[IO.Path]::GetFullPath($Target)
    $allowlist=@(Get-F2IcaclsExpectedPaths -ProjectRoot $ProjectRoot)
    if(-not [string]::Equals($Target,$full,[StringComparison]::OrdinalIgnoreCase) -or $full -notin $allowlist -or $Target.Contains('"') -or $Target.Contains("`r") -or $Target.Contains("`n")){throw 'TargetOutsideExactIcaclsAllowlist.'}
    $exe=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'icacls.exe'
    return [pscustomobject]@{FilePath=$exe;Arguments=('"'+$full+'"');Target=$full;Switches=@()}
}

function Invoke-F2IcaclsObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Target,[string]$ProjectRoot=$script:F2IcaclsProjectRoot,[ValidateRange(1,120)][int]$TimeoutSeconds=15,[ValidateRange(1024,1048576)][int]$MaxBytesPerStream=$script:F2IcaclsMaxOutputBytes)
    $spec=Get-F2IcaclsCommandSpec -Target $Target -ProjectRoot $ProjectRoot
    $result=Invoke-F2IcaclsProcessCore -FilePath $spec.FilePath -Arguments $spec.Arguments -TimeoutSeconds $TimeoutSeconds -MaxBytesPerStream $MaxBytesPerStream
    $result | Add-Member -NotePropertyName Path -NotePropertyValue $spec.Target
    $result | Add-Member -NotePropertyName Command -NotePropertyValue 'icacls.exe "<approved-path>"'
    return $result
}

function Invoke-F2IcaclsPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Targets,[Parameter(Mandatory)][scriptblock]$StandardRunner,[Parameter(Mandatory)][scriptblock]$CoordinatorLauncher,[string]$ProjectRoot=$script:F2IcaclsProjectRoot,[switch]$PermitOneCoordinatorLaunch)
    $expected=@(Get-F2IcaclsExpectedPaths -ProjectRoot $ProjectRoot)
    $provided=@($Targets|ForEach-Object{[IO.Path]::GetFullPath($_)})
    if($provided.Count -ne 11 -or @($provided|Sort-Object -Unique).Count -ne 11 -or @(Compare-Object ($expected|Sort-Object) ($provided|Sort-Object) -CaseSensitive).Count -ne 0){return [pscustomobject]@{Complete=$false;Runs=@();ElevationLaunches=0;Outcome='PREFLIGHT_TARGET_SCOPE_FAILURE';Errors=@('TargetsDoNotMatchExactElevenObjectAllowlist')}}
    $runs=@();$elevationLaunches=0
    foreach($target in $expected){
        try{$r=& $StandardRunner $target;if($null -ne $r -and $r.PSObject.Properties['Result']){$r=$r.Result};if($null -eq $r -or $null -eq $r.ExitCode){throw 'StandardRunnerReturnedNoStatus.'}}
        catch{$r=[pscustomobject]@{Started=$false;ProcessId=$null;ExitCode=$null;TimedOut=$false;CleanupComplete=$false;OutputComplete=$false;Truncated=$false;Stdout='';Stderr='';StdoutBytes=0;StderrBytes=0;StdoutSha256=$null;StderrSha256=$null;ReaderError='StandardRunnerFailed';ElapsedMilliseconds=0}}
        $runs+=@([pscustomobject]@{Path=$target;Result=$r;Mode='Standard'})
    }
    $failed=@($runs|Where-Object{$_.Result.ExitCode -ne 0 -or $_.Result.TimedOut -or -not $_.Result.CleanupComplete -or -not $_.Result.OutputComplete -or $_.Result.Truncated})
    if($failed.Count -eq 0){return [pscustomobject]@{Complete=$true;Runs=$runs;ElevationLaunches=0;Outcome='STANDARD_COMPLETE'}}
    $other=@($failed|Where-Object{-not (Test-F2IcaclsAccessDenied -Result $_.Result)})
    if($other.Count -gt 0 -or -not $PermitOneCoordinatorLaunch){return [pscustomobject]@{Complete=$false;Runs=$runs;ElevationLaunches=0;Outcome='INDETERMINATE';Errors=@('StandardCommandFailureOrElevationNotPermitted')}}
    if($elevationLaunches -ne 0){throw 'ElevatedCoordinatorLaunchLimitExceeded.'}
    $elevationLaunches++
    $retryPaths=@($failed.Path)
    try{$coordinator=& $CoordinatorLauncher $retryPaths}catch{return [pscustomobject]@{Complete=$false;Runs=$runs;ElevationLaunches=1;Outcome='INDETERMINATE';Errors=@('CoordinatorLaunchOrResultFailed')}}
    if($elevationLaunches -ne 1){throw 'ElevatedCoordinatorLaunchCountInvalid.'}
    $coordinatorRuns=@()
    if($null -ne $coordinator){$coordinatorRuns=@($coordinator.Runs)}
    $coordinatorValid=($null -ne $coordinator -and $coordinator.Complete -eq $true -and $coordinatorRuns.Count -eq $retryPaths.Count -and @(Compare-Object ($retryPaths|Sort-Object) ($coordinatorRuns.Path|Sort-Object) -CaseSensitive).Count -eq 0 -and @($coordinatorRuns|Where-Object{$_.Result.ExitCode -ne 0 -or $_.Result.TimedOut -or -not $_.Result.OutputComplete -or -not $_.Result.CleanupComplete -or $_.Result.Truncated}).Count -eq 0)
    if(-not $coordinatorValid){
        if($null -ne $coordinator){$runs+=@($coordinator.Runs|ForEach-Object{[pscustomobject]@{Path=$_.Path;Result=$_.Result;Mode='Elevated'}})}
        return [pscustomobject]@{Complete=$false;Runs=$runs;ElevationLaunches=1;Outcome='INDETERMINATE';Errors=@('ElevatedRetryIncompleteOrScopeMismatch')}
    }
    $runs+=@($coordinator.Runs|ForEach-Object{[pscustomobject]@{Path=$_.Path;Result=$_.Result;Mode='Elevated'}})
    return [pscustomobject]@{Complete=$true;Runs=$runs;ElevationLaunches=1;Outcome='ELEVATED_RETRY_COMPLETE'}
}

function Write-F2IcaclsEvidencePackage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$OwnerSid,[Parameter(Mandatory)][string[]]$Targets,[Parameter(Mandatory)][object[]]$Runs,[Parameter(Mandatory)][object[]]$Comparisons,[Parameter(Mandatory)][string]$ProjectVolumePath,[Parameter(Mandatory)][string]$ProjectVolumeGuid,[Parameter(Mandatory)][string]$EvidenceVolumeGuid,[ValidateRange(1024,1048576)][int]$MaxFileBytes=524288,[string]$MailboxCaptureId,[string]$MailboxRequesterSid)
    $full=[IO.Path]::GetFullPath($Directory)
    if(-not [IO.Directory]::Exists($full)){throw 'EvidenceDirectoryMissing.'}
    if($OwnerSid -notmatch '^S-1-'){throw 'EvidenceDirectoryOwnerSidInvalid.'}
    Test-F2AclNoReparseAncestors -Path $full | Out-Null
    if(-not [string]::IsNullOrWhiteSpace($MailboxCaptureId) -or -not [string]::IsNullOrWhiteSpace($MailboxRequesterSid)){
        if([string]::IsNullOrWhiteSpace($MailboxCaptureId) -or [string]::IsNullOrWhiteSpace($MailboxRequesterSid) -or $MailboxRequesterSid -cne $OwnerSid){throw 'EvidenceMailboxArgumentsInvalid.'}
        $secureDirectory=Test-F2IcaclsMailboxEvidenceDirectory -Path $full -CaptureId $MailboxCaptureId -RequesterSid $MailboxRequesterSid
    }else{$secureDirectory=Test-F2AclRestrictedDirectory -Path $full -OwnerSid $OwnerSid}
    if(-not $secureDirectory.Protected){throw 'EvidenceDirectoryAclNotVerified.'}
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'EvidenceDirectoryIsReparsePoint.'}
    $actualEvidenceVolume=Get-F2IcaclsVolumeGuid -Path $full
    $actualProjectVolume=Get-F2IcaclsVolumeGuid -Path $ProjectVolumePath
    if(-not [string]::Equals($actualProjectVolume,$ProjectVolumeGuid,[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals($actualEvidenceVolume,$EvidenceVolumeGuid,[StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($actualEvidenceVolume,$actualProjectVolume,[StringComparison]::OrdinalIgnoreCase)){throw 'EvidenceVolumeIdentityOrSeparationFailed.'}
    $targetSet=@($Targets|Sort-Object -Unique)
    $runPaths=@($Runs.Path|Sort-Object -Unique);$comparisonPaths=@($Comparisons.Path|Sort-Object -Unique)
    if($targetSet.Count -ne 11 -or $Runs.Count -lt 11 -or $runPaths.Count -ne 11 -or @(Compare-Object $targetSet $runPaths).Count -ne 0 -or $comparisonPaths.Count -ne 11 -or @(Compare-Object $targetSet $comparisonPaths).Count -ne 0 -or $Comparisons.Count -ne 11){throw 'EvidencePackageTargetCompletenessFailed.'}
    foreach($run in $Runs){if([string]$run.Path -notin $targetSet -or $null -eq $run.Result -or $null -eq $run.Result.ExitCode){throw 'EvidencePackageContainsInvalidRun.'}}
    foreach($comparison in $Comparisons){if([string]$comparison.Classification -notin @('PASS','MISMATCH','INDETERMINATE')){throw 'EvidencePackageContainsInvalidClassification.'}}
    $manifestRows=New-Object 'System.Collections.Generic.List[object]';$index=0
    foreach($run in $Runs){
        $index++
        if([string]$run.Path -notin $targetSet){throw 'EvidencePackageContainsUnexpectedPath.'}
        $json=$run|ConvertTo-Json -Depth 14
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes($json)
        if($bytes.Length -gt $MaxFileBytes){throw 'EvidenceRecordExceedsLimit.'}
        $name=('icacls-{0:D2}.json' -f $index);$path=Join-Path $full $name
        $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        $manifestRows.Add([pscustomobject]@{Name=$name;Path=[string]$run.Path;Bytes=$bytes.Length;Sha256=(Get-F2IcaclsSha256 -Bytes $bytes)})
    }
    $allTargets=@($Runs.Path|Sort-Object -Unique)
    $complete=($allTargets.Count -eq 11 -and @(Compare-Object $targetSet $allTargets).Count -eq 0 -and $Runs.Count -ge 11 -and $Comparisons.Count -eq 11)
    $commandsSuccessful=(@($Runs|Where-Object{$_.Result.ExitCode -ne 0 -or -not $_.Result.OutputComplete -or -not $_.Result.CleanupComplete -or $_.Result.TimedOut -or $_.Result.Truncated}).Count -eq 0)
    $allComparisonsPass=(@($Comparisons|Where-Object{$_.Classification -ne 'PASS'}).Count -eq 0)
    $manifest=[pscustomobject]@{Schema='f2-icacls-evidence-v1';Complete=$complete;AllCommandsSuccessful=$commandsSuccessful;AllComparisonsPass=$allComparisonsPass;OwnerSid=$OwnerSid;ProjectVolumeGuid=$ProjectVolumeGuid;EvidenceVolumeGuid=$EvidenceVolumeGuid;TargetCount=$targetSet.Count;RunCount=$Runs.Count;ComparisonCount=$Comparisons.Count;Results=$manifestRows.ToArray();Comparisons=@($Comparisons);CreatedUtc=[DateTime]::UtcNow.ToString('o')}
    $manifestBytes=[Text.UTF8Encoding]::new($false).GetBytes(($manifest|ConvertTo-Json -Depth 14))
    if($manifestBytes.Length -gt $MaxFileBytes){throw 'EvidenceManifestExceedsLimit.'}
    $manifestPath=Join-Path $full 'integrity.json';$manifestStream=[IO.File]::Open($manifestPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$manifestStream.Write($manifestBytes,0,$manifestBytes.Length);$manifestStream.Flush($true)}finally{$manifestStream.Dispose()}
    return [pscustomobject]@{Complete=$complete;Directory=$full;IntegritySha256=(Get-F2IcaclsSha256 -Bytes $manifestBytes);TargetCount=$targetSet.Count;RunCount=$Runs.Count;ComparisonCount=$Comparisons.Count;IntegrityPath=$manifestPath}
}

Export-ModuleMember -Function Get-F2IcaclsExpectedPaths,Get-F2IcaclsExpectedMailboxPath,Get-F2IcaclsSha256,Get-F2IcaclsFileSha256,Read-F2IcaclsBaselineEvidence,Test-F2IcaclsSourcePins,Test-F2IcaclsPreflight,Get-F2IcaclsRightMask,ConvertFrom-F2IcaclsText,Get-F2IcaclsComparison,Test-F2IcaclsAccessDenied,Get-F2IcaclsCommandSpec,Invoke-F2IcaclsObject,Invoke-F2IcaclsPlan,Write-F2IcaclsEvidencePackage,Test-F2IcaclsMailboxEvidenceDirectory

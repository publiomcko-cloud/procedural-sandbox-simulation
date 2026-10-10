Set-StrictMode -Version Latest

$script:F2IcaclsVmId = '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1'
$script:F2IcaclsVmName = 'F2-G1-Isolated-Disposable'
$script:F2IcaclsDiskSerial = '152D20337A0C'
$script:F2IcaclsDiskModel = 'KINGSTON SA400S37240G'
$script:F2IcaclsReviewedCollectorBaseSha = 'a62773f0553dff4a05055b18fa10834f7488ae55'
$script:F2IcaclsProjectRoot = 'G:\F2-G1-Isolated-Disposable'
$script:F2IcaclsMaxOutputBytes = 262144
$script:F2IcaclsVolumeResolver = $null

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

function Read-F2IcaclsBaselineEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EvidenceDirectory,[Parameter(Mandatory)][string]$ExpectedCaptureId,[Parameter(Mandatory)][string]$ExpectedOwnerSid)
    try {
        $directory=[IO.Path]::GetFullPath($EvidenceDirectory)
        Test-F2AclNoReparseAncestors -Path $directory | Out-Null
        $secure=Test-F2AclRestrictedDirectory -Path $directory -OwnerSid $ExpectedOwnerSid
        if(-not $secure.Protected){throw 'EvidenceDirectoryDaclInvalid.'}
        $integrityPath=Join-Path $directory 'integrity.json'
        $payloadPath=Join-Path $directory 'acl-baseline.json'
        foreach($path in @($integrityPath,$payloadPath)){
            $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.PSIsContainer){throw 'EvidenceFileTypeInvalid.'}
        }
        $integrityBytes=[IO.File]::ReadAllBytes($integrityPath)
        $integrity=[Text.Encoding]::UTF8.GetString($integrityBytes)|ConvertFrom-Json -ErrorAction Stop
        if($integrity.Schema -cne 'f2-acl-integrity-v1' -or $integrity.PayloadFile -cne 'acl-baseline.json' -or $integrity.ProjectVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $integrity.EvidenceVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$'){throw 'IntegrityManifestIdentityInvalid.'}
        $payload=[IO.File]::ReadAllBytes($payloadPath)
        $payloadHash=Get-F2IcaclsSha256 -Bytes $payload
        if($integrity.PayloadBytes -ne $payload.Length -or -not [string]::Equals([string]$integrity.PayloadSha256,$payloadHash,[StringComparison]::OrdinalIgnoreCase)){throw 'BaselinePayloadIntegrityMismatch.'}
        $baseline=[Text.Encoding]::UTF8.GetString($payload)|ConvertFrom-Json -ErrorAction Stop
        if($baseline.CaptureId -cne $ExpectedCaptureId -or $baseline.Complete -ne $true){throw 'BaselineCaptureIdentityOrCompletenessInvalid.'}
        return [pscustomobject]@{Pass=$true;Baseline=$baseline;Integrity=$integrity;PayloadSha256=$payloadHash;IntegritySha256=(Get-F2IcaclsSha256 -Bytes $integrityBytes);ErrorCode=$null}
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
        [Parameter(Mandatory)][string]$ActualCommitSha
    )
    try {
        if($ExpectedCommitSha -notmatch '^[0-9a-f]{40}$' -or $ActualCommitSha -cne $ExpectedCommitSha){throw 'ReviewedCommitMismatch.'}
        $root=[IO.Path]::GetFullPath($RepositoryRoot)
        $pinPath=Join-Path $root 'scripts\f2-acl\F2_ICACLS_SOURCE_PINS.json'
        $pinsBytes=[IO.File]::ReadAllBytes($pinPath)
        $pinsHash=Get-F2IcaclsSha256 -Bytes $pinsBytes
        if($ExpectedPinManifestSha256 -notmatch '^[0-9a-f]{64}$' -or -not [string]::Equals($pinsHash,$ExpectedPinManifestSha256,[StringComparison]::OrdinalIgnoreCase)){throw 'PinManifestDigestMismatch.'}
        $pins=[Text.Encoding]::UTF8.GetString($pinsBytes)|ConvertFrom-Json -ErrorAction Stop
        if($pins.Schema -cne 'f2-icacls-corroboration-pins-v1' -or $pins.ReviewedCollectorBaseSha -cne $script:F2IcaclsReviewedCollectorBaseSha){throw 'PinManifestSchemaOrBaseInvalid.'}
        $modulePath=Join-Path $root 'scripts\f2-acl\F2AclIcacls.Corroboration.psm1'
        $capturePath=Join-Path $root 'scripts\f2-acl\Invoke-F2AclReadOnlyCapture.ps1'
        $protocolPath=Join-Path $root 'scripts\f2-acl\F2AclCapture.Protocol.psm1'
        $moduleHash=Get-F2IcaclsFileSha256 -Path $modulePath
        $captureHash=Get-F2IcaclsFileSha256 -Path $capturePath
        $protocolHash=Get-F2IcaclsFileSha256 -Path $protocolPath
        if($pins.CorroborationModuleSha256 -cne $moduleHash -or $pins.CollectorScriptSha256 -cne $captureHash -or $pins.ProtocolModuleSha256 -cne $protocolHash -or $Integrity.CollectorScriptSha256 -cne $captureHash -or $Integrity.ProtocolModuleSha256 -cne $protocolHash){throw 'SourcePinOrBaselineProvenanceMismatch.'}
        return [pscustomobject]@{Pass=$true;CommitSha=$ActualCommitSha;PinManifestSha256=$pinsHash;CorroborationModuleSha256=$moduleHash;CollectorScriptSha256=$captureHash;ProtocolModuleSha256=$protocolHash;ErrorCode=$null}
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
    $storagePass = ($storage.Win32MatchCount -eq 1 -and $storage.DiskMatchCount -eq 1 -and $storage.PhysicalMatchCount -eq 1 -and $storage.Win32Serial -eq $script:F2IcaclsDiskSerial -and $storage.DiskSerial -eq $script:F2IcaclsDiskSerial -and $storage.PhysicalSerial -eq $script:F2IcaclsDiskSerial -and $storage.Win32Model -ceq 'KINGSTON  SA400S37240G USB Device' -and $storage.DiskFriendlyName -ceq $script:F2IcaclsDiskModel -and $storage.DiskModel -ceq ' SA400S37240G   ' -and $storage.BusType -ceq 'USB' -and $storage.DiskHealth -ceq 'Healthy' -and $storage.PhysicalHealth -ceq 'Healthy' -and $storage.DiskOperationalStatus -ceq 'Online' -and $storage.DiskNumber -is [int] -and $storage.DiskNumber -ge 0 -and $storage.PartitionDiskNumber -is [int] -and $storage.Win32Index -is [int] -and $storage.PartitionDiskNumber -eq $storage.DiskNumber -and $storage.Win32Index -eq $storage.DiskNumber -and $storage.GDriveLetter -ceq 'G:' -and $storage.VolumeFileSystem -ceq 'NTFS' -and [string]::Equals([string]$storage.GVolumeGuid.TrimEnd('\'),$projectGuid.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase))
    & $add 'KingstonIdentityAndGMapping' $storagePass 'Unique serial/model/USB/health checks and G: volume mapping must all agree.'

    $pathChecks = @($Observation.PathChecks)
    $safePaths = ($pathChecks.Count -eq 11 -and @($pathChecks | Where-Object { $_.Exists -ne $true -or $_.ReparsePoint -ne $false -or $_.ParentChainClear -ne $true -or -not [string]::Equals([string]$_.Path,[IO.Path]::GetFullPath([string]$_.Path),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFullPath([string]$_.Path) -notin $expectedPaths }).Count -eq 0 -and @($pathChecks.Path | Sort-Object -Unique).Count -eq 11)
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
        F=[uint32]0x001F01FF; M=[uint32]0x001301BF; RX=[uint32]0x001200A9; R=[uint32]0x00120089; W=[uint32]0x00120116; D=[uint32]0x00010000
        AD=[uint32]0x00000002; AS=[uint32]0x00000004; WD=[uint32]0x00000002; DC=[uint32]0x00000040; X=[uint32]0x00000020
        RA=[uint32]0x00000200; REA=[uint32]0x00000200; WA=[uint32]0x00000100; WEA=[uint32]0x00000010; EA=[uint32]0x00000008
        RC=[uint32]0x00020000; WDAC=[uint32]0x00040000; WO=[uint32]0x00080000
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
    $pathSeen=$false
    foreach($line in $lines){
        if(-not $pathSeen){if([string]::Equals($line.TrimEnd(),$ExpectedPath,[StringComparison]::OrdinalIgnoreCase)){$pathSeen=$true;continue};if($line -match '^(Successfully processed|processed successfully|No mapping between account names and security IDs was done)'){continue};$pathSeen=$true}
        if($line -match '^\s*(?<principal>.+?):(?<codes>(?:\([^)]+\))+?)\s*$'){
            $principal=$Matches.principal.Trim();$codes=@([regex]::Matches($Matches.codes,'\((?<c>[^)]+)\)')|ForEach-Object{$_.Groups['c'].Value})
            if($principal -match '^S-1-'){ $sid=$principal } else { try{$sid=([Security.Principal.NTAccount]::new($principal)).Translate([Security.Principal.SecurityIdentifier]).Value}catch{$unsupported.Add('UnresolvedPrincipal');continue} }
            $aceType='Allow';$flags=New-Object 'System.Collections.Generic.List[string]';$rights=New-Object 'System.Collections.Generic.List[string]'
            foreach($code in $codes){switch -CaseSensitive ($code){'I' {$flags.Add('Inherited')};'OI' {$flags.Add('ObjectInherit')};'CI' {$flags.Add('ContainerInherit')};'IO' {$flags.Add('InheritOnly')};'NP' {$flags.Add('NoPropagateInherit')};'DENY' {$aceType='Deny'};default {$rights.Add($code)}}}
            $mask=Get-F2IcaclsRightMask -Rights $rights.ToArray()
            if(-not $mask.Supported){$unsupported.Add('UnsupportedRight');continue}
            $aces.Add([pscustomobject]@{Sid=$sid;Type=$aceType;Mask=$mask.Mask;Flags=@($flags.ToArray()|Sort-Object -Unique)})
        } elseif($line -match 'Successfully processed|processed successfully|failed processing|failed to process'){continue}
        else {$unsupported.Add('UnparsedAclLine')}
    }
    return [pscustomobject]@{PathMatched=$pathSeen;Aces=$aces.ToArray();Unsupported=$unsupported.ToArray()}
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
        $expected+=@(([string]$a.Sid+'|'+[string]$a.Type+'|'+$mask+'|'+(@($flags|Sort-Object -Unique)-join ',')))
    }
    $actual=@($parsed.Aces|ForEach-Object{[string]$_.Sid+'|'+[string]$_.Type+'|'+[uint32]$_.Mask+'|'+(@($_.Flags|Sort-Object -Unique)-join ',')})
    $diff=@(Compare-Object ($expected|Sort-Object) ($actual|Sort-Object))
    if($diff.Count -eq 0 -and $expected.Count -eq $actual.Count){return [pscustomobject]@{Classification='PASS';Reason='AllParsedAcesMatch';Path=[string]$BaselineRecord.Path}}
    return [pscustomobject]@{Classification='MISMATCH';Reason='ParsedAceSetDiffers';Path=[string]$BaselineRecord.Path}
}

function Invoke-F2IcaclsProcessCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FilePath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Arguments,
        [ValidateRange(1,120)][int]$TimeoutSeconds=15,
        [ValidateRange(1,5000)][int]$CleanupGraceMilliseconds=1000,
        [ValidateRange(1,5000)][int]$DrainGraceMilliseconds=1000,
        [ValidateRange(1024,1048576)][int]$MaxBytesPerStream=$script:F2IcaclsMaxOutputBytes
    )

    $result=[ordered]@{Started=$false;ProcessId=$null;ExitCode=$null;TimedOut=$false;CleanupComplete=$true;OutputComplete=$false;Truncated=$false;Stdout='';Stderr='';StdoutBytes=0;StderrBytes=0;StdoutSha256=$null;StderrSha256=$null;ReaderError=$null;ElapsedMilliseconds=0}
    $clock=[Diagnostics.Stopwatch]::StartNew();$process=$null;$outSource=$null;$errSource=$null
    $capture=[hashtable]::Synchronized(@{Out=(New-Object Text.StringBuilder);Err=(New-Object Text.StringBuilder);OutBytes=0L;ErrBytes=0L;OutEof=$false;ErrEof=$false;Overflow=$false;OutError=$false;ErrError=$false})
    try {
        $startInfo=New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName=$FilePath;$startInfo.Arguments=$Arguments;$startInfo.UseShellExecute=$false;$startInfo.CreateNoWindow=$true;$startInfo.RedirectStandardOutput=$true;$startInfo.RedirectStandardError=$true
        $process=New-Object Diagnostics.Process;$process.StartInfo=$startInfo
        if(-not $process.Start()){throw 'IcaclsChildStartReturnedFalse.'}
        $result.Started=$true;$result.ProcessId=[int]$process.Id
        $eventAction={
            $state=$event.MessageData
            $shared=$state.Shared
            try {
                $line=$event.SourceEventArgs.Data
                if($null -eq $line){$shared[$state.EofKey]=$true;return}
                $text=$line+[Environment]::NewLine;$bytes=[Text.Encoding]::UTF8.GetByteCount($text)
                if(($shared[$state.BytesKey]+$bytes) -le $state.Limit){[void]$state.Builder.Append($text)}else{$state.Overflow=$true}
                $shared[$state.BytesKey]+=$bytes
            } catch {$state.Error=$true}
        }
        $outSource='F2IcaclsOut-'+[guid]::NewGuid().ToString('N');$errSource='F2IcaclsErr-'+[guid]::NewGuid().ToString('N')
        $outState=[hashtable]::Synchronized(@{Shared=$capture;Builder=$capture.Out;BytesKey='OutBytes';EofKey='OutEof';Limit=$MaxBytesPerStream;Overflow=$false;Error=$false})
        $errState=[hashtable]::Synchronized(@{Shared=$capture;Builder=$capture.Err;BytesKey='ErrBytes';EofKey='ErrEof';Limit=$MaxBytesPerStream;Overflow=$false;Error=$false})
        Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -SourceIdentifier $outSource -MessageData $outState -Action $eventAction | Out-Null
        Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -SourceIdentifier $errSource -MessageData $errState -Action $eventAction | Out-Null
        $process.BeginOutputReadLine();$process.BeginErrorReadLine()
        $deadline=[int64]$TimeoutSeconds*1000
        while($true){
            $hasExited=[bool]$process.HasExited
            $streamsDone=($capture.OutEof -and $capture.ErrEof)
            if($hasExited -and $streamsDone){break}
            $remaining=$deadline-[int64]$clock.ElapsedMilliseconds
            if($remaining -le 0){$result.TimedOut=$true;break}
            Wait-Event -SourceIdentifier $outSource -Timeout 0.01 | Out-Null
            Wait-Event -SourceIdentifier $errSource -Timeout 0.01 | Out-Null
            $sleep=[int][Math]::Min(20,$remaining)
            if($sleep -gt 0){Start-Sleep -Milliseconds $sleep}
        }
        if($result.TimedOut -and -not $process.HasExited){
            try{$process.Kill()}catch{$result.CleanupComplete=$false;$result.ReaderError='ChildTerminationFailed'}
            try{if(-not $process.WaitForExit($CleanupGraceMilliseconds)){$result.CleanupComplete=$false}}catch{$result.CleanupComplete=$false;$result.ReaderError='ChildTerminationWaitFailed'}
        }
        $remainingDrain=[int][Math]::Max(0,[Math]::Min($DrainGraceMilliseconds,($deadline-[int64]$clock.ElapsedMilliseconds)))
        $drainClock=[Diagnostics.Stopwatch]::StartNew()
        while(((-not $capture.OutEof) -or (-not $capture.ErrEof)) -and $drainClock.ElapsedMilliseconds -lt $remainingDrain){Wait-Event -SourceIdentifier $outSource -Timeout 0.01 | Out-Null;Wait-Event -SourceIdentifier $errSource -Timeout 0.01 | Out-Null}
        $drainClock.Stop()
        if(-not $capture.OutEof -or -not $capture.ErrEof){$result.OutputComplete=$false;$result.CleanupComplete=$false;$result.ReaderError='RedirectedStreamDrainDeadlineExceeded'}
        if($process.HasExited){$result.ExitCode=[int]$process.ExitCode}
        $result.Stdout=[string]$capture.Out.ToString();$result.Stderr=[string]$capture.Err.ToString()
        $result.StdoutBytes=[long]$capture.OutBytes;$result.StderrBytes=[long]$capture.ErrBytes
        if($outState.Overflow -or $errState.Overflow){$result.Truncated=$true;$result.CleanupComplete=$false;$result.ReaderError='OutputLimitExceeded'}
        if($outState.Error -or $errState.Error){$result.CleanupComplete=$false;$result.ReaderError='OutputCaptureCallbackFailed'}
        $stdoutUtf8=[Text.Encoding]::UTF8.GetBytes($result.Stdout);$stderrUtf8=[Text.Encoding]::UTF8.GetBytes($result.Stderr)
        $result.StdoutSha256=Get-F2IcaclsSha256 -Bytes $stdoutUtf8;$result.StderrSha256=Get-F2IcaclsSha256 -Bytes $stderrUtf8
        if(-not $result.TimedOut -and $result.CleanupComplete -and $process.HasExited -and $capture.OutEof -and $capture.ErrEof -and -not $outState.Overflow -and -not $errState.Overflow -and -not $outState.Error -and -not $errState.Error){$result.OutputComplete=$true}
    }
    catch{$result.ReaderError=if($null -eq $result.ReaderError){$_.Exception.GetType().Name+': '+$_.Exception.Message}else{$result.ReaderError};$result.CleanupComplete=$false}
    finally{
        if($null -ne $process){
            try{if(-not $process.HasExited){$process.Kill();if(-not $process.WaitForExit($CleanupGraceMilliseconds)){$result.CleanupComplete=$false}}}catch{$result.CleanupComplete=$false}
            try{$process.CancelOutputRead()}catch{}
            try{$process.CancelErrorRead()}catch{}
            try{$process.Dispose()}catch{$result.CleanupComplete=$false}
        }
        foreach($source in @($outSource,$errSource)){if($source){try{Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue;Get-Job -Name $source -ErrorAction SilentlyContinue|Remove-Job -Force -ErrorAction SilentlyContinue}catch{$result.CleanupComplete=$false}}}
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
    $exe=Join-Path $env:SystemRoot 'System32\icacls.exe'
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
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$OwnerSid,[Parameter(Mandatory)][string[]]$Targets,[Parameter(Mandatory)][object[]]$Runs,[Parameter(Mandatory)][object[]]$Comparisons,[Parameter(Mandatory)][string]$ProjectVolumePath,[Parameter(Mandatory)][string]$ProjectVolumeGuid,[Parameter(Mandatory)][string]$EvidenceVolumeGuid,[ValidateRange(1024,1048576)][int]$MaxFileBytes=524288)
    $full=[IO.Path]::GetFullPath($Directory)
    if(-not [IO.Directory]::Exists($full)){throw 'EvidenceDirectoryMissing.'}
    if($OwnerSid -notmatch '^S-1-'){throw 'EvidenceDirectoryOwnerSidInvalid.'}
    Test-F2AclNoReparseAncestors -Path $full | Out-Null
    $secureDirectory=Test-F2AclRestrictedDirectory -Path $full -OwnerSid $OwnerSid
    if(-not $secureDirectory.Protected){throw 'EvidenceDirectoryAclNotVerified.'}
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'EvidenceDirectoryIsReparsePoint.'}
    $actualEvidenceVolume=Get-F2IcaclsVolumeGuid -Path $full
    $actualProjectVolume=Get-F2IcaclsVolumeGuid -Path $ProjectVolumePath
    if(-not [string]::Equals($actualProjectVolume,$ProjectVolumeGuid,[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals($actualEvidenceVolume,$EvidenceVolumeGuid,[StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($actualEvidenceVolume,$actualProjectVolume,[StringComparison]::OrdinalIgnoreCase)){throw 'EvidenceVolumeIdentityOrSeparationFailed.'}
    $targetSet=@($Targets|Sort-Object -Unique)
    $runPaths=@($Runs.Path|Sort-Object -Unique);$comparisonPaths=@($Comparisons.Path|Sort-Object -Unique)
    if($targetSet.Count -ne 11 -or $runPaths.Count -ne 11 -or @(Compare-Object $targetSet $runPaths).Count -ne 0 -or $comparisonPaths.Count -ne 11 -or @(Compare-Object $targetSet $comparisonPaths).Count -ne 0 -or $Comparisons.Count -ne 11){throw 'EvidencePackageTargetCompletenessFailed.'}
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
        $manifestRows.Add([pscustomobject]@{Name=$name;Bytes=$bytes.Length;Sha256=(Get-F2IcaclsSha256 -Bytes $bytes)})
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

Export-ModuleMember -Function Get-F2IcaclsExpectedPaths,Get-F2IcaclsSha256,Get-F2IcaclsFileSha256,Read-F2IcaclsBaselineEvidence,Test-F2IcaclsSourcePins,Test-F2IcaclsPreflight,Get-F2IcaclsRightMask,ConvertFrom-F2IcaclsText,Get-F2IcaclsComparison,Test-F2IcaclsAccessDenied,Get-F2IcaclsCommandSpec,Invoke-F2IcaclsObject,Invoke-F2IcaclsPlan,Write-F2IcaclsEvidencePackage

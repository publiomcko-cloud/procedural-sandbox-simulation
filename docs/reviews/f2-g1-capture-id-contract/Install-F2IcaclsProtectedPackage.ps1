Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2InstallReviewedCommit = '5741ffe90a3abd02a08563e6431e8a0b9b63eeb1'
$script:F2InstallBaselineMailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:F2InstallBaselinePayloadCaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:F2InstallBaselinePayloadSha256 = '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
$script:F2InstallBaselineIntegritySha256 = '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
$script:F2InstallSourcePinsSha256 = 'bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7'
$script:F2InstallMaxSourceBytes = 1048576

$script:F2InstallFiles = [ordered]@{
    'F2AclCapture.Protocol.psm1' = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1' = 'a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1' = '950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5'
    'Invoke-F2IcaclsCapture.ps1' = 'fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0'
    'Invoke-F2IcaclsProtectedCoordinator.ps1' = '3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2'
    'F2_ICACLS_SOURCE_PINS.json' = 'bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7'
    'Invoke-F2AclReadOnlyCapture.ps1' = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}

$script:F2InstallAdminSid = 'S-1-5-32-544'
$script:F2InstallSystemSid = 'S-1-5-18'
$script:F2InstallUsersSid = 'S-1-5-11'
$script:F2InstallTrustedInstallerSid = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
$script:F2InstallReparseProvider = $null

function Get-F2InstallHashBytes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-F2InstallFileBytes {
    param([Parameter(Mandatory)][string]$Path,[int]$MaxBytes=$script:F2InstallMaxSourceBytes)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -lt 1 -or $item.Length -gt $MaxBytes) { throw 'INSTALL_SOURCE_FILE_TYPE_OR_SIZE' }
    $stream = [IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes,$offset,$bytes.Length-$offset)
            if ($read -le 0) { throw 'INSTALL_SOURCE_SHORT_READ' }
            $offset += $read
        }
        return ,$bytes
    } finally { $stream.Dispose() }
}

function Get-F2InstallFileSddl {
    param([Parameter(Mandatory)][string]$Path)
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    return $acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access)
}

function Get-F2InstallExpectedSddl {
    param([Parameter(Mandatory)][ValidateSet('Directory','File')][string]$Kind)
    $admin = if ($script:F2InstallAdminSid -eq 'S-1-5-32-544') { 'BA' } else { $script:F2InstallAdminSid }
    if ($Kind -eq 'Directory') { return ('O:{0}D:P(A;OICI;FA;;;SY)(A;OICI;0x001200A9;;;AU)(A;OICI;FA;;;{0})' -f $admin) }
    return ('O:{0}D:P(A;;FA;;;SY)(A;;0x001200A9;;;AU)(A;;FA;;;{0})' -f $admin)
}

function Test-F2InstallExactDacl {
    param([Parameter(Mandatory)][string]$Sddl,[Parameter(Mandatory)][ValidateSet('Directory','File')][string]$Kind)
    try {
        $raw = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
        if ($raw.Owner.Value -cne $script:F2InstallAdminSid -or $null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0) { return $false }
        $expectedFlags = if ($Kind -eq 'Directory') { [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit } else { 0 }
        $expected = @{
            $script:F2InstallSystemSid = [uint32]0x001F01FF
            $script:F2InstallAdminSid = [uint32]0x001F01FF
            $script:F2InstallUsersSid = [uint32]0x001200A9
        }
        $aces = @($raw.DiscretionaryAcl)
        if ($aces.Count -ne 3) { return $false }
        $seen = @{}
        foreach ($ace in $aces) {
            $sid = $ace.SecurityIdentifier.Value
            if (-not $expected.ContainsKey($sid) -or $seen.ContainsKey($sid) -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed) { return $false }
            $mask = [uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
            if ($mask -ne $expected[$sid] -or [int]$ace.AceFlags -ne $expectedFlags) { return $false }
            $seen[$sid] = $true
        }
        return ($seen.Count -eq 3)
    } catch { return $false }
}

function Test-F2InstallSafeParentSddl {
    param([Parameter(Mandatory)][string]$Sddl,[switch]$AllowProgramDataCreateMask,[switch]$AllowSystemDriveRootAddSubdirectoryMask)
    try { $raw = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl) } catch { return $false }
    if ($null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0 -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $raw.Owner.Value -notin @($script:F2InstallSystemSid,$script:F2InstallAdminSid,$script:F2InstallTrustedInstallerSid)) { return $false }
    $danger = [long]0x00000002 -bor 0x00000004 -bor 0x00000010 -bor 0x00000040 -bor 0x00000100 -bor 0x00010000 -bor 0x00040000 -bor 0x00080000 -bor 0x40000000 -bor 0x10000000
    $safeReadExecute=[long]0x001200A9
    $rootCreateAceCount=0
    $rootInheritedAceCount=0
    $programDataCreateAceCount=0
    foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed) { continue }
        $sid = $ace.SecurityIdentifier.Value
        $mask = [long]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        $isInheritOnly=([int]$ace.AceFlags -band [int][Security.AccessControl.AceFlags]::InheritOnly) -ne 0
        if ($isInheritOnly) {
            if (-not $AllowSystemDriveRootAddSubdirectoryMask) { continue }
            if ($sid -in @($script:F2InstallSystemSid,$script:F2InstallAdminSid,$script:F2InstallTrustedInstallerSid)) { continue }
            $observedRootInheritedFlags=[int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit -bor [int][Security.AccessControl.AceFlags]::InheritOnly
            if ($AllowSystemDriveRootAddSubdirectoryMask -and $sid -eq 'S-1-5-11' -and $mask -eq 3758161920 -and [int]$ace.AceFlags -eq $observedRootInheritedFlags) { $rootInheritedAceCount++; continue }
            if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
            continue
        }
        if ($sid -in @($script:F2InstallSystemSid,$script:F2InstallAdminSid,$script:F2InstallTrustedInstallerSid)) { continue }
        if ($AllowSystemDriveRootAddSubdirectoryMask -and $sid -eq 'S-1-5-11' -and $mask -eq 0x00000004 -and [int]$ace.AceFlags -eq 0) { $rootCreateAceCount++; continue }
        if ($AllowProgramDataCreateMask -and $sid -eq 'S-1-5-32-545' -and $mask -eq 0x116 -and [int]$ace.AceFlags -eq [int][Security.AccessControl.AceFlags]::ContainerInherit) { $programDataCreateAceCount++; continue }
        if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
    }
    if ($AllowSystemDriveRootAddSubdirectoryMask -and $rootCreateAceCount -ne 1) { return $false }
    if ($AllowSystemDriveRootAddSubdirectoryMask -and $rootInheritedAceCount -ne 1) { return $false }
    if ($AllowProgramDataCreateMask -and $programDataCreateAceCount -ne 1) { return $false }
    return $true
}

function Test-F2InstallNoReparseChain {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $current = $full
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $isReparse=if($null -ne $script:F2InstallReparseProvider){[bool](& $script:F2InstallReparseProvider $current)}else{$item=Get-Item -LiteralPath $current -Force -ErrorAction Stop;(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0)}
            if ($isReparse) { throw 'INSTALL_REPARSE_POINT' }
        }
        $root = [IO.Path]::GetPathRoot($current)
        if ([string]::Equals($current.TrimEnd(''),$root.TrimEnd(''),[StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw 'INSTALL_PATH_PARENT_UNKNOWN' }
        $current = $parent.FullName
    }
    return $true
}

function New-F2InstallDirectorySecurity {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetSecurityDescriptorSddlForm((Get-F2InstallExpectedSddl -Kind Directory))
    return $acl
}

function New-F2InstallFileSecurity {
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetSecurityDescriptorSddlForm((Get-F2InstallExpectedSddl -Kind File))
    return $acl
}

function Get-F2InstallSanitizedAces {
    param([Parameter(Mandatory)][ValidateSet('Directory','File')][string]$Kind)
    $flags=if($Kind -eq 'Directory'){'ObjectInherit,ContainerInherit'}else{'None'}
    return @(
        [pscustomobject]@{Sid=$script:F2InstallSystemSid;Principal='SYSTEM';Type='Allow';AccessMask='0x001F01FF';InheritanceFlags=$flags;PropagationFlags='None';Inherited=$false}
        [pscustomobject]@{Sid=$script:F2InstallAdminSid;Principal='AdministratorOwner';Type='Allow';AccessMask='0x001F01FF';InheritanceFlags=$flags;PropagationFlags='None';Inherited=$false}
        [pscustomobject]@{Sid=$script:F2InstallUsersSid;Principal='AuthenticatedUsers';Type='Allow';AccessMask='0x001200A9';InheritanceFlags=$flags;PropagationFlags='None';Inherited=$false}
    )
}

function New-F2InstallSecureDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) { throw 'INSTALL_CREATE_NEW_DIRECTORY_COLLISION' }
    $parent = Split-Path -Parent $Path
    Test-F2InstallNoReparseChain -Path $parent | Out-Null
    [void][IO.Directory]::CreateDirectory($Path,(New-F2InstallDirectorySecurity))
    if (-not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $Path) -Kind Directory)) { throw 'INSTALL_CREATED_DIRECTORY_ACL_MISMATCH' }
}

function Write-F2InstallCreateNewFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][byte[]]$Bytes)
    $stream = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $stream.Write($Bytes,0,$Bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    Set-Acl -LiteralPath $Path -AclObject (New-F2InstallFileSecurity) -ErrorAction Stop
    if (-not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $Path) -Kind File)) { throw 'INSTALL_CREATED_FILE_ACL_MISMATCH' }
}

function Get-F2InstallExpectedPaths {
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $vmId = '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1'.ToUpperInvariant()
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\')
    $config = [IO.Path]::Combine($root,'F2-G1-Isolated-Disposable')
    $configVirtualMachines = [IO.Path]::Combine($config,'Virtual Machines')
    $configVm = [IO.Path]::Combine($configVirtualMachines,$vmId)
    $virtualMachines = [IO.Path]::Combine($root,'Virtual Machines')
    return @($root,$config,$configVirtualMachines,$configVm,($configVm+'.vmcx'),($configVm+'.vmgs'),($configVm+'.VMRS'),([IO.Path]::Combine($root,'F2-G1-OS.vhdx')),([IO.Path]::Combine($root,'F2-G1-Scratch.vhdx')),$virtualMachines,([IO.Path]::Combine($virtualMachines,$vmId)))
}

function Read-F2InstallBaseline {
    param([Parameter(Mandatory)]$Context)
    $dir = $Context.BaselineDirectory
    Test-F2InstallNoReparseChain -Path $dir | Out-Null
    if ($Context.BaselineMailboxId -cne $script:F2InstallBaselineMailboxId -or $Context.BaselinePayloadCaptureId -cne $script:F2InstallBaselinePayloadCaptureId) { throw 'BASELINE_MAILBOX_OR_PAYLOAD_CAPTURE_PIN_MISMATCH' }
    $expected = Join-Path $Context.CommonApplicationData ('F2-G1-ACL-Evidence-' + $Context.BaselineMailboxId)
    if (-not [string]::Equals([IO.Path]::GetFullPath($dir),[IO.Path]::GetFullPath($expected),[StringComparison]::OrdinalIgnoreCase)) { throw 'BASELINE_DIRECTORY_SCOPE_MISMATCH' }
    $requesterSid = [string]$Context.RequesterSid
    if ($requesterSid -notmatch '^S-1-') { throw 'BASELINE_REQUESTER_IDENTITY_UNKNOWN' }
    $dacl = [Security.AccessControl.RawSecurityDescriptor]::new((Get-F2InstallFileSddl -Path $dir))
    $expectedMailbox = @{$script:F2InstallSystemSid=[uint32]0x001F01FF;$script:F2InstallAdminSid=[uint32]0x001F01FF;'S-1-3-4'=[uint32]0x001200A9;$requesterSid=[uint32]0x001200A9}
    $seen=@{}
    if ($dacl.Owner.Value -cne $script:F2InstallAdminSid -or ($dacl.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or @($dacl.DiscretionaryAcl).Count -ne 4) { throw 'BASELINE_MAILBOX_ACL_INVALID' }
    foreach ($ace in $dacl.DiscretionaryAcl) {
        $sid=$ace.SecurityIdentifier.Value
        $mask=[uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        $flags=[int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
        if (-not $expectedMailbox.ContainsKey($sid) -or $seen.ContainsKey($sid) -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $mask -ne $expectedMailbox[$sid] -or [int]$ace.AceFlags -ne $flags) { throw 'BASELINE_MAILBOX_ACE_INVALID' }
        $seen[$sid]=$true
    }
    foreach ($name in @('acl-baseline.json','integrity.json')) { Test-F2InstallNoReparseChain -Path (Join-Path $dir $name) | Out-Null }
    $payload=Read-F2InstallFileBytes -Path (Join-Path $dir 'acl-baseline.json')
    $integrityBytes=Read-F2InstallFileBytes -Path (Join-Path $dir 'integrity.json')
    $payloadHash=Get-F2InstallHashBytes -Bytes $payload
    $integrityHash=Get-F2InstallHashBytes -Bytes $integrityBytes
    if ($payloadHash -cne $Context.BaselinePayloadSha256 -or $integrityHash -cne $Context.BaselineIntegritySha256) { throw 'BASELINE_PIN_MISMATCH' }
    $integrity=[Text.Encoding]::UTF8.GetString($integrityBytes)|ConvertFrom-Json -ErrorAction Stop
    $baseline=[Text.Encoding]::UTF8.GetString($payload)|ConvertFrom-Json -ErrorAction Stop
    $guidPattern='^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$'
    if ($integrity.Schema -cne 'f2-acl-integrity-v1' -or $integrity.PayloadFile -cne 'acl-baseline.json' -or [long]$integrity.PayloadBytes -ne $payload.Length -or $integrity.PayloadSha256 -cne $payloadHash -or $integrity.CollectorScriptSha256 -cne $script:F2InstallFiles['Invoke-F2AclReadOnlyCapture.ps1'] -or $integrity.ProtocolModuleSha256 -cne $script:F2InstallFiles['F2AclCapture.Protocol.psm1'] -or [string]$integrity.ProjectVolumeGuid -notmatch $guidPattern -or [string]$integrity.EvidenceVolumeGuid -notmatch $guidPattern -or [string]::Equals(([string]$integrity.ProjectVolumeGuid).TrimEnd('\'),([string]$integrity.EvidenceVolumeGuid).TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'BASELINE_INTEGRITY_DOCUMENT_INVALID' }
    if ($baseline.CaptureId -cne $Context.BaselinePayloadCaptureId -or $baseline.Complete -ne $true -or $baseline.VmId -cne '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1' -or $baseline.VmName -cne 'F2-G1-Isolated-Disposable' -or @($baseline.Records).Count -ne 11 -or $baseline.Manifest.ExpectedCount -ne 11) { throw 'BASELINE_PAYLOAD_IDENTITY_OR_COMPLETENESS_INVALID' }
    $targetPaths=@(Get-F2InstallExpectedPaths -ProjectRoot 'G:\F2-G1-Isolated-Disposable')
    $actualPaths=@($baseline.Records|ForEach-Object{[string]$_.Path})
    $manifestPaths=@($baseline.Manifest.ExpectedPaths|ForEach-Object{[string]$_})
    if (@($actualPaths|Sort-Object -Unique).Count -ne 11 -or @(Compare-Object ($targetPaths|Sort-Object) ($actualPaths|Sort-Object) -CaseSensitive).Count -ne 0 -or @($manifestPaths|Sort-Object -Unique).Count -ne 11 -or @(Compare-Object ($targetPaths|Sort-Object) ($manifestPaths|Sort-Object) -CaseSensitive).Count -ne 0) { throw 'BASELINE_PATH_SET_INVALID' }
    return [pscustomobject]@{MailboxId=$Context.BaselineMailboxId;PayloadCaptureId=$Context.BaselinePayloadCaptureId;PayloadSha256=$payloadHash;IntegritySha256=$integrityHash;PayloadBytes=$payload.Length;IntegrityBytes=$integrityBytes.Length}
}

function Get-F2InstallPackageBytes {
    param([Parameter(Mandatory)]$Context)
    $sourceAcl=Join-Path $Context.SourceRoot 'scripts\f2-acl'
    Test-F2InstallNoReparseChain -Path $sourceAcl | Out-Null
    $pinPath=Join-Path $sourceAcl 'F2_ICACLS_SOURCE_PINS.json'
    $pinBytes=Read-F2InstallFileBytes -Path $pinPath
    if ((Get-F2InstallHashBytes -Bytes $pinBytes) -cne $Context.SourcePinsSha256) { throw 'SOURCE_PIN_MANIFEST_HASH_MISMATCH' }
    $sourcePins=[Text.Encoding]::UTF8.GetString($pinBytes)|ConvertFrom-Json -ErrorAction Stop
    if ($sourcePins.Schema -cne 'f2-icacls-corroboration-pins-v1' -or $sourcePins.ReviewedCollectorBaseSha -cne 'a62773f0553dff4a05055b18fa10834f7488ae55') { throw 'SOURCE_PIN_MANIFEST_IDENTITY_INVALID' }
    $actual=@{}
    foreach ($name in $script:F2InstallFiles.Keys) {
        $bytes=Read-F2InstallFileBytes -Path (Join-Path $sourceAcl $name)
        $sha=Get-F2InstallHashBytes -Bytes $bytes
        if ($sha -cne $script:F2InstallFiles[$name]) { throw ('PACKAGE_SOURCE_HASH_MISMATCH:'+$name) }
        $actual[$name]=[pscustomobject]@{Bytes=$bytes;Sha256=$sha}
    }
    if ($sourcePins.CorroborationModuleSha256 -cne $actual['F2AclIcacls.Corroboration.psm1'].Sha256 -or $sourcePins.CollectorScriptSha256 -cne $actual['Invoke-F2AclReadOnlyCapture.ps1'].Sha256 -or $sourcePins.ProtocolModuleSha256 -cne $actual['F2AclCapture.Protocol.psm1'].Sha256 -or $sourcePins.RuntimeModuleSha256 -cne $actual['F2AclIcacls.Runtime.psm1'].Sha256 -or $sourcePins.LauncherScriptSha256 -cne $actual['Invoke-F2IcaclsCapture.ps1'].Sha256 -or $sourcePins.CoordinatorScriptSha256 -cne $actual['Invoke-F2IcaclsProtectedCoordinator.ps1'].Sha256) { throw 'SOURCE_PINS_DO_NOT_MATCH_PACKAGE' }
    return [pscustomobject]@{Files=$actual;PinsManifestSha256=$Context.SourcePinsSha256}
}

function New-F2InstallContext {
    return @{
        SourceRoot='C:\Dev\f2-g1-capture-id-contract-source'
        ProgramFilesParent='C:\Program Files'
        CommonApplicationData='C:\ProgramData'
        PackageFinal='C:\Program Files\F2-G1-Icacls'
        ReleaseDirectoryFinal='C:\ProgramData\F2-G1-Icacls'
        BaselineDirectory='C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df'
        BaselineMailboxId=$script:F2InstallBaselineMailboxId
        BaselinePayloadCaptureId=$script:F2InstallBaselinePayloadCaptureId
        BaselinePayloadSha256=$script:F2InstallBaselinePayloadSha256
        BaselineIntegritySha256=$script:F2InstallBaselineIntegritySha256
        SourcePinsSha256=$script:F2InstallSourcePinsSha256
        RequesterSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        ParentSddlProvider=$null
    }
}

function Test-F2InstallParentChain {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][string]$TargetParent)
    $current=[IO.Path]::GetFullPath($TargetParent)
    $pathRoot=[IO.Path]::GetPathRoot($current)
    while ($true) {
        Test-F2InstallNoReparseChain -Path $current | Out-Null
        $sddl=if($null -ne $Context.ParentSddlProvider){[string](& $Context.ParentSddlProvider $current)}else{Get-F2InstallFileSddl -Path $current}
        $isProgramData=[string]::Equals($current,[string]$Context.CommonApplicationData,[StringComparison]::OrdinalIgnoreCase)
        $isCanonicalSystemDriveRoot=[string]::Equals($current,'C:\',[StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($current.TrimEnd('\'),$pathRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)
        if (-not (Test-F2InstallSafeParentSddl -Sddl $sddl -AllowProgramDataCreateMask:$isProgramData -AllowSystemDriveRootAddSubdirectoryMask:$isCanonicalSystemDriveRoot)) { if ($isCanonicalSystemDriveRoot) { throw 'INSTALL_SYSTEM_DRIVE_ROOT_DACL_UNSAFE' } else { throw 'INSTALL_PARENT_DACL_UNSAFE' } }
        if ([string]::Equals($current.TrimEnd('\'),$pathRoot.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { break }
        $parent=[IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw 'INSTALL_PARENT_CHAIN_UNKNOWN' }
        $current=$parent.FullName
    }
}

function Invoke-F2InstallCore {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)
    $stage='Preflight';$packageStage=$null;$releaseStage=$null;$packagePublished=$false;$releasePublished=$false
    try {
        foreach ($path in @($Context.PackageFinal,$Context.ReleaseDirectoryFinal)) {
            if (-not [string]::Equals([IO.Path]::GetFullPath($path),$path,[StringComparison]::OrdinalIgnoreCase)) { throw 'INSTALL_TARGET_PATH_NOT_CANONICAL' }
            if (Test-Path -LiteralPath $path) { throw 'INSTALL_TARGET_ALREADY_EXISTS' }
        }
        Test-F2InstallParentChain -Context $Context -TargetParent $Context.ProgramFilesParent
        Test-F2InstallParentChain -Context $Context -TargetParent $Context.CommonApplicationData
        $baseline=Read-F2InstallBaseline -Context $Context
        $package=Get-F2InstallPackageBytes -Context $Context
        $stage='CreateStagingDirectories'
        $packageStage=Join-Path $Context.ProgramFilesParent ('.F2-G1-Icacls-stage-'+[guid]::NewGuid().ToString('N'))
        $releaseStage=Join-Path $Context.CommonApplicationData ('.F2-G1-Icacls-stage-'+[guid]::NewGuid().ToString('N'))
        New-F2InstallSecureDirectory -Path $packageStage
        New-F2InstallSecureDirectory -Path $releaseStage
        $scriptsStage=Join-Path $packageStage 'scripts';New-F2InstallSecureDirectory -Path $scriptsStage
        $aclStage=Join-Path $scriptsStage 'f2-acl';New-F2InstallSecureDirectory -Path $aclStage
        $stage='CopyCreateNewPackageFiles'
        foreach ($name in $script:F2InstallFiles.Keys) { Write-F2InstallCreateNewFile -Path (Join-Path $aclStage $name) -Bytes $package.Files[$name].Bytes }
        $release=[ordered]@{
            Schema='f2-icacls-runtime-release-v2'
            ReviewedCommitSha=$script:F2InstallReviewedCommit
            BaselineMailboxId=$Context.BaselineMailboxId
            BaselinePayloadCaptureId=$Context.BaselinePayloadCaptureId
            BaselinePayloadSha256=$baseline.PayloadSha256
            BaselineIntegritySha256=$baseline.IntegritySha256
            SourcePinsManifestSha256=$package.PinsManifestSha256
            Files=@(foreach($name in $script:F2InstallFiles.Keys){[pscustomobject]@{Name=$name;Sha256=$package.Files[$name].Sha256}})
        }
        $releaseBytes=[Text.UTF8Encoding]::new($false).GetBytes(($release|ConvertTo-Json -Compress -Depth 6))
        Write-F2InstallCreateNewFile -Path (Join-Path $releaseStage 'approved-release.json') -Bytes $releaseBytes
        $stage='PrePublishAttestation'
        foreach ($dir in @($packageStage,$scriptsStage,$aclStage,$releaseStage)) { if (-not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $dir) -Kind Directory)) { throw 'INSTALL_DIRECTORY_ATTESTATION_FAILED' } }
        foreach ($name in $script:F2InstallFiles.Keys) {
            $file=Join-Path $aclStage $name
            if ((Get-F2InstallHashBytes -Bytes (Read-F2InstallFileBytes -Path $file)) -cne $package.Files[$name].Sha256 -or -not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $file) -Kind File)) { throw 'INSTALL_PACKAGE_FILE_ATTESTATION_FAILED' }
        }
        $manifestStage=Join-Path $releaseStage 'approved-release.json'
        if (-not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $manifestStage) -Kind File) -or (Get-F2InstallHashBytes -Bytes (Read-F2InstallFileBytes -Path $manifestStage)) -cne (Get-F2InstallHashBytes -Bytes $releaseBytes)) { throw 'INSTALL_RELEASE_MANIFEST_ATTESTATION_FAILED' }
        $stage='PublishCreateNewDirectories'
        [IO.Directory]::Move($packageStage,$Context.PackageFinal);$packagePublished=$true
        [IO.Directory]::Move($releaseStage,$Context.ReleaseDirectoryFinal);$releasePublished=$true
        $stage='PostInstallAttestation'
        Test-F2InstallParentChain -Context $Context -TargetParent $Context.ProgramFilesParent
        Test-F2InstallParentChain -Context $Context -TargetParent $Context.CommonApplicationData
        $attested=@()
        foreach ($dir in @($Context.PackageFinal,(Join-Path $Context.PackageFinal 'scripts'),(Join-Path $Context.PackageFinal 'scripts\f2-acl'),$Context.ReleaseDirectoryFinal)) {
            Test-F2InstallNoReparseChain -Path $dir|Out-Null
            if (-not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $dir) -Kind Directory)) { throw 'POST_INSTALL_DIRECTORY_ATTESTATION_FAILED' }
            $attested+=@([pscustomobject]@{Path=$dir;Type='Directory';OwnerSid=$script:F2InstallAdminSid;DaclProtected=$true;Aces=(Get-F2InstallSanitizedAces Directory);ReparsePoint=$false})
        }
        $finalAcl=Join-Path (Join-Path $Context.PackageFinal 'scripts') 'f2-acl'
        foreach ($name in $script:F2InstallFiles.Keys) {
            $path=Join-Path $finalAcl $name;$bytes=Read-F2InstallFileBytes -Path $path;Test-F2InstallNoReparseChain -Path $path|Out-Null
            if ((Get-F2InstallHashBytes -Bytes $bytes) -cne $package.Files[$name].Sha256 -or -not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $path) -Kind File)) { throw 'POST_INSTALL_PACKAGE_FILE_ATTESTATION_FAILED' }
            $attested+=@([pscustomobject]@{Path=$path;Type='File';OwnerSid=$script:F2InstallAdminSid;DaclProtected=$true;Aces=(Get-F2InstallSanitizedAces File);Sha256=$package.Files[$name].Sha256;Bytes=$bytes.Length;ReparsePoint=$false})
        }
        $manifestFinal=Join-Path $Context.ReleaseDirectoryFinal 'approved-release.json';$finalManifest=Read-F2InstallFileBytes -Path $manifestFinal
        if ((Get-F2InstallHashBytes -Bytes $finalManifest) -cne (Get-F2InstallHashBytes -Bytes $releaseBytes) -or -not (Test-F2InstallExactDacl -Sddl (Get-F2InstallFileSddl -Path $manifestFinal) -Kind File)) { throw 'POST_INSTALL_RELEASE_ATTESTATION_FAILED' }
        $attested+=@([pscustomobject]@{Path=$manifestFinal;Type='File';OwnerSid=$script:F2InstallAdminSid;DaclProtected=$true;Aces=(Get-F2InstallSanitizedAces File);Sha256=(Get-F2InstallHashBytes -Bytes $finalManifest);Bytes=$finalManifest.Length;ReparsePoint=$false})
        return [pscustomobject]@{Success=$true;Outcome='INSTALL_COMPLETE';ReviewedCommitSha=$script:F2InstallReviewedCommit;BaselineMailboxId=$Context.BaselineMailboxId;BaselinePayloadCaptureId=$Context.BaselinePayloadCaptureId;BaselinePayloadSha256=$baseline.PayloadSha256;BaselineIntegritySha256=$baseline.IntegritySha256;SourcePinsManifestSha256=$package.PinsManifestSha256;PackagePath=$Context.PackageFinal;ReleaseManifestPath=$manifestFinal;InstalledFileCount=7;Attestation=$attested;PartialStagePaths=@()}
    } catch {
        $errorCode=[string]$_.Exception.Message
        if ($errorCode -cnotmatch '^[A-Z][A-Z0-9_]{0,63}$') { $errorCode='INSTALL_OPERATION_FAILED' }
        return [pscustomobject]@{Success=$false;Outcome='INSTALL_BLOCKED';Stage=$stage;ErrorCode=$errorCode;PackagePublished=$packagePublished;ReleasePublished=$releasePublished;PartialStagePaths=@(@($packageStage,$releaseStage)|Where-Object{$_ -and (Test-Path -LiteralPath $_)})}
    }
}

function Invoke-F2InstallMain {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=[Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return [pscustomobject]@{Success=$false;Outcome='ADMINISTRATOR_TOKEN_REQUIRED';ErrorCode='INSTALL_REQUIRES_REVIEWED_UAC_LAUNCH'} }
    return Invoke-F2InstallCore -Context (New-F2InstallContext)
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $unbound = @($MyInvocation.UnboundArguments)
        if ($unbound.Count -ne 0) { throw 'INSTALL_ARGUMENTS_NOT_ACCEPTED' }
        $result=Invoke-F2InstallMain
        [Console]::Out.WriteLine(($result|ConvertTo-Json -Depth 8 -Compress))
        if (-not $result.Success) { exit 1 }
        exit 0
    } catch {
        $code = [string]$_.Exception.Message
        if ($code -cnotmatch '^[A-Z][A-Z0-9_]{0,63}$') { $code = 'INSTALL_OPERATION_FAILED' }
        [Console]::Error.WriteLine(('F2_INSTALL: ' + $code + '; no success attestation.'));exit 1
    }
}

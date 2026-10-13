[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ReviewHead = '7f99bc10f3e2258d2340cea4e7ba1352022cbb6d'
$script:ProductionCommit = '396c44965c90c08292ad2835f8317e81b6b9daaf'
$script:ProductionParent = 'f58b7fdfaf71e212213d559480e1913ae6c210f8'
$script:Origin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$script:SourceRoot = 'C:\Dev\f2-g1-protected-updater-source'
$script:CandidateRoot = 'C:\Dev\f2-g1-protected-updater'
$script:CandidatePath = Join-Path $script:CandidateRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
$script:PackageHome = 'C:\Program Files\F2-G1-Icacls'
$script:ProgramDataRoot = 'C:\ProgramData\F2-G1-Icacls'
$script:ActiveManifestPath = Join-Path $script:ProgramDataRoot 'approved-release.json'
$script:MailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:PayloadCaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:PayloadSha256 = '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
$script:IntegritySha256 = '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
$script:PinManifestSha256 = '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
$script:CandidateSha256 = 'b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
$script:LauncherSha256 = '9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
$script:UpdaterSha256 = 'd9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2'
$script:DiagnosticSha256 = '66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'
$script:PackagePins = [ordered]@{
    'F2AclCapture.Protocol.psm1' = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1' = 'a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1' = 'd1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4'
    'Invoke-F2IcaclsCapture.ps1' = '0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818'
    'Invoke-F2IcaclsProtectedCoordinator.ps1' = '9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515'
    'F2_ICACLS_SOURCE_PINS.json' = '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
    'Invoke-F2AclReadOnlyCapture.ps1' = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}
$script:OldV2Pins = [ordered]@{
    'F2AclCapture.Protocol.psm1' = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1' = 'a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1' = '950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5'
    'Invoke-F2IcaclsCapture.ps1' = 'fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0'
    'Invoke-F2IcaclsProtectedCoordinator.ps1' = '3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2'
    'F2_ICACLS_SOURCE_PINS.json' = 'bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7'
    'Invoke-F2AclReadOnlyCapture.ps1' = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}
$script:Gates = New-Object 'System.Collections.Generic.List[object]'
$script:BaselineAuxiliaryHashes = [ordered]@{}
$script:FailureCode = $null
$script:Stage = 'Runtime'

function Stop-Preflight([string]$Code) {
    $script:FailureCode = $Code
    throw 'PREFLIGHT_STOP'
}

function Add-PreflightGate([string]$Name,[bool]$Pass,[string]$FailureCode,[string]$Detail) {
    $result = if ($Pass) { 'PASS' } else { 'FAIL' }
    $code = if ($Pass) { 'PASS' } else { $FailureCode }
    $script:Gates.Add([pscustomobject]@{ Name=$Name; Result=$result; Code=$code; Detail=$Detail })
    if (-not $Pass) { Stop-Preflight $FailureCode }
}

function Get-F2Sha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2FileSha256([string]$Path,[int]$MaximumBytes=16777216) {
    $item = $null
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch [System.UnauthorizedAccessException] { Stop-Preflight 'HOST_ACCESS_DENIED' }
    catch { Stop-Preflight 'HOST_REQUIRED_OBJECT_UNREADABLE' }
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -lt 1 -or $item.Length -gt $MaximumBytes) { Stop-Preflight 'HOST_FILE_TYPE_SIZE_OR_REPARSE_INVALID' }
    try { return Get-F2Sha256 ([IO.File]::ReadAllBytes($Path)) }
    catch [System.UnauthorizedAccessException] { Stop-Preflight 'HOST_ACCESS_DENIED' }
    catch { Stop-Preflight 'HOST_FILE_READ_FAILED' }
}

function Test-F2NoReparseChain([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    $current = $root
    $rest = $full.Substring($root.Length).TrimEnd('\')
    if (-not [string]::IsNullOrEmpty($rest)) {
        foreach ($part in $rest.Split('\')) {
            if ([string]::IsNullOrEmpty($part)) { continue }
            $current = Join-Path $current $part
            if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
                try { $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop }
                catch [System.UnauthorizedAccessException] { Stop-Preflight 'HOST_ACCESS_DENIED' }
                catch { Stop-Preflight 'HOST_PATH_CHAIN_UNREADABLE' }
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Stop-Preflight 'HOST_REPARSE_POINT_PRESENT' }
            }
        }
    }
    return $full
}

function Get-F2RawDescriptor([string]$Path,[ValidateSet('Directory','File')][string]$Kind) {
    [void](Test-F2NoReparseChain $Path)
    try { $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop }
    catch [System.UnauthorizedAccessException] { Stop-Preflight 'HOST_ACCESS_DENIED' }
    catch { Stop-Preflight 'HOST_REQUIRED_OBJECT_UNREADABLE' }
    if (($Kind -eq 'Directory' -and -not $item.PSIsContainer) -or ($Kind -eq 'File' -and $item.PSIsContainer)) { Stop-Preflight 'HOST_OBJECT_TYPE_MISMATCH' }
    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $sections = [Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access
        $sddl = $acl.GetSecurityDescriptorSddlForm($sections)
        $raw = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
        return [pscustomobject]@{ Item=$item; Raw=$raw }
    }
    catch [System.UnauthorizedAccessException] { Stop-Preflight 'HOST_ACCESS_DENIED' }
    catch { Stop-Preflight 'HOST_ACL_READ_OR_PARSE_FAILED' }
}

function Test-F2ExactInstallDacl($Raw,[ValidateSet('Directory','File')][string]$Kind) {
    $flags = if ($Kind -eq 'Directory') { 3 } else { 0 }
    $expected = @{ 'S-1-5-18'=[uint32]0x001F01FF; 'S-1-5-32-544'=[uint32]0x001F01FF; 'S-1-5-11'=[uint32]0x001200A9 }
    if ($null -eq $Raw.Owner -or $Raw.Owner.Value -ne 'S-1-5-32-544' -or $null -eq $Raw.DiscretionaryAcl -or ($Raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or @($Raw.DiscretionaryAcl).Count -ne 3) { return $false }
    $seen = @{}
    foreach ($ace in $Raw.DiscretionaryAcl) {
        if ($null -eq $ace.SecurityIdentifier -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed) { return $false }
        $sid = $ace.SecurityIdentifier.Value
        if (-not $expected.ContainsKey($sid) -or $seen.ContainsKey($sid)) { return $false }
        $mask = [uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        if ($mask -ne $expected[$sid] -or [int]$ace.AceFlags -ne $flags) { return $false }
        $seen[$sid] = $true
    }
    return $seen.Count -eq 3
}

function Test-F2SafeParentDacl([string]$Sddl,[ValidateSet('DriveRoot','ProgramFiles','ProgramData')][string]$Mode) {
    try { $raw = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl) } catch { return $false }
    $trustedOwners = @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    if ($null -eq $raw.Owner -or $raw.Owner.Value -notin $trustedOwners -or $null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0 -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0) { return $false }
    $danger = [long]0x00000002 -bor 0x00000004 -bor 0x00000010 -bor 0x00000040 -bor 0x00000100 -bor 0x00010000 -bor 0x00040000 -bor 0x00080000 -bor 0x40000000 -bor 0x10000000
    $safeReadExecute = [long]0x001200A9
    $rootCreateCount=0; $rootInheritedCount=0; $programDataCreateCount=0
    foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $null -eq $ace.SecurityIdentifier) { continue }
        $sid = $ace.SecurityIdentifier.Value
        $mask = [long]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        $inheritOnly = ([int]$ace.AceFlags -band [int][Security.AccessControl.AceFlags]::InheritOnly) -ne 0
        if ($inheritOnly) {
            if ($Mode -ne 'DriveRoot') { continue }
            if ($sid -in @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { continue }
            $expectedFlags=[int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit -bor [int][Security.AccessControl.AceFlags]::InheritOnly
            if ($sid -eq 'S-1-5-11' -and $mask -eq 3758161920 -and [int]$ace.AceFlags -eq $expectedFlags) { $rootInheritedCount++; continue }
            if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
            continue
        }
        if ($sid -in @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { continue }
        if ($Mode -eq 'DriveRoot' -and $sid -eq 'S-1-5-11' -and $mask -eq 0x00000004 -and [int]$ace.AceFlags -eq 0) { $rootCreateCount++; continue }
        if ($Mode -eq 'ProgramData' -and $sid -eq 'S-1-5-32-545' -and $mask -eq 0x116 -and [int]$ace.AceFlags -eq [int][Security.AccessControl.AceFlags]::ContainerInherit) { $programDataCreateCount++; continue }
        if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
    }
    if ($Mode -eq 'DriveRoot' -and ($rootCreateCount -ne 1 -or $rootInheritedCount -ne 1)) { return $false }
    if ($Mode -eq 'ProgramData' -and $programDataCreateCount -ne 1) { return $false }
    return $true
}

function Get-F2ChildNames([string]$Path) {
    try { return @((Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | ForEach-Object { [string]$_.Name })) }
    catch [System.UnauthorizedAccessException] { Stop-Preflight 'HOST_ACCESS_DENIED' }
    catch { Stop-Preflight 'HOST_CHILD_INVENTORY_FAILED' }
}

function Test-F2ExactNameSet([string]$Path,[string[]]$Expected) {
    $actual = @(Get-F2ChildNames $Path)
    return ($actual.Count -eq $Expected.Count -and @($actual | Sort-Object -Unique).Count -eq $Expected.Count -and @(Compare-Object ($Expected | Sort-Object) ($actual | Sort-Object) -CaseSensitive).Count -eq 0)
}

function Get-F2ExpectedBaselinePaths {
    $root='G:\F2-G1-Isolated-Disposable'; $name='F2-G1-Isolated-Disposable'; $vm=([guid]'6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1').ToString().ToUpperInvariant(); $config=Join-Path $root $name; $configVm=Join-Path (Join-Path $config 'Virtual Machines') $vm
    return @($root,$config,(Join-Path $config 'Virtual Machines'),$configVm,($configVm+'.vmcx'),($configVm+'.vmgs'),($configVm+'.VMRS'),(Join-Path $root 'F2-G1-OS.vhdx'),(Join-Path $root 'F2-G1-Scratch.vhdx'),(Join-Path $root 'Virtual Machines'),(Join-Path (Join-Path $root 'Virtual Machines') $vm))
}

try {
    $script:Stage='ExecutionContext'
    $ps51 = ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -eq 1)
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    try { $admin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); $requesterSid=$id.User.Value }
    finally { $id.Dispose() }
    Add-PreflightGate 'WindowsPowerShell51StandardToken' ($ps51 -and -not $admin) 'WRONG_POWERSHELL_OR_ELEVATED_TOKEN' 'Windows PowerShell 5.1; Administrator role not enabled.'

    $script:Stage='CheckoutProvenance'
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $git) { Stop-Preflight 'GIT_UNAVAILABLE' }
    foreach ($repo in @(
        [pscustomobject]@{Path=$script:SourceRoot;Head=$script:ProductionCommit;Parent=$script:ProductionParent;Label='ProductionSourceRoot'},
        [pscustomobject]@{Path=$script:CandidateRoot;Head=$script:ReviewHead;Parent=$script:ProductionCommit;Label='LauncherCandidateRoot'}
    )) {
        $full=[IO.Path]::GetFullPath($repo.Path).TrimEnd('\')
        if ($full -cne $repo.Path) { Stop-Preflight 'CHECKOUT_CANONICAL_PATH_MISMATCH' }
        [void](Test-F2NoReparseChain $full)
        $head=@(& $git.Source -C $full rev-parse HEAD 2>$null); $exit=$LASTEXITCODE
        if ($exit -ne 0 -or [string]::Join('',[string[]]$head).Trim() -cne $repo.Head) { Stop-Preflight 'CHECKOUT_HEAD_MISMATCH' }
        $parent=@(& $git.Source -C $full rev-parse 'HEAD^' 2>$null); $exit=$LASTEXITCODE
        if ($exit -ne 0 -or [string]::Join('',[string[]]$parent).Trim() -cne $repo.Parent) { Stop-Preflight 'CHECKOUT_PARENT_MISMATCH' }
        $origin=@(& $git.Source -C $full remote get-url origin 2>$null); $exit=$LASTEXITCODE
        if ($exit -ne 0 -or [string]::Join('',[string[]]$origin).Trim() -cne $script:Origin) { Stop-Preflight 'CHECKOUT_ORIGIN_MISMATCH' }
        $status=@(& $git.Source -C $full status --porcelain --untracked-files=all 2>$null); $exit=$LASTEXITCODE
        if ($exit -ne 0 -or $status.Count -ne 0) { Stop-Preflight 'CHECKOUT_NOT_CLEAN' }
    }
    $remote=@(& $git.Source -C $script:CandidateRoot ls-remote origin 'refs/heads/fix/f2-g1-prelock-diagnostics-issue48' 2>$null); $exit=$LASTEXITCODE
    if ($exit -ne 0 -or $remote.Count -ne 1 -or ([string]$remote[0] -split '\s+')[0] -cne $script:ReviewHead) { Stop-Preflight 'PR65_REMOTE_REF_MISMATCH' }
    $prRef=@(& $git.Source -C $script:CandidateRoot rev-parse 'refs/remotes/origin/pr/65' 2>$null); $exit=$LASTEXITCODE
    if ($exit -ne 0 -or [string]::Join('',[string[]]$prRef).Trim() -cne $script:ReviewHead) { Stop-Preflight 'PR65_FETCHED_REF_MISMATCH' }
    Add-PreflightGate 'FixedGitCheckoutsAndRemoteRefs' $true 'CHECKOUT_IDENTITY_INVALID' 'SourceRoot and launcher candidate roots match reviewed commits, parents, origin, clean state, and PR #65 refs.'

    $script:Stage='SourceBytes'
    $fixedHashes = @(
        [pscustomobject]@{Path=(Join-Path $script:SourceRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1');Sha=$script:LauncherSha256},
        [pscustomobject]@{Path=(Join-Path $script:SourceRoot 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1');Sha=$script:UpdaterSha256},
        [pscustomobject]@{Path=(Join-Path $script:SourceRoot 'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1');Sha=$script:DiagnosticSha256},
        [pscustomobject]@{Path=$script:CandidatePath;Sha=$script:CandidateSha256},
        [pscustomobject]@{Path=(Join-Path $script:SourceRoot 'scripts\f2-acl\F2_ICACLS_SOURCE_PINS.json');Sha=$script:PinManifestSha256}
    )
    foreach ($f in $fixedHashes) {
        [void](Test-F2NoReparseChain $f.Path)
        if ((Get-F2FileSha256 -Path $f.Path -MaximumBytes 4194304) -cne $f.Sha) { Stop-Preflight 'REVIEWED_EXECUTABLE_OR_MANIFEST_HASH_MISMATCH' }
    }
    $sourcePackage=Join-Path $script:SourceRoot 'scripts\f2-acl'
    foreach ($name in $script:PackagePins.Keys) {
        $path=Join-Path $sourcePackage $name
        if ((Get-F2FileSha256 -Path $path) -cne $script:PackagePins[$name]) { Stop-Preflight 'SOURCE_PACKAGE_PIN_MISMATCH' }
    }
    $candidateBytes=[IO.File]::ReadAllBytes($script:CandidatePath)
    $candidate=[Text.Encoding]::UTF8.GetString($candidateBytes)|ConvertFrom-Json -ErrorAction Stop
    if ($candidate.Schema -cne 'f2-icacls-runtime-release-v3' -or $candidate.ReviewedCommitSha -cne $script:ProductionCommit -or $candidate.PackageRoot -cne (Join-Path (Join-Path $script:PackageHome 'releases') $script:ProductionCommit) -or $candidate.BaselineMailboxId -cne $script:MailboxId -or $candidate.BaselinePayloadCaptureId -cne $script:PayloadCaptureId -or $candidate.BaselinePayloadSha256 -cne $script:PayloadSha256 -or $candidate.BaselineIntegritySha256 -cne $script:IntegritySha256 -or $candidate.SourcePinsManifestSha256 -cne $script:PinManifestSha256) { Stop-Preflight 'CANDIDATE_IDENTITY_INVALID' }
    if (@($candidate.Files).Count -ne 7) { Stop-Preflight 'CANDIDATE_PACKAGE_SET_INVALID' }
    foreach ($f in $candidate.Files) { if (-not $script:PackagePins.Contains($f.Name) -or $script:PackagePins[$f.Name] -cne $f.Sha256) { Stop-Preflight 'CANDIDATE_PACKAGE_PIN_INVALID' } }
    Add-PreflightGate 'ReviewedPhysicalSourceAndCandidateHashes' $true 'SOURCE_HASH_MISMATCH' 'Three production executables, candidate manifest, source pin manifest, and seven package members match full SHA-256 pins.'

    $script:Stage='ParentAcl'
    $rootD=Get-F2RawDescriptor 'C:\' Directory
    $pfD=Get-F2RawDescriptor 'C:\Program Files' Directory
    $pdD=Get-F2RawDescriptor 'C:\ProgramData' Directory
    $parentPass=(Test-F2SafeParentDacl $rootD.Raw.GetSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access) DriveRoot) -and (Test-F2SafeParentDacl $pfD.Raw.GetSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access) ProgramFiles) -and (Test-F2SafeParentDacl $pdD.Raw.GetSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access) ProgramData)
    Add-PreflightGate 'SystemDriveAndProtectedParentAclPolicy' $parentPass 'PARENT_ACL_POLICY_UNSAFE' 'C:\ root, Program Files, and ProgramData satisfy the reviewed fail-closed parent ACL rules.'

    $script:Stage='InstalledV2'
    $programFiles=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    $commonData=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([IO.Path]::GetFullPath($programFiles) -cne 'C:\Program Files' -or [IO.Path]::GetFullPath($commonData) -cne 'C:\ProgramData') { Stop-Preflight 'PROTECTED_ROOT_PATH_MISMATCH' }
    $dirChecks=@(
        [pscustomobject]@{Path=$script:PackageHome;NameSet=@('scripts')},
        [pscustomobject]@{Path=(Join-Path $script:PackageHome 'scripts');NameSet=@('f2-acl')},
        [pscustomobject]@{Path=(Join-Path $script:PackageHome 'scripts\f2-acl');NameSet=@($script:OldV2Pins.Keys)},
        [pscustomobject]@{Path=$script:ProgramDataRoot;NameSet=@('approved-release.json')}
    )
    foreach ($d in $dirChecks) {
        $snapshot=Get-F2RawDescriptor $d.Path Directory
        if (-not (Test-F2ExactInstallDacl $snapshot.Raw Directory)) { Stop-Preflight 'INSTALLED_DIRECTORY_OWNER_OR_DACL_MISMATCH' }
        if (-not (Test-F2ExactNameSet $d.Path $d.NameSet)) { Stop-Preflight 'INSTALLED_DIRECTORY_CHILD_SET_MISMATCH' }
    }
    $releaseRoot=Join-Path $script:PackageHome 'releases'
    if ([IO.Directory]::Exists($releaseRoot) -or [IO.File]::Exists($releaseRoot)) { Stop-Preflight 'V3_RELEASE_OR_COLLISION_PRESENT' }
    foreach ($name in @('release.lock','updates','backups','journals')) {
        $path=Join-Path $script:ProgramDataRoot $name
        if ([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) { Stop-Preflight 'TRANSACTION_OR_BACKUP_OBJECT_PRESENT' }
    }
    $installedManifestSha=Get-F2FileSha256 $script:ActiveManifestPath 65536
    if ($installedManifestSha -cne 'b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9') { Stop-Preflight 'ACTIVE_V2_MANIFEST_HASH_MISMATCH' }
    $installedManifestBytes=[IO.File]::ReadAllBytes($script:ActiveManifestPath)
    $installedManifest=[Text.Encoding]::UTF8.GetString($installedManifestBytes)|ConvertFrom-Json -ErrorAction Stop
    if ($installedManifest.Schema -cne 'f2-icacls-runtime-release-v2' -or $installedManifest.ReviewedCommitSha -cne '5741ffe90a3abd02a08563e6431e8a0b9b63eeb1' -or $installedManifest.BaselineMailboxId -cne $script:MailboxId -or $installedManifest.BaselinePayloadCaptureId -cne $script:PayloadCaptureId -or $installedManifest.BaselinePayloadSha256 -cne $script:PayloadSha256 -or $installedManifest.BaselineIntegritySha256 -cne $script:IntegritySha256 -or $installedManifest.SourcePinsManifestSha256 -cne 'bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7') { Stop-Preflight 'ACTIVE_V2_MANIFEST_IDENTITY_INVALID' }
    if (@($installedManifest.Files).Count -ne 7) { Stop-Preflight 'ACTIVE_V2_FILE_SET_INVALID' }
    $oldAclRoot=Join-Path $script:PackageHome 'scripts\f2-acl'
    $installedFileHashes=[ordered]@{}
    foreach ($name in $script:OldV2Pins.Keys) {
        $path=Join-Path $oldAclRoot $name
        $fileD=Get-F2RawDescriptor $path File
        if (-not (Test-F2ExactInstallDacl $fileD.Raw File)) { Stop-Preflight 'INSTALLED_FILE_OWNER_OR_DACL_MISMATCH' }
        $actual=Get-F2FileSha256 $path
        if ($actual -cne $script:OldV2Pins[$name]) { Stop-Preflight 'INSTALLED_V2_FILE_HASH_MISMATCH' }
        $declared=@($installedManifest.Files|Where-Object{$_.Name -ceq $name})
        if ($declared.Count -ne 1 -or $declared[0].Sha256 -cne $actual) { Stop-Preflight 'ACTIVE_V2_FILE_PIN_MISMATCH' }
        $installedFileHashes[$name]=$actual
    }
    $activeD=Get-F2RawDescriptor $script:ActiveManifestPath File
    if (-not (Test-F2ExactInstallDacl $activeD.Raw File)) { Stop-Preflight 'ACTIVE_V2_MANIFEST_OWNER_OR_DACL_MISMATCH' }
    Add-PreflightGate 'InstalledV2HashesOwnersDaclsAndTransactionAbsence' $true 'INSTALLED_V2_OR_TRANSACTION_STATE_INVALID' 'Active v2 manifest, seven installed v2 files, four installation directories, exact protected ACL profiles, no reparse paths, and no transaction/release objects verified.'

    $script:Stage='RetainedBaseline'
    $mailbox=Join-Path $commonData ('F2-G1-ACL-Evidence-'+$script:MailboxId)
    $mailD=Get-F2RawDescriptor $mailbox Directory
    $raw=$mailD.Raw
    $mailboxPass=($mailD.Item.PSIsContainer -and $raw.Owner.Value -eq 'S-1-5-32-544' -and ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0 -and $null -ne $raw.DiscretionaryAcl -and @($raw.DiscretionaryAcl).Count -eq 4)
    $rights=[uint32]0x001200A9; $mailSids=@{}; $currentSeen=$false
    if ($mailboxPass) {
        foreach ($ace in $raw.DiscretionaryAcl) {
            if ($null -eq $ace.SecurityIdentifier -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or [int]$ace.AceFlags -ne 3) { $mailboxPass=$false; break }
            $sid=$ace.SecurityIdentifier.Value; $mask=[uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
            if ($mailSids.ContainsKey($sid)) { $mailboxPass=$false; break }; $mailSids[$sid]=$true
            if ($sid -in @('S-1-5-18','S-1-5-32-544')) { if ($mask -ne [uint32]0x001F01FF) { $mailboxPass=$false; break } }
            elseif ($sid -eq 'S-1-3-4' -or $sid -eq $requesterSid) { if ($mask -ne $rights) { $mailboxPass=$false; break }; if ($sid -eq $requesterSid) { $currentSeen=$true } }
            else { $mailboxPass=$false; break }
        }
    }
    if ($mailSids.Count -ne 4 -or -not $mailSids.ContainsKey('S-1-5-18') -or -not $mailSids.ContainsKey('S-1-5-32-544') -or -not $mailSids.ContainsKey('S-1-3-4') -or -not $currentSeen) { $mailboxPass=$false }
    if (-not $mailboxPass) { Stop-Preflight 'BASELINE_MAILBOX_FOUR_ACE_REQUESTER_PROFILE_INVALID' }
    $mailboxFiles=@('acl-baseline.frame','acl-baseline.json','coordinator-status.json','integrity.json','powershell-streams.json','worker-stderr.json','worker-stdout.json')
    if (-not (Test-F2ExactNameSet $mailbox $mailboxFiles)) { Stop-Preflight 'BASELINE_MAILBOX_CONTENT_SET_INVALID' }
    $payloadPath=Join-Path $mailbox 'acl-baseline.json'; $integrityPath=Join-Path $mailbox 'integrity.json'
    $payloadFileSha=Get-F2FileSha256 $payloadPath 1048576; $integrityFileSha=Get-F2FileSha256 $integrityPath 1048576
    if ($payloadFileSha -cne $script:PayloadSha256 -or $integrityFileSha -cne $script:IntegritySha256) { Stop-Preflight 'RETAINED_BASELINE_FILE_HASH_MISMATCH' }
    $payloadBytes=[IO.File]::ReadAllBytes($payloadPath); $integrityBytes=[IO.File]::ReadAllBytes($integrityPath)
    $integrity=[Text.Encoding]::UTF8.GetString($integrityBytes)|ConvertFrom-Json -ErrorAction Stop
    $baseline=[Text.Encoding]::UTF8.GetString($payloadBytes)|ConvertFrom-Json -ErrorAction Stop
    if ($integrity.Schema -cne 'f2-acl-integrity-v1' -or $integrity.PayloadFile -cne 'acl-baseline.json' -or [int64]$integrity.PayloadBytes -ne $payloadBytes.Length -or $integrity.PayloadSha256 -cne $script:PayloadSha256 -or $integrity.ProjectVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $integrity.EvidenceVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $integrity.ProjectVolumeGuid -ceq $integrity.EvidenceVolumeGuid) { Stop-Preflight 'BASELINE_INTEGRITY_IDENTITY_INVALID' }
    $script:BaselineAuxiliaryHashes['acl-baseline.json']=$payloadFileSha
    $script:BaselineAuxiliaryHashes['integrity.json']=$integrityFileSha
    $streamsPath=Join-Path $mailbox 'powershell-streams.json'
    $streamsSha=Get-F2FileSha256 $streamsPath 65536
    $streamsBytes=[IO.File]::ReadAllBytes($streamsPath)
    if ($integrity.PowerShellStreamsFile -cne 'powershell-streams.json' -or [int64]$integrity.PowerShellStreamsBytes -ne $streamsBytes.Length -or $integrity.PowerShellStreamsSha256 -cne $streamsSha -or $integrity.ChildExitCode -ne 0 -or $integrity.CollectorScriptSha256 -cne 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b' -or $integrity.ProtocolModuleSha256 -cne '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728' -or $integrity.SeparateFromProjectVolume -ne $true) { Stop-Preflight 'BASELINE_INTEGRITY_PROVENANCE_INVALID' }
    $streams=[Text.Encoding]::UTF8.GetString($streamsBytes)|ConvertFrom-Json -ErrorAction Stop
    if ($streams.Schema -cne 'f2-acl-powershell-streams-v1' -or $streams.Complete -ne $true -or $streams.ExitCode -ne 0) { Stop-Preflight 'BASELINE_STREAM_EVIDENCE_INCOMPLETE' }
    $script:BaselineAuxiliaryHashes['powershell-streams.json']=$streamsSha
    $expectedDiagnosticNames=@('worker-stderr.json','worker-stdout.json')
    $integrityDiagnostics=@($integrity.WorkerDiagnosticFiles)
    $diagnosticNames=@($integrityDiagnostics|ForEach-Object{[string]$_.Name}|Sort-Object)
    if ($integrityDiagnostics.Count -ne 2 -or @($diagnosticNames|Sort-Object -Unique).Count -ne 2 -or @(Compare-Object ($expectedDiagnosticNames|Sort-Object) $diagnosticNames -CaseSensitive).Count -ne 0) { Stop-Preflight 'BASELINE_WORKER_DIAGNOSTIC_MANIFEST_INVALID' }
    foreach ($d in $integrityDiagnostics) {
        $name=[string]$d.Name
        if ($name -notin $expectedDiagnosticNames -or [int64]$d.Bytes -le 0 -or [int64]$d.Bytes -gt 65536) { Stop-Preflight 'BASELINE_WORKER_DIAGNOSTIC_MANIFEST_INVALID' }
        $path=Join-Path $mailbox $name
        $actual=Get-F2FileSha256 $path 65536
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ([int64]$item.Length -ne [int64]$d.Bytes -or $actual -cne [string]$d.Sha256) { Stop-Preflight 'BASELINE_WORKER_DIAGNOSTIC_HASH_MISMATCH' }
        $script:BaselineAuxiliaryHashes[$name]=$actual
    }
    $framePath=Join-Path $mailbox 'acl-baseline.frame'
    $frameFileSha=Get-F2FileSha256 $framePath 262188
    $frameBytes=[IO.File]::ReadAllBytes($framePath)
    if ($frameBytes.Length -lt 44 -or [BitConverter]::ToString($frameBytes[0..7]) -cne '46-32-41-43-4C-01-0D-0A') { Stop-Preflight 'BASELINE_FRAME_INVALID' }
    $framePayloadLength=[BitConverter]::ToInt32($frameBytes,8)
    if ($framePayloadLength -ne $payloadBytes.Length -or $frameBytes.Length -ne (44+$framePayloadLength)) { Stop-Preflight 'BASELINE_FRAME_LENGTH_MISMATCH' }
    $framePayload=New-Object byte[] $framePayloadLength
    [Buffer]::BlockCopy($frameBytes,12,$framePayload,0,$framePayloadLength)
    $frameDigest=New-Object byte[] 32
    [Buffer]::BlockCopy($frameBytes,(12+$framePayloadLength),$frameDigest,0,32)
    if ((Get-F2Sha256 $framePayload) -cne $script:PayloadSha256 -or [BitConverter]::ToString($framePayload) -cne [BitConverter]::ToString($payloadBytes) -or [BitConverter]::ToString($frameDigest) -cne ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($framePayload)))) { Stop-Preflight 'BASELINE_FRAME_INTEGRITY_MISMATCH' }
    if ((Get-F2Sha256 $frameBytes) -cne $frameFileSha) { Stop-Preflight 'BASELINE_FRAME_READ_RACE' }
    $script:BaselineAuxiliaryHashes['acl-baseline.frame']=$frameFileSha
    $statusPath=Join-Path $mailbox 'coordinator-status.json'
    $statusSha=Get-F2FileSha256 $statusPath 65536
    $statusBytes=[IO.File]::ReadAllBytes($statusPath)
    $status=[Text.Encoding]::UTF8.GetString($statusBytes)|ConvertFrom-Json -ErrorAction Stop
    $coordinatorSidValid=$false
    try { [void][Security.Principal.SecurityIdentifier]::new([string]$status.CoordinatorSid); $coordinatorSidValid=$true } catch { $coordinatorSidValid=$false }
    $worker=$status.WorkerDiagnostics
    $requiredStages=@('EntrypointReached','InvocationStarted','SourceVerified','MailboxVerified','CollectorEntered','FramePublished','StreamPublished','InvocationReturned')
    $expectedWorkerFiles=@($status.WorkerExpectedFiles|ForEach-Object{[string]$_.Name}|Sort-Object)
    $workerFilesExact=($expectedWorkerFiles -join ',') -ceq 'acl-baseline.frame,powershell-streams.json' -and @($status.WorkerExpectedFiles|Where-Object{$_.Exists -ne $true -or $_.Length -le 0}).Count -eq 0
    $statusDiagnostics=@($status.WorkerDiagnosticFiles|Sort-Object Name|ForEach-Object{([string]$_.Name)+':'+[string]$_.Bytes+':'+[string]$_.Sha256}) -join '|'
    $integrityDiagnosticsCanonical=@($integrityDiagnostics|Sort-Object Name|ForEach-Object{([string]$_.Name)+':'+[string]$_.Bytes+':'+[string]$_.Sha256}) -join '|'
    if ($status.Schema -cne 'f2-acl-elevated-coordinator-v1' -or $status.Outcome -cne 'COMPLETE_READ_ONLY_ACL_BASELINE' -or $status.RequesterSid -cne $requesterSid -or -not $status.AdministratorRoleVerified -or -not $coordinatorSidValid -or $status.WorkerExitCode -ne 0 -or $status.ExpectedProcessExitCode -ne 0 -or @($status.Errors).Count -ne 0 -or $null -ne $status.WorkerDiagnosticFallback -or -not $worker.Started -or $worker.State -cne 'Exited' -or $worker.TimedOut -or $worker.ExitCode -ne 0 -or -not $worker.OutputComplete -or -not $worker.CleanupComplete -or $worker.StdoutTruncated -or $worker.StderrTruncated -or $null -ne $worker.FatalError -or @($worker.ReaderErrors).Count -ne 0 -or @($requiredStages|Where-Object{$worker.Stages -cnotcontains $_}).Count -ne 0 -or -not $workerFilesExact -or $statusDiagnostics -cne $integrityDiagnosticsCanonical) { Stop-Preflight 'BASELINE_COORDINATOR_STATUS_INVALID' }
    $script:BaselineAuxiliaryHashes['coordinator-status.json']=$statusSha
    if ($baseline.CaptureId -cne $script:PayloadCaptureId -or $baseline.Complete -ne $true -or $baseline.VmId -cne '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1' -or $baseline.VmName -cne 'F2-G1-Isolated-Disposable') { Stop-Preflight 'BASELINE_PAYLOAD_IDENTITY_INVALID' }
    $expectedPaths=@(Get-F2ExpectedBaselinePaths); $recordPaths=@($baseline.Records|ForEach-Object{[string]$_.Path}); $manifestPaths=@($baseline.Manifest.ExpectedPaths|ForEach-Object{[string]$_})
    $canon={param($x) [IO.Path]::GetFullPath([string]$x).TrimEnd('\')}.GetNewClosure()
    $expectedCanon=@($expectedPaths|ForEach-Object{& $canon $_}|Sort-Object);$recordCanon=@($recordPaths|ForEach-Object{& $canon $_}|Sort-Object);$manifestCanon=@($manifestPaths|ForEach-Object{& $canon $_}|Sort-Object)
    if ($expectedPaths.Count -ne 11 -or @($expectedCanon|Sort-Object -Unique).Count -ne 11 -or $recordPaths.Count -ne 11 -or @($recordCanon|Sort-Object -Unique).Count -ne 11 -or $manifestPaths.Count -ne 11 -or @($manifestCanon|Sort-Object -Unique).Count -ne 11 -or @(Compare-Object $expectedCanon $recordCanon -CaseSensitive).Count -ne 0 -or @(Compare-Object $expectedCanon $manifestCanon -CaseSensitive).Count -ne 0 -or $baseline.Manifest.ExpectedCount -ne 11 -or $baseline.Manifest.RecordCount -ne 11 -or $baseline.Manifest.UniquePathCount -ne 11) { Stop-Preflight 'BASELINE_ELEVEN_PATH_COMPLETENESS_INVALID' }
    Add-PreflightGate 'OriginalRequesterMailboxAndRetainedBaseline' $true 'RETAINED_BASELINE_INVALID' 'Four-ACE protected mailbox matches the current requester without exposing its SID; distinct mailbox/payload identities, pinned payload/integrity hashes, 11 unique authorized records, and separate recorded volume identities verified. No G: path was queried.'
}
catch {
    if ([string]::IsNullOrEmpty($script:FailureCode)) {
        $script:FailureCode = switch ($script:Stage) {
            'CheckoutProvenance' { 'CHECKOUT_PREFLIGHT_UNCLASSIFIED_FAILURE' }
            'SourceBytes' { 'SOURCE_PREFLIGHT_UNCLASSIFIED_FAILURE' }
            'ParentAcl' { 'PARENT_ACL_PREFLIGHT_UNCLASSIFIED_FAILURE' }
            'InstalledV2' { 'INSTALLED_V2_PREFLIGHT_UNCLASSIFIED_FAILURE' }
            'RetainedBaseline' { 'BASELINE_PREFLIGHT_UNCLASSIFIED_FAILURE' }
            default { 'HOST_PREFLIGHT_UNCLASSIFIED_FAILURE' }
        }
    }
}

$outcome = if ($null -eq $script:FailureCode) { 'PASS_READ_ONLY_PREFLIGHT' } else { 'BLOCKED_WITH_EVIDENCE' }
$report=[ordered]@{
    Schema='f2-g1-standard-read-only-preflight-v1'
    Outcome=$outcome
    FailureCode=$script:FailureCode
    Stage=$script:Stage
    PowerShellVersion=$PSVersionTable.PSVersion.ToString()
    StandardToken=($Gates.Count -gt 0 -and $Gates[0].Result -eq 'PASS')
    ReviewHead=$script:ReviewHead
    ProductionCommit=$script:ProductionCommit
    SourceRoot=$script:SourceRoot
    CandidateRoot=$script:CandidateRoot
    Gates=@($script:Gates.ToArray())
    ProtectedStateAttestation=if ($null -eq $script:FailureCode -and $script:Stage -eq 'RetainedBaseline') { [ordered]@{ActiveV2ManifestSha256='b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9';InstalledV2Files=$script:OldV2Pins;CandidateManifestSha256=$script:CandidateSha256;BaselineMailboxId=$script:MailboxId;BaselinePayloadCaptureId=$script:PayloadCaptureId;BaselinePayloadSha256=$script:PayloadSha256;BaselineIntegritySha256=$script:IntegritySha256;BaselineRecordCount=11;MailboxEntryCount=7;MailboxEvidenceHashes=$script:BaselineAuxiliaryHashes;DaclDetails='Exact reviewed profiles PASS; raw SDDL and private SIDs omitted.'} } else { $null }
}
[Console]::Out.WriteLine(($report | ConvertTo-Json -Depth 8 -Compress))
if ($null -ne $script:FailureCode) { exit 1 }
exit 0

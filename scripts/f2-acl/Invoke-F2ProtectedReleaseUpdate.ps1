Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2UpdateOldCommit = '5741ffe90a3abd02a08563e6431e8a0b9b63eeb1'
$script:F2UpdateOldManifestSha256 = 'b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9'
$script:F2UpdateBaselineMailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:F2UpdateBaselineCaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:F2UpdateBaselinePayloadSha256 = '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
$script:F2UpdateBaselineIntegritySha256 = '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
$script:F2UpdateOriginalCollectorBaseSha = 'a62773f0553dff4a05055b18fa10834f7488ae55'
$script:F2UpdateOldPins = [ordered]@{
    'F2AclCapture.Protocol.psm1' = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1' = 'a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1' = '950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5'
    'Invoke-F2IcaclsCapture.ps1' = 'fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0'
    'Invoke-F2IcaclsProtectedCoordinator.ps1' = '3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2'
    'F2_ICACLS_SOURCE_PINS.json' = 'bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7'
    'Invoke-F2AclReadOnlyCapture.ps1' = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}

function Get-F2UpdateSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2UpdateHook {
    param($Context,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $Context -or $null -eq $Context.Hooks) { return $null }
    $property = $Context.Hooks.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-F2UpdateDiagnosticStage {
    param(
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)][ValidateSet(
            'CandidateManifestValidation','SourceGitValidation','SourcePackagePinValidation',
            'ParentAclValidation','InstalledV2Validation','TransactionCollisionValidation',
            'AcquireReleaseBarrier','RuntimeQuiescence','CreateTransactionRoots','StagePackage',
            'ActivatePackageSideBySide','ActivateManifest'
        )][string]$Stage
    )
    if ($null -eq $Context.PSObject.Properties['DiagnosticStage']) { throw 'UPDATE_DIAGNOSTIC_STAGE_CONTEXT_INVALID' }
    $Context.DiagnosticStage = $Stage
    return $Stage
}

function Get-F2UpdateDiagnosticStage {
    param($Context)
    $allowed = @(
        'CandidateManifestValidation','SourceGitValidation','SourcePackagePinValidation',
        'ParentAclValidation','InstalledV2Validation','TransactionCollisionValidation',
        'AcquireReleaseBarrier','RuntimeQuiescence','CreateTransactionRoots','StagePackage',
        'ActivatePackageSideBySide','ActivateManifest'
    )
    if ($null -ne $Context -and $null -ne $Context.PSObject.Properties['DiagnosticStage']) {
        $stage = [string]$Context.DiagnosticStage
        if ($stage -cin $allowed) { return $stage }
    }
    return 'UpdaterInvocation'
}

function Test-F2UpdateElevationIdentity {
    param([Parameter(Mandatory)][ValidatePattern('^S-1-')][string]$ExpectedRequesterSid,$Context)
    $hook = Get-F2UpdateHook -Context $Context -Name 'Identity'
    if ($null -ne $hook) {
        $identity = & $hook
        if ([string]$identity.UserSid -cne $ExpectedRequesterSid -or -not [bool]$identity.IsAdministrator) { throw 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH' }
        return $true
    }
    $identity = $null
    try { $identity = [Security.Principal.WindowsIdentity]::GetCurrent() } catch { throw 'UPDATE_ELEVATED_REQUESTER_IDENTITY_UNVERIFIABLE' }
    try {
        if ($null -eq $identity.User -or [string]$identity.User.Value -cne $ExpectedRequesterSid) { throw 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH' }
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH' }
    } finally { $identity.Dispose() }
    return $true
}

function Get-F2UpdateDaclSddl {
    param([Parameter(Mandatory)][string]$Path)
    New-F2UpdateNativeSupport
    return [F2Update.NativeOps]::GetSddl($Path)
}

function Test-F2UpdateExactDacl {
    param([Parameter(Mandatory)][string]$Sddl,[Parameter(Mandatory)][ValidateSet('Directory','File')][string]$Kind)
    $descriptor = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
    $expectedFlags = if ($Kind -eq 'Directory') { [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit } else { 0 }
    $expected = @{'S-1-5-18'=[uint32]0x001F01FF;'S-1-5-32-544'=[uint32]0x001F01FF;'S-1-5-11'=[uint32]0x001200A9}
    if ($descriptor.Owner.Value -ne 'S-1-5-32-544' -or $null -eq $descriptor.DiscretionaryAcl -or ($descriptor.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or @($descriptor.DiscretionaryAcl).Count -ne 3) { return $false }
    $seen = @{}
    foreach ($ace in @($descriptor.DiscretionaryAcl)) {
        $sid = $ace.SecurityIdentifier.Value
        if (-not $expected.ContainsKey($sid) -or $seen.ContainsKey($sid) -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or [uint32]$ace.AccessMask -ne $expected[$sid] -or [int]$ace.AceFlags -ne $expectedFlags) { return $false }
        $seen[$sid] = $true
    }
    return $seen.Count -eq 3
}

function Test-F2UpdateNoReparsePath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $current = $full
    while (-not [string]::IsNullOrEmpty($current)) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'UPDATE_REPARSE_POINT_REJECTED' }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
    return $full
}

function Test-F2UpdateSafeParentSddl {
    param([Parameter(Mandatory)][string]$Sddl,[switch]$AllowProgramDataCreateMask,[switch]$AllowSystemDriveRootAddSubdirectoryMask)
    try { $raw = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl) } catch { return $false }
    if ($null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0 -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $raw.Owner.Value -notin @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { return $false }
    $danger = [long]0x00000002 -bor 0x00000004 -bor 0x00000010 -bor 0x00000040 -bor 0x00000100 -bor 0x00010000 -bor 0x00040000 -bor 0x00080000 -bor 0x40000000 -bor 0x10000000
    $safeReadExecute = [long]0x001200A9
    $rootCreateCount = 0; $rootInheritedCount = 0; $programDataCreateCount = 0
    foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed) { continue }
        $sid = $ace.SecurityIdentifier.Value
        $mask = [long]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        $inheritOnly = ([int]$ace.AceFlags -band [int][Security.AccessControl.AceFlags]::InheritOnly) -ne 0
        if ($inheritOnly) {
            if (-not $AllowSystemDriveRootAddSubdirectoryMask) { continue }
            if ($sid -in @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { continue }
            $expectedFlags = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit -bor [int][Security.AccessControl.AceFlags]::InheritOnly
            if ($sid -eq 'S-1-5-11' -and $mask -eq 3758161920 -and [int]$ace.AceFlags -eq $expectedFlags) { $rootInheritedCount++; continue }
            if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
            continue
        }
        if ($sid -in @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { continue }
        if ($AllowSystemDriveRootAddSubdirectoryMask -and $sid -eq 'S-1-5-11' -and $mask -eq 0x00000004 -and [int]$ace.AceFlags -eq 0) { $rootCreateCount++; continue }
        if ($AllowProgramDataCreateMask -and $sid -eq 'S-1-5-32-545' -and $mask -eq 0x116 -and [int]$ace.AceFlags -eq [int][Security.AccessControl.AceFlags]::ContainerInherit) { $programDataCreateCount++; continue }
        if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
    }
    if ($AllowSystemDriveRootAddSubdirectoryMask -and ($rootCreateCount -ne 1 -or $rootInheritedCount -ne 1)) { return $false }
    if ($AllowProgramDataCreateMask -and $programDataCreateCount -ne 1) { return $false }
    return $true
}

function Test-F2UpdateParentChains {
    param($Context)
    $hook = Get-F2UpdateHook -Context $Context -Name 'ParentChainCheck'
    if ($null -ne $hook) {
        if (-not [bool](& $hook $Context)) { throw 'UPDATE_PARENT_CHAIN_UNSAFE' }
        return $true
    }
    $programFiles = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if (-not [string]::Equals([IO.Path]::GetFullPath($programFiles),'C:\Program Files',[StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([IO.Path]::GetFullPath($commonData),'C:\ProgramData',[StringComparison]::OrdinalIgnoreCase)) { throw 'UPDATE_PARENT_ROOT_NOT_C' }
    $driveRoot = 'C:\'; $programFilesSddl = Get-F2UpdateDaclSddl -Path $programFiles; $programDataSddl = Get-F2UpdateDaclSddl -Path $commonData
    $rootSddl = Get-F2UpdateDaclSddl -Path $driveRoot
    if (-not (Test-F2UpdateSafeParentSddl -Sddl $rootSddl -AllowSystemDriveRootAddSubdirectoryMask)) { throw 'UPDATE_SYSTEM_DRIVE_ROOT_DACL_UNSAFE' }
    if (-not (Test-F2UpdateSafeParentSddl -Sddl $programFilesSddl)) { throw 'UPDATE_PROGRAM_FILES_PARENT_DACL_UNSAFE' }
    if (-not (Test-F2UpdateSafeParentSddl -Sddl $programDataSddl -AllowProgramDataCreateMask)) { throw 'UPDATE_PROGRAM_DATA_PARENT_DACL_UNSAFE' }
    return $true
}

function Read-F2UpdateFileBytes {
    param([Parameter(Mandatory)][string]$Path,[int]$MaxBytes=16777216)
    $full = Test-F2UpdateNoReparsePath -Path $Path
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -gt $MaxBytes) { throw 'UPDATE_FILE_TYPE_OR_SIZE_INVALID' }
    return ,[IO.File]::ReadAllBytes($full)
}

function Assert-F2UpdateDacl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][ValidateSet('Directory','File')][string]$Kind,$Context)
    $hook = Get-F2UpdateHook -Context $Context -Name 'AclCheck'
    if ($null -ne $hook) {
        if (-not [bool](& $hook $Path $Kind)) { throw 'UPDATE_ACL_PROFILE_INVALID' }
        return $true
    }
    if (-not (Test-F2UpdateExactDacl -Sddl (Get-F2UpdateDaclSddl -Path $Path) -Kind $Kind)) { throw 'UPDATE_ACL_PROFILE_INVALID' }
    return $true
}

function Assert-F2UpdateDirectory {
    param([Parameter(Mandatory)][string]$Path,$Context,[switch]$RequireAbsent)
    $full = Test-F2UpdateNoReparsePath -Path $Path
    if ($RequireAbsent) {
        if ([IO.File]::Exists($full) -or [IO.Directory]::Exists($full)) { throw 'UPDATE_CREATE_NEW_COLLISION' }
        return $true
    }
    if (-not [IO.Directory]::Exists($full)) { throw 'UPDATE_REQUIRED_DIRECTORY_MISSING' }
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw 'UPDATE_REQUIRED_DIRECTORY_TYPE_INVALID' }
    Assert-F2UpdateDacl -Path $full -Kind Directory -Context $Context | Out-Null
    return $true
}

function Assert-F2UpdateFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedSha256,$Context,[int]$MaxBytes=16777216)
    $bytes = Read-F2UpdateFileBytes -Path $Path -MaxBytes $MaxBytes
    if ((Get-F2UpdateSha256 -Bytes $bytes) -cne $ExpectedSha256.ToLowerInvariant()) { throw 'UPDATE_FILE_HASH_MISMATCH' }
    Assert-F2UpdateDacl -Path $Path -Kind File -Context $Context | Out-Null
    return $bytes
}

function Assert-F2UpdateChildren {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExpectedNames,[switch]$AllowEmptyOnly)
    if (-not [IO.Directory]::Exists($Path)) { return }
    Test-F2UpdateNoReparsePath -Path $Path | Out-Null
    $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    if ($AllowEmptyOnly) {
        if ($items.Count -ne 0) { throw 'UPDATE_EXISTING_TRANSACTION_OBJECTS_PRESENT' }
        return
    }
    $names = @($items | ForEach-Object { [string]$_.Name })
    if ($names.Count -ne $ExpectedNames.Count -or @($names | Sort-Object -Unique).Count -ne $ExpectedNames.Count -or @(Compare-Object ($ExpectedNames | Sort-Object) ($names | Sort-Object) -CaseSensitive).Count -ne 0) { throw 'UPDATE_EXISTING_OBJECT_SET_INVALID' }
    foreach ($item in $items) { if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'UPDATE_REPARSE_POINT_REJECTED' } }
}

function Get-F2UpdateHeldManifestBytes {
    param([Parameter(Mandatory)][IO.FileStream]$Stream)
    if ($Stream.Length -lt 1 -or $Stream.Length -gt 65536) { throw 'UPDATE_MANIFEST_SIZE_INVALID' }
    $bytes = New-Object byte[] ([int]$Stream.Length)
    $Stream.Position = 0
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes,$offset,$bytes.Length-$offset)
        if ($read -le 0) { throw 'UPDATE_MANIFEST_READ_INCOMPLETE' }
        $offset += $read
    }
    $Stream.Position = 0
    return ,$bytes
}

function Get-F2UpdateManifestObject {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,[Parameter(Mandatory)][ValidateSet('v2','v3')][string]$ExpectedSchema,[string]$ExpectedHash)
    # Every unexpected PowerShell/.NET failure is reduced to the fixed code for
    # the operation in progress. Raw exception text, types, and values never
    # escape the parser or reach the elevated-child diagnostic channel.
    $operationFailureCode = 'UPDATE_MANIFEST_JSON_INVALID'
    try {
        $operationFailureCode = 'UPDATE_MANIFEST_SIZE_INVALID'
        if ($Bytes.Length -gt 65536 -or $Bytes.Length -eq 0) { throw 'UPDATE_MANIFEST_SIZE_INVALID' }

        $operationFailureCode = 'UPDATE_MANIFEST_HASH_MISMATCH'
        if (-not [string]::IsNullOrWhiteSpace($ExpectedHash) -and (Get-F2UpdateSha256 -Bytes $Bytes) -cne $ExpectedHash.ToLowerInvariant()) { throw 'UPDATE_MANIFEST_HASH_MISMATCH' }

        $operationFailureCode = 'UPDATE_MANIFEST_JSON_INVALID'
        try { $manifest = [Text.Encoding]::UTF8.GetString($Bytes) | ConvertFrom-Json -ErrorAction Stop } catch { throw 'UPDATE_MANIFEST_JSON_INVALID' }
        if ($null -eq $manifest -or $manifest -isnot [Management.Automation.PSCustomObject]) { throw 'UPDATE_MANIFEST_JSON_INVALID' }

        $operationFailureCode = 'UPDATE_MANIFEST_SCHEMA_INVALID'
        $schemaProperty = $manifest.PSObject.Properties['Schema']
        $schema = 'f2-icacls-runtime-release-' + $ExpectedSchema
        if ($null -eq $schemaProperty -or $schemaProperty.Value -isnot [string] -or $schemaProperty.Value -cne $schema) { throw 'UPDATE_MANIFEST_SCHEMA_INVALID' }

        $operationFailureCode = 'UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID'
        $identityValues = @{}
        foreach ($name in @('ReviewedCommitSha','BaselineMailboxId','BaselinePayloadCaptureId','BaselinePayloadSha256','BaselineIntegritySha256')) {
            $property = $manifest.PSObject.Properties[$name]
            if ($null -eq $property -or $property.Value -isnot [string]) { throw 'UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID' }
            $identityValues[$name] = [string]$property.Value
        }
        if ($identityValues['ReviewedCommitSha'] -notmatch '^[0-9a-f]{40}$' -or
            $identityValues['BaselineMailboxId'] -cne $script:F2UpdateBaselineMailboxId -or
            $identityValues['BaselinePayloadCaptureId'] -cne $script:F2UpdateBaselineCaptureId -or
            $identityValues['BaselinePayloadSha256'] -cne $script:F2UpdateBaselinePayloadSha256 -or
            $identityValues['BaselineIntegritySha256'] -cne $script:F2UpdateBaselineIntegritySha256) { throw 'UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID' }

        $operationFailureCode = 'UPDATE_SOURCE_PINS_HASH_INVALID'
        $sourcePinsProperty = $manifest.PSObject.Properties['SourcePinsManifestSha256']
        if ($null -eq $sourcePinsProperty -or $sourcePinsProperty.Value -isnot [string] -or $sourcePinsProperty.Value -notmatch '^[0-9a-f]{64}$') { throw 'UPDATE_SOURCE_PINS_HASH_INVALID' }

        $operationFailureCode = 'UPDATE_MANIFEST_FILE_SET_INVALID'
        $filesProperty = $manifest.PSObject.Properties['Files']
        if ($null -eq $filesProperty -or $filesProperty.Value -isnot [array]) { throw 'UPDATE_MANIFEST_FILE_SET_INVALID' }
        $files = @($filesProperty.Value)
        if ($files.Count -ne 7) { throw 'UPDATE_MANIFEST_FILE_SET_INVALID' }
        $manifestNames = @()
        foreach ($file in $files) {
            if ($null -eq $file -or $file -isnot [Management.Automation.PSCustomObject]) { throw 'UPDATE_MANIFEST_FILE_SET_INVALID' }
            $nameProperty = $file.PSObject.Properties['Name']
            if ($null -eq $nameProperty -or $nameProperty.Value -isnot [string]) { throw 'UPDATE_MANIFEST_FILE_SET_INVALID' }
            $manifestNames += [string]$nameProperty.Value

            $operationFailureCode = 'UPDATE_MANIFEST_FILE_PIN_INVALID'
            $shaProperty = $file.PSObject.Properties['Sha256']
            if ($null -eq $shaProperty -or $shaProperty.Value -isnot [string] -or $shaProperty.Value -notmatch '^[0-9a-f]{64}$') { throw 'UPDATE_MANIFEST_FILE_PIN_INVALID' }
            $operationFailureCode = 'UPDATE_MANIFEST_FILE_SET_INVALID'
        }
        $names = @($script:F2UpdateOldPins.Keys | Sort-Object)
        if (@($manifestNames | Sort-Object -Unique).Count -ne 7 -or @(Compare-Object $names ($manifestNames | Sort-Object) -CaseSensitive).Count -ne 0) { throw 'UPDATE_MANIFEST_FILE_SET_INVALID' }

        if ($ExpectedSchema -eq 'v3') {
            $operationFailureCode = 'UPDATE_MANIFEST_PACKAGE_ROOT_INVALID'
            $packageRootProperty = $manifest.PSObject.Properties['PackageRoot']
            if ($null -eq $packageRootProperty -or $packageRootProperty.Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$packageRootProperty.Value)) { throw 'UPDATE_MANIFEST_PACKAGE_ROOT_INVALID' }
        }
        return $manifest
    } catch {
        $caughtCode = ''
        if ($null -ne $_.Exception) { try { $caughtCode = [string]$_.Exception.Message } catch { $caughtCode = '' } }
        $safeManifestCodes = @(
            'UPDATE_MANIFEST_SIZE_INVALID','UPDATE_MANIFEST_HASH_MISMATCH','UPDATE_MANIFEST_JSON_INVALID',
            'UPDATE_MANIFEST_SCHEMA_INVALID','UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID',
            'UPDATE_SOURCE_PINS_HASH_INVALID','UPDATE_MANIFEST_FILE_SET_INVALID',
            'UPDATE_MANIFEST_FILE_PIN_INVALID','UPDATE_MANIFEST_PACKAGE_ROOT_INVALID'
        )
        if ($caughtCode -cin $safeManifestCodes) { throw $caughtCode }
        throw $operationFailureCode
    }
}

function Get-F2UpdateRuntimePathInventory {
    param($Context)
    $oldSourceRoot = if ($null -ne $Context.Hooks -and $null -ne $Context.PSObject.Properties['OldRuntimeSourceRoot']) { [string]$Context.OldRuntimeSourceRoot } else { 'C:\Dev\f2-g1-capture-id-contract-source' }
    $newSourceRoot = [string]$Context.SourceRoot
    $versionRoot = Join-Path (Join-Path $Context.PackageHome 'releases') $Context.ExpectedSourceCommit
    $roots = @(
        (Join-Path $Context.PackageHome 'scripts\f2-acl'),
        (Join-Path $versionRoot 'scripts\f2-acl'),
        (Join-Path $oldSourceRoot 'scripts\f2-acl'),
        (Join-Path $newSourceRoot 'scripts\f2-acl')
    )
    $names = @('Invoke-F2IcaclsCapture.ps1','Invoke-F2IcaclsProtectedCoordinator.ps1','F2AclIcacls.Runtime.psm1')
    $paths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($root in $roots) { foreach ($name in $names) { $paths.Add([IO.Path]::GetFullPath((Join-Path $root $name))) } }
    return [string[]]$paths.ToArray()
}

function Test-F2UpdateAuthorizedRequesterProcess {
    param($Process,$Context)
    $commandLine = [string]$Process.CommandLine
    if ([string]::IsNullOrWhiteSpace($commandLine) -or $commandLine.Length -gt 32767) { return $false }
    if ($commandLine -match '(?i)(?:^|\s)-(?:encodedcommand|enc)(?:\s|:|$)' -or $commandLine -notmatch '(?i)(?:^|\s)-(?:command|c)(?:\s|:|$)') { return $false }
    $expectedLauncherPath = Join-Path $Context.SourceRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'
    foreach ($value in @([IO.Path]::GetFullPath($expectedLauncherPath),'. ([scriptblock]::Create($text))','Invoke-F2ProtectedReleaseUpdateLauncher')) {
        if ([string]::IsNullOrWhiteSpace($value) -or $commandLine.IndexOf($value,[StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false }
    }
    foreach ($pair in @(
        @('ExpectedSourceCommit',[string]$Context.ExpectedSourceCommit),
        @('ExpectedUpdaterSha256',[string]$Context.UpdaterSha256),
        @('ExpectedLauncherSha256',[string]$Context.ExpectedLauncherSha256),
        @('ExpectedCandidateManifestSha256',[string]$Context.CandidateManifestSha256)
    )) {
        if ([string]::IsNullOrWhiteSpace($pair[1]) -or $commandLine -notmatch ('(?i)-' + [regex]::Escape($pair[0]) + '\s+"?' + [regex]::Escape($pair[1]) + '"?(?=\s|;|\}|$)')) { return $false }
    }
    return $true
}

function Test-F2UpdateProcessInventory {
    param([AllowEmptyCollection()][object[]]$Processes,[int]$CurrentProcessId,$Context)
    if ($null -eq $Processes) { throw 'UPDATE_PROCESS_INVENTORY_UNKNOWN' }
    if ($CurrentProcessId -le 0 -or [int]$Context.RequesterLauncherProcessId -le 0 -or [int]$Context.RequesterLauncherProcessId -eq $CurrentProcessId -or [long]$Context.RequesterLauncherCreationUtcTicks -le 0) { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
    $currentCount = 0; $authorizedLauncherCount = 0; $seen = @{}
    $runtimePaths = @(Get-F2UpdateRuntimePathInventory -Context $Context | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
    foreach ($process in $Processes) {
        if ($null -eq $process -or $null -eq $process.PSObject.Properties['ProcessId'] -or $null -eq $process.PSObject.Properties['Name']) { throw 'UPDATE_PROCESS_INVENTORY_UNKNOWN' }
        $processId = 0
        if (-not [int]::TryParse([string]$process.ProcessId,[ref]$processId) -or $processId -le 0 -or $seen.ContainsKey($processId)) { throw 'UPDATE_PROCESS_INVENTORY_UNKNOWN' }
        $seen[$processId] = $true
        $name = [string]$process.Name
        if ($name -notmatch '^(?i:powershell|powershell_ise|pwsh)\.exe$') { throw 'UPDATE_PROCESS_INVENTORY_UNKNOWN' }
        if ($processId -eq $CurrentProcessId) {
            if ($name -ine 'powershell.exe') { throw 'UPDATE_PROCESS_SELF_IDENTITY_UNKNOWN' }
            $currentCount++
            continue
        }
        if ($null -eq $process.PSObject.Properties['CommandLine'] -or [string]::IsNullOrWhiteSpace([string]$process.CommandLine)) { throw 'UPDATE_PROCESS_COMMAND_LINE_UNKNOWN' }
        $commandLine = [string]$process.CommandLine
        foreach ($path in $runtimePaths) {
            if ($commandLine.IndexOf($path,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw 'UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN' }
        }
        if ($processId -eq [int]$Context.RequesterLauncherProcessId) {
            if ($name -ine 'powershell.exe') { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
            if ($null -eq $process.PSObject.Properties['CreationUtcTicks'] -or [long]$process.CreationUtcTicks -ne [long]$Context.RequesterLauncherCreationUtcTicks) { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
            if ($null -eq $process.PSObject.Properties['OwnerSid'] -or [string]$process.OwnerSid -cne [string]$Context.ExpectedRequesterSid) { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
            if (-not (Test-F2UpdateAuthorizedRequesterProcess -Process $process -Context $Context)) { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
            $authorizedLauncherCount++
            if ($authorizedLauncherCount -gt 1) { throw 'UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN' }
            continue
        }
        # Unknown, unrelated, direct-module and encoded PowerShell invocations
        # are all excluded. Command-line heuristics are not used to bless them.
        throw 'UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN'
    }
    if ($currentCount -ne 1) { throw 'UPDATE_PROCESS_SELF_IDENTITY_UNKNOWN' }
    if ($authorizedLauncherCount -ne 1) { throw 'UPDATE_REQUESTER_LAUNCHER_UNKNOWN' }
    return $true
}

function Assert-F2UpdateProcessQuiescence {
    param($Context)
    $inventoryHook = Get-F2UpdateHook -Context $Context -Name 'ProcessInventory'
    if ($null -ne $inventoryHook) {
        try { $processes = @(& $inventoryHook $Context) } catch { throw 'UPDATE_PROCESS_INVENTORY_UNKNOWN' }
        $currentProcessId = if ($null -ne $Context.PSObject.Properties['CurrentProcessId']) { [int]$Context.CurrentProcessId } else { 1000 }
    } else {
        try { $rawProcesses = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe' OR Name='powershell_ise.exe' OR Name='pwsh.exe'" -ErrorAction Stop) }
        catch { throw 'UPDATE_PROCESS_INVENTORY_UNKNOWN' }
        $currentProcessId = $PID
        $normalized = New-Object 'System.Collections.Generic.List[object]'
        foreach ($process in $rawProcesses) {
            $creationTicks = 0L; $ownerSid = ''
            if ([int]$process.ProcessId -eq [int]$Context.RequesterLauncherProcessId) {
                try {
                    $creationTicks = ([datetime]$process.CreationDate).ToUniversalTime().Ticks
                    $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
                    if ([uint32]$owner.ReturnValue -ne 0 -or $null -eq $owner.Sid) { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
                    $ownerSid = [string]$owner.Sid
                } catch { throw 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN' }
            }
            $normalized.Add([pscustomobject]@{ProcessId=[int]$process.ProcessId;Name=[string]$process.Name;CommandLine=[string]$process.CommandLine;CreationUtcTicks=$creationTicks;OwnerSid=$ownerSid})
        }
        $processes = $normalized.ToArray()
    }
    return Test-F2UpdateProcessInventory -Processes $processes -CurrentProcessId $currentProcessId -Context $Context
}

function New-F2UpdateNativeSupport {
    if ($null -ne ('F2Update.NativeOps' -as [type])) { return }
    try { Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace F2Update {
  public static class NativeOps {
    [StructLayout(LayoutKind.Sequential)] private struct SECURITY_ATTRIBUTES { public int nLength; public IntPtr lpSecurityDescriptor; [MarshalAs(UnmanagedType.Bool)] public bool bInheritHandle; }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl,uint revision,out IntPtr descriptor,out uint size);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateFileW")] private static extern SafeFileHandle CreateFileNative(string path,uint access,uint share,ref SECURITY_ATTRIBUTES attributes,uint creation,uint flags,IntPtr template);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateDirectoryW")] private static extern bool CreateDirectoryNative(string path,ref SECURITY_ATTRIBUTES attributes);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="GetNamedSecurityInfoW")] private static extern uint GetNamedSecurityInfoNative(string path,int objectType,uint securityInfo,out IntPtr owner,out IntPtr group,out IntPtr dacl,out IntPtr sacl,out IntPtr descriptor);
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr descriptor,uint revision,uint securityInfo,out IntPtr text,out uint chars);
    [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);
    public static string GetSddl(string path) {
      IntPtr owner,group,dacl,sacl,descriptor; uint status=GetNamedSecurityInfoNative(path,1,0x7,out owner,out group,out dacl,out sacl,out descriptor);
      if(status!=0) throw new Win32Exception((int)status,"Owner/DACL query failed.");
      try { IntPtr text;uint chars;if(!ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor,1,0x7,out text,out chars))throw new Win32Exception(Marshal.GetLastWin32Error());
        try{return Marshal.PtrToStringUni(text);}finally{LocalFree(text);}
      } finally {LocalFree(descriptor);}
    }
    public static void CreateDirectory(string path,string sddl) {
      IntPtr descriptor;uint size;if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl,1,out descriptor,out size))throw new Win32Exception(Marshal.GetLastWin32Error());
      try { SECURITY_ATTRIBUTES a=new SECURITY_ATTRIBUTES();a.nLength=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));a.lpSecurityDescriptor=descriptor;a.bInheritHandle=false;
        if(!CreateDirectoryNative(path,ref a))throw new Win32Exception(Marshal.GetLastWin32Error(),"Create-new protected directory failed.");
      } finally {LocalFree(descriptor);}
    }
    public static void CreateNew(string path, byte[] bytes, string sddl) {
      IntPtr descriptor; uint size;
      if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl,1,out descriptor,out size)) throw new Win32Exception(Marshal.GetLastWin32Error());
      try {
        SECURITY_ATTRIBUTES attributes=new SECURITY_ATTRIBUTES(); attributes.nLength=Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES)); attributes.lpSecurityDescriptor=descriptor; attributes.bInheritHandle=false;
        using(SafeFileHandle handle=CreateFileNative(path,0x40000000,0,ref attributes,1,0x80,IntPtr.Zero)) {
          if(handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(),"Create-new protected file failed.");
          using(FileStream stream=new FileStream(handle,FileAccess.Write)) { stream.Write(bytes,0,bytes.Length); stream.Flush(true); }
        }
      } finally { LocalFree(descriptor); }
    }
  }
}
'@ -ErrorAction Stop
    } catch { throw 'UPDATE_NATIVE_HELPER_COMPILE_FAILED' }
}

function New-F2UpdateDirectory {
    param([Parameter(Mandatory)][string]$Path,$Context)
    Assert-F2UpdateDirectory -Path $Path -Context $Context -RequireAbsent | Out-Null
    $hook = Get-F2UpdateHook -Context $Context -Name 'CreateDirectory'
    if ($null -ne $hook) { & $hook $Path; Assert-F2UpdateDacl -Path $Path -Kind Directory -Context $Context | Out-Null; return }
    $sddl = 'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200A9;;;AU)'
    New-F2UpdateNativeSupport
    [F2Update.NativeOps]::CreateDirectory($Path,$sddl)
    Assert-F2UpdateDacl -Path $Path -Kind Directory -Context $Context | Out-Null
}

function Write-F2UpdateNewFile {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,$Context,[ValidateSet('File','Directory')][string]$Kind='File')
    Assert-F2UpdateDirectory -Path (Split-Path -Parent $Path) -Context $Context | Out-Null
    Assert-F2UpdateDirectory -Path $Path -Context $Context -RequireAbsent | Out-Null
    $hook = Get-F2UpdateHook -Context $Context -Name 'WriteFile'
    if ($null -ne $hook) { & $hook $Path $Bytes $Kind; Assert-F2UpdateDacl -Path $Path -Kind File -Context $Context | Out-Null; return }
    New-F2UpdateNativeSupport
    $sddl = 'O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200A9;;;AU)'
    [F2Update.NativeOps]::CreateNew($Path,$Bytes,$sddl)
    Assert-F2UpdateDacl -Path $Path -Kind File -Context $Context | Out-Null
}

function Add-F2UpdateJournalRecord {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$TxId,[Parameter(Mandatory)][string]$State,[Parameter(Mandatory)][AllowEmptyString()][string]$PreviousHash,$Context)
    $record = [ordered]@{TxId=$TxId;State=$State;PreviousHash=$PreviousHash;Utc=[DateTime]::UtcNow.ToString('o')}
    $json = $record | ConvertTo-Json -Compress
    $body = [Text.Encoding]::UTF8.GetBytes($json)
    $hash = Get-F2UpdateSha256 -Bytes $body
    $line = [Text.Encoding]::UTF8.GetBytes(($json + "`n"))
    $hook = Get-F2UpdateHook -Context $Context -Name 'AppendJournal'
    if ($null -ne $hook) { & $hook $Path $line; return $hash }
    $stream = [IO.File]::Open($Path,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $stream.Write($line,0,$line.Length);$stream.Flush($true) } finally { $stream.Dispose() }
    return $hash
}

function Invoke-F2UpdateFaultPoint {
    param([string]$Name,$Context)
    if ($null -ne $Context.TransactionState) {
        $state = $Context.TransactionState
        $state.JournalHash = Add-F2UpdateJournalRecord -Path $state.JournalPath -TxId $state.TxId -State ('OPERATION:' + $Name) -PreviousHash $state.JournalHash -Context $Context
    }
    $hook = Get-F2UpdateHook -Context $Context -Name 'AfterOperation'
    if ($null -ne $hook) { & $hook $Name }
}

function Get-F2UpdateSourceBytes {
    param($Context)
    Set-F2UpdateDiagnosticStage -Context $Context -Stage 'SourceGitValidation' | Out-Null
    $hook = Get-F2UpdateHook -Context $Context -Name 'SourceBytes'
    if ($null -ne $hook) { return & $hook $Context }
    $root = [IO.Path]::GetFullPath([string]$Context.SourceRoot)
    Test-F2UpdateNoReparsePath -Path $root | Out-Null
    $git = Get-Command git.exe -ErrorAction Stop
    $head = (& $git.Source -C $root rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -cne $Context.ExpectedSourceCommit) { throw 'UPDATE_SOURCE_COMMIT_MISMATCH' }
    $origin = (& $git.Source -C $root remote get-url origin 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $origin -cne 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git') { throw 'UPDATE_SOURCE_ORIGIN_MISMATCH' }
    $status = @(& $git.Source -C $root status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0 -or $status.Count -ne 0) { throw 'UPDATE_SOURCE_WORKTREE_NOT_CLEAN' }
    Set-F2UpdateDiagnosticStage -Context $Context -Stage 'SourcePackagePinValidation' | Out-Null
    $result = @{}
    foreach ($name in @($script:F2UpdateOldPins.Keys)) {
        $path = Join-Path (Join-Path $root 'scripts\f2-acl') $name
        $bytes = Read-F2UpdateFileBytes -Path $path
        $expected = @($Context.Manifest.Files | Where-Object { $_.Name -ceq $name })
        if ($expected.Count -ne 1 -or (Get-F2UpdateSha256 -Bytes $bytes) -cne $expected[0].Sha256) { throw ('UPDATE_SOURCE_PACKAGE_HASH_MISMATCH:' + $name) }
        $result[$name] = $bytes
    }
    $pins = [Text.Encoding]::UTF8.GetString([byte[]]$result['F2_ICACLS_SOURCE_PINS.json']) | ConvertFrom-Json -ErrorAction Stop
    if ((Get-F2UpdateSha256 -Bytes $result['F2_ICACLS_SOURCE_PINS.json']) -cne $Context.Manifest.SourcePinsManifestSha256) { throw 'UPDATE_SOURCE_PIN_MANIFEST_HASH_MISMATCH' }
    if ($pins.Schema -cne 'f2-icacls-corroboration-pins-v1' -or $pins.ReviewedCollectorBaseSha -cne $script:F2UpdateOriginalCollectorBaseSha) { throw 'UPDATE_SOURCE_PIN_PROVENANCE_INVALID' }
    $pinMap = @{
        'F2AclCapture.Protocol.psm1' = [string]$pins.ProtocolModuleSha256
        'F2AclIcacls.Corroboration.psm1' = [string]$pins.CorroborationModuleSha256
        'F2AclIcacls.Runtime.psm1' = [string]$pins.RuntimeModuleSha256
        'Invoke-F2IcaclsCapture.ps1' = [string]$pins.LauncherScriptSha256
        'Invoke-F2IcaclsProtectedCoordinator.ps1' = [string]$pins.CoordinatorScriptSha256
        'Invoke-F2AclReadOnlyCapture.ps1' = [string]$pins.CollectorScriptSha256
    }
    foreach ($name in $pinMap.Keys) { if ((Get-F2UpdateSha256 -Bytes $result[$name]) -cne $pinMap[$name]) { throw ('UPDATE_SOURCE_INTERNAL_PIN_MISMATCH:' + $name) } }
    return $result
}

function Test-F2UpdateInstalledOldRelease {
    param($Context,[byte[]]$ActiveManifestBytes,[string]$ExpectedReleaseCommit,[string]$ExpectedTransactionId,[string]$ExpectedBackupTransactionId,[switch]$PostActivation)
    $oldPackage = Join-Path $Context.PackageHome 'scripts\f2-acl'
    Assert-F2UpdateDirectory -Path $Context.PackageHome -Context $Context | Out-Null
    Assert-F2UpdateDirectory -Path (Join-Path $Context.PackageHome 'scripts') -Context $Context | Out-Null
    Assert-F2UpdateDirectory -Path $oldPackage -Context $Context | Out-Null
    $packageHomeChildren = @('scripts')
    if ([IO.Directory]::Exists((Join-Path $Context.PackageHome 'releases'))) { $packageHomeChildren += 'releases' }
    Assert-F2UpdateChildren -Path $Context.PackageHome -ExpectedNames $packageHomeChildren
    Assert-F2UpdateChildren -Path (Join-Path $Context.PackageHome 'scripts') -ExpectedNames @('f2-acl')
    Assert-F2UpdateChildren -Path $oldPackage -ExpectedNames @($script:F2UpdateOldPins.Keys)
    foreach ($name in $script:F2UpdateOldPins.Keys) { [void](Assert-F2UpdateFile -Path (Join-Path $oldPackage $name) -ExpectedSha256 $script:F2UpdateOldPins[$name] -Context $Context) }
    Assert-F2UpdateDirectory -Path $Context.ProgramDataRoot -Context $Context | Out-Null
    $programDataChildren = @('approved-release.json')
    if ([IO.File]::Exists((Join-Path $Context.ProgramDataRoot 'release.lock'))) { $programDataChildren += 'release.lock' }
    if ([IO.Directory]::Exists((Join-Path $Context.ProgramDataRoot 'updates'))) { $programDataChildren += 'updates' }
    if ([IO.Directory]::Exists((Join-Path $Context.ProgramDataRoot 'backups'))) { $programDataChildren += 'backups' }
    Assert-F2UpdateChildren -Path $Context.ProgramDataRoot -ExpectedNames $programDataChildren
    $updatesRoot = Join-Path $Context.ProgramDataRoot 'updates'
    $backupsRoot = Join-Path $Context.ProgramDataRoot 'backups'
    if ([IO.Directory]::Exists($updatesRoot) -and -not [string]::IsNullOrEmpty($ExpectedTransactionId)) {
        Assert-F2UpdateChildren -Path $updatesRoot -ExpectedNames @($ExpectedTransactionId)
        $transactionChildren = if ($PostActivation) { @('transaction.ndjson') } else { @('transaction.ndjson','approved-release.new.json') }
        Assert-F2UpdateChildren -Path (Join-Path $updatesRoot $ExpectedTransactionId) -ExpectedNames $transactionChildren
    } else { Assert-F2UpdateChildren -Path $updatesRoot -ExpectedNames @() -AllowEmptyOnly }
    if ([IO.Directory]::Exists($backupsRoot) -and -not [string]::IsNullOrEmpty($ExpectedBackupTransactionId)) {
        Assert-F2UpdateChildren -Path $backupsRoot -ExpectedNames @($ExpectedBackupTransactionId + '.approved-release.v2.json')
    } else { Assert-F2UpdateChildren -Path $backupsRoot -ExpectedNames @() -AllowEmptyOnly }
    $releasesRoot = Join-Path $Context.PackageHome 'releases'
    if ([IO.Directory]::Exists($releasesRoot) -and -not [string]::IsNullOrEmpty($ExpectedReleaseCommit)) {
        Assert-F2UpdateChildren -Path $releasesRoot -ExpectedNames @($ExpectedReleaseCommit)
        Assert-F2UpdateDirectory -Path (Join-Path $releasesRoot $ExpectedReleaseCommit) -Context $Context | Out-Null
    } else { Assert-F2UpdateChildren -Path $releasesRoot -ExpectedNames @() -AllowEmptyOnly }
    if ($null -ne $ActiveManifestBytes) {
        $oldBytes = $ActiveManifestBytes
        if ((Get-F2UpdateSha256 -Bytes $oldBytes) -cne $script:F2UpdateOldManifestSha256) { throw 'UPDATE_FILE_HASH_MISMATCH' }
        Assert-F2UpdateDacl -Path $Context.ActiveManifestPath -Kind File -Context $Context | Out-Null
    } else { $oldBytes = Assert-F2UpdateFile -Path $Context.ActiveManifestPath -ExpectedSha256 $script:F2UpdateOldManifestSha256 -Context $Context -MaxBytes 65536 }
    $oldManifest = Get-F2UpdateManifestObject -Bytes $oldBytes -ExpectedSchema v2 -ExpectedHash $script:F2UpdateOldManifestSha256
    if ($oldManifest.ReviewedCommitSha -cne $script:F2UpdateOldCommit) { throw 'UPDATE_OLD_RELEASE_COMMIT_MISMATCH' }
    foreach ($file in @($oldManifest.Files)) { if ($script:F2UpdateOldPins[$file.Name] -cne $file.Sha256) { throw 'UPDATE_OLD_RELEASE_PIN_MISMATCH' } }
    return $oldManifest
}

function Test-F2UpdateCandidate {
    param($Context)
    $bytes = [byte[]]$Context.CandidateManifestBytes
    $manifest = Get-F2UpdateManifestObject -Bytes $bytes -ExpectedSchema v3 -ExpectedHash ([string]$Context.CandidateManifestSha256)
    if ($manifest.ReviewedCommitSha -cne $Context.ExpectedSourceCommit) { throw 'UPDATE_CANDIDATE_COMMIT_MISMATCH' }
    $expectedPackageRoot = Join-Path (Join-Path $Context.PackageHome 'releases') $manifest.ReviewedCommitSha
    if (-not [string]::Equals([IO.Path]::GetFullPath([string]$manifest.PackageRoot),[IO.Path]::GetFullPath($expectedPackageRoot),[StringComparison]::OrdinalIgnoreCase)) { throw 'UPDATE_CANDIDATE_PACKAGE_ROOT_MISMATCH' }
    return $manifest
}

function Test-F2UpdateRuntimeProcessPaths {
    param($Context)
    $null = Get-F2UpdateRuntimePathInventory -Context $Context
    Assert-F2UpdateProcessQuiescence -Context $Context | Out-Null
}

function Invoke-F2UpdateTransaction {
    param([Parameter(Mandatory)]$Context)
    $manifest=$null; $source=$null; $txId=$null; $lease=$null; $manifestBarrier=$null;$activeState='UNKNOWN'
    try {
        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'CandidateManifestValidation' | Out-Null
        $manifest = Test-F2UpdateCandidate -Context $Context
        $Context.Manifest = $manifest
        $source = Get-F2UpdateSourceBytes -Context $Context
        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'ParentAclValidation' | Out-Null
        Test-F2UpdateParentChains -Context $Context | Out-Null
        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'InstalledV2Validation' | Out-Null
        $null = Test-F2UpdateInstalledOldRelease -Context $Context
        $activeState = $script:F2UpdateOldManifestSha256
        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'TransactionCollisionValidation' | Out-Null
        $releaseRoot = Join-Path $Context.PackageHome 'releases'
        if ([IO.Directory]::Exists($releaseRoot)) { Assert-F2UpdateDirectory -Path $releaseRoot -Context $Context | Out-Null }
        elseif ([IO.File]::Exists($releaseRoot)) { throw 'UPDATE_RELEASE_ROOT_TYPE_INVALID' }
        $updateRoot = Join-Path $Context.ProgramDataRoot 'updates'
        $backupRoot = Join-Path $Context.ProgramDataRoot 'backups'
        foreach ($root in @($updateRoot,$backupRoot)) { if ([IO.File]::Exists($root)) { throw 'UPDATE_TRANSACTION_ROOT_TYPE_INVALID' }; if ([IO.Directory]::Exists($root)) { Assert-F2UpdateDirectory -Path $root -Context $Context | Out-Null } }
        $lockPath = Join-Path $Context.ProgramDataRoot 'release.lock'
        if ([IO.File]::Exists($lockPath)) { [void](Assert-F2UpdateFile -Path $lockPath -ExpectedSha256 (Get-F2UpdateSha256 -Bytes ([byte[]]@())) -Context $Context -MaxBytes 1) }
        elseif ([IO.Directory]::Exists($lockPath)) { throw 'UPDATE_RELEASE_LOCK_TYPE_INVALID' }

        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'AcquireReleaseBarrier' | Out-Null
        # The updater's one pinned elevated bootstrap verifies the updater and
        # candidate bytes before calling this function. The shared lease blocks
        # new v3 readers. The manifest barrier blocks fresh v2 manifest reads;
        # the process inventory rejects every other PowerShell host so a v2
        # process that cached the old manifest before the barrier cannot survive
        # unnoticed. A second inventory sits at the activation edge.
        $lockHook = Get-F2UpdateHook -Context $Context -Name 'AcquireLocks'
        if ($null -ne $lockHook) {
            $lockResult = & $lockHook $lockPath $Context.ActiveManifestPath
            if ($null -ne $lockResult -and $null -ne $lockResult.PSObject.Properties['Lease'] -and $null -ne $lockResult.PSObject.Properties['ManifestBarrier']) { $lease = $lockResult.Lease;$manifestBarrier = $lockResult.ManifestBarrier }
            else { $lease = $lockResult }
        }
        else {
            if (-not [IO.File]::Exists($lockPath)) {
                $leaseBytes = [byte[]]@()
                $writeHook = Get-F2UpdateHook -Context $Context -Name 'WriteFile'
                try {
                    if ($null -ne $writeHook) { & $writeHook $lockPath $leaseBytes 'File' }
                    else { New-F2UpdateNativeSupport;[F2Update.NativeOps]::CreateNew($lockPath,$leaseBytes,'O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200A9;;;AU)') }
                } catch { throw 'UPDATE_RELEASE_LOCK_CREATE_FAILED' }
                Invoke-F2UpdateFaultPoint -Name 'ReleaseLeaseCreated' -Context $Context
            }
            [void](Assert-F2UpdateFile -Path $lockPath -ExpectedSha256 (Get-F2UpdateSha256 -Bytes ([byte[]]@())) -Context $Context -MaxBytes 1)
            $lease = [IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            $manifestBarrier = [IO.File]::Open($Context.ActiveManifestPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Delete)
        }
        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'RuntimeQuiescence' | Out-Null
        Test-F2UpdateRuntimeProcessPaths -Context $Context
        if ($null -eq $manifestBarrier) { throw 'UPDATE_MANIFEST_BARRIER_UNAVAILABLE' }
        $barrierBytes = Get-F2UpdateHeldManifestBytes -Stream $manifestBarrier
        $null = Test-F2UpdateInstalledOldRelease -Context $Context -ActiveManifestBytes $barrierBytes

        $txId = [guid]::NewGuid().ToString('N')
        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'CreateTransactionRoots' | Out-Null
        if (-not [IO.Directory]::Exists($releaseRoot)) { New-F2UpdateDirectory -Path $releaseRoot -Context $Context; Invoke-F2UpdateFaultPoint -Name 'ReleaseRootCreated' -Context $Context }
        if (-not [IO.Directory]::Exists($updateRoot)) { New-F2UpdateDirectory -Path $updateRoot -Context $Context; Invoke-F2UpdateFaultPoint -Name 'UpdateRootCreated' -Context $Context }
        if (-not [IO.Directory]::Exists($backupRoot)) { New-F2UpdateDirectory -Path $backupRoot -Context $Context; Invoke-F2UpdateFaultPoint -Name 'BackupRootCreated' -Context $Context }
        $stageRoot = Join-Path $releaseRoot ('.f2-update-' + $txId + '.new')
        $finalRoot = Join-Path $releaseRoot $manifest.ReviewedCommitSha
        $programDataTxRoot = Join-Path $updateRoot $txId
        $journalPath = Join-Path $programDataTxRoot 'transaction.ndjson'
        $candidatePath = Join-Path $programDataTxRoot 'approved-release.new.json'
        $backupPath = Join-Path (Join-Path $Context.ProgramDataRoot 'backups') ($txId + '.approved-release.v2.json')
        Assert-F2UpdateDirectory -Path $finalRoot -Context $Context -RequireAbsent | Out-Null
        Assert-F2UpdateDirectory -Path $stageRoot -Context $Context -RequireAbsent | Out-Null
        Assert-F2UpdateDirectory -Path $updateRoot -Context $Context | Out-Null
        Assert-F2UpdateDirectory -Path $backupRoot -Context $Context | Out-Null
        Assert-F2UpdateDirectory -Path $programDataTxRoot -Context $Context -RequireAbsent | Out-Null
        Assert-F2UpdateDirectory -Path $backupPath -Context $Context -RequireAbsent | Out-Null
        Assert-F2UpdateDirectory -Path $candidatePath -Context $Context -RequireAbsent | Out-Null

        New-F2UpdateDirectory -Path $programDataTxRoot -Context $Context
        Write-F2UpdateNewFile -Path $journalPath -Bytes ([byte[]]@()) -Context $Context
        $initialJournalHash = Add-F2UpdateJournalRecord -Path $journalPath -TxId $txId -State 'PREPARED' -PreviousHash '' -Context $Context
        $Context.TransactionState = [pscustomobject]@{TxId=$txId;JournalPath=$journalPath;JournalHash=$initialJournalHash}
        Invoke-F2UpdateFaultPoint -Name 'JournalCreated' -Context $Context
        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'StagePackage' | Out-Null
        New-F2UpdateDirectory -Path $stageRoot -Context $Context
        Invoke-F2UpdateFaultPoint -Name 'StageRootCreated' -Context $Context
        $scriptsRoot = Join-Path $stageRoot 'scripts'
        $aclRoot = Join-Path $scriptsRoot 'f2-acl'
        New-F2UpdateDirectory -Path $scriptsRoot -Context $Context
        Invoke-F2UpdateFaultPoint -Name 'ScriptsDirectoryCreated' -Context $Context
        New-F2UpdateDirectory -Path $aclRoot -Context $Context
        Invoke-F2UpdateFaultPoint -Name 'PackageDirectoryCreated' -Context $Context
        foreach ($name in @($script:F2UpdateOldPins.Keys)) {
            Write-F2UpdateNewFile -Path (Join-Path $aclRoot $name) -Bytes $source[$name] -Context $Context
            Invoke-F2UpdateFaultPoint -Name ('PackageFileCreated:' + $name) -Context $Context
        }
        foreach ($file in @($manifest.Files)) { [void](Assert-F2UpdateFile -Path (Join-Path $aclRoot $file.Name) -ExpectedSha256 $file.Sha256 -Context $Context) }
        [void](Test-F2UpdateExactDacl -Sddl 'O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200A9;;;AU)' -Kind Directory)
        Invoke-F2UpdateFaultPoint -Name 'StagedPackageVerified' -Context $Context

        Write-F2UpdateNewFile -Path $candidatePath -Bytes ([byte[]]$Context.CandidateManifestBytes) -Context $Context
        Invoke-F2UpdateFaultPoint -Name 'CandidateManifestStaged' -Context $Context

        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'ActivatePackageSideBySide' | Out-Null
        $moveHook = Get-F2UpdateHook -Context $Context -Name 'DirectoryMove'
        if ($null -ne $moveHook) { & $moveHook $stageRoot $finalRoot }
        else { [IO.Directory]::Move($stageRoot,$finalRoot) }
        Invoke-F2UpdateFaultPoint -Name 'PackageActivatedSideBySide' -Context $Context
        Invoke-F2UpdateFaultPoint -Name 'JournalPackageReady' -Context $Context

        Set-F2UpdateDiagnosticStage -Context $Context -Stage 'ActivateManifest' | Out-Null
        $replaceHook = Get-F2UpdateHook -Context $Context -Name 'ReplaceManifest'
        $activeState = 'UNKNOWN'
        # Recheck at the activation edge. The manifest barrier is still held:
        # pre-barrier cached readers must be visible in this inventory, while
        # post-barrier supported readers cannot obtain the old manifest.
        Test-F2UpdateRuntimeProcessPaths -Context $Context
        if ($null -ne $replaceHook) { & $replaceHook $candidatePath $Context.ActiveManifestPath $backupPath }
        else { [IO.File]::Replace($candidatePath,$Context.ActiveManifestPath,$backupPath,$false) }
        $activeState = [string]$Context.CandidateManifestSha256
        Invoke-F2UpdateFaultPoint -Name 'ReleaseManifestActivated' -Context $Context
        $activeBytes = Read-F2UpdateFileBytes -Path $Context.ActiveManifestPath -MaxBytes 65536
        if ((Get-F2UpdateSha256 -Bytes $activeBytes) -cne $Context.CandidateManifestSha256) { throw 'UPDATE_ACTIVE_MANIFEST_POSTCHECK_FAILED' }
        Assert-F2UpdateDacl -Path $Context.ActiveManifestPath -Kind File -Context $Context | Out-Null
        foreach ($file in @($manifest.Files)) { [void](Assert-F2UpdateFile -Path (Join-Path (Join-Path $finalRoot 'scripts\f2-acl') $file.Name) -ExpectedSha256 $file.Sha256 -Context $Context) }
        $backupBytes = Get-F2UpdateHeldManifestBytes -Stream $manifestBarrier
        if ((Get-F2UpdateSha256 -Bytes $backupBytes) -cne $script:F2UpdateOldManifestSha256) { throw 'UPDATE_OLD_MANIFEST_BACKUP_INVALID' }
        Assert-F2UpdateDacl -Path $backupPath -Kind File -Context $Context | Out-Null
        if ((Get-F2UpdateManifestObject -Bytes $backupBytes -ExpectedSchema v2).ReviewedCommitSha -cne $script:F2UpdateOldCommit) { throw 'UPDATE_OLD_MANIFEST_BACKUP_INVALID' }
        Invoke-F2UpdateFaultPoint -Name 'JournalCommitted' -Context $Context
        return [pscustomobject]@{Success=$true;Outcome='UPDATE_COMPLETE';TransactionId=$txId;ReviewedCommitSha=$manifest.ReviewedCommitSha;OldReleaseCommitSha=$script:F2UpdateOldCommit;PackageRoot=$finalRoot;OldReleaseRetained=$true;OldManifestBackup=$backupPath;JournalPath=$journalPath;InstalledFiles=7;PartialStagePaths=@()}
    } catch {
        $safeCode = [string]$_.Exception.Message
        if ($_.Exception -is [Management.Automation.CommandNotFoundException] -and [string]$_.Exception.CommandName -ieq 'git.exe') { $safeCode = 'UPDATE_SOURCE_GIT_UNAVAILABLE' }
        if ($safeCode -notmatch '^[A-Z0-9_:.\-]{1,100}$') { $safeCode = 'UPDATE_UNCLASSIFIED_FAILURE' }
        $innerType = if ($null -ne $_.Exception.InnerException) { $_.Exception.InnerException.GetType().FullName } else { $null }
        return [pscustomobject]@{Success=$false;Outcome='UPDATE_BLOCKED';Stage=(Get-F2UpdateDiagnosticStage -Context $Context);ErrorCode=$safeCode;FailureType=$_.Exception.GetType().FullName;FailureInnerType=$innerType;TransactionId=$txId;ActiveManifestSha256=$activeState;PartialObjectsPreserved=$true;CleanupPerformed=$false}
    } finally {
        if ($null -ne $manifestBarrier) { try { $manifestBarrier.Dispose() } catch {} }
        if ($null -ne $lease) { try { $lease.Dispose() } catch {} }
    }
}

function Resolve-F2UpdateTransaction {
    param([Parameter(Mandatory)]$Context,[Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$TransactionId,[switch]$ResumeForward)
    $root = Join-Path (Join-Path $Context.ProgramDataRoot 'updates') $TransactionId
    Test-F2UpdateNoReparsePath -Path $root | Out-Null
    $journal = Join-Path $root 'transaction.ndjson'
    $journalBytes = Read-F2UpdateFileBytes -Path $journal -MaxBytes 262144
    $lines = @([Text.Encoding]::UTF8.GetString($journalBytes) -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -lt 1 -or $lines.Count -gt 64) { throw 'UPDATE_RECOVERY_JOURNAL_INCOMPLETE' }
    $records = @();$previous=''
    foreach ($line in $lines) {
        try { $record = $line | ConvertFrom-Json -ErrorAction Stop } catch { throw 'UPDATE_RECOVERY_JOURNAL_INVALID' }
        if ($record.TxId -cne $TransactionId -or $record.PreviousHash -cne $previous) { throw 'UPDATE_RECOVERY_JOURNAL_CHAIN_INVALID' }
        $body = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress))
        $previous = Get-F2UpdateSha256 -Bytes $body
        $records += $record
    }
    $requiredStates = @('PREPARED','OPERATION:JournalCreated','OPERATION:StageRootCreated','OPERATION:ScriptsDirectoryCreated','OPERATION:PackageDirectoryCreated')
    foreach ($name in @($script:F2UpdateOldPins.Keys)) { $requiredStates += 'OPERATION:PackageFileCreated:' + $name }
    $requiredStates += @('OPERATION:StagedPackageVerified','OPERATION:CandidateManifestStaged','OPERATION:PackageActivatedSideBySide')
    $readyStates = @($requiredStates + 'OPERATION:JournalPackageReady')
    $observedStates = @($records | ForEach-Object { [string]$_.State })
    $matchesStates = {
        param([string[]]$Expected)
        if ($observedStates.Count -ne $Expected.Count) { return $false }
        for ($i=0; $i -lt $Expected.Count; $i++) { if ($observedStates[$i] -cne $Expected[$i]) { return $false } }
        return $true
    }.GetNewClosure()
    Assert-F2UpdateDacl -Path $root -Kind Directory -Context $Context | Out-Null
    Assert-F2UpdateDacl -Path $journal -Kind File -Context $Context | Out-Null
    $manifestBytes = Read-F2UpdateFileBytes -Path $Context.ActiveManifestPath -MaxBytes 65536
    $manifestHash = Get-F2UpdateSha256 -Bytes $manifestBytes
    if ($manifestHash -ceq $script:F2UpdateOldManifestSha256) {
        if (-not $ResumeForward) { return [pscustomobject]@{State='OLD_RELEASE_ACTIVE';TransactionId=$TransactionId;Action='PRESERVE_ALL_OBJECTS'} }
        if (-not (& $matchesStates $requiredStates) -and -not (& $matchesStates $readyStates)) { throw 'UPDATE_RECOVERY_JOURNAL_STATE_INVALID' }
        $newManifest = Test-F2UpdateCandidate -Context $Context
        $candidatePath = Join-Path $root 'approved-release.new.json'
        $finalRoot = [IO.Path]::GetFullPath([string]$newManifest.PackageRoot)
        $backupPath = Join-Path (Join-Path $Context.ProgramDataRoot 'backups') ($TransactionId + '.approved-release.v2.json')
        $stageRoot = Join-Path (Join-Path $Context.PackageHome 'releases') ('.f2-update-' + $TransactionId + '.new')
        if ([IO.Directory]::Exists($stageRoot) -or [IO.File]::Exists($stageRoot) -or -not [IO.Directory]::Exists($finalRoot) -or [IO.File]::Exists($backupPath) -or [IO.Directory]::Exists($backupPath)) { throw 'UPDATE_RECOVERY_OBJECT_SET_INVALID' }
        foreach ($file in @($newManifest.Files)) { [void](Assert-F2UpdateFile -Path (Join-Path (Join-Path $finalRoot 'scripts\f2-acl') $file.Name) -ExpectedSha256 $file.Sha256 -Context $Context) }
        [void](Assert-F2UpdateFile -Path $candidatePath -ExpectedSha256 $Context.CandidateManifestSha256 -Context $Context -MaxBytes 65536)
        $null = Test-F2UpdateInstalledOldRelease -Context $Context -ExpectedReleaseCommit $newManifest.ReviewedCommitSha -ExpectedTransactionId $TransactionId
        $lease=$null;$barrier=$null
        try {
            $lockHook = Get-F2UpdateHook -Context $Context -Name 'AcquireLocks'
            if ($null -ne $lockHook) {
                $lockResult = & $lockHook (Join-Path $Context.ProgramDataRoot 'release.lock') $Context.ActiveManifestPath
                if ($null -ne $lockResult -and $null -ne $lockResult.PSObject.Properties['Lease'] -and $null -ne $lockResult.PSObject.Properties['ManifestBarrier']) { $lease = $lockResult.Lease;$barrier = $lockResult.ManifestBarrier }
                else { $lease = $lockResult }
            }
            else { $lease=[IO.File]::Open((Join-Path $Context.ProgramDataRoot 'release.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$barrier=[IO.File]::Open($Context.ActiveManifestPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Delete) }
            Test-F2UpdateRuntimeProcessPaths -Context $Context
            [IO.File]::Replace($candidatePath,$Context.ActiveManifestPath,$backupPath,$false)
            $newBytes=Read-F2UpdateFileBytes -Path $Context.ActiveManifestPath -MaxBytes 65536
            if ((Get-F2UpdateSha256 -Bytes $newBytes) -cne $Context.CandidateManifestSha256) { throw 'UPDATE_RECOVERY_POSTCHECK_FAILED' }
            Assert-F2UpdateDacl -Path $Context.ActiveManifestPath -Kind File -Context $Context | Out-Null
            $oldBackupBytes = Get-F2UpdateHeldManifestBytes -Stream $barrier
            if ((Get-F2UpdateSha256 -Bytes $oldBackupBytes) -cne $script:F2UpdateOldManifestSha256) { throw 'UPDATE_RECOVERY_OLD_BACKUP_INVALID' }
            Assert-F2UpdateDacl -Path $backupPath -Kind File -Context $Context | Out-Null
            if ((Get-F2UpdateManifestObject -Bytes $oldBackupBytes -ExpectedSchema v2 -ExpectedHash $script:F2UpdateOldManifestSha256).ReviewedCommitSha -cne $script:F2UpdateOldCommit) { throw 'UPDATE_RECOVERY_OLD_BACKUP_INVALID' }
            $null = Test-F2UpdateInstalledOldRelease -Context $Context -ActiveManifestBytes $oldBackupBytes -ExpectedReleaseCommit $newManifest.ReviewedCommitSha -ExpectedTransactionId $TransactionId -ExpectedBackupTransactionId $TransactionId -PostActivation
            $null = Add-F2UpdateJournalRecord -Path $journal -TxId $TransactionId -State 'RECOVERED_COMMIT' -PreviousHash $previous -Context $Context
            return [pscustomobject]@{State='NEW_RELEASE_ACTIVATED_BY_RECOVERY';TransactionId=$TransactionId;Action='FORWARD_COMMIT';OldBackupRetained=$true}
        } finally { if($null -ne $barrier){$barrier.Dispose()};if($null -ne $lease){$lease.Dispose()} }
    }
    $newManifest = Test-F2UpdateCandidate -Context $Context
    if ($manifestHash -ceq $Context.CandidateManifestSha256) {
        $activeStates = @($readyStates + 'OPERATION:ReleaseManifestActivated')
        $committedStates = @($activeStates + 'OPERATION:JournalCommitted')
        $recoveredStates = @($activeStates + 'RECOVERED_COMMIT')
        if (-not (& $matchesStates $requiredStates) -and -not (& $matchesStates $readyStates) -and -not (& $matchesStates $activeStates) -and -not (& $matchesStates $committedStates) -and -not (& $matchesStates $recoveredStates)) { throw 'UPDATE_RECOVERY_JOURNAL_STATE_INVALID' }
        foreach ($file in @($newManifest.Files)) { [void](Assert-F2UpdateFile -Path (Join-Path (Join-Path $newManifest.PackageRoot 'scripts\f2-acl') $file.Name) -ExpectedSha256 $file.Sha256 -Context $Context) }
        $backupPath = Join-Path (Join-Path $Context.ProgramDataRoot 'backups') ($TransactionId + '.approved-release.v2.json')
        $oldBackupBytes = Assert-F2UpdateFile -Path $backupPath -ExpectedSha256 $script:F2UpdateOldManifestSha256 -Context $Context -MaxBytes 65536
        if ((Get-F2UpdateManifestObject -Bytes $oldBackupBytes -ExpectedSchema v2 -ExpectedHash $script:F2UpdateOldManifestSha256).ReviewedCommitSha -cne $script:F2UpdateOldCommit) { throw 'UPDATE_RECOVERY_OLD_BACKUP_INVALID' }
        $null = Test-F2UpdateInstalledOldRelease -Context $Context -ActiveManifestBytes $oldBackupBytes -ExpectedReleaseCommit $newManifest.ReviewedCommitSha -ExpectedTransactionId $TransactionId -ExpectedBackupTransactionId $TransactionId -PostActivation
        return [pscustomobject]@{State='NEW_RELEASE_ACTIVE';TransactionId=$TransactionId;Action='VERIFY_ONLY'}
    }
    throw 'UPDATE_RECOVERY_ACTIVE_MANIFEST_UNKNOWN'
}

function Invoke-F2ProtectedReleaseRecovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$CandidateManifestBytes,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$CandidateManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedUpdaterSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedLauncherSha256,
        [Parameter(Mandatory)][string]$SourceRoot,
        [Parameter(Mandatory)][ValidatePattern('^S-1-')][string]$ExpectedRequesterSid,
        [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$RequesterLauncherProcessId,
        [Parameter(Mandatory)][ValidateRange(1,9223372036854775807)][long]$RequesterLauncherCreationUtcTicks,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$TransactionId,
        [switch]$ResumeForward
    )
    Test-F2UpdateElevationIdentity -ExpectedRequesterSid $ExpectedRequesterSid | Out-Null
    $manifest = Get-F2UpdateManifestObject -Bytes $CandidateManifestBytes -ExpectedSchema v3 -ExpectedHash $CandidateManifestSha256
    $context = [pscustomobject]@{
        SourceRoot=[IO.Path]::GetFullPath($SourceRoot);ExpectedSourceCommit=[string]$manifest.ReviewedCommitSha
        CandidateManifestBytes=$CandidateManifestBytes;CandidateManifestSha256=$CandidateManifestSha256;Manifest=$manifest
        UpdaterSha256=$ExpectedUpdaterSha256;ExpectedLauncherSha256=$ExpectedLauncherSha256;ExpectedRequesterSid=$ExpectedRequesterSid
        RequesterLauncherProcessId=$RequesterLauncherProcessId;RequesterLauncherCreationUtcTicks=$RequesterLauncherCreationUtcTicks
        PackageHome=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'F2-G1-Icacls')
        ProgramDataRoot=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'F2-G1-Icacls')
        ActiveManifestPath=(Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'F2-G1-Icacls') 'approved-release.json')
        Hooks=$null;DiagnosticStage='UpdaterInvocation'
    }
    [void](Get-F2UpdateSourceBytes -Context $context)
    Test-F2UpdateParentChains -Context $context | Out-Null
    $lockPath = Join-Path $context.ProgramDataRoot 'release.lock'
    if (-not [IO.File]::Exists($lockPath) -or [IO.Directory]::Exists($lockPath)) { throw 'UPDATE_RECOVERY_LOCK_MISSING_OR_INVALID' }
    [void](Assert-F2UpdateFile -Path $lockPath -ExpectedSha256 (Get-F2UpdateSha256 -Bytes ([byte[]]@())) -Context $context -MaxBytes 1)
    return Resolve-F2UpdateTransaction -Context $context -TransactionId $TransactionId -ResumeForward:$ResumeForward
}

function Invoke-F2ProtectedReleaseUpdate {
    # Called only by a separately pinned, one-read in-memory elevated bootstrap.
    # SourceRoot selects bytes, but its clean origin/commit and every package
    # byte are revalidated before the updater writes anything.
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$CandidateManifestBytes,[Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$CandidateManifestSha256,[Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedUpdaterSha256,[Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedLauncherSha256,[Parameter(Mandatory)][string]$SourceRoot,[Parameter(Mandatory)][ValidatePattern('^S-1-')][string]$ExpectedRequesterSid,[Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$RequesterLauncherProcessId,[Parameter(Mandatory)][ValidateRange(1,9223372036854775807)][long]$RequesterLauncherCreationUtcTicks)
    Test-F2UpdateElevationIdentity -ExpectedRequesterSid $ExpectedRequesterSid | Out-Null
    $manifest = Get-F2UpdateManifestObject -Bytes $CandidateManifestBytes -ExpectedSchema v3 -ExpectedHash $CandidateManifestSha256
    $context = [pscustomobject]@{
        SourceRoot=[IO.Path]::GetFullPath($SourceRoot);ExpectedSourceCommit=[string]$manifest.ReviewedCommitSha
        CandidateManifestBytes=$CandidateManifestBytes;CandidateManifestSha256=$CandidateManifestSha256
        UpdaterSha256=$ExpectedUpdaterSha256;ExpectedLauncherSha256=$ExpectedLauncherSha256;ExpectedRequesterSid=$ExpectedRequesterSid
        RequesterLauncherProcessId=$RequesterLauncherProcessId;RequesterLauncherCreationUtcTicks=$RequesterLauncherCreationUtcTicks
        PackageHome=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'F2-G1-Icacls')
        ProgramDataRoot=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'F2-G1-Icacls')
        ActiveManifestPath=(Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'F2-G1-Icacls') 'approved-release.json')
        Hooks=$null;DiagnosticStage='UpdaterInvocation'
    }
    return Invoke-F2UpdateTransaction -Context $context
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2ApprovedInstallerPath = 'C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1'
$script:F2ApprovedInstallerSha256 = 'cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118'
$script:F2InstallerMaximumBytes = 1048576
$script:F2DiagnosticSchema = 'f2-install-diagnostic-v1'
$script:F2DiagnosticMaximumBytes = 4096
$script:F2DiagnosticStages = @('BootstrapArgumentValidation','BootstrapSourceVerification','BootstrapInstallerExecution','Preflight','CreateStagingDirectories','CopyCreateNewPackageFiles','PrePublishAttestation','PublishCreateNewDirectories','PostInstallAttestation','BootstrapDiagnosticPublication')
$script:F2DiagnosticErrorCodes = @('BASELINE_DIRECTORY_SCOPE_MISMATCH','BASELINE_INTEGRITY_DOCUMENT_INVALID','BASELINE_MAILBOX_ACE_INVALID','BASELINE_MAILBOX_ACL_INVALID','BASELINE_MAILBOX_OR_PAYLOAD_CAPTURE_ID_MISMATCH','BASELINE_PATH_SET_INVALID','BASELINE_PAYLOAD_IDENTITY_OR_COMPLETENESS_INVALID','BASELINE_PIN_MISMATCH','BASELINE_REQUESTER_IDENTITY_UNKNOWN','BOOTSTRAP_ARGUMENTS_NOT_ACCEPTED','BOOTSTRAP_DIAGNOSTIC_DIRECTORY_INVALID','BOOTSTRAP_DIAGNOSTIC_DACL_INVALID','BOOTSTRAP_DIAGNOSTIC_FIELDS_INVALID','BOOTSTRAP_DIAGNOSTIC_NONCE_INVALID','BOOTSTRAP_DIAGNOSTIC_PARENT_UNKNOWN','BOOTSTRAP_DIAGNOSTIC_PATH_INVALID','BOOTSTRAP_DIAGNOSTIC_PUBLICATION_FAILED','BOOTSTRAP_DIAGNOSTIC_SIZE_INVALID','BOOTSTRAP_EXECUTION_FAILED','BOOTSTRAP_EXPECTED_HASH_INVALID','BOOTSTRAP_INSTALLER_ENCODING_INVALID','BOOTSTRAP_INSTALLER_HASH_MISMATCH','BOOTSTRAP_INSTALLER_SIZE_INVALID','BOOTSTRAP_REVIEWED_LAUNCHER_REQUIRED','INSTALL_CREATE_NEW_DIRECTORY_COLLISION','INSTALL_CREATED_DIRECTORY_ACL_MISMATCH','INSTALL_CREATED_FILE_ACL_MISMATCH','INSTALL_DIRECTORY_ATTESTATION_FAILED','INSTALL_OPERATION_FAILED','INSTALL_PACKAGE_FILE_ATTESTATION_FAILED','INSTALL_PARENT_CHAIN_UNKNOWN','INSTALL_PATH_PARENT_UNKNOWN','INSTALL_PARENT_DACL_UNSAFE','INSTALL_REQUIRES_REVIEWED_UAC_LAUNCH','INSTALL_RELEASE_MANIFEST_ATTESTATION_FAILED','INSTALL_REPARSE_POINT','INSTALL_SOURCE_FILE_TYPE_OR_SIZE','INSTALL_SOURCE_SHORT_READ','INSTALL_SYSTEM_DRIVE_ROOT_DACL_UNSAFE','INSTALL_TARGET_ALREADY_EXISTS','INSTALL_TARGET_PATH_NOT_CANONICAL','MAILBOX_PATH_INVALID','POST_INSTALL_DIRECTORY_ATTESTATION_FAILED','POST_INSTALL_PACKAGE_FILE_ATTESTATION_FAILED','POST_INSTALL_RELEASE_ATTESTATION_FAILED','SOURCE_PIN_MANIFEST_HASH_MISMATCH','SOURCE_PIN_MANIFEST_IDENTITY_INVALID','SOURCE_PINS_DO_NOT_MATCH_PACKAGE','TEMP_VOLUME_NOT_FIXED')

function Get-F2BootstrapHashBytes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-F2BootstrapDiagnosticFileSecurity {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedOwnerSid)
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    $raw=[Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access))
    if($raw.Owner.Value-cne$ExpectedOwnerSid-or($raw.ControlFlags-band[Security.AccessControl.ControlFlags]::DiscretionaryAclProtected)-eq 0-or$null-eq$raw.DiscretionaryAcl-or@($raw.DiscretionaryAcl).Count-ne 2){throw 'BOOTSTRAP_DIAGNOSTIC_DACL_INVALID'}
    $expected=@{'S-1-5-18'=[uint32]0x001F01FF;$ExpectedOwnerSid=[uint32]0x001F01FF};$seen=@{}
    foreach($ace in $raw.DiscretionaryAcl){$sid=$ace.SecurityIdentifier.Value;$mask=[uint32]([int64]$ace.AccessMask-band 0xFFFFFFFFL);if(-not$expected.ContainsKey($sid)-or$seen.ContainsKey($sid)-or$ace.AceQualifier-ne[Security.AccessControl.AceQualifier]::AccessAllowed-or$mask-ne$expected[$sid]-or[int]$ace.AceFlags-ne 0){throw 'BOOTSTRAP_DIAGNOSTIC_DACL_INVALID'};$seen[$sid]=$true}
    if($seen.Count-ne 2){throw 'BOOTSTRAP_DIAGNOSTIC_DACL_INVALID'}
    return $true
}

function Publish-F2InstallDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Nonce,
        [Parameter(Mandatory)][ValidateSet('Bootstrap','Installer')][string]$Component,
        [Parameter(Mandatory)][ValidateSet('BOOTSTRAP_BLOCKED','INSTALL_BLOCKED','INSTALL_COMPLETE')][string]$Outcome,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$ErrorCode
    )

    if ($Stage -cnotin $script:F2DiagnosticStages -or $ErrorCode -cnotin $script:F2DiagnosticErrorCodes -and $ErrorCode -cne 'NONE' -or $Nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'BOOTSTRAP_DIAGNOSTIC_FIELDS_INVALID' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sid = $identity.User.Value
    Test-F2BootstrapMailbox -Directory $Directory -ExpectedOwnerSid $sid | Out-Null
    if (-not [string]::Equals([IO.Path]::GetFullPath($Directory),$Directory,[StringComparison]::OrdinalIgnoreCase)) { throw 'BOOTSTRAP_DIAGNOSTIC_PATH_INVALID' }

    $record = [ordered]@{ Schema=$script:F2DiagnosticSchema; Nonce=$Nonce; Component=$Component; Outcome=$Outcome; Stage=$Stage; ErrorCode=$ErrorCode }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($record | ConvertTo-Json -Compress -Depth 3))
    if ($bytes.Length -lt 1 -or $bytes.Length -gt $script:F2DiagnosticMaximumBytes) { throw 'BOOTSTRAP_DIAGNOSTIC_SIZE_INVALID' }

    $temporaryPath = Join-Path $Directory ('.result-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $resultPath = Join-Path $Directory 'result.json'
    try {
        $fileSecurity=[Security.AccessControl.FileSecurity]::new()
        $fileSecurity.SetSecurityDescriptorSddlForm(('O:{0}D:P(A;;FA;;;SY)(A;;FA;;;{0})' -f $sid))
        $stream=New-Object IO.FileStream($temporaryPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough,$fileSecurity)
        try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) }
        finally { $stream.Dispose() }
        Test-F2BootstrapDiagnosticFileSecurity -Path $temporaryPath -ExpectedOwnerSid $sid | Out-Null
        # Same-directory move publishes a complete record and never replaces a prior file.
        [IO.File]::Move($temporaryPath,$resultPath)
    } catch {
        try { if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) } } catch { }
        throw 'BOOTSTRAP_DIAGNOSTIC_PUBLICATION_FAILED'
    }
}

function Test-F2BootstrapMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)][string]$ExpectedOwnerSid)
    $full = [IO.Path]::GetFullPath($Directory)
    if (-not [string]::Equals($full,$Directory,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetPathRoot($full) -match '^\\') { throw 'BOOTSTRAP_DIAGNOSTIC_PATH_INVALID' }
    $leaf = [IO.Path]::GetFileName($full)
    if ($leaf -cnotmatch '^F2-G1-Install-[0-9a-f]{32}$' -or -not (Test-Path -LiteralPath $full -PathType Container)) { throw 'BOOTSTRAP_DIAGNOSTIC_DIRECTORY_INVALID' }
    $expectedTemp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $actualParent=[IO.Directory]::GetParent($full)
    if($null-eq $actualParent-or -not [string]::Equals($actualParent.FullName.TrimEnd('\'),$expectedTemp,[StringComparison]::OrdinalIgnoreCase)){throw 'BOOTSTRAP_DIAGNOSTIC_PATH_INVALID'}
    $current = $full
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BOOTSTRAP_DIAGNOSTIC_REPARSE' }
        $root = [IO.Path]::GetPathRoot($current)
        if ([string]::Equals($current.TrimEnd('\'),$root.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw 'BOOTSTRAP_DIAGNOSTIC_PARENT_UNKNOWN' }
        $current = $parent.FullName
    }
    $acl = Get-Acl -LiteralPath $full -ErrorAction Stop
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access))
    if ($raw.Owner.Value -cne $ExpectedOwnerSid -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $null -eq $raw.DiscretionaryAcl -or @($raw.DiscretionaryAcl).Count -ne 2) { throw 'BOOTSTRAP_DIAGNOSTIC_DACL_INVALID' }
    $expected = @{'S-1-5-18'=[uint32]0x001F01FF;$ExpectedOwnerSid=[uint32]0x001F01FF}
    $expectedFlags = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
    $seen = @{}
    foreach ($ace in $raw.DiscretionaryAcl) {
        $sid = $ace.SecurityIdentifier.Value
        $mask = [uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        if (-not $expected.ContainsKey($sid) -or $seen.ContainsKey($sid) -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $mask -ne $expected[$sid] -or [int]$ace.AceFlags -ne $expectedFlags) { throw 'BOOTSTRAP_DIAGNOSTIC_DACL_INVALID' }
        $seen[$sid] = $true
    }
    if ($seen.Count -ne 2) { throw 'BOOTSTRAP_DIAGNOSTIC_DACL_INVALID' }
    return $true
}

function ConvertTo-F2BootstrapSafeErrorCode {
    param([Parameter(Mandatory)]$Result)
    $errorProperty = $Result.PSObject.Properties['ErrorCode']
    if ($null -eq $errorProperty) { return 'INSTALL_OPERATION_FAILED' }
    $candidate = [string]$errorProperty.Value
    if ($candidate -cin $script:F2DiagnosticErrorCodes) { return $candidate }
    return 'INSTALL_OPERATION_FAILED'
}

function Invoke-F2VerifiedInstallerCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallerPath,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)][string]$DiagnosticDirectory,
        [Parameter(Mandatory)][string]$CorrelationNonce
    )

    $stage = 'BootstrapSourceVerification'
    try {
        if ($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'BOOTSTRAP_EXPECTED_HASH_INVALID' }
        if ($CorrelationNonce -cnotmatch '^[0-9a-f]{32}$') { throw 'BOOTSTRAP_DIAGNOSTIC_NONCE_INVALID' }
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        Test-F2BootstrapMailbox -Directory $DiagnosticDirectory -ExpectedOwnerSid $identity.User.Value | Out-Null

        # Read exactly once. Hash, decode and execute this same in-memory byte array.
        $bytes = [IO.File]::ReadAllBytes($InstallerPath)
        if ($bytes.Length -lt 1 -or $bytes.Length -gt $script:F2InstallerMaximumBytes) { throw 'BOOTSTRAP_INSTALLER_SIZE_INVALID' }
        if ((Get-F2BootstrapHashBytes -Bytes $bytes) -cne $ExpectedSha256) { throw 'BOOTSTRAP_INSTALLER_HASH_MISMATCH' }
        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        try { $source = $utf8.GetString($bytes) } catch { throw 'BOOTSTRAP_INSTALLER_ENCODING_INVALID' }
        if ($source.Length -gt 0 -and $source[0] -eq [char]0xFEFF) { $source = $source.Substring(1) }

        $stage = 'BootstrapInstallerExecution'
        $verifiedScript = [ScriptBlock]::Create($source)
        # Dot-source only the already verified ScriptBlock. The reviewed PS 5.1
        # tests verify that Invoke-F2InstallMain is visible in this invocation scope.
        . $verifiedScript
        $result = Invoke-F2InstallMain
        if ($null -eq $result -or $result -isnot [psobject] -or $null -eq $result.PSObject.Properties['Success']) { throw 'INSTALL_RESULT_INVALID' }

        $outcome = if ($result.Success) { 'INSTALL_COMPLETE' } else { 'INSTALL_BLOCKED' }
        $stageProperty = $result.PSObject.Properties['Stage']
        $diagnosticStage = if ($null -ne $stageProperty) { [string]$stageProperty.Value } else { '' }
        if ($diagnosticStage -cnotin $script:F2DiagnosticStages) { $diagnosticStage = if ($result.Success) { 'PostInstallAttestation' } else { 'Preflight' } }
        $errorCode = if ($result.Success) { 'NONE' } else { ConvertTo-F2BootstrapSafeErrorCode -Result $result }
        Publish-F2InstallDiagnostic -Directory $DiagnosticDirectory -Nonce $CorrelationNonce -Component 'Installer' -Outcome $outcome -Stage $diagnosticStage -ErrorCode $errorCode
        return [pscustomobject]@{ ChildExitCode=if($result.Success){0}else{1}; DiagnosticPublished=$true; Stage=$diagnosticStage; ErrorCode=$errorCode; Outcome=$outcome }
    } catch {
        $candidate = [string]$_.Exception.Message
        $errorCode = if ($candidate -cin $script:F2DiagnosticErrorCodes) { $candidate } else { 'BOOTSTRAP_EXECUTION_FAILED' }
        $published = $false
        try {
            Publish-F2InstallDiagnostic -Directory $DiagnosticDirectory -Nonce $CorrelationNonce -Component 'Bootstrap' -Outcome 'BOOTSTRAP_BLOCKED' -Stage $stage -ErrorCode $errorCode
            $published = $true
        } catch { }
        return [pscustomobject]@{ ChildExitCode=1; DiagnosticPublished=$published; Stage=$stage; ErrorCode=$errorCode; Outcome='BOOTSTRAP_BLOCKED' }
    }
}

function Invoke-F2VerifiedInstallerMain {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DiagnosticDirectory,[Parameter(Mandatory)][string]$CorrelationNonce)
    return Invoke-F2VerifiedInstallerCore -InstallerPath $script:F2ApprovedInstallerPath -ExpectedSha256 $script:F2ApprovedInstallerSha256 -DiagnosticDirectory $DiagnosticDirectory -CorrelationNonce $CorrelationNonce
}

# This source is normally dot-sourced by the hash-pinned elevated command built
# by Start-F2VerifiedInstall.ps1. Direct encoded/file invocations are diagnostic
# only and can never install without that reviewed caller.
if ($MyInvocation.InvocationName -ne '.') {
    try {
        $unbound = @($MyInvocation.UnboundArguments)
        if ($unbound.Count -eq 0) { throw 'BOOTSTRAP_REVIEWED_LAUNCHER_REQUIRED' }
        if ($unbound.Count -ne 2) { throw 'BOOTSTRAP_ARGUMENTS_NOT_ACCEPTED' }
        $diagnosticDirectory = [string]$unbound[0]
        $correlationNonce = [string]$unbound[1]
        if ($correlationNonce -cnotmatch '^[0-9a-f]{32}$') { throw 'BOOTSTRAP_DIAGNOSTIC_NONCE_INVALID' }
        $run = Invoke-F2VerifiedInstallerMain -DiagnosticDirectory $diagnosticDirectory -CorrelationNonce $correlationNonce
        exit [int]$run.ChildExitCode
    } catch {
        $code = [string]$_.Exception.Message
        if ($code -cnotin $script:F2DiagnosticErrorCodes) { $code = 'BOOTSTRAP_EXECUTION_FAILED' }
        [Console]::Error.WriteLine(('F2_INSTALL_BOOTSTRAP: ' + $code))
        exit 1
    }
}

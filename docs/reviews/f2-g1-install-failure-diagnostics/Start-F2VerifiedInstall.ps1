Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2InstallBootstrapPath = 'C:\Dev\f2-g1-protected-install-prep\Invoke-F2VerifiedInstaller.ps1'
$script:F2InstallBootstrapSha256 = '6f47d802a2cd5d7deb65083c546829de6a71d26356dcf2b71f6cc6f14d81a4a9'
$script:F2InstallInstallerPath = 'C:\Dev\f2-g1-protected-install-prep\Install-F2IcaclsProtectedPackage.ps1'
$script:F2InstallInstallerSha256 = 'cf8abc7c94186f44044684e77eb432c3a20a20c3cfd8fb099b6e32e4a2ca0118'
$script:F2InstallMaximumSourceBytes = 1048576
$script:F2DiagnosticMaximumBytes = 4096
$script:F2DiagnosticStages = @('BootstrapArgumentValidation','BootstrapSourceVerification','BootstrapInstallerExecution','Preflight','CreateStagingDirectories','CopyCreateNewPackageFiles','PrePublishAttestation','PublishCreateNewDirectories','PostInstallAttestation','BootstrapDiagnosticPublication')
$script:F2DiagnosticErrorCodes = @('BASELINE_DIRECTORY_SCOPE_MISMATCH','BASELINE_INTEGRITY_DOCUMENT_INVALID','BASELINE_MAILBOX_ACE_INVALID','BASELINE_MAILBOX_ACL_INVALID','BASELINE_MAILBOX_OR_PAYLOAD_CAPTURE_PIN_MISMATCH','BASELINE_PATH_SET_INVALID','BASELINE_PAYLOAD_IDENTITY_OR_COMPLETENESS_INVALID','BASELINE_PIN_MISMATCH','BASELINE_REQUESTER_IDENTITY_UNKNOWN','BOOTSTRAP_ARGUMENTS_NOT_ACCEPTED','BOOTSTRAP_DIAGNOSTIC_DIRECTORY_INVALID','BOOTSTRAP_DIAGNOSTIC_DACL_INVALID','BOOTSTRAP_DIAGNOSTIC_FIELDS_INVALID','BOOTSTRAP_DIAGNOSTIC_NONCE_INVALID','BOOTSTRAP_DIAGNOSTIC_PARENT_UNKNOWN','BOOTSTRAP_DIAGNOSTIC_PATH_INVALID','BOOTSTRAP_DIAGNOSTIC_PUBLICATION_FAILED','BOOTSTRAP_DIAGNOSTIC_SIZE_INVALID','BOOTSTRAP_EXECUTION_FAILED','BOOTSTRAP_EXPECTED_HASH_INVALID','BOOTSTRAP_INSTALLER_ENCODING_INVALID','BOOTSTRAP_INSTALLER_HASH_MISMATCH','BOOTSTRAP_INSTALLER_SIZE_INVALID','BOOTSTRAP_REVIEWED_LAUNCHER_REQUIRED','INSTALL_CREATE_NEW_DIRECTORY_COLLISION','INSTALL_CREATED_DIRECTORY_ACL_MISMATCH','INSTALL_CREATED_FILE_ACL_MISMATCH','INSTALL_DIRECTORY_ATTESTATION_FAILED','INSTALL_OPERATION_FAILED','INSTALL_PACKAGE_FILE_ATTESTATION_FAILED','INSTALL_PARENT_CHAIN_UNKNOWN','INSTALL_PATH_PARENT_UNKNOWN','INSTALL_PARENT_DACL_UNSAFE','INSTALL_REQUIRES_REVIEWED_UAC_LAUNCH','INSTALL_RELEASE_MANIFEST_ATTESTATION_FAILED','INSTALL_REPARSE_POINT','INSTALL_SOURCE_FILE_TYPE_OR_SIZE','INSTALL_SOURCE_SHORT_READ','INSTALL_SYSTEM_DRIVE_ROOT_DACL_UNSAFE','INSTALL_TARGET_ALREADY_EXISTS','INSTALL_TARGET_PATH_NOT_CANONICAL','POST_INSTALL_DIRECTORY_ATTESTATION_FAILED','POST_INSTALL_PACKAGE_FILE_ATTESTATION_FAILED','POST_INSTALL_RELEASE_ATTESTATION_FAILED','SOURCE_PIN_MANIFEST_HASH_MISMATCH','SOURCE_PIN_MANIFEST_IDENTITY_INVALID','SOURCE_PINS_DO_NOT_MATCH_PACKAGE')
$script:F2LauncherErrorCodes = @('BOOTSTRAP_HASH_MISMATCH','BOOTSTRAP_PARSE_FAILED','DIAGNOSTIC_NONCE_INVALID','DIAGNOSTIC_PATH_NOT_CANONICAL','ELEVATED_COMMAND_TOO_LARGE','INSTALLER_HASH_MISMATCH','LAUNCHER_ARGUMENTS_NOT_ACCEPTED','MAILBOX_NAME_COLLISION','MAILBOX_NOT_EMPTY','MAILBOX_OWNER_OR_DACL_INVALID','PATH_PARENT_UNKNOWN','PATH_REPARSE_POINT','SOURCE_SHORT_READ','SOURCE_TYPE_OR_SIZE_INVALID','TEMP_VOLUME_NOT_FIXED','TEMP_VOLUME_NOT_LOCAL','WINDOWS_POWERSHELL_51_NOT_FOUND','WINDOWS_POWERSHELL_51_REQUIRED')
$script:F2DiagnosticErrorCodes += @('MAILBOX_PATH_INVALID','TEMP_VOLUME_NOT_FIXED')
$script:F2LauncherErrorCodes += @('LAUNCHER_MUST_RUN_UNELEVATED')
$script:F2InstallPowerShell51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:F2InstallStartProcessProvider = $null # Synthetic tests only; production leaves null.

function Get-F2InstallLauncherHash {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2InstallLaunchIdentity {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=[Security.Principal.WindowsPrincipal]::new($identity)
    return [pscustomobject]@{Sid=$identity.User.Value;IsAdministrator=[bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
}

function Read-F2InstallLauncherBytes {
    param([Parameter(Mandatory)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -lt 1 -or $item.Length -gt $script:F2InstallMaximumSourceBytes) { throw 'SOURCE_TYPE_OR_SIZE_INVALID' }
    $stream = [IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) { $read = $stream.Read($bytes,$offset,$bytes.Length-$offset); if ($read -le 0) { throw 'SOURCE_SHORT_READ' }; $offset += $read }
        return ,$bytes
    } finally { $stream.Dispose() }
}

function Test-F2InstallLauncherNoReparseChain {
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PATH_REPARSE_POINT' }
        }
        $root = [IO.Path]::GetPathRoot($current)
        if ([string]::Equals($current.TrimEnd('\'),$root.TrimEnd('\'),[StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw 'PATH_PARENT_UNKNOWN' }
        $current = $parent.FullName
    }
}

function Get-F2InstallMailboxSddl {
    param([Parameter(Mandatory)][string]$OwnerSid)
    return ('O:{0}D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;{0})' -f $OwnerSid)
}

function Test-F2InstallMailboxDirectory {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$OwnerSid)
    $full = [IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals($full,$Path,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetPathRoot($full) -match '^\\' -or [IO.Path]::GetFileName($full) -cnotmatch '^F2-G1-Install-[0-9a-f]{32}$') { throw 'MAILBOX_PATH_INVALID' }
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\');$parent=[IO.Directory]::GetParent($full)
    if($null-eq $parent-or -not [string]::Equals($parent.FullName.TrimEnd('\'),$tempRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'BOOTSTRAP_DIAGNOSTIC_PATH_INVALID'}
    if((New-Object IO.DriveInfo([IO.Path]::GetPathRoot($full))).DriveType-ne[IO.DriveType]::Fixed){throw 'TEMP_VOLUME_NOT_FIXED'}
    Test-F2InstallLauncherNoReparseChain -Path $full
    $acl = Get-Acl -LiteralPath $full -ErrorAction Stop
    $sddl = $acl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access)
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
    if ($raw.Owner.Value -cne $OwnerSid -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $null -eq $raw.DiscretionaryAcl -or @($raw.DiscretionaryAcl).Count -ne 2) { throw 'MAILBOX_OWNER_OR_DACL_INVALID' }
    $expected = @{'S-1-5-18'=[uint32]0x001F01FF;$OwnerSid=[uint32]0x001F01FF}
    $expectedFlags = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
    $seen = @{}
    foreach ($ace in $raw.DiscretionaryAcl) {
        $sid = $ace.SecurityIdentifier.Value
        $mask = [uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        if (-not $expected.ContainsKey($sid) -or $seen.ContainsKey($sid) -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $mask -ne $expected[$sid] -or [int]$ace.AceFlags -ne $expectedFlags) { throw 'MAILBOX_OWNER_OR_DACL_INVALID' }
        $seen[$sid] = $true
    }
    if ($seen.Count -ne 2) { throw 'MAILBOX_OWNER_OR_DACL_INVALID' }
    return $true
}

function New-F2InstallDiagnosticMailbox {
    param([Parameter(Mandatory)][string]$OwnerSid)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if ([IO.Path]::GetPathRoot($tempRoot) -match '^\\') { throw 'TEMP_VOLUME_NOT_LOCAL' }
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($tempRoot))
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) { throw 'TEMP_VOLUME_NOT_FIXED' }
    Test-F2InstallLauncherNoReparseChain -Path $tempRoot
    $directory = Join-Path $tempRoot ('F2-G1-Install-' + [guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $directory) { throw 'MAILBOX_NAME_COLLISION' }
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetSecurityDescriptorSddlForm((Get-F2InstallMailboxSddl -OwnerSid $OwnerSid))
    [void][IO.Directory]::CreateDirectory($directory,$security)
    Test-F2InstallMailboxDirectory -Path $directory -OwnerSid $OwnerSid | Out-Null
    if (@(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop).Count -ne 0) { throw 'MAILBOX_NOT_EMPTY' }
    return [pscustomobject]@{Directory=$directory;Nonce=[guid]::NewGuid().ToString('N');OwnerSid=$OwnerSid}
}

function New-F2InstallElevatedCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$BootstrapBytes,[Parameter(Mandatory)][string]$MailboxDirectory,[Parameter(Mandatory)][string]$Nonce)
    if ($Nonce -cnotmatch '^[0-9a-f]{32}$') { throw 'DIAGNOSTIC_NONCE_INVALID' }
    if ([IO.Path]::GetFullPath($MailboxDirectory) -cne $MailboxDirectory) { throw 'DIAGNOSTIC_PATH_NOT_CANONICAL' }
    $utf8 = New-Object System.Text.UTF8Encoding($false,$true)
    $source = $utf8.GetString($BootstrapBytes)
    $tokens = $null;$parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -ne 0) { throw 'BOOTSTRAP_PARSE_FAILED' }
    $sourceB64=[Convert]::ToBase64String($BootstrapBytes)
    $directoryB64=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($MailboxDirectory))
    $nonceB64=[Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($Nonce))
    $expectedHash=Get-F2InstallLauncherHash -Bytes $BootstrapBytes
    if($expectedHash-cne $script:F2InstallBootstrapSha256){throw 'BOOTSTRAP_HASH_MISMATCH'}
    $command=@"
`$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
`$bytes=[Convert]::FromBase64String('$sourceB64')
`$sha=[Security.Cryptography.SHA256]::Create();try{`$actual=([BitConverter]::ToString(`$sha.ComputeHash(`$bytes))).Replace('-','').ToLowerInvariant()}finally{`$sha.Dispose()}
if(`$actual-cne '$expectedHash'){[Console]::Error.WriteLine('F2_INSTALL_BOOTSTRAP: BOOTSTRAP_HASH_MISMATCH');exit 1}
`$utf8=New-Object System.Text.UTF8Encoding(`$false,`$true);`$source=`$utf8.GetString(`$bytes);`$block=[ScriptBlock]::Create(`$source);.` `$block
`$directory=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$directoryB64'));`$nonce=[Text.Encoding]::ASCII.GetString([Convert]::FromBase64String('$nonceB64'))
`$run=Invoke-F2VerifiedInstallerMain -DiagnosticDirectory `$directory -CorrelationNonce `$nonce
exit [int]`$run.ChildExitCode
"@
    if ($command.Length -gt 30000) { throw 'ELEVATED_COMMAND_TOO_LARGE' }
    return $command.Trim()
}

function Get-F2InstallDiagnosticStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$MailboxDirectory,[Parameter(Mandatory)][string]$Nonce,[Parameter(Mandatory)][string]$OwnerSid,[Parameter(Mandatory)][int]$ChildExitCode)
    try { Test-F2InstallMailboxDirectory -Path $MailboxDirectory -OwnerSid $OwnerSid | Out-Null }
    catch { return [pscustomobject]@{Status='DIAGNOSTIC_MAILBOX_INVALID';Record=$null;Sha256=$null;ErrorCode='MAILBOX_SECURITY_INVALID'} }
    $entries = @(Get-ChildItem -LiteralPath $MailboxDirectory -Force -ErrorAction Stop)
    $path = Join-Path $MailboxDirectory 'result.json'
    if ($entries.Count -eq 0) { return [pscustomobject]@{Status='DIAGNOSTIC_MISSING';Record=$null;Sha256=$null;ErrorCode='CHILD_DIAGNOSTIC_MISSING'} }
    if ($entries.Count -ne 1 -or $entries[0].Name -cne 'result.json' -or $entries[0].PSIsContainer -or ($entries[0].Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return [pscustomobject]@{Status='DIAGNOSTIC_DIRECTORY_CONTENTS_INVALID';Record=$null;Sha256=$null;ErrorCode='CHILD_DIAGNOSTIC_CONTENTS_INVALID'} }
    if ($entries[0].Length -lt 1 -or $entries[0].Length -gt $script:F2DiagnosticMaximumBytes) { return [pscustomobject]@{Status='DIAGNOSTIC_SIZE_INVALID';Record=$null;Sha256=$null;ErrorCode='CHILD_DIAGNOSTIC_SIZE_INVALID'} }
    try {
        $fileAcl=Get-Acl -LiteralPath $path -ErrorAction Stop
        $raw=[Security.AccessControl.RawSecurityDescriptor]::new($fileAcl.GetSecurityDescriptorSddlForm([Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access))
        if ($raw.Owner.Value -cne $OwnerSid -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or @($raw.DiscretionaryAcl).Count -ne 2) { throw 'DIAGNOSTIC_FILE_SECURITY_INVALID' }
        $expected=@{'S-1-5-18'=[uint32]0x001F01FF;$OwnerSid=[uint32]0x001F01FF};$seen=@{}
        foreach($ace in $raw.DiscretionaryAcl){$sid=$ace.SecurityIdentifier.Value;$mask=[uint32]([int64]$ace.AccessMask-band 0xFFFFFFFFL);if(-not $expected.ContainsKey($sid)-or $seen.ContainsKey($sid)-or $ace.AceQualifier-ne[Security.AccessControl.AceQualifier]::AccessAllowed-or $mask-ne$expected[$sid]-or [int]$ace.AceFlags-ne 0){throw 'DIAGNOSTIC_FILE_SECURITY_INVALID'};$seen[$sid]=$true}
        if($seen.Count-ne 2){throw 'DIAGNOSTIC_FILE_SECURITY_INVALID'}
        $bytes=[IO.File]::ReadAllBytes($path)
        $record=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json -ErrorAction Stop
    } catch { return [pscustomobject]@{Status='DIAGNOSTIC_MALFORMED_OR_SECURITY_INVALID';Record=$null;Sha256=$null;ErrorCode='CHILD_DIAGNOSTIC_INVALID'} }
    $expectedNames=@('Schema','Nonce','Component','Outcome','Stage','ErrorCode')
    $actualNames=@($record.PSObject.Properties|ForEach-Object Name|Sort-Object)
    if (-not [string]::Equals([string]$record.Nonce,$Nonce,[StringComparison]::Ordinal)) { return [pscustomobject]@{Status='DIAGNOSTIC_CONTENT_INVALID';Record=$null;Sha256=$null;ErrorCode='CHILD_DIAGNOSTIC_CONTENT_INVALID'} }
    if (@(Compare-Object $expectedNames ($actualNames|Sort-Object) -CaseSensitive).Count -ne 0 -or $record.Schema -cne 'f2-install-diagnostic-v1' -or $record.Component -notin @('Bootstrap','Installer') -or $record.Outcome -notin @('BOOTSTRAP_BLOCKED','INSTALL_BLOCKED','INSTALL_COMPLETE') -or $record.Stage -cnotin $script:F2DiagnosticStages -or $record.ErrorCode -cnotin $script:F2DiagnosticErrorCodes -and $record.ErrorCode -cne 'NONE') { return [pscustomobject]@{Status='DIAGNOSTIC_CONTENT_INVALID';Record=$null;Sha256=$null;ErrorCode='CHILD_DIAGNOSTIC_CONTENT_INVALID'} }
    $sha=Get-F2InstallLauncherHash -Bytes $bytes
    if($ChildExitCode-ne 0-and $record.Outcome-eq 'INSTALL_COMPLETE'){return [pscustomobject]@{Status='CHILD_STATUS_CONFLICT';Record=$record;Sha256=$sha;ErrorCode='CHILD_EXIT_CONFLICT'}}
    if($ChildExitCode-eq 0-and $record.Outcome-ne 'INSTALL_COMPLETE'){return [pscustomobject]@{Status='CHILD_STATUS_CONFLICT';Record=$record;Sha256=$sha;ErrorCode='CHILD_EXIT_CONFLICT'}}
    if($ChildExitCode-ne 0){return [pscustomobject]@{Status='CHILD_FAILURE';Record=$record;Sha256=$sha;ErrorCode=$record.ErrorCode}}
    return [pscustomobject]@{Status='CHILD_CLAIM_ONLY';Record=$record;Sha256=$sha;ErrorCode='NONE'}
}

function Get-F2InstallNextStep {
    param([Parameter(Mandatory)][string]$LaunchDisposition,[string]$DiagnosticStatus,[string]$Outcome)
    if($LaunchDisposition-eq 'UAC_CANCELLED_OR_LAUNCH_ERROR'){return 'No child exit was observed. Review the UAC decision or shell-launch failure; do not infer installation status.'}
    if($LaunchDisposition-eq 'NOT_LAUNCHED'){return 'No elevated child was launched. Correct the reported preflight issue before any separately authorized attempt.'}
    switch($DiagnosticStatus){
        'CHILD_CLAIM_ONLY' { return 'The child claims completion only. Independently attest the four protected directories, seven pinned files and external v2 release manifest.' }
        'DIAGNOSTIC_MISSING' { return 'No authenticated child record was available. Confirm UAC used the original requester account and inspect the preserved mailbox; no success may be inferred.' }
        'CHILD_STATUS_CONFLICT' { return 'Child diagnostic conflicts with its real exit code. Preserve evidence and stop for review.' }
        'DIAGNOSTIC_MAILBOX_INVALID' { return 'Mailbox owner or protected DACL did not match. Preserve evidence and stop for review.' }
        'DIAGNOSTIC_DIRECTORY_CONTENTS_INVALID' { return 'Mailbox has an extra, duplicate, linked or incomplete record. Preserve evidence and stop for review.' }
        default { return 'Review the sanitized stage and error code with the actual child exit. Do not retry automatically.' }
    }
}

function Invoke-F2InstallLaunch {
    [CmdletBinding()]
    param()
    $launchDisposition='NOT_LAUNCHED';$childPid=$null;$childExitCode=$null;$mailbox=$null;$diagnostic=$null
    try {
        if($PSVersionTable.PSVersion.Major-ne 5-or $PSVersionTable.PSVersion.Minor-ne 1-or $PSVersionTable.PSEdition-ne 'Desktop'){throw 'WINDOWS_POWERSHELL_51_REQUIRED'}
        if(-not(Test-Path -LiteralPath $script:F2InstallPowerShell51 -PathType Leaf)){throw 'WINDOWS_POWERSHELL_51_NOT_FOUND'}
        $launchIdentity=Get-F2InstallLaunchIdentity;$sid=[string]$launchIdentity.Sid
        if($launchIdentity.IsAdministrator){throw 'LAUNCHER_MUST_RUN_UNELEVATED'}
        $bootstrapBytes=Read-F2InstallLauncherBytes -Path $script:F2InstallBootstrapPath
        if((Get-F2InstallLauncherHash -Bytes $bootstrapBytes)-cne $script:F2InstallBootstrapSha256){throw 'BOOTSTRAP_HASH_MISMATCH'}
        $installerBytes=Read-F2InstallLauncherBytes -Path $script:F2InstallInstallerPath
        if((Get-F2InstallLauncherHash -Bytes $installerBytes)-cne $script:F2InstallInstallerSha256){throw 'INSTALLER_HASH_MISMATCH'}
        $mailbox=New-F2InstallDiagnosticMailbox -OwnerSid $sid
        $encoded=New-F2InstallElevatedCommand -BootstrapBytes $bootstrapBytes -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce
        $launchDisposition='UAC_LAUNCH_REQUESTED'
        if($null-ne $script:F2InstallStartProcessProvider){$process=& $script:F2InstallStartProcessProvider $script:F2InstallPowerShell51 $encoded}else{$quotedCommand='"'+$encoded.Replace('"','`"')+'"';$process=Start-Process -FilePath $script:F2InstallPowerShell51 -Verb RunAs -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command',$quotedCommand) -Wait -PassThru -ErrorAction Stop}
        $launchDisposition='CHILD_EXITED';$childPid=[int]$process.Id;$childExitCode=[int]$process.ExitCode
        try { $diagnostic=Get-F2InstallDiagnosticStatus -MailboxDirectory $mailbox.Directory -Nonce $mailbox.Nonce -OwnerSid $sid -ChildExitCode $childExitCode }
        catch { $diagnostic=[pscustomobject]@{Status='DIAGNOSTIC_READ_FAILED';Record=$null;Sha256=$null;ErrorCode='CHILD_DIAGNOSTIC_READ_FAILED'} }
        $status=if($childExitCode-eq 0-and $diagnostic.Status-eq 'CHILD_CLAIM_ONLY'){'CHILD_CLAIM_ONLY'}elseif($childExitCode-eq 0){'BLOCKED_DIAGNOSTIC_INVALID'}else{'BLOCKED_CHILD_FAILURE'}
        $next=Get-F2InstallNextStep -LaunchDisposition $launchDisposition -DiagnosticStatus $diagnostic.Status -Outcome $status
        return [pscustomobject]@{Schema='f2-install-launch-result-v1';LaunchDisposition=$launchDisposition;ChildPid=$childPid;ChildExitCode=$childExitCode;MailboxPath=$mailbox.Directory;DiagnosticStatus=$diagnostic.Status;DiagnosticStage=if($null-ne$diagnostic.Record){$diagnostic.Record.Stage}else{$null};DiagnosticErrorCode=$diagnostic.ErrorCode;DiagnosticSha256=$diagnostic.Sha256;Outcome=$status;NextStep=$next;DiagnosticIsNonAuthoritative=$true;IndependentInstallationAttestationRequired=$true}
    } catch {
        $code=[string]$_.Exception.Message
        if($code-cnotin $script:F2LauncherErrorCodes){$code='LAUNCHER_OPERATION_FAILED'}
        if($launchDisposition-eq 'UAC_LAUNCH_REQUESTED'){$launchDisposition='UAC_CANCELLED_OR_LAUNCH_ERROR'}
        $next=Get-F2InstallNextStep -LaunchDisposition $launchDisposition -DiagnosticStatus $(if($null-ne$diagnostic){$diagnostic.Status}else{'NOT_AVAILABLE'}) -Outcome 'BLOCKED_BEFORE_OR_DURING_LAUNCH'
        return [pscustomobject]@{Schema='f2-install-launch-result-v1';LaunchDisposition=$launchDisposition;ChildPid=$childPid;ChildExitCode=$childExitCode;MailboxPath=if($null-ne$mailbox){$mailbox.Directory}else{$null};DiagnosticStatus=if($null-ne$diagnostic){$diagnostic.Status}else{'NOT_AVAILABLE'};DiagnosticStage=$null;DiagnosticErrorCode=$code;DiagnosticSha256=$null;Outcome='BLOCKED_BEFORE_OR_DURING_LAUNCH';NextStep=$next;DiagnosticIsNonAuthoritative=$true;IndependentInstallationAttestationRequired=$true}
    }
}

if($MyInvocation.InvocationName-ne '.'){
    try{$unbound=@($MyInvocation.UnboundArguments);if($unbound.Count-ne 0){throw 'LAUNCHER_ARGUMENTS_NOT_ACCEPTED'};$result=Invoke-F2InstallLaunch;[Console]::Out.WriteLine(($result|ConvertTo-Json -Compress -Depth 5));if($result.Outcome-ne 'CHILD_CLAIM_ONLY'){exit 1};exit 0}
    catch{$code=[string]$_.Exception.Message;if($code-cnotin $script:F2LauncherErrorCodes){$code='LAUNCHER_OPERATION_FAILED'};[Console]::Error.WriteLine(('F2_INSTALL_LAUNCHER: '+$code));exit 1}
}

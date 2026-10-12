[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRoot = 'C:\Dev\f2-g1-protected-updater-source'
$reviewRoot = 'C:\Dev\f2-g1-protected-updater'
$updaterPath = Join-Path $sourceRoot 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'
$candidatePath = Join-Path $reviewRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
$expectedUpdaterSha256 = 'c4dfc71606888555f7b93930671045490ba8e49d20d65f858eab6c084bf620eb'
$expectedCandidateSha256 = 'ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07'
$expectedSourceCommit = '03882eedf3104fc33aa0cf503ddef9c9a6bec702'
$failures = New-Object 'System.Collections.Generic.List[string]'

function Get-F2ReviewSha256 {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Write-F2ReviewPass {
    param([Parameter(Mandatory)][string]$Name)
    [Console]::Out.WriteLine('PASS:' + $Name)
}

function Add-F2ReviewFailure {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)]$Record)
    $message = [string]$Record.Exception.Message
    if ($message -match '^UPDATE_[A-Z0-9_]+$') {
        $safe = 'Code=' + $message
    } else {
        $safe = 'Exception=' + $Record.Exception.GetType().Name
    }
    $failures.Add($Name + ';' + $safe)
    [Console]::Out.WriteLine('FAIL:' + $Name + ';' + $safe)
}

function Test-F2ReviewMailboxAcl {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$RequesterSid)
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $sections = [Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Access
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new($acl.GetSecurityDescriptorSddlForm($sections))
    if ($raw.Owner.Value -cne 'S-1-5-32-544' -or $null -eq $raw.DiscretionaryAcl -or
        ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or
        @($raw.DiscretionaryAcl).Count -ne 4) { return $false }

    $readExecute = [uint32]0x001200A9
    $expected = @{
        'S-1-5-18' = [uint32]0x001F01FF
        'S-1-5-32-544' = [uint32]0x001F01FF
        'S-1-3-4' = $readExecute
    }
    $expected[$RequesterSid] = $readExecute
    $expectedFlags = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
    $seen = @{}
    foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace -isnot [Security.AccessControl.QualifiedAce]) { return $false }
        $sid = $ace.SecurityIdentifier.Value
        $mask = [uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        if (-not $expected.ContainsKey($sid) -or $seen.ContainsKey($sid) -or
            $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or
            $mask -ne $expected[$sid] -or [int]$ace.AceFlags -ne $expectedFlags) { return $false }
        $seen[$sid] = $true
    }
    return $seen.Count -eq 4
}

function Assert-F2ReviewNoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'BASELINE_REPARSE_POINT_REJECTED' }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
}

function Read-F2ReviewBaselineFile {
    param([Parameter(Mandatory)][string]$Path)
    Assert-F2ReviewNoReparseAncestors -Path $Path
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt 1048576) { throw 'BASELINE_FILE_TYPE_OR_SIZE_INVALID' }
    return ,[IO.File]::ReadAllBytes($Path)
}

try {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'WINDOWS_POWERSHELL_51_REQUIRED' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $requesterSid = [string]$identity.User.Value
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'STANDARD_TOKEN_REQUIRED' }
    } finally { $identity.Dispose() }
    Write-F2ReviewPass 'PowerShell51StandardToken'

    $updaterBytes = [IO.File]::ReadAllBytes($updaterPath)
    if ((Get-F2ReviewSha256 -Bytes $updaterBytes) -cne $expectedUpdaterSha256) { throw 'PINNED_UPDATER_HASH_MISMATCH' }
    $tokens = $null; $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($updaterPath,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count -ne 0) { throw 'PINNED_UPDATER_PARSE_FAILED' }
    foreach ($statement in $ast.EndBlock.Statements) {
        if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) { continue }
        if ($statement -is [Management.Automation.Language.AssignmentStatementAst]) {
            $expression = $statement.Right.Expression
            if ($expression -is [Management.Automation.Language.StringConstantExpressionAst]) { continue }
            if ($expression -is [Management.Automation.Language.ConvertExpressionAst] -and $expression.Child -is [Management.Automation.Language.HashtableAst]) { continue }
            throw 'UNEXPECTED_PINNED_UPDATER_TOP_LEVEL_EXPRESSION'
        }
        if ($statement -is [Management.Automation.Language.PipelineAst] -and $statement.PipelineElements.Count -eq 1 -and
            $statement.PipelineElements[0] -is [Management.Automation.Language.CommandAst] -and
            $statement.PipelineElements[0].GetCommandName() -ceq 'Set-StrictMode') { continue }
        throw 'UNEXPECTED_PINNED_UPDATER_TOP_LEVEL_STATEMENT'
    }
    . ([scriptblock]::Create([Text.UTF8Encoding]::new($false,$true).GetString($updaterBytes)))
    Write-F2ReviewPass 'ReviewedUpdaterHashParseAndDefinitionsOnlyLoad'

    $candidateBytes = [IO.File]::ReadAllBytes($candidatePath)
    if ((Get-F2ReviewSha256 -Bytes $candidateBytes) -cne $expectedCandidateSha256) { throw 'PINNED_CANDIDATE_HASH_MISMATCH' }
    $candidate = Get-F2UpdateManifestObject -Bytes $candidateBytes -ExpectedSchema v3 -ExpectedHash $expectedCandidateSha256
    $context = [pscustomobject]@{
        SourceRoot = $sourceRoot
        ExpectedSourceCommit = $expectedSourceCommit
        CandidateManifestBytes = $candidateBytes
        CandidateManifestSha256 = $expectedCandidateSha256
        Manifest = $candidate
        PackageHome = 'C:\Program Files\F2-G1-Icacls'
        ProgramDataRoot = 'C:\ProgramData\F2-G1-Icacls'
        ActiveManifestPath = 'C:\ProgramData\F2-G1-Icacls\approved-release.json'
        Hooks = $null
        TransactionState = $null
    }

    try { $null = Test-F2UpdateCandidate -Context $context; Write-F2ReviewPass 'CandidateManifestValidation' }
    catch { Add-F2ReviewFailure 'CandidateManifestValidation' $_ }
    try {
        $sourceBytes = Get-F2UpdateSourceBytes -Context $context
        if ($sourceBytes.Count -ne 7) { throw 'UPDATE_SOURCE_FILE_SET_INVALID' }
        Write-F2ReviewPass 'GitSourceAndSevenPackagePinValidation'
    } catch { Add-F2ReviewFailure 'GitSourceAndSevenPackagePinValidation' $_ }
    try { $null = Test-F2UpdateParentChains -Context $context; Write-F2ReviewPass 'CDriveParentAclValidation' }
    catch { Add-F2ReviewFailure 'CDriveParentAclValidation' $_ }
    try {
        $oldManifest = Test-F2UpdateInstalledOldRelease -Context $context
        if ($oldManifest.ReviewedCommitSha -cne '5741ffe90a3abd02a08563e6431e8a0b9b63eeb1') { throw 'UPDATE_OLD_RELEASE_COMMIT_MISMATCH' }
        Write-F2ReviewPass 'InstalledV2ReadOnlyValidation'
    } catch { Add-F2ReviewFailure 'InstalledV2ReadOnlyValidation' $_ }

    foreach ($path in @(
        (Join-Path $context.ProgramDataRoot 'release.lock'),
        (Join-Path $context.ProgramDataRoot 'updates'),
        (Join-Path $context.ProgramDataRoot 'backups'),
        (Join-Path $context.PackageHome 'releases')
    )) {
        if ([IO.File]::Exists($path) -or [IO.Directory]::Exists($path)) { $failures.Add('TransactionObjectPresent'); break }
    }
    if ($failures -notcontains 'TransactionObjectPresent') { Write-F2ReviewPass 'NoLockTransactionRootsBackupsReleasesOrStages' }
    else { [Console]::Out.WriteLine('FAIL:NoLockTransactionRootsBackupsReleasesOrStages;Code=TRANSACTION_OBJECT_PRESENT') }

    $mailbox = 'C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df'
    Assert-F2ReviewNoReparseAncestors -Path $mailbox
    if (-not [IO.Directory]::Exists($mailbox) -or -not (Test-F2ReviewMailboxAcl -Path $mailbox -RequesterSid $requesterSid)) { throw 'BASELINE_MAILBOX_ACL_OR_IDENTITY_INVALID' }
    $integrityBytes = Read-F2ReviewBaselineFile -Path (Join-Path $mailbox 'integrity.json')
    $payloadBytes = Read-F2ReviewBaselineFile -Path (Join-Path $mailbox 'acl-baseline.json')
    if ((Get-F2ReviewSha256 -Bytes $integrityBytes) -cne '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34' -or
        (Get-F2ReviewSha256 -Bytes $payloadBytes) -cne '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014') { throw 'BASELINE_PINNED_HASH_MISMATCH' }
    $integrity = [Text.UTF8Encoding]::new($false,$true).GetString($integrityBytes) | ConvertFrom-Json -ErrorAction Stop
    $payload = [Text.UTF8Encoding]::new($false,$true).GetString($payloadBytes) | ConvertFrom-Json -ErrorAction Stop
    if ($integrity.Schema -cne 'f2-acl-integrity-v1' -or $integrity.PayloadFile -cne 'acl-baseline.json' -or
        $integrity.PayloadBytes -ne $payloadBytes.Length -or $integrity.PayloadSha256 -cne '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014' -or
        $integrity.ProjectVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or
        $integrity.EvidenceVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $integrity.SeparateFromProjectVolume -ne $true) { throw 'BASELINE_INTEGRITY_FIELDS_INVALID' }
    if ($payload.CaptureId -cne '489e7fec-0300-467c-bfbd-a46fb8cf7211' -or $payload.Complete -ne $true -or
        $payload.VmId -cne '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1' -or $payload.VmName -cne 'F2-G1-Isolated-Disposable' -or
        $payload.VmState -cne 'Off' -or @($payload.Records).Count -ne 11 -or $payload.Manifest.ExpectedCount -ne 11 -or
        $payload.Manifest.RecordCount -ne 11 -or $payload.Manifest.UniquePathCount -ne 11 -or
        $payload.Manifest.ErrorCount -ne 0 -or @($payload.Manifest.Errors).Count -ne 0) { throw 'BASELINE_PAYLOAD_IDENTITY_OR_COMPLETENESS_INVALID' }
    Write-F2ReviewPass 'BaselineMailboxPayloadIntegrityAndElevenRecordValidation'

    [Console]::Out.WriteLine('UpdaterEntryPointInvoked=NO')
    [Console]::Out.WriteLine('TransactionEntryPointInvoked=NO')
    [Console]::Out.WriteLine('UAC=NONE')
    [Console]::Out.WriteLine('ProtectedWrites=NONE')
    [Console]::Out.WriteLine('LiveIcacls=NOT_RUN')
    [Console]::Out.WriteLine('VMHyperVAndG=NOT_QUERIED')
    if ($failures.Count -ne 0) {
        [Console]::Out.WriteLine('Result=BLOCKED_WITH_EVIDENCE;FailureCount=' + $failures.Count)
        exit 1
    }
    [Console]::Out.WriteLine('Result=READ_ONLY_FUNCTION_DIAGNOSTICS_COMPLETE')
    exit 0
} catch {
    $message = [string]$_.Exception.Message
    if ($message -match '^[A-Z0-9_:-]{1,100}$') { [Console]::Out.WriteLine('Result=BLOCKED_WITH_EVIDENCE;Code=' + $message) }
    else { [Console]::Out.WriteLine('Result=BLOCKED_WITH_EVIDENCE;Exception=' + $_.Exception.GetType().Name) }
    exit 1
}

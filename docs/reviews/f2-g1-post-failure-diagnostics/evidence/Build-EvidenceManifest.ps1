[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repo = [IO.Path]::GetFullPath($RepositoryRoot)
$reviewBase = '9e9915e6eb15bcb20cc2f5a1c990791e2a822b90'
$sourceCommit = '8b70a70934445bee660c1e53e71b2e7b20a6191f'
$folder = 'docs/reviews/f2-g1-post-failure-diagnostics'
$manifestRelative = Join-Path $folder 'evidence-manifest.json'
$items = @(
    @{ Path = 'F2_G1_UPGRADE_POST_FAILURE_DIAGNOSTIC.md'; Purpose = 'Consolidated sanitized source-path and postfailure analysis' },
    @{ Path = 'evidence/postfailure-readonly-results.json'; Purpose = 'Sanitized measured results; excludes SDDL and private requester SID' },
    @{ Path = 'evidence/Test-SyntheticMissingGitPreflight.ps1'; Purpose = 'Reproducible PS5.1 TEMP-only missing-Git failure fixture' },
    @{ Path = 'evidence/Synthetic-GitPathFailure.log'; Purpose = 'Complete output of the synthetic missing-Git test' },
    @{ Path = 'evidence/Test-EncodedChildTemplateParse.ps1'; Purpose = 'Reproducible PS5.1 parser fixture for embedded elevated child script' },
    @{ Path = 'evidence/EncodedChildTemplateParse.log'; Purpose = 'Complete output of the child-template parser fixture' },
    @{ Path = 'evidence/Test-ProductionPowerShellParserSweep.ps1'; Purpose = 'Reproducible production-source parser sweep' },
    @{ Path = 'evidence/PowerShellParserSweep.log'; Purpose = 'Complete parser sweep output' },
    @{ Path = 'evidence/Test-CurrentPS51Dependencies.ps1'; Purpose = 'Reproducible no-profile PS 5.1 command and module availability probe' },
    @{ Path = 'evidence/CurrentPS51Dependencies.log'; Purpose = 'Complete current PS 5.1 dependency probe output' },
    @{ Path = 'evidence/Test-F2AclProtectedReleaseUpdater.ps1.log'; Purpose = 'Full 133-assertion PS5.1 updater regression output' },
    @{ Path = 'evidence/Test-F2AclProtectedReleaseNativeHelper.ps1.log'; Purpose = 'Full 20-assertion PS5.1 TEMP native helper output' },
    @{ Path = 'evidence/Build-EvidenceManifest.ps1'; Purpose = 'Reproducible Git-blob hash manifest builder' }
)

function Get-EntryBytes {
    param([Parameter(Mandatory)]$Archive, [Parameter(Mandatory)][string]$EntryPath)
    $entry = $Archive.GetEntry($EntryPath)
    if ($null -eq $entry) { throw ('ARCHIVE_ENTRY_MISSING:' + $EntryPath) }
    $input = $entry.Open()
    $memory = New-Object IO.MemoryStream
    try {
        $input.CopyTo($memory)
        return ,$memory.ToArray()
    }
    finally {
        $input.Dispose()
        $memory.Dispose()
    }
}

function Get-BytesSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$tempBase = [IO.Path]::GetTempPath()
$zipPath = Join-Path $tempBase ('f2-evidence-' + [guid]::NewGuid().ToString('N') + '.zip')
try {
    $tree = (& git -C $repo write-tree).Trim()
    if ($LASTEXITCODE -ne 0 -or $tree -notmatch '^[0-9a-f]{40}$') { throw 'EVIDENCE_INDEX_TREE_INVALID' }
    & git -C $repo archive --format=zip ('--output=' + $zipPath) $tree $folder
    if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($zipPath)) { throw 'EVIDENCE_ARCHIVE_CREATE_FAILED' }

    $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $records = @()
        foreach ($item in $items) {
            $entryPath = ($folder + '/' + $item.Path).Replace('\', '/')
            $bytes = Get-EntryBytes -Archive $archive -EntryPath $entryPath
            $records += ,[ordered]@{
                Path = $item.Path
                Purpose = $item.Purpose
                GitHubRawBytes = $bytes.Length
                Sha256 = Get-BytesSha256 -Bytes $bytes
            }
        }
    }
    finally { $archive.Dispose() }
    Remove-Item -LiteralPath $zipPath -Force

    $manifest = [ordered]@{
        Schema = 'f2-g1-postfailure-evidence-manifest-v1'
        ReviewBaseCommit = $reviewBase
        ProductionSourceCommit = $sourceCommit
        HashDefinition = 'SHA-256 over exact staged Git blob bytes; this matches the content served by GitHub.'
        ReferencedProductionFiles = @(
            @{ Path = 'scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1'; WindowsCheckoutSha256 = '8278bbff8e5b7cdb313235bcc271fa31a947ca384d7496053650c3097af19720' },
            @{ Path = 'scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1'; WindowsCheckoutSha256 = 'd26eb89a424e3f268099e0ac1d3ffd674dde1128321567df3a0702abb591f75e' },
            @{ Path = 'docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json'; Sha256 = '74d178917fba4f50fdca40505d8c1dc81639f3c60bbb25c0332fd737c681562c' }
        )
        EvidenceItems = $records
        ManifestNote = 'This manifest lists all accompanying diagnostic and test artifacts except itself. Its own GitHub raw-content SHA-256 is recorded in the review handoff.'
    }
    $manifestPath = Join-Path $repo $manifestRelative
    $manifestText = ($manifest | ConvertTo-Json -Depth 6) + "`n"
    [IO.File]::WriteAllText($manifestPath, $manifestText, [Text.UTF8Encoding]::new($false))
    & git -C $repo add -- $manifestRelative
    if ($LASTEXITCODE -ne 0) { throw 'EVIDENCE_MANIFEST_STAGE_FAILED' }

    $finalTree = (& git -C $repo write-tree).Trim()
    if ($LASTEXITCODE -ne 0 -or $finalTree -notmatch '^[0-9a-f]{40}$') { throw 'EVIDENCE_FINAL_TREE_INVALID' }
    & git -C $repo archive --format=zip ('--output=' + $zipPath) $finalTree $folder
    if ($LASTEXITCODE -ne 0) { throw 'EVIDENCE_FINAL_ARCHIVE_FAILED' }
    $finalArchive = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $manifestBytes = Get-EntryBytes -Archive $finalArchive -EntryPath (($folder + '/evidence-manifest.json').Replace('\', '/'))
        $actualManifestSha = Get-BytesSha256 -Bytes $manifestBytes
        $verifiedItems = 0
        foreach ($record in $records) {
            $entryPath = ($folder + '/' + $record.Path).Replace('\', '/')
            $bytes = Get-EntryBytes -Archive $finalArchive -EntryPath $entryPath
            if ($bytes.Length -ne $record.GitHubRawBytes -or (Get-BytesSha256 -Bytes $bytes) -cne $record.Sha256) {
                throw ('EVIDENCE_MANIFEST_CONTENT_MISMATCH:' + $record.Path)
            }
            $verifiedItems++
        }
    }
    finally { $finalArchive.Dispose() }

    [pscustomobject]@{
        Result = 'PASS'
        IndexTree = $finalTree
        EvidenceItems = $records.Count
        VerifiedItems = $verifiedItems
        ManifestGitBlobSha256 = $actualManifestSha
        ManifestGitBlobBytes = $manifestBytes.Length
    } | ConvertTo-Json -Compress
}
finally {
    if ([IO.File]::Exists($zipPath)) { Remove-Item -LiteralPath $zipPath -Force }
}

[CmdletBinding()]
param(
    [string]$SourceRoot = 'C:\Dev\f2-g1-updater-diagnostics-source',
    [string]$ReviewRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedCommit = '03882eedf3104fc33aa0cf503ddef9c9a6bec702'
$expectedParent = '12575f4802f471210c0516b68b5d0d37d2eb8642'
$expectedBranch = 'fix/f2-g1-update-diagnostics-source'
$expectedOrigin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$expectedCandidateSha256 = 'ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07'
$productionFiles = @(
    'scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1',
    'scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1',
    'scripts/f2-acl/F2ProtectedRelease.Diagnostics.ps1'
)

function Get-Sha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-GitText([string]$Root, [string[]]$GitArgs) {
    $lines = @(& git -C $Root @GitArgs 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('GIT_COMMAND_FAILED:' + ($GitArgs -join ' ')) }
    return (($lines | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Assert-Equal([string]$Name, [string]$Actual, [string]$Expected) {
    if ($Actual -cne $Expected) { throw ($Name + '_MISMATCH') }
    Write-Output ('PASS:' + $Name + '=' + $Actual)
}

try {
    if ([string]::IsNullOrWhiteSpace($ReviewRoot)) {
        $ReviewRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)) '..\..'))
    }
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $ReviewRoot -PathType Container)) { throw 'ROOT_MISSING' }

    Assert-Equal 'SourceHead' (Get-GitText $SourceRoot @('rev-parse', 'HEAD')) $expectedCommit
    Assert-Equal 'SourceParent' (Get-GitText $SourceRoot @('rev-parse', 'HEAD^')) $expectedParent
    Assert-Equal 'SourceBranch' (Get-GitText $SourceRoot @('branch', '--show-current')) $expectedBranch
    Assert-Equal 'SourceOrigin' (Get-GitText $SourceRoot @('remote', 'get-url', 'origin')) $expectedOrigin
    $remoteBranchRef = 'origin/' + $expectedBranch
    Assert-Equal 'RemoteBranchHead' (Get-GitText $SourceRoot @('rev-parse', $remoteBranchRef)) $expectedCommit
    Assert-Equal 'SourceWorktree' (Get-GitText $SourceRoot @('status', '--porcelain')) ''

    $candidatePath = Join-Path $ReviewRoot 'docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json'
    Assert-Equal 'CandidateRawSha256' (Get-Sha256 $candidatePath) $expectedCandidateSha256
    $candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
    Assert-Equal 'CandidateSchema' ([string]$candidate.Schema) 'f2-icacls-runtime-release-v3'
    Assert-Equal 'CandidateReviewedCommit' ([string]$candidate.ReviewedCommitSha) $expectedCommit
    Assert-Equal 'CandidatePackageRoot' ([string]$candidate.PackageRoot) ('C:\Program Files\F2-G1-Icacls\releases\' + $expectedCommit)
    Assert-Equal 'CandidateSourcePinManifestSha256' ([string]$candidate.SourcePinsManifestSha256) '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
    Assert-Equal 'BaselineMailboxId' ([string]$candidate.BaselineMailboxId) 'ecb6deeb424e40feb5354d18908986df'
    Assert-Equal 'BaselinePayloadCaptureId' ([string]$candidate.BaselinePayloadCaptureId) '489e7fec-0300-467c-bfbd-a46fb8cf7211'
    Assert-Equal 'BaselinePayloadSha256' ([string]$candidate.BaselinePayloadSha256) '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
    Assert-Equal 'BaselineIntegritySha256' ([string]$candidate.BaselineIntegritySha256) '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'

    if (@($candidate.Files).Count -ne 7) { throw 'CANDIDATE_FILE_COUNT_MISMATCH' }
    $names = @($candidate.Files | ForEach-Object { [string]$_.Name })
    if (@($names | Select-Object -Unique).Count -ne 7) { throw 'CANDIDATE_FILE_NAMES_NOT_UNIQUE' }
    foreach ($file in $candidate.Files) {
        $path = Join-Path $SourceRoot ('scripts/f2-acl/' + [string]$file.Name)
        $actual = Get-Sha256 $path
        if ($actual -cne ([string]$file.Sha256).ToLowerInvariant()) { throw ('PACKAGE_HASH_MISMATCH:' + [string]$file.Name) }
        Write-Output ('PASS:PackageFile=' + [string]$file.Name + ';SHA256=' + $actual)
    }

    foreach ($relativePath in $productionFiles) {
        $sourcePath = Join-Path $SourceRoot $relativePath
        $reviewPath = Join-Path $ReviewRoot $relativePath
        $sourceHash = Get-Sha256 $sourcePath
        $reviewHash = Get-Sha256 $reviewPath
        Assert-Equal ('ReviewCopy:' + [IO.Path]::GetFileName($relativePath)) $reviewHash $sourceHash
        Write-Output ('PASS:ProductionFile=' + $relativePath + ';SHA256=' + $sourceHash)
    }
    Write-Output 'Result=PASS_SOURCE_CHAIN'
    exit 0
}
catch {
    Write-Output ('Result=FAIL_SOURCE_CHAIN;Code=' + $_.Exception.Message)
    exit 1
}

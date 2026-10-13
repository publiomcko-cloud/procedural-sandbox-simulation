[CmdletBinding()]
param(
    [string]$SourceRoot = 'C:\Dev\f2-g1-protected-updater-source',
    [string]$ReviewRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedCommit = '396c44965c90c08292ad2835f8317e81b6b9daaf'
$expectedParent = 'f58b7fdfaf71e212213d559480e1913ae6c210f8'
$expectedOrigin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$expectedCandidateSha = 'b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
$expectedSourcePinsSha = '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
$expectedCandidatePath = 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
$productionFiles = @(
    'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1',
    'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1',
    'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1'
)
$runtimeFiles = @(
    'F2AclCapture.Protocol.psm1',
    'F2AclIcacls.Corroboration.psm1',
    'F2AclIcacls.Runtime.psm1',
    'Invoke-F2IcaclsCapture.ps1',
    'Invoke-F2IcaclsProtectedCoordinator.ps1',
    'F2_ICACLS_SOURCE_PINS.json',
    'Invoke-F2AclReadOnlyCapture.ps1'
)
$pinPropertyByFile = @{
    'F2AclCapture.Protocol.psm1' = 'ProtocolModuleSha256'
    'F2AclIcacls.Corroboration.psm1' = 'CorroborationModuleSha256'
    'F2AclIcacls.Runtime.psm1' = 'RuntimeModuleSha256'
    'Invoke-F2IcaclsCapture.ps1' = 'LauncherScriptSha256'
    'Invoke-F2IcaclsProtectedCoordinator.ps1' = 'CoordinatorScriptSha256'
    'Invoke-F2AclReadOnlyCapture.ps1' = 'CollectorScriptSha256'
}

function Assert-Chain([bool]$Condition, [string]$Name, [string]$Value = 'PASS') {
    if (-not $Condition) { throw ('SOURCE_CHAIN_' + $Name + '_FAILED') }
    Write-Output ('PASS:' + $Name + '=' + $Value)
}

function Get-FileSha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-GitValue([string]$Root, [string[]]$GitArgs) {
    $lines = @(& $script:git.Source -C $Root @GitArgs 2>$null)
    if ($LASTEXITCODE -ne 0) { throw ('SOURCE_CHAIN_GIT_' + ($GitArgs[0] -replace '[^A-Za-z]','').ToUpperInvariant() + '_FAILED') }
    return (($lines | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

try {
    $script:git = Get-Command git.exe -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($ReviewRoot)) { $ReviewRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..')) }
    $sourceRootFull = [IO.Path]::GetFullPath($SourceRoot)
    $reviewRootFull = [IO.Path]::GetFullPath($ReviewRoot)
    Assert-Chain ([IO.Directory]::Exists($sourceRootFull)) 'SourceRootExists' $sourceRootFull
    Assert-Chain ([IO.Directory]::Exists($reviewRootFull)) 'ReviewRootExists' $reviewRootFull
    $sourceHead = Get-GitValue $sourceRootFull @('rev-parse','HEAD')
    Assert-Chain ($sourceHead -ceq $expectedCommit) 'SourceHead' $sourceHead
    $sourceParent = Get-GitValue $sourceRootFull @('rev-parse','HEAD^')
    Assert-Chain ($sourceParent -ceq $expectedParent) 'SourceParent' $sourceParent
    $sourceOrigin = Get-GitValue $sourceRootFull @('remote','get-url','origin')
    Assert-Chain ($sourceOrigin -ceq $expectedOrigin) 'SourceOrigin' $sourceOrigin
    $sourceStatus = Get-GitValue $sourceRootFull @('status','--porcelain','--untracked-files=all')
    Assert-Chain ([string]::IsNullOrEmpty($sourceStatus)) 'SourceWorktreeClean'

    $candidatePath = Join-Path $reviewRootFull $expectedCandidatePath
    Assert-Chain ([IO.File]::Exists($candidatePath)) 'CandidateExists' $candidatePath
    $candidateItem = Get-Item -LiteralPath $candidatePath -Force
    Assert-Chain (($candidateItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'CandidateNotReparse'
    $candidateSha = Get-FileSha256 $candidatePath
    Assert-Chain ($candidateSha -ceq $expectedCandidateSha) 'CandidateSha256' $candidateSha
    $candidate = Get-Content -LiteralPath $candidatePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Assert-Chain ($candidate.Schema -ceq 'f2-icacls-runtime-release-v3') 'CandidateSchema' ([string]$candidate.Schema)
    Assert-Chain ($candidate.ReviewedCommitSha -ceq $expectedCommit) 'CandidateReviewedCommit' ([string]$candidate.ReviewedCommitSha)
    Assert-Chain ($candidate.PackageRoot -ceq ('C:\Program Files\F2-G1-Icacls\releases\' + $expectedCommit)) 'CandidatePackageRoot' ([string]$candidate.PackageRoot)
    Assert-Chain ($candidate.SourcePinsManifestSha256 -ceq $expectedSourcePinsSha) 'CandidatePinManifestSha256' ([string]$candidate.SourcePinsManifestSha256)
    Assert-Chain ($candidate.BaselineMailboxId -ceq 'ecb6deeb424e40feb5354d18908986df') 'BaselineMailboxId' ([string]$candidate.BaselineMailboxId)
    Assert-Chain ($candidate.BaselinePayloadCaptureId -ceq '489e7fec-0300-467c-bfbd-a46fb8cf7211') 'BaselinePayloadCaptureId' ([string]$candidate.BaselinePayloadCaptureId)
    Assert-Chain ($candidate.BaselinePayloadSha256 -ceq '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014') 'BaselinePayloadSha256' ([string]$candidate.BaselinePayloadSha256)
    Assert-Chain ($candidate.BaselineIntegritySha256 -ceq '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34') 'BaselineIntegritySha256' ([string]$candidate.BaselineIntegritySha256)

    $candidateNames = @($candidate.Files | ForEach-Object { [string]$_.Name })
    Assert-Chain ($candidateNames.Count -eq 7 -and @($candidateNames | Select-Object -Unique).Count -eq 7 -and @(Compare-Object $runtimeFiles $candidateNames -CaseSensitive).Count -eq 0) 'SevenPackageNames'
    $pinsPath = Join-Path (Join-Path $sourceRootFull 'scripts\f2-acl') 'F2_ICACLS_SOURCE_PINS.json'
    $sourcePins = Get-Content -LiteralPath $pinsPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    foreach ($file in $candidate.Files) {
        $name = [string]$file.Name
        $path = Join-Path (Join-Path $sourceRootFull 'scripts\f2-acl') $name
        $actual = Get-FileSha256 $path
        Assert-Chain ($actual -ceq ([string]$file.Sha256).ToLowerInvariant()) ('PackageFile:' + $name) $actual
        if ($name -ceq 'F2_ICACLS_SOURCE_PINS.json') {
            Assert-Chain ($actual -ceq $expectedSourcePinsSha) 'PinManifestFileHash' $actual
        } else {
            $property = $pinPropertyByFile[$name]
            Assert-Chain ($actual -ceq ([string]$sourcePins.$property).ToLowerInvariant()) ('InternalSourcePin:' + $name) $actual
        }
    }

    foreach ($relative in $productionFiles) {
        $sourceFile = Join-Path $sourceRootFull $relative
        $reviewFile = Join-Path $reviewRootFull $relative
        $sourceHash = Get-FileSha256 $sourceFile
        $reviewHash = Get-FileSha256 $reviewFile
        Assert-Chain ($sourceHash -ceq $reviewHash) ('ReviewCopy:' + [IO.Path]::GetFileName($relative)) $sourceHash
    }
    Write-Output 'RESULT=PASS_PRELOCK_SOURCE_CHAIN'
    exit 0
}
catch {
    $code = [string]$_.Exception.Message
    if ($code -notmatch '^SOURCE_CHAIN_[A-Z0-9_]+_FAILED$') { $code = 'SOURCE_CHAIN_VALIDATION_FAILED' }
    Write-Output ('RESULT=FAIL_PRELOCK_SOURCE_CHAIN;Code=' + $code)
    exit 1
}

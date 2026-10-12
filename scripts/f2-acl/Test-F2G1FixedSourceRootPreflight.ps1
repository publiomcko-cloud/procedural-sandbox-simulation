[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedSourceRoot = 'C:\Dev\f2-g1-protected-updater-source'
$expectedReviewRoot = 'C:\Dev\f2-g1-protected-updater'
$expectedSourceCommit = '03882eedf3104fc33aa0cf503ddef9c9a6bec702'
$expectedSourceParent = '12575f4802f471210c0516b68b5d0d37d2eb8642'
$expectedOrigin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$expectedSourceBranch = 'fix/f2-g1-update-diagnostics-source'
$expectedReviewCommit = '923c7d39d7fbfe106dea404c386efd4b5844654e'
$expectedReviewBranch = 'fix/f2-g1-update-diagnostics'
$expectedLauncherSha256 = '054e69a4b908c1fe1927e5997bf1c7aca003e8ae21fbaa278323fdf6b5179e68'
$expectedUpdaterSha256 = 'c4dfc71606888555f7b93930671045490ba8e49d20d65f858eab6c084bf620eb'
$expectedProtocolSha256 = 'f66783ac53ce84c093193fc6e20547e707da7013f4f1406a87b088ab6898654c'
$expectedCandidateSha256 = 'ac42f719583ba58b1c122a9318368d34699cf60103787034525be4fbe937ad07'
$expectedPinManifestSha256 = '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
$candidateRelativePath = 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
$reviewDocumentRelativePath = 'docs\reviews\f2-g1-elevated-child-diagnostics\F2_G1_ELEVATED_CHILD_DIAGNOSTICS_REVIEW.md'

$expectedPackage = @(
    [pscustomobject]@{ Name = 'F2AclCapture.Protocol.psm1'; Sha256 = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728' }
    [pscustomobject]@{ Name = 'F2AclIcacls.Corroboration.psm1'; Sha256 = 'a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b' }
    [pscustomobject]@{ Name = 'F2AclIcacls.Runtime.psm1'; Sha256 = 'd1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4' }
    [pscustomobject]@{ Name = 'Invoke-F2IcaclsCapture.ps1'; Sha256 = '0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818' }
    [pscustomobject]@{ Name = 'Invoke-F2IcaclsProtectedCoordinator.ps1'; Sha256 = '9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515' }
    [pscustomobject]@{ Name = 'F2_ICACLS_SOURCE_PINS.json'; Sha256 = '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce' }
    [pscustomobject]@{ Name = 'Invoke-F2AclReadOnlyCapture.ps1'; Sha256 = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b' }
)

function Get-F2FileSha256([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-F2GitText([string]$Root, [string[]]$GitArgs) {
    $lines = @(& git -C $Root @GitArgs 2>&1)
    $exit = $LASTEXITCODE
    if ($exit -ne 0) { throw ('GIT_FAILED:' + ($GitArgs -join ' ')) }
    return [string]::Join("`n", [string[]]$lines).Trim()
}

function Assert-F2Equal([string]$Name, [string]$Actual, [string]$Expected) {
    if ($Actual -cne $Expected) { throw ($Name + '_MISMATCH') }
    Write-Output ('PASS:' + $Name + '=' + $Actual)
}

function Assert-F2NoReparseChain([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'REPARSE_PATH_REJECTED'
            }
        }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { break }
        $current = $parent.FullName
    }
}

try {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
        throw 'WINDOWS_POWERSHELL_51_REQUIRED'
    }
    Write-Output ('PASS:PowerShellVersion=' + $PSVersionTable.PSVersion.ToString())

    foreach ($root in @($expectedSourceRoot, $expectedReviewRoot)) {
        if (-not [IO.Directory]::Exists($root)) { throw 'REVIEWED_ROOT_MISSING' }
        if ([IO.Path]::GetFullPath($root) -cne $root) { throw 'ROOT_PATH_NOT_CANONICAL' }
        Assert-F2NoReparseChain $root
        Assert-F2Equal ('Origin:' + $root) (Get-F2GitText $root @('remote', 'get-url', 'origin')) $expectedOrigin
        $status = @(Get-F2GitText $root @('status', '--porcelain', '--untracked-files=all'))
        if ($status.Count -ne 1 -or -not [string]::IsNullOrEmpty($status[0])) {
            throw ('WORKTREE_NOT_CLEAN:' + $root)
        }
        Write-Output ('PASS:CleanWorktree=' + $root)
    }

    Assert-F2Equal 'SourceHead' (Get-F2GitText $expectedSourceRoot @('rev-parse', 'HEAD')) $expectedSourceCommit
    Assert-F2Equal 'SourceParent' (Get-F2GitText $expectedSourceRoot @('rev-parse', 'HEAD^')) $expectedSourceParent
    Assert-F2Equal 'SourceRemoteBranch' (Get-F2GitText $expectedSourceRoot @('rev-parse', ('origin/' + $expectedSourceBranch))) $expectedSourceCommit
    Assert-F2Equal 'ReviewHead' (Get-F2GitText $expectedReviewRoot @('rev-parse', 'HEAD')) $expectedReviewCommit
    Assert-F2Equal 'ReviewRemoteBranch' (Get-F2GitText $expectedReviewRoot @('rev-parse', ('origin/' + $expectedReviewBranch))) $expectedReviewCommit

    $launcherPath = Join-Path $expectedSourceRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'
    $updaterPath = Join-Path $expectedSourceRoot 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'
    $protocolPath = Join-Path $expectedSourceRoot 'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1'
    Assert-F2NoReparseChain $launcherPath
    Assert-F2NoReparseChain $updaterPath
    Assert-F2NoReparseChain $protocolPath
    Assert-F2Equal 'LauncherWindowsSha256' (Get-F2FileSha256 $launcherPath) $expectedLauncherSha256
    Assert-F2Equal 'UpdaterWindowsSha256' (Get-F2FileSha256 $updaterPath) $expectedUpdaterSha256
    Assert-F2Equal 'DiagnosticProtocolWindowsSha256' (Get-F2FileSha256 $protocolPath) $expectedProtocolSha256

    $candidatePath = Join-Path $expectedReviewRoot $candidateRelativePath
    Assert-F2NoReparseChain $candidatePath
    Assert-F2Equal 'CandidateSha256' (Get-F2FileSha256 $candidatePath) $expectedCandidateSha256
    $candidate = Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json
    Assert-F2Equal 'CandidateSchema' ([string]$candidate.Schema) 'f2-icacls-runtime-release-v3'
    Assert-F2Equal 'CandidateReviewedCommit' ([string]$candidate.ReviewedCommitSha) $expectedSourceCommit
    Assert-F2Equal 'CandidatePackageRoot' ([string]$candidate.PackageRoot) ('C:\Program Files\F2-G1-Icacls\releases\' + $expectedSourceCommit)
    Assert-F2Equal 'CandidateSourcePinManifestSha256' ([string]$candidate.SourcePinsManifestSha256) $expectedPinManifestSha256
    if (@($candidate.Files).Count -ne 7) { throw 'CANDIDATE_PACKAGE_COUNT_MISMATCH' }
    if (@($expectedPackage).Count -ne 7) { throw 'TEST_PACKAGE_COUNT_INVALID' }
    $candidateNames = @($candidate.Files | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
    $expectedNames = @($expectedPackage | ForEach-Object { [string]$_.Name } | Sort-Object -Unique)
    if (@($candidateNames).Count -ne 7 -or [string]::Join('|', $candidateNames) -cne [string]::Join('|', $expectedNames)) {
        throw 'CANDIDATE_PACKAGE_NAMES_MISMATCH'
    }
    foreach ($expectedFile in $expectedPackage) {
        $candidateFile = @($candidate.Files | Where-Object { [string]$_.Name -ceq $expectedFile.Name })
        if ($candidateFile.Count -ne 1) { throw ('CANDIDATE_PACKAGE_FILE_AMBIGUOUS:' + $expectedFile.Name) }
        Assert-F2Equal ('CandidateMemberPin:' + $expectedFile.Name) ([string]$candidateFile[0].Sha256).ToLowerInvariant() $expectedFile.Sha256
        $packagePath = Join-Path $expectedSourceRoot ('scripts\f2-acl\' + $expectedFile.Name)
        Assert-F2NoReparseChain $packagePath
        Assert-F2Equal ('PackageWindowsSha256:' + $expectedFile.Name) (Get-F2FileSha256 $packagePath) $expectedFile.Sha256
    }
    Assert-F2Equal 'SourcePinManifestWindowsSha256' (Get-F2FileSha256 (Join-Path $expectedSourceRoot 'scripts\f2-acl\F2_ICACLS_SOURCE_PINS.json')) $expectedPinManifestSha256

    $launcherText = [IO.File]::ReadAllText($launcherPath)
    $expectedReviewAssignment = '$reviewRoot = ''C:\Dev\f2-g1-protected-updater'''
    if (-not $launcherText.Contains($expectedReviewAssignment)) { throw 'LAUNCHER_REVIEW_ROOT_MISMATCH' }
    $reviewDocumentPath = Join-Path $expectedReviewRoot $reviewDocumentRelativePath
    Assert-F2NoReparseChain $reviewDocumentPath
    $reviewDocument = [IO.File]::ReadAllText($reviewDocumentPath)
    $commandMatch = [regex]::Match($reviewDocument, '(?m)^"%SystemRoot%\\System32\\WindowsPowerShell\\v1\.0\\powershell\.exe".*$')
    if (-not $commandMatch.Success) { throw 'REVIEWED_CMD_COMMAND_MISSING' }
    $commandLine = $commandMatch.Value
    foreach ($requiredText in @($expectedSourceRoot, $expectedSourceCommit, $expectedLauncherSha256, $expectedUpdaterSha256, $expectedCandidateSha256)) {
        if (-not $commandLine.Contains($requiredText)) { throw 'REVIEWED_CMD_PIN_MISMATCH' }
    }
    if (-not $commandLine.Contains("$expectedSourceRoot\scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1")) {
        throw 'REVIEWED_CMD_LAUNCHER_PATH_MISMATCH'
    }
    Write-Output 'PASS:ReviewedCmdPinsAndSourceRoot'
    Write-Output ('PASS:LauncherCandidateRoot=' + $expectedReviewRoot)
    Write-Output 'CommandExecution=NOT_RUN_BY_DESIGN'
    Write-Output 'ElevatedUpdaterExecution=NOT_RUN'
    Write-Output 'Result=PASS_FIXED_PATH_SOURCE_PREFLIGHT'
    exit 0
}
catch {
    Write-Output ('Result=FAIL_FIXED_PATH_SOURCE_PREFLIGHT;Code=' + $_.Exception.Message)
    exit 1
}

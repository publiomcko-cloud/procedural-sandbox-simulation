[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$updaterPath = Join-Path $repoRoot 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'
$candidatePath = Join-Path $repoRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
. $updaterPath

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixtureRoot = Join-Path $tempRoot ('F2-GitPath-' + [guid]::NewGuid().ToString('N'))
$sourceRoot = Join-Path $fixtureRoot 'source'
$programFilesRoot = Join-Path $fixtureRoot 'ProgramFiles'
$programDataRoot = Join-Path $fixtureRoot 'ProgramData'
$oldPath = $env:PATH

try {
    if ([IO.Directory]::Exists($fixtureRoot) -or [IO.File]::Exists($fixtureRoot)) { throw 'SYNTHETIC_FIXTURE_COLLISION' }
    [void][IO.Directory]::CreateDirectory($sourceRoot)
    [void][IO.Directory]::CreateDirectory($programFilesRoot)
    [void][IO.Directory]::CreateDirectory($programDataRoot)

    $manifest = Get-Content -LiteralPath $candidatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $packageHome = Join-Path $programFilesRoot 'F2-G1-Icacls'
    $manifest.PackageRoot = Join-Path (Join-Path $packageHome 'releases') ([string]$manifest.ReviewedCommitSha)
    $manifestBytes = [Text.UTF8Encoding]::new($false).GetBytes(($manifest | ConvertTo-Json -Depth 12 -Compress))
    $manifestSha256 = Get-F2UpdateSha256 -Bytes $manifestBytes

    $context = [pscustomobject]@{
        SourceRoot = $sourceRoot
        ExpectedSourceCommit = [string]$manifest.ReviewedCommitSha
        CandidateManifestBytes = $manifestBytes
        CandidateManifestSha256 = $manifestSha256
        Manifest = $manifest
        UpdaterSha256 = ('d' * 64)
        ExpectedLauncherSha256 = ('e' * 64)
        ExpectedRequesterSid = 'S-1-5-21-111-222-333-1001' # Synthetic fixture identity only.
        RequesterLauncherProcessId = 1234
        RequesterLauncherCreationUtcTicks = 638000000000000000L
        PackageHome = $packageHome
        ProgramDataRoot = Join-Path $programDataRoot 'F2-G1-Icacls'
        ActiveManifestPath = Join-Path (Join-Path $programDataRoot 'F2-G1-Icacls') 'approved-release.json'
        Hooks = $null
    }

    # Model an elevated process environment that lacks the Git for Windows PATH entry.
    # The change is confined to this synthetic child process and restored in finally.
    $env:PATH = $env:SystemRoot + '\System32;' + $env:SystemRoot
    $gitResolved = $null -ne (Get-Command git.exe -ErrorAction SilentlyContinue)
    $cimCommand = Get-Command Get-CimInstance -ErrorAction SilentlyContinue
    $cimModuleAvailable = @(Get-Module -ListAvailable CimCmdlets).Count -gt 0
    $result = Invoke-F2UpdateTransaction -Context $context

    $remaining = [pscustomobject]@{
        ReleaseLock = [IO.File]::Exists((Join-Path $context.ProgramDataRoot 'release.lock'))
        PackageHome = [IO.Directory]::Exists($context.PackageHome)
        ReleaseRoot = [IO.Directory]::Exists((Join-Path $context.PackageHome 'releases'))
        ProgramDataRoot = [IO.Directory]::Exists($context.ProgramDataRoot)
    }
    $pass = (-not $gitResolved -and $null -ne $cimCommand -and $cimModuleAvailable -and -not $result.Success -and
        $result.Outcome -ceq 'UPDATE_BLOCKED' -and
        $result.Stage -ceq 'CandidateAndSourceValidation' -and
        $result.ErrorCode -ceq 'UPDATE_UNCLASSIFIED_FAILURE' -and
        $result.FailureType -ceq 'System.Management.Automation.CommandNotFoundException' -and
        -not $remaining.ReleaseLock -and -not $remaining.PackageHome -and
        -not $remaining.ReleaseRoot -and -not $remaining.ProgramDataRoot)

    [pscustomobject]@{
        Test = 'Synthetic missing-Git preflight using production transaction function'
        PowerShell = $PSVersionTable.PSVersion.ToString()
        GitResolved = $gitResolved
        CimCmdletResolved = ($null -ne $cimCommand)
        CimModuleAvailable = $cimModuleAvailable
        Outcome = [string]$result.Outcome
        Stage = [string]$result.Stage
        ErrorCode = [string]$result.ErrorCode
        FailureType = [string]$result.FailureType
        TransactionObjectsAfterFailure = $remaining
        ProtectedPathsAccessed = $false
        Pass = $pass
    } | ConvertTo-Json -Depth 4 -Compress

    if (-not $pass) { exit 1 }
}
finally {
    $env:PATH = $oldPath
    if ([IO.Directory]::Exists($fixtureRoot)) {
        $canonicalFixture = [IO.Path]::GetFullPath($fixtureRoot)
        if (-not $canonicalFixture.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'SYNTHETIC_FIXTURE_CLEANUP_SCOPE_REJECTED'
        }
        $attributes = [IO.File]::GetAttributes($canonicalFixture)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'SYNTHETIC_FIXTURE_CLEANUP_REPARSE_REJECTED' }
        Remove-Item -LiteralPath $canonicalFixture -Recurse -Force -ErrorAction Stop
    }
}

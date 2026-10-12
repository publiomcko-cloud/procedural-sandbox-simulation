param(
    [string]$CaptureId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failureExitCode = 1
$failureStage = 'ProtectedCoordinatorFailure'
try {
    $releasePath = Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'F2-G1-Icacls') 'approved-release.json'
    $currentPath = [IO.Path]::GetFullPath($releasePath)
    while (-not [string]::IsNullOrEmpty($currentPath)) {
        if ([IO.File]::Exists($currentPath) -or [IO.Directory]::Exists($currentPath)) {
            $pathItem = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
            if (($pathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ReleaseManifestPathReparsePoint.' }
        }
        $parent = [IO.Directory]::GetParent($currentPath)
        if ($null -eq $parent) { break }
        $currentPath = $parent.FullName
    }
    $releaseFile = Get-Item -LiteralPath $releasePath -Force -ErrorAction Stop
    if ($releaseFile.PSIsContainer -or ($releaseFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $releaseFile.Length -lt 1 -or $releaseFile.Length -gt 65536) { throw 'ReleaseManifestTypeOrSizeInvalid.' }
    $release = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($releaseFile.FullName)) | ConvertFrom-Json -ErrorAction Stop
    if ($release.Schema -cne 'f2-icacls-runtime-release-v3' -or $release.ReviewedCommitSha -notmatch '^[0-9a-f]{40}$') { throw 'ReleaseManifestSchemaOrCommitInvalid.' }
    $expectedRoot = Join-Path (Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'F2-G1-Icacls') 'releases') $release.ReviewedCommitSha
    if (-not [string]::Equals([IO.Path]::GetFullPath([string]$release.PackageRoot),[IO.Path]::GetFullPath($expectedRoot),[StringComparison]::OrdinalIgnoreCase)) { throw 'ReleaseManifestPackageRootInvalid.' }
    $expectedPath = Join-Path (Join-Path $release.PackageRoot 'scripts\f2-acl') 'Invoke-F2IcaclsProtectedCoordinator.ps1'
    if (-not [string]::Equals([IO.Path]::GetFullPath($PSCommandPath),[IO.Path]::GetFullPath($expectedPath),[StringComparison]::OrdinalIgnoreCase)) {
        $failureExitCode = 2
        $failureStage = 'ProtectedCoordinatorPathRejected'
        throw 'ProtectedCoordinatorPathRejected.'
    }
    $unboundArguments = @($MyInvocation.UnboundArguments)
    if ($unboundArguments.Count -ne 0) {
        $failureExitCode = 2
        $failureStage = 'ProtectedCoordinatorArgumentsRejected'
        throw 'ProtectedCoordinatorArgumentsRejected.'
    }
    if ([string]$CaptureId -notmatch '^[0-9a-f]{32}$') {
        $failureExitCode = 2
        $failureStage = 'ProtectedCoordinatorCaptureIdRejected'
        throw 'ProtectedCoordinatorCaptureIdRejected.'
    }
    Import-Module (Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1') -Force -ErrorAction Stop
    $result = Invoke-F2IcaclsProtectedCoordinator -CaptureId $CaptureId
    if (-not $result.Success) { exit 1 }
    exit 0
}
catch {
    [Console]::Error.WriteLine(('F2_ICACLS_STAGE:' + $failureStage))
    exit $failureExitCode
}

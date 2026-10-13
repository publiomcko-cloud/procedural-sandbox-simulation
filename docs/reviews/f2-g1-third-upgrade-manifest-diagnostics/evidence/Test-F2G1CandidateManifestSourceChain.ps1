[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$ReviewRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$expectedSourceCommit='af9aa616e112e4db4abd7cc607d396fdadb7b76c'
$expectedSourceParent='7f99bc10f3e2258d2340cea4e7ba1352022cbb6d'
$expectedOrigin='https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$expectedCandidateSha256='f9034e16287006522ece2efd03a0b427a0beec7e3edadbe06d32d49e9cfd2f29'
$expectedUpdaterSha256='88bbc62d9a083c278f2f9ab56fd4507a220234ee266232cf6f1a69f2f9740b02'
$expectedLauncherSha256='9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
$expectedDiagnosticProtocolSha256='66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'
$expectedPinManifestSha256='7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
$expectedFiles=[ordered]@{
    'F2AclCapture.Protocol.psm1'='42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1'='a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1'='d1f4697e6fcb04d8707442e7c0579dc1bd0934c0565d48c5527080af462663e4'
    'Invoke-F2IcaclsCapture.ps1'='0b9214c3d6f6e96081b9d86aa8d62087c82527443f2c4b3e7ee09a1ca3dae818'
    'Invoke-F2IcaclsProtectedCoordinator.ps1'='9b8816c941eebaa87aafd597e6bc326d380c7fbb34321ef97ab0c04a4c1ac515'
    'F2_ICACLS_SOURCE_PINS.json'='7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
    'Invoke-F2AclReadOnlyCapture.ps1'='bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}

function Assert-Equal([string]$Name,[string]$Actual,[string]$Expected){
    if($Actual -cne $Expected){throw ($Name+'_MISMATCH')}
    Write-Output ('PASS='+$Name)
}

function Get-GitValue([string]$Root,[string[]]$Arguments){
    $output=@(& git.exe -C $Root @Arguments 2>$null)
    if($LASTEXITCODE -ne 0){throw 'GIT_VALIDATION_FAILED'}
    return ([string]::Join("
",[string[]]$output)).Trim()
}

function Get-FileSha256([string]$Path){
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0)){throw 'SOURCE_FILE_TYPE_OR_REPARSE_INVALID'}
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-NoReparseChain([string]$Path){
    $current=[IO.Path]::GetFullPath($Path)
    while(-not [string]::IsNullOrEmpty($current)){
        if([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)){
            $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'SOURCE_PATH_REPARSE_REJECTED'}
        }
        $parent=[IO.Directory]::GetParent($current)
        if($null -eq $parent){break}
        $current=$parent.FullName
    }
}

try{
    $sourceRootFull=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\')
    $reviewRootFull=[IO.Path]::GetFullPath($ReviewRoot).TrimEnd('\')
    Assert-NoReparseChain $sourceRootFull
    Assert-NoReparseChain $reviewRootFull
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){throw 'WINDOWS_POWERSHELL_51_REQUIRED'}
    Write-Output ('PASS=WindowsPowerShell51;Version='+$PSVersionTable.PSVersion.ToString())
    Assert-Equal 'ProductionHead' (Get-GitValue $sourceRootFull @('rev-parse','HEAD')) $expectedSourceCommit
    Assert-Equal 'ProductionParent' (Get-GitValue $sourceRootFull @('rev-parse','HEAD^')) $expectedSourceParent
    Assert-Equal 'ProductionOrigin' (Get-GitValue $sourceRootFull @('remote','get-url','origin')) $expectedOrigin
    Assert-Equal 'ProductionWorktreeClean' (Get-GitValue $sourceRootFull @('status','--porcelain')) ''
    Assert-Equal 'ReviewOrigin' (Get-GitValue $reviewRootFull @('remote','get-url','origin')) $expectedOrigin
    & git.exe -C $reviewRootFull merge-base --is-ancestor $expectedSourceCommit HEAD 2>$null
    if($LASTEXITCODE -ne 0){throw 'SOURCE_COMMIT_NOT_IN_REVIEW_LINEAGE'}
    Write-Output 'PASS=ProductionIsAncestorOfReview'

    $launcherPath=Join-Path $sourceRootFull 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'
    $updaterPath=Join-Path $sourceRootFull 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'
    $protocolPath=Join-Path $sourceRootFull 'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1'
    $pinManifestPath=Join-Path $sourceRootFull 'scripts\f2-acl\F2_ICACLS_SOURCE_PINS.json'
    Assert-Equal 'LauncherSha256' (Get-FileSha256 $launcherPath) $expectedLauncherSha256
    Assert-Equal 'UpdaterSha256' (Get-FileSha256 $updaterPath) $expectedUpdaterSha256
    Assert-Equal 'DiagnosticProtocolSha256' (Get-FileSha256 $protocolPath) $expectedDiagnosticProtocolSha256
    Assert-Equal 'SourcePinManifestSha256' (Get-FileSha256 $pinManifestPath) $expectedPinManifestSha256

    foreach($name in $expectedFiles.Keys){
        $path=Join-Path $sourceRootFull ('scripts\f2-acl\'+$name)
        Assert-Equal ('PackageFile_'+$name) (Get-FileSha256 $path) $expectedFiles[$name]
    }
    $candidatePath=Join-Path $reviewRootFull 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
    Assert-Equal 'CandidateManifestSha256' (Get-FileSha256 $candidatePath) $expectedCandidateSha256
    $candidate=Get-Content -LiteralPath $candidatePath -Raw | ConvertFrom-Json -ErrorAction Stop
    Assert-Equal 'CandidateSchema' ([string]$candidate.Schema) 'f2-icacls-runtime-release-v3'
    Assert-Equal 'CandidateReviewedCommit' ([string]$candidate.ReviewedCommitSha) $expectedSourceCommit
    Assert-Equal 'CandidatePackageRoot' ([string]$candidate.PackageRoot) ('C:\Program Files\F2-G1-Icacls\releases\'+$expectedSourceCommit)
    Assert-Equal 'CandidateSourcePinManifestSha256' ([string]$candidate.SourcePinsManifestSha256) $expectedPinManifestSha256
    if(@($candidate.Files).Count -ne 7){throw 'CANDIDATE_FILE_COUNT_INVALID'}
    foreach($file in $candidate.Files){
        if($expectedFiles[[string]$file.Name] -cne [string]$file.Sha256){throw 'CANDIDATE_PACKAGE_PIN_MISMATCH'}
    }
    Write-Output 'RESULT=PASS_SOURCE_CHAIN'
    exit 0
}catch{
    Write-Output ('RESULT=FAIL_SOURCE_CHAIN;Code='+$_.Exception.Message)
    exit 1
}

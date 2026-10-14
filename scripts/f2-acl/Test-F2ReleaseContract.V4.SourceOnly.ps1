[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseContract.V4.SourceOnly.psm1') -Force
$script:count=0
$script:failures=New-Object 'System.Collections.Generic.List[string]'
function Assert-V4([bool]$ok,[string]$label){$script:count++;if(-not $ok){$script:failures.Add($label);Write-Output ('FAIL: '+$label)}else{Write-Output ('PASS: '+$label)}}
$sha='1234567890abcdef1234567890abcdef12345678'
$home='C:\F2SyntheticV4\PackageHome'
$sourcePins='a'*64
$known=Get-F2V4PackageNames
Assert-V4 ($known.Count -eq 10 -and @($known | Sort-Object -Unique).Count -eq 10) 'exact ten members and no duplicates'
$exports=@((Get-Module F2ReleaseContract.V4.SourceOnly).ExportedCommands.Keys | Sort-Object)
Assert-V4 ($exports.Count -eq 3 -and $exports -contains 'Test-F2V4ReleaseContract' -and $exports -contains 'Get-F2V4Sha256' -and $exports -contains 'Get-F2V4PackageNames') 'only read-only contract verification entrypoints are exported'
$manifest=[ordered]@{
  Schema='f2-icacls-runtime-release-v4'
  Status='SOURCE_ONLY_NOT_RELEASE_APPROVED'
  ReviewedCommitSha=$sha
  PackageRoot=(Join-Path (Join-Path $home 'releases') $sha)
  BaselineMailboxId='ecb6deeb424e40feb5354d18908986df'
  BaselinePayloadCaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211'
  BaselinePayloadSha256='1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
  BaselineIntegritySha256='02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
  SourcePinsManifestSha256=$sourcePins
  LegacySourcePinsManifestSha256='7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
  CollectorPinsManifestSha256=('b'*64)
  LegacyCollectorPinsManifestSha256=('c'*64)
  Files=@(foreach($name in $known){
    $value=if($name -ceq 'F2_ICACLS_SOURCE_PINS_V2.json'){$sourcePins}
    elseif($name -ceq 'F2_ICACLS_SOURCE_PINS.json'){'7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'}
    elseif($name -ceq 'F2_ACL_SOURCE_PINS_V2.json'){'b'*64}
    elseif($name -ceq 'F2_ACL_SOURCE_PINS.json'){'c'*64}
    else{'d'*64}
    [pscustomobject]@{Name=$name;Sha256=$value}
  })
}
function Invoke-Contract($candidate,[string]$pins=$sourcePins,[string]$expectedCommit=$sha,[string]$actualCommit=$sha,[string]$digest=''){
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($candidate | ConvertTo-Json -Depth 8 -Compress))
    if(-not $digest){$digest=Get-F2V4Sha256 -Bytes $bytes}
    return Test-F2V4ReleaseContract -ManifestBytes $bytes -ExpectedManifestSha256 $digest -ExpectedActivePinsSha256 $pins -ExpectedCommitSha $expectedCommit -ActualCommitSha $actualCommit -ExpectedPackageHome $home
}
$good=Invoke-Contract $manifest
Assert-V4 ($good.Pass -and $good.Files -eq 10 -and -not $good.InstallAuthorized) 'source-only v4 candidate accepted without runtime/install authorization'
Assert-V4 (-not (Invoke-Contract $manifest ('0'*64)).Pass) 'wrong external active source-pins digest rejected'
Assert-V4 (-not (Invoke-Contract $manifest $sourcePins $sha ('f'*40)).Pass) 'unreviewed actual source commit rejected'
Assert-V4 (-not (Invoke-Contract $manifest $sourcePins $sha $sha ('0'*64)).Pass) 'wrong external manifest digest rejected'
function Copy-V4($candidate){return ($candidate | ConvertTo-Json -Depth 8 | ConvertFrom-Json)}
$x=Copy-V4 $manifest;$x.Schema='f2-icacls-runtime-release-v3'
Assert-V4 (-not (Invoke-Contract $x).Pass) 'v3/v4 cross-version confusion rejected'
$x=Copy-V4 $manifest;$x.Status='RELEASE_APPROVED'
Assert-V4 (-not (Invoke-Contract $x).Pass) 'attempted runtime-release activation status rejected'
$x=Copy-V4 $manifest;$x.BaselinePayloadSha256=('0'*64)
Assert-V4 (-not (Invoke-Contract $x).Pass) 'modified retained baseline digest rejected'
$x=Copy-V4 $manifest;$x.LegacySourcePinsManifestSha256=('0'*64)
Assert-V4 (-not (Invoke-Contract $x).Pass) 'changed historical icacls pins rejected'
$x=Copy-V4 $manifest;$x.Files=@($x.Files | Select-Object -Skip 1)
Assert-V4 (-not (Invoke-Contract $x).Pass) 'missing package member rejected'
$x=Copy-V4 $manifest;$x.Files[1].Name=$x.Files[0].Name
Assert-V4 (-not (Invoke-Contract $x).Pass) 'duplicate package member rejected'
$x=Copy-V4 $manifest;$x.Files[0].Name='evil.ps1'
Assert-V4 (-not (Invoke-Contract $x).Pass) 'unknown package member rejected'
$x=Copy-V4 $manifest;$x.Files[0].Sha256=('0'*63)
Assert-V4 (-not (Invoke-Contract $x).Pass) 'malformed package digest rejected'
$x=Copy-V4 $manifest;$x.Files=@($x.Files | ForEach-Object {
    if($_.Name -eq 'F2_ICACLS_SOURCE_PINS_V2.json'){$_.Sha256=('0'*64)};$_
})
Assert-V4 (-not (Invoke-Contract $x).Pass) 'source pins digest must equal package file pin'
$x=Copy-V4 $manifest;$x.PackageRoot='C:\F2SyntheticV4\OtherRoot'
Assert-V4 (-not (Invoke-Contract $x).Pass) 'package root mismatch rejected'
$x=Copy-V4 $manifest;$x.ReviewedCommitSha=('0'*40)
Assert-V4 (-not (Invoke-Contract $x).Pass) 'candidate reviewed commit mismatch rejected'
# A source-only functional fixture checks all ten REAL checkout bytes; the
# hashes computed here are test data, NOT independently approved release pins.
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$sourceActual=Copy-V4 $manifest
$sourceRows=@(foreach($name in $known){
    $file=Join-Path $PSScriptRoot $name
    $digest=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{Name=$name;Sha256=$digest}
})
$sourceActual.Files=$sourceRows
$actualPinDigest=[string](@($sourceRows | Where-Object { $_.Name -ceq 'F2_ICACLS_SOURCE_PINS_V2.json' })[0].Sha256)
$sourceActual.SourcePinsManifestSha256=$actualPinDigest
$sourceActual.LegacySourcePinsManifestSha256=[string](@($sourceRows | Where-Object { $_.Name -ceq 'F2_ICACLS_SOURCE_PINS.json' })[0].Sha256)
$sourceActual.CollectorPinsManifestSha256=[string](@($sourceRows | Where-Object { $_.Name -ceq 'F2_ACL_SOURCE_PINS_V2.json' })[0].Sha256)
$sourceActual.LegacyCollectorPinsManifestSha256=[string](@($sourceRows | Where-Object { $_.Name -ceq 'F2_ACL_SOURCE_PINS.json' })[0].Sha256)
$sourceBytes=[Text.UTF8Encoding]::new($false).GetBytes(($sourceActual | ConvertTo-Json -Depth 8 -Compress))
$sourceDigest=Get-F2V4Sha256 -Bytes $sourceBytes
$sourceCheck=Test-F2V4ReleaseContract -ManifestBytes $sourceBytes -ExpectedManifestSha256 $sourceDigest -ExpectedActivePinsSha256 $actualPinDigest -ExpectedCommitSha $sha -ActualCommitSha $sha -ExpectedPackageHome $home -VerifySourceBytes -SourceRoot $sourceRoot
Assert-V4 ($sourceCheck.Pass -and $sourceCheck.SourceBytesVerified -and -not $sourceCheck.InstallAuthorized) 'ten real checkout package files and nested v1/v2 pin roles validate read-only'
$badSource=Copy-V4 $sourceActual
$badSource.Files[0].Sha256=('0'*64)
$badBytes=[Text.UTF8Encoding]::new($false).GetBytes(($badSource | ConvertTo-Json -Depth 8 -Compress))
$badDigest=Get-F2V4Sha256 -Bytes $badBytes
$badSourceCheck=Test-F2V4ReleaseContract -ManifestBytes $badBytes -ExpectedManifestSha256 $badDigest -ExpectedActivePinsSha256 $actualPinDigest -ExpectedCommitSha $sha -ActualCommitSha $sha -ExpectedPackageHome $home -VerifySourceBytes -SourceRoot $sourceRoot
Assert-V4 (-not $badSourceCheck.Pass -and -not $badSourceCheck.InstallAuthorized) 'changed individual source-file pin fails the exact-byte package gate'
$wrongPath=Test-F2V4ReleaseContract -ManifestBytes $sourceBytes -ExpectedManifestSha256 $sourceDigest -ExpectedActivePinsSha256 $actualPinDigest -ExpectedCommitSha $sha -ActualCommitSha $sha -ExpectedPackageHome $home -VerifySourceBytes -SourceRoot 'G:\F2Forbidden'
Assert-V4 (-not $wrongPath.Pass -and -not $wrongPath.InstallAuthorized) 'project volume G: cannot be used as v4 source root'

# Static source checks: the current installed path must still reject v4.
$oldRuntime=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1'))
$oldCoordinator=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2IcaclsProtectedCoordinator.ps1'))
$oldUpdater=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2ProtectedReleaseUpdate.ps1'))
$oldLauncher=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Start-F2ProtectedReleaseUpdate.ps1'))
Assert-V4 ($oldRuntime.Contains("'f2-icacls-runtime-release-v3'") -and -not $oldRuntime.Contains("'f2-icacls-runtime-release-v4'")) 'runtime dispatch remains exclusively v3'
Assert-V4 ($oldCoordinator.Contains("'f2-icacls-runtime-release-v3'") -and -not $oldCoordinator.Contains("'f2-icacls-runtime-release-v4'")) 'protected coordinator dispatch remains exclusively v3'
Assert-V4 ($oldUpdater.Contains("[ValidateSet('v2','v3')]") -and -not $oldUpdater.Contains("[ValidateSet('v2','v3','v4')]")) 'updater candidate schema remains v3; legacy v2 retained'
Assert-V4 ($oldLauncher.Contains("'f2-icacls-runtime-release-v3'") -and -not $oldLauncher.Contains("'f2-icacls-runtime-release-v4'")) 'UAC launcher cannot activate v4'

Write-Output ("Assertions={0};Failures={1}" -f $script:count,$script:failures.Count)
if($script:failures.Count){exit 1}

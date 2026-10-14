[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Import dependency modules in this order to preserve PS 5.1 harness scope.
Import-Module (Join-Path $PSScriptRoot 'F2ReleasePreDispatch.V4.SourceOnly.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseContract.V4.SourceOnly.psm1') -Force -ErrorAction Stop

$script:assertions=0
$script:failures=[Collections.Generic.List[string]]::new()
function Assert-PreDispatch([bool]$condition,[string]$label){
    $script:assertions++
    if($condition){Write-Output ('PASS: '+$label)}
    else{$script:failures.Add($label);Write-Output ('FAIL: '+$label)}
}
$module=(Get-Module F2ReleasePreDispatch.V4.SourceOnly)
Assert-PreDispatch (@($module.ExportedCommands.Keys).Count -eq 1 -and $module.ExportedCommands.ContainsKey('Test-F2V4ReadOnlyPreDispatch')) 'pre-dispatch module exposes exactly one read-only verifier'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$gitFixture=Get-Command git.exe -CommandType Application -ErrorAction Stop
$gitExePath=[IO.Path]::GetFullPath([string]$gitFixture.Source)
$gitExeHash=(Get-FileHash -LiteralPath $gitExePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
$actualGitHead=[string]((Get-Module F2ReleasePreDispatch.V4.SourceOnly).Invoke({
    param($GitPath,$RepositoryPath)
    Invoke-F2V4GitRead -GitExecutable $GitPath -RepositoryRoot $RepositoryPath -Query Head
},$gitExePath,$root))
# The executable hash here is a synthetic fixture derived from local bytes.
# It is NOT an independently authorized Git toolchain identity.
Assert-PreDispatch ($actualGitHead -match '^[0-9a-f]{40}$') 'test fixture reads an actual valid Git SHA-1 HEAD'
$known=@(Get-F2V4PackageNames)
Assert-PreDispatch ($known.Count -eq 10 -and @($known|Sort-Object -Unique).Count -eq 10) 'v4 package inventory contains exactly ten distinct members'
$rows=@(foreach($name in $known){
    $path=Join-Path $PSScriptRoot $name
    [pscustomobject]@{Name=$name;Sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
})
function Get-FilePin([string]$Name) {return [string](@($rows | Where-Object {$_.Name -ceq $Name})[0].Sha256)}
$activePin=Get-FilePin 'F2_ICACLS_SOURCE_PINS_V2.json'
$legacyPin=Get-FilePin 'F2_ICACLS_SOURCE_PINS.json'
$collectorPin=Get-FilePin 'F2_ACL_SOURCE_PINS_V2.json'
$collectorLegacyPin=Get-FilePin 'F2_ACL_SOURCE_PINS.json'
$packageHome='C:\F2SyntheticV4\PackageHome'
$manifest=[ordered]@{
    Schema='f2-icacls-runtime-release-v4'
    Status='SOURCE_ONLY_NOT_RELEASE_APPROVED'
    ReviewedCommitSha=$actualGitHead
    PackageRoot=(Join-Path (Join-Path $packageHome 'releases') $actualGitHead)
    BaselineMailboxId='ecb6deeb424e40feb5354d18908986df'
    BaselinePayloadCaptureId='489e7fec-0300-467c-bfbd-a46fb8cf7211'
    BaselinePayloadSha256='1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
    BaselineIntegritySha256='02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
    SourcePinsManifestSha256=$activePin
    LegacySourcePinsManifestSha256=$legacyPin
    CollectorPinsManifestSha256=$collectorPin
    LegacyCollectorPinsManifestSha256=$collectorLegacyPin
    Files=$rows
}
function Get-TestBytes($obj){
    return [Text.UTF8Encoding]::new($false).GetBytes(($obj | ConvertTo-Json -Compress -Depth 10))
}
$goodBytes=[byte[]](Get-TestBytes $manifest)
$manifestDigest=Get-F2V4Sha256 -Bytes $goodBytes
# These digests are generated locally for test vectors ONLY, not external release approval.
function Invoke-TestPreflight {
    param([string]$Actor='Runtime',[byte[]]$Payload=$goodBytes,[string]$Commit=$actualGitHead,[string]$ManifestHash=$manifestDigest,[string]$PinHash=$activePin,[string]$Source=$root,[string]$PackageLocation=$packageHome,[string]$GitTool=$gitExePath,[string]$ToolHash=$gitExeHash)
    return Test-F2V4ReadOnlyPreDispatch -Role $Actor -ManifestBytes $Payload -ExternallyReviewedCommitSha $Commit -ExternallyApprovedManifestSha256 $ManifestHash -ExternallyApprovedActivePinsSha256 $PinHash -SourceRoot $Source -ExpectedPackageHome $PackageLocation -TrustedGitExecutablePath $GitTool -ExternallyPinnedGitExecutableSha256 $ToolHash
}
foreach($role in @('Collector','Runtime','Coordinator','Launcher','Updater','Recovery')){
    $v=Invoke-TestPreflight -Actor $role
    Assert-PreDispatch ($v.Pass -and $v.Disposition -ceq 'SOURCE_ONLY_INSPECTION_ACCEPTED' -and $v.VerifiedCheckoutHead -ceq $actualGitHead -and $v.GitHeadMatchesExpected -and $v.CheckoutClean -and $v.ExactTenSourceBytesVerified) ('real Git checkout and ten-byte package verify for '+$role)
    Assert-PreDispatch (-not $v.CanDispatch -and -not $v.CanCapture -and -not $v.CanLaunch -and -not $v.CanInstall -and -not $v.CanActivate -and -not $v.CanRollback -and -not $v.CanResumeForward -and -not $v.ReleaseApproved -and -not $v.ExternalReceiptIndependentlyAuthenticated -and -not $v.HasSideEffects) ('role '+$role+' cannot perform protected dispatch')
}
Assert-PreDispatch (-not (Invoke-TestPreflight -ToolHash ('0'*64)).Pass) 'incorrect externally pinned Git executable SHA-256 rejected before Git execution'
Assert-PreDispatch (-not (Invoke-TestPreflight -GitTool (Join-Path $root 'does-not-exist\git.exe')).Pass) 'missing trusted Git executable rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -GitTool 'G:\Forbidden\git.exe').Pass) 'G: Git binary path rejected before file I/O'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source '\\server\share\repo').Pass) 'UNC source root rejected before file I/O'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source '\\?\C:\Dev\repo').Pass) 'Windows device namespace rejected before file I/O'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source 'C:relative\repo').Pass) 'drive-relative source root rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source '\root-relative\repo').Pass) 'rooted-relative source root rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source 'Z:\Unmapped\repo').Pass) 'unavailable or non-fixed volume rejected'

# A junction is a reparse point even on a fixed drive; create and delete
# this synthetic fixture exclusively in the ordinary temp directory.
$junctionFixture=Join-Path ([IO.Path]::GetTempPath()) ('f2v4-source-junction-'+[Guid]::NewGuid().ToString('N'))
try {
    [void](New-Item -ItemType Junction -Path $junctionFixture -Target $root -ErrorAction Stop)
    Assert-PreDispatch (-not (Invoke-TestPreflight -Source $junctionFixture).Pass) 'junction/reparse source path rejected'
} finally {
    if([IO.Directory]::Exists($junctionFixture)){
        [IO.Directory]::Delete($junctionFixture,$false)
    }
}


# A temporary untracked fixture exercises the actual dirty checkout rejection.
# It is ALWAYS removed by finally, and no tracked file is modified.
$dirtyPath=Join-Path $root ('__F2_V4_DIRTY_SENTINEL__'+[Guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllText($dirtyPath,'synthetic untracked fixture')
    Assert-PreDispatch (-not (Invoke-TestPreflight).Pass) 'actual dirty checkout with untracked file rejected'
} finally {
    if([IO.File]::Exists($dirtyPath)){[IO.File]::Delete($dirtyPath)}
}
Assert-PreDispatch ((Invoke-TestPreflight).Pass) 'clean checkout accepted again after fixture cleanup'

# Test the process runner's bounded stdout and timeout with synthetic,
# nonprivileged PowerShell child processes (never updater, UAC or VM).
$testRunner=(Get-Module F2ReleasePreDispatch.V4.SourceOnly)
$powerShellFixture=(Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
$timedOut=$false
try {
    [void]$testRunner.Invoke({
        param($exe,$dir)
        Invoke-F2V4BoundedProcess -ExecutablePath $exe -WorkingDirectory $dir -ArgumentsText '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 5"' -TimeoutMilliseconds 150 -MaxOutputBytes 1024
    },$powerShellFixture,$root)
} catch { $timedOut=$true }
Assert-PreDispatch $timedOut 'synthetic stalled child process is rejected by deadline'
$overflowRejected=$false
try {
    [void]$testRunner.Invoke({
        param($exe,$dir)
        Invoke-F2V4BoundedProcess -ExecutablePath $exe -WorkingDirectory $dir -ArgumentsText '-NoProfile -NonInteractive -Command "[Console]::Out.Write((''x''*200000))"' -TimeoutMilliseconds 4000 -MaxOutputBytes 1024
    },$powerShellFixture,$root)
} catch { $overflowRejected=$true }
Assert-PreDispatch $overflowRejected 'synthetic oversized stdout stream rejected while draining'

# Force a malicious-looking inherited Git config. The bounded runner MUST clear
# GIT_CONFIG_* and must apply core.fsmonitor=false on its fixed command line.
$beforeCount=$env:GIT_CONFIG_COUNT
$beforeKey=$env:GIT_CONFIG_KEY_0
$beforeValue=$env:GIT_CONFIG_VALUE_0
try {
    $env:GIT_CONFIG_COUNT='1'
    $env:GIT_CONFIG_KEY_0='core.fsmonitor'
    $env:GIT_CONFIG_VALUE_0='C:\F2SyntheticV4\no-fsmonitor-helper.exe'
    Assert-PreDispatch ((Invoke-TestPreflight).Pass) 'inherited FSMonitor configuration cannot change the read-only preflight'
} finally {
    if($null -eq $beforeCount){[Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT',$null,'Process')}else{$env:GIT_CONFIG_COUNT=$beforeCount}
    if($null -eq $beforeKey){[Environment]::SetEnvironmentVariable('GIT_CONFIG_KEY_0',$null,'Process')}else{$env:GIT_CONFIG_KEY_0=$beforeKey}
    if($null -eq $beforeValue){[Environment]::SetEnvironmentVariable('GIT_CONFIG_VALUE_0',$null,'Process')}else{$env:GIT_CONFIG_VALUE_0=$beforeValue}
}

Assert-PreDispatch (-not (Invoke-TestPreflight -Commit ('0'*40)).Pass) 'incorrect expected reviewed source commit is rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -ManifestHash ('0'*64)).Pass) 'incorrect independently supplied manifest hash is rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -PinHash ('0'*64)).Pass) 'incorrect independently supplied active pin hash is rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source 'G:\F2Forbidden').Pass) 'G drive source root is rejected before Git access'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source $PSScriptRoot).Pass) 'non-root nested Git path is rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -Source (Join-Path $root 'f2-not-a-repository')).Pass) 'missing source root is rejected'
Assert-PreDispatch (-not (Invoke-TestPreflight -PackageLocation 'C:\F2SyntheticV4\IncorrectPackageHome').Pass) 'incorrect reviewed package root is rejected'
function Copy-Manifest {return ($manifest | ConvertTo-Json -Depth 10 | ConvertFrom-Json)}
$m=Copy-Manifest;$m.Schema='f2-icacls-runtime-release-v3'
$bytes=[byte[]](Get-TestBytes $m)
Assert-PreDispatch (-not (Invoke-TestPreflight -Payload $bytes -ManifestHash (Get-F2V4Sha256 -Bytes $bytes)).Pass) 'v3/v4 manifest confusion is rejected'
$m=Copy-Manifest;$m.Status='RELEASE_APPROVED'
$bytes=[byte[]](Get-TestBytes $m)
Assert-PreDispatch (-not (Invoke-TestPreflight -Payload $bytes -ManifestHash (Get-F2V4Sha256 -Bytes $bytes)).Pass) 'release approved status cannot bypass source-only hold'
$m=Copy-Manifest;$m.Files[0].Sha256=('0'*64)
$bytes=[byte[]](Get-TestBytes $m)
Assert-PreDispatch (-not (Invoke-TestPreflight -Payload $bytes -ManifestHash (Get-F2V4Sha256 -Bytes $bytes)).Pass) 'tampered member hash is rejected'
$m=Copy-Manifest;$m.BaselineIntegritySha256=('0'*64)
$bytes=[byte[]](Get-TestBytes $m)
Assert-PreDispatch (-not (Invoke-TestPreflight -Payload $bytes -ManifestHash (Get-F2V4Sha256 -Bytes $bytes)).Pass) 'altered retained baseline hash is rejected'

# Read only static source checks for installed v2/v3 entrypoints.
$runtimeText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1'))
$coordText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2IcaclsProtectedCoordinator.ps1'))
$updaterText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2ProtectedReleaseUpdate.ps1'))
$collectorText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Invoke-F2AclReadOnlyCapture.ps1'))
Assert-PreDispatch ($runtimeText.Contains("'f2-icacls-runtime-release-v3'") -and -not $runtimeText.Contains("'f2-icacls-runtime-release-v4'")) 'installed runtime remains v3-only'
Assert-PreDispatch ($coordText.Contains("'f2-icacls-runtime-release-v3'") -and -not $coordText.Contains("'f2-icacls-runtime-release-v4'")) 'protected coordinator remains v3-only'
Assert-PreDispatch ($updaterText.Contains("[ValidateSet('v2','v3')]") -and -not $updaterText.Contains("[ValidateSet('v2','v3','v4')]")) 'installed updater rejects v4'
Assert-PreDispatch ($collectorText.Contains("'f2-acl-source-pins-v1'") -and -not $collectorText.Contains("'f2-acl-source-pins-v2'")) 'collector remains v1 source-pinned'

Write-Output ("Assertions={0};Failures={1}" -f $script:assertions,$script:failures.Count)
if($script:failures.Count -ne 0){exit 1}

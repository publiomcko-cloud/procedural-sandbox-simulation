Set-StrictMode -Version Latest

# Independent, read-only candidate contract. No deployment functions are exported.
# Runtime/updater/collector/coordinator v3 interfaces intentionally do not import it.
$script:F2V4ExpectedFiles = @(
    'F2AclCapture.Protocol.psm1',
    'F2AclIcacls.Corroboration.psm1',
    'F2AclIcacls.Runtime.psm1',
    'Invoke-F2IcaclsCapture.ps1',
    'Invoke-F2IcaclsProtectedCoordinator.ps1',
    'Invoke-F2AclReadOnlyCapture.ps1',
    'F2_ICACLS_SOURCE_PINS.json',
    'F2_ICACLS_SOURCE_PINS_V2.json',
    'F2_ACL_SOURCE_PINS.json',
    'F2_ACL_SOURCE_PINS_V2.json'
)
$script:F2V4LegacyIcaclsSha = '7e05d48ef25e7cff19d84db151395921b5d89b52b1e2f45b94a84a4778a615ce'
$script:F2V4OldCollectorSha = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
$script:F2V4OldProtocolSha = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
$script:F2V4OldBase = 'a62773f0553dff4a05055b18fa10834f7488ae55'
$script:F2V4BaselineMailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:F2V4BaselineCaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:F2V4BaselinePayloadSha = '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
$script:F2V4BaselineIntegritySha = '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'

function Get-F2V4Sha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Get-F2V4PackageNames {
    [CmdletBinding()]
    param()
    return @($script:F2V4ExpectedFiles)
}
function Assert-F2V4SourcePathNoReparse {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while(-not [string]::IsNullOrWhiteSpace($current)){
        if([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)){
            $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'SOURCE_PATH_REPARSE'}
        }
        $parent=[IO.Directory]::GetParent($current)
        if($null -eq $parent){break}
        $current=$parent.FullName
    }
    return $true
}
function Test-F2V4ReleaseContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$ManifestBytes,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedActivePinsSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedCommitSha,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ActualCommitSha,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedPackageHome,
        [string]$SourceRoot,
        [switch]$VerifySourceBytes
    )
    $stage = 'MANIFEST_BYTES'
    try {
        # Callers must obtain these two expected SHA-256 values from an
        # independently approved receipt. Never hash and trust the same input.
        if($ManifestBytes.Length -lt 1 -or $ManifestBytes.Length -gt 65536 -or
            (Get-F2V4Sha256 -Bytes $ManifestBytes) -cne $ExpectedManifestSha256){
            throw 'MANIFEST_BYTES'
        }
        $stage = 'IDENTITY'
        if($ExpectedCommitSha -cne $ActualCommitSha){throw 'IDENTITY'}
        $m = [Text.UTF8Encoding]::new($false,$true).GetString($ManifestBytes) | ConvertFrom-Json -ErrorAction Stop
        if($null -eq $m -or $m -isnot [Management.Automation.PSCustomObject] -or
            $m.Schema -cne 'f2-icacls-runtime-release-v4' -or
            $m.Status -cne 'SOURCE_ONLY_NOT_RELEASE_APPROVED' -or
            $m.ReviewedCommitSha -cne $ExpectedCommitSha -or
            $m.BaselineMailboxId -cne $script:F2V4BaselineMailboxId -or
            $m.BaselinePayloadCaptureId -cne $script:F2V4BaselineCaptureId -or
            $m.BaselinePayloadSha256 -cne $script:F2V4BaselinePayloadSha -or
            $m.BaselineIntegritySha256 -cne $script:F2V4BaselineIntegritySha){
            throw 'IDENTITY'
        }
        $root=[IO.Path]::GetFullPath($ExpectedPackageHome)
        $expectedRoot=[IO.Path]::GetFullPath((Join-Path (Join-Path $root 'releases') $ExpectedCommitSha))
        if(-not [string]::Equals([string]$m.PackageRoot,$expectedRoot,[StringComparison]::OrdinalIgnoreCase)){
            throw 'IDENTITY'
        }
        $stage = 'SOURCE_PIN_ANCHOR'
        if($m.SourcePinsManifestSha256 -cne $ExpectedActivePinsSha256 -or
            $m.LegacySourcePinsManifestSha256 -cne $script:F2V4LegacyIcaclsSha -or
            $m.CollectorPinsManifestSha256 -notmatch '^[0-9a-f]{64}$' -or
            $m.LegacyCollectorPinsManifestSha256 -notmatch '^[0-9a-f]{64}$'){
            throw 'SOURCE_PIN_ANCHOR'
        }
        $stage = 'FILE_SET'
        $files=@($m.Files)
        if($files.Count -ne $script:F2V4ExpectedFiles.Count -or
            @($files.Name | Sort-Object -CaseSensitive -Unique).Count -ne $script:F2V4ExpectedFiles.Count -or
            @(Compare-Object ($script:F2V4ExpectedFiles | Sort-Object) ($files.Name | Sort-Object) -CaseSensitive).Count -ne 0){
            throw 'FILE_SET'
        }
        $pinMap = @{}
        foreach($f in $files){
            if($null -eq $f -or [string]$f.Name -cnotin $script:F2V4ExpectedFiles -or
                $f.Sha256 -notmatch '^[0-9a-f]{64}$' -or $pinMap.ContainsKey([string]$f.Name)){
                throw 'FILE_SET'
            }
            $pinMap[[string]$f.Name] = [string]$f.Sha256
        }
        if($pinMap['F2_ICACLS_SOURCE_PINS_V2.json'] -cne $m.SourcePinsManifestSha256 -or
            $pinMap['F2_ICACLS_SOURCE_PINS.json'] -cne $m.LegacySourcePinsManifestSha256 -or
            $pinMap['F2_ACL_SOURCE_PINS_V2.json'] -cne $m.CollectorPinsManifestSha256 -or
            $pinMap['F2_ACL_SOURCE_PINS.json'] -cne $m.LegacyCollectorPinsManifestSha256){
            throw 'SOURCE_PIN_ANCHOR'
        }
        if($VerifySourceBytes){
            $stage = 'PACKAGE_BYTES'
            if([string]::IsNullOrWhiteSpace($SourceRoot)){throw 'PACKAGE_BYTES'}
            $source=[IO.Path]::GetFullPath($SourceRoot)
            if($source -match '^[Gg]:\\' -or $source.StartsWith('\')){throw 'PACKAGE_BYTES'}
            [void](Assert-F2V4SourcePathNoReparse -Path $source)
            $sourceItem=Get-Item -LiteralPath $source -Force -ErrorAction Stop
            if(-not $sourceItem.PSIsContainer -or
                ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'PACKAGE_BYTES'}
            $base=Join-Path $source 'scripts\f2-acl'
            $contents=@{}
            foreach($name in $script:F2V4ExpectedFiles){
                $path=Join-Path $base $name
                [void](Assert-F2V4SourcePathNoReparse -Path $path)
                $entry=Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if($entry.PSIsContainer -or ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    $entry.Length -lt 1 -or $entry.Length -gt 4194304){throw 'PACKAGE_BYTES'}
                $bytes=[IO.File]::ReadAllBytes($entry.FullName)
                if((Get-F2V4Sha256 -Bytes $bytes) -cne $pinMap[$name]){throw 'PACKAGE_BYTES'}
                $contents[$name]=$bytes
            }
            $stage = 'PIN_ROLES'
            $activeIcacls = [Text.UTF8Encoding]::new($false,$true).GetString($contents['F2_ICACLS_SOURCE_PINS_V2.json']) | ConvertFrom-Json -ErrorAction Stop
            $activeAcl = [Text.UTF8Encoding]::new($false,$true).GetString($contents['F2_ACL_SOURCE_PINS_V2.json']) | ConvertFrom-Json -ErrorAction Stop
            $oldIcacls = [Text.UTF8Encoding]::new($false,$true).GetString($contents['F2_ICACLS_SOURCE_PINS.json']) | ConvertFrom-Json -ErrorAction Stop
            $oldAcl = [Text.UTF8Encoding]::new($false,$true).GetString($contents['F2_ACL_SOURCE_PINS.json']) | ConvertFrom-Json -ErrorAction Stop
            if($activeIcacls.Schema -cne 'f2-icacls-corroboration-pins-v2' -or
                $activeIcacls.Status -cne 'SOURCE_REVIEW_ONLY_NOT_RELEASE_APPROVED' -or
                $activeAcl.Schema -cne 'f2-acl-source-pins-v2' -or
                $activeAcl.Status -cne 'SOURCE_REVIEW_ONLY_NOT_RELEASE_APPROVED' -or
                $oldIcacls.Schema -cne 'f2-icacls-corroboration-pins-v1' -or
                $oldAcl.Schema -cne 'f2-acl-source-pins-v1' -or
                $activeIcacls.ReviewedCollectorBaseSha -cne $script:F2V4OldBase -or
                $activeAcl.ReviewedCollectorBaseSha -cne $script:F2V4OldBase -or
                $activeIcacls.LegacyPinManifestSha256 -cne $script:F2V4LegacyIcaclsSha -or
                $oldAcl.ModuleSha256 -cne $script:F2V4OldProtocolSha -or
                $oldAcl.ScriptSha256 -cne $script:F2V4OldCollectorSha -or
                $activeIcacls.RetainedBaseline.ProtocolModuleSha256 -cne $script:F2V4OldProtocolSha -or
                $activeIcacls.RetainedBaseline.CollectorScriptSha256 -cne $script:F2V4OldCollectorSha -or
                $activeAcl.RetainedBaseline.ProtocolModuleSha256 -cne $script:F2V4OldProtocolSha -or
                $activeAcl.RetainedBaseline.CollectorScriptSha256 -cne $script:F2V4OldCollectorSha){
                throw 'PIN_ROLES'
            }
            $pairs = @{
                'F2AclCapture.Protocol.psm1'='ProtocolModuleSha256'
                'F2AclIcacls.Corroboration.psm1'='CorroborationModuleSha256'
                'F2AclIcacls.Runtime.psm1'='RuntimeModuleSha256'
                'Invoke-F2IcaclsCapture.ps1'='LauncherScriptSha256'
                'Invoke-F2IcaclsProtectedCoordinator.ps1'='CoordinatorScriptSha256'
                'Invoke-F2AclReadOnlyCapture.ps1'='CollectorScriptSha256'
            }
            foreach($name in $pairs.Keys){
                if($pinMap[$name] -cne [string]$activeIcacls.Active.($pairs[$name])){throw 'PIN_ROLES'}
            }
            if($pinMap['F2AclCapture.Protocol.psm1'] -cne $activeAcl.Active.ProtocolModuleSha256 -or
                $pinMap['Invoke-F2AclReadOnlyCapture.ps1'] -cne $activeAcl.Active.CollectorScriptSha256){
                throw 'PIN_ROLES'
            }
        }
        return [pscustomobject]@{Pass=$true;Stage='SOURCE_V4_CONTRACT_VALID';Files=$files.Count;ReviewedCommitSha=$m.ReviewedCommitSha;SourceBytesVerified=[bool]$VerifySourceBytes;InstallAuthorized=$false;ErrorCode=$null}
    } catch {
        # Deliberately omit raw exceptions, paths, hashes and user input.
        return [pscustomobject]@{Pass=$false;Stage=$stage;Files=0;ReviewedCommitSha=$null;SourceBytesVerified=$false;InstallAuthorized=$false;ErrorCode='F2_V4_SOURCE_CONTRACT_REJECTED'}
    }
}
Export-ModuleMember -Function Get-F2V4Sha256,Get-F2V4PackageNames,Test-F2V4ReleaseContract

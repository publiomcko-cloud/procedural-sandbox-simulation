Set-StrictMode -Version Latest

# V4 production-facing read-only pre-dispatch seam. It does NOT dispatch.
# Existing protected v2/v3 runtime, collector, updater and recovery are unmodified.
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseIntegration.V4.SourceOnly.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseContract.V4.SourceOnly.psm1') -Force -ErrorAction Stop

function Assert-F2V4PreDispatchSourceRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceRoot)
    if([string]::IsNullOrWhiteSpace($SourceRoot) -or $SourceRoot -match '^[Gg]:[\\/]' -or $SourceRoot.StartsWith('\\')){
        throw 'F2_V4_INVALID_SOURCE_ROOT'
    }
    $root=[IO.Path]::GetFullPath($SourceRoot)
    $item=Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if(-not $item.PSIsContainer){throw 'F2_V4_SOURCE_NOT_DIRECTORY'}
    $cursor=$item.FullName
    while(-not [string]::IsNullOrWhiteSpace($cursor)){
        $node=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if(($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'F2_V4_SOURCE_REPARSE'}
        $parent=[IO.Directory]::GetParent($cursor)
        if($null -eq $parent){break}
        $cursor=$parent.FullName
    }
    return $root
}

function Invoke-F2V4GitRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GitExecutable,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $output=@(& $GitExecutable --no-optional-locks -C $RepositoryRoot @Arguments 2>&1)
    $code=$LASTEXITCODE
    if($code -ne 0 -or $output.Count -gt 10000){throw 'F2_V4_GIT_COMMAND_REJECTED'}
    return @($output)
}

function Test-F2V4ReadOnlyPreDispatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Collector','Runtime','Coordinator','Launcher','Updater','Recovery')][string]$Role,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$ManifestBytes,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExternallyReviewedCommitSha,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExternallyApprovedManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExternallyApprovedActivePinsSha256,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedPackageHome
    )
    $stage='ROOT'
    $passed=$false
    $actualHead=$null
    try {
        $root=Assert-F2V4PreDispatchSourceRoot -SourceRoot $SourceRoot
        $stage='GIT_EXECUTABLE'
        $git=Get-Command git.exe -CommandType Application -ErrorAction Stop
        $gitPath=[IO.Path]::GetFullPath([string]$git.Source)
        if(-not [IO.File]::Exists($gitPath)){throw 'F2_V4_GIT_BINARY_MISSING'}
        $stage='GIT_IDENTITY'
        $verifiedRoot=@(Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Arguments @('rev-parse','--show-toplevel'))
        $isWorktree=@(Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Arguments @('rev-parse','--is-inside-work-tree'))
        $heads=@(Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Arguments @('rev-parse','--verify','HEAD'))
        if($verifiedRoot.Count -ne 1 -or $isWorktree.Count -ne 1 -or $heads.Count -ne 1 -or
            [string]$isWorktree[0] -cne 'true'){throw 'F2_V4_GIT_IDENTITY_INVALID'}
        $actualRoot=[IO.Path]::GetFullPath(([string]$verifiedRoot[0]).Replace('/','\'))
        if(-not [string]::Equals($actualRoot,$root,[StringComparison]::OrdinalIgnoreCase)){throw 'F2_V4_WRONG_REPOSITORY_ROOT'}
        $actualHead=[string]$heads[0]
        if($actualHead -cne $ExternallyReviewedCommitSha){throw 'F2_V4_COMMIT_MISMATCH'}
        $stage='GIT_DIRTY_STATE'
        $dirty=@(Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Arguments @('status','--porcelain=v1','--untracked-files=normal'))
        if($dirty.Count -ne 0){throw 'F2_V4_DIRTY_SOURCE'}
        $stage='V4_SOURCE_PACKAGE'
        # All approved digests MUST originate from an external reviewed receipt.
        # This function checks the local checkout, not the approval signature.
        $result=Test-F2V4IntegrationBoundary -Role $Role -Action Inspect -ManifestBytes $ManifestBytes -ExpectedManifestSha256 $ExternallyApprovedManifestSha256 -ExpectedActivePinsSha256 $ExternallyApprovedActivePinsSha256 -ExpectedCommitSha $ExternallyReviewedCommitSha -ActualCommitSha $actualHead -ExpectedPackageHome $ExpectedPackageHome -SourceRoot $root -VerifySourceBytes
        if(-not $result.Pass -or -not $result.SourceBytesVerified -or $result.HasSideEffects -or $result.CanInstall -or
            $result.CanActivate -or $result.CanRollback -or $result.CanResumeForward){
            throw 'F2_V4_READ_ONLY_CONTRACT_REJECTED'
        }
        $stage='SOURCE_ONLY_PRE_DISPATCH_ACCEPTED'
        $passed=$true
    } catch {
        $passed=$false
    }
    return [pscustomobject]@{
        Pass=$passed
        Role=$Role
        Disposition=if($passed){'SOURCE_ONLY_INSPECTION_ACCEPTED'}else{'REJECTED'}
        Stage=$stage
        ErrorCode=if($passed){$null}else{'F2_V4_PRE_DISPATCH_REJECTED'}
        VerifiedCheckoutHead=if($passed){$actualHead}else{$null}
        GitHeadMatchesExpected=$passed
        CheckoutClean=$passed
        ExactTenSourceBytesVerified=$passed
        ExternalReceiptIndependentlyAuthenticated=$false
        ReleaseApproved=$false
        CanDispatch=$false
        CanCapture=$false
        CanLaunch=$false
        CanInstall=$false
        CanActivate=$false
        CanRollback=$false
        CanResumeForward=$false
        HasSideEffects=$false
    }
}
Export-ModuleMember -Function Test-F2V4ReadOnlyPreDispatch

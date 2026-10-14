Set-StrictMode -Version Latest
# Source-only role contract; never used by installed runtime or updater.
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseContract.V4.SourceOnly.psm1') -Force -ErrorAction Stop

$script:F2V4Roles=@('Collector','Runtime','Coordinator','Launcher','Updater','Recovery')
$script:F2V4OldManifestSha256='b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9'
$script:F2V4OldCommitSha='5741ffe90a3abd02a08563e6431e8a0b9b63eeb1'
$script:F2V4RecoveryPhases=@('INVENTORY_OBSERVED','RETAINED_V2_PIN_VERIFIED','V4_SOURCE_VERIFIED','PROTECTED_OPERATION_NOT_STARTED')

function Get-F2V4IntegrationRoles {
    [CmdletBinding()]
    param()
    return @($script:F2V4Roles)
}
function Get-F2V4IntegrationDescriptor {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('Collector','Runtime','Coordinator','Launcher','Updater','Recovery')][string]$Role)
    $current=switch($Role){
        'Collector' {'f2-acl-source-pins-v1'}
        'Recovery' {'f2-icacls-runtime-release-v2/v3'}
        default {'f2-icacls-runtime-release-v3'}
    }
    return [pscustomobject]@{Role=$Role;CurrentProductionContract=$current;CandidateContract='f2-icacls-runtime-release-v4';ContractStatus='SOURCE_ONLY_NOT_RELEASE_APPROVED';AllowedAction='Inspect';V4RuntimeDispatchAllowed=$false;V4InstallAllowed=$false;V4RecoveryAllowed=$false;RequiresIndependentCommitAuthentication=$true;RequiresExternalApprovedDigests=$true}
}
function Test-F2V4IntegrationBoundary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Collector','Runtime','Coordinator','Launcher','Updater','Recovery')][string]$Role,
        [Parameter(Mandatory)][ValidateSet('Inspect','Capture','Run','Launch','Install','Activate','Rollback','ResumeForward')][string]$Action,
        [Parameter(Mandatory)][byte[]]$ManifestBytes,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedActivePinsSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedCommitSha,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ActualCommitSha,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedPackageHome,
        [string]$SourceRoot,
        [switch]$VerifySourceBytes
    )
    $verified=$false
    try {
        if($Action -cne 'Inspect'){throw 'F2_V4_PROTECTED_ACTION_DISABLED'}
        if(-not $VerifySourceBytes -or [string]::IsNullOrWhiteSpace($SourceRoot)){throw 'F2_V4_EXACT_SOURCE_BYTES_REQUIRED'}
        # ActualCommitSha and digests are caller-provided, NOT independently authenticated here.
        $contract=Test-F2V4ReleaseContract -ManifestBytes $ManifestBytes -ExpectedManifestSha256 $ExpectedManifestSha256 -ExpectedActivePinsSha256 $ExpectedActivePinsSha256 -ExpectedCommitSha $ExpectedCommitSha -ActualCommitSha $ActualCommitSha -ExpectedPackageHome $ExpectedPackageHome -SourceRoot $SourceRoot -VerifySourceBytes
        if(-not $contract.Pass -or -not $contract.SourceBytesVerified -or $contract.InstallAuthorized){throw 'F2_V4_SOURCE_CONTRACT_REJECTED'}
        $verified=$true
    } catch { $verified=$false }
    return [pscustomobject]@{
        Role=$Role;Action=$Action;Pass=$verified
        Disposition=if($verified){'INSPECTION_ONLY'}else{'REJECTED'}
        ErrorCode=if($verified){$null}else{'F2_V4_SOURCE_ONLY_REJECTED'}
        SourceBytesVerified=$verified
        GitCommitIndependentlyAuthenticated=$false;ManifestIndependentlyApproved=$false
        CanCapture=$false;CanLaunch=$false;CanInstall=$false;CanActivate=$false
        CanRollback=$false;CanResumeForward=$false;HasSideEffects=$false
    }
}
function Test-F2V4RecoveryObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Inspect','Rollback','ResumeForward','Activate')][string]$Action,
        [Parameter(Mandatory)]$Observation,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$ExpectedTransactionId,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedCommitSha,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedCandidateManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedOldManifestSha256
    )
    $passed=$false
    try {
        # Pure synthetic observation envelope, NOT transaction.ndjson hash-chain validation.
        if($Action -cne 'Inspect'){throw 'V4_RECOVERY_ACTION_DISABLED'}
        if($ExpectedOldManifestSha256 -cne $script:F2V4OldManifestSha256){throw 'HISTORICAL_RECEIPT_MISMATCH'}
        if($null -eq $Observation -or
            $Observation.Schema -cne 'f2-v4-recovery-observation-v1' -or
            $Observation.ContractStatus -cne 'SOURCE_ONLY_NOT_RELEASE_APPROVED' -or
            $Observation.TransactionId -cne $ExpectedTransactionId -or
            $Observation.ReviewedCommitSha -cne $ExpectedCommitSha -or
            $Observation.CandidateManifestSha256 -cne $ExpectedCandidateManifestSha256 -or
            $Observation.OldManifestSha256 -cne $ExpectedOldManifestSha256 -or
            $Observation.OldReleaseCommitSha -cne $script:F2V4OldCommitSha -or
            $Observation.ActiveManifestSha256 -cne $script:F2V4OldManifestSha256 -or
            $Observation.LegacyBackupPreserved -cne $true -or
            $Observation.ProtectedOperationOccurred -cne $false){throw 'RECOVERY_OBSERVATION_IDENTITY_INVALID'}
        $states=@($Observation.Phases)
        if($states.Count -ne $script:F2V4RecoveryPhases.Count){throw 'RECOVERY_OBSERVATION_SEQUENCE_INVALID'}
        for($i=0;$i -lt $states.Count;$i++){
            if([string]$states[$i] -cne $script:F2V4RecoveryPhases[$i]){throw 'RECOVERY_OBSERVATION_SEQUENCE_INVALID'}
        }
        $passed=$true
    } catch { $passed=$false }
    return [pscustomobject]@{
        Pass=$passed;Action=$Action
        Disposition=if($passed){'OBSERVATION_ACCEPTED_NO_RECOVERY'}else{'REJECTED'}
        ErrorCode=if($passed){$null}else{'F2_V4_RECOVERY_OBSERVATION_REJECTED'}
        LegacyReleasePreserved=if($passed){$true}else{$false}
        MayPerformProtectedRecovery=$false;MayRollback=$false;MayResumeForward=$false
        MayActivate=$false;HasSideEffects=$false
    }
}
Export-ModuleMember -Function Get-F2V4IntegrationRoles,Get-F2V4IntegrationDescriptor,Test-F2V4IntegrationBoundary,Test-F2V4RecoveryObservation

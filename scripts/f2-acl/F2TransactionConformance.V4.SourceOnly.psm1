# Source-only F2 G1 transaction-v4 abstract conformance model.
# No filesystem reads or writes, child processes, Git, signatures, installer or recovery.
Set-StrictMode -Version Latest
$script:DispositionByState = @{
    REJECTED_RECEIPT='REJECT_BEFORE_WRITE'
    TRUST_BOOTSTRAP_UNPROVEN='REJECT_BEFORE_WRITE'
    AUTHORITY_UNAVAILABLE='REJECT_BEFORE_WRITE'
    UNSUPPORTED_OPERATION='REJECT_BEFORE_WRITE'
    UNSUPPORTED_PREDECESSOR='REJECT_BEFORE_WRITE'
    PREDECESSOR_OBSERVED='OBSERVE_ONLY'
    SOURCE_ONLY_ACCEPTED='OBSERVE_ONLY'
    OBSERVATION_ONLY='OBSERVE_ONLY'
    NEW_ACTIVE_COMPLETE_OBSERVED='OBSERVE_ONLY'
    PRECONDITION_UNMET='HOLD_PRESERVE'
    UNTRUSTED_TRANSACTION='HOLD_PRESERVE'
    REMOTE_RESERVED_NO_LOCAL='HOLD_PRESERVE'
    LOCAL_ROOT_GENESIS_INCOMPLETE='HOLD_PRESERVE'
    OLD_ACTIVE_PARTIAL_STAGING='HOLD_PRESERVE'
    OLD_ACTIVE_FORWARD_ELIGIBILITY_CANDIDATE='HOLD_PRESERVE'
    NEW_ACTIVE_VERIFY_ONLY_CANDIDATE='HOLD_PRESERVE'
    AMBIGUOUS_NEW_ACTIVE='HOLD_PRESERVE'
    UNKNOWN_ACTIVE='HOLD_PRESERVE'
    QUIESCENCE_UNPROVEN='HOLD_PRESERVE'
}
function New-F2V4ConformanceDecision {
    param([string]$InspectionState)
    if(-not $script:DispositionByState.ContainsKey($InspectionState)){
        $InspectionState='PRECONDITION_UNMET'
    }
    return [pscustomobject]@{
        InspectionState=$InspectionState
        Classification=$script:DispositionByState[$InspectionState]
        CanMutate=$false
        CanInstall=$false
        CanActivate=$false
        CanRollback=$false
        CanRecoverForward=$false
        CanFinalizePostSwitch=$false
        HasProductionAuthority=$false
        Mode='SOURCE_ONLY_SYNTHETIC'
    }
}
function Resolve-F2V4ConformanceObservation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateNotNull()][psobject]$Evidence)
    # Evidence is synthetic input facts, never a trusted production observation.
    # Reject fields that could inject a verdict, capability or unknown semantics.
    $allowed=@('Domain','Condition','LocalWritePossible','RootPresent','AuthorityReserved','RequestedOperation','SignatureValidated')
    foreach($property in $Evidence.PSObject.Properties){
        if($allowed -cnotcontains [string]$property.Name){
            return New-F2V4ConformanceDecision -InspectionState 'PRECONDITION_UNMET'
        }
    }
    foreach($required in $allowed){
        if($null -eq $Evidence.PSObject.Properties[$required]){
            return New-F2V4ConformanceDecision -InspectionState 'PRECONDITION_UNMET'
        }
    }
    $domain=[string]$Evidence.Domain
    $condition=[string]$Evidence.Condition
    if([string]::IsNullOrEmpty($domain) -or [string]::IsNullOrEmpty($condition)){
        return New-F2V4ConformanceDecision -InspectionState 'PRECONDITION_UNMET'
    }
    foreach($field in @('LocalWritePossible','RootPresent','AuthorityReserved','SignatureValidated')){
        $property=$Evidence.PSObject.Properties[$field]
        if($null -ne $property -and $property.Value -isnot [bool]){
            return New-F2V4ConformanceDecision -InspectionState 'PRECONDITION_UNMET'
        }
    }
    $localWrite=$Evidence.LocalWritePossible -eq $true
    $state='PRECONDITION_UNMET'
    switch -CaseSensitive ($domain) {
        'Receipt' {
            if(@('Missing','SourceOnlyInstall','SelfSigned','UnverifiedSignature','CommitMismatch','MemberMismatch',
                 'HistoricalPinMismatch','MixedSchema','PrivilegedGit','ExecutablePinMismatch','ForbiddenPath',
                 'DuplicateField','AlgorithmConfusion','RevokedSigner','ExpiredSigner','ReplayOtherTx',
                 'ReplayChangedTuple','ReplayOtherEnvironment') -ccontains $condition){$state='REJECTED_RECEIPT'}
        }
        'Cutover' {
            if(@('DraftV3','UnknownInstalledVersion','LegacyInstallRequested') -ccontains $condition){
                $state='UNSUPPORTED_PREDECESSOR'
            }
        }
        'Bootstrap' {
            if(@('Unprovisioned','PolicyUnenforced','CandidateControlledKey','ConstrainedLanguage') -ccontains $condition){
                $state='TRUST_BOOTSTRAP_UNPROVEN'
            }
        }
        'Authority' {
            if(@('Offline','TrustedTimeUnavailable') -ccontains $condition){
                if($localWrite){$state='PRECONDITION_UNMET'}else{$state='AUTHORITY_UNAVAILABLE'}
            } elseif(@('DuplicateApprovalOtherTx','SameTxAlteredTuple','CrossEnvironmentReplay') -ccontains $condition){
                $state='REJECTED_RECEIPT'
            } elseif(@('IdenticalReplay','OfflineAfterWrite') -ccontains $condition){
                $state='PRECONDITION_UNMET'
            } elseif(@('OldHeadRestore','OldGeneration','RootWithoutReservation','AlreadyConsumedFinalizer') -ccontains $condition){
                $state='UNTRUSTED_TRANSACTION'
            } elseif($condition -ceq 'ReservedWithoutRoot') {
                if($Evidence.AuthorityReserved -eq $true -and $Evidence.RootPresent -eq $false){
                    $state='REMOTE_RESERVED_NO_LOCAL'
                }
            }
        }
        'Journal' {
            if(@('LegacySchema','SequenceGap','PreviousHashMismatch','NoncanonicalBytes','RewrittenChain',
                 'TupleChanged','UnknownFlush','GenesisNotAnchored','EventHashMismatch','NoPublishIntent',
                 'NoSwitchIntent','RemoteCompletionMissing','CheckpointMismatch') -ccontains $condition){
                $state='UNTRUSTED_TRANSACTION'
            } elseif(@('GenesisMissing','GenesisTorn') -ccontains $condition){
                if($Evidence.RootPresent -eq $true -and $Evidence.AuthorityReserved -eq $true){
                    $state='LOCAL_ROOT_GENESIS_INCOMPLETE'
                }
            }
        }
        'Transaction' {
            if(@('LeaseConflict','DuplicateTransaction','BeforeStage','UnsignedForward',
                 'UnapprovedRollback','AutoRepair','LostLease','NoStageIntent','AmbiguousRename',
                 'VolumeMismatch','BackupPublishIncomplete','BackupNotVerified','BackupCollision',
                 'RepeatManifestSwap','UnprovenCrashTier','DirectoryFlushUnknown','UnsupportedPowerCrash',
                 'UnsupportedOfflineAuthority') -ccontains $condition){$state='PRECONDITION_UNMET'}
        }
        'Active' {
            switch -CaseSensitive ($condition) {
                'OldWithPublishedTarget' { $state='OLD_ACTIVE_FORWARD_ELIGIBILITY_CANDIDATE' }
                'TargetWithBothBackups' { $state='NEW_ACTIVE_VERIFY_ONLY_CANDIDATE' }
                'TargetMissingFinalizeReceipt' { $state='NEW_ACTIVE_VERIFY_ONLY_CANDIDATE' }
                'TargetAuthorizedFinalizeCandidate' { $state='NEW_ACTIVE_VERIFY_ONLY_CANDIDATE' }
                'TargetMissingBackup' { $state='AMBIGUOUS_NEW_ACTIVE' }
                'OldPackageModified' { $state='AMBIGUOUS_NEW_ACTIVE' }
                'BackupsDisagree' { $state='AMBIGUOUS_NEW_ACTIVE' }
                'TargetPackageMismatch' { $state='AMBIGUOUS_NEW_ACTIVE' }
                'AmbiguousReplaceNames' { $state='AMBIGUOUS_NEW_ACTIVE' }
                'UnknownPointer' { $state='UNKNOWN_ACTIVE' }
                'TerminalVerified' { $state='NEW_ACTIVE_COMPLETE_OBSERVED' }
                'TargetWithoutSwitchIntent' { $state='UNTRUSTED_TRANSACTION' }
            }
        }
        'Quiescence' {
            if(@('AclOrReparseConflict','LateV2Worker','UnmediatedV3','MetadataInaccessible',
                 'LegacyLaunchStillAllowed','CachedOldReader') -ccontains $condition){
                $state='QUIESCENCE_UNPROVEN'
            }
        }
        'Recovery' {
            if(@('RollbackWithInstallReceipt','AuthenticRollbackReceipt') -ccontains $condition){
                if($Evidence.RequestedOperation -ceq 'ROLLBACK'){$state='UNSUPPORTED_OPERATION'}
            } elseif($condition -ceq 'ConsumedFinalizer'){$state='UNTRUSTED_TRANSACTION'}
        }
        'Observation' {
            switch -CaseSensitive ($condition) {
                'VerifiedHistoricalV2' {$state='PREDECESSOR_OBSERVED'}
                'ValidatedSourceOnlyV4' {$state='SOURCE_ONLY_ACCEPTED'}
                'CIInconclusive' {$state='OBSERVATION_ONLY'}
                'SyntheticReviewOnly' {$state='OBSERVATION_ONLY'}
                'DesignOnly' {$state='OBSERVATION_ONLY'}
            }
        }
    }
    return New-F2V4ConformanceDecision -InspectionState $state
}
function New-F2V4FakeAuthority {
    [CmdletBinding()]
    param()
    # Mutable in-memory test double only: NOT a signer, durable CAS or real authority.
    return @{
        Generation=0
        Approvals=@{}
        Transactions=@{}
        Checkpoints=@{}
        Kind='IN_MEMORY_TEST_DOUBLE_NOT_DURABLE'
    }
}
function Invoke-F2V4FakeReservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Authority,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$ApprovalId,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$TxId,
        [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{1,64}$')][string]$EnvironmentId,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$TargetDigest,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][int]$ExpectedGeneration,
        [string]$PredecessorSchema='synthetic'
    )
    $status='DENIED'
    $tuple="$TxId|$EnvironmentId|$TargetDigest|$Operation"
    if($Operation -cnotin @('INSTALL','RECOVER_FORWARD','FINALIZE_POST_SWITCH')){
        $status='UNSUPPORTED_OPERATION'
    } elseif($PredecessorSchema -cin @('v2','v3')){
        $status='UNSUPPORTED_PREDECESSOR'
    } elseif($Authority.Approvals.ContainsKey($ApprovalId)){
        if($Authority.Approvals[$ApprovalId] -ceq $tuple){$status='REPLAY_IDENTICAL'}
        else{$status='REPLAY_CONFLICT'}
    } elseif($Authority.Transactions.ContainsKey($TxId)) {
        $existing=$Authority.Transactions[$TxId]
        if($existing.EnvironmentId -cne $EnvironmentId -or $existing.TargetDigest -cne $TargetDigest){
            $status='REPLAY_CONFLICT'
        } elseif($existing.Operations.ContainsKey($Operation)){
            $status='REPLAY_CONFLICT'
        } elseif($Operation -ceq 'INSTALL'){
            $status='REPLAY_CONFLICT'
        } elseif($ExpectedGeneration -ne [int]$Authority.Generation){
            $status='STALE_GENERATION'
        } else {
            $Authority.Generation=[int]$Authority.Generation+1
            $Authority.Approvals[$ApprovalId]=$tuple
            $existing.Operations[$Operation]=$ApprovalId
            $status='RESERVED_SIMULATED'
        }
    } elseif($Operation -cne 'INSTALL'){
        $status='MISSING_INSTALL_REJECTED'
    } elseif($ExpectedGeneration -ne [int]$Authority.Generation){
        $status='STALE_GENERATION'
    } else {
        $Authority.Generation=[int]$Authority.Generation+1
        $Authority.Approvals[$ApprovalId]=$tuple
        $opLedger=@{}
        $opLedger[$Operation]=$ApprovalId
        $Authority.Transactions[$TxId]=@{EnvironmentId=$EnvironmentId;TargetDigest=$TargetDigest;Operations=$opLedger}
        $status='RESERVED_SIMULATED'
    }
    return [pscustomobject]@{
        Status=$status
        Generation=[int]$Authority.Generation
        CanMutate=$false
        SignedCertificateProduced=$false
        Durable=$false
    }
}
function Set-F2V4FakeCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Authority,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$TxId,
        [Parameter(Mandatory)][ValidateRange(1,65535)][int]$NextSequence,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$HeadSha256
    )
    $status='REJECTED'
    if($Authority.Transactions.ContainsKey($TxId)){
        $prior=0
        if($Authority.Checkpoints.ContainsKey($TxId)){$prior=[int]$Authority.Checkpoints[$TxId].Sequence}
        if($NextSequence -eq $prior+1){
            $Authority.Checkpoints[$TxId]=[pscustomobject]@{Sequence=$NextSequence;HeadSha256=$HeadSha256}
            $status='CHECKPOINT_SIMULATED'
        }else{$status='NONMONOTONIC_REJECTED'}
    }
    return [pscustomobject]@{Status=$status;CanMutate=$false;Durable=$false}
}
function Compare-F2V4FakeCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Authority,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string]$TxId,
        [Parameter(Mandatory)][ValidateRange(0,65535)][int]$LocalSequence,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$LocalHeadSha256
    )
    $status='NO_ANCHOR'
    if($Authority.Checkpoints.ContainsKey($TxId)){
        $p=$Authority.Checkpoints[$TxId]
        if($LocalSequence -lt [int]$p.Sequence){$status='OLDER_PREFIX'}
        elseif($LocalSequence -gt [int]$p.Sequence){$status='LOCAL_AHEAD_UNANCHORED'}
        elseif($LocalHeadSha256 -cne $p.HeadSha256){$status='HEAD_MISMATCH'}
        else{$status='MATCH'}
    }
    return [pscustomobject]@{Status=$status;CanMutate=$false;Durable=$false}
}
function Test-F2V4ConformanceTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FromState,
        [Parameter(Mandatory)][string]$ToState,
        [Parameter(Mandatory)][ValidateSet('Normal','FinalizeEvidence','Rollback')][string]$ModelPath,
        [bool]$SyntheticPrerequisitesVerified=$false,
        [bool]$SyntheticOperationApproval=$false,
        [bool]$SyntheticTargetAndBackupsExact=$false
    )
    # These are pure candidate state-machine edges. Nothing is executed and
    # a modeled edge is NOT an installation/recovery capability.
    $normal=@('REMOTE_RESERVED_NO_LOCAL','GENESIS','STAGE_INTENT','STAGE_CREATED',
        'PACKAGE_VERIFIED','PUBLISH_INTENT','PACKAGE_PUBLISHED',
        'BACKUP_INTENT','BACKUP_DURABLE','SWITCH_INTENT',
        'ACTIVE_MANIFEST_SWITCHED','POSTCHECK_VERIFIED','COMMIT_DURABLE')
    $allowed=$false
    $reason='UNSUPPORTED_EDGE'
    if($ModelPath -ceq 'Rollback'){
        $reason='ROLLBACK_UNSUPPORTED'
    } elseif(-not $SyntheticPrerequisitesVerified -or -not $SyntheticOperationApproval){
        $reason='SYNTHETIC_PRECONDITION_UNMET'
    } elseif($ModelPath -ceq 'Normal'){
        $index=[array]::IndexOf($normal,$FromState)
        if($index -ge 0 -and $index -lt ($normal.Count-1) -and $normal[$index+1] -ceq $ToState){
            $allowed=$true
            $reason='PURE_ADJACENT_EDGE_MODELED'
        }
    } elseif($ModelPath -ceq 'FinalizeEvidence'){
        # Never model a second active-manifest switch.
        $edges=@{
            SWITCH_INTENT='RECOVERY_POST_SWITCH_VERIFIED'
            RECOVERY_POST_SWITCH_VERIFIED='POSTCHECK_VERIFIED'
            POSTCHECK_VERIFIED='COMMIT_DURABLE'
        }
        if($SyntheticTargetAndBackupsExact -and $edges.ContainsKey($FromState) -and
            $edges[$FromState] -ceq $ToState){
            $allowed=$true
            $reason='PURE_FINALIZATION_EVIDENCE_EDGE_MODELED'
        }
    }
    $classification=if($allowed){'OBSERVE_ONLY'}elseif($ModelPath -ceq 'Rollback'){'REJECT_BEFORE_WRITE'}else{'HOLD_PRESERVE'}
    return [pscustomobject]@{
        AllowedInModel=$allowed
        Reason=$reason
        Classification=$classification
        CanMutate=$false
        CanInstall=$false
        CanActivate=$false
        CanRollback=$false
        CanRecoverForward=$false
        CanFinalizePostSwitch=$false
        HasProductionAuthority=$false
        Mode='SOURCE_ONLY_SYNTHETIC'
    }
}
Export-ModuleMember -Function Resolve-F2V4ConformanceObservation,New-F2V4FakeAuthority,Invoke-F2V4FakeReservation,Set-F2V4FakeCheckpoint,Compare-F2V4FakeCheckpoint,Test-F2V4ConformanceTransition

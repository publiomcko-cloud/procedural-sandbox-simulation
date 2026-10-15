# Windows PowerShell 5.1 synthetic-only conformance harness.
# Reads two design JSON fixtures and imports ONLY the new in-memory model.
# It never launches the installed updater or touches protected paths.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:AssertPassed=0
$script:AssertFailed=0
function Assert-F2V4Conformance {
    param([bool]$Condition,[string]$Label)
    if($Condition){
        $script:AssertPassed++
    }else{
        $script:AssertFailed++
        [Console]::Error.WriteLine("F2_V4_CONFORMANCE_ASSERT_FAIL: $Label")
    }
}
function Test-F2V4NoPower {
    param([psobject]$Result)
    return ($Result.CanMutate -eq $false -and $Result.CanInstall -eq $false -and $Result.CanActivate -eq $false -and
        $Result.CanRollback -eq $false -and $Result.CanRecoverForward -eq $false -and
        $Result.CanFinalizePostSwitch -eq $false -and $Result.HasProductionAuthority -eq $false)
}
$repoRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$reviewRoot=Join-Path $repoRoot 'docs/reviews/f2-g1-v4-transaction-design'
$matrixPath=Join-Path $reviewRoot 'ACCEPTANCE_MATRIX.json'
$factsPath=Join-Path $reviewRoot 'CONFORMANCE_FACTS.SourceOnly.json'
$modelPath=Join-Path $PSScriptRoot 'F2TransactionConformance.V4.SourceOnly.psm1'
try {
    if(-not [IO.File]::Exists($matrixPath) -or -not [IO.File]::Exists($factsPath) -or -not [IO.File]::Exists($modelPath)){
        throw 'F2_V4_REQUIRED_SOURCE_FILE_MISSING'
    }
    Import-Module -Name $modelPath -Force -ErrorAction Stop
    $matrix=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($matrixPath,[Text.Encoding]::UTF8)) -ErrorAction Stop
    $facts=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($factsPath,[Text.Encoding]::UTF8)) -ErrorAction Stop
    Assert-F2V4Conformance ($matrix.Schema -ceq 'f2-g1-v4-transaction-design-acceptance-matrix-v3') 'immutable 92-case R3 oracle schema'
    Assert-F2V4Conformance ($facts.Schema -ceq 'f2-g1-v4-pure-conformance-facts-v1') 'synthetic facts version'
    Assert-F2V4Conformance ($facts.OriginDesignHead -ceq 'c15b6440f91fe363b7bc1be7bf24b59229c3e402') 'fixtures bound to reviewed R3 design SHA'
    Assert-F2V4Conformance (@($matrix.Cases).Count -eq 92) 'oracle has 92 reviewed cases'
    Assert-F2V4Conformance (@($facts.Vectors).Count -eq 92) 'facts have 92 independent inputs'
    Assert-F2V4Conformance (@($matrix.ClosedInspectionStateDispositionMap.PSObject.Properties).Count -eq 19) '19-state closed oracle'
    $expectedIds=@{}
    foreach($oracle in @($matrix.Cases)){
        Assert-F2V4Conformance (-not $expectedIds.ContainsKey([string]$oracle.id)) ("oracle id unique: "+$oracle.id)
        $expectedIds[[string]$oracle.id]=$oracle
    }
    $seen=@{}
    $factsBefore=ConvertTo-Json -InputObject $facts.Vectors -Depth 12 -Compress
    foreach($vector in @($facts.Vectors)){
        $id=[string]$vector.Id
        Assert-F2V4Conformance ($expectedIds.ContainsKey($id) -and -not $seen.ContainsKey($id)) ("facts id unique and matches oracle: "+$id)
        if(-not $expectedIds.ContainsKey($id) -or $seen.ContainsKey($id)){continue}
        $seen[$id]=$true
        $oracle=$expectedIds[$id]
        try {
            $result=Resolve-F2V4ConformanceObservation -Evidence $vector.Facts
            Assert-F2V4Conformance ($result.InspectionState -ceq $oracle.inspection_state) ("state "+$id+" "+$vector.Facts.Domain+"/"+$vector.Facts.Condition)
            Assert-F2V4Conformance ($result.Classification -ceq $oracle.expected_classification) ("default classification "+$id)
            Assert-F2V4Conformance (Test-F2V4NoPower -Result $result) ("zero production permissions "+$id)
            $mapped=$matrix.ClosedInspectionStateDispositionMap.PSObject.Properties[[string]$result.InspectionState]
            Assert-F2V4Conformance ($null -ne $mapped -and [string]$mapped.Value -ceq $result.Classification) ("reviewed closed map "+$id)
            Assert-F2V4Conformance ($oracle.default_mutation_allowed -eq $false) ("oracle forbids mutations "+$id)
        } catch {
            Assert-F2V4Conformance $false ("unexpected evaluator error "+$id+": "+$_.Exception.Message)
        }
    }
    Assert-F2V4Conformance ($seen.Count -eq 92) 'all 92 source-only cases independently evaluated'
    Assert-F2V4Conformance ($factsBefore -ceq (ConvertTo-Json -InputObject $facts.Vectors -Depth 12 -Compress)) 'pure evaluator never modifies input facts'

    $baseline=[pscustomobject]@{
        Domain='Observation';Condition='VerifiedHistoricalV2'
        LocalWritePossible=$false;RootPresent=$false;AuthorityReserved=$false
        RequestedOperation='INSPECT';SignatureValidated=$false
    }
    $baseResult=Resolve-F2V4ConformanceObservation -Evidence $baseline
    Assert-F2V4Conformance ($baseResult.InspectionState -ceq 'PREDECESSOR_OBSERVED') 'baseline observation'
    $spoof=[pscustomobject]@{
        Domain='Observation';Condition='VerifiedHistoricalV2'
        LocalWritePossible=$false;RootPresent=$false;AuthorityReserved=$false
        RequestedOperation='INSPECT';SignatureValidated=$false
        InspectionState='NEW_ACTIVE_COMPLETE_OBSERVED'
    }
    $spoofResult=Resolve-F2V4ConformanceObservation -Evidence $spoof
    Assert-F2V4Conformance ($spoofResult.InspectionState -ceq 'PRECONDITION_UNMET' -and (Test-F2V4NoPower $spoofResult)) 'caller-supplied verdict field rejected'
    $missing= [pscustomobject]@{Domain='Receipt';Condition='Missing'}
    Assert-F2V4Conformance ((Resolve-F2V4ConformanceObservation -Evidence $missing).Classification -ceq 'HOLD_PRESERVE') 'missing structural evidence fields fail closed'
    $unknown=[pscustomobject]@{
        Domain='Fake';Condition='Tricked';LocalWritePossible=$false;RootPresent=$false
        AuthorityReserved=$false;RequestedOperation='INSPECT';SignatureValidated=$false
    }
    Assert-F2V4Conformance ((Resolve-F2V4ConformanceObservation -Evidence $unknown).Classification -ceq 'HOLD_PRESERVE') 'unknown synthetic evidence domain fails closed'
    $noRoot=[pscustomobject]@{
        Domain='Authority';Condition='ReservedWithoutRoot';LocalWritePossible=$false;RootPresent=$false
        AuthorityReserved=$true;RequestedOperation='INSPECT';SignatureValidated=$false
    }
    $hasRoot=[pscustomobject]@{
        Domain='Authority';Condition='ReservedWithoutRoot';LocalWritePossible=$false;RootPresent=$true
        AuthorityReserved=$true;RequestedOperation='INSPECT';SignatureValidated=$false
    }
    Assert-F2V4Conformance ((Resolve-F2V4ConformanceObservation -Evidence $noRoot).InspectionState -ceq 'REMOTE_RESERVED_NO_LOCAL') 'remote-only root absent'
    Assert-F2V4Conformance ((Resolve-F2V4ConformanceObservation -Evidence $hasRoot).Classification -ceq 'HOLD_PRESERVE' -and
        (Resolve-F2V4ConformanceObservation -Evidence $hasRoot).InspectionState -cne 'REMOTE_RESERVED_NO_LOCAL') 'present root cannot masquerade as no-root'
    $rollback=[pscustomobject]@{
        Domain='Recovery';Condition='AuthenticRollbackReceipt';LocalWritePossible=$false;RootPresent=$false
        AuthorityReserved=$false;RequestedOperation='ROLLBACK';SignatureValidated=$true
    }
    $rb=Resolve-F2V4ConformanceObservation -Evidence $rollback
    Assert-F2V4Conformance ($rb.InspectionState -ceq 'UNSUPPORTED_OPERATION' -and $rb.Classification -ceq 'REJECT_BEFORE_WRITE' -and
        (Test-F2V4NoPower $rb)) 'T86 verified-signature simulation cannot authorize rollback'
    $offline=[pscustomobject]@{
        Domain='Authority';Condition='Offline';LocalWritePossible=$true;RootPresent=$false
        AuthorityReserved=$false;RequestedOperation='INSPECT';SignatureValidated=$false
    }
    Assert-F2V4Conformance ((Resolve-F2V4ConformanceObservation -Evidence $offline).Classification -ceq 'HOLD_PRESERVE') 'authority outage after possible local write cannot claim prewrite rejection'


    # A possible earlier local write overrides all nominal pre-write outcomes.
    # These synthetic contradictions are outside the immutable 92-case oracle.
    $contradictoryPrewrite=@(
        @{Domain='Receipt';Condition='Missing';RequestedOperation='INSPECT';SignatureValidated=$false;RootPresent=$false}
        @{Domain='Bootstrap';Condition='Unprovisioned';RequestedOperation='INSPECT';SignatureValidated=$false;RootPresent=$true}
        @{Domain='Cutover';Condition='LegacyInstallRequested';RequestedOperation='INSPECT';SignatureValidated=$false;RootPresent=$true}
        @{Domain='Authority';Condition='DuplicateApprovalOtherTx';RequestedOperation='INSPECT';SignatureValidated=$false;RootPresent=$true}
        @{Domain='Recovery';Condition='AuthenticRollbackReceipt';RequestedOperation='ROLLBACK';SignatureValidated=$true;RootPresent=$true}
    )
    foreach($case in $contradictoryPrewrite){
        $possibleWrite=[pscustomobject]@{
            Domain=$case.Domain
            Condition=$case.Condition
            LocalWritePossible=$true
            RootPresent=[bool]$case.RootPresent
            AuthorityReserved=$false
            RequestedOperation=$case.RequestedOperation
            SignatureValidated=[bool]$case.SignatureValidated
        }
        $decision=Resolve-F2V4ConformanceObservation -Evidence $possibleWrite
        Assert-F2V4Conformance ($decision.InspectionState -ceq 'PRECONDITION_UNMET' -and
            $decision.Classification -ceq 'HOLD_PRESERVE' -and
            (Test-F2V4NoPower -Result $decision)) ("possible local write overrides prewrite verdict: "+$case.Domain+"/"+$case.Condition)
    }

    # Pure transition graph checks: modeled edge approval never imply protected
    # filesystem or manifest activation authority.
    $normalPhases=@('REMOTE_RESERVED_NO_LOCAL','GENESIS','STAGE_INTENT','STAGE_CREATED',
        'PACKAGE_VERIFIED','PUBLISH_INTENT','PACKAGE_PUBLISHED',
        'BACKUP_INTENT','BACKUP_DURABLE','SWITCH_INTENT',
        'ACTIVE_MANIFEST_SWITCHED','POSTCHECK_VERIFIED','COMMIT_DURABLE')
    for($i=0;$i -lt $normalPhases.Count-1;$i++){
        $transition=Test-F2V4ConformanceTransition -FromState $normalPhases[$i] -ToState $normalPhases[$i+1] -ModelPath Normal -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true
        Assert-F2V4Conformance ($transition.AllowedInModel -and $transition.Reason -ceq 'PURE_ADJACENT_EDGE_MODELED' -and
            $transition.Classification -ceq 'OBSERVE_ONLY' -and (Test-F2V4NoPower $transition)) ("modeled normal edge "+$normalPhases[$i]+" -> "+$normalPhases[$i+1])
    }
    $skip=Test-F2V4ConformanceTransition -FromState GENESIS -ToState PACKAGE_PUBLISHED -ModelPath Normal -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true
    Assert-F2V4Conformance (-not $skip.AllowedInModel -and $skip.Classification -ceq 'HOLD_PRESERVE') 'journal phase skip prohibited'
    $back=Test-F2V4ConformanceTransition -FromState BACKUP_DURABLE -ToState STAGE_INTENT -ModelPath Normal -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true
    Assert-F2V4Conformance (-not $back.AllowedInModel) 'journal phase regression prohibited'
    $same=Test-F2V4ConformanceTransition -FromState GENESIS -ToState GENESIS -ModelPath Normal -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true
    Assert-F2V4Conformance (-not $same.AllowedInModel) 'journal phase duplicate prohibited'
    $noApproval=Test-F2V4ConformanceTransition -FromState GENESIS -ToState STAGE_INTENT -ModelPath Normal -SyntheticPrerequisitesVerified $true
    Assert-F2V4Conformance (-not $noApproval.AllowedInModel -and (Test-F2V4NoPower $noApproval)) 'no synthetic operation permission: hold'
    $noPrereq=Test-F2V4ConformanceTransition -FromState GENESIS -ToState STAGE_INTENT -ModelPath Normal -SyntheticOperationApproval $true
    Assert-F2V4Conformance (-not $noPrereq.AllowedInModel) 'missing synthetic preconditions: hold'
    $finalizePhases=@('SWITCH_INTENT','RECOVERY_POST_SWITCH_VERIFIED','POSTCHECK_VERIFIED','COMMIT_DURABLE')
    for($i=0;$i -lt $finalizePhases.Count-1;$i++){
        $transition=Test-F2V4ConformanceTransition -FromState $finalizePhases[$i] -ToState $finalizePhases[$i+1] -ModelPath FinalizeEvidence -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true -SyntheticTargetAndBackupsExact $true
        Assert-F2V4Conformance ($transition.AllowedInModel -and $transition.Reason -ceq 'PURE_FINALIZATION_EVIDENCE_EDGE_MODELED' -and
            (Test-F2V4NoPower $transition)) ("modeled proof-only finalization "+$finalizePhases[$i]+" -> "+$finalizePhases[$i+1])
    }
    $noBackups=Test-F2V4ConformanceTransition -FromState SWITCH_INTENT -ToState RECOVERY_POST_SWITCH_VERIFIED -ModelPath FinalizeEvidence -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true
    Assert-F2V4Conformance (-not $noBackups.AllowedInModel) 'post-switch proof missing dual backups rejected'
    $repeatSwitch=Test-F2V4ConformanceTransition -FromState SWITCH_INTENT -ToState ACTIVE_MANIFEST_SWITCHED -ModelPath FinalizeEvidence -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true -SyntheticTargetAndBackupsExact $true
    Assert-F2V4Conformance (-not $repeatSwitch.AllowedInModel) 'finalization cannot perform second active-manifest switch'
    $rollbackEdge=Test-F2V4ConformanceTransition -FromState COMMIT_DURABLE -ToState BACKUP_DURABLE -ModelPath Rollback -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true -SyntheticTargetAndBackupsExact $true
    Assert-F2V4Conformance (-not $rollbackEdge.AllowedInModel -and $rollbackEdge.Classification -ceq 'REJECT_BEFORE_WRITE' -and
        (Test-F2V4NoPower $rollbackEdge)) 'signed-looking rollback cannot create modeled write edge'
    $unknownEdge=Test-F2V4ConformanceTransition -FromState UNTRUSTED_STATE -ToState GENESIS -ModelPath Normal -SyntheticPrerequisitesVerified $true -SyntheticOperationApproval $true
    Assert-F2V4Conformance (-not $unknownEdge.AllowedInModel) 'unknown phase fail closed'

    # Fake authority: in-memory generation, replay and restored-head simulation only.

    # Only the explicitly modeled synthetic predecessor is accepted by this
    # in-memory test double. All other schemas must leave its ledger unchanged.
    $schemaProbe=New-F2V4FakeAuthority
    $schemaTx=('c'*32)
    $schemaDigest=('3'*64)
    foreach($unsupportedSchema in @('v2','v3','v5','unknown','Synthetic','')){
        $schemaDenied=Invoke-F2V4FakeReservation -Authority $schemaProbe -ApprovalId 'schema-probe' -TxId $schemaTx -EnvironmentId 'synthetic-host' -TargetDigest $schemaDigest -Operation INSTALL -ExpectedGeneration 0 -PredecessorSchema $unsupportedSchema
        Assert-F2V4Conformance ($schemaDenied.Status -ceq 'UNSUPPORTED_PREDECESSOR' -and
            $schemaDenied.CanMutate -eq $false -and $schemaDenied.Durable -eq $false -and
            $schemaProbe.Generation -eq 0 -and $schemaProbe.Approvals.Count -eq 0 -and
            $schemaProbe.Transactions.Count -eq 0 -and $schemaProbe.Checkpoints.Count -eq 0) ("unsupported predecessor schema rejected without reservation: ["+$unsupportedSchema+"]")
    }

    $authority=New-F2V4FakeAuthority
    $tx='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $anotherTx='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    $digest=('1'*64)
    $differentDigest=('2'*64)
    $reserved=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-1' -TxId $tx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation INSTALL -ExpectedGeneration 0
    Assert-F2V4Conformance ($reserved.Status -ceq 'RESERVED_SIMULATED' -and $authority.Generation -eq 1 -and -not $reserved.Durable -and -not $reserved.CanMutate) 'fake approval reserves without durable/real authority'
    $repeat=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-1' -TxId $tx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation INSTALL -ExpectedGeneration 1
    Assert-F2V4Conformance ($repeat.Status -ceq 'REPLAY_IDENTICAL' -and $authority.Generation -eq 1) 'identical approval replay is observation only'
    $otherTx=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-1' -TxId $anotherTx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation INSTALL -ExpectedGeneration 1
    Assert-F2V4Conformance ($otherTx.Status -ceq 'REPLAY_CONFLICT') 'same ApprovalId new TxId rejected'
    $newApprovalOldTx=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-2' -TxId $tx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation INSTALL -ExpectedGeneration 1
    Assert-F2V4Conformance ($newApprovalOldTx.Status -ceq 'REPLAY_CONFLICT') 'new ApprovalId same install TxId rejected'
    $otherEnv=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-1' -TxId $tx -EnvironmentId 'other-host' -TargetDigest $digest -Operation INSTALL -ExpectedGeneration 1
    Assert-F2V4Conformance ($otherEnv.Status -ceq 'REPLAY_CONFLICT') 'approval replay across environment rejected'
    $stale=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-3' -TxId $anotherTx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation INSTALL -ExpectedGeneration 0
    Assert-F2V4Conformance ($stale.Status -ceq 'STALE_GENERATION') 'authority generation compare rejects stale request'
    $otherDigest=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-3' -TxId $tx -EnvironmentId 'synthetic-host' -TargetDigest $differentDigest -Operation RECOVER_FORWARD -ExpectedGeneration 1
    Assert-F2V4Conformance ($otherDigest.Status -ceq 'REPLAY_CONFLICT') 'same TxId different target digest rejected'
    $rollbackReservation=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'approve-3' -TxId $tx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation ROLLBACK -ExpectedGeneration 1
    Assert-F2V4Conformance ($rollbackReservation.Status -ceq 'UNSUPPORTED_OPERATION') 'signed-looking rollback rejected before fake reservation'
    $finalize=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'finalize-1' -TxId $tx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation FINALIZE_POST_SWITCH -ExpectedGeneration 1
    Assert-F2V4Conformance ($finalize.Status -ceq 'RESERVED_SIMULATED' -and $authority.Generation -eq 2 -and -not $finalize.CanMutate) 'separate fake finalization operation bound to original TxId'
    $repeatFinalizer=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'finalize-1' -TxId $tx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation FINALIZE_POST_SWITCH -ExpectedGeneration 2
    Assert-F2V4Conformance ($repeatFinalizer.Status -ceq 'REPLAY_IDENTICAL') 'fake finalizer approval cannot be consumed twice'
    $orphan=Invoke-F2V4FakeReservation -Authority $authority -ApprovalId 'orphan-finalize' -TxId $anotherTx -EnvironmentId 'synthetic-host' -TargetDigest $digest -Operation FINALIZE_POST_SWITCH -ExpectedGeneration 2
    Assert-F2V4Conformance ($orphan.Status -ceq 'MISSING_INSTALL_REJECTED') 'cannot finalize transaction without initial simulated install'
    $h1='1'*64;$h2='2'*64
    $c1=Set-F2V4FakeCheckpoint -Authority $authority -TxId $tx -NextSequence 1 -HeadSha256 $h1
    $c2=Set-F2V4FakeCheckpoint -Authority $authority -TxId $tx -NextSequence 2 -HeadSha256 $h2
    Assert-F2V4Conformance ($c1.Status -ceq 'CHECKPOINT_SIMULATED' -and $c2.Status -ceq 'CHECKPOINT_SIMULATED') 'fake journal checkpoint monotonic'
    $oldHead=Compare-F2V4FakeCheckpoint -Authority $authority -TxId $tx -LocalSequence 1 -LocalHeadSha256 $h1
    $changedHead=Compare-F2V4FakeCheckpoint -Authority $authority -TxId $tx -LocalSequence 2 -LocalHeadSha256 $h1
    $goodHead=Compare-F2V4FakeCheckpoint -Authority $authority -TxId $tx -LocalSequence 2 -LocalHeadSha256 $h2
    Assert-F2V4Conformance ($oldHead.Status -ceq 'OLDER_PREFIX') 'restored old journal prefix detected by fake external checkpoint'
    Assert-F2V4Conformance ($changedHead.Status -ceq 'HEAD_MISMATCH') 'same-sequence changed head detected'
    Assert-F2V4Conformance ($goodHead.Status -ceq 'MATCH' -and -not $goodHead.Durable) 'fake checkpoint match is not durable external proof'
    $repeatCheckpoint=Set-F2V4FakeCheckpoint -Authority $authority -TxId $tx -NextSequence 2 -HeadSha256 $h2
    Assert-F2V4Conformance ($repeatCheckpoint.Status -ceq 'NONMONOTONIC_REJECTED') 'duplicate checkpoint cannot advance'
    Assert-F2V4Conformance ($authority.Generation -eq 2 -and $authority.Kind -ceq 'IN_MEMORY_TEST_DOUBLE_NOT_DURABLE') 'all authority state is in-memory test data'
} catch {
    $script:AssertFailed++
    [Console]::Error.WriteLine("F2_V4_CONFORMANCE_FATAL: "+$_.Exception.Message)
} finally {
    Remove-Module -Name F2TransactionConformance.V4.SourceOnly -ErrorAction SilentlyContinue
}
Write-Output ("F2_V4_PURE_CONFORMANCE: {0} passed, {1} failed; source-only, no protected writes" -f $script:AssertPassed,$script:AssertFailed)
if($script:AssertFailed -ne 0){exit 1}
exit 0

# F2 G1 — fixed-scope owner-operated read-only host inspection candidate.
# Do NOT execute against host without fresh owner grant for reviewed exact SHA.
# No caller-defined paths, UAC elevation, ACL mutation or guest/VM access.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\lt1\F2G1LT1.Synthetic.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\lt3\F2G1LT3.Readiness.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '..\lt2\F2G1LT2.Fixture.psm1') -ErrorAction Stop

$script:ProtectedHostAccessEnabled=$false
$script:Scope=Get-F2G1LT1Scope

function Test-F2G1LT4ActualToken {
    # Reuse the LT-2's real GetTokenInformation native primitive; no CI fake token.
    try {
        if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {return $false}
        $imp=[Security.Principal.WindowsIdentity]::GetCurrent($true)
        if($null -ne $imp){$imp.Dispose();return $false}
        $id=[Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $principal=New-Object Security.Principal.WindowsPrincipal($id)
            $elev=[F2G1LT2TokenNative]::IntValue($id.Token,20)
            $type=[F2G1LT2TokenNative]::IntValue($id.Token,18)
            $rid=[F2G1LT2TokenNative]::IntegrityRid($id.Token)
            return (-not ($id.IsSystem -or $id.IsAnonymous -or $id.IsGuest) -and
                -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -and
                $elev -eq 0 -and $type -in @(1,3) -and $rid -ge 8192 -and $rid -lt 12288)
        } finally {$id.Dispose()}
    } catch {return $false}
}

function Get-F2G1LT4HostReadiness {
    # Status function never calls host I/O. Owner-operated function is separate.
    return [pscustomobject]@{
        Schema='f2-g1-lt4-host-gate-v1';Verdict='BLOCKED_WITH_EVIDENCE'
        Code='HOST_ADAPTER_EXECUTION_NOT_AUTHORIZED'
        HostAdapterImplemented=$true;HostAccessEnabled=$script:ProtectedHostAccessEnabled
        ProtectedReads=0;HostAttestation='NOT_PERFORMED'
    }
}

function Assert-F2G1LT4FixtureRoot([string]$Root) {
    # A self-hosted runner is NOT supported for fixture invocation.
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       $env:GITHUB_REPOSITORY -cne 'publiomcko-cloud/procedural-sandbox-simulation' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or [string]::IsNullOrWhiteSpace($Root)){
        throw 'FIXTURE_ONLY_CI_REQUIRED'
    }
    $temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($full) -cne $temp -or
       [IO.Path]::GetFileName($full) -cnotmatch '^F2G1-LT4-[0-9a-fA-F-]{36}$'){
        throw 'FIXTURE_ROOT_REJECTED'
    }
    foreach($candidate in @($temp,$full,(Join-Path $full 'C'))){
        $item=Get-Item -LiteralPath $candidate -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'FIXTURE_REPARSE_REJECTED'
        }
    }
    return $full
}

function New-F2G1LT4PathMap([string]$Mode,[string]$Root) {
    # Host mapping is transiently enabled only inside validated owner operation.
    # This is procedural local-host control, NOT protection from host malware.
    if($Mode -ceq 'Host'){
        if(-not $script:ProtectedHostAccessEnabled){throw 'HOST_MAPPING_DISABLED'}
        if(-not (Test-F2G1LT4ActualToken)){throw 'HOST_TOKEN_REJECTED'}
        return [pscustomobject]@{Mode='Host';Root=$null}
    }
    if($Mode -cne 'Fixture'){throw 'UNKNOWN_ADAPTER_MODE'}
    $verified=Assert-F2G1LT4FixtureRoot $Root
    return [pscustomobject]@{Mode='Fixture';Root=$verified}
}

function Get-F2G1LT4PhysicalPath($Map,[string]$Label,[string]$Kind) {
    # Exact fixed allowlist checked before any path lookup.
    $dirs=@($script:Scope.Directories)
    $files=@($script:Scope.Files|ForEach-Object {$_.Path})
    if(($Kind -ceq 'Directory' -and $dirs -cnotcontains $Label) -or
       ($Kind -ceq 'File' -and $files -cnotcontains $Label) -or
       $Kind -cnotin @('File','Directory')){throw 'LABEL_OUTSIDE_FROZEN_SCOPE'}
    if($Map.Mode -ceq 'Host'){
        # All labels are fixed by the allowlist above. No caller path accepted.
        if(-not $script:ProtectedHostAccessEnabled){throw 'HOST_MAPPING_DISABLED'}
        if(-not (Test-F2G1LT4ActualToken)){throw 'HOST_TOKEN_REJECTED'}
        return $Label
    }
    if($Map.Mode -cne 'Fixture'){throw 'UNKNOWN_ADAPTER_MODE'}
    if($Label -ceq 'C:\') {return (Join-Path $Map.Root 'C')}
    if(-not $Label.StartsWith('C:\',[StringComparison]::Ordinal)){throw 'LABEL_OUTSIDE_FROZEN_SCOPE'}
    return (Join-Path (Join-Path $Map.Root 'C') $Label.Substring(3))
}

function Assert-F2G1LT4Parents($Map,[string]$Label) {
    # Read-only reparse check of each fixed intermediate parent. No hostile
    # concurrent writer is assumed under the approved local-trust ADR.
    $prefixes=@('C:\','C:\Program Files','C:\ProgramData','C:\Program Files\F2-G1-Icacls',
        'C:\Program Files\F2-G1-Icacls\scripts',
        'C:\Program Files\F2-G1-Icacls\scripts\f2-acl',
        'C:\ProgramData\F2-G1-Icacls',
        'C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df')
    foreach($parent in $prefixes){
        if($Label -cne $parent -and -not $Label.StartsWith($parent.TrimEnd('\')+'\',[StringComparison]::Ordinal)){continue}
        $path=Get-F2G1LT4PhysicalPath $Map $parent 'Directory'
        $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'PARENT_REPARSE_OR_TYPE'
        }
    }
}

function Get-F2G1LT4PhysicalMeta($Map,[string]$Label) {
    $kind=if($script:Scope.Directories -ccontains $Label){'Directory'}else{'File'}
    $path=Get-F2G1LT4PhysicalPath $Map $Label $kind
    Assert-F2G1LT4Parents $Map $Label
    $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if((($kind -ceq 'Directory') -ne [bool]$item.PSIsContainer) -or
       ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'OBJECT_TYPE_OR_REPARSE'}
    $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace([string]$acl.Owner) -or
       [string]::IsNullOrWhiteSpace([string]$acl.Sddl)){throw 'ACL_NOT_READABLE'}
    return [pscustomobject]@{
        Path=$Label;Exists=$true;Kind=$kind;Reparse=$false
        Length=$(if($kind -ceq 'File'){[long]$item.Length}else{[long]0})
        Sddl=[string]$acl.Sddl
        Created=$item.CreationTimeUtc.Ticks
        Modified=$item.LastWriteTimeUtc.Ticks
    }
}

function Get-F2G1LT4PhysicalBytes($Map,[string]$Label,[int]$Maximum) {
    $path=Get-F2G1LT4PhysicalPath $Map $Label 'File'
    $rule=@($script:Scope.Files|Where-Object {$_.Path -ceq $Label})
    if($rule.Count -ne 1 -or $Maximum -le 0){throw 'FILE_LIMIT_INVALID'}
    $bounded=[math]::Min([long]$Maximum,[long]$rule[0].Max)
    $before=Get-F2G1LT4PhysicalMeta $Map $Label
    if($before.Length -le 0 -or $before.Length -gt $bounded){throw 'FILE_SIZE_REJECTED'}
    $stream=New-Object IO.FileStream($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -ne $before.Length){throw 'FILE_CHANGED'}
        $bytes=New-Object byte[] ([int]$stream.Length)
        $offset=0
        while($offset -lt $bytes.Length){
            $got=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if($got -le 0){throw 'INCOMPLETE_READ'}
            $offset+=$got
        }
        if($stream.ReadByte() -ne -1){throw 'FILE_CHANGED'}
        $after=Get-F2G1LT4PhysicalMeta $Map $Label
        if($before.Length -ne $after.Length -or $before.Created -ne $after.Created -or
           $before.Modified -ne $after.Modified -or $before.Sddl -cne $after.Sddl){
            throw 'FILE_CHANGED'
        }
        return ,$bytes
    } finally {$stream.Dispose()}
}

function Get-F2G1LT4PhysicalChildren($Map,[string]$Label) {
    $policy=@($script:Scope.Inventories|Where-Object {$_.Path -ceq $Label})
    if($policy.Count -ne 1){throw 'INVENTORY_OUTSIDE_FROZEN_SCOPE'}
    $meta=Get-F2G1LT4PhysicalMeta $Map $Label
    if($meta.Kind -cne 'Directory'){throw 'INVENTORY_WRONG_TYPE'}
    $path=Get-F2G1LT4PhysicalPath $Map $Label 'Directory'
    $children=@(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop)
    $expected=@($policy[0].Names)
    if($children.Count -ne $expected.Count){throw 'INVENTORY_COUNT_MISMATCH'}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $rows=@()
    foreach($item in $children){
        $name=[string]$item.Name
        if(-not $seen.Add($name) -or $expected -cnotcontains $name -or
           $script:Scope.TransactionNames -ccontains $name -or
           ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'INVENTORY_ENTRY_INVALID'
        }
        $rows+=[pscustomobject]@{Name=$name;Kind=$(if($item.PSIsContainer){'Directory'}else{'File'});Reparse=$false}
    }
    # Exactly 5 inventories; each excludes extra/missing children.
    foreach($wanted in $expected){if(-not $seen.Contains($wanted)){throw 'INVENTORY_ENTRY_INVALID'}}
    return $rows
}


# Only the first R2 STOP category and a finite, R2-defined code may leave the
# private evaluator. Never forward raw Gate.Name, Gate.Data, SDDL or object paths.
function ConvertTo-F2G1LT4SanitizedR2Stop {
    param([object]$R2Report)
    $default=[pscustomobject]@{Stage='R2_STOP_NOT_REPORTED';Code='R2_STOP_NOT_REPORTED'}
    if($null -eq $R2Report){return $default}
    $stages=@('ExecutionContext','ImmediateChildInventory','TransactionArtifacts',
        'ActiveManifest','BaselineMailbox','BaselineMailboxInventory','BaselineHashes',
        'BaselineJson','BaselineRecords','BaselineIntegrity','BaselineStreams',
        'BaselineFrame','BaselineCoordinator','BaselineEvidence')
    $allowedCodes=@(
        'ADMINISTRATOR_TOKEN_OR_GROUP_MEMBERSHIP',
        'CAPTURE_ID_OR_ELEVEN_RECORD_COMPLETENESS_INVALID',
        'CHILD_TYPE_OR_REPARSE_INVALID',
        'COORDINATOR_OR_OUTPUT_COMPLETENESS_INVALID',
        'EXACT_ELEVEN_PATH_SET_INVALID',
        'FOUR_ACE_PROFILE_MISMATCH',
        'FRAME_HEADER_INVALID',
        'FRAME_LENGTH_INVALID',
        'FRAME_PAYLOAD_OR_DIGEST_INVALID',
        'HISTORICAL_HASH_MISMATCH',
        'INCOMPLETE_STREAM_OUTPUT',
        'INVENTORY_FAILED',
        'MALFORMED_OR_INCOMPLETE_OUTPUT',
        'MALFORMED_STREAM_OUTPUT',
        'MANIFEST_BASELINE_OR_SOURCE_PIN_MISMATCH',
        'MANIFEST_FILE_SET_INVALID',
        'MANIFEST_IDENTITY_MISMATCH',
        'MANIFEST_JSON_INVALID',
        'MANIFEST_SHA256_MISMATCH',
        'MISSING_OR_REPARSE',
        'MISSING_TYPE_OR_REPARSE',
        'MISSING_TYPE_REPARSE_OR_READ_RACE',
        'OBJECT_TYPE_MISMATCH',
        'OWNER_OR_DACL_POLICY_MISMATCH',
        'PACKAGE_HASH_MISMATCH',
        'PATH_OR_ACL_UNREADABLE',
        'PAYLOAD_OR_PROVENANCE_BINDING_INVALID',
        'READ_FAILED',
        'REPARSE_CHILD',
        'REQUIRED_CHILD_MISSING',
        'SEVEN_FILE_SET_INVALID',
        'STATUS_JSON_INVALID',
        'STREAM_HASH_MISMATCH',
        'TRANSACTION_ARTIFACT_PRESENT',
        'TYPE_REPARSE_OWNER_DACL_OR_READ_RACE',
        'UNEXPECTED_CHILD',
        'WORKER_DIAGNOSTIC_HASH_MISMATCH',
        'WORKER_DIAGNOSTIC_MANIFEST_INVALID'
    )
    foreach($gate in $R2Report.Gates){
        if($null -eq $gate -or [string]$gate.Result -cne 'STOP'){continue}
        $name=[string]$gate.Name
        $stage='R2_UNCLASSIFIED_STAGE'
        if($name.StartsWith('Path:',[StringComparison]::Ordinal)){$stage='Path'}
        elseif($name.StartsWith('PackageFile:',[StringComparison]::Ordinal)){$stage='PackageFile'}
        elseif($name.StartsWith('BaselineFile:',[StringComparison]::Ordinal)){$stage='BaselineFile'}
        elseif($stages -ccontains $name){$stage=$name}
        $rawCode=if($null -eq $gate.Data){''}else{[string]$gate.Data.Code}
        $code=if($allowedCodes -ccontains $rawCode){$rawCode}else{'R2_UNCLASSIFIED_STOP'}
        return [pscustomobject]@{Stage=$stage;Code=$code}
    }
    return $default
}

# A closure is a dynamic module. Resolve the original LT4 private commands
# inside LT4 before capturing them, then invoke those bound FunctionInfo values
# rather than looking up private function names inside the closure or R2 module.
function New-F2G1LT4R2Callbacks($Map) {
    $getMetaCommand=Get-Command Get-F2G1LT4PhysicalMeta -CommandType Function -ErrorAction Stop
    $readBytesCommand=Get-Command Get-F2G1LT4PhysicalBytes -CommandType Function -ErrorAction Stop
    $listChildrenCommand=Get-Command Get-F2G1LT4PhysicalChildren -CommandType Function -ErrorAction Stop
    $getPath={param([string]$Label) & $getMetaCommand $Map $Label}.GetNewClosure()
    $readBytes={param([string]$Label,[int]$Max) & $readBytesCommand $Map $Label $Max}.GetNewClosure()
    $listChildren={param([string]$Label) @(& $listChildrenCommand $Map $Label)}.GetNewClosure()
    return [pscustomobject]@{GetPath=$getPath;ReadBytes=$readBytes;ListChildren=$listChildren}
}

function Invoke-F2G1LT4R2HistoricalPolicy($Map) {
    # Reuse unchanged R2 semantics with physically read bytes/ACLs.
    # Its public legacy -Live entrypoint stays disabled.
    $r2=Import-Module (Join-Path $PSScriptRoot '..\F2G1CPostfailureAttestation.psm1') -PassThru -ErrorAction Stop
    $refs=Get-F2G1LT3ReferenceContract
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        $admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $groupPresent=@($identity.Groups|Where-Object {$_.Value -ceq 'S-1-5-32-544'}).Count -gt 0
        $identityInfo=[pscustomobject]@{
            IsAdministrator=[bool]$admin
            AdministratorGroupPresent=[bool]$groupPresent
            UserSid=[string]$identity.User.Value
        }
    } finally {$identity.Dispose()}
    # GitHub-hosted Windows runners normally hold an administrator token.
    # The synthetic fixture must exercise R2's *path/ACL policy*, not stop at
    # that CI token. Host mode always keeps the actual measured identity.
    if($Map.Mode -ceq 'Fixture'){
        $identityInfo=[pscustomobject]@{
            IsAdministrator=$false;AdministratorGroupPresent=$false
            UserSid=$identityInfo.UserSid
        }
    }
    $callbacks=New-F2G1LT4R2Callbacks $Map
    $fixtureExpected=[pscustomobject]@{
        ManifestSha256=$refs.ManifestSha256
        ReviewedCommitSha=$refs.ReviewedSourceSha
        BaselineMailboxId=$refs.MailboxId
        BaselinePayloadCaptureId=$refs.CaptureId
        RecordPaths=@() # Fixture cannot claim historical G: observations.
    }
    $r2Mode=if($Map.Mode -ceq 'Host'){'Live'}else{'Fixture'}
    $provider=@{
        Mode=$r2Mode;Fixture=[pscustomobject]@{Expected=$fixtureExpected}
        Identity=$identityInfo;GetPath=$callbacks.GetPath;ReadBytes=$callbacks.ReadBytes
        ListChildren=$callbacks.ListChildren
    }
    # Execute in R2 module scope to reuse private historical ACL/evidence policy
    # without changing or making R2's live entrypoint reachable.
    $result=@($r2.Invoke([scriptblock]::Create('param($Provider) Invoke-F2G1Core -Provider $Provider'),@($provider)))
    if($result.Count -ne 1){throw 'R2_POLICY_BRIDGE_INVALID'}
    $stop=ConvertTo-F2G1LT4SanitizedR2Stop -R2Report $result[0]
    return [pscustomobject]@{
        Executed=$true;FixtureVerdict=[string]$result[0].Verdict
        StopStage=$stop.Stage;StopCode=$stop.Code
    }
}

function Invoke-F2G1LT4Fixture {
    param([string]$FixtureRoot)
    $out=[ordered]@{
        Schema='f2-g1-lt4-physical-adapter-v1';Mode='DISPOSABLE_WINDOWS_CI_FIXTURE_ONLY'
        Verdict='BLOCKED_WITH_EVIDENCE';Code='FIXTURE_OBSERVATION_INCOMPLETE'
        PhysicalObjects=0;PhysicalFiles=0;PhysicalInventories=0
        ProtectedReads=0;HostAttestation='NOT_PERFORMED'
        HistoricalV2='NOT_ATTESTED_FIXTURE_ONLY';LinkAndAds='LINK_ADS_NOT_ATTESTED'
        R2PolicyEvaluated=$false;R2FixtureVerdict='NOT_RUN'
        R2StopStage='NOT_EVALUATED';R2StopCode='NOT_EVALUATED'
    }
    try {
        $map=New-F2G1LT4PathMap 'Fixture' $FixtureRoot
        # This adapter reads REAL NTFS fixture bytes/ACLs, not mock dictionaries.
        foreach($label in @($script:Scope.Directories)){[void](Get-F2G1LT4PhysicalMeta $map $label);$out.PhysicalObjects++}
        $contents=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        foreach($file in @($script:Scope.Files)){
            $bytes=Get-F2G1LT4PhysicalBytes $map $file.Path ([int]$file.Max)
            $contents.Add($file.Path,[byte[]]$bytes)
            $out.PhysicalObjects++;$out.PhysicalFiles++
        }
        foreach($inv in @($script:Scope.Inventories)){[void]@(Get-F2G1LT4PhysicalChildren $map $inv.Path);$out.PhysicalInventories++}
        $r2policy=Invoke-F2G1LT4R2HistoricalPolicy $map
        $out.R2PolicyEvaluated=$r2policy.Executed
        $out.R2FixtureVerdict=$r2policy.FixtureVerdict
        $out.R2StopStage=$r2policy.StopStage
        $out.R2StopCode=$r2policy.StopCode
        $reference=Get-F2G1LT3ReferenceContract
        $package=@()
        foreach($pin in @($reference.PackageMembers)){
            $package+=[pscustomobject]@{Path=$pin.Path;Bytes=$contents[$pin.Path]}
        }
        $capture=[pscustomobject]@{
            PackageMembers=$package
            ManifestBytes=$contents['C:\ProgramData\F2-G1-Icacls\approved-release.json']
            PayloadBytes=$contents['C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\acl-baseline.json']
            IntegrityBytes=$contents['C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\integrity.json']
        }
        $check=Test-F2G1LT3CapturedBytes $capture
        if($check.Code -cne 'BYTES_MATCH_HISTORICAL_PINS_ORIGIN_UNVERIFIED'){
            $out.Code='HISTORICAL_PIN_MISMATCH_IN_DISPOSABLE_FIXTURE'
        } else {
            # Still not an operational PASS: R2 full ACL/evidence policy and host
            # identity/grant are not yet run on protected host observations.
            $out.Code='FIXTURE_BYTES_MATCH_PINS_NOT_HOST_ATTESTATION'
        }
    } catch {
        $allowed=@('FIXTURE_ONLY_CI_REQUIRED','FIXTURE_ROOT_REJECTED','FIXTURE_REPARSE_REJECTED',
            'HOST_MAPPING_DISABLED','LABEL_OUTSIDE_FROZEN_SCOPE','PARENT_REPARSE_OR_TYPE',
            'OBJECT_TYPE_OR_REPARSE','ACL_NOT_READABLE','FILE_LIMIT_INVALID','FILE_SIZE_REJECTED',
            'FILE_CHANGED','INCOMPLETE_READ','INVENTORY_OUTSIDE_FROZEN_SCOPE',
            'INVENTORY_WRONG_TYPE','INVENTORY_COUNT_MISMATCH','INVENTORY_ENTRY_INVALID')
        $out.Code='FIXTURE_OBSERVATION_FAILED_CLOSED'
        foreach($code in $allowed){if($_.Exception.Message -ceq $code){$out.Code=$code;break}}
    }
    return [pscustomobject]$out
}


function Invoke-F2G1LT4OwnerHostReadOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedComputerName,
        [Parameter(Mandatory)][ValidatePattern('^S-1-[0-9-]+$')][string]$ExpectedUserSid,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ReviewedAdapterSha256
    )
    # The caller must first obtain a separate, fresh owner execution approval
    # naming exact reviewed SHA, account, machine, command and fixed C: scope.
    # These metadata checks prevent operator mistakes; they are NOT authentication.
    $report=[ordered]@{
        Schema='f2-g1-fixed-host-read-v1';Mode='OWNER_OPERATED_FIXED_C_READ_ONLY'
        Verdict='BLOCKED_WITH_EVIDENCE';Code='HOST_PREFLIGHT_FAILED'
        ProtectedAccessAttempted=$false;ObservedObjects=0;ObservedFiles=0;ObservedInventories=0
        HistoricalV2='NOT_ATTESTED';LinkAndAds='LINK_ADS_NOT_ATTESTED'
        GVolumeAccess=$false;WritesPerformed=$false;Elevated=$false
        R2StopStage='NOT_EVALUATED';R2StopCode='NOT_EVALUATED'
    }
    try {
        # No hosted CI or non-Windows environment can ever take a host-read path.
        if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
           $env:GITHUB_ACTIONS -ceq 'true'){throw 'HOST_RUN_CONTEXT_REJECTED'}
        if(-not [string]::Equals([Environment]::MachineName,$ExpectedComputerName,[StringComparison]::OrdinalIgnoreCase)){
            throw 'MACHINE_NOT_MATCHED'
        }
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            if([string]$identity.User.Value -cne $ExpectedUserSid){throw 'ACCOUNT_NOT_MATCHED'}
            # R2 still forbids Administrator-group membership even on a UAC filtered token.
            if(@($identity.Groups|Where-Object {$_.Value -ceq 'S-1-5-32-544'}).Count -ne 0){
                throw 'R2_ADMINISTRATORS_GROUP_REJECTED'
            }
        } finally {$identity.Dispose()}
        if(-not (Test-F2G1LT4ActualToken)){throw 'STANDARD_TOKEN_REQUIRED'}
        # Read only source bytes from this checkout, never a protected C: target.
        $self=Get-Module -Name F2G1LT4.ReadOnlyAdapter -ErrorAction Stop
        if($null -eq $self -or [string]::IsNullOrWhiteSpace([string]$self.Path)){throw 'SOURCE_IDENTITY_UNAVAILABLE'}
        $sourceHash=(Get-FileHash -LiteralPath $self.Path -Algorithm SHA256 -ErrorAction Stop).Hash
        if($sourceHash -cne $ReviewedAdapterSha256.ToUpperInvariant()){throw 'REVIEWED_SOURCE_HASH_MISMATCH'}
        if($script:ProtectedHostAccessEnabled){throw 'HOST_REENTRANCY_DENIED'}
        $script:ProtectedHostAccessEnabled=$true
        try {
            $map=New-F2G1LT4PathMap 'Host' ''
            $scope=$script:Scope
            $report.ProtectedAccessAttempted=$true
            foreach($label in @($scope.Directories)){
                [void](Get-F2G1LT4PhysicalMeta $map $label)
                $report.ObservedObjects++
            }
            $bytesByLabel=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
            foreach($file in @($scope.Files)){
                $bytes=Get-F2G1LT4PhysicalBytes $map $file.Path ([int]$file.Max)
                $bytesByLabel.Add($file.Path,[byte[]]$bytes)
                $report.ObservedFiles++
                $report.ObservedObjects++
            }
            foreach($inventory in @($scope.Inventories)){
                [void]@(Get-F2G1LT4PhysicalChildren $map $inventory.Path)
                $report.ObservedInventories++
            }
            # Check actual physically read package/manifest/payload/integrity bytes.
            $ref=Get-F2G1LT3ReferenceContract
            $members=@()
            foreach($pin in @($ref.PackageMembers)){
                $members+=[pscustomobject]@{Path=$pin.Path;Bytes=$bytesByLabel[$pin.Path]}
            }
            $mail='C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\'
            $check=Test-F2G1LT3CapturedBytes ([pscustomobject]@{
                PackageMembers=$members
                ManifestBytes=$bytesByLabel['C:\ProgramData\F2-G1-Icacls\approved-release.json']
                PayloadBytes=$bytesByLabel[$mail+'acl-baseline.json']
                IntegrityBytes=$bytesByLabel[$mail+'integrity.json']
            })
            if($check.Code -cne 'BYTES_MATCH_HISTORICAL_PINS_ORIGIN_UNVERIFIED'){
                throw 'HISTORICAL_HASHES_NOT_MATCHED'
            }
            # The unchanged R2 Live *semantic core*, not its disabled Live entrypoint.
            $evaluated=Invoke-F2G1LT4R2HistoricalPolicy $map
            $report.R2StopStage=[string]$evaluated.StopStage
            $report.R2StopCode=[string]$evaluated.StopCode
            if(-not $evaluated.Executed -or $evaluated.FixtureVerdict -cne 'PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION'){
                throw 'R2_HISTORICAL_POLICY_NOT_MATCHED'
            }
            $report.Verdict='PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION'
            $report.Code='HISTORICAL_V2_C_OBJECTS_MATCHED_READ_ONLY'
            $report.HistoricalV2='C_FIXED_OBJECTS_MATCHED_AT_OBSERVATION'
        } finally {
            $script:ProtectedHostAccessEnabled=$false
        }
    } catch {
        # Do not emit exception messages, paths, user SIDs, SDDL or historical bytes.
        $report.Code='HOST_OBSERVATION_BLOCKED'
        foreach($code in @('HOST_RUN_CONTEXT_REJECTED','MACHINE_NOT_MATCHED','ACCOUNT_NOT_MATCHED',
           'R2_ADMINISTRATORS_GROUP_REJECTED','STANDARD_TOKEN_REQUIRED','SOURCE_IDENTITY_UNAVAILABLE',
           'REVIEWED_SOURCE_HASH_MISMATCH','HOST_REENTRANCY_DENIED','HISTORICAL_HASHES_NOT_MATCHED',
           'R2_HISTORICAL_POLICY_NOT_MATCHED')){
            if($_.Exception.Message -ceq $code){$report.Code=$code;break}
        }
    }
    return [pscustomobject]$report
}

Export-ModuleMember -Function Get-F2G1LT4HostReadiness,Invoke-F2G1LT4Fixture,Test-F2G1LT4ActualToken,Invoke-F2G1LT4OwnerHostReadOnly

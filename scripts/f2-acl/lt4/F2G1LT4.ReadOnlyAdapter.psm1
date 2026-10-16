# F2 G1 LT-4 — reusable read-only filesystem provider; HOST mode hard disabled.
# No public host path parameter, no live entrypoint, no destructive code.
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
    # This is the ONLY exported host-specific function. It never calls I/O.
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
    # The physical adapter can use either mapping after a future separately
    # reviewed source change/owner grant. HOST is presently unreachable.
    if($Mode -ceq 'Host'){
        if(-not $script:ProtectedHostAccessEnabled){throw 'HOST_MAPPING_DISABLED'}
        if(-not (Test-F2G1LT4ActualToken)){throw 'HOST_TOKEN_REJECTED'}
        throw 'HOST_EXECUTION_GATE_NOT_IMPLEMENTED'
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
    if($Map.Mode -cne 'Fixture'){throw 'HOST_MAPPING_DISABLED'}
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


function Invoke-F2G1LT4R2PolicyOnFixture($Map) {
    # Reuse the accepted R2 policy with ACTUAL fixture bytes and ACL observations.
    # This is NOT R2's disabled -Live entrypoint and cannot produce a host verdict.
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
    $getPath={param([string]$Label) Get-F2G1LT4PhysicalMeta $Map $Label}.GetNewClosure()
    $readBytes={param([string]$Label,[int]$Max) Get-F2G1LT4PhysicalBytes $Map $Label $Max}.GetNewClosure()
    $listChildren={param([string]$Label) @(Get-F2G1LT4PhysicalChildren $Map $Label)}.GetNewClosure()
    $fixtureExpected=[pscustomobject]@{
        ManifestSha256=$refs.ManifestSha256
        ReviewedCommitSha=$refs.ReviewedSourceSha
        BaselineMailboxId=$refs.MailboxId
        BaselinePayloadCaptureId=$refs.CaptureId
        RecordPaths=@() # Fixture cannot claim historical G: observations.
    }
    $provider=@{
        Mode='Fixture';Fixture=[pscustomobject]@{Expected=$fixtureExpected}
        Identity=$identityInfo;GetPath=$getPath;ReadBytes=$readBytes
        ListChildren=$listChildren
    }
    # Execute in R2 module scope to reuse private historical ACL/evidence policy
    # without changing or making R2's live entrypoint reachable.
    $result=@($r2.Invoke([scriptblock]::Create('param($Provider) Invoke-F2G1Core -Provider $Provider'),@($provider)))
    if($result.Count -ne 1){throw 'R2_POLICY_BRIDGE_INVALID'}
    return [pscustomobject]@{Executed=$true;FixtureVerdict=[string]$result[0].Verdict}
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
        $r2policy=Invoke-F2G1LT4R2PolicyOnFixture $map
        $out.R2PolicyEvaluated=$r2policy.Executed
        $out.R2FixtureVerdict=$r2policy.FixtureVerdict
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

Export-ModuleMember -Function Get-F2G1LT4HostReadiness,Invoke-F2G1LT4Fixture,Test-F2G1LT4ActualToken

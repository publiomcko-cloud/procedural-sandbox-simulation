# F2 G1 LT-1: IN-MEMORY MOCK ONLY. No path opens, no host provider, no live route.
# R2 remains the separate historical V2 fixture evaluator; LT-1 validates the
# approved local-trust entrypoint contract and a complete 23-object mock scope.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-F2G1LT1Scope {
    $home='C:\Program Files\F2-G1-Icacls'
    $pkg=$home+'\scripts\f2-acl'
    $data='C:\ProgramData\F2-G1-Icacls'
    $mail='C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df'
    $dirNames=@('C:\','C:\Program Files','C:\ProgramData',$home,($home+'\scripts'),$pkg,$data,$mail)
    $packageNames=@('F2AclCapture.Protocol.psm1','F2AclIcacls.Corroboration.psm1','F2AclIcacls.Runtime.psm1','Invoke-F2IcaclsCapture.ps1','Invoke-F2IcaclsProtectedCoordinator.ps1','F2_ICACLS_SOURCE_PINS.json','Invoke-F2AclReadOnlyCapture.ps1')
    $mailNames=@('acl-baseline.frame','acl-baseline.json','coordinator-status.json','integrity.json','powershell-streams.json','worker-stderr.json','worker-stdout.json')
    $files=@()
    foreach($name in $packageNames) {$files+= [pscustomobject]@{Path=($pkg+'\'+$name);Max=16777216}}
    $files+= [pscustomobject]@{Path=($data+'\approved-release.json');Max=65536}
    foreach($name in $mailNames) {
        $max=if($name -ceq 'acl-baseline.frame'){262188}elseif($name -ceq 'acl-baseline.json'){1048576}else{65536}
        $files+= [pscustomobject]@{Path=($mail+'\'+$name);Max=$max}
    }
    $inventories=@(
        [pscustomobject]@{Path=$home;Names=@('scripts')},
        [pscustomobject]@{Path=($home+'\scripts');Names=@('f2-acl')},
        [pscustomobject]@{Path=$pkg;Names=@($packageNames)},
        [pscustomobject]@{Path=$data;Names=@('approved-release.json')},
        [pscustomobject]@{Path=$mail;Names=@($mailNames)}
    )
    return [pscustomobject]@{Directories=$dirNames;Files=$files;Inventories=$inventories;TransactionNames=@('release.lock','updates','backups','releases','journals','stages')}
}

function Get-F2G1LT1BodyHash([string]$Body) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes($Body)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Test-F2G1LT1MockToken([string]$Profile) {
    # Deliberately mock-only. A real Windows GetTokenInformation gate is LT-2
    # work requiring review and owner authorization; no real token is inferred.
    switch -CaseSensitive ($Profile) {
        'Standard' {return $true}
        'FilteredLimited' {return $true} # Simulated UAC limited token with admin SID deny-only, never elevated
        default {return $false}
    }
}

function New-F2G1LT1SyntheticFixture {
    param([ValidateSet('Standard','FilteredLimited','Elevated','FullAdministrator','System','HighIntegrity','Impersonated','Privileged','Unknown')][string]$MockTokenProfile='Standard')
    $scope=Get-F2G1LT1Scope
    $objects=@()
    foreach($dir in $scope.Directories) {
        $objects+= [pscustomobject]@{Path=$dir;Kind='Directory';Exists=$true;Reparse=$false;AclMatches=$true;Before='stable-mock-id';After='stable-mock-id';Body=''}
    }
    foreach($file in $scope.Files) {
        $objects+= [pscustomobject]@{Path=$file.Path;Kind='File';Exists=$true;Reparse=$false;AclMatches=$true;Before='stable-mock-id';After='stable-mock-id';Body=('LT1-SYNTHETIC-ONLY|'+$file.Path)}
    }
    $inventories=@()
    foreach($inventory in $scope.Inventories) {
        $inventories+= [pscustomobject]@{Path=$inventory.Path;Children=@($inventory.Names)}
    }
    return [pscustomobject]@{Schema='f2-g1-lt1-inert-fixture-v1';MockTokenProfile=$MockTokenProfile;Objects=$objects;Inventories=$inventories}
}

function Invoke-F2G1LT1Synthetic {
    param([Parameter(Mandatory)][object]$Fixture)
    $reason='INCOMPLETE_FIXTURE'
    $passed=$false
    $scope=Get-F2G1LT1Scope
    $all=@($scope.Directories)+@($scope.Files|ForEach-Object {$_.Path})
    $report=[ordered]@{
        Schema='f2-g1-lt1-source-only-v1';Mode='SYNTHETIC_FIXTURE_ONLY'
        Verdict='BLOCKED_WITH_EVIDENCE';Code='INCOMPLETE_FIXTURE'
        ObjectCount=0;DirectoryCount=0;FileCount=0;InventoryCount=0;ProtectedReads=0
        LinkAndAds='LINK_ADS_NOT_ATTESTED'
        HistoricalV2='NOT_ATTESTED_MOCK_BYTES_ONLY'
    }
    try {
        if($null -eq $Fixture -or $Fixture.Schema -cne 'f2-g1-lt1-inert-fixture-v1') {throw 'FIXTURE_SCHEMA_REJECTED'}
        if(-not (Test-F2G1LT1MockToken ([string]$Fixture.MockTokenProfile))) {throw 'MOCK_TOKEN_NOT_STANDARD'}
        $rows=@($Fixture.Objects)
        if($rows.Count -ne 23 -or $all.Count -ne 23 -or $scope.Files.Count -ne 15 -or $scope.Directories.Count -ne 8){throw 'OBJECT_COUNT_INVALID'}
        $found=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        foreach($row in $rows){
            $name=[string]$row.Path
            if($found.ContainsKey($name)){throw 'DUPLICATE_OBJECT'}
            $found.Add($name,$row)
        }
        foreach($dir in $scope.Directories){
            if(-not $found.ContainsKey($dir)) {throw 'REQUIRED_DIRECTORY_MISSING'}
            $row=$found[$dir]
            if($row.Kind -cne 'Directory' -or $row.Exists -ne $true -or $row.Reparse -ne $false -or $row.AclMatches -ne $true){throw 'DIRECTORY_TYPE_OR_ACL_INVALID'}
            if($row.Before -cne $row.After -or [string]::IsNullOrEmpty([string]$row.Before)){throw 'DIRECTORY_IDENTITY_DRIFT'}
        }
        foreach($file in $scope.Files){
            if(-not $found.ContainsKey($file.Path)){throw 'REQUIRED_FILE_MISSING'}
            $row=$found[$file.Path]
            if($row.Kind -cne 'File' -or $row.Exists -ne $true -or $row.Reparse -ne $false -or $row.AclMatches -ne $true){throw 'FILE_TYPE_OR_ACL_INVALID'}
            if($row.Before -cne $row.After -or [string]::IsNullOrEmpty([string]$row.Before)){throw 'FILE_IDENTITY_DRIFT'}
            $body=[string]$row.Body
            if($body.Length -gt [int]$file.Max -or $body.Length -eq 0){throw 'FILE_SIZE_INVALID'}
            # Test-specific fixed public bytes; NEVER substitute these digests for R2 historical pins.
            $expected='LT1-SYNTHETIC-ONLY|'+$file.Path
            if((Get-F2G1LT1BodyHash $body) -cne (Get-F2G1LT1BodyHash $expected)){throw 'MOCK_CONTENT_MISMATCH'}
        }
        $invs=@($Fixture.Inventories)
        if($invs.Count -ne 5){throw 'INVENTORY_COUNT_INVALID'}
        $observed=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        foreach($inv in $invs) {
            if($observed.ContainsKey([string]$inv.Path)){throw 'DUPLICATE_INVENTORY'}
            $observed.Add([string]$inv.Path,$inv)
        }
        foreach($inv in $scope.Inventories){
            if(-not $observed.ContainsKey($inv.Path)){throw 'INVENTORY_MISSING'}
            $actual=@($observed[$inv.Path].Children)
            $expect=@($inv.Names)
            if($actual.Count -ne $expect.Count){throw 'INVENTORY_CARDINALITY_INVALID'}
            $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach($name in $actual){
                if(-not $seen.Add([string]$name)){throw 'DUPLICATE_CHILD'}
                if($expect -cnotcontains [string]$name){throw 'UNEXPECTED_CHILD'}
                if($scope.TransactionNames -ccontains [string]$name){throw 'TRANSACTION_ARTIFACT_PRESENT'}
            }
        }
        $passed=$true
    } catch {
        # Sanitized finite error code only, no paths, SIDs, SDDL or mock contents.
        $codes=@('FIXTURE_SCHEMA_REJECTED','MOCK_TOKEN_NOT_STANDARD','OBJECT_COUNT_INVALID','DUPLICATE_OBJECT','REQUIRED_DIRECTORY_MISSING','DIRECTORY_TYPE_OR_ACL_INVALID','DIRECTORY_IDENTITY_DRIFT','REQUIRED_FILE_MISSING','FILE_TYPE_OR_ACL_INVALID','FILE_IDENTITY_DRIFT','FILE_SIZE_INVALID','MOCK_CONTENT_MISMATCH','INVENTORY_COUNT_INVALID','DUPLICATE_INVENTORY','INVENTORY_MISSING','INVENTORY_CARDINALITY_INVALID','DUPLICATE_CHILD','UNEXPECTED_CHILD','TRANSACTION_ARTIFACT_PRESENT')
        $reason='UNCLASSIFIED_BLOCKED'
        foreach($code in $codes){if($_.Exception.Message -ceq $code){$reason=$code;break}}
    }
    if($passed) {
        $report.Verdict='SYNTHETIC_FIXTURE_PASS';$report.Code='COMPLETE_MOCK_ONLY'
        $report.ObjectCount=23;$report.DirectoryCount=8;$report.FileCount=15;$report.InventoryCount=5
    } else {$report.Code=$reason}
    return [pscustomobject]$report
}

Export-ModuleMember -Function Get-F2G1LT1Scope,New-F2G1LT1SyntheticFixture,Invoke-F2G1LT1Synthetic,Test-F2G1LT1MockToken

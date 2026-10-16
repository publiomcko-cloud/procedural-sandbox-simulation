# F2 G1 LT-3 — source-only host readiness contract.
# No protected host provider, no live execution, no caller-chosen paths.
# A "match" here compares caller-supplied UNTRUSTED hash declarations
# to immutable R2 historical reference values. It NEVER verifies physical bytes.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\lt1\F2G1LT1.Synthetic.psm1') -ErrorAction Stop

$script:Pins=[ordered]@{
    'F2AclCapture.Protocol.psm1'='42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1'='a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1'='950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5'
    'Invoke-F2IcaclsCapture.ps1'='fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0'
    'Invoke-F2IcaclsProtectedCoordinator.ps1'='3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2'
    'F2_ICACLS_SOURCE_PINS.json'='bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7'
    'Invoke-F2AclReadOnlyCapture.ps1'='bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}
$script:ManifestSha='b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9'
$script:PayloadSha='1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
$script:IntegritySha='02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
$script:Mailbox='ecb6deeb424e40feb5354d18908986df'
$script:Capture='489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:ReviewedSource='5741ffe90a3abd02a08563e6431e8a0b9b63eeb1'

function Get-F2G1LT3ReferenceContract {
    $scope=Get-F2G1LT1Scope
    $root='C:\Program Files\F2-G1-Icacls\scripts\f2-acl\'
    $members=@()
    foreach($name in @($script:Pins.Keys)){
        $members+= [pscustomobject]@{Path=($root+$name);Sha256=$script:Pins[$name]}
    }
    return [pscustomobject]@{
        Schema='f2-g1-lt3-reference-contract-v1';Mode='HISTORICAL_REFERENCE_ONLY'
        ReadOnly=$true;HostAccessEnabled=$false;AuthorizationConfigured=$false
        DirectoryCount=8;FileCount=15;ObjectCount=23;InventoryCount=5
        DirectoryLabels=@($scope.Directories)
        FileLabels=@($scope.Files|ForEach-Object{$_.Path})
        InventoryLabels=@($scope.Inventories|ForEach-Object{$_.Path})
        PackageMembers=$members
        ManifestSha256=$script:ManifestSha
        PayloadSha256=$script:PayloadSha
        IntegritySha256=$script:IntegritySha
        MailboxId=$script:Mailbox;CaptureId=$script:Capture;ReviewedSourceSha=$script:ReviewedSource
        HistoricalPinsSource='R2-fixed-ancestor'
        GDrivePolicy='HISTORICAL_STRINGS_ONLY_NO_G_VOLUME_ACCESS'
        AclPolicySource='R2_F2G1CPostfailureAttestation_READ_ONLY_OWNER_DACL_RULES'
        LinkAndAds='LINK_ADS_NOT_ATTESTED'
    }
}

function Get-F2G1LT3Readiness {
    # No authorized host-read capability exists. Do NOT convert this into a
    # "grant" based on a string or a caller-supplied Boolean.
    return [pscustomobject]@{
        Schema='f2-g1-lt3-host-readiness-v1'
        Verdict='BLOCKED_WITH_EVIDENCE'
        Code='PROTECTED_HOST_READ_NOT_AUTHORIZED_OR_IMPLEMENTED'
        ProtectedReads=0
        HostAttestation='NOT_PERFORMED'
        V3='NOT_ATTESTED'
        SourceOnly=$true
    }
}

function Test-F2G1LT3ReferenceDeclarations {
    param([object]$Declarations)
    # Deliberate metadata-only preflight; never reports a real-host PASS.
    $out=[ordered]@{
        Schema='f2-g1-lt3-reference-preflight-v1'
        Verdict='BLOCKED_WITH_EVIDENCE'
        Code='DECLARATIONS_INCOMPLETE'
        ProtectedReads=0;HostAttestation='NOT_PERFORMED'
        TrustedEvidence=$false
    }
    try {
        if($null -eq $Declarations){throw 'DECLARATIONS_INCOMPLETE'}
        $ref=Get-F2G1LT3ReferenceContract
        if($Declarations.Schema -cne 'f2-g1-lt3-untrusted-declarations-v1'){throw 'DECLARATIONS_SCHEMA_INVALID'}
        if($Declarations.ManifestSha256 -cne $ref.ManifestSha256 -or
           $Declarations.PayloadSha256 -cne $ref.PayloadSha256 -or
           $Declarations.IntegritySha256 -cne $ref.IntegritySha256 -or
           $Declarations.MailboxId -cne $ref.MailboxId -or
           $Declarations.CaptureId -cne $ref.CaptureId -or
           $Declarations.ReviewedSourceSha -cne $ref.ReviewedSourceSha) {
            throw 'HISTORICAL_IDENTITY_MISMATCH'
        }
        $rows=@($Declarations.PackageMembers)
        if($rows.Count -ne 7){throw 'PACKAGE_REFERENCE_SET_INVALID'}
        $expected=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
        foreach($pin in @($ref.PackageMembers)) {$expected.Add($pin.Path,$pin.Sha256)}
        $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach($row in $rows){
            $path=[string]$row.Path
            $digest=[string]$row.Sha256
            if(-not $expected.ContainsKey($path) -or -not $seen.Add($path)){throw 'PACKAGE_REFERENCE_SET_INVALID'}
            if($digest -cnotmatch '^[0-9a-f]{64}$' -or $digest -cne $expected[$path]){throw 'HISTORICAL_PACKAGE_PIN_MISMATCH'}
        }
        if($seen.Count -ne 7){throw 'PACKAGE_REFERENCE_SET_INVALID'}
        $out.Code='DECLARATIONS_MATCH_HISTORICAL_REFERENCES_NOT_OBSERVED'
        # Still BLOCKED: input declarations can be forged and prove no physical bytes or ACL.
    } catch {
        $allowed=@('DECLARATIONS_INCOMPLETE','DECLARATIONS_SCHEMA_INVALID','HISTORICAL_IDENTITY_MISMATCH','PACKAGE_REFERENCE_SET_INVALID','HISTORICAL_PACKAGE_PIN_MISMATCH')
        $out.Code='DECLARATIONS_UNCLASSIFIED_BLOCKED'
        foreach($item in $allowed){if($_.Exception.Message -ceq $item){$out.Code=$item;break}}
    }
    return [pscustomobject]$out
}

Export-ModuleMember -Function Get-F2G1LT3ReferenceContract,Get-F2G1LT3Readiness,Test-F2G1LT3ReferenceDeclarations

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:HistoricalManifestSha256 = 'b5f01570cf8937324f0c763f72a8d05b5532472156d4e5b0fcfbd180dc7abbe9'
$script:HistoricalSourceSha = '5741ffe90a3abd02a08563e6431e8a0b9b63eeb1'
$script:MailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:CaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:PayloadSha256 = '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
$script:IntegritySha256 = '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
$script:CollectorSha256 = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
$script:ProtocolSha256 = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
$script:OldV2Pins = [ordered]@{
    'F2AclCapture.Protocol.psm1' = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1' = 'a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1' = '950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5'
    'Invoke-F2IcaclsCapture.ps1' = 'fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0'
    'Invoke-F2IcaclsProtectedCoordinator.ps1' = '3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2'
    'F2_ICACLS_SOURCE_PINS.json' = 'bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7'
    'Invoke-F2AclReadOnlyCapture.ps1' = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}
$script:PackageHome = 'C:\Program Files\F2-G1-Icacls'
$script:ProgramDataRoot = 'C:\ProgramData\F2-G1-Icacls'
$script:PackageScriptDir = Join-Path $script:PackageHome 'scripts'
$script:PackageAclDir = Join-Path $script:PackageScriptDir 'f2-acl'
$script:ActiveManifest = Join-Path $script:ProgramDataRoot 'approved-release.json'
$script:Mailbox = 'C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df'
$script:PackageFiles = @($script:OldV2Pins.Keys)
$script:MailboxFiles = @('acl-baseline.frame','acl-baseline.json','coordinator-status.json','integrity.json','powershell-streams.json','worker-stderr.json','worker-stdout.json')
$script:TransactionNames = @('release.lock','updates','backups','releases','journals','stages')
$script:Directories = @('C:\','C:\Program Files','C:\ProgramData',$script:PackageHome,$script:PackageScriptDir,$script:PackageAclDir,$script:ProgramDataRoot)

function New-F2G1Report {
    param([string]$Mode)
    return [pscustomobject]@{ Schema='f2-g1-c-postfailure-attestation-v1'; Mode=$Mode; Verdict='BLOCKED_WITH_EVIDENCE'; Scope='historical V2 preservation on this inspection only'; Limitations=@('No effective-token authorization decision.','No PASS_RESTRICTIVE_ACL conclusion.','No V3 installation or production readiness conclusion.'); Gates=(New-Object 'System.Collections.Generic.List[object]') }
}

function Add-F2G1Gate {
    param($Report,[string]$Name,[string]$Result,[hashtable]$Data)
    $Report.Gates.Add([pscustomobject]@{Name=$Name;Result=$Result;Data=$Data})
}

function Stop-F2G1 {
    param($Report,[string]$Name,[string]$Code,[hashtable]$Data)
    Add-F2G1Gate $Report $Name 'STOP' (@{Code=$Code} + $Data)
    return $Report
}

function Get-F2G1SddlProfile {
    param([string]$Sddl)
    try {
        $raw = [Security.AccessControl.RawSecurityDescriptor]::new($Sddl)
        $rules = @($raw.DiscretionaryAcl)
        $principals = @()
        foreach ($ace in $rules) {
            if ($null -eq $ace.SecurityIdentifier) { return $null }
            $principals += [string]$ace.SecurityIdentifier.Value
        }
        return [pscustomobject]@{Raw=$raw;Rules=$rules;Principals=$principals}
    } catch { return $null }
}

function Test-F2G1InstallDacl {
    param([string]$Sddl,[ValidateSet('Directory','File')][string]$Kind)
    $p = Get-F2G1SddlProfile $Sddl
    if ($null -eq $p -or $null -eq $p.Raw.Owner -or $p.Raw.Owner.Value -ne 'S-1-5-32-544' -or $null -eq $p.Raw.DiscretionaryAcl -or ($p.Raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $p.Rules.Count -ne 3) { return $false }
    $flags = if ($Kind -eq 'Directory') { 3 } else { 0 }
    $expected = @{'S-1-5-18'=[uint32]0x001F01FF;'S-1-5-32-544'=[uint32]0x001F01FF;'S-1-5-11'=[uint32]0x001200A9}
    $seen = @{}
    foreach ($ace in $p.Rules) {
        $sid = $ace.SecurityIdentifier.Value
        if (-not $expected.ContainsKey($sid) -or $seen.ContainsKey($sid) -or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or [uint32]$ace.AccessMask -ne $expected[$sid] -or [int]$ace.AceFlags -ne $flags) { return $false }
        $seen[$sid] = $true
    }
    return $seen.Count -eq 3
}

function Test-F2G1ParentDacl {
    param([string]$Sddl,[ValidateSet('DriveRoot','ProgramFiles','ProgramData')][string]$Mode)
    $p = Get-F2G1SddlProfile $Sddl
    if ($null -eq $p) { return $false }
    $raw = $p.Raw
    $trustedOwners = @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    if ($null -eq $raw.Owner -or $raw.Owner.Value -notin $trustedOwners -or $null -eq $raw.DiscretionaryAcl -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0 -or ($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0) { return $false }
    $danger = [long]0x00000002 -bor 0x00000004 -bor 0x00000010 -bor 0x00000040 -bor 0x00000100 -bor 0x00010000 -bor 0x00040000 -bor 0x00080000 -bor 0x40000000 -bor 0x10000000
    $safeReadExecute = [long]0x001200A9
    $rootCreateCount=0; $rootInheritedCount=0; $programDataCreateCount=0
    foreach ($ace in $raw.DiscretionaryAcl) {
        if ($ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $null -eq $ace.SecurityIdentifier) { return $false }
        $sid = $ace.SecurityIdentifier.Value
        $mask = [long]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        $inheritOnly = ([int]$ace.AceFlags -band [int][Security.AccessControl.AceFlags]::InheritOnly) -ne 0
        if ($inheritOnly) {
            if ($Mode -ne 'DriveRoot') { continue }
            if ($sid -in @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { continue }
            $expectedFlags=[int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit -bor [int][Security.AccessControl.AceFlags]::InheritOnly
            if ($sid -eq 'S-1-5-11' -and $mask -eq 3758161920 -and [int]$ace.AceFlags -eq $expectedFlags) { $rootInheritedCount++; continue }
            if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
            continue
        }
        if ($sid -in @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')) { continue }
        if ($Mode -eq 'DriveRoot' -and $sid -eq 'S-1-5-11' -and $mask -eq 0x00000004 -and [int]$ace.AceFlags -eq 0) { $rootCreateCount++; continue }
        if ($Mode -eq 'ProgramData' -and $sid -eq 'S-1-5-32-545' -and $mask -eq 0x116 -and [int]$ace.AceFlags -eq [int][Security.AccessControl.AceFlags]::ContainerInherit) { $programDataCreateCount++; continue }
        if (($mask -band $danger) -ne 0 -or ($mask -band (-bnot $safeReadExecute)) -ne 0) { return $false }
    }
    if ($Mode -eq 'DriveRoot' -and ($rootCreateCount -ne 1 -or $rootInheritedCount -ne 1)) { return $false }
    if ($Mode -eq 'ProgramData' -and $programDataCreateCount -ne 1) { return $false }
    return $true
}

function Get-F2G1SanitizedAclMetadata {
    param([string]$Sddl)
    $profile=Get-F2G1SddlProfile $Sddl
    if($null -eq $profile){return @()}
    $rows=@()
    foreach($ace in $profile.Rules){
        $sid=$ace.SecurityIdentifier.Value
        $principal=switch -Exact($sid){'S-1-5-18'{'SYSTEM'}'S-1-5-32-544'{'Administrators'}'S-1-5-11'{'Authenticated Users'}'S-1-5-32-545'{'Users'}'S-1-1-0'{'Everyone'}'S-1-3-4'{'Owner Rights'}default{'OTHER'}}
        $mask=[uint32]([int64]$ace.AccessMask -band 0xFFFFFFFFL)
        $rights=if($mask -eq [uint32]0x001F01FF){'FullControl'}elseif($mask -eq [uint32]0x001200A9){'ReadExecute'}elseif($mask -eq 4){'CreateFiles'}elseif($mask -eq 0x116){'CreateFolders'}else{'OtherRightsRedacted'}
        $rows+=@{Principal=$principal;Access=$(if($ace.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed){'Allow'}else{'Deny'});RightsClass=$rights;Inherited=(([int]$ace.AceFlags -band [int][Security.AccessControl.AceFlags]::Inherited) -ne 0);InheritOnly=(([int]$ace.AceFlags -band [int][Security.AccessControl.AceFlags]::InheritOnly) -ne 0)}
    }
    return $rows
}

function Get-F2G1ExpectedBaselinePaths {
    $root='G:\F2-G1-Isolated-Disposable';$name='F2-G1-Isolated-Disposable';$vm=([guid]'6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1').ToString().ToUpperInvariant();$config=Join-Path $root $name;$configVm=Join-Path (Join-Path $config 'Virtual Machines') $vm
    return @($root,$config,(Join-Path $config 'Virtual Machines'),$configVm,($configVm+'.vmcx'),($configVm+'.vmgs'),($configVm+'.VMRS'),(Join-Path $root 'F2-G1-OS.vhdx'),(Join-Path $root 'F2-G1-Scratch.vhdx'),(Join-Path $root 'Virtual Machines'),(Join-Path (Join-Path $root 'Virtual Machines') $vm))
}

function New-F2G1LiveProvider {
    $getPath={
            param([string]$Path)
            if ($Path -notin $script:Directories -and $Path -ne $script:ActiveManifest -and $Path -ne $script:Mailbox -and $Path -notin @($script:PackageFiles | ForEach-Object { Join-Path $script:PackageAclDir $_ }) -and $Path -notin @($script:MailboxFiles | ForEach-Object { Join-Path $script:Mailbox $_ })) { throw 'PATH_NOT_ALLOWLISTED' }
            $full = [IO.Path]::GetFullPath($Path)
            if (-not [string]::Equals($full,$Path,[StringComparison]::OrdinalIgnoreCase)) { throw 'PATH_NOT_CANONICAL' }
            $root = [IO.Path]::GetPathRoot($full); $current=$root; $rest=$full.Substring($root.Length).TrimEnd('\')
            if (-not [string]::IsNullOrEmpty($rest)) {
                foreach ($part in $rest.Split('\')) {
                    if ([string]::IsNullOrEmpty($part)) { continue }
                    $current=Join-Path $current $part
                    if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
                        $ancestor=Get-Item -LiteralPath $current -Force -ErrorAction Stop
                        if (($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'REPARSE_POINT_PRESENT' }
                    }
                }
            }
            $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
            $acl=Get-Acl -LiteralPath $full -ErrorAction Stop
            $sections=[Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group -bor [Security.AccessControl.AccessControlSections]::Access
            $sddl=$acl.GetSecurityDescriptorSddlForm($sections)
            return [pscustomobject]@{Exists=$true;Kind=$(if($item.PSIsContainer){'Directory'}else{'File'});Reparse=(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0);Length=$(if($item.PSIsContainer){0}else{$item.Length});Sddl=$sddl}
        }.GetNewClosure()
    $readBytes={
            param([string]$Path,[int]$MaximumBytes)
            $meta=& $getPath $Path
            if ($meta.Kind -ne 'File' -or $meta.Length -lt 0 -or $meta.Length -gt $MaximumBytes) { throw 'FILE_SIZE_OR_TYPE_INVALID' }
            $stream=New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                if($stream.Length -gt $MaximumBytes){throw 'FILE_SIZE_OR_TYPE_INVALID'}
                $bytes=New-Object byte[] ([int]$stream.Length);$offset=0
                while($offset -lt $bytes.Length){$read=$stream.Read($bytes,$offset,$bytes.Length-$offset);if($read -le 0){throw 'INCOMPLETE_FILE_READ'};$offset+=$read}
                if($stream.ReadByte() -ne -1){throw 'FILE_CHANGED_DURING_READ'}
                return ,$bytes
            } finally { $stream.Dispose() }
        }.GetNewClosure()
    $listChildren={
            param([string]$Path)
            if ($Path -notin @($script:PackageHome,$script:PackageScriptDir,$script:PackageAclDir,$script:ProgramDataRoot,$script:Mailbox)) { throw 'DIRECTORY_NOT_ALLOWLISTED_FOR_ENUMERATION' }
            return @((Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | ForEach-Object { [pscustomobject]@{Name=[string]$_.Name;Kind=$(if($_.PSIsContainer){'Directory'}else{'File'});Reparse=(($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)} }))
        }.GetNewClosure()
    return @{Mode='Live';GetPath=$getPath;ReadBytes=$readBytes;ListChildren=$listChildren}
}

function New-F2G1FixtureProvider {
    param([string]$FixtureRoot)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -ne $temp -or [IO.Path]::GetFileName($full) -notmatch '^F2G1-CPostfailure-[0-9a-fA-F-]{36}$') { throw 'FIXTURE_ROOT_OUTSIDE_TEMP_ALLOWLIST' }
    $rootItem=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'FIXTURE_ROOT_INVALID' }
    $fixturePath=Join-Path $full 'fixture.json'
    $fixtureItem=Get-Item -LiteralPath $fixturePath -Force -ErrorAction Stop
    if ($fixtureItem.PSIsContainer -or ($fixtureItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $fixtureItem.Length -gt 1048576) { throw 'FIXTURE_TYPE_REPARSE_OR_SIZE_INVALID' }
    $fixtureStream=New-Object IO.FileStream($fixturePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if ($fixtureStream.Length -gt 1048576) { throw 'FIXTURE_TOO_LARGE' }
        $fixtureBytes=New-Object byte[] ([int]$fixtureStream.Length);$fixtureOffset=0
        while($fixtureOffset -lt $fixtureBytes.Length){$fixtureRead=$fixtureStream.Read($fixtureBytes,$fixtureOffset,$fixtureBytes.Length-$fixtureOffset);if($fixtureRead -le 0){throw 'FIXTURE_INCOMPLETE_READ'};$fixtureOffset+=$fixtureRead}
        if($fixtureStream.ReadByte() -ne -1){throw 'FIXTURE_CHANGED_DURING_READ'}
    } finally { $fixtureStream.Dispose() }
    $fixture=[Text.Encoding]::UTF8.GetString($fixtureBytes)|ConvertFrom-Json -ErrorAction Stop
    $getPath={param([string]$Path) if ($fixture.Fault -eq 'AccessDenied' -and $Path -eq $fixture.FaultPath) { throw 'SIMULATED_ACCESS_DENIED' }; $row=@($fixture.Paths | Where-Object { $_.Path -ceq $Path }) | Select-Object -First 1; if ($null -eq $row -or -not $row.Exists) { throw 'SIMULATED_MISSING_OBJECT' }; return $row}.GetNewClosure()
    $readBytes={param([string]$Path,[int]$MaximumBytes) if ($fixture.Fault -eq 'AccessDenied' -and $Path -eq $fixture.FaultPath) { throw 'SIMULATED_ACCESS_DENIED' }; $row=@($fixture.Files | Where-Object { $_.Path -ceq $Path }) | Select-Object -First 1; if ($null -eq $row) { throw 'SIMULATED_MISSING_FILE' }; $bytes=[Convert]::FromBase64String([string]$row.Base64); if($bytes.Length -gt $MaximumBytes){throw 'SIMULATED_FILE_TOO_LARGE'}; return ,$bytes}.GetNewClosure()
    $listChildren={param([string]$Path) if ($fixture.Fault -eq 'AccessDenied' -and $Path -eq $fixture.FaultPath) { throw 'SIMULATED_ACCESS_DENIED' }; $row=@($fixture.Children | Where-Object { $_.Path -ceq $Path }) | Select-Object -First 1; if($null -eq $row){throw 'SIMULATED_MISSING_INVENTORY'}; return @($row.Entries)}.GetNewClosure()
    return @{
        Mode='Fixture'; Fixture=$fixture; GetPath=$getPath; ReadBytes=$readBytes; ListChildren=$listChildren
        Identity=[pscustomobject]@{IsAdministrator=[bool]$fixture.IsAdministrator;UserSid=[string]$fixture.UserSid}
    }
}

function Get-F2G1Sha256 {
    param([byte[]]$Bytes)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-F2G1Core {
    param($Provider)
    $report=New-F2G1Report $Provider.Mode
    $identity = if($Provider.Mode -eq 'Live') { $i=[Security.Principal.WindowsIdentity]::GetCurrent();$p=New-Object Security.Principal.WindowsPrincipal($i);[pscustomobject]@{IsAdministrator=[bool]$p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);UserSid=[string]$i.User.Value} } else { $Provider.Identity }
    if ($identity.IsAdministrator) { return (Stop-F2G1 $report 'ExecutionContext' 'ADMINISTRATOR_TOKEN' @{}) }
    Add-F2G1Gate $report 'ExecutionContext' 'PASS' @{PowerShell='5.1';IsAdministrator=$false}

    $parentModes=@{'C:\'='DriveRoot';'C:\Program Files'='ProgramFiles';'C:\ProgramData'='ProgramData'}
    foreach($path in $script:Directories){
        try{$meta=& $Provider.GetPath $path}catch{return (Stop-F2G1 $report ('Path:'+ $path) 'PATH_OR_ACL_UNREADABLE' @{ErrorClass=$_.Exception.GetType().Name})}
        if(-not $meta.Exists -or $meta.Reparse){return (Stop-F2G1 $report ('Path:'+ $path) 'MISSING_OR_REPARSE' @{})}
        if($meta.Kind -ne 'Directory'){return (Stop-F2G1 $report ('Path:'+ $path) 'OBJECT_TYPE_MISMATCH' @{Kind=$meta.Kind})}
        $pass=$false
        if($parentModes.ContainsKey($path)){$pass=Test-F2G1ParentDacl $meta.Sddl $parentModes[$path]}else{$pass=Test-F2G1InstallDacl $meta.Sddl Directory}
        if(-not $pass){return (Stop-F2G1 $report ('Path:'+ $path) 'OWNER_OR_DACL_POLICY_MISMATCH' @{Dacl='redacted'})}
        Add-F2G1Gate $report ('Path:'+ $path) 'PASS' @{Kind='Directory';Reparse=$false;OwnerClass='approved-profile';Dacl='approved-profile';ReadWriteGrantMetadata=(Get-F2G1SanitizedAclMetadata $meta.Sddl);EffectiveTokenConclusion='not computed'}
    }

    $roots=@{$script:PackageHome=@('scripts');$script:PackageScriptDir=@('f2-acl');$script:PackageAclDir=$script:PackageFiles;$script:ProgramDataRoot=@('approved-release.json')}
    foreach($root in @($script:PackageHome,$script:PackageScriptDir,$script:PackageAclDir,$script:ProgramDataRoot)){
        try{$actual=@(& $Provider.ListChildren $root)}catch{return (Stop-F2G1 $report 'ImmediateChildInventory' 'INVENTORY_FAILED' @{Root=$root;ErrorClass=$_.Exception.GetType().Name})}
        $expected=@($roots[$root])
        if($root -eq $script:PackageAclDir){$expected+= $script:TransactionNames}
        if($root -eq $script:ProgramDataRoot){$expected+= $script:TransactionNames}
        foreach($entry in $actual){if($entry.Name -notin $expected){return (Stop-F2G1 $report 'ImmediateChildInventory' 'UNEXPECTED_CHILD' @{Root=$root;Name=$entry.Name})};if($entry.Reparse){return (Stop-F2G1 $report 'ImmediateChildInventory' 'REPARSE_CHILD' @{Root=$root;Name=$entry.Name})};if($entry.Name -in $script:TransactionNames){return (Stop-F2G1 $report 'TransactionArtifacts' 'TRANSACTION_ARTIFACT_PRESENT' @{Root=$root;Name=$entry.Name;Kind=$entry.Kind})}}
        foreach($name in $expected){if($name -notin @($actual.Name)){if($name -in $script:TransactionNames){continue};return (Stop-F2G1 $report 'ImmediateChildInventory' 'REQUIRED_CHILD_MISSING' @{Root=$root;Name=$name})}}
        Add-F2G1Gate $report ('Inventory:'+ $root) 'PASS' @{Count=$actual.Count;Unexpected=0;TransactionArtifacts=0}
    }

    try{$manifestMeta=& $Provider.GetPath $script:ActiveManifest;$manifestBytes=& $Provider.ReadBytes $script:ActiveManifest 65536}catch{return (Stop-F2G1 $report 'ActiveManifest' 'READ_FAILED' @{ErrorClass=$_.Exception.GetType().Name})}
    if(-not $manifestMeta.Exists -or $manifestMeta.Reparse -or $manifestMeta.Kind -ne 'File' -or $manifestMeta.Length -ne $manifestBytes.Length -or -not (Test-F2G1InstallDacl $manifestMeta.Sddl File)){return (Stop-F2G1 $report 'ActiveManifest' 'TYPE_REPARSE_OWNER_DACL_OR_READ_RACE' @{Dacl='redacted'})}
    $manifestHash=Get-F2G1Sha256 $manifestBytes
    $expectedManifestHash=if($Provider.Mode -eq 'Live'){$script:HistoricalManifestSha256}else{[string]$Provider.Fixture.Expected.ManifestSha256}
    if($manifestHash -cne $expectedManifestHash){return (Stop-F2G1 $report 'ActiveManifest' 'MANIFEST_SHA256_MISMATCH' @{ActualSha256=$manifestHash;ExpectedSha256=$expectedManifestHash})}
    try{$m=[Text.Encoding]::UTF8.GetString($manifestBytes)|ConvertFrom-Json -ErrorAction Stop}catch{return (Stop-F2G1 $report 'ActiveManifest' 'MANIFEST_JSON_INVALID' @{Sha256=$manifestHash})}
    $expectedSource=if($Provider.Mode -eq 'Live'){$script:HistoricalSourceSha}else{[string]$Provider.Fixture.Expected.ReviewedCommitSha}
    $expectedMailbox=if($Provider.Mode -eq 'Live'){$script:MailboxId}else{[string]$Provider.Fixture.Expected.BaselineMailboxId}
    $expectedCapture=if($Provider.Mode -eq 'Live'){$script:CaptureId}else{[string]$Provider.Fixture.Expected.BaselinePayloadCaptureId}
    if($m.Schema -cne 'f2-icacls-runtime-release-v2' -or $m.ReviewedCommitSha -cne $expectedSource -or $m.BaselineMailboxId -cne $expectedMailbox -or $m.BaselinePayloadCaptureId -cne $expectedCapture){return (Stop-F2G1 $report 'ActiveManifest' 'MANIFEST_IDENTITY_MISMATCH' @{Sha256=$manifestHash})}
    $manifestPins=@($m.Files);$pinNames=@($manifestPins.Name | Sort-Object -Unique)
    if($manifestPins.Count -ne 7 -or $pinNames.Count -ne 7 -or @(Compare-Object (@($script:PackageFiles|Sort-Object)) $pinNames -CaseSensitive).Count -ne 0){return (Stop-F2G1 $report 'ActiveManifest' 'MANIFEST_FILE_SET_INVALID' @{Sha256=$manifestHash})}
    if($Provider.Mode -eq 'Live'){
        if($m.BaselinePayloadSha256 -cne $script:PayloadSha256 -or $m.BaselineIntegritySha256 -cne $script:IntegritySha256 -or $m.SourcePinsManifestSha256 -cne $script:OldV2Pins['F2_ICACLS_SOURCE_PINS.json']){return (Stop-F2G1 $report 'ActiveManifest' 'MANIFEST_BASELINE_OR_SOURCE_PIN_MISMATCH' @{Sha256=$manifestHash})}
    }
    $packageRootClass=if($m.PSObject.Properties.Name -contains 'PackageRoot'){if([string]::IsNullOrWhiteSpace([string]$m.PackageRoot)){'present-empty'}else{'present-nonempty'}}else{'absent'}
    Add-F2G1Gate $report 'ActiveManifestIdentity' 'PASS' @{Sha256=$manifestHash;Schema=$m.Schema;ReviewedCommitSha=$m.ReviewedCommitSha;PackageRoot=$packageRootClass;BaselineMailboxId=$expectedMailbox;BaselinePayloadCaptureId=$expectedCapture;MemberCount=7}

    foreach($pin in $manifestPins){
        $path=Join-Path $script:PackageAclDir ([string]$pin.Name)
        try{$meta=& $Provider.GetPath $path;$bytes=& $Provider.ReadBytes $path 16777216}catch{return (Stop-F2G1 $report ('PackageFile:'+ $pin.Name) 'READ_FAILED' @{ErrorClass=$_.Exception.GetType().Name})}
        if(-not $meta.Exists -or $meta.Reparse -or $meta.Kind -ne 'File' -or $meta.Length -ne $bytes.Length){return (Stop-F2G1 $report ('PackageFile:'+ $pin.Name) 'MISSING_TYPE_REPARSE_OR_READ_RACE' @{})}
        $actual=Get-F2G1Sha256 $bytes;$oldPin=[string]$script:OldV2Pins[[string]$pin.Name]
        $expectedPin=if($Provider.Mode -eq 'Live'){$oldPin}else{[string]$pin.Sha256}
        if($pin.Sha256 -notmatch '^[0-9a-f]{64}$' -or $actual -cne $pin.Sha256 -or ($Provider.Mode -eq 'Live' -and $pin.Sha256 -cne $oldPin)){return (Stop-F2G1 $report ('PackageFile:'+ $pin.Name) 'PACKAGE_HASH_MISMATCH' @{ActualSha256=$actual;ExpectedSha256=$expectedPin;Length=$bytes.Length})}
        if(-not (Test-F2G1InstallDacl $meta.Sddl File)){return (Stop-F2G1 $report ('PackageFile:'+ $pin.Name) 'OWNER_OR_DACL_POLICY_MISMATCH' @{ActualSha256=$actual;Length=$bytes.Length;Dacl='redacted'})}
        Add-F2G1Gate $report ('PackageFile:'+ $pin.Name) 'PASS' @{Length=$bytes.Length;Sha256=$actual;OwnerClass='Administrators';Dacl='approved-file-profile';ReadWriteGrantMetadata=(Get-F2G1SanitizedAclMetadata $meta.Sddl);EffectiveTokenConclusion='not computed'}
    }

    try{$mailMeta=& $Provider.GetPath $script:Mailbox}catch{return (Stop-F2G1 $report 'BaselineMailbox' 'PATH_OR_ACL_UNREADABLE' @{ErrorClass=$_.Exception.GetType().Name})}
    if(-not $mailMeta.Exists -or $mailMeta.Reparse -or $mailMeta.Kind -ne 'Directory'){return (Stop-F2G1 $report 'BaselineMailbox' 'MISSING_TYPE_OR_REPARSE' @{})}
    $mailProfile=Get-F2G1SddlProfile $mailMeta.Sddl
    $requesterSid=[string]$identity.UserSid
    if($null -eq $mailProfile -or $mailProfile.Raw.Owner.Value -ne 'S-1-5-32-544' -or ($mailProfile.Raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $mailProfile.Rules.Count -ne 4){return (Stop-F2G1 $report 'BaselineMailbox' 'FOUR_ACE_PROFILE_MISMATCH' @{Dacl='redacted'})}
    $mailSeen=@{};$mailValid=$true
    foreach($ace in $mailProfile.Rules){$sid=$ace.SecurityIdentifier.Value;if($mailSeen.ContainsKey($sid)-or $ace.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or [int]$ace.AceFlags -ne 3){$mailValid=$false;break};$mailSeen[$sid]=$true;$mask=[uint32]$ace.AccessMask;if($sid -in @('S-1-5-18','S-1-5-32-544')){if($mask -ne [uint32]0x001F01FF){$mailValid=$false;break}}elseif($sid -in @('S-1-3-4',$requesterSid)){if($mask -ne [uint32]0x001200A9){$mailValid=$false;break}}else{$mailValid=$false;break}}
    if(-not $mailValid -or $mailSeen.Count -ne 4 -or -not $mailSeen.ContainsKey('S-1-5-18') -or -not $mailSeen.ContainsKey('S-1-5-32-544') -or -not $mailSeen.ContainsKey('S-1-3-4') -or -not $mailSeen.ContainsKey($requesterSid)){return (Stop-F2G1 $report 'BaselineMailbox' 'FOUR_ACE_PROFILE_MISMATCH' @{Dacl='redacted'})}
    try{$actualMailbox=@(& $Provider.ListChildren $script:Mailbox)}catch{return (Stop-F2G1 $report 'BaselineMailboxInventory' 'INVENTORY_FAILED' @{ErrorClass=$_.Exception.GetType().Name})}
    if($actualMailbox.Count -ne 7 -or @($actualMailbox.Name|Sort-Object -Unique).Count -ne 7 -or @(Compare-Object (@($script:MailboxFiles|Sort-Object)) (@($actualMailbox.Name|Sort-Object)) -CaseSensitive).Count -ne 0){return (Stop-F2G1 $report 'BaselineMailboxInventory' 'SEVEN_FILE_SET_INVALID' @{Count=$actualMailbox.Count})}
    foreach($entry in $actualMailbox){if($entry.Reparse -or $entry.Kind -ne 'File'){return (Stop-F2G1 $report 'BaselineMailboxInventory' 'CHILD_TYPE_OR_REPARSE_INVALID' @{Name=$entry.Name})}}
    $baselineBytes=@{};$baselineHashes=@{}
    foreach($name in $script:MailboxFiles){$path=Join-Path $script:Mailbox $name;$maxBytes=switch($name){'acl-baseline.frame'{262188};'acl-baseline.json'{1048576};default{65536}};try{$meta=& $Provider.GetPath $path;$bytes=& $Provider.ReadBytes $path $maxBytes}catch{return (Stop-F2G1 $report ('BaselineFile:'+ $name) 'READ_FAILED' @{ErrorClass=$_.Exception.GetType().Name})};if(-not $meta.Exists -or $meta.Reparse -or $meta.Kind -ne 'File' -or $meta.Length -ne $bytes.Length){return (Stop-F2G1 $report ('BaselineFile:'+ $name) 'MISSING_TYPE_REPARSE_OR_READ_RACE' @{})};$baselineBytes[$name]=$bytes;$baselineHashes[$name]=Get-F2G1Sha256 $bytes}
    $payloadHash=$baselineHashes['acl-baseline.json'];$integrityHash=$baselineHashes['integrity.json']
    if($Provider.Mode -eq 'Live' -and ($payloadHash -cne $script:PayloadSha256 -or $integrityHash -cne $script:IntegritySha256)){return (Stop-F2G1 $report 'BaselineHashes' 'HISTORICAL_HASH_MISMATCH' @{PayloadSha256=$payloadHash;IntegritySha256=$integrityHash})}
    try{$baseline=[Text.Encoding]::UTF8.GetString($baselineBytes['acl-baseline.json'])|ConvertFrom-Json -ErrorAction Stop;$integrity=[Text.Encoding]::UTF8.GetString($baselineBytes['integrity.json'])|ConvertFrom-Json -ErrorAction Stop}catch{return (Stop-F2G1 $report 'BaselineJson' 'MALFORMED_OR_INCOMPLETE_OUTPUT' @{PayloadSha256=$payloadHash;IntegritySha256=$integrityHash})}
    if($baseline.CaptureId -cne $expectedCapture -or $baseline.Complete -ne $true -or $baseline.VmId -cne '6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1' -or $baseline.VmName -cne 'F2-G1-Isolated-Disposable' -or @($baseline.Records).Count -ne 11){return (Stop-F2G1 $report 'BaselineRecords' 'CAPTURE_ID_OR_ELEVEN_RECORD_COMPLETENESS_INVALID' @{PayloadSha256=$payloadHash;RecordCount=@($baseline.Records).Count})}
    $recordPaths=@($baseline.Records|ForEach-Object{[string]$_.Path});$manifestPaths=@($baseline.Manifest.ExpectedPaths|ForEach-Object{[string]$_})
    $expectedRecordPaths=if($Provider.Mode -eq 'Live'){Get-F2G1ExpectedBaselinePaths}else{@($Provider.Fixture.Expected.RecordPaths)}
    if($recordPaths.Count -ne 11 -or @($recordPaths|Sort-Object -Unique).Count -ne 11 -or $manifestPaths.Count -ne 11 -or @($manifestPaths|Sort-Object -Unique).Count -ne 11 -or @(Compare-Object (@($expectedRecordPaths|Sort-Object)) (@($recordPaths|Sort-Object)) -CaseSensitive).Count -ne 0 -or @(Compare-Object (@($expectedRecordPaths|Sort-Object)) (@($manifestPaths|Sort-Object)) -CaseSensitive).Count -ne 0 -or $baseline.Manifest.ExpectedCount -ne 11 -or $baseline.Manifest.RecordCount -ne 11 -or $baseline.Manifest.UniquePathCount -ne 11){return (Stop-F2G1 $report 'BaselineRecords' 'EXACT_ELEVEN_PATH_SET_INVALID' @{PayloadSha256=$payloadHash})}
    if($integrity.Schema -cne 'f2-acl-integrity-v1' -or $integrity.PayloadFile -cne 'acl-baseline.json' -or [int64]$integrity.PayloadBytes -ne $baselineBytes['acl-baseline.json'].Length -or $integrity.PayloadSha256 -cne $payloadHash -or $integrity.ProjectVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $integrity.EvidenceVolumeGuid -notmatch '^\\\\\?\\Volume\{[0-9a-fA-F-]{36}\}\\?$' -or $integrity.ProjectVolumeGuid -ceq $integrity.EvidenceVolumeGuid -or $integrity.SeparateFromProjectVolume -ne $true -or $integrity.ChildExitCode -ne 0 -or $integrity.CollectorScriptSha256 -cne $script:CollectorSha256 -or $integrity.ProtocolModuleSha256 -cne $script:ProtocolSha256){return (Stop-F2G1 $report 'BaselineIntegrity' 'PAYLOAD_OR_PROVENANCE_BINDING_INVALID' @{IntegritySha256=$integrityHash})}
    $streamsBytes=$baselineBytes['powershell-streams.json'];$streamsHash=$baselineHashes['powershell-streams.json']
    if($integrity.PowerShellStreamsFile -cne 'powershell-streams.json' -or [int64]$integrity.PowerShellStreamsBytes -ne $streamsBytes.Length -or $integrity.PowerShellStreamsSha256 -cne $streamsHash){return (Stop-F2G1 $report 'BaselineIntegrity' 'STREAM_HASH_MISMATCH' @{IntegritySha256=$integrityHash})}
    try{$streams=[Text.Encoding]::UTF8.GetString($streamsBytes)|ConvertFrom-Json -ErrorAction Stop}catch{return (Stop-F2G1 $report 'BaselineStreams' 'MALFORMED_STREAM_OUTPUT' @{Sha256=$streamsHash})}
    if($streams.Schema -cne 'f2-acl-powershell-streams-v1' -or $streams.Complete -ne $true -or $streams.ExitCode -ne 0){return (Stop-F2G1 $report 'BaselineStreams' 'INCOMPLETE_STREAM_OUTPUT' @{Sha256=$streamsHash})}
    $diagnostics=@($integrity.WorkerDiagnosticFiles);$diagnosticNames=@($diagnostics|ForEach-Object{[string]$_.Name}|Sort-Object)
    if($diagnostics.Count -ne 2 -or @($diagnosticNames|Sort-Object -Unique).Count -ne 2 -or @(Compare-Object @('worker-stderr.json','worker-stdout.json') $diagnosticNames -CaseSensitive).Count -ne 0){return (Stop-F2G1 $report 'BaselineIntegrity' 'WORKER_DIAGNOSTIC_MANIFEST_INVALID' @{IntegritySha256=$integrityHash})}
    foreach($d in $diagnostics){$name=[string]$d.Name;if($name -notin @('worker-stderr.json','worker-stdout.json') -or [int64]$d.Bytes -le 0 -or [int64]$d.Bytes -gt 65536 -or [int64]$d.Bytes -ne $baselineBytes[$name].Length -or [string]$d.Sha256 -cne $baselineHashes[$name]){return (Stop-F2G1 $report 'BaselineIntegrity' 'WORKER_DIAGNOSTIC_HASH_MISMATCH' @{IntegritySha256=$integrityHash})}}
    $frame=$baselineBytes['acl-baseline.frame'];$payload=$baselineBytes['acl-baseline.json'];$frameHeader='46-32-41-43-4C-01-0D-0A'
    if($frame.Length -lt 44 -or [BitConverter]::ToString($frame[0..7]) -cne $frameHeader){return (Stop-F2G1 $report 'BaselineFrame' 'FRAME_HEADER_INVALID' @{Sha256=$baselineHashes['acl-baseline.frame']})}
    $frameLength=[BitConverter]::ToInt32($frame,8);if($frameLength -ne $payload.Length -or $frame.Length -ne (44+$frameLength)){return (Stop-F2G1 $report 'BaselineFrame' 'FRAME_LENGTH_INVALID' @{Sha256=$baselineHashes['acl-baseline.frame']})}
    $framePayload=New-Object byte[] $frameLength;$frameDigest=New-Object byte[] 32;[Buffer]::BlockCopy($frame,12,$framePayload,0,$frameLength);[Buffer]::BlockCopy($frame,(12+$frameLength),$frameDigest,0,32)
    $shaForFrame=[Security.Cryptography.SHA256]::Create();try{$expectedFrameDigest=$shaForFrame.ComputeHash($framePayload)}finally{$shaForFrame.Dispose()}
    if((Get-F2G1Sha256 $framePayload) -cne $payloadHash -or [BitConverter]::ToString($framePayload) -cne [BitConverter]::ToString($payload) -or [BitConverter]::ToString($frameDigest) -cne [BitConverter]::ToString($expectedFrameDigest)){return (Stop-F2G1 $report 'BaselineFrame' 'FRAME_PAYLOAD_OR_DIGEST_INVALID' @{Sha256=$baselineHashes['acl-baseline.frame']})}
    try{$status=[Text.Encoding]::UTF8.GetString($baselineBytes['coordinator-status.json'])|ConvertFrom-Json -ErrorAction Stop}catch{return (Stop-F2G1 $report 'BaselineCoordinator' 'STATUS_JSON_INVALID' @{Sha256=$baselineHashes['coordinator-status.json']})}
    $worker=$status.WorkerDiagnostics;$requiredStages=@('EntrypointReached','InvocationStarted','SourceVerified','MailboxVerified','CollectorEntered','FramePublished','StreamPublished','InvocationReturned')
    $expectedWorkerFiles=@($status.WorkerExpectedFiles|ForEach-Object{[string]$_.Name}|Sort-Object)
    $workerFilesExact=(($expectedWorkerFiles -join ',') -ceq 'acl-baseline.frame,powershell-streams.json' -and @($status.WorkerExpectedFiles|Where-Object{$_.Exists -ne $true -or $_.Length -le 0}).Count -eq 0)
    $statusDiagnostics=@($status.WorkerDiagnosticFiles|Sort-Object Name|ForEach-Object{([string]$_.Name)+':'+[string]$_.Bytes+':'+[string]$_.Sha256}) -join '|'
    $integrityDiagnostics=@($diagnostics|Sort-Object Name|ForEach-Object{([string]$_.Name)+':'+[string]$_.Bytes+':'+[string]$_.Sha256}) -join '|'
    if($status.Schema -cne 'f2-acl-elevated-coordinator-v1' -or $status.Outcome -cne 'COMPLETE_READ_ONLY_ACL_BASELINE' -or $status.RequesterSid -cne $requesterSid -or -not $status.AdministratorRoleVerified -or $status.WorkerExitCode -ne 0 -or $status.ExpectedProcessExitCode -ne 0 -or @($status.Errors).Count -ne 0 -or $null -ne $status.WorkerDiagnosticFallback -or -not $worker.Started -or $worker.State -cne 'Exited' -or $worker.TimedOut -or $worker.ExitCode -ne 0 -or -not $worker.OutputComplete -or -not $worker.CleanupComplete -or $worker.StdoutTruncated -or $worker.StderrTruncated -or $null -ne $worker.FatalError -or @($worker.ReaderErrors).Count -ne 0 -or @($requiredStages|Where-Object{$worker.Stages -cnotcontains $_}).Count -ne 0 -or -not $workerFilesExact -or $statusDiagnostics -cne $integrityDiagnostics){return (Stop-F2G1 $report 'BaselineCoordinator' 'COORDINATOR_OR_OUTPUT_COMPLETENESS_INVALID' @{Sha256=$baselineHashes['coordinator-status.json']})}
    $reportedHashes=@{};foreach($name in $script:MailboxFiles){$reportedHashes[$name]=$baselineHashes[$name]}
    Add-F2G1Gate $report 'BaselineEvidence' 'PASS' @{FileCount=7;UniqueRecordCount=11;PayloadSha256=$payloadHash;IntegritySha256=$integrityHash;AuxiliaryFileSha256=$reportedHashes;VolumeIdentity='distinct and validated; values redacted';RawSddlOmitted=$true;PrivateSidsOmitted=$true}
    $report.Verdict=if($Provider.Mode -eq 'Live'){'PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION'}else{'SYNTHETIC_FIXTURE_PASS'}
    return $report
}

function Invoke-F2G1CPostfailureAttestation {
    [CmdletBinding(DefaultParameterSetName='None')]
    param(
        [Parameter(Mandatory,ParameterSetName='Live')][switch]$Live,
        [Parameter(Mandatory,ParameterSetName='Live')][ValidateNotNullOrEmpty()][string]$OwnerAuthorizationReference,
        [Parameter(Mandatory,ParameterSetName='Fixture')][ValidateNotNullOrEmpty()][string]$SyntheticFixtureRoot
    )
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { return (Stop-F2G1 (New-F2G1Report 'Environment') 'Environment' 'POWERSHELL_51_REQUIRED' @{}) }
    if ($PSCmdlet.ParameterSetName -eq 'Live' -and $OwnerAuthorizationReference -notmatch '^https://github\.com/publiomcko-cloud/procedural-sandbox-simulation/issues/48#issuecomment-[1-9][0-9]*$') { return (Stop-F2G1 (New-F2G1Report 'Live') 'Authorization' 'EXACT_ISSUE_48_COMMENT_REFERENCE_REQUIRED' @{}) }
    if ($PSCmdlet.ParameterSetName -eq 'Live' -and $OwnerAuthorizationReference -match '6196160426') { return (Stop-F2G1 (New-F2G1Report 'Live') 'Authorization' 'PREVIOUS_OWNER_AUTHORIZATION_NOT_REUSABLE' @{}) }
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Live') { $provider=New-F2G1LiveProvider }
        else { $provider=New-F2G1FixtureProvider $SyntheticFixtureRoot }
        return Invoke-F2G1Core $provider
    } catch {
        $r=New-F2G1Report $PSCmdlet.ParameterSetName
        return (Stop-F2G1 $r 'Inspector' 'UNCLASSIFIED_FAILURE_CLOSED' @{ErrorClass=$_.Exception.GetType().Name;ErrorLine=[int]$_.InvocationInfo.ScriptLineNumber})
    }
}

Export-ModuleMember -Function Invoke-F2G1CPostfailureAttestation

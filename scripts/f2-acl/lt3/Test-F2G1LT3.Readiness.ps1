[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:GITHUB_REPOSITORY -cne 'publiomcko-cloud/procedural-sandbox-simulation'){throw 'LT3_CI_ONLY'}
$script:Count=0;$script:Failures=0
function Check([bool]$Ok,[string]$Name) {
 $script:Count++
 if($Ok){Write-Output ('PASS: '+$Name)}
 else{$script:Failures++;Write-Output ('FAIL: '+$Name)}
}
$module=Join-Path $PSScriptRoot 'F2G1LT3.Readiness.psm1'
$entry=Join-Path $PSScriptRoot 'Invoke-F2G1LT3.Readiness.ps1'
foreach($file in @($module,$entry,$MyInvocation.MyCommand.Path)){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) ('PS5.1 parser '+[IO.Path]::GetFileName($file))
}
$code=[IO.File]::ReadAllText($module)+[IO.File]::ReadAllText($entry)
$forbidden=@('Get-Acl','Get-Item','Get-ChildItem','Set-Acl','Remove-Item','Start-Process','Invoke-Expression','icacls.exe','-Live','OwnerAuthorizationReference')
Check (@($forbidden|Where-Object{$code.Contains($_)}).Count -eq 0) 'no host I/O, live or authorization-by-string'
Import-Module $module -Force -ErrorAction Stop
$ref=Get-F2G1LT3ReferenceContract
Check ($ref.ObjectCount -eq 23 -and $ref.DirectoryCount -eq 8 -and $ref.FileCount -eq 15 -and $ref.InventoryCount -eq 5) 'historical object counts fixed'
Check ($ref.PackageMembers.Count -eq 7 -and @($ref.PackageMembers.Path|Sort-Object -Unique).Count -eq 7) 'seven unique historical package pins'
Check ($ref.DirectoryLabels.Count -eq 8 -and $ref.FileLabels.Count -eq 15 -and $ref.InventoryLabels.Count -eq 5) 'fixed labels'
Check (-not $ref.HostAccessEnabled -and -not $ref.AuthorizationConfigured -and $ref.GDrivePolicy -ceq 'HISTORICAL_STRINGS_ONLY_NO_G_VOLUME_ACCESS') 'host and G volume access denied'
$readiness=Get-F2G1LT3Readiness
Check ($readiness.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $readiness.ProtectedReads -eq 0 -and $readiness.HostAttestation -ceq 'NOT_PERFORMED') 'host gate denied'
$r2=Join-Path $PSScriptRoot '..\F2G1CPostfailureAttestation.psm1'
$r2text=[IO.File]::ReadAllText($r2)
foreach($pin in @($ref.PackageMembers)){
 $name=[IO.Path]::GetFileName($pin.Path)
 Check ($r2text.Contains($name+"' = '"+$pin.Sha256+"'")) ('exact R2 pin '+$name)
}
foreach($digest in @($ref.ManifestSha256,$ref.PayloadSha256,$ref.IntegritySha256)){
 Check ($r2text.Contains($digest) -and $digest -cmatch '^[0-9a-f]{64}$') 'manifest/payload/integrity R2 hash match'
}
Check ($r2text.Contains($ref.MailboxId) -and $r2text.Contains($ref.CaptureId) -and $r2text.Contains($ref.ReviewedSourceSha)) 'historical R2 identities present'
function Declaration {
 $r=Get-F2G1LT3ReferenceContract
 return [pscustomobject]@{
  Schema='f2-g1-lt3-untrusted-declarations-v1'
  ManifestSha256=$r.ManifestSha256;PayloadSha256=$r.PayloadSha256;IntegritySha256=$r.IntegritySha256
  MailboxId=$r.MailboxId;CaptureId=$r.CaptureId;ReviewedSourceSha=$r.ReviewedSourceSha
  PackageMembers=@($r.PackageMembers|ForEach-Object{[pscustomobject]@{Path=$_.Path;Sha256=$_.Sha256}})
 }
}
$match=Test-F2G1LT3ReferenceDeclarations (Declaration)
Check ($match.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and
 $match.Code -ceq 'DECLARATIONS_MATCH_HISTORICAL_REFERENCES_NOT_OBSERVED' -and
 $match.ProtectedReads -eq 0 -and -not $match.TrustedEvidence) 'matching declarations remain untrusted and blocked'
$cases=@(
 @{Name='schema';Code='DECLARATIONS_SCHEMA_INVALID';Fault={param($x) $x.Schema='wrong'}},
 @{Name='manifest';Code='HISTORICAL_IDENTITY_MISMATCH';Fault={param($x) $x.ManifestSha256='wrong'}},
 @{Name='payload';Code='HISTORICAL_IDENTITY_MISMATCH';Fault={param($x) $x.PayloadSha256='wrong'}},
 @{Name='integrity';Code='HISTORICAL_IDENTITY_MISMATCH';Fault={param($x) $x.IntegritySha256='wrong'}},
 @{Name='mailbox';Code='HISTORICAL_IDENTITY_MISMATCH';Fault={param($x) $x.MailboxId='wrong'}},
 @{Name='capture';Code='HISTORICAL_IDENTITY_MISMATCH';Fault={param($x) $x.CaptureId='wrong'}},
 @{Name='source';Code='HISTORICAL_IDENTITY_MISMATCH';Fault={param($x) $x.ReviewedSourceSha='wrong'}},
 @{Name='pin';Code='HISTORICAL_PACKAGE_PIN_MISMATCH';Fault={param($x) $x.PackageMembers[0].Sha256=('a'*64)}},
 @{Name='pin-malformed';Code='HISTORICAL_PACKAGE_PIN_MISMATCH';Fault={param($x) $x.PackageMembers[0].Sha256='no'}},
 @{Name='duplicate';Code='PACKAGE_REFERENCE_SET_INVALID';Fault={param($x) $x.PackageMembers[1].Path=$x.PackageMembers[0].Path}},
 @{Name='missing';Code='PACKAGE_REFERENCE_SET_INVALID';Fault={param($x) $x.PackageMembers=@($x.PackageMembers|Select-Object -Skip 1)}},
 @{Name='case-alias';Code='PACKAGE_REFERENCE_SET_INVALID';Fault={param($x) $x.PackageMembers[0].Path=$x.PackageMembers[0].Path.ToUpperInvariant()}}
)
foreach($case in $cases){
 $d=Declaration
 & $case.Fault $d
 $result=Test-F2G1LT3ReferenceDeclarations $d
 Check ($result.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $result.Code -ceq $case.Code -and $result.ProtectedReads -eq 0) ('invalid declarations '+$case.Name)
}
$invalid=Test-F2G1LT3ReferenceDeclarations $null
Check ($invalid.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $invalid.ProtectedReads -eq 0) 'null input denied'
foreach($which in @('default','describe')){
 $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$entry)
 if($which -ceq 'describe'){$arguments+='-Describe'}
 $output=@(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @arguments)
 $exitcode=$LASTEXITCODE
 $j=($output -join [Environment]::NewLine)|ConvertFrom-Json
 Check ($exitcode -eq 2 -and $j.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $j.ProtectedReads -eq 0 -and $j.HostAttestation -ceq 'NOT_PERFORMED') ('CLI '+$which+' denied')
}

# Actual BYTES (not advertised checksums) must be digested against the immutable R2 pins.
# Known historical installed bytes are intentionally NOT in this synthetic source suite.
$bytes=[Text.UTF8Encoding]::new($false).GetBytes('synthetic-not-historical')
$members=@($ref.PackageMembers|ForEach-Object{[pscustomobject]@{Path=$_.Path;Bytes=[byte[]]$bytes}})
$captured=[pscustomobject]@{
    PackageMembers=$members
    ManifestBytes=[byte[]]$bytes
    PayloadBytes=[byte[]]$bytes
    IntegrityBytes=[byte[]]$bytes
}
$wrongBytes=Test-F2G1LT3CapturedBytes $captured
Check ($wrongBytes.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $wrongBytes.Code -ceq 'PACKAGE_BYTES_HASH_MISMATCH' -and
    $wrongBytes.ProtectedReads -eq 0 -and -not $wrongBytes.TrustedOrigin) 'real byte digests cannot be forged by declared hash values'
$captured.PackageMembers[1].Path=$captured.PackageMembers[0].Path
$dupe=Test-F2G1LT3CapturedBytes $captured
Check ($dupe.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $dupe.ProtectedReads -eq 0) 'duplicate captured byte path cannot pass'
$empty=Test-F2G1LT3CapturedBytes $null
Check ($empty.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $empty.ProtectedReads -eq 0) 'missing bytes fail closed'

Write-Output ('LT3_ASSERTIONS='+$script:Count+' FAILURES='+$script:Failures)
if($script:Failures -ne 0){exit 1}
exit 0

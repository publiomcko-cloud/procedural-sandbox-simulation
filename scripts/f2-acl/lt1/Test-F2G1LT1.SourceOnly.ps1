[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:GITHUB_REPOSITORY -cne 'publiomcko-cloud/procedural-sandbox-simulation'){
    throw 'LT1_DISPOSABLE_HOSTED_WINDOWS_CI_ONLY'
}
$script:Count=0;$script:Failures=New-Object 'System.Collections.Generic.List[string]'
function Check([bool]$Condition,[string]$Label) {
    $script:Count++
    if($Condition){[Console]::Out.WriteLine('PASS: '+$Label)}
    else{$script:Failures.Add($Label);[Console]::Out.WriteLine('FAIL: '+$Label)}
}
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$module=Join-Path $root 'F2G1LT1.Synthetic.psm1'
$entry=Join-Path $root 'Invoke-F2G1LT1.SourceOnly.ps1'
foreach($file in @($module,$entry,$MyInvocation.MyCommand.Path)){
    $tokens=$null;$errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) ('PS51 syntax: '+[IO.Path]::GetFileName($file))
}
$source=[IO.File]::ReadAllText($module)+[IO.File]::ReadAllText($entry)
$forbidden=@('Get-Acl','Get-ChildItem','Set-Acl','Remove-Item','Invoke-Expression','Start-Process','icacls','-Live','Invoke-F2G1CPostfailureAttestation')
$found=@($forbidden|Where-Object{$source.Contains($_)})
Check ($found.Count -eq 0) 'LT1 mock sources contain no protected I/O, live flag or legacy inspector invocation'
Import-Module $module -Force -ErrorAction Stop
$scope=Get-F2G1LT1Scope
Check ($scope.Directories.Count -eq 8 -and $scope.Files.Count -eq 15 -and $scope.Inventories.Count -eq 5) 'fixed 23-object, five-inventory historical shape'
Check ($scope.TransactionNames.Count -eq 6 -and @($scope.Inventories[2].Names).Count -eq 7 -and @($scope.Inventories[4].Names).Count -eq 7) 'fixed historical package/mailbox and prohibited transaction shapes'
foreach($profile in @('Standard','FilteredLimited')){
    $mock=New-F2G1LT1SyntheticFixture -MockTokenProfile $profile
    $r=Invoke-F2G1LT1Synthetic -Fixture $mock
    Check ($r.Verdict -ceq 'SYNTHETIC_FIXTURE_PASS' -and $r.ObjectCount -eq 23 -and $r.InventoryCount -eq 5 -and $r.ProtectedReads -eq 0 -and $r.LinkAndAds -ceq 'LINK_ADS_NOT_ATTESTED' -and $r.HistoricalV2 -ceq 'NOT_ATTESTED_MOCK_BYTES_ONLY') ('complete inert '+$profile+' profile passes without host or V2 attestation')
}
foreach($profile in @('Elevated','FullAdministrator','System','HighIntegrity','Impersonated','Privileged','Unknown')){
    $r=Invoke-F2G1LT1Synthetic -Fixture (New-F2G1LT1SyntheticFixture -MockTokenProfile $profile)
    Check ($r.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $r.Code -ceq 'MOCK_TOKEN_NOT_STANDARD' -and $r.ProtectedReads -eq 0) ('mock '+$profile+' denied before inspecting objects')
}
$cases=@(
    @{Name='missing-object';Fault={param($x) $x.Objects[8].Exists=$false}},
    @{Name='unexpected-file-content';Fault={param($x) $x.Objects[8].Body='tampered synthetic body'}},
    @{Name='reparse';Fault={param($x) $x.Objects[3].Reparse=$true}},
    @{Name='acl-profile';Fault={param($x) $x.Objects[3].AclMatches=$false}},
    @{Name='identity-drift';Fault={param($x) $x.Objects[8].After='changed'}},
    @{Name='extra-child';Fault={param($x) $x.Inventories[2].Children+=@('unexpected.bin')}},
    @{Name='missing-child';Fault={param($x) $x.Inventories[2].Children=@()}},
    @{Name='duplicate-object';Fault={param($x) $x.Objects[1].Path=$x.Objects[0].Path}},
    @{Name='wrong-case-path';Fault={param($x) $x.Objects[8].Path=$x.Objects[8].Path.ToUpperInvariant()}},
    @{Name='missing-inventory';Fault={param($x) $x.Inventories=@($x.Inventories | Select-Object -Skip 1)}},
    @{Name='duplicated-inventory';Fault={param($x) $x.Inventories[1].Path=$x.Inventories[0].Path}},
    @{Name='duplicate-child';Fault={param($x) $x.Inventories[2].Children[1]=$x.Inventories[2].Children[0]}},
    @{Name='overlong-file';Fault={param($x) $x.Objects[15].Body=('X'*65537)}}
)
foreach($case in $cases){
    $fixture=New-F2G1LT1SyntheticFixture
    & $case.Fault $fixture
    $result=Invoke-F2G1LT1Synthetic -Fixture $fixture
    Check ($result.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $result.ProtectedReads -eq 0 -and $result.Code -cne 'COMPLETE_MOCK_ONLY') ('inert negative '+$case.Name+' fails closed')
}
$blocked=$false
try {Invoke-F2G1LT1Synthetic -Fixture $null | Out-Null}
catch {$blocked=$true}
Check ($blocked -or (Invoke-F2G1LT1Synthetic -Fixture ([pscustomobject]@{Schema='wrong';MockTokenProfile='Standard';Objects=@();Inventories=@()})).Verdict -ceq 'BLOCKED_WITH_EVIDENCE') 'invalid fixture schema rejected'
[Console]::Out.WriteLine('LT1_ASSERTIONS='+$script:Count+' FAILURES='+$script:Failures.Count)
if($script:Failures.Count -ne 0){exit 1}
exit 0

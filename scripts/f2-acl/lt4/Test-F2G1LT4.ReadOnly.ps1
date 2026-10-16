[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:GITHUB_REPOSITORY -cne 'publiomcko-cloud/procedural-sandbox-simulation'){
 throw 'LT4_DISPOSABLE_CI_ONLY'
}
Import-Module (Join-Path $PSScriptRoot '..\lt1\F2G1LT1.Synthetic.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'F2G1LT4.ReadOnlyAdapter.psm1') -Force -ErrorAction Stop
$script:Assertions=0;$script:Failures=0
function Check([bool]$Ok,[string]$Label){
 $script:Assertions++
 if($Ok){Write-Output ('PASS: '+$Label)}
 else{$script:Failures++;Write-Output ('FAIL: '+$Label)}
}
function FixturePath([string]$Root,[string]$Label){
 if($Label -ceq 'C:\'){return (Join-Path $Root 'C')}
 return (Join-Path (Join-Path $Root 'C') $Label.Substring(3))
}
function CreateFixture {
 $root=Join-Path $env:RUNNER_TEMP ('F2G1-LT4-'+[guid]::NewGuid().ToString())
 [void][IO.Directory]::CreateDirectory($root)
 $scope=Get-F2G1LT1Scope
 foreach($label in $scope.Directories){
  [void][IO.Directory]::CreateDirectory((FixturePath $root $label))
 }
 foreach($file in $scope.Files){
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes('LT4-CI-SYNTHETIC|'+$file.Path)
  [IO.File]::WriteAllBytes((FixturePath $root $file.Path),$bytes)
 }
 return $root
}
function Snapshot([string]$Root){
 $rows=@(Get-ChildItem -LiteralPath $Root -File -Recurse -Force | Sort-Object FullName)
 $values=@()
 foreach($f in $rows){
  $sha=[Security.Cryptography.SHA256]::Create()
  try{
   $stream=[IO.File]::OpenRead($f.FullName)
   try{$hash=[BitConverter]::ToString($sha.ComputeHash($stream))}
   finally{$stream.Dispose()}
  }finally{$sha.Dispose()}
  $values+=($f.FullName.Substring($Root.Length)+':'+$hash+':'+(Get-Acl -LiteralPath $f.FullName).Sddl)
 }
 return ($values -join '|')
}
foreach($file in @((Join-Path $PSScriptRoot 'F2G1LT4.ReadOnlyAdapter.psm1'),
 (Join-Path $PSScriptRoot 'Invoke-F2G1LT4.ReadOnly.ps1'),$MyInvocation.MyCommand.Path)){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) ('PS5.1 syntax '+[IO.Path]::GetFileName($file))
}
$gate=Get-F2G1LT4HostReadiness
Check ($gate.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and -not $gate.HostAccessEnabled -and
 $gate.ProtectedReads -eq 0) 'protected host entry blocked'
$token=Test-F2G1LT4ActualToken
Check ($token -is [bool]) 'actual process token classified'
$root=CreateFixture
$before=Snapshot $root
$result=Invoke-F2G1LT4Fixture -FixtureRoot $root
$after=Snapshot $root
Check ($result.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $result.ProtectedReads -eq 0 -and
 $result.HostAttestation -ceq 'NOT_PERFORMED') 'physical fixture cannot claim host pass'
Check ($result.PhysicalObjects -eq 23 -and $result.PhysicalFiles -eq 15 -and
 $result.PhysicalInventories -eq 5) 'all 23 objects, 15 files and five inventories read'
Check ($result.R2PolicyEvaluated -and $result.R2FixtureVerdict -ceq 'BLOCKED_WITH_EVIDENCE') 'frozen R2 ACL/evidence policy invoked'
Check ($result.Code -ceq 'HISTORICAL_PIN_MISMATCH_IN_DISPOSABLE_FIXTURE') 'synthetic bytes do not match R2 historical file pins'
Check ($before -ceq $after) 'read-only observer preserved file bytes and DACLs'
[IO.File]::WriteAllText((FixturePath $root 'C:\ProgramData\F2-G1-Icacls\unexpected.tmp'),'synthetic extra child')
$extra=Invoke-F2G1LT4Fixture -FixtureRoot $root
Check ($extra.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and
 $extra.Code -ceq 'INVENTORY_COUNT_MISMATCH') 'extra child blocked by physical inventory'
$bad=Invoke-F2G1LT4Fixture -FixtureRoot (Join-Path $env:RUNNER_TEMP 'other-folder')
Check ($bad.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and $bad.ProtectedReads -eq 0) 'nonfixture target rejected'
$entry=Join-Path $PSScriptRoot 'Invoke-F2G1LT4.ReadOnly.ps1'
$output=@(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $entry)
$j=($output -join [Environment]::NewLine)|ConvertFrom-Json
Check ($LASTEXITCODE -eq 2 -and $j.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and
 $j.ProtectedReads -eq 0) 'default CLI refuses protected host execution'
Write-Output ('LT4_ASSERTIONS='+$script:Assertions+' FAILURES='+$script:Failures)
if($script:Failures -ne 0){exit 1}
exit 0

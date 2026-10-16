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

# Host activation is a source-review candidate, NOT an owner execution grant.
$hostCli=Join-Path $PSScriptRoot 'Invoke-F2G1LT4.FixedHostC.ReadOnly.ps1'
$tokens=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($hostCli,[ref]$tokens,[ref]$parseErrors)
Check ($parseErrors.Count -eq 0) 'fixed-host owner entrypoint parses under PS5.1'
$hostSource=[IO.File]::ReadAllText($hostCli)
Check ($hostSource.Contains('InspectFixedHostC') -and
  $hostSource.Contains('ReviewedAdapterSha256') -and
  $hostSource.Contains('ExpectedComputerName') -and
  $hostSource.Contains('ExpectedUserSid') -and
  -not $hostSource.Contains('SyntheticFixtureRoot') -and
  -not $hostSource.Contains('OwnerAuthorizationReference')) 'operational command has no caller-selected object paths or grant URL'
$noargs=@(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hostCli)
$noargsCode=$LASTEXITCODE
$noargsStatus=($noargs -join [Environment]::NewLine)|ConvertFrom-Json
Check ($noargsCode -eq 2 -and $noargsStatus.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and
  $noargsStatus.ProtectedReads -eq 0) 'new host CLI default denies with zero reads'
# Regression: PS5.1 binds a mandatory switch with :$false to the Host
# parameter set. Use valid machine/account/module identities so the blocked
# result must come from the FALSE switch branch, never from host preflight.
$ciIdentity=[Security.Principal.WindowsIdentity]::GetCurrent()
try {$ciSid=[string]$ciIdentity.User.Value}finally{$ciIdentity.Dispose()}
$ciModuleHash=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'F2G1LT4.ReadOnlyAdapter.psm1') -Algorithm SHA256).Hash
# powershell.exe -File marshals switch values as strings on Windows PS5.1.
# -EncodedCommand executes native PowerShell parameter binding INSIDE the child.
$probe="& '$($hostCli.Replace("'","''"))' -InspectFixedHostC:`$false -ExpectedComputerName '$([Environment]::MachineName)' -ExpectedUserSid '$ciSid' -ReviewedAdapterSha256 '$ciModuleHash'"
$probeEncoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($probe))
$falseOptIn=@(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $probeEncoded)
$falseOptInCode=$LASTEXITCODE
$falseResult=($falseOptIn -join [Environment]::NewLine)|ConvertFrom-Json
Check ($falseOptInCode -eq 2 -and
  $falseResult.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and
  $falseResult.Code -ceq 'HOST_ADAPTER_EXECUTION_NOT_AUTHORIZED' -and
  $falseResult.ProtectedReads -eq 0 -and
  $falseResult.HostAttestation -ceq 'NOT_PERFORMED' -and
  -not $falseResult.HostAccessEnabled) 'false-valued host switch never calls protected reader, even with matching identity and module hash'

$hash='0'*64
$cliOutput=@(& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hostCli -InspectFixedHostC -ExpectedComputerName 'DO-NOT-READ-HOST' -ExpectedUserSid 'S-1-5-21-1-2-3-1001' -ReviewedAdapterSha256 $hash)
$cliExit=$LASTEXITCODE
$cliResult=($cliOutput -join [Environment]::NewLine)|ConvertFrom-Json
Check ($cliExit -eq 2 -and $cliResult.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and
  $cliResult.Code -ceq 'HOST_RUN_CONTEXT_REJECTED' -and
  -not $cliResult.ProtectedAccessAttempted) 'host CLI fails closed before physical I/O in GitHub CI'
$direct=Invoke-F2G1LT4OwnerHostReadOnly -ExpectedComputerName 'DO-NOT-READ-HOST' -ExpectedUserSid 'S-1-5-21-1-2-3-1001' -ReviewedAdapterSha256 $hash
Check ($direct.Verdict -ceq 'BLOCKED_WITH_EVIDENCE' -and
  $direct.Code -ceq 'HOST_RUN_CONTEXT_REJECTED' -and
  -not $direct.ProtectedAccessAttempted) 'direct module host invocation denies in CI'

Write-Output ('LT4_ASSERTIONS='+$script:Assertions+' FAILURES='+$script:Failures)
if($script:Failures -ne 0){exit 1}
exit 0

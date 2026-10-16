[CmdletBinding()]
param(
    [ValidateSet('Standard','FilteredLimited','Elevated','FullAdministrator','System','HighIntegrity','Impersonated','Privileged','Unknown')]
    [string]$MockTokenProfile='Standard',
    [ValidateSet('None','Missing','WrongHash','Reparse','InvalidAcl','IdentityDrift','ExtraChild','MissingChild','DuplicateObject','CaseAlias')]
    [string]$SyntheticFault='None'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# An inert in-memory demonstration, not a host probe or authenticated CI gate.
# Requiring hosted Windows CI is an operational guard ONLY; environment metadata is spoofable.
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:GITHUB_REPOSITORY -cne 'publiomcko-cloud/procedural-sandbox-simulation'){
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:CI_PS51_MOCK_ONLY')
    exit 2
}
try {
    $module=Join-Path $PSScriptRoot 'F2G1LT1.Synthetic.psm1'
    Import-Module $module -Force -ErrorAction Stop
    $fixture=New-F2G1LT1SyntheticFixture -MockTokenProfile $MockTokenProfile
    switch -CaseSensitive ($SyntheticFault) {
        'Missing'         {$fixture.Objects[8].Exists=$false}
        'WrongHash'       {$fixture.Objects[8].Body='wrong-mock-content'}
        'Reparse'         {$fixture.Objects[3].Reparse=$true}
        'InvalidAcl'      {$fixture.Objects[3].AclMatches=$false}
        'IdentityDrift'   {$fixture.Objects[8].After='different-mock-identity'}
        'ExtraChild'      {$fixture.Inventories[2].Children+=@('unexpected.bin')}
        'MissingChild'    {$fixture.Inventories[2].Children=@()}
        'DuplicateObject' {$fixture.Objects[1].Path=$fixture.Objects[0].Path}
        'CaseAlias'       {$fixture.Objects[8].Path=$fixture.Objects[8].Path.ToUpperInvariant()}
    }
    $result=Invoke-F2G1LT1Synthetic -Fixture $fixture
    $out=ConvertTo-Json -InputObject $result -Depth 5 -Compress
    if($out.Length -gt 4096){throw 'MOCK_REPORT_TOO_LARGE'}
    [Console]::Out.WriteLine($out)
    if($result.Verdict -ceq 'SYNTHETIC_FIXTURE_PASS'){exit 0}
    exit 2
} catch {
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:INERT_MOCK_FAILURE')
    exit 2
}

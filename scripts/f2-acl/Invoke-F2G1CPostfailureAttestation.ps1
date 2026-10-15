[CmdletBinding(DefaultParameterSetName='None')]
param(
    [Parameter(Mandatory,ParameterSetName='Live')]
    [switch]$Live,

    [Parameter(Mandatory,ParameterSetName='Live')]
    [ValidateNotNullOrEmpty()]
    [string]$OwnerAuthorizationReference,

    [Parameter(Mandatory,ParameterSetName='Fixture')]
    [ValidateNotNullOrEmpty()]
    [string]$SyntheticFixtureRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE: Windows PowerShell 5.1 is required.')
    exit 64
}

if ($PSCmdlet.ParameterSetName -eq 'None') {
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE: choose -Live with a new owner authorization reference, or -SyntheticFixtureRoot for inert tests.')
    exit 64
}

$modulePath = Join-Path $PSScriptRoot 'F2G1CPostfailureAttestation.psm1'
try {
    Import-Module -Name $modulePath -Force -ErrorAction Stop
    if ($PSCmdlet.ParameterSetName -eq 'Live') {
        $result = Invoke-F2G1CPostfailureAttestation -Live -OwnerAuthorizationReference $OwnerAuthorizationReference
    }
    else {
        $result = Invoke-F2G1CPostfailureAttestation -SyntheticFixtureRoot $SyntheticFixtureRoot
    }
    $json = ConvertTo-Json -InputObject $result -Depth 12 -Compress
    if ($json.Length -gt 65536) {
        [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE: sanitized report exceeds the 64 KiB output bound.')
        exit 2
    }
    [Console]::Out.WriteLine($json)
    if ($result.Verdict -eq 'PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION' -or $result.Verdict -eq 'SYNTHETIC_FIXTURE_PASS') { exit 0 }
    exit 2
}
catch {
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE: inspector stopped before producing a complete report; error class=' + $_.Exception.GetType().Name)
    exit 2
}

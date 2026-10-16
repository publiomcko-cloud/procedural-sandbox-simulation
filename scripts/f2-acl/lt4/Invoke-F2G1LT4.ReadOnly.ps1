[CmdletBinding(DefaultParameterSetName='Status')]
param(
    [Parameter(Mandatory,ParameterSetName='Fixture')]
    [ValidateNotNullOrEmpty()][string]$SyntheticFixtureRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:PS51_REQUIRED')
    exit 2
}
try {
    Import-Module (Join-Path $PSScriptRoot 'F2G1LT4.ReadOnlyAdapter.psm1') -Force -ErrorAction Stop
    if($PSCmdlet.ParameterSetName -ceq 'Fixture'){
        $result=Invoke-F2G1LT4Fixture -FixtureRoot $SyntheticFixtureRoot
    } else {
        $result=Get-F2G1LT4HostReadiness
    }
    $json=ConvertTo-Json -InputObject $result -Depth 5 -Compress
    if($json.Length -gt 4096){throw 'REPORT_OVER_BOUNDS'}
    [Console]::Out.WriteLine($json)
    exit 2 # No LT4 operational/host PASS is possible through this entrypoint.
} catch {
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:LT4_READ_ONLY_ADAPTER_FAILED')
    exit 2
}

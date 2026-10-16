[CmdletBinding(DefaultParameterSetName='Readiness')]
param(
    [Parameter(Mandatory,ParameterSetName='Host')]
    [switch]$InspectFixedHostC,
    [Parameter(Mandatory,ParameterSetName='Host')]
    [ValidateNotNullOrEmpty()][string]$ExpectedComputerName,
    [Parameter(Mandatory,ParameterSetName='Host')]
    [ValidatePattern('^S-1-[0-9-]+$')][string]$ExpectedUserSid,
    [Parameter(Mandatory,ParameterSetName='Host')]
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ReviewedAdapterSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# CAUTION: Do not invoke -InspectFixedHostC without a NEW, explicit owner grant
# for the exact reviewed SHA, actual computer/account and this one operation.
# There is no caller-controlled object path, ACL repair or privilege elevation.
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:POWERSHELL_51_REQUIRED')
    exit 2
}
try {
    Import-Module (Join-Path $PSScriptRoot 'F2G1LT4.ReadOnlyAdapter.psm1') -Force -ErrorAction Stop
    if($PSCmdlet.ParameterSetName -ceq 'Host'){
        $result=Invoke-F2G1LT4OwnerHostReadOnly -ExpectedComputerName $ExpectedComputerName -ExpectedUserSid $ExpectedUserSid -ReviewedAdapterSha256 $ReviewedAdapterSha256
    } else {
        $result=Get-F2G1LT4HostReadiness
    }
    $json=ConvertTo-Json -InputObject $result -Compress -Depth 4
    if($json.Length -gt 2048){throw 'BOUNDED_REPORT_REQUIRED'}
    [Console]::Out.WriteLine($json)
    if($result.Verdict -ceq 'PASS_READ_ONLY_C_POSTFAILURE_ATTESTATION'){exit 0}
    exit 2
} catch {
    # No exception text, stack, path, account SID or raw ACL is emitted.
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:FIXED_HOST_READ_FAILED_CLOSED')
    exit 2
}

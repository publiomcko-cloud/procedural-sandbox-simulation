[CmdletBinding()]
param([switch]$Describe)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Source-only interface. No arbitrary path, no Live, no grant reference.
if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1){
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:POWERSHELL_51_REQUIRED')
    exit 2
}
try {
    Import-Module (Join-Path $PSScriptRoot 'F2G1LT3.Readiness.psm1') -Force -ErrorAction Stop
    if($Describe){
        $contract=Get-F2G1LT3ReferenceContract
        $result=[pscustomobject]@{
            Schema='f2-g1-lt3-source-only-description-v1'
            Verdict='BLOCKED_WITH_EVIDENCE'
            Code='REFERENCE_DESCRIBED_BUT_HOST_READ_NOT_AUTHORIZED'
            ProtectedReads=0
            HostAttestation='NOT_PERFORMED'
            ExpectedObjects=$contract.ObjectCount
            ExpectedFiles=$contract.FileCount
            ExpectedDirectories=$contract.DirectoryCount
            ExpectedInventories=$contract.InventoryCount
        }
    } else {$result=Get-F2G1LT3Readiness}
    $json=ConvertTo-Json -InputObject $result -Compress -Depth 4
    if($json.Length -gt 2048){throw 'OUTPUT_BOUNDS_EXCEEDED'}
    [Console]::Out.WriteLine($json)
    exit 2 # Always blocked, including -Describe.
} catch {
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:READINESS_SOURCE_ONLY_FAILED')
    exit 2
}

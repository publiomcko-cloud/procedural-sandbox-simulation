[CmdletBinding()]
param(
    [Parameter(Mandatory,Position=0)]
    [ValidatePattern('^[0-9a-f]{32}$')]
    [string]$CaptureId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$expectedPath = Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'F2-G1-Icacls\scripts\f2-acl') 'Invoke-F2IcaclsProtectedCoordinator.ps1'
if (-not [string]::Equals([IO.Path]::GetFullPath($PSCommandPath),[IO.Path]::GetFullPath($expectedPath),[StringComparison]::OrdinalIgnoreCase) -or $args.Count -ne 0) {
    [Console]::Error.WriteLine('F2_ICACLS_STAGE:ProtectedCoordinatorPathRejected')
    exit 2
}

try {
    Import-Module (Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1') -Force -ErrorAction Stop
    $result = Invoke-F2IcaclsProtectedCoordinator -CaptureId $CaptureId
    if (-not $result.Success) { exit 1 }
    exit 0
}
catch {
    [Console]::Error.WriteLine('F2_ICACLS_STAGE:ProtectedCoordinatorFailure')
    exit 1
}

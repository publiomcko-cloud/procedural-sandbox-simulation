param(
    [string]$CaptureId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failureExitCode = 1
$failureStage = 'ProtectedCoordinatorFailure'
try {
    $expectedPath = Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'F2-G1-Icacls\scripts\f2-acl') 'Invoke-F2IcaclsProtectedCoordinator.ps1'
    if (-not [string]::Equals([IO.Path]::GetFullPath($PSCommandPath),[IO.Path]::GetFullPath($expectedPath),[StringComparison]::OrdinalIgnoreCase)) {
        $failureExitCode = 2
        $failureStage = 'ProtectedCoordinatorPathRejected'
        throw 'ProtectedCoordinatorPathRejected.'
    }
    $unboundArguments = @($MyInvocation.UnboundArguments)
    if ($unboundArguments.Count -ne 0) {
        $failureExitCode = 2
        $failureStage = 'ProtectedCoordinatorArgumentsRejected'
        throw 'ProtectedCoordinatorArgumentsRejected.'
    }
    if ([string]$CaptureId -notmatch '^[0-9a-f]{32}$') {
        $failureExitCode = 2
        $failureStage = 'ProtectedCoordinatorCaptureIdRejected'
        throw 'ProtectedCoordinatorCaptureIdRejected.'
    }
    Import-Module (Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1') -Force -ErrorAction Stop
    $result = Invoke-F2IcaclsProtectedCoordinator -CaptureId $CaptureId
    if (-not $result.Success) { exit 1 }
    exit 0
}
catch {
    [Console]::Error.WriteLine(('F2_ICACLS_STAGE:' + $failureStage))
    exit $failureExitCode
}

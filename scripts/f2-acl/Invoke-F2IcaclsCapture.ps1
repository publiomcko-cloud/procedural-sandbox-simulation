param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failureExitCode = 1
$failureStage = 'LauncherFailure'
try {
    $unboundArguments = @($MyInvocation.UnboundArguments)
    if ($unboundArguments.Count -ne 0) {
        $failureExitCode = 2
        $failureStage = 'RuntimeArgumentsRejected'
        throw 'RuntimeArgumentsRejected.'
    }
    Import-Module (Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1') -Force -ErrorAction Stop
    $result = Invoke-F2IcaclsCaptureLauncher
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 8 -Compress))
    if (-not $result.Success) { exit 1 }
    exit 0
}
catch {
    [Console]::Error.WriteLine(('F2_ICACLS_STAGE:' + $failureStage))
    exit $failureExitCode
}

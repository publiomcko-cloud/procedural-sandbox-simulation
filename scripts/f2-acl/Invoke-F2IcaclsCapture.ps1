[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($args.Count -ne 0) {
    [Console]::Error.WriteLine('F2_ICACLS: runtime arguments are not accepted.')
    exit 2
}

try {
    Import-Module (Join-Path $PSScriptRoot 'F2AclIcacls.Runtime.psm1') -Force -ErrorAction Stop
    $result = Invoke-F2IcaclsCaptureLauncher
    [Console]::Out.WriteLine(($result | ConvertTo-Json -Depth 8 -Compress))
    if (-not $result.Success) { exit 1 }
    exit 0
}
catch {
    [Console]::Error.WriteLine('F2_ICACLS_STAGE:LauncherFailure')
    exit 1
}

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'WINDOWS_POWERSHELL_51_REQUIRED' }
$paths = @(
    (Join-Path $PSScriptRoot 'Test-F2G1SecondFailureReadOnly.ps1'),
    (Join-Path $PSScriptRoot 'Test-F2G1ReviewCheckoutIdentity.ps1'),
    (Join-Path $PSScriptRoot 'New-F2G1FailureEvidenceManifest.ps1'),
    'C:\Dev\f2-g1-protected-updater-source\scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'
)
foreach ($path in $paths) {
    $tokens = $null
    $errors = $null
    $null = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { throw ('PARSE_FAILED:' + [IO.Path]::GetFileName($path)) }
    [Console]::Out.WriteLine(('PASS:Parser:{0}' -f [IO.Path]::GetFileName($path)))
}
[Console]::Out.WriteLine('ParsedFileCount=4')
[Console]::Out.WriteLine('Result=PS51_PARSE_SWEEP_PASSED')

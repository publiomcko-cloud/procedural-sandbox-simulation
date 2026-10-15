[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SyntheticFixtureRoot,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedNativeSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedScopeSha256,
    [switch]$AttemptReplacement,
    [switch]$InjectIdentityDrift
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'WINDOWS_POWERSHELL_51_REQUIRED' }
    if ($env:OS -ne 'Windows_NT') { throw 'WINDOWS_ONLY' }
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $full = [IO.Path]::GetFullPath($SyntheticFixtureRoot).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($full) -cne $temp -or [IO.Path]::GetFileName($full) -notmatch '^F2G1-R3Handle-[0-9a-fA-F-]{36}$') { throw 'TEMP_FIXTURE_ONLY' }
    $root = Split-Path -Parent $MyInvocation.MyCommand.Path
    $native = Join-Path $root 'F2G1R3.TempHandleProbe.cs'
    $scope = Join-Path $root 'F2G1R3.FixedScope.json'
    $actualNative = (Get-FileHash -LiteralPath $native -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    $actualScope = (Get-FileHash -LiteralPath $scope -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if ($actualNative -cne $ExpectedNativeSha256.ToLowerInvariant() -or $actualScope -cne $ExpectedScopeSha256.ToLowerInvariant()) { throw 'EXECUTABLE_OR_SCOPE_DIGEST_MISMATCH' }
    $scopeSpec = Get-Content -LiteralPath $scope -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ($scopeSpec.Schema -cne 'f2-g1-r3-fixed-c-scope-design-v1' -or $scopeSpec.LivePermitted -ne $false -or $scopeSpec.Mode -cne 'NON_ELEVATED_READ_ONLY_ONLY' -or @($scopeSpec.PackageMembers).Count -ne 7 -or @($scopeSpec.MailboxMembers).Count -ne 7) { throw 'FIXED_SCOPE_CONTRACT_REJECTED' }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or @($identity.Groups|Where-Object{$_.Value -eq 'S-1-5-32-544'}).Count -gt 0) { throw 'NON_ADMINISTRATOR_REQUIRED' }
    Add-Type -Path $native -ErrorAction Stop
    $probe = [F2G1R3.TempHandleProbe]::ProbeFixture($full,[bool]$AttemptReplacement,[bool]$InjectIdentityDrift)
    if (-not $probe.StartsWith('TEMP_HANDLE_FIXTURE_PASS|SHA256=')) { throw 'INCOMPLETE_NATIVE_RESULT' }
    [Console]::Out.WriteLine($probe)
    exit 0
} catch {
    # Only error family is reported. Never publish source, host ACL/SID, path or SDDL.
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:R3_SOURCE_ONLY:' + $_.Exception.GetType().Name)
    exit 2
}

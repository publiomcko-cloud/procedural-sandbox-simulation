[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SyntheticFixtureRoot,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedNativeSha256,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedScopeSha256,
    [switch]$AttemptReplacement,
    [switch]$InjectIdentityDrift,
    [switch]$SimulatePrivilegedToken,
    [ValidateRange(0,10)][int]$SimulateDelaySeconds=0
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$nativeHandle=$null
$scopeHandle=$null
function Read-HeldBytes {
    param([IO.FileStream]$Handle,[int]$Maximum)
    if ($Handle.Length -le 0 -or $Handle.Length -gt $Maximum) { throw 'SOURCE_LENGTH_REJECTED' }
    $data=New-Object byte[] ([int]$Handle.Length)
    $position=0
    while ($position -lt $data.Length) {
        $read=$Handle.Read($data,$position,$data.Length-$position)
        if ($read -le 0) { throw 'INCOMPLETE_SOURCE_READ' }
        $position+=$read
    }
    if ($Handle.ReadByte() -ne -1) { throw 'SOURCE_LENGTH_CHANGED' }
    return ,$data
}
function Sha256-Hex {
    param([byte[]]$Data)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Data))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
try {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or $env:OS -ne 'Windows_NT') { throw 'WINDOWS_PS51_ONLY' }
    # The input is NEVER used to open the fixture. Native code opens only a
    # literal C: volume root, then Users/Public/one GUID via held no-follow handles.
    $parent='C:\Users\Public'
    $name=[IO.Path]::GetFileName($SyntheticFixtureRoot.TrimEnd('\'))
    $accepted=$parent+'\'+$name
    if ($name -notmatch '^F2G1-R3Handle-[0-9a-fA-F-]{36}$') { throw 'FIXED_FIXTURE_PARENT_ONLY_BAD_LEAF' }
    if (-not [string]::Equals($SyntheticFixtureRoot,$accepted,[StringComparison]::OrdinalIgnoreCase)) { throw 'FIXED_FIXTURE_PARENT_ONLY_MISMATCH' }
    $root=Split-Path -Parent $MyInvocation.MyCommand.Path
    $native=Join-Path $root 'F2G1R3.TempHandleProbe.cs'
    $scope=Join-Path $root 'F2G1R3.FixedScope.json'
    $nativeHandle=[IO.FileStream]::new($native,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    $scopeHandle=[IO.FileStream]::new($scope,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    # The very same held byte arrays are hashed, decoded and passed to Add-Type.
    # Caller hashes are synthetic test assertions, NEVER owner authorization.
    $nativeBytes=Read-HeldBytes -Handle $nativeHandle -Maximum 131072
    $scopeBytes=Read-HeldBytes -Handle $scopeHandle -Maximum 16384
    $actualNative=Sha256-Hex $nativeBytes
    $actualScope=Sha256-Hex $scopeBytes
    if ($actualNative -cne $ExpectedNativeSha256.ToLowerInvariant() -or
        $actualScope -cne $ExpectedScopeSha256.ToLowerInvariant()) { throw 'SOURCE_OR_SCOPE_HASH_MISMATCH' }
    # This pin establishes canonical design-time scope shape, not a trusted
    # runtime identity or an authenticated owner's consent.
    if ($actualScope -cne '9dcf97a9ad2636a28616278bc33d390443aca12ce3f930cbbcbcf8926fc800a1') { throw 'NONCANONICAL_FIXED_SCOPE' }
    $utf8=[Text.UTF8Encoding]::new($false,$true)
    $scopeText=$utf8.GetString($scopeBytes)
    $scopeSpec=ConvertFrom-Json -InputObject $scopeText -ErrorAction Stop
    if ($scopeSpec.Schema -cne 'f2-g1-r3-fixed-c-scope-design-v1' -or
        $scopeSpec.LivePermitted -ne $false -or
        $scopeSpec.Mode -cne 'SYNTHETIC_FIXTURE_ONLY' -or
        $scopeSpec.TokenGate -cne 'SIMULATED_NEGATIVE_TEST_ONLY' -or
        $scopeSpec.FixtureTrustedParent -cne $parent) { throw 'FIXED_SCOPE_CONTRACT_REJECTED' }
    if ($SimulatePrivilegedToken) { throw 'SIMULATED_PRIVILEGED_TOKEN_REJECTED' }
    if ($SimulateDelaySeconds -gt 0) { Start-Sleep -Seconds $SimulateDelaySeconds }
    $code=$utf8.GetString($nativeBytes)
    Add-Type -TypeDefinition $code -Language CSharp -ErrorAction Stop
    $probe=[F2G1R3.TempHandleProbe]::ProbeFixture($SyntheticFixtureRoot,[bool]$AttemptReplacement,[bool]$InjectIdentityDrift)
    if (-not $probe.StartsWith('TEMP_HANDLE_FIXTURE_PASS|SHA256=')) { throw 'INCOMPLETE_NATIVE_RESULT' }
    [Console]::Out.WriteLine($probe)
    exit 0
} catch {
    # This entrypoint NEVER reports a successful protected-host result.
    # Avoid raw stack traces, paths, SDDL, tokens or source in error output.
    $allowed=@('FIXED_FIXTURE_PARENT_ONLY','SOURCE_OR_SCOPE_HASH_MISMATCH','NONCANONICAL_FIXED_SCOPE','SIMULATED_PRIVILEGED_TOKEN_REJECTED','RELATIVE_DIRECTORY_OPEN_FAILED','RELATIVE_NOFOLLOW_OPEN_FAILED','REPARSE_POINT_DENIED','UNEXPECTED_OR_MISSING_CHILD','FILE_IDENTITY_OR_ACL_CHANGED','DIR_IDENTITY_ACL_OR_INVENTORY_CHANGED','INJECTED_FILE_IDENTITY_DRIFT','PAYLOAD_INCOMPLETE')
    $errorCode='UNCLASSIFIED_BLOCKED'
    foreach($candidate in $allowed) {if ($_.Exception.ToString().Contains($candidate)) {$errorCode=$candidate;break}}
    $stage='NONE'
    if ($_.Exception.ToString().Contains('FIXED_FIXTURE_PARENT_ONLY_BAD_LEAF')) {$stage='BAD_LEAF'}
    elseif ($_.Exception.ToString().Contains('FIXED_FIXTURE_PARENT_ONLY_MISMATCH')) {$stage='PARENT_MISMATCH'}
    [Console]::Error.WriteLine('BLOCKED_WITH_EVIDENCE:R3_1_SYNTHETIC_ONLY:'+$errorCode+';STAGE='+$stage)
    exit 2
} finally {
    if ($null -ne $scopeHandle) { $scopeHandle.Dispose() }
    if ($null -ne $nativeHandle) { $nativeHandle.Dispose() }
}

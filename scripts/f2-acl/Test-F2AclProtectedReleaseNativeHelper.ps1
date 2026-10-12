$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:assertions = 0
function Assert-F2NativeHelper {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw "ASSERTION_FAILED: $Message" }
}

$updaterPath = Join-Path $PSScriptRoot 'Invoke-F2ProtectedReleaseUpdate.ps1'
if (-not [IO.File]::Exists($updaterPath)) { throw 'UPDATER_SOURCE_MISSING' }
$updaterText = [IO.File]::ReadAllText($updaterPath)
$nativeBlocks = [regex]::Matches($updaterText, "(?s)Add-Type\s+-TypeDefinition\s+@'\r?\n(.*?)\r?\n'@\s+-ErrorAction\s+Stop")
Assert-F2NativeHelper ($nativeBlocks.Count -eq 1) 'exactly one production native helper block is present'
$nativeSource = $nativeBlocks[0].Groups[1].Value

# Compile the exact production C# here-string. This test does not invoke the
# production PowerShell updater or any update/transaction entrypoint.
Add-Type -TypeDefinition $nativeSource -ErrorAction Stop
Assert-F2NativeHelper ($null -ne ('F2Update.NativeOps' -as [type])) 'production native helper compiles and loads'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
try { $sid = $identity.User.Value } finally { $identity.Dispose() }
Assert-F2NativeHelper ($sid -match '^S-1-5-') 'current ordinary Windows account SID is available'

$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixtureRoot = Join-Path $tempRoot ('F2-NativeHelper-' + [guid]::NewGuid().ToString('N'))
$fixtureDirectory = Join-Path $fixtureRoot 'protected-child'
$fixtureFile = Join-Path $fixtureDirectory 'create-new.bin'
$createdRoot = $false
$cleanupErrors = New-Object 'System.Collections.Generic.List[string]'
try {
    Assert-F2NativeHelper (-not [IO.Directory]::Exists($fixtureRoot) -and -not [IO.File]::Exists($fixtureRoot)) 'fixture path is create-new'
    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    $createdRoot = $true
    $canonicalRoot = [IO.Path]::GetFullPath($fixtureRoot)
    Assert-F2NativeHelper ($canonicalRoot.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) 'fixture is strictly below TEMP'
    Assert-F2NativeHelper (([IO.File]::GetAttributes($fixtureRoot) -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'TEMP fixture root is not a reparse point'

    $directorySddl = 'O:' + $sid + 'G:' + $sid + 'D:P(A;OICI;FA;;;' + $sid + ')'
    [F2Update.NativeOps]::CreateDirectory($fixtureDirectory, $directorySddl)
    Assert-F2NativeHelper ([IO.Directory]::Exists($fixtureDirectory)) 'native helper creates the protected directory'
    $directorySddlReadback = [F2Update.NativeOps]::GetSddl($fixtureDirectory)
    $directoryDescriptor = New-Object Security.AccessControl.RawSecurityDescriptor($directorySddlReadback)
    Assert-F2NativeHelper ($directoryDescriptor.Owner.Value -eq $sid) 'directory owner matches the ordinary test account'
    Assert-F2NativeHelper (($directoryDescriptor.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0) 'directory DACL is protected'
    Assert-F2NativeHelper ($directoryDescriptor.DiscretionaryAcl.Count -eq 1) 'directory DACL contains only the fixture account grant'
    $directoryAce = [Security.AccessControl.QualifiedAce]$directoryDescriptor.DiscretionaryAcl[0]
    Assert-F2NativeHelper ($directoryAce.SecurityIdentifier.Value -eq $sid -and $directoryAce.AccessMask -eq 0x001F01FF) 'directory ACE is the exact fixture-account full-control grant'
    $inheritMask = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
    Assert-F2NativeHelper (([int]$directoryAce.AceFlags -band $inheritMask) -eq $inheritMask) 'directory ACE has the requested object/container inheritance flags'

    $directoryCollisionRejected = $false
    try { [F2Update.NativeOps]::CreateDirectory($fixtureDirectory, $directorySddl) }
    catch { $directoryCollisionRejected = $true }
    Assert-F2NativeHelper $directoryCollisionRejected 'directory creation rejects an existing path'

    $fileSddl = 'O:' + $sid + 'G:' + $sid + 'D:P(A;;FA;;;' + $sid + ')'
    $expectedBytes = [Text.Encoding]::UTF8.GetBytes('F2 native helper TEMP fixture')
    [F2Update.NativeOps]::CreateNew($fixtureFile, $expectedBytes, $fileSddl)
    Assert-F2NativeHelper ([IO.File]::Exists($fixtureFile)) 'native helper creates a new file'
    $actualBytes = [IO.File]::ReadAllBytes($fixtureFile)
    Assert-F2NativeHelper ([Convert]::ToBase64String($actualBytes) -ceq [Convert]::ToBase64String($expectedBytes)) 'native helper writes the exact fixture bytes'
    $fileSddlReadback = [F2Update.NativeOps]::GetSddl($fixtureFile)
    $fileDescriptor = New-Object Security.AccessControl.RawSecurityDescriptor($fileSddlReadback)
    Assert-F2NativeHelper ($fileDescriptor.Owner.Value -eq $sid) 'file owner matches the ordinary test account'
    Assert-F2NativeHelper (($fileDescriptor.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0) 'file DACL is protected'
    Assert-F2NativeHelper ($fileDescriptor.DiscretionaryAcl.Count -eq 1) 'file DACL contains only the fixture account grant'
    $fileAce = [Security.AccessControl.QualifiedAce]$fileDescriptor.DiscretionaryAcl[0]
    Assert-F2NativeHelper ($fileAce.SecurityIdentifier.Value -eq $sid -and $fileAce.AccessMask -eq 0x001F01FF -and $fileAce.AceFlags -eq [Security.AccessControl.AceFlags]::None) 'file ACE is the exact non-inheriting fixture-account full-control grant'

    $fileCollisionRejected = $false
    try { [F2Update.NativeOps]::CreateNew($fixtureFile, $expectedBytes, $fileSddl) }
    catch { $fileCollisionRejected = $true }
    Assert-F2NativeHelper $fileCollisionRejected 'file creation rejects an existing path'
}
finally {
    if ([IO.File]::Exists($fixtureFile)) {
        try {
            if (([IO.File]::GetAttributes($fixtureFile) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'fixture file unexpectedly became a reparse point' }
            [IO.File]::Delete($fixtureFile)
        } catch { [void]$cleanupErrors.Add('fixture file cleanup failed') }
    }
    if ([IO.Directory]::Exists($fixtureDirectory)) {
        try {
            if (([IO.File]::GetAttributes($fixtureDirectory) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'fixture directory unexpectedly became a reparse point' }
            [IO.Directory]::Delete($fixtureDirectory, $false)
        } catch { [void]$cleanupErrors.Add('fixture child cleanup failed') }
    }
    if ($createdRoot -and [IO.Directory]::Exists($fixtureRoot)) {
        try {
            if (([IO.File]::GetAttributes($fixtureRoot) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'fixture root unexpectedly became a reparse point' }
            [IO.Directory]::Delete($fixtureRoot, $false)
        } catch { [void]$cleanupErrors.Add('fixture root cleanup failed') }
    }
}

if ($cleanupErrors.Count -gt 0) { throw ('TEMP_FIXTURE_CLEANUP_FAILED: ' + ($cleanupErrors -join ',')) }
Write-Output ("F2NativeHelperAssertions={0};Failures=0;TempCleanup=PASS" -f $script:assertions)

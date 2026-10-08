[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\inspect-zip.ps1')

$script:Assertions = 0
$script:Failures = [Collections.Generic.List[string]]::new()
$testBase = Join-Path ([IO.Path]::GetTempPath()) ('p0-1-f1-tests-' + [guid]::NewGuid().ToString())
[void][IO.Directory]::CreateDirectory($testBase)

function Assert([bool]$Condition, [string]$Message) {
    $script:Assertions++
    if (-not $Condition) { $script:Failures.Add($Message); throw "ASSERTION FAILED: $Message" }
}
function New-Root {
    $path = Join-Path ([IO.Path]::GetTempPath()) ('p0-1-f1-' + [guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($path)
    return $path
}
function New-Zip([string]$Name, [scriptblock]$Build) {
    $path = Join-Path $testBase $Name
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
    try { & $Build $zip } finally { $zip.Dispose() }
    return $path
}
function Add-Entry($Zip, [string]$Name, [string]$Content, [int]$Attributes = 0) {
    $entry = $Zip.CreateEntry($Name)
    $entry.ExternalAttributes = $Attributes
    $writer = [IO.StreamWriter]::new($entry.Open())
    try { $writer.Write($Content) } finally { $writer.Dispose() }
}
function Set-DeclaredUncompressedSize([string]$Path, [uint32]$Size) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $local = -1
    $central = -1
    for ($i = 0; $i -le $bytes.Length - 4; $i++) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x03 -and $bytes[$i+3] -eq 0x04) { $local = $i }
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x01 -and $bytes[$i+3] -eq 0x02) { $central = $i; break }
    }
    if ($local -lt 0 -or $central -lt 0) { throw 'Synthetic ZIP header not found.' }
    [Array]::Copy([BitConverter]::GetBytes($Size), 0, $bytes, $local + 22, 4)
    [Array]::Copy([BitConverter]::GetBytes($Size), 0, $bytes, $central + 24, 4)
    [IO.File]::WriteAllBytes($Path, $bytes)
}
function Corrupt-CompressedPayload([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $nameLength = [BitConverter]::ToUInt16($bytes, 26)
    $extraLength = [BitConverter]::ToUInt16($bytes, 28)
    $compressedLength = [BitConverter]::ToUInt32($bytes, 18)
    $payloadOffset = 30 + $nameLength + $extraLength
    for ($i = 0; $i -lt $compressedLength; $i++) { $bytes[$payloadOffset + $i] = 0 }
    [IO.File]::WriteAllBytes($Path, $bytes)
}
function Expect-Reject([string]$Label, [string]$ZipPath, [scriptblock]$Extra = {}) {
    $root = New-Root
    $before = @(Get-ChildItem -LiteralPath $root -Force).Count
    $rejected = $false
    try { & $Extra; Get-ZipPreflight $ZipPath $root -SkipDiskSpaceCheck | Out-Null } catch { $rejected = $true }
    Assert $rejected "$Label must fail preflight"
    Assert (@(Get-ChildItem -LiteralPath $root -Force).Count -eq $before) "$Label must leave output root empty"
    Remove-SafeInspectionRoot $root
}

try {
    $good = New-Zip 'good.zip' { param($z) Add-Entry $z 'folder/' ''; Add-Entry $z 'folder/readme.txt' 'safe payload'; Add-Entry $z 'top.txt' 'ok' }
    $goodRoot = New-Root
    $result = Invoke-SafeZipExtract $good $goodRoot -SkipDiskSpaceCheck
    Assert ($result.Entries.Count -eq 3) 'valid archive entry count'
    Assert ((Get-Content -Raw (Join-Path $goodRoot 'folder/readme.txt')) -eq 'safe payload') 'valid nested content'
    Assert ((Get-Content -Raw (Join-Path $goodRoot 'top.txt')) -eq 'ok') 'valid top-level content'
    Remove-SafeInspectionRoot $goodRoot

    foreach ($case in @(
        @{ Name='traversal'; Path='../escape.txt'; Content='bad' },
        @{ Name='absolute'; Path='/rooted.txt'; Content='bad' },
        @{ Name='backslash'; Path='folder\escape.txt'; Content='bad' },
        @{ Name='drive'; Path='C:/escape.txt'; Content='bad' },
        @{ Name='unc'; Path='//server/share/x'; Content='bad' },
        @{ Name='ads'; Path='safe.txt:stream'; Content='bad' },
        @{ Name='reserved'; Path='CON.txt'; Content='bad' },
        @{ Name='trailing-dot'; Path='bad./file'; Content='bad' },
        @{ Name='empty-component'; Path='a//b'; Content='bad' },
        @{ Name='non-nfc'; Path="e$([char]0x0301).txt"; Content='bad' }
    )) {
        $archive = New-Zip ($case.Name + '.zip') { param($z) Add-Entry $z $case.Path $case.Content }
        Expect-Reject $case.Name $archive
    }

    $duplicate = New-Zip 'duplicate.zip' { param($z) Add-Entry $z 'same.txt' '1'; Add-Entry $z 'same.txt' '2' }
    Expect-Reject 'duplicate names' $duplicate
    $caseCollision = New-Zip 'case.zip' { param($z) Add-Entry $z 'Alpha.txt' '1'; Add-Entry $z 'alpha.TXT' '2' }
    Expect-Reject 'case collision' $caseCollision
    $unicodeCollision = New-Zip 'unicode-collision.zip' { param($z) Add-Entry $z "é.txt" '1'; Add-Entry $z "e$([char]0x0301).txt" '2' }
    Expect-Reject 'Unicode normalization collision' $unicodeCollision

    $symlink = New-Zip 'symlink.zip' { param($z) $e=$z.CreateEntry('link'); $e.ExternalAttributes=([int](0xA000 -shl 16)); $w=[IO.StreamWriter]::new($e.Open()); $w.Write('../target'); $w.Dispose() }
    Expect-Reject 'Unix symlink' $symlink
    $reparse = New-Zip 'reparse.zip' { param($z) $e=$z.CreateEntry('junction'); $e.ExternalAttributes=0x400; $w=[IO.StreamWriter]::new($e.Open()); $w.Write('x'); $w.Dispose() }
    Expect-Reject 'DOS reparse point' $reparse
    $device = New-Zip 'device.zip' { param($z) $e=$z.CreateEntry('device'); $e.ExternalAttributes=([int](0x6000 -shl 16)); $w=[IO.StreamWriter]::new($e.Open()); $w.Dispose() }
    Expect-Reject 'Unix device' $device

    $prefixConflict = New-Zip 'prefix.zip' { param($z) Add-Entry $z 'node' 'file'; Add-Entry $z 'node/child.txt' 'child' }
    Expect-Reject 'file/directory prefix conflict' $prefixConflict
    $countZip = New-Zip 'count.zip' { param($z) Add-Entry $z 'one' '1'; Add-Entry $z 'two' '2'; Add-Entry $z 'three' '3' }
    $oldCount = $script:ZipLimits.MaxEntries
    try { $script:ZipLimits.MaxEntries = 2; Expect-Reject 'entry count cap' $countZip } finally { $script:ZipLimits.MaxEntries = $oldCount }
    $sizeZip = New-Zip 'large.zip' { param($z) Add-Entry $z 'large.bin' ('x' * 512) }
    $oldSize = $script:ZipLimits.MaxFileBytes
    try { $script:ZipLimits.MaxFileBytes = 128; Expect-Reject 'individual size cap' $sizeZip } finally { $script:ZipLimits.MaxFileBytes = $oldSize }
    $totalZip = New-Zip 'aggregate.zip' { param($z) Add-Entry $z 'a.bin' ('x' * 80); Add-Entry $z 'b.bin' ('y' * 80) }
    $oldTotal = $script:ZipLimits.MaxTotalBytes
    try { $script:ZipLimits.MaxTotalBytes = 128; Expect-Reject 'aggregate size cap' $totalZip } finally { $script:ZipLimits.MaxTotalBytes = $oldTotal }
    $ratioZip = New-Zip 'ratio.zip' { param($z) Add-Entry $z 'bomb.txt' ('a' * 10000) }
    Expect-Reject 'expansion ratio cap' $ratioZip

    $mismatchZip = New-Zip 'mismatch.zip' { param($z) Add-Entry $z 'mismatch.txt' 'claimed-size-mismatch' }
    Set-DeclaredUncompressedSize $mismatchZip 64
    $mismatchRoot = New-Root
    $rejected = $false
    try { Invoke-SafeZipExtract $mismatchZip $mismatchRoot -SkipDiskSpaceCheck | Out-Null } catch { $rejected = $true }
    Assert $rejected 'declared/actual size mismatch rejected during streaming'
    Assert (-not (Test-Path -LiteralPath (Join-Path $mismatchRoot 'mismatch.txt'))) 'mismatched file never published'
    Remove-SafeInspectionRoot $mismatchRoot

    $corruptZip = New-Zip 'corrupt.zip' { param($z) Add-Entry $z 'corrupt.txt' ('compressible data ' * 128) }
    Corrupt-CompressedPayload $corruptZip
    $corruptRoot = New-Root
    $rejected = $false
    try { Invoke-SafeZipExtract $corruptZip $corruptRoot -SkipDiskSpaceCheck | Out-Null } catch { $rejected = $true }
    Assert $rejected 'corrupted compressed stream rejected during extraction'
    Assert (-not (Test-Path -LiteralPath (Join-Path $corruptRoot 'corrupt.txt'))) 'corrupt file never published'
    Remove-SafeInspectionRoot $corruptRoot

    $existing = New-Root
    [IO.File]::WriteAllText((Join-Path $existing 'already.txt'), 'keep')
    $rejected = $false
    try { Get-ZipPreflight $good $existing -SkipDiskSpaceCheck | Out-Null } catch { $rejected = $true }
    Assert $rejected 'pre-existing output rejected'
    Assert ((Get-Content -Raw (Join-Path $existing 'already.txt')) -eq 'keep') 'pre-existing output preserved'
    Remove-SafeInspectionRoot $existing

    $outside = Join-Path $testBase ('not-temp-' + [guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($outside)
    $rejected = $false
    try { Remove-SafeInspectionRoot $outside } catch { $rejected = $true }
    Assert $rejected 'cleanup refuses incorrect root'
    Remove-Item -LiteralPath $outside -Force

    $linkRoot = New-Root
    $linkTarget = Join-Path $testBase ('link-target-' + [guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($linkTarget)
    $linkCreated = $false
    try { New-Item -ItemType Junction -Path (Join-Path $linkRoot 'link') -Target $linkTarget | Out-Null; $linkCreated = $true } catch { }
    if ($linkCreated) {
        $rejected = $false
        try { Remove-SafeInspectionRoot $linkRoot } catch { $rejected = $true }
        Assert $rejected 'cleanup refuses reparse point'
        Remove-Item -LiteralPath (Join-Path $linkRoot 'link') -Force
        Remove-SafeInspectionRoot $linkRoot
    } else {
        $script:Failures.Add('cleanup reparse-point test unavailable: symbolic-link creation was denied')
    }
    Remove-Item -LiteralPath $linkTarget -Force

    $escapeRoot = Join-Path $testBase 'not-a-guid-root'
    [void][IO.Directory]::CreateDirectory($escapeRoot)
    $rejected = $false
    try { Get-ZipPreflight $good $escapeRoot -SkipDiskSpaceCheck | Out-Null } catch { $rejected = $true }
    Assert $rejected 'destination containment root validation'
    Remove-Item -LiteralPath $escapeRoot -Force

    "Assertions: $script:Assertions"
    "Failures: $($script:Failures.Count)"
    if ($script:Failures.Count -gt 0) { $script:Failures | ForEach-Object { "FAIL: $_" }; exit 1 }
    exit 0
} catch {
    $script:Failures.Add($_.Exception.Message)
    "Assertions: $script:Assertions"
    "Failures: $($script:Failures.Count)"
    "FAIL: $($_.Exception.Message)"
    exit 1
} finally {
    if (Test-Path -LiteralPath $testBase) { Remove-Item -LiteralPath $testBase -Recurse -Force }
}

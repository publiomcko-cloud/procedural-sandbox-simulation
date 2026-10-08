[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\inspect-zip.ps1')

$script:Assertions = 0
$script:Failures = [Collections.Generic.List[string]]::new()
$script:TestCases = [Collections.Generic.List[string]]::new()
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
function Record-Test([string]$Label) {
    $script:TestCases.Add($Label)
}
function Expect-Reject([string]$Label, [string]$ZipPath, [string]$ExpectedDiagnostic, [switch]$CheckDiskSpace) {
    $root = New-Root
    try {
        $before = @(Get-ChildItem -LiteralPath $root -Force).Count
        $diagnostic = ''
        try {
            if ($CheckDiskSpace) { Get-ZipPreflight $ZipPath $root | Out-Null }
            else { Get-ZipPreflight $ZipPath $root -SkipDiskSpaceCheck | Out-Null }
        } catch { $diagnostic = $_.Exception.Message }
        Assert ($diagnostic.IndexOf($ExpectedDiagnostic, [StringComparison]::OrdinalIgnoreCase) -ge 0) "$Label expected diagnostic '$ExpectedDiagnostic'; got '$diagnostic'"
        Assert (@(Get-ChildItem -LiteralPath $root -Force).Count -eq $before) "$Label must leave output root empty"
        Record-Test $Label
    } finally { if (Test-Path -LiteralPath $root) { Remove-SafeInspectionRoot $root } }
}
function Expect-ExtractionReject([string]$Label, [string]$ZipPath, [string]$ExpectedPattern, [string]$TargetPath) {
    $root = New-Root
    try {
        $diagnostic = ''
        try { Invoke-SafeZipExtract $ZipPath $root -SkipDiskSpaceCheck | Out-Null } catch { $diagnostic = $_.Exception.Message }
        Assert ($diagnostic -match $ExpectedPattern) "$Label expected rejection matching '$ExpectedPattern'; got '$diagnostic'"
        Assert (-not (Test-Path -LiteralPath (Join-Path $root $TargetPath))) "$Label must not publish its final target"
        Record-Test $Label
    } finally { if (Test-Path -LiteralPath $root) { Remove-SafeInspectionRoot $root } }
}
function Expect-IdentityReject([string]$Label, [string]$Path, [long]$ExpectedBytes, [string]$ExpectedHash, [string]$ExpectedDiagnostic) {
    $diagnostic = ''
    try { Assert-ArchiveIdentity $Path $ExpectedBytes $ExpectedHash | Out-Null } catch { $diagnostic = $_.Exception.Message }
    Assert ($diagnostic.IndexOf($ExpectedDiagnostic, [StringComparison]::OrdinalIgnoreCase) -ge 0) "$Label expected diagnostic '$ExpectedDiagnostic'; got '$diagnostic'"
    Record-Test $Label
}

try {
    $good = New-Zip 'good.zip' { param($z) Add-Entry $z 'folder/' ''; Add-Entry $z 'folder/readme.txt' 'safe payload'; Add-Entry $z 'top.txt' 'ok' }
    $goodRoot = New-Root
    $result = Invoke-SafeZipExtract $good $goodRoot -SkipDiskSpaceCheck
    Assert ($result.Entries.Count -eq 3) 'valid archive entry count'
    Assert ((Get-Content -Raw (Join-Path $goodRoot 'folder/readme.txt')) -eq 'safe payload') 'valid nested content'
    Assert ((Get-Content -Raw (Join-Path $goodRoot 'top.txt')) -eq 'ok') 'valid top-level content'
    Record-Test 'valid files and directories extract'
    Remove-SafeInspectionRoot $goodRoot

    $goodBytes = (Get-Item -LiteralPath $good).Length
    $goodHash = (Get-FileHash -LiteralPath $good -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ((Assert-ArchiveIdentity $good $goodBytes $goodHash) -eq $goodHash) 'pinned identity checker accepts exact size and SHA-256'
    Record-Test 'archive identity accepts exact size and SHA-256'
    Expect-IdentityReject 'archive identity rejects wrong size' $good ($goodBytes + 1) $goodHash 'Archive size mismatch'
    Expect-IdentityReject 'archive identity rejects wrong SHA-256' $good $goodBytes ('0' * 64) 'Archive SHA-256 mismatch'
    $manifestRoot = New-Root
    $manifestOutput = Join-Path $testBase 'must-not-create-manifest.json'
    try {
        $manifestDiagnostic = ''
        try { & (Join-Path $PSScriptRoot '..\write-artifact-manifest.ps1') -ZipPath $good -ExtractedRoot $manifestRoot -OutputPath $manifestOutput } catch { $manifestDiagnostic = $_.Exception.Message }
        Assert ($manifestDiagnostic -like '*Archive size mismatch*') "manifest writer expected pinned-size rejection; got '$manifestDiagnostic'"
        Assert (-not (Test-Path -LiteralPath $manifestOutput)) 'manifest writer must not produce success evidence for unpinned bytes'
        Record-Test 'manifest writer refuses unpinned archive bytes'
    } finally { if (Test-Path -LiteralPath $manifestRoot) { Remove-SafeInspectionRoot $manifestRoot } }

    $oldArchiveLimit = $script:ZipLimits.MaxArchiveBytes
    try {
        $script:ZipLimits.MaxArchiveBytes = $goodBytes - 1
        Expect-Reject 'archive ZIP-size cap' $good 'Archive exceeds configured maximum ZIP size'
    } finally { $script:ZipLimits.MaxArchiveBytes = $oldArchiveLimit }

    $diskRoot = New-Root
    $diskDrive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($diskRoot))
    $oldMinimumFree = $script:ZipLimits.MinFreeBytes
    try {
        $script:ZipLimits.MinFreeBytes = $diskDrive.AvailableFreeSpace + 1
        Expect-Reject 'minimum free-disk-space gate' $good 'Insufficient free disk space' -CheckDiskSpace
    } finally { $script:ZipLimits.MinFreeBytes = $oldMinimumFree; Remove-SafeInspectionRoot $diskRoot }

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
        $expected = switch ($case.Name) {
            'traversal' { 'Empty or traversal component rejected' }
            'absolute' { 'Absolute or UNC path rejected' }
            'backslash' { 'Backslash path separator rejected' }
            'drive' { 'Drive-qualified path rejected' }
            'unc' { 'Absolute or UNC path rejected' }
            'ads' { 'Colon or alternate data stream rejected' }
            'reserved' { 'Reserved Windows device name rejected' }
            'trailing-dot' { 'Ambiguous trailing dot/space rejected' }
            'empty-component' { 'Empty or traversal component rejected' }
            'non-nfc' { 'Non-NFC Unicode component rejected' }
        }
        Expect-Reject $case.Name $archive $expected
    }

    $duplicate = New-Zip 'duplicate.zip' { param($z) Add-Entry $z 'same.txt' '1'; Add-Entry $z 'same.txt' '2' }
    Expect-Reject 'duplicate names' $duplicate 'Duplicate or case-insensitive path collision'
    $caseCollision = New-Zip 'case.zip' { param($z) Add-Entry $z 'Alpha.txt' '1'; Add-Entry $z 'alpha.TXT' '2' }
    Expect-Reject 'case collision' $caseCollision 'Duplicate or case-insensitive path collision'
    $unicodeCollision = New-Zip 'unicode-collision.zip' { param($z) Add-Entry $z "é.txt" '1'; Add-Entry $z "e$([char]0x0301).txt" '2' }
    Expect-Reject 'Unicode normalization collision' $unicodeCollision 'Non-NFC Unicode component rejected'

    $symlink = New-Zip 'symlink.zip' { param($z) $e=$z.CreateEntry('link'); $e.ExternalAttributes=([int](0xA000 -shl 16)); $w=[IO.StreamWriter]::new($e.Open()); $w.Write('../target'); $w.Dispose() }
    Expect-Reject 'Unix symlink' $symlink 'Link or special Unix file type rejected'
    $reparse = New-Zip 'reparse.zip' { param($z) $e=$z.CreateEntry('junction'); $e.ExternalAttributes=0x400; $w=[IO.StreamWriter]::new($e.Open()); $w.Write('x'); $w.Dispose() }
    Expect-Reject 'DOS reparse point' $reparse 'Reparse-point attribute rejected'
    $device = New-Zip 'device.zip' { param($z) $e=$z.CreateEntry('device'); $e.ExternalAttributes=([int](0x6000 -shl 16)); $w=[IO.StreamWriter]::new($e.Open()); $w.Dispose() }
    Expect-Reject 'Unix device' $device 'Link or special Unix file type rejected'

    $prefixConflict = New-Zip 'prefix.zip' { param($z) Add-Entry $z 'node' 'file'; Add-Entry $z 'node/child.txt' 'child' }
    Expect-Reject 'file/directory prefix conflict' $prefixConflict 'File/directory prefix conflict'
    $countZip = New-Zip 'count.zip' { param($z) Add-Entry $z 'one' '1'; Add-Entry $z 'two' '2'; Add-Entry $z 'three' '3' }
    $oldCount = $script:ZipLimits.MaxEntries
    try { $script:ZipLimits.MaxEntries = 2; Expect-Reject 'entry count cap' $countZip 'configured maximum entry count' } finally { $script:ZipLimits.MaxEntries = $oldCount }
    $sizeZip = New-Zip 'large.zip' { param($z) Add-Entry $z 'large.bin' ('x' * 512) }
    $oldSize = $script:ZipLimits.MaxFileBytes
    try { $script:ZipLimits.MaxFileBytes = 128; Expect-Reject 'individual size cap' $sizeZip 'per-file expanded-size limit' } finally { $script:ZipLimits.MaxFileBytes = $oldSize }
    $totalZip = New-Zip 'aggregate.zip' { param($z) Add-Entry $z 'a.bin' ('x' * 80); Add-Entry $z 'b.bin' ('y' * 80) }
    $oldTotal = $script:ZipLimits.MaxTotalBytes
    try { $script:ZipLimits.MaxTotalBytes = 128; Expect-Reject 'aggregate size cap' $totalZip 'aggregate expanded-size limit' } finally { $script:ZipLimits.MaxTotalBytes = $oldTotal }
    $ratioZip = New-Zip 'ratio.zip' { param($z) Add-Entry $z 'bomb.txt' ('a' * 10000) }
    Expect-Reject 'expansion ratio cap' $ratioZip 'expansion-ratio limit'

    $mismatchZip = New-Zip 'mismatch.zip' { param($z) Add-Entry $z 'mismatch.txt' 'claimed-size-mismatch' }
    Set-DeclaredUncompressedSize $mismatchZip 64
    Expect-ExtractionReject 'declared/actual size mismatch' $mismatchZip 'Declared/actual size mismatch' 'mismatch.txt'

    $corruptZip = New-Zip 'corrupt.zip' { param($z) Add-Entry $z 'corrupt.txt' ('compressible data ' * 128) }
    Corrupt-CompressedPayload $corruptZip
    Expect-ExtractionReject 'corrupted compressed stream' $corruptZip '(?i)(Safe extraction aborted.*(compressed|invalid|end of stream)|Declared/actual size mismatch)' 'corrupt.txt'

    $existing = New-Root
    try {
        [IO.File]::WriteAllText((Join-Path $existing 'already.txt'), 'keep')
        $diagnostic = ''
        try { Get-ZipPreflight $good $existing -SkipDiskSpaceCheck | Out-Null } catch { $diagnostic = $_.Exception.Message }
        Assert ($diagnostic -like '*Destination root must be empty*') "pre-existing output expected empty-root rejection; got '$diagnostic'"
        Assert ((Get-Content -Raw (Join-Path $existing 'already.txt')) -eq 'keep') 'pre-existing output preserved'
        Record-Test 'pre-existing output rejected and preserved'
    } finally { if (Test-Path -LiteralPath $existing) { Remove-SafeInspectionRoot $existing } }

    $outside = Join-Path $testBase ('not-temp-' + [guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($outside)
    try {
        $diagnostic = ''
        try { Remove-SafeInspectionRoot $outside } catch { $diagnostic = $_.Exception.Message }
        Assert ($diagnostic -like '*Root must be a direct child*') "cleanup wrong-root expected direct-child rejection; got '$diagnostic'"
        Record-Test 'cleanup refuses incorrect root'
    } finally { if (Test-Path -LiteralPath $outside) { Remove-Item -LiteralPath $outside -Force } }

    $linkRoot = New-Root
    $linkTarget = Join-Path $testBase ('link-target-' + [guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($linkTarget)
    try {
        try { New-Item -ItemType Junction -Path (Join-Path $linkRoot 'link') -Target $linkTarget | Out-Null } catch { throw "Required cleanup reparse-point fixture unavailable: $($_.Exception.Message)" }
        $diagnostic = ''
        try { Remove-SafeInspectionRoot $linkRoot } catch { $diagnostic = $_.Exception.Message }
        Assert ($diagnostic -like '*Cleanup refused because a reparse point exists*') "cleanup reparse fixture expected reparse-point refusal; got '$diagnostic'"
        Assert (Test-Path -LiteralPath (Join-Path $linkRoot 'link')) 'cleanup refusal preserves the junction'
        Record-Test 'cleanup refuses reparse point'
    } finally {
        $junction = Join-Path $linkRoot 'link'
        if (Test-Path -LiteralPath $junction) { Remove-Item -LiteralPath $junction -Force }
        if (Test-Path -LiteralPath $linkRoot) { Remove-SafeInspectionRoot $linkRoot }
        if (Test-Path -LiteralPath $linkTarget) { Remove-Item -LiteralPath $linkTarget -Force }
    }

    $escapeRoot = Join-Path $testBase 'not-a-guid-root'
    [void][IO.Directory]::CreateDirectory($escapeRoot)
    try {
        $diagnostic = ''
        try { Get-ZipPreflight $good $escapeRoot -SkipDiskSpaceCheck | Out-Null } catch { $diagnostic = $_.Exception.Message }
        Assert ($diagnostic -like '*Root must be a direct child*') "destination root expected containment rejection; got '$diagnostic'"
        Record-Test 'destination root confinement'
    } finally { if (Test-Path -LiteralPath $escapeRoot) { Remove-Item -LiteralPath $escapeRoot -Force } }

    "Assertions: $script:Assertions"
    "Failures: $($script:Failures.Count)"
    "Test cases: $($script:TestCases.Count)"
    $script:TestCases | ForEach-Object { "PASS: $_" }
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

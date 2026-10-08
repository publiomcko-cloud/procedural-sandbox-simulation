[CmdletBinding()]
param(
    [ValidateSet('Preflight', 'Extract', 'Cleanup')]
    [string] $Mode,
    [string] $ZipPath,
    [string] $DestinationRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ZipLimits = [ordered]@{
    MaxArchiveBytes = [long](100MB)
    MaxEntries = 20000
    MaxFileBytes = [long](512MB)
    MaxTotalBytes = [long](2GB)
    MaxExpansionRatio = 200.0
    MinFreeBytes = [long](2.5GB)
    BufferBytes = [int](1MB)
}

function Get-CanonicalPath([string] $Path) {
    [System.IO.Path]::GetFullPath($Path).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
}

function Assert-ArchiveIdentity([string] $Path, [long] $ExpectedBytes, [string] $ExpectedSha256) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Archive identity check failed: file not found: $Path" }
    $observedBytes = (Get-Item -LiteralPath $Path).Length
    if ($observedBytes -ne $ExpectedBytes) { throw "Archive size mismatch: expected $ExpectedBytes bytes, observed $observedBytes." }
    $observedSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::Equals($observedSha256, $ExpectedSha256.ToLowerInvariant(), [StringComparison]::Ordinal)) { throw "Archive SHA-256 mismatch: expected $ExpectedSha256, observed $observedSha256." }
    return $observedSha256
}

function Assert-TempRoot([string] $Root, [switch] $RequireEmpty) {
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Destination root is required.' }
    $canonical = Get-CanonicalPath $Root
    $temp = Get-CanonicalPath ([System.IO.Path]::GetTempPath())
    $parent = Get-CanonicalPath ([System.IO.Directory]::GetParent($canonical).FullName)
    if (-not [string]::Equals($parent, $temp, [StringComparison]::OrdinalIgnoreCase)) { throw 'Root must be a direct child of the current user TEMP directory.' }
    $leaf = [System.IO.Path]::GetFileName($canonical)
    if ($leaf -notmatch '^p0-1-f1-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { throw 'Root name must be the expected GUID-unique P0.1-F1 child.' }
    foreach ($repo in @((Get-Location).Path, (git rev-parse --show-toplevel 2>$null))) {
        if ($repo) {
            $repoPath = Get-CanonicalPath ([string]$repo)
            if ($canonical.StartsWith($repoPath + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($canonical, $repoPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Destination root must be outside every repository worktree.' }
        }
    }
    if ([System.IO.Directory]::Exists($canonical)) {
        $rootInfo = [System.IO.DirectoryInfo]::new($canonical)
        if (($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Destination root cannot be a reparse point.' }
        if ($RequireEmpty -and (@($rootInfo.EnumerateFileSystemInfos()).Count -ne 0)) { throw 'Destination root must be empty; pre-existing output is forbidden.' }
    } elseif ($RequireEmpty) { throw 'Destination root must already exist and be empty.' }
    return $canonical
}

function Test-OrdinaryEntry([System.IO.Compression.ZipArchiveEntry] $Entry, [string] $Path, [bool] $IsDirectory) {
    $attributes = [int]$Entry.ExternalAttributes
    $dosAttributes = $attributes -band 0xFFFF
    $unixMode = ($attributes -shr 16) -band 0xFFFF
    $unixType = $unixMode -band 0xF000
    if (($dosAttributes -band 0x400) -ne 0) { throw "Reparse-point attribute rejected: $Path" }
    if ($unixType -in @(0xA000, 0x6000, 0x2000, 0x1000, 0xC000)) { throw "Link or special Unix file type rejected: $Path" }
    if ($unixType -notin @(0, 0x8000, 0x4000)) { throw "Unknown Unix file type rejected: $Path" }
    if ($unixType -eq 0x8000 -and $IsDirectory) { throw "File/directory attribute mismatch: $Path" }
    if ($unixType -eq 0x4000 -and -not $IsDirectory) { throw "File/directory attribute mismatch: $Path" }
    if ($IsDirectory -and $Entry.Length -ne 0) { throw "Directory entry has payload: $Path" }
}

function ConvertTo-SafeZipPath([string] $Name) {
    if ([string]::IsNullOrEmpty($Name)) { throw 'Empty archive path rejected.' }
    if ($Name.Contains('\')) { throw "Backslash path separator rejected: $Name" }
    if ($Name.StartsWith('/') -or $Name.StartsWith('//')) { throw "Absolute or UNC path rejected: $Name" }
    if ($Name -match '^[A-Za-z]:') { throw "Drive-qualified path rejected: $Name" }
    if ($Name.Contains(':')) { throw "Colon or alternate data stream rejected: $Name" }
    if ($Name.Contains([char]0)) { throw 'NUL path character rejected.' }
    $isDirectory = $Name.EndsWith('/')
    $trimmed = if ($isDirectory) { $Name.Substring(0, $Name.Length - 1) } else { $Name }
    if ([string]::IsNullOrEmpty($trimmed)) { throw "Empty archive path rejected: $Name" }
    $parts = $trimmed.Split('/')
    foreach ($part in $parts) {
        if ([string]::IsNullOrEmpty($part) -or $part -in @('.', '..')) { throw "Empty or traversal component rejected: $Name" }
        if (-not [string]::Equals($part, $part.Normalize([Text.NormalizationForm]::FormC), [StringComparison]::Ordinal)) { throw "Non-NFC Unicode component rejected: $Name" }
        if ($part.EndsWith('.') -or $part.EndsWith(' ')) { throw "Ambiguous trailing dot/space rejected: $Name" }
        if ($part -match '[<>"|?*]' -or $part -match '[\x00-\x1F]') { throw "Invalid Windows path component rejected: $Name" }
        $stem = ($part -split '\.', 2)[0]
        if ($stem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])$') { throw "Reserved Windows device name rejected: $Name" }
    }
    return [pscustomobject]@{ Path = ($parts -join '/'); IsDirectory = $isDirectory }
}

function Get-ZipPreflight([string] $Zip, [string] $Root, [switch] $SkipDiskSpaceCheck, [switch] $KeepOpen) {
    if (-not (Test-Path -LiteralPath $Zip -PathType Leaf)) { throw "ZIP file does not exist: $Zip" }
    $zipItem = Get-Item -LiteralPath $Zip
    if ($zipItem.Length -gt $script:ZipLimits.MaxArchiveBytes) { throw 'Archive exceeds configured maximum ZIP size.' }
    $canonicalRoot = Assert-TempRoot $Root -RequireEmpty
    $drive = [System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($canonicalRoot))
    if (-not $SkipDiskSpaceCheck -and $drive.AvailableFreeSpace -lt $script:ZipLimits.MinFreeBytes) { throw "Insufficient free disk space: available $($drive.AvailableFreeSpace) bytes, required $($script:ZipLimits.MinFreeBytes) bytes." }

    $stream = [System.IO.File]::Open($zipItem.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $archive = $null
    $completed = $false
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        if ($archive.Entries.Count -gt $script:ZipLimits.MaxEntries) { throw 'Archive exceeds configured maximum entry count.' }
        $seen = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
        $entries = [Collections.Generic.List[object]]::new()
        [long]$total = 0
        foreach ($entry in $archive.Entries) {
            $pathInfo = ConvertTo-SafeZipPath $entry.FullName
            $path = $pathInfo.Path
            $isDir = $pathInfo.IsDirectory
            Test-OrdinaryEntry $entry $entry.FullName $isDir
            if ($seen.ContainsKey($path)) { throw "Duplicate or case-insensitive path collision: $path and $($seen[$path])" }
            $seen.Add($path, $entry.FullName)
            if (-not $isDir) {
                if ($entry.Length -gt $script:ZipLimits.MaxFileBytes) { throw "File exceeds configured per-file expanded-size limit: $path" }
                if ([long]$entry.Length -gt ([long]::MaxValue - $total)) { throw 'Declared aggregate size overflow.' }
                $total += [long]$entry.Length
                if ($total -gt $script:ZipLimits.MaxTotalBytes) { throw 'Archive exceeds configured aggregate expanded-size limit.' }
                if ($entry.Length -gt 0) {
                    if ($entry.CompressedLength -le 0 -or ($entry.Length / [double]$entry.CompressedLength) -gt $script:ZipLimits.MaxExpansionRatio) { throw "File exceeds configured expansion-ratio limit: $path" }
                }
            }
            $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($canonicalRoot, ($path -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
            $prefix = $canonicalRoot + [System.IO.Path]::DirectorySeparatorChar
            if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Destination path escapes extraction root: $path" }
            $entries.Add([pscustomobject]@{ Entry = $entry; Path = $path; IsDirectory = $isDir; Length = [long]$entry.Length; CompressedLength = [long]$entry.CompressedLength })
        }
        foreach ($path in $seen.Keys) {
            $parts = $path.Split('/')
            for ($i = 1; $i -lt $parts.Length; $i++) {
                $ancestor = ($parts[0..($i - 1)] -join '/')
                if ($seen.ContainsKey($ancestor) -and -not $seen[$ancestor].EndsWith('/')) { throw "File/directory prefix conflict: $ancestor conflicts with $path" }
            }
        }
        foreach ($item in $entries) {
            $parts = $item.Path.Split('/')
            for ($i = 1; $i -lt $parts.Length; $i++) {
                $ancestor = ($parts[0..($i - 1)] -join '/')
                if ($seen.ContainsKey($ancestor) -and $seen[$ancestor].EndsWith('/')) { continue }
            }
        }
        $completed = $true
        return [pscustomobject]@{ ArchivePath = $zipItem.FullName; ArchiveBytes = [long]$zipItem.Length; Root = $canonicalRoot; Entries = $entries; DeclaredBytes = $total; Archive = $archive }
    } finally {
        if (-not $KeepOpen -or -not $completed) {
            if ($archive) { $archive.Dispose() } else { $stream.Dispose() }
        }
    }
}

function Ensure-SafeDirectoryPath([string] $Root, [string] $Target) {
    $canonicalTarget = [System.IO.Path]::GetFullPath($Target)
    $prefix = $Root + [System.IO.Path]::DirectorySeparatorChar
    $rootInfo = [System.IO.DirectoryInfo]::new($Root)
    if (-not $rootInfo.Exists -or ($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Extraction root is missing or became a reparse point.' }
    if ([string]::Equals($canonicalTarget, $Root, [StringComparison]::OrdinalIgnoreCase)) { return }
    if (-not $canonicalTarget.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Directory target escapes extraction root: $Target" }
    $relative = $canonicalTarget.Substring($prefix.Length)
    $cursor = $Root
    foreach ($part in $relative.Split([System.IO.Path]::DirectorySeparatorChar)) {
        $cursor = [System.IO.Path]::Combine($cursor, $part)
        if ([System.IO.File]::Exists($cursor)) { throw "File blocks directory path: $cursor" }
        if (-not [System.IO.Directory]::Exists($cursor)) { [void][System.IO.Directory]::CreateDirectory($cursor) }
        $info = [System.IO.DirectoryInfo]::new($cursor)
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point in extraction path: $cursor" }
    }
}

function Invoke-SafeZipExtract([string] $Zip, [string] $Root, [switch] $SkipDiskSpaceCheck) {
    $preflight = Get-ZipPreflight $Zip $Root -SkipDiskSpaceCheck:$SkipDiskSpaceCheck -KeepOpen
    $archive = $preflight.Archive
    [long]$aggregate = 0
    $buffer = [byte[]]::new($script:ZipLimits.BufferBytes)
    try {
        foreach ($item in $preflight.Entries) {
            $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($preflight.Root, ($item.Path -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
            $prefix = $preflight.Root + [System.IO.Path]::DirectorySeparatorChar
            if (-not $target.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "Destination path escapes extraction root: $($item.Path)" }
            if ($item.IsDirectory) {
                Ensure-SafeDirectoryPath $preflight.Root $target
                continue
            }
            $parent = [System.IO.Path]::GetDirectoryName($target)
            Ensure-SafeDirectoryPath $preflight.Root $parent
            $entry = $archive.GetEntry($item.Entry.FullName)
            $input = $entry.Open()
            $output = $null
            $staging = $target + '.partial-' + [guid]::NewGuid().ToString('N')
            [long]$actual = 0
            try {
                $output = [System.IO.File]::Open($staging, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $actual += $read
                    $aggregate += $read
                    if ($actual -gt $script:ZipLimits.MaxFileBytes -or $aggregate -gt $script:ZipLimits.MaxTotalBytes) { throw 'Actual decompressed data exceeded a configured limit.' }
                    $output.Write($buffer, 0, $read)
                }
                if ($actual -ne $item.Length) { throw "Declared/actual size mismatch for $($item.Path): declared $($item.Length), actual $actual." }
                $output.Flush($true)
                $output.Dispose()
                $output = $null
                [System.IO.File]::Move($staging, $target)
            } catch {
                if ($output) { $output.Dispose(); $output = $null }
                if ([System.IO.File]::Exists($staging)) { [System.IO.File]::Delete($staging) }
                throw
            } finally {
                if ($output) { $output.Dispose() }
                $input.Dispose()
            }
        }
        return $preflight
    } catch {
        throw "Safe extraction aborted; no automatic cleanup was attempted. $($_.Exception.Message)"
    } finally {
        $archive.Dispose()
    }
}

function Remove-SafeInspectionRoot([string] $Root) {
    $canonical = Assert-TempRoot $Root
    $rootInfo = [System.IO.DirectoryInfo]::new($canonical)
    if (-not $rootInfo.Exists) { throw 'Cleanup root does not exist.' }
    $queue = [Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
    $queue.Enqueue($rootInfo)
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Cleanup refused because a reparse point exists: $($directory.FullName)" }
        foreach ($child in $directory.EnumerateFileSystemInfos()) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Cleanup refused because a reparse point exists: $($child.FullName)" }
            if (($child.Attributes -band [IO.FileAttributes]::Directory) -ne 0) { $queue.Enqueue([System.IO.DirectoryInfo]::new($child.FullName)) }
        }
    }
    [System.IO.Directory]::Delete($canonical, $true)
}

if ($MyInvocation.InvocationName -ne '.') {
    switch ($Mode) {
        'Preflight' { Get-ZipPreflight $ZipPath $DestinationRoot | Select-Object ArchivePath, ArchiveBytes, Root, DeclaredBytes, @{n='EntryCount';e={$_.Entries.Count}} | ConvertTo-Json -Depth 4 }
        'Extract' { Invoke-SafeZipExtract $ZipPath $DestinationRoot | Select-Object ArchivePath, ArchiveBytes, Root, DeclaredBytes, @{n='EntryCount';e={$_.Entries.Count}} | ConvertTo-Json -Depth 4 }
        'Cleanup' { Remove-SafeInspectionRoot $DestinationRoot }
    }
}

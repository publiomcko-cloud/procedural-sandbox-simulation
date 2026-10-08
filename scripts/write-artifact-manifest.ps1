[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ZipPath,
    [Parameter(Mandatory)][string] $ExtractedRoot,
    [Parameter(Mandatory)][string] $OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$artifactZipPath = $ZipPath
$artifactExtractedRoot = $ExtractedRoot
$artifactOutputPath = $OutputPath
. (Join-Path $PSScriptRoot 'inspect-zip.ps1')

$expectedArchiveBytes = [long]54457774
$expectedArchiveSha256 = '600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8'
$root = [IO.Path]::GetFullPath($artifactExtractedRoot).TrimEnd('\')
$zip = [IO.Path]::GetFullPath($artifactZipPath)
if (-not (Test-Path -LiteralPath $root -PathType Container) -or -not (Test-Path -LiteralPath $zip -PathType Leaf)) { throw 'Archive and extracted root must exist.' }
if (-not [string]::Equals((Assert-TempRoot $root), $root, [StringComparison]::OrdinalIgnoreCase)) { throw 'Extracted root is not canonical.' }
$observedArchiveSha256 = Assert-ArchiveIdentity $zip $expectedArchiveBytes $expectedArchiveSha256

$zipStream = [IO.File]::Open($zip, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
$archive = [IO.Compression.ZipArchive]::new($zipStream, [IO.Compression.ZipArchiveMode]::Read, $false)
$files = [Collections.Generic.List[object]]::new()
$directories = [Collections.Generic.List[string]]::new()
try {
    foreach ($entry in $archive.Entries) {
        $safe = ConvertTo-SafeZipPath $entry.FullName
        if ($safe.IsDirectory) { $directories.Add($safe.Path + '/'); continue }
        $path = $safe.Path
        $local = [IO.Path]::GetFullPath([IO.Path]::Combine($root, ($path -replace '/', '\')))
        if (-not $local.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Manifest path escaped extraction root: $path" }
        if (-not (Test-Path -LiteralPath $local -PathType Leaf)) { throw "Extracted file is missing: $path" }
        $item = Get-Item -LiteralPath $local
        if ($item.Length -ne $entry.Length) { throw "Extracted size does not match ZIP metadata: $path" }
        $files.Add([pscustomobject]@{ path=$path; type='file'; length=[long]$item.Length; sha256=(Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant() })
    }
} finally { $archive.Dispose() }

$diskFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Force)
if ($diskFiles.Count -ne $files.Count) { throw "Extracted file count differs from archive file count: $($diskFiles.Count) != $($files.Count)" }
$reparseItems = @(Get-ChildItem -LiteralPath $root -Recurse -Force | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
if ($reparseItems.Count -gt 0) { throw "Unexpected reparse point exists in extracted tree: $($reparseItems[0].FullName)" }
$archiveFilePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($item in $files) { [void]$archiveFilePaths.Add($item.path) }
foreach ($item in $diskFiles) {
    $relative = $item.FullName.Substring($root.Length + 1).Replace([string][char]92, '/')
    if (-not $archiveFilePaths.Contains($relative)) { throw "Unexpected file exists in extracted tree: $relative" }
}

$descriptorItem = $files | Where-Object path -eq 'addons/zylann.voxel/voxel.gdextension'
if (-not $descriptorItem) { throw 'Release extension descriptor is missing.' }
$descriptorPath = Join-Path $root 'addons/zylann.voxel\voxel.gdextension'
$descriptorText = Get-Content -Raw -LiteralPath $descriptorPath
$mappings = [Collections.Generic.List[object]]::new()
foreach ($match in [regex]::Matches($descriptorText, '(?m)^([A-Za-z0-9_.]+)\s*=\s*"([^"]+)"\s*$')) {
    $key = $match.Groups[1].Value
    $relative = $match.Groups[2].Value.TrimStart('./').Replace('/', '\')
    if ($key -in @('entry_symbol', 'compatibility_minimum')) { continue }
    $expectedPath = 'addons/zylann.voxel/' + $match.Groups[2].Value.TrimStart('./')
    $present = [bool]($files | Where-Object { $_.path -ceq $expectedPath })
    $mappings.Add([pscustomobject]@{ mapping=$key; path=$expectedPath; present=$present })
}
if (@($mappings | Where-Object { -not $_.present }).Count -gt 0) { throw 'One or more .gdextension library/icon mappings do not resolve to an extracted file.' }

$result = [ordered]@{
    schema_version = 1
    artifact = [ordered]@{
        upstream = 'Zylann/godot_voxel'
        release_tag = 'v1.7x'
        source_commit = '75d3c6d996ed2331c80edcd8c3ebc947afc0f041'
        asset = 'GodotVoxelExtension.zip'
        official_url = 'https://github.com/Zylann/godot_voxel/releases/download/v1.7x/GodotVoxelExtension.zip'
        expected_size_bytes = $expectedArchiveBytes
        observed_size_bytes = (Get-Item -LiteralPath $zip).Length
        github_reported_sha256 = '600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8'
        observed_sha256 = $observedArchiveSha256
        extracted_declared_bytes = [long](($files | Measure-Object -Property length -Sum).Sum)
    }
    archive_entries = @(@($directories | Sort-Object -CaseSensitive | ForEach-Object { [pscustomobject]@{path=$_;type='directory'} }) + @($files | Sort-Object path -CaseSensitive))
    gdextension = [ordered]@{
        descriptor_path = 'addons/zylann.voxel/voxel.gdextension'
        descriptor_sha256 = $descriptorItem.sha256
        entry_symbol = ([regex]::Match($descriptorText, '(?m)^entry_symbol\s*=\s*"([^"]+)"').Groups[1].Value)
        compatibility_minimum = ([regex]::Match($descriptorText, '(?m)^compatibility_minimum\s*=\s*"([^"]+)"').Groups[1].Value)
        mappings = @($mappings)
    }
    extraction = [ordered]@{ file_count=$files.Count; directory_entry_count=$directories.Count; preflight_entry_count=($files.Count + $directories.Count); limits='P0.1-F1 enforced limits' }
}
$parent = Split-Path -Parent $artifactOutputPath
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [void][IO.Directory]::CreateDirectory($parent) }
$json = $result | ConvertTo-Json -Depth 12
[IO.File]::WriteAllText([IO.Path]::GetFullPath($artifactOutputPath), $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
Write-Output "Wrote artifact manifest: $artifactOutputPath"

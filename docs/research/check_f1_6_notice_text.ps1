$ErrorActionPreference = 'Stop'

$noticePath = Join-Path $PSScriptRoot '..\legal\P0.1-F1.6-THIRD-PARTY-NOTICES-DRAFT.md'
$noticeDocument = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $noticePath))
$markdownPaths = @(
    (Resolve-Path -LiteralPath $noticePath).Path
    (Join-Path $PSScriptRoot 'P0.1-F1.6-NOTICE-RESOLUTION.md')
    (Join-Path $PSScriptRoot '..\handoffs\P0.1_F1.6_NOTICE_HANDOFF.md')
)

function Normalize-SourceText([string] $Text) {
    $normalized = $Text -replace "`r`n?", "`n"
    if ($normalized.EndsWith("`n", [System.StringComparison]::Ordinal)) {
        $normalized = $normalized.Substring(0, $normalized.Length - 1)
    }
    return $normalized
}

function Get-NoticeBlock([string] $Document, [string] $Heading) {
    $escapedHeading = [regex]::Escape($Heading)
    $pattern = '(?ms)^## ' + $escapedHeading + '[^\n]*\n.*?^```text\r?\n(.*?)\r?\n^```'
    $match = [regex]::Match($Document, $pattern)
    if (!$match.Success) {
        throw "Could not find a fenced text block under heading: $Heading"
    }
    return Normalize-SourceText $match.Groups[1].Value
}

function Get-PinnedText([string] $Uri) {
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -Headers @{ 'User-Agent' = 'F1.6-notice-text-verifier' }
    return Normalize-SourceText $response.Content
}

function Compare-Notice([string] $Name, [string] $Expected, [string] $Heading) {
    $actual = Get-NoticeBlock $noticeDocument $Heading
    if (![string]::Equals($Expected, $actual, [System.StringComparison]::Ordinal)) {
        $expectedLines = $Expected.Split([char[]]@([char] 10))
        $actualLines = $actual.Split([char[]]@([char] 10))
        $count = [Math]::Max($expectedLines.Count, $actualLines.Count)
        for ($index = 0; $index -lt $count; $index++) {
            $expectedLine = if ($index -lt $expectedLines.Count) { $expectedLines[$index] } else { '<end of source text>' }
            $actualLine = if ($index -lt $actualLines.Count) { $actualLines[$index] } else { '<end of notice block>' }
            if ($expectedLine -cne $actualLine) {
                throw "$Name mismatch at line $($index + 1): source=[$expectedLine] draft=[$actualLine]"
            }
        }
        throw "$Name text differs from pinned source."
    }
    Write-Output "PASS $Name — exact source text, line wrapping, punctuation, and blank lines"
}

$voxelRevision = '75d3c6d996ed2331c80edcd8c3ebc947afc0f041'
$sources = @{
    LZ4 = "https://raw.githubusercontent.com/Zylann/godot_voxel/$voxelRevision/thirdparty/lz4/LICENSE"
    meshoptimizer = "https://raw.githubusercontent.com/Zylann/godot_voxel/$voxelRevision/thirdparty/meshoptimizer/LICENSE.md"
    FastNoiseLite = "https://raw.githubusercontent.com/Zylann/godot_voxel/$voxelRevision/thirdparty/fast_noise/FastNoiseLite.h"
    godot_cpp = 'https://raw.githubusercontent.com/godotengine/godot-cpp/9c8aeff0f58ad030f3d1030e8262de1322cd0ccd/LICENSE.md'
    Voxel_Tools = "https://raw.githubusercontent.com/Zylann/godot_voxel/$voxelRevision/LICENSE.md"
}

$lz4 = Get-PinnedText $sources.LZ4
Compare-Notice 'LZ4 1.10.0' $lz4 'LZ4 1.10.0 — BSD 2-Clause style'

$meshoptimizer = Get-PinnedText $sources.meshoptimizer
Compare-Notice 'meshoptimizer v0.25' $meshoptimizer 'meshoptimizer v0.25 — MIT'

$fastNoiseLiteSource = Get-PinnedText $sources.FastNoiseLite
$fastNoiseLiteMatch = [regex]::Match($fastNoiseLiteSource, '(?ms)\A// MIT License\n.*?^// SOFTWARE\.$')
if (!$fastNoiseLiteMatch.Success) {
    throw 'Could not isolate the initial FastNoiseLite MIT notice comment block.'
}
Compare-Notice 'FastNoiseLite 1.1.1' $fastNoiseLiteMatch.Value 'FastNoiseLite 1.1.1 — MIT'

$godotCpp = Get-PinnedText $sources.godot_cpp
Compare-Notice 'godot-cpp 9c8aeff' $godotCpp 'godot-cpp — MIT'

$voxelTools = Get-PinnedText $sources.Voxel_Tools
Compare-Notice 'Voxel Tools project' $voxelTools 'Voxel Tools project — existing separate MIT notice'

Write-Output 'PASS: all five notice blocks match immutable pinned UTF-8 source text.'

foreach ($markdownPath in $markdownPaths) {
    $markdown = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $markdownPath))
    foreach ($link in [regex]::Matches($markdown, '\[[^\]]*\]\(([^)]+)\)')) {
        $target = $link.Groups[1].Value
        if ($target -match '^https?://' -or $target.StartsWith('#')) {
            continue
        }
        $relativePath = ($target -split '#', 2)[0]
        if (!$relativePath) {
            continue
        }
        $resolvedLink = [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $markdownPath) $relativePath))
        if (!(Test-Path -LiteralPath $resolvedLink)) {
            throw "Broken local Markdown link in $markdownPath -> $target"
        }
    }
}
Write-Output 'PASS: local Markdown links resolve in the notice, research report, and handoff.'

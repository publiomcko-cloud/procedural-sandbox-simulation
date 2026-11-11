param([string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe')
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
$sha = (& git -C $root rev-parse HEAD).Trim()
Write-Host "P5_PHASE2_SOURCE: $sha"
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw 'Pinned Godot executable missing' }
foreach ($relative in @(
    'scripts\perf\run-p5-deterministic-stream-benchmark.ps1',
    'scripts\perf\analyze-p5-phase2-causal.ps1',
    'scripts\perf\run-p5-phase2-causal.ps1',
    'scripts\ci\run-p5-phase2-static-qualification.ps1'
)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative), [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "PHASE2_POWERSHELL_PARSE_FAILED: $relative $($parseErrors[0])"
    }
}
$env:APPDATA = Join-Path $env:RUNNER_TEMP 'p5-phase2-parse-appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
& $GodotBin --headless --editor --path $project --import
if ($LASTEXITCODE -ne 0) { throw 'Godot import failed' }
& $GodotBin --headless --path $project --check-only --script res://scripts/terrain/terrain_demo.gd
if ($LASTEXITCODE -ne 0) { throw 'Godot terrain scene parser failed' }
& $GodotBin --headless --path $project --script res://tests/p5_stream_coarse_preview_tests.gd
if ($LASTEXITCODE -ne 0) { throw 'E2 coarse preview contracts failed' }
Write-Host 'P5_PHASE2_STATIC_QUALIFICATION_PASS'

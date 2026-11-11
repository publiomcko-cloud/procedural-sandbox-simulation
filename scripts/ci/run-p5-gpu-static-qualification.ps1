param(
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
foreach ($relative in @(
    'scripts\ci\p5-gpu-session-preflight.ps1',
    'scripts\ci\configure-p5-gpu-runner-logon.ps1',
    'scripts\perf\run-p5-gpu-smoke.ps1',
    'scripts\ci\run-p5-gpu-static-qualification.ps1'
)) {
    $path = Join-Path $root $relative
    $tokens = $null
    $errorsFound = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errorsFound)
    if ($errorsFound.Count -ne 0) {
        foreach ($parseError in $errorsFound) { Write-Error $parseError.ToString() }
        throw "P5_GPU_POWERSHELL_PARSE_FAILED: $relative"
    }
    Write-Host "P5_GPU_POWERSHELL_PARSE_PASS: $relative"
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Godot not found: $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Unexpected Godot: $version" }
$env:APPDATA = Join-Path $env:RUNNER_TEMP 'p5-gpu-static-isolated'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
& $GodotBin --headless --editor --path $project --import
if ($LASTEXITCODE -ne 0) { throw 'Godot editor import failed' }
& $GodotBin --headless --path $project --check-only --script res://scripts/terrain/terrain_demo.gd
if ($LASTEXITCODE -ne 0) { throw 'Godot terrain_demo parser failed' }
& $GodotBin --headless --path $project --script res://tests/p5_stream_coarse_preview_tests.gd
if ($LASTEXITCODE -ne 0) { throw 'Godot coarse-first tests failed' }
Write-Host 'P5_GPU_STATIC_QUALIFICATION_PASS'

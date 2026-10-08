$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'game'
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'godot' }
foreach ($file in @('project.godot','scenes/main.tscn','scripts/bootstrap.gd','tests/smoke.gd')) {
    if (-not (Test-Path (Join-Path $project $file))) { throw "Missing source: $file" }
}
Write-Host 'L0 PASS: project source exists'
& $godot --headless --editor --path $project --import
if ($LASTEXITCODE -ne 0) { throw "L1 FAIL: import exit code $LASTEXITCODE" }
Write-Host 'L1 PASS: Godot project import'
& $godot --headless --path $project --script 'res://tests/smoke.gd'
if ($LASTEXITCODE -ne 0) { throw "L2 FAIL: smoke exit code $LASTEXITCODE" }
Write-Host 'L2 PASS: seeded-RNG smoke'
Write-Host 'VALIDATION_PASS (L0-L2 only; terrain and GUI untested)'

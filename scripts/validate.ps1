$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'game'
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'godot' }
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($file in @('project.godot', 'scenes/main.tscn', 'scenes/terrain_demo.tscn', 'scripts/bootstrap.gd', 'scripts/region_generator.gd', 'scripts/terrain/sdf_world.gd', 'scripts/terrain/sdf_brush_edit_state.gd', 'scripts/terrain/terrain_brush_picker.gd', 'scripts/terrain/marching_tetrahedra.gd', 'scripts/terrain/terrain_demo.gd', 'tests/smoke.gd', 'tests/terrain_sdf_tests.gd', 'tests/terrain_brush_tests.gd', 'tests/bootstrap_visual_regression.gd')) {
    if (-not (Test-Path (Join-Path $project $file))) { $failures.Add("L0 FAIL: missing source $file") }
}
if ($failures.Count -eq 0) { Write-Host 'L0 PASS: all project source files exist' }

if ((Get-Command $godot -ErrorAction SilentlyContinue) -or (Test-Path $godot)) {
    $version = (& $godot --version 2>&1 | Out-String).Trim()
    $versionExit = $LASTEXITCODE
    Write-Host "Godot found: $version"
    if ($versionExit -ne 0) { $failures.Add("Godot version command exit code $versionExit") }
    elseif ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') {
        $failures.Add("Godot 4.7.2 stable required; found '$version'")
    } else {
        Write-Host 'Godot PASS: pinned version 4.7.2 stable'
    }

    Write-Host "COMMAND: `"$godot`" --headless --editor --path `"$project`" --import"
    & $godot --headless --editor --path $project --import
    $importExit = $LASTEXITCODE
    if ($importExit -eq 0) { Write-Host 'L1 PASS: Godot project import' }
    else { $failures.Add("L1 FAIL: Godot import exit code $importExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/smoke.gd"
    & $godot --headless --path $project --script 'res://tests/smoke.gd'
    $testExit = $LASTEXITCODE
    if ($testExit -eq 0) { Write-Host 'L2 PASS: deterministic generation and failure-path checks' }
    else { $failures.Add("L2 FAIL: headless tests exit code $testExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_sdf_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_sdf_tests.gd'
    $terrainExit = $LASTEXITCODE
    if ($terrainExit -eq 0) { Write-Host 'L2 PASS: deterministic SDF and mesh tests' }
    else { $failures.Add("L2 FAIL: terrain SDF test exit code $terrainExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_brush_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_brush_tests.gd'
    $brushExit = $LASTEXITCODE
    if ($brushExit -eq 0) { Write-Host 'L2 PASS: bounded SDF brush edits and viewport interaction tests' }
    else { $failures.Add("L2 FAIL: terrain brush test exit code $brushExit") }

    Write-Host ('COMMAND: ' + $godot + ' --headless --path ' + $project + ' --script res://tests/bootstrap_visual_regression.gd')
    & $godot --headless --path $project --script 'res://tests/bootstrap_visual_regression.gd'
    $bootstrapExit = $LASTEXITCODE
    if ($bootstrapExit -eq 0) { Write-Host 'L2 PASS: instantiated bootstrap structure (pixels are not assessed)' }
    else { $failures.Add("L2 FAIL: bootstrap structure test exit code $bootstrapExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --quit-after 2"
    & $godot --headless --path $project --quit-after 2
    $startupExit = $LASTEXITCODE
    if ($startupExit -eq 0) { Write-Host 'L2 PASS: configured main scene startup' }
    else { $failures.Add("L2 FAIL: main scene startup exit code $startupExit") }
} else {
    $failures.Add("Godot command not found: $godot")
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VALIDATION_FAIL: failures=$($failures.Count); GUI visual test is not performed by this script"
    exit 1
}
Write-Host 'VALIDATION_PASS: L0-L2; GUI visual test remains an owner task'
exit 0

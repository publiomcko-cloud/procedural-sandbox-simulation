$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$project = Join-Path $root 'game'
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'godot' }
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($file in @('project.godot', 'scenes/main.tscn', 'scenes/terrain_demo.tscn', 'scripts/bootstrap.gd', 'scripts/region_generator.gd', 'scripts/modding/declarative_mod_loader.gd', 'scripts/modding/content_definition_registry.gd', 'scripts/objects/procedural_object_world.gd', 'scripts/objects/procedural_rock_mesh_adapter.gd', 'scripts/objects/procedural_object_stream.gd', 'scripts/terrain/sdf_world.gd', 'scripts/terrain/sdf_brush_edit_state.gd', 'scripts/terrain/terrain_brush_picker.gd', 'scripts/terrain/terrain_chunk_grid.gd', 'scripts/terrain/terrain_spatial_ownership.gd', 'scripts/terrain/terrain_world_state.gd', 'scripts/terrain/terrain_world_save_store.gd', 'scripts/terrain/marching_tetrahedra.gd', 'scripts/terrain/terrain_mesh_job.gd', 'scripts/terrain/terrain_lod_policy.gd', 'scripts/terrain/lod01_chunk_mesher.gd', 'scripts/terrain/terrain_demo.gd', 'scripts/experiments/lod01_transition_fixture.gd', 'tests/smoke.gd', 'tests/terrain_sdf_tests.gd', 'tests/terrain_brush_tests.gd', 'tests/terrain_chunk_tests.gd', 'tests/terrain_multiregion_tests.gd', 'tests/terrain_perf_benchmark.gd', 'tests/terrain_history_tests.gd', 'tests/terrain_picker_history_perf.gd', 'tests/terrain_end_to_end_perf.gd', 'tests/terrain_concurrency_tests.gd', 'tests/lod01_transition_tests.gd', 'tests/terrain_lod_runtime_tests.gd', 'tests/terrain_world_persistence_tests.gd', 'tests/terrain_world_persistence_process_probe.gd', 'tests/declarative_mod_tests.gd', 'tests/procedural_object_tests.gd', 'tests/terrain_lighting_capture.gd', 'tests/bootstrap_visual_regression.gd')) {
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

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_chunk_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_chunk_tests.gd'
    $chunkExit = $LASTEXITCODE
    if ($chunkExit -eq 0) { Write-Host 'L2 PASS: chunk partition, seam, localized rebuild and benchmark tests' }
    else { $failures.Add("L2 FAIL: terrain chunk test exit code $chunkExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_multiregion_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_multiregion_tests.gd'
    $multiregionExit = $LASTEXITCODE
    if ($multiregionExit -eq 0) { Write-Host 'L2 PASS: multi-region ownership, continuity, seam and viewport tests' }
    else { $failures.Add("L2 FAIL: multi-region tests exit code $multiregionExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_perf_benchmark.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_perf_benchmark.gd'
    $perfExit = $LASTEXITCODE
    if ($perfExit -eq 0) { Write-Host 'L2 PASS: staged CPU mesh, ledger-size and worker equivalence benchmark' }
    else { $failures.Add("L2 FAIL: terrain performance benchmark exit code $perfExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_history_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_history_tests.gd'
    $historyExit = $LASTEXITCODE
    if ($historyExit -eq 0) { Write-Host 'L2 PASS: 256-operation history, replay equivalence and revision supersession tests' }
    else { $failures.Add("L2 FAIL: terrain history test exit code $historyExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_world_persistence_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_world_persistence_tests.gd'
    $persistenceExit = $LASTEXITCODE
    if ($persistenceExit -eq 0) { Write-Host 'L2 PASS: versioned persistent world save, recovery, restart and LOD reconstruction tests' }
    else { $failures.Add("L2 FAIL: terrain persistence test exit code $persistenceExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/declarative_mod_tests.gd"
    & $godot --headless --path $project --script 'res://tests/declarative_mod_tests.gd'
    $modExit = $LASTEXITCODE
    if ($modExit -eq 0) { Write-Host 'L2 PASS: declarative package validation, content registry and deterministic recipe tests' }
    else { $failures.Add("L2 FAIL: declarative mod test exit code $modExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/procedural_object_tests.gd"
    & $godot --headless --path $project --script 'res://tests/procedural_object_tests.gd'
    $objectExit = $LASTEXITCODE
    if ($objectExit -eq 0) { Write-Host 'L2 PASS: mod-first deterministic procedural objects and region streaming tests' }
    else { $failures.Add("L2 FAIL: procedural object tests exit code $objectExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_picker_history_perf.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_picker_history_perf.gd'
    $pickerExit = $LASTEXITCODE
    if ($pickerExit -eq 0) { Write-Host 'L2 PASS: real viewport picking at 0/32/128/256 history levels' }
    else { $failures.Add("L2 FAIL: terrain picker history test exit code $pickerExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/lod01_transition_tests.gd"
    & $godot --headless --path $project --script 'res://tests/lod01_transition_tests.gd'
    $lodExit = $LASTEXITCODE
    if ($lodExit -eq 0) { Write-Host 'L2 PASS: experimental deterministic LOD 0/1 transition fixture' }
    else { $failures.Add("L2 FAIL: LOD 0/1 transition fixture exit code $lodExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_lod_runtime_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_lod_runtime_tests.gd'
    $lodRuntimeExit = $LASTEXITCODE
    if ($lodRuntimeExit -eq 0) { Write-Host 'L2 PASS: playable LOD0/LOD1 selector, chunk assembly and seam tests' }
    else { $failures.Add("L2 FAIL: playable LOD runtime tests exit code $lodRuntimeExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_end_to_end_perf.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_end_to_end_perf.gd'
    $e2ePerfExit = $LASTEXITCODE
    if ($e2ePerfExit -eq 0) { Write-Host 'L2 PASS: viewport-click to visible commit and region traversal performance scenarios' }
    else { $failures.Add("L2 FAIL: terrain end-to-end performance tests exit code $e2ePerfExit") }

    Write-Host "COMMAND: `"$godot`" --headless --path `"$project`" --script res://tests/terrain_concurrency_tests.gd"
    & $godot --headless --path $project --script 'res://tests/terrain_concurrency_tests.gd'
    $concurrencyExit = $LASTEXITCODE
    if ($concurrencyExit -eq 0) { Write-Host 'L2 PASS: worker concurrency, cancellation and transactional publication tests' }
    else { $failures.Add("L2 FAIL: terrain concurrency tests exit code $concurrencyExit") }

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

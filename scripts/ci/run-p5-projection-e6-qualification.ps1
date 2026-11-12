param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-projection-e6-qualification' } else { Join-Path $env:TEMP 'p5-projection-e6-qualification' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Wrong Godot version: $version" }
foreach ($p in @(
    'scripts\ci\run-p5-projection-e6-qualification.ps1',
    'scripts\perf\run-p5-deterministic-stream-benchmark.ps1',
    'scripts\perf\run-p5-projection-e6-abba.ps1',
    'scripts\perf\analyze-p5-projection-e6-abba.ps1'
)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $p), [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "PowerShell parse error: $p $($errors[0])" }
}
$env:APPDATA = Join-Path $EvidenceDir 'isolated-appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
function Run-Test([string]$Name, [string[]]$Arguments, [string]$Expected) {
    $stdout = Join-Path $EvidenceDir "$Name.stdout.log"
    $stderr = Join-Path $EvidenceDir "$Name.stderr.log"
    $argLine = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $p = Start-Process -FilePath $GodotBin -ArgumentList $argLine -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $p.WaitForExit(150000)) { $p.Kill(); $p.WaitForExit(); throw "Godot timeout: $Name" }
    $p.Refresh()
    $out = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) -replace '\x00', ''
    $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00', ''
    if (($null -ne $p.ExitCode -and [int]$p.ExitCode -ne 0) -or ($out + $err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR:)') {
        throw "Godot test failed: $Name, inspect $stdout and $stderr"
    }
    if ($Expected -and -not $out.Contains($Expected)) { throw "Missing PASS marker $Expected in $Name" }
    Write-Host "P5_E6_TEST_PASS: $Name"
    return $out
}
[void](Run-Test 'editor-import' @('--headless', '--editor', '--path', $project, '--import') '')
[void](Run-Test 'scene-parser' @('--headless', '--path', $project, '--check-only', '--script', 'res://scripts/terrain/terrain_demo.gd') '')
[void](Run-Test 'projection-capacity-contracts' @('--headless', '--path', $project, '--script', 'res://tests/p5_projection_pipeline_e6_capacity_tests.gd') 'P5_PROJECTION_E6_CAPACITY_PASS:')
[void](Run-Test 'inherited-effect-contracts' @('--headless', '--path', $project, '--script', 'res://tests/issue108_phase_b_pure_effect_tests.gd') 'ISSUE108_PHASE_B_PASS:')
[void](Run-Test 'inherited-worker-projection' @('--headless', '--path', $project, '--script', 'res://tests/issue108_d6_1_worker_prevalidated_effect_tests.gd') 'ISSUE108_D6_1_WORKER_PREVALIDATED_PASS:')
[void](Run-Test 'stream-profile-contracts' @('--headless', '--path', $project, '--script', 'res://tests/p5_0f_stream_budget_tests.gd') 'P5_0F_STREAM_BUDGET_PASS:')
[void](Run-Test 'coarse-preview-contracts' @('--headless', '--path', $project, '--script', 'res://tests/p5_stream_coarse_preview_tests.gd') 'P5_STREAM_COARSE_PREVIEW_PASS:')
$env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-coarse-pipeline'
$env:SANDBOX_PERF_TRACE = '1'
$env:SANDBOX_PERF_TRACE_MIN_MS = '2.0'
$runtime = Run-Test 'real-scene-projection-opt-in' @('--headless', '--path', $project, '--quit-after', '480', '--', '--start-water=ocean') '"event":"terrain_stream_profile"'
if ($runtime -notmatch '"profile":"adaptive-skip-coarse-pipeline"') { throw 'Opt-in profile not recognized' }
if ($runtime -notmatch '"event":"terrain_region_coarse_visible"') { throw 'Coarse preview missing from E6 profile' }
if ($runtime -notmatch '"event":"effect_projection_pipeline_config"') { throw 'Missing authoritative E6 pipeline configuration trace' }
if ($runtime -notmatch '"projection_worker_limit":4') { throw 'Projection capacity 4 not applied' }
if ($runtime -notmatch '"source_worker_limit":2') { throw 'Source generation worker capacity changed unexpectedly' }
if ($runtime -notmatch '"publish_limit_per_frame":2') { throw 'E6 publication capacity 2 not applied' }
Write-Host 'P5_PROJECTION_E6_QUALIFICATION_PASS'

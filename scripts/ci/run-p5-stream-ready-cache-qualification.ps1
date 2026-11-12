param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-ready-cache-qualification' } else { Join-Path $env:TEMP 'p5-ready-cache-qualification' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Godot missing: $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Unexpected Godot: $version" }
foreach ($p in @(
    'scripts\ci\run-p5-stream-ready-cache-qualification.ps1',
    'scripts\perf\run-p5-ready-cache-abba.ps1',
    'scripts\perf\run-p5-deterministic-stream-benchmark.ps1'
)) {
    $tokens = $null
    $errorsFound = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $p), [ref]$tokens, [ref]$errorsFound)
    if ($errorsFound.Count -gt 0) { throw "PowerShell script parse: $p $($errorsFound[0])" }
}
$env:APPDATA = Join-Path $EvidenceDir 'isolated-world'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
function Run-Godot([string]$Name, [string[]]$Arguments, [string]$Expected) {
    $out = Join-Path $EvidenceDir "$Name.log"
    $err = Join-Path $EvidenceDir "$Name.stderr.log"
    $argLine = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $p = Start-Process -FilePath $GodotBin -ArgumentList $argLine -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $p.WaitForExit(120000)) { $p.Kill(); $p.WaitForExit(); throw "Godot timeout: $Name" }
    $p.Refresh()
    $stdout = (Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) -replace '\x00', ''
    $stderr = (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue) -replace '\x00', ''
    if (($null -ne $p.ExitCode -and [int]$p.ExitCode -ne 0) -or ($stdout + $stderr) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)') {
        throw "Godot failure: $Name (inspect $out / $err)"
    }
    if (-not [string]::IsNullOrEmpty($Expected) -and -not $stdout.Contains($Expected)) {
        throw "Missing marker: $Name -> $Expected"
    }
    Write-Host "P5_READY_QUAL_PASS: $Name"
    return $stdout
}
[void](Run-Godot 'editor-import' @('--headless', '--editor', '--path', $project, '--import') '')
[void](Run-Godot 'scene-parser' @('--headless', '--path', $project, '--check-only', '--script', 'res://scripts/terrain/terrain_demo.gd') '')
[void](Run-Godot 'ready-cache-policy-tests' @('--headless', '--path', $project, '--script', 'res://tests/p5_stream_ready_cache_tests.gd') 'P5_STREAM_READY_CACHE_PASS:')
[void](Run-Godot 'existing-stream-policy-tests' @('--headless', '--path', $project, '--script', 'res://tests/p5_0f_stream_budget_tests.gd') 'P5_0F_STREAM_BUDGET_PASS:')
[void](Run-Godot 'existing-coarse-policy-tests' @('--headless', '--path', $project, '--script', 'res://tests/p5_stream_coarse_preview_tests.gd') 'P5_STREAM_COARSE_PREVIEW_PASS:')
$env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-coarse-ready'
$env:SANDBOX_PERF_TRACE = '1'
$env:SANDBOX_PERF_TRACE_MIN_MS = '2.0'
$runtime = Run-Godot 'headless-real-scene' @('--headless', '--path', $project, '--quit-after', '480', '--', '--start-water=ocean') '"event":"terrain_stream_profile"'
if ($runtime -notmatch '"profile":"adaptive-skip-coarse-ready"') { throw 'Runtime silently changed requested profile' }
if ($runtime -notmatch '"event":"terrain_region_coarse_visible"') { throw 'No E2 coarse publication in real scene' }
if ($runtime -notmatch '"ready_cache_hits":\s*[1-9]\d*') { throw 'New negative readiness cache was not exercised by a real scene' }
Write-Host 'P5_STREAM_READY_CACHE_QUALIFICATION_PASS'

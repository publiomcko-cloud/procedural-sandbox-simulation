param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-e7-qualification' } else { Join-Path $env:TEMP 'p5-e7-qualification' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "E7 wrong Godot: $version" }
foreach ($p in @(
    'scripts\ci\run-p5-progressive-e7-qualification.ps1',
    'scripts\perf\run-p5-deterministic-stream-benchmark.ps1'
)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root $p), [ref]$tokens, [ref]$errors
    )
    if ($errors.Count -gt 0) { throw "PowerShell parse error: $p $($errors[0])" }
}
$env:APPDATA = Join-Path $EvidenceDir 'isolated-appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
function Run-Godot([string]$Name, [string[]]$Arguments, [string]$Expected, [int]$TimeoutMs = 180000) {
    $stdout = Join-Path $EvidenceDir "$Name.stdout.log"
    $stderr = Join-Path $EvidenceDir "$Name.stderr.log"
    $argLine = ($Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $p = Start-Process -FilePath $GodotBin -ArgumentList $argLine -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $p.WaitForExit($TimeoutMs)) { $p.Kill(); $p.WaitForExit(); throw "E7_GODOT_TIMEOUT: $Name" }
    $p.Refresh()
    $out = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
    $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
    if (($null -ne $p.ExitCode -and [int]$p.ExitCode -ne 0) -or
        ($out + $err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR:)') {
        throw "E7_GODOT_FAILED: $Name; inspect $stdout and $stderr"
    }
    if ($Expected -and -not $out.Contains($Expected)) { throw "E7_PASS_MARKER_MISSING: $Name / $Expected" }
    Write-Host "P5_E7_QUALIFIED: $Name"
    return $out
}
[void](Run-Godot 'editor-import' @('--headless', '--editor', '--path', $project, '--import') '')
[void](Run-Godot 'scene-parser' @('--headless', '--path', $project, '--check-only', '--script', 'res://scripts/terrain/terrain_demo.gd') '')
[void](Run-Godot 'progressive-policy-coverage' @('--headless', '--path', $project, '--script', 'res://tests/p5_stream_progressive_chunk_tests.gd') 'P5_PROGRESSIVE_E7_POLICY_PASS:')
[void](Run-Godot 'inherited-coarse-preview' @('--headless', '--path', $project, '--script', 'res://tests/p5_stream_coarse_preview_tests.gd') 'P5_STREAM_COARSE_PREVIEW_PASS:')
[void](Run-Godot 'inherited-budget' @('--headless', '--path', $project, '--script', 'res://tests/p5_0f_stream_budget_tests.gd') 'P5_0F_STREAM_BUDGET_PASS:')
[void](Run-Godot 'inherited-effects' @('--headless', '--path', $project, '--script', 'res://tests/issue108_d6_1_worker_prevalidated_effect_tests.gd') 'ISSUE108_D6_1_WORKER_PREVALIDATED_PASS:')
$env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
$env:SANDBOX_PERF_TRACE = '1'
$env:SANDBOX_PERF_TRACE_MIN_MS = '0'
$runtime = Run-Godot 'scene-progressive-smoke' @('--headless', '--path', $project, '--quit-after', '720', '--', '--start-water=ocean') '"event":"terrain_stream_profile"' 240000
if ($runtime -notmatch '"profile":"adaptive-skip-progressive"') {
    throw 'E7_PROFILE_NOT_SELECTED'
}
if ($runtime -notmatch '"event":"terrain_chunk_progressive_visible"') {
    throw 'E7_NO_REAL_PROGRESSIVE_CHUNK_PUBLICATION'
}
if ($runtime -notmatch '"event":"terrain_region_coarse_visible"') {
    throw 'E7_NO_REAL_COARSE_PREVIEW'
}
Write-Host 'P5_PROGRESSIVE_E7_QUALIFICATION_PASS'

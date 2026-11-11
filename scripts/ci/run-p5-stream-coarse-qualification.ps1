param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$ProjectPath = $(Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'game'),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-e2-evidence' } else { Join-Path $env:TEMP 'p5-e2-evidence' })
)
$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Godot 4.7.2 not found: $GodotBin" }
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Wrong Godot version: $version" }
$env:APPDATA = Join-Path $EvidenceDir 'isolated-appdata'
New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null

function Invoke-Godot([string]$Label, [string[]]$Arguments, [string]$Marker) {
    $ErrorActionPreference = 'Continue'
    $lines = @(& $GodotBin @Arguments 2>&1)
    $exit = $LASTEXITCODE
    $output = ($lines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $EvidenceDir "$Label.log"), $output, [Text.UTF8Encoding]::new($false))
    $ErrorActionPreference = 'Stop'
    if ($exit -ne 0 -or $output.Contains('SCRIPT ERROR:') -or $output.Contains('ERROR: FAIL:') -or $output.Contains('Parse Error:') -or $output.Contains('ERROR: Failed to load script')) {
        throw "E2 $Label failed (exit=$exit). See $EvidenceDir"
    }
    if ($Marker -and -not $output.Contains($Marker)) {
        throw "E2 $Label missing evidence marker: $Marker"
    }
    Write-Output "E2 $Label PASS"
}

Invoke-Godot 'editor-import' @('--headless', '--editor', '--path', $ProjectPath, '--import') ''
# Unit tests alone are insufficient: E1.1 broke the runtime scene parser.
Invoke-Godot 'terrain-main-parse' @('--headless', '--path', $ProjectPath, '--check-only', '--script', 'res://scripts/terrain/terrain_demo.gd') ''
Invoke-Godot 'coarse-worker-revision-tests' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/p5_stream_coarse_preview_tests.gd') 'P5_STREAM_COARSE_PREVIEW_PASS:'

$env:SANDBOX_PERF_TRACE = '1'
$env:SANDBOX_PERF_TRACE_MIN_MS = '2.0'
$env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-coarse'
# Real scene, isolated default world. Requires an actual coarse publication,
# rather than treating a script parser or standalone test PASS as a visible game.
Invoke-Godot 'headless-runtime-smoke' @('--headless', '--path', $ProjectPath, '--quit-after', '480', '--', '--start-water=ocean') '"event":"terrain_region_coarse_visible"'
$env:SANDBOX_STREAM_PROFILE = 'baseline'

& (Join-Path $PSScriptRoot 'run-p5-0f-qualification.ps1') -GodotBin $GodotBin -ProjectPath $ProjectPath
if ($LASTEXITCODE -ne 0) { throw "E2 inherited P5/P4 qualification failed: $LASTEXITCODE" }
Write-Output 'SELF_HOSTED_P5_STREAM_E2_QUALIFICATION_PASS'
exit 0

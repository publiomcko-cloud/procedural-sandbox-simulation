param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-e7-abba' } else { Join-Path $env:TEMP 'p5-e7-abba' }),
    [ValidateRange(120,5400)][int]$Frames = 720
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
if (@(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File).Count -gt 0) {
    throw 'E7_EVIDENCE_DIRECTORY_NOT_EMPTY'
}
$control = 'adaptive-skip-coarse'
$variant = 'adaptive-skip-progressive'
$routes = @('idle', 'straight-18', 'straight-54', 'outback-54')
$profiles = @($control, $variant, $variant, $control)
& (Join-Path $PSScriptRoot 'run-p5-deterministic-stream-benchmark.ps1') -GodotBin $GodotBin -EvidenceDir $EvidenceDir -Frames $Frames -Routes $routes -Profiles $profiles
if ($LASTEXITCODE -ne 0) { throw "E7_BENCHMARK_RUN_FAILED: $LASTEXITCODE" }
$head = (& git rev-parse HEAD).Trim()
& (Join-Path $PSScriptRoot 'analyze-p5-progressive-e7-abba.ps1') -EvidenceDir $EvidenceDir -Frames $Frames -ExpectedSourceCommit $head
if ($LASTEXITCODE -ne 0) { throw "E7_ANALYZER_FAILED: $LASTEXITCODE" }
Write-Host "P5_PROGRESSIVE_E7_16_TRIALS_CAPTURED: commit=$head"

param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-projection-e5-abba' } else { Join-Path $env:TEMP 'p5-projection-e5-abba' }),
    [ValidateRange(120, 5400)][int]$Frames = 720
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
if (@(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'E5_EVIDENCE_DIR_NONEMPTY'
}
$routes = @('idle', 'straight-18', 'straight-54', 'outback-54')
$profiles = @('adaptive-skip-coarse', 'adaptive-skip-coarse-projection', 'adaptive-skip-coarse-projection', 'adaptive-skip-coarse')
& (Join-Path $PSScriptRoot 'run-p5-deterministic-stream-benchmark.ps1') -GodotBin $GodotBin -EvidenceDir $EvidenceDir -Frames $Frames -Routes $routes -Profiles $profiles
if ($LASTEXITCODE -ne 0) { throw "E5_BENCHMARK_RUN_FAILED: $LASTEXITCODE" }
$head = (& git rev-parse HEAD).Trim()
& (Join-Path $PSScriptRoot 'analyze-p5-projection-e5-abba.ps1') -EvidenceDir $EvidenceDir -Frames $Frames -ExpectedSourceCommit $head
if ($LASTEXITCODE -ne 0) { throw "E5_ANALYZER_FAILED: $LASTEXITCODE" }
Write-Host "P5_PROJECTION_E5_16_TRIALS_CAPTURED: commit=$head"

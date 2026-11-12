param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-consumer-demand-abba' } else { Join-Path $env:TEMP 'p5-consumer-demand-abba' }),
    [ValidateRange(120, 5400)][int]$Frames = 720
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
if (@(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'E4_EVIDENCE_DIRECTORY_NOT_EMPTY: cannot mix benchmark runs'
}
$control = 'adaptive-skip-coarse'
$variant = 'adaptive-skip-coarse-demand'
$routes = @('idle', 'straight-18', 'straight-54', 'outback-54')
$profiles = @($control, $variant, $variant, $control)
& (Join-Path $PSScriptRoot 'run-p5-deterministic-stream-benchmark.ps1') -GodotBin $GodotBin -EvidenceDir $EvidenceDir -Frames $Frames -Routes $routes -Profiles $profiles
if ($LASTEXITCODE -ne 0) { throw "E4_BENCHMARK_FAILED: exit=$LASTEXITCODE" }
$receipts = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File)
if ($receipts.Count -ne 16) { throw "E4_INCOMPLETE_TRIALS: actual=$($receipts.Count)" }
$head = (& git rev-parse HEAD).Trim()
foreach ($p in $receipts) {
    $d = Get-Content -LiteralPath $p.FullName -Raw | ConvertFrom-Json
    if ([string]$d.commit -ne $head -or [int]$d.seed -ne 424242 -or [int]$d.sampled_frames -ne ($Frames + 1)) {
        throw "E4_NONDETERMINISTIC_RECEIPT: $($p.Name)"
    }
}
Write-Host "P5_E4_16_TRIALS_CAPTURED: commit=$head"
& (Join-Path $PSScriptRoot 'analyze-p5-consumer-demand-abba.ps1') -EvidenceDir $EvidenceDir -Frames $Frames -ExpectedSourceCommit $head
if ($LASTEXITCODE -ne 0) { throw "E4_ANALYSIS_FAILED: exit=$LASTEXITCODE" }
Write-Host "P5_E4_ABBA_EVIDENCE_PASS: commit=$head"

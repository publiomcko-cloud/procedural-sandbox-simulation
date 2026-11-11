param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-phase2-causal' } else { Join-Path $env:TEMP 'p5-phase2-causal' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$existing = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.stdout.log' -File -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) { throw 'PHASE2_EVIDENCE_DIR_NOT_EMPTY: cannot mix old trials with new trial matrix' }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$head = (& git rev-parse HEAD).Trim()
Write-Host "P5_PHASE2_BEGIN: commit=$head"
Write-Host 'Controlled ABBA order for each cold-start route; no production stream code changes.'
& (Join-Path $PSScriptRoot 'run-p5-deterministic-stream-benchmark.ps1') -GodotBin $GodotBin -EvidenceDir $EvidenceDir -Frames 720 -Routes @('idle', 'straight-18', 'straight-54', 'outback-54') -Profiles @('adaptive-skip', 'adaptive-skip-coarse', 'adaptive-skip-coarse', 'adaptive-skip')
if ($LASTEXITCODE -ne 0) { throw "PHASE2_ROUTER_FAILED: exit=$LASTEXITCODE" }
& (Join-Path $PSScriptRoot 'analyze-p5-phase2-causal.ps1') -EvidenceDir $EvidenceDir -ExpectedFrames 720 -ExpectedTrials 16
if ($LASTEXITCODE -ne 0) { throw "PHASE2_ANALYZER_FAILED: exit=$LASTEXITCODE" }
Write-Host "P5_PHASE2_CAUSAL_QUALIFICATION_PASS: commit=$head"

param(
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm2-b4-abba' } else { Join-Path $env:TEMP 'dm2-b4-abba' }),
    [ValidateRange(240,5400)][int]$Frames = 480
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$backends = @('sdf','b4','b4','sdf')
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$sha = (& git -C $repoRoot rev-parse HEAD).Trim()
$measurements = @()
for ($i = 0; $i -lt $backends.Count; $i++) {
    $backend = $backends[$i]
    $trial = '{0:d2}-{1}' -f ($i + 1), $backend
    $directory = Join-Path $EvidenceDir $trial
    if (Test-Path -LiteralPath $directory) {
        throw "DM2 evidence directory already exists: $directory"
    }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $env:SANDBOX_TERRAIN_BACKEND = $backend
    $env:SANDBOX_STREAM_BENCHMARK = '1'
    Write-Host "DM2_TRIAL_START backend=$backend trial=$trial sha=$sha"
    & (Join-Path $PSScriptRoot 'run-p5-deterministic-stream-benchmark.ps1') `
        -GodotBin $GodotBin -EvidenceDir $directory `
        -Frames $Frames -Routes @('straight-18') `
        -Profiles @('adaptive-skip-progressive')
    if ($LASTEXITCODE -ne 0) {
        throw "DM2 deterministic route failed: $trial"
    }
    $logs = @(Get-ChildItem -LiteralPath $directory -Filter '*.stdout.log' -File)
    if ($logs.Count -ne 1) {
        throw "DM2 missing route stdout: $trial"
    }
    $stdout = Get-Content -LiteralPath $logs[0].FullName -Raw
    if (-not $stdout.Contains("DM2_TERRAIN_BACKEND=$backend ") -or
        $stdout -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: Failed to load script)') {
        throw "DM2 wrong backend receipt or script errors: $trial"
    }
    $markers = @([regex]::Matches($stdout, 'DM2_TERRAIN_BACKEND='))
    if ($markers.Count -ne 1) {
        throw "DM2 missing/duplicate backend receipt: $trial"
    }
    # The job trace includes backend identity, rather than inferring selection
    # from environment or timings. Require at least one real B4 worker.
    if ($backend -eq 'b4' -and $stdout -notmatch '"terrain_backend":"b4"') {
        throw "DM2 B4 was requested but no B4 mesh worker completed: $trial"
    }
    $json = Get-Content -LiteralPath (Join-Path $directory 'summary.json') -Raw | ConvertFrom-Json
    $metric = @($json)[0]
    if ([int]$metric.mesh_uploads -lt 1) {
        throw "DM2 no terrain mesh published: $trial"
    }
    $record = [ordered]@{
        backend = $backend
        trial = $trial
        source_sha = $sha
        frames = $Frames
        route = [string]$metric.route
        average_frame_ms = [double]$metric.avg_frame_ms
        average_process_ms = [double]$metric.avg_process_ms
        over_33_ms_pct = [double]$metric.frames_over_33_ms_pct
        focus_missing_pct = [double]$metric.f10_focus_missing_pct
        perceived_focus_missing_pct = [double]$metric.f10_perceived_focus_missing_pct
        region_load_p50_ms = $metric.region_load_p50_ms
        region_load_p95_ms = $metric.region_load_p95_ms
        mesh_dispatches = [int]$metric.mesh_dispatches
        mesh_uploads = [int]$metric.mesh_uploads
        mesh_workers = $metric.mesh_worker_job_kind
    }
    $measurements += [pscustomobject]$record
    Write-Host "DM2_TRIAL_PASS $trial frame_ms=$($record.average_frame_ms) missing_pct=$($record.focus_missing_pct) uploads=$($record.mesh_uploads)"
}
$summaryPath = Join-Path $EvidenceDir 'dm2-abba-summary.json'
$measurements | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$comparison = [ordered]@{
    source_sha = $sha
    frames = $Frames
    route = 'straight-18'
    environment = 'isolated_empty_APPDATA'
    trials = $measurements
}
$comparison | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm2-report.json') -Encoding UTF8
Write-Host "DM2_B4_ABBA_PASS trials=$($measurements.Count) sha=$sha results=$summaryPath"

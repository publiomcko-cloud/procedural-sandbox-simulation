param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-ready-cache-abba' } else { Join-Path $env:TEMP 'p5-ready-cache-abba' }),
    [ValidateRange(120, 5400)] [int]$Frames = 720
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
if (@(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'ABBA evidence directory not empty: refuses mixed runs'
}
$baseline = 'adaptive-skip-coarse'
$experiment = 'adaptive-skip-coarse-ready'
$profiles = @($baseline, $experiment, $experiment, $baseline)
$routes = @('idle', 'straight-18', 'straight-54', 'outback-54')
& (Join-Path $PSScriptRoot 'run-p5-deterministic-stream-benchmark.ps1') -GodotBin $GodotBin -EvidenceDir $EvidenceDir -Frames $Frames -Routes $routes -Profiles $profiles
if ($LASTEXITCODE -ne 0) { throw 'ABBA trial harness failed' }
$results = @()
foreach ($p in @(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File | Sort-Object Name)) {
    $obj = Get-Content -LiteralPath $p.FullName -Raw | ConvertFrom-Json
    $log = $p.FullName.Substring(0, $p.FullName.Length - '.metrics.json'.Length) + '.stdout.log'
    if (-not (Test-Path -LiteralPath $log)) { throw "Missing stream trace for $($p.Name)" }
    $cacheHits = 0
    $cacheProbes = 0
    $windows = 0
    $snapshots = 0
    $workerRun = @()
    $effectPending = 0
    $stageWork = @{}
    foreach ($raw in [IO.File]::ReadLines($log)) {
        $pos = $raw.IndexOf('PERF_TRACE ')
        if ($pos -lt 0) { continue }
        try { $e = $raw.Substring($pos + 11) | ConvertFrom-Json } catch { continue }
        switch ($e.event) {
            'terrain_stream_budget_window' {
                $windows++
                $cacheHits += [int]$e.ready_cache_hits
                $cacheProbes += [int]$e.ready_cache_pending_probes
                foreach ($key in $e.stage_work_usec.PSObject.Properties) {
                    if (-not $stageWork.ContainsKey($key.Name)) { $stageWork[$key.Name] = [double]0 }
                    $stageWork[$key.Name] += [double]$key.Value
                }
                foreach ($item in $e.mesh_dispatch_blockers.PSObject.Properties) {
                    if ($item.Name.StartsWith('effect_pending')) { $effectPending += [int]$item.Value }
                }
            }
            'terrain_mesh_snapshot' { $snapshots++ }
            'terrain_mesh_job_complete' { $workerRun += ([double]$e.worker_run_usec / 1000.0) }
        }
    }
    if ($windows -eq 0 -or [int]$obj.sampled_frames -ne ($Frames + 1)) { throw "Invalid window coverage: $($p.Name)" }
    if ($obj.profile -eq $experiment -and $cacheHits -le 0) { throw "Ready-cache was not exercised: $($p.Name)" }
    $results += [pscustomobject]@{
        run_id = $obj.run_id
        route = [string]$obj.route
        profile = [string]$obj.profile
        head_sha = [string]$obj.commit
        frames = [int]$obj.sampled_frames
        movement_frames = [int]$obj.measured_movement_frames
        frame_gt20_pct = [double]$obj.frames_over_20_ms_pct
        frame_gt33_pct = [double]$obj.frames_over_33_ms_pct
        process_mean_ms = [double]$obj.avg_process_ms
        focus_missing_pct = $obj.f10_focus_missing_pct
        perceived_missing_pct = $obj.f10_perceived_focus_missing_pct
        mesh_dispatches = [int]$obj.mesh_dispatches
        mesh_uploads = [int]$obj.mesh_uploads
        cache_hits = $cacheHits
        cache_pending_probes = $cacheProbes
        effect_blocked_attempts = $effectPending
        mesh_snapshots_over_2ms = $snapshots
        worker_jobs_observed = $workerRun.Count
        mesh_dispatch_and_upload_ms_per_frame = [Math]::Round([double]$stageWork['mesh_dispatch_and_upload'] / 1000.0 / ($Frames + 1), 5)
    }
}
if ($results.Count -ne 16) { throw "Bad trial count $($results.Count)" }
$verdict = 'PROMISING_DIAGNOSTIC'
$comparisons = @()
foreach ($route in $routes) {
    $control = @($results | Where-Object { $_.route -eq $route -and $_.profile -eq $baseline })
    $variant = @($results | Where-Object { $_.route -eq $route -and $_.profile -eq $experiment })
    if ($control.Count -ne 2 -or $variant.Count -ne 2) { throw "Unbalanced ABBA at $route" }
    $base20 = ($control | Measure-Object -Property frame_gt20_pct -Average).Average
    $trial20 = ($variant | Measure-Object -Property frame_gt20_pct -Average).Average
    $baseMs = ($control | Measure-Object -Property process_mean_ms -Average).Average
    $trialMs = ($variant | Measure-Object -Property process_mean_ms -Average).Average
    $baseDispatch = ($control | Measure-Object -Property mesh_dispatch_and_upload_ms_per_frame -Average).Average
    $trialDispatch = ($variant | Measure-Object -Property mesh_dispatch_and_upload_ms_per_frame -Average).Average
    $controlMissing = ($control | Measure-Object -Property perceived_missing_pct -Average).Average
    $trialMissing = ($variant | Measure-Object -Property perceived_missing_pct -Average).Average
    if (($trial20 - $base20) -ge 1.0 -or ($trialMs - $baseMs) -gt 0.5 -or
        ($route -ne 'idle' -and ($trialMissing - $controlMissing) -ge 1.0)) {
        $verdict = 'PERFORMANCE_REJECTED'
    }
    $comparisons += [pscustomobject]@{
        route = $route
        baseline_gt20_pct = [Math]::Round($base20, 3)
        ready_gt20_pct = [Math]::Round($trial20, 3)
        baseline_process_ms = [Math]::Round($baseMs, 3)
        ready_process_ms = [Math]::Round($trialMs, 3)
        baseline_dispatch_ms_per_frame = [Math]::Round($baseDispatch, 3)
        ready_dispatch_ms_per_frame = [Math]::Round($trialDispatch, 3)
        baseline_perceived_missing_pct = if ($route -eq 'idle') { $null } else { [Math]::Round($controlMissing, 3) }
        ready_perceived_missing_pct = if ($route -eq 'idle') { $null } else { [Math]::Round($trialMissing, 3) }
        ready_cache_hits = [int](($variant | Measure-Object -Property cache_hits -Sum).Sum)
        baseline_effect_blocked = [int](($control | Measure-Object -Property effect_blocked_attempts -Sum).Sum)
        ready_effect_blocked = [int](($variant | Measure-Object -Property effect_blocked_attempts -Sum).Sum)
    }
}
if ($verdict -ne 'PERFORMANCE_REJECTED') {
    $averageBase = ($comparisons | Measure-Object -Property baseline_dispatch_ms_per_frame -Average).Average
    $averageReady = ($comparisons | Measure-Object -Property ready_dispatch_ms_per_frame -Average).Average
    if ($averageReady -ge $averageBase) { $verdict = 'NO_MEASURED_DISPATCH_CPU_GAIN' }
}
$report = [ordered]@{
    verdict = $verdict
    isolation = 'headless_windows_software_scene'
    source_sha = [string]$results[0].head_sha
    frames_each = $Frames
    profiles = @($baseline, $experiment)
    per_route = $comparisons
    trials = $results
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'ready-cache-abba-verdict.json') -Encoding UTF8
Write-Host ('P5_STREAM_READY_CACHE_ABBA_VERDICT: ' + $verdict)
$comparisons | Format-Table -AutoSize | Out-Host
Write-Host 'P5_STREAM_READY_CACHE_ABBA_EVIDENCE_COMPLETE'

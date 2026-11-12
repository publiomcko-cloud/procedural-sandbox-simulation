param(
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-projection-e6-abba' } else { Join-Path $env:TEMP 'p5-projection-e6-abba' }),
    [ValidateRange(120,5400)][int]$Frames = 720,
    [string]$ExpectedSourceCommit = ''
)
$ErrorActionPreference = 'Stop'
function Percentile([double[]]$values, [double]$p) {
    if ($null -eq $values -or $values.Count -eq 0) { return $null }
    $sorted = @($values | Sort-Object)
    return [Math]::Round([double]$sorted[[int][Math]::Floor(($sorted.Count - 1) * $p)], 4)
}
$control = 'adaptive-skip-coarse'
$variant = 'adaptive-skip-coarse-pipeline'
$routes = @('idle', 'straight-18', 'straight-54', 'outback-54')
$files = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File | Sort-Object Name)
if ($files.Count -ne 16) { throw "E6_INCOMPLETE_RECEIPTS: $($files.Count) instead of 16" }
$results = @()
foreach ($p in $files) {
    $d = Get-Content -LiteralPath $p.FullName -Raw | ConvertFrom-Json
    if ($ExpectedSourceCommit -and [string]$d.commit -ne $ExpectedSourceCommit) {
        throw "E6_WRONG_SOURCE_COMMIT: $($p.Name)"
    }
    if ([int]$d.seed -ne 424242 -or [int]$d.requested_frames -ne $Frames -or
        [int]$d.sampled_frames -ne ($Frames + 1)) {
        throw "E6_NONDETERMINISTIC_TRIAL: $($p.Name)"
    }
    $log = $p.FullName.Substring(0, $p.FullName.Length - '.metrics.json'.Length) + '.stdout.log'
    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) {
        throw "E6_MISSING_STDOUT: $($p.Name)"
    }
    $workerMs = [System.Collections.Generic.List[double]]::new()
    $effectMs = [System.Collections.Generic.List[double]]::new()
    $publishedScopes = 0
    $maxProjectionInFlight = 0
    $pipelineConfig = $null
    $definitiveLoads = 0
    $pendingBlocks = 0
    $windows = 0
    $schedulerUsec = 0.0
    foreach ($raw in [IO.File]::ReadLines($log)) {
        $start = $raw.IndexOf('PERF_TRACE ')
        if ($start -lt 0) { continue }
        try { $e = $raw.Substring($start + 11) | ConvertFrom-Json }
        catch { continue }
        switch ([string]$e.event) {
            'effect_scope_published' {
                $timings = $e.projection_worker_timings_usec
                if ([double]$e.projection_worker_usec -gt 0) {
                    $workerMs.Add([double]$e.projection_worker_usec / 1000.0)
                    if ($null -ne $timings -and [double]$timings.effect_frame_build -gt 0) {
                        $effectMs.Add([double]$timings.effect_frame_build / 1000.0)
                    }
                    $publishedScopes++
                }
            }
            'effect_projection_pipeline_config' { $pipelineConfig = $e }
            'effect_prefetch_tick' {
                $maxProjectionInFlight = [Math]::Max($maxProjectionInFlight, [int]$e.projection_in_flight)
            }
            'terrain_region_load_complete' {
                if ([string]$e.purpose -eq 'load') { $definitiveLoads++ }
            }
            'terrain_stream_budget_window' {
                $windows++
                if ($null -ne $e.stage_work_usec) {
                    $schedulerUsec += [double]$e.stage_work_usec.mesh_dispatch_and_upload
                }
                if ($null -ne $e.mesh_dispatch_blockers) {
                    foreach ($b in $e.mesh_dispatch_blockers.PSObject.Properties) {
                        if ($b.Name.StartsWith('effect_pending')) { $pendingBlocks += [int]$b.Value }
                    }
                }
            }
        }
    }
    if ($windows -eq 0 -or $workerMs.Count -lt 1 -or $effectMs.Count -lt 1) {
        throw "E6_MISSING_PROJECTION_TIMING: $($p.Name)"
    }
    $expectedProjectionLimit = if ([string]$d.profile -eq $variant) { 4 } else { 2 }
    $expectedPublicationLimit = if ([string]$d.profile -eq $variant) { 2 } else { 1 }
    if ($null -eq $pipelineConfig -or [int]$pipelineConfig.source_worker_limit -ne 2 -or
        [int]$pipelineConfig.projection_worker_limit -ne $expectedProjectionLimit -or
        [int]$pipelineConfig.publish_limit_per_frame -ne $expectedPublicationLimit) {
        throw "E6_WRONG_PIPELINE_CONFIGURATION: $($p.Name)"
    }
    $results += [pscustomobject]@{
        trial = [string]$d.run_id
        route = [string]$d.route
        profile = [string]$d.profile
        commit = [string]$d.commit
        sampled_frames = [int]$d.sampled_frames
        frame_gt20_pct = [double]$d.frames_over_20_ms_pct
        frame_gt33_pct = [double]$d.frames_over_33_ms_pct
        process_mean_ms = [double]$d.avg_process_ms
        perceived_missing_pct = $d.f10_perceived_focus_missing_pct
        definitive_loads = $definitiveLoads
        mesh_dispatches = [int]$d.mesh_dispatches
        mesh_uploads = [int]$d.mesh_uploads
        projection_worker_count = $workerMs.Count
        published_scopes = $publishedScopes
        max_projection_in_flight = $maxProjectionInFlight
        projection_worker_p50_ms = Percentile $workerMs.ToArray() 0.5
        projection_worker_p95_ms = Percentile $workerMs.ToArray() 0.95
        projection_effect_p50_ms = Percentile $effectMs.ToArray() 0.5
        effect_pending_attempts = $pendingBlocks
        dispatch_ms_per_frame = [Math]::Round($schedulerUsec / 1000.0 / ($Frames + 1), 5)
    }
    Write-Host "P5_E6_TRIAL_VALIDATED: $($p.Name) projections=$($workerMs.Count) peak_projection_in_flight=$maxProjectionInFlight definitive=$definitiveLoads"
}
$distinct = @($results | Select-Object -ExpandProperty commit -Unique)
if ($results.Count -ne 16 -or $distinct.Count -ne 1) { throw 'E6_INCOMPLETE_OR_MIXED_COMMITS' }
$routesFound = @($results | Select-Object -ExpandProperty route -Unique)
if ($routesFound.Count -ne 4) { throw 'E6_MISSING_ROUTES' }
$verdict = 'PROJECTION_GAIN_UNPROVEN'
$summary = @()
foreach ($route in $routes) {
    $b = @($results | Where-Object { $_.route -eq $route -and $_.profile -eq $control })
    $v = @($results | Where-Object { $_.route -eq $route -and $_.profile -eq $variant })
    if ($b.Count -ne 2 -or $v.Count -ne 2) { throw "E6_UNBALANCED_ABBA: $route" }
    $baseWorker = ($b | Measure-Object -Property projection_worker_p50_ms -Average).Average
    $fastWorker = ($v | Measure-Object -Property projection_worker_p50_ms -Average).Average
    $baseEffect = ($b | Measure-Object -Property projection_effect_p50_ms -Average).Average
    $fastEffect = ($v | Measure-Object -Property projection_effect_p50_ms -Average).Average
    $base20 = ($b | Measure-Object -Property frame_gt20_pct -Average).Average
    $fast20 = ($v | Measure-Object -Property frame_gt20_pct -Average).Average
    $baseProcess = ($b | Measure-Object -Property process_mean_ms -Average).Average
    $fastProcess = ($v | Measure-Object -Property process_mean_ms -Average).Average
    $baseLoads = ($b | Measure-Object -Property definitive_loads -Average).Average
    $fastLoads = ($v | Measure-Object -Property definitive_loads -Average).Average
    $baseMissing = ($b | Measure-Object -Property perceived_missing_pct -Average).Average
    $fastMissing = ($v | Measure-Object -Property perceived_missing_pct -Average).Average
    if (($fast20 - $base20) -ge 1.0 -or ($fastProcess - $baseProcess) -gt 0.5 -or
        ($route -ne 'idle' -and ($fastMissing - $baseMissing) -ge 1.0) -or
        $fastLoads -lt ($baseLoads - 1.0)) {
        $verdict = 'PERFORMANCE_REJECTED'
    }
    $summary += [pscustomobject]@{
        route = $route
        baseline_projection_p50_ms = [Math]::Round($baseWorker, 3)
        e6_projection_p50_ms = [Math]::Round($fastWorker, 3)
        projection_worker_gain_pct = if ($baseWorker -gt 0) { [Math]::Round(100.0 * ($baseWorker - $fastWorker) / $baseWorker, 3) } else { $null }
        baseline_effect_p50_ms = [Math]::Round($baseEffect, 3)
        e6_effect_p50_ms = [Math]::Round($fastEffect, 3)
        baseline_process_ms = [Math]::Round($baseProcess, 3)
        e6_process_ms = [Math]::Round($fastProcess, 3)
        baseline_frame_gt20_pct = [Math]::Round($base20, 3)
        e6_frame_gt20_pct = [Math]::Round($fast20, 3)
        baseline_definitive_loads = [Math]::Round($baseLoads, 2)
        e6_definitive_loads = [Math]::Round($fastLoads, 2)
        baseline_perceived_missing_pct = if ($route -eq 'idle') { $null } else { [Math]::Round($baseMissing, 3) }
        e6_perceived_missing_pct = if ($route -eq 'idle') { $null } else { [Math]::Round($fastMissing, 3) }
    }
}
if ($verdict -ne 'PERFORMANCE_REJECTED') {
    $controlLoads = ($summary | Measure-Object -Property baseline_definitive_loads -Sum).Sum
    $fastLoads = ($summary | Measure-Object -Property e6_definitive_loads -Sum).Sum
    if ($fastLoads -gt $controlLoads) {
        $verdict = 'CANDIDATE_REQUIRES_FULL_QUALIFICATION'
    } else {
        $verdict = 'NO_DEFINITIVE_PROGRESS'
    }
}
$record = [ordered]@{
    verdict = $verdict
    source_commit = [string]$distinct[0]
    experimental_profile = $variant
    baseline_profile = $control
    seed = 424242
    frames = $Frames
    benchmark_mode = 'headless_windows'
    summary = $summary
    trials = $results
}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'projection-e6-abba-verdict.json') -Encoding UTF8
Write-Host "P5_PROJECTION_E6_ABBA_VERDICT: $verdict"
$summary | Format-Table -AutoSize | Out-Host
Write-Host "P5_PROJECTION_E6_ABBA_EVIDENCE_COMPLETE"

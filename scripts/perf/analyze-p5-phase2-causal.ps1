param(
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-phase2-causal' } else { Join-Path $env:TEMP 'p5-phase2-causal' }),
    [int]$ExpectedFrames = 720,
    [int]$ExpectedTrials = 16,
    [string]$ExpectedSourceCommit = ''
)
$ErrorActionPreference = 'Stop'
function Percentile([double[]]$Values, [double]$P) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $ordered = @($Values | Sort-Object)
    return [Math]::Round([double]$ordered[[int][Math]::Floor(($ordered.Count - 1) * $P)], 3)
}
function Summary([double[]]$Values) {
    return [ordered]@{
        count = if ($null -eq $Values) { 0 } else { $Values.Count }
        p50_ms = Percentile $Values 0.50
        p95_ms = Percentile $Values 0.95
    }
}
$logs = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.stdout.log' -File | Sort-Object Name)
if ($logs.Count -ne $ExpectedTrials) {
    throw "PHASE2_BAD_TRIAL_COUNT: actual=$($logs.Count) expected=$ExpectedTrials"
}
$matrix = @()
foreach ($file in $logs) {
    $windows = 0
    $frames = 0
    $f10Frames = 0
    $focusMissing = 0
    $perceivedMissing = 0
    $bad20 = 0
    $bad33 = 0
    $meshDispatches = 0
    $meshUploads = 0
    $coarsePublished = 0
    $coarseDiscarded = 0
    $finalPublished = 0
    $effectScopesPublished = 0
    $effectSourcesReady = 0
    $stageUsec = @{}
    $blockers = @{}
    $snapshotWaitMs = [System.Collections.Generic.List[double]]::new()
    $snapshotCpuMs = [System.Collections.Generic.List[double]]::new()
    $meshWorkerWaitMs = [System.Collections.Generic.List[double]]::new()
    $meshWorkerRunMs = [System.Collections.Generic.List[double]]::new()
    $meshUploadMs = [System.Collections.Generic.List[double]]::new()
    $surfaceWorkerMs = [System.Collections.Generic.List[double]]::new()
    $effectPrefetchMs = [System.Collections.Generic.List[double]]::new()
    $effectPending = [System.Collections.Generic.List[double]]::new()
    $effectGenerationActive = [System.Collections.Generic.List[double]]::new()
    $effectProjectionActive = [System.Collections.Generic.List[double]]::new()
    $coarseReadyMs = [System.Collections.Generic.List[double]]::new()
    $definitiveReadyMs = [System.Collections.Generic.List[double]]::new()
    $workerTypes = @{}
    $profileEvent = $null
    $completeEvent = $null
    foreach ($raw in [System.IO.File]::ReadLines($file.FullName)) {
        $line = $raw -replace '\x00', ''
        if ($line.StartsWith('P5_STREAM_BENCH_COMPLETE: ')) {
            $completeEvent = $line.Substring('P5_STREAM_BENCH_COMPLETE: '.Length) | ConvertFrom-Json
        }
        $start = $line.IndexOf('PERF_TRACE ')
        if ($start -lt 0) { continue }
        try { $e = $line.Substring($start + 11) | ConvertFrom-Json }
        catch { continue }
        switch ([string]$e.event) {
            'terrain_stream_profile' { $profileEvent = $e }
            'terrain_stream_budget_window' {
                $windows++
                $frames += [int]$e.frame_count
                $f10Frames += [int]$e.f10_movement_frames
                $focusMissing += [int]$e.f10_focus_missing_frames
                $perceivedMissing += [int]$e.f10_perceived_focus_missing_frames
                $bad20 += [int]$e.frames_over_20_ms
                $bad33 += [int]$e.frames_over_33_ms
                $meshDispatches += [int]$e.mesh_dispatches
                $meshUploads += [int]$e.mesh_uploads
                foreach ($prop in $e.stage_work_usec.PSObject.Properties) {
                    if (-not $stageUsec.ContainsKey($prop.Name)) { $stageUsec[$prop.Name] = [long]0 }
                    $stageUsec[$prop.Name] += [long]$prop.Value
                }
                foreach ($prop in $e.mesh_dispatch_blockers.PSObject.Properties) {
                    if (-not $blockers.ContainsKey($prop.Name)) { $blockers[$prop.Name] = [long]0 }
                    $blockers[$prop.Name] += [long]$prop.Value
                }
            }
            'terrain_mesh_snapshot' {
                $snapshotWaitMs.Add([double]$e.queue_wait_usec / 1000.0)
                $snapshotCpuMs.Add([double]$e.duration_usec / 1000.0)
            }
            'terrain_mesh_job_complete' {
                $meshWorkerWaitMs.Add([double]$e.worker_queue_usec / 1000.0)
                $meshWorkerRunMs.Add([double]$e.worker_run_usec / 1000.0)
                $meshUploadMs.Add([double]$e.upload_usec / 1000.0)
                $kind = [string]$e.job_kind
                if (-not $workerTypes.ContainsKey($kind)) { $workerTypes[$kind] = [System.Collections.Generic.List[double]]::new() }
                $workerTypes[$kind].Add([double]$e.worker_run_usec / 1000.0)
            }
            'environment_surface_cache_job' { $surfaceWorkerMs.Add([double]$e.worker_usec / 1000.0) }
            'effect_prefetch_tick' {
                $effectPrefetchMs.Add([double]$e.duration_usec / 1000.0)
                $effectPending.Add([double]$e.pending)
                $effectGenerationActive.Add([double]$e.generation_in_flight)
                $effectProjectionActive.Add([double]$e.projection_in_flight)
            }
            'effect_scope_published' { $effectScopesPublished++ }
            'effect_source_ready' { $effectSourcesReady++ }
            'terrain_region_publish' { $finalPublished++ }
            'terrain_region_coarse_visible' {
                $coarsePublished++
                $coarseReadyMs.Add([double]$e.queue_to_coarse_usec / 1000.0)
            }
            'terrain_region_coarse_discarded' { $coarseDiscarded++ }
            'terrain_region_load_complete' {
                if ($e.purpose -eq 'load') { $definitiveReadyMs.Add([double]$e.elapsed_usec / 1000.0) }
            }
        }
    }
    if ($null -eq $profileEvent -or $null -eq $completeEvent) {
        throw "PHASE2_MISSING_PROFILE_OR_TERMINAL_RECEIPT: $($file.Name)"
    }
    if ($frames -ne ($ExpectedFrames + 1) -or $completeEvent.frames -ne $ExpectedFrames -or $completeEvent.seed -ne 424242) {
        throw "PHASE2_INCOMPLETE_OR_NONDETERMINISTIC_FRAMES: $($file.Name) sampled=$frames"
    }
    if ($profileEvent.profile -ne $completeEvent.profile -or $profileEvent.profile_mismatch) {
        throw "PHASE2_PROFILE_MISMATCH: $($file.Name)"
    }
    if ($completeEvent.route -ne 'idle' -and $f10Frames -ne $ExpectedFrames) {
        throw "PHASE2_F10_MISSING_FRAMES: $($file.Name) recorded=$f10Frames"
    }
    if ($completeEvent.route -eq 'idle' -and $f10Frames -ne 0) {
        throw "PHASE2_IDLE_MOVEMENT: $($file.Name)"
    }
    $stageRank = @(
        $stageUsec.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            [ordered]@{
                stage = [string]$_.Key
                total_ms = [Math]::Round([double]$_.Value / 1000.0, 3)
                mean_ms_per_frame = [Math]::Round([double]$_.Value / 1000.0 / $frames, 5)
            }
        }
    )
    $blockerRank = @(
        $blockers.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            [ordered]@{ reason = [string]$_.Key; count = [int]$_.Value }
        }
    )
    $perKind = [ordered]@{}
    foreach ($k in @($workerTypes.Keys | Sort-Object)) {
        $perKind[$k] = Summary $workerTypes[$k].ToArray()
    }
    $matrix += [ordered]@{
        trial = $file.BaseName
        route = [string]$completeEvent.route
        profile = [string]$completeEvent.profile
        seed = [int]$completeEvent.seed
        samples = [int]$frames
        movement_frames = [int]$f10Frames
        focus_missing_pct = if ($f10Frames -gt 0) { [Math]::Round(100.0 * $focusMissing / $f10Frames, 3) } else { $null }
        perceived_focus_missing_pct = if ($f10Frames -gt 0) { [Math]::Round(100.0 * $perceivedMissing / $f10Frames, 3) } else { $null }
        frames_over_20_pct = [Math]::Round(100.0 * $bad20 / $frames, 3)
        frames_over_33_pct = [Math]::Round(100.0 * $bad33 / $frames, 3)
        mesh_dispatches = [int]$meshDispatches
        mesh_uploads = [int]$meshUploads
        final_regions_published = [int]$definitiveReadyMs.Count
        coarse_regions_visible = [int]$coarsePublished
        coarse_regions_discarded = [int]$coarseDiscarded
        effect_sources_ready = [int]$effectSourcesReady
        effect_scopes_published = [int]$effectScopesPublished
        effect_pending_p50 = Percentile $effectPending.ToArray() 0.5
        effect_pending_p95 = Percentile $effectPending.ToArray() 0.95
        effect_generation_active_p50 = Percentile $effectGenerationActive.ToArray() 0.5
        effect_projection_active_p50 = Percentile $effectProjectionActive.ToArray() 0.5
        predispatch_stage_wait = Summary $snapshotWaitMs.ToArray()
        snapshot_main_thread = Summary $snapshotCpuMs.ToArray()
        worker_wait = Summary $meshWorkerWaitMs.ToArray()
        mesh_worker = Summary $meshWorkerRunMs.ToArray()
        mesh_upload = Summary $meshUploadMs.ToArray()
        environment_surface_worker = Summary $surfaceWorkerMs.ToArray()
        effect_prefetch_tick = Summary $effectPrefetchMs.ToArray()
        coarse_first_visibility = Summary $coarseReadyMs.ToArray()
        definitive_load = Summary $definitiveReadyMs.ToArray()
        worker_by_kind = $perKind
        blocked_dispatch = $blockerRank
        stage_work = $stageRank
    }
    Write-Host "PHASE2_CAUSAL_TRIAL_PASS: $($file.Name) stages=$($stageRank.Count) blockers=$($blockerRank.Count) final=$($definitiveReadyMs.Count)"
}
$groups = @{}
foreach ($row in $matrix) {
    $key = ([string]$row['route']) + '|' + ([string]$row['profile'])
    if (-not $groups.ContainsKey($key)) { $groups[$key] = 0 }
    $groups[$key] += 1
}
if ($groups.Count -ne 8) { throw "PHASE2_INCOMPLETE_ROUTE_PROFILE_GROUPS: actual=$($groups.Count) expected=8" }
foreach ($entry in $groups.GetEnumerator()) {
    if ([int]$entry.Value -ne 2) { throw "PHASE2_UNBALANCED_ABBA: group=$($entry.Key) actual=$($entry.Value)" }
}
# Do not rely on PowerShell 5.1 ConvertFrom-Json array-enumeration semantics:
# audit one sidecar receipt per trajectory instead.
$metricFiles = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File)
if ($metricFiles.Count -ne $ExpectedTrials) { throw "PHASE2_SOURCE_RECEIPTS_INCOMPLETE: actual=$($metricFiles.Count) expected=$ExpectedTrials" }
$sourceShas = @($metricFiles | ForEach-Object {
    $receipt = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    [string]$receipt.commit
} | Sort-Object -Unique)
if ($sourceShas.Count -ne 1) { throw 'PHASE2_MIXED_SOURCE_COMMITS' }
$sourceSha = [string]$sourceShas[0]
if ($ExpectedSourceCommit -and $ExpectedSourceCommit -ne $sourceSha) { throw "PHASE2_EXPECTED_SHA_MISMATCH: actual=$sourceSha expected=$ExpectedSourceCommit" }
$analysisSha = (& git rev-parse HEAD).Trim()
$record = [ordered]@{
    verdict = 'PHASE2_CAUSAL_DIAGNOSTIC_CAPTURED'
    source_commit = $sourceSha
    analysis_commit = $analysisSha
    expected_trials = $ExpectedTrials
    full_frame_coverage = $true
    trials = $matrix
}
$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'causal-analysis.json') -Encoding UTF8
$report = @(
    '# P5 Phase 2 — deterministic causal diagnostic'
    ''
    "Benchmark source commit: $sourceSha"
    "Analysis tool commit: $analysisSha"
    'Status: PHASE2_CAUSAL_DIAGNOSTIC_CAPTURED (observation, not optimization).'
    ''
    '| Route | Profile | Focus missing % | Preview-covered focus missing % | Final regions | Coarse previews | Effect-pending p50 | Effect blocked | Worker p50 ms |'
    '|---|---|---:|---:|---:|---:|---:|---:|---:|'
)
foreach ($row in $matrix) {
    $effectBlocked = @($row.blocked_dispatch | Where-Object { $_.reason -eq 'effect_pending_corner' })
    $blockedCount = if ($effectBlocked.Count -gt 0) { [int]$effectBlocked[0].count } else { 0 }
    $workerP50 = if ($null -eq $row.mesh_worker.p50_ms) { '-' } else { [string]$row.mesh_worker.p50_ms }
    $report += "| $($row['route']) | $($row['profile']) | $($row['focus_missing_pct']) | $($row['perceived_focus_missing_pct']) | $($row['final_regions_published']) | $($row['coarse_regions_visible']) | $($row['effect_pending_p50']) | $blockedCount | $workerP50 |"
}
$report += ''
$report += 'Interpret blocked-dispatch count as failed admission attempts, **not time spent waiting**. Work-stage milliseconds overlap other processes; no exclusive CPU attribution.'
$report | Set-Content -LiteralPath (Join-Path $EvidenceDir 'causal-report.md') -Encoding UTF8
Write-Host "P5_PHASE2_CAUSAL_ANALYSIS_PASS: trials=$($matrix.Count) source=$sourceSha analyzer=$analysisSha"

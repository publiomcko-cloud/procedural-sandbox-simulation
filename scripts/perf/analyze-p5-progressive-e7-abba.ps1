param(
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-e7-abba' } else { Join-Path $env:TEMP 'p5-e7-abba' }),
    [ValidateRange(120,5400)][int]$Frames = 720,
    [string]$ExpectedSourceCommit = ''
)
$ErrorActionPreference = 'Stop'
$control = 'adaptive-skip-coarse'
$experiment = 'adaptive-skip-progressive'
$routes = @('idle', 'straight-18', 'straight-54', 'outback-54')
$pattern = @($control, $experiment, $experiment, $control)
$files = @(Get-ChildItem -LiteralPath $EvidenceDir -Filter '*.metrics.json' -File | Sort-Object Name)
if ($files.Count -ne 16) { throw "E7_INCOMPLETE_RECEIPTS: actual=$($files.Count)" }
$results = @()
foreach ($p in $files) {
    $obj = Get-Content -LiteralPath $p.FullName -Raw | ConvertFrom-Json
    if ($ExpectedSourceCommit -and [string]$obj.commit -ne $ExpectedSourceCommit) {
        throw "E7_BAD_SOURCE_COMMIT: $($p.Name)"
    }
    if ([int]$obj.seed -ne 424242 -or [int]$obj.requested_frames -ne $Frames -or
        [int]$obj.sampled_frames -ne ($Frames + 1)) {
        throw "E7_BAD_DETERMINISTIC_ROUTE: $($p.Name)"
    }
    $log = $p.FullName.Substring(0, $p.FullName.Length - '.metrics.json'.Length) + '.stdout.log'
    if (-not (Test-Path -LiteralPath $log -PathType Leaf)) {
        throw "E7_MISSING_TRACE: $($p.Name)"
    }
    $previewCount = 0
    $fullLoads = 0
    $progressiveCount = 0
    $focusedCount = 0
    $revoked = 0
    $revokedRegions = 0
    $readyWindowSamples = 0
    $effectBlocks = 0
    $progressiveWindowSum = 0
    $firstElapsedMs = $null
    $firstByStage = @{}
    $fullLeadMs = New-Object 'System.Collections.Generic.List[double]'
    foreach ($raw in [System.IO.File]::ReadLines($log)) {
        $at = $raw.IndexOf('PERF_TRACE ')
        if ($at -lt 0) { continue }
        try { $e = $raw.Substring($at + 11) | ConvertFrom-Json } catch { continue }
        switch ([string]$e.event) {
            'terrain_chunk_progressive_visible' {
                if ([string]$obj.profile -ne $experiment) {
                    throw "E7_BASELINE_CONTAMINATION: $($p.Name)"
                }
                if ([bool]$e.has_authoritative_region_commit) {
                    throw "E7_PREMATURE_REGION_AUTHORITY: $($p.Name)"
                }
                $progressiveCount++
                if ([bool]$e.focused) { $focusedCount++ }
                $elapsedMs = [double]$e.elapsed_usec / 1000.0
                if ($null -eq $firstElapsedMs -or $elapsedMs -lt $firstElapsedMs) { $firstElapsedMs = $elapsedMs }
                $key = "$($e.region[0]),$($e.region[1]):$($e.stage_token)"
                if (-not $firstByStage.ContainsKey($key)) { $firstByStage[$key] = $elapsedMs }
            }
            'terrain_region_load_complete' {
                if ([string]$e.purpose -eq 'load') {
                    $fullLoads++
                    $key = "$($e.region[0]),$($e.region[1]):$($e.stage_token)"
                    if ($firstByStage.ContainsKey($key)) {
                        $lead = [double]$e.elapsed_usec / 1000.0 - [double]$firstByStage[$key]
                        if ($lead -lt -0.001) { throw 'E7_NONMONOTONIC_CHUNK_STAGE_LIFETIME' }
                        $fullLeadMs.Add($lead)
                    }
                }
            }
            'terrain_region_coarse_visible' {
                $previewCount++
                if ([string]$obj.profile -eq $experiment -and [int]$e.preview_patch_count -ne 16) {
                    throw "E7_COARSE_PREVIEW_PATCH_COUNT_INVALID: $($p.Name)"
                }
            }
            'terrain_progressive_chunks_revoked' {
                $revoked += [int]$e.count
                $revokedRegions++
                if ([bool]$e.authoritative_region_committed) {
                    throw 'E7_PROVISIONAL_REVOCATION_MISLABELED'
                }
            }
            'terrain_stream_budget_window' {
                $readyWindowSamples++
                $progressiveWindowSum += [int]$e.progressive_chunks_published
                foreach ($block in $e.mesh_dispatch_blockers.PSObject.Properties) {
                    if ($block.Name.StartsWith('effect_pending')) { $effectBlocks += [int]$block.Value }
                }
            }
        }
    }
    if ($readyWindowSamples -eq 0) { throw "E7_NO_FRAME_WINDOW_METRICS: $($p.Name)" }
    $results += [pscustomobject]@{
        trial_file = $p.Name
        route = [string]$obj.route
        profile = [string]$obj.profile
        commit = [string]$obj.commit
        frames = [int]$obj.sampled_frames
        process_mean_ms = [double]$obj.avg_process_ms
        frame_gt20_pct = [double]$obj.frames_over_20_ms_pct
        frame_gt33_pct = [double]$obj.frames_over_33_ms_pct
        focus_missing_pct = $obj.f10_focus_missing_pct
        perceived_missing_pct = $obj.f10_perceived_focus_missing_pct
        mesh_dispatches = [int]$obj.mesh_dispatches
        mesh_uploads = [int]$obj.mesh_uploads
        coarse_regions = $previewCount
        complete_regions = $fullLoads
        progressive_chunks = $progressiveCount
        progressive_focused_chunks = $focusedCount
        progressive_revoked_chunks = $revoked
        progressive_revoked_regions = $revokedRegions
        first_progressive_stage_ms = $firstElapsedMs
        early_vs_full_mean_lead_ms = if ($fullLeadMs.Count -gt 0) {
            [Math]::Round((($fullLeadMs | Measure-Object -Average).Average), 3)
        } else { $null }
        progressive_window_publishes = $progressiveWindowSum
        effect_pending_blockers = $effectBlocks
    }
    Write-Host "P5_E7_RECEIPT_PASS: $($p.Name) early=$progressiveCount focus=$focusedCount loads=$fullLoads"
}
$commits = @($results | Select-Object -ExpandProperty commit -Unique)
if ($commits.Count -ne 1) { throw 'E7_MIXED_HEAD_COMMITS' }
$summary = @()
$verdict = 'NO_HIGH_SPEED_PROGRESS'
foreach ($route in $routes) {
    $trials = @($results | Where-Object { $_.route -eq $route } | Sort-Object trial_file)
    if ($trials.Count -ne 4) { throw "E7_MISSING_ABBA_ROUTE: $route" }
    for ($i = 0; $i -lt 4; $i++) {
        if ([string]$trials[$i].profile -ne $pattern[$i]) {
            throw "E7_BAD_ABBA_PROFILE_ORDER: $route, index=$i"
        }
    }
    $b = @($trials | Where-Object { $_.profile -eq $control })
    $v = @($trials | Where-Object { $_.profile -eq $experiment })
    $bm = ($b | Measure-Object -Property process_mean_ms -Average).Average
    $vm = ($v | Measure-Object -Property process_mean_ms -Average).Average
    $b20 = ($b | Measure-Object -Property frame_gt20_pct -Average).Average
    $v20 = ($v | Measure-Object -Property frame_gt20_pct -Average).Average
    $bd = ($b | Measure-Object -Property complete_regions -Average).Average
    $vd = ($v | Measure-Object -Property complete_regions -Average).Average
    $bc = ($b | Measure-Object -Property perceived_missing_pct -Average).Average
    $vc = ($v | Measure-Object -Property perceived_missing_pct -Average).Average
    $progressive = [int](($v | Measure-Object -Property progressive_chunks -Sum).Sum)
    $focused = [int](($v | Measure-Object -Property progressive_focused_chunks -Sum).Sum)
    $revoked = [int](($v | Measure-Object -Property progressive_revoked_chunks -Sum).Sum)
    if (($v20 - $b20) -ge 1.0 -or ($vm - $bm) -gt 0.5 -or
        ($route -ne 'idle' -and ($vc - $bc) -ge 1.0) -or ($vd -lt ($bd - 1.0))) {
        $verdict = 'PERFORMANCE_REJECTED'
    }
    $summary += [pscustomobject]@{
        route = $route
        baseline_process_ms = [Math]::Round($bm, 3)
        progressive_process_ms = [Math]::Round($vm, 3)
        baseline_gt20_pct = [Math]::Round($b20, 3)
        progressive_gt20_pct = [Math]::Round($v20, 3)
        baseline_complete_loads = [Math]::Round($bd, 2)
        progressive_complete_loads = [Math]::Round($vd, 2)
        progressive_visible_chunks = $progressive
        progressive_focused_chunks = $focused
        progressive_revoked_chunks = $revoked
        baseline_perceived_focus_missing_pct = if ($route -eq 'idle') { $null } else { [Math]::Round($bc, 3) }
        progressive_perceived_focus_missing_pct = if ($route -eq 'idle') { $null } else { [Math]::Round($vc, 3) }
    }
}
if ($verdict -ne 'PERFORMANCE_REJECTED') {
    $slow = @($summary | Where-Object { $_.route -in @('straight-54', 'outback-54') })
    if (($slow | Measure-Object -Property progressive_focused_chunks -Sum).Sum -gt 0) {
        $verdict = 'CANDIDATE_REQUIRES_FULL_QUALIFICATION'
    }
}
$report = [ordered]@{
    verdict = $verdict
    source_sha = [string]$commits[0]
    baseline = $control
    experiment = $experiment
    frames = $Frames
    seed = 424242
    mode = 'headless_windows'
    summary = $summary
    trials = $results
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'progressive-e7-abba-verdict.json') -Encoding UTF8
Write-Host ("P5_PROGRESSIVE_E7_ABBA_VERDICT: " + $verdict)
$summary | Format-Table -AutoSize | Out-Host
Write-Host 'P5_PROGRESSIVE_E7_ABBA_EVIDENCE_COMPLETE'

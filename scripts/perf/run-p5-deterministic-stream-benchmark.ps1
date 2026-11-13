param(
    [ValidateSet('idle', 'straight-2', 'straight-18', 'straight-54', 'outback-18', 'outback-54')]
    [string[]]$Routes = @('straight-18', 'straight-54'),
    [ValidateSet('baseline', 'adaptive', 'adaptive-skip', 'adaptive-skip-lookahead', 'adaptive-skip-coarse', 'adaptive-skip-progressive')]
    [string[]]$Profiles = @('adaptive-skip', 'adaptive-skip-coarse', 'adaptive-skip-coarse', 'adaptive-skip'),
    [ValidateRange(120, 18000)]
    [int]$Frames = 720,
    [ValidateRange(0, 12000)]
    [int]$WarmupFrames = 0,
    [switch]$CaptureProcessCpu,
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-deterministic-evidence' } else { Join-Path $env:TEMP 'p5-deterministic-evidence' })
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $repoRoot 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Godot missing: $GodotBin" }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Wrong Godot version: $version" }

function Get-Percentile([object[]]$Values, [double]$P) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | ForEach-Object { [double]$_ } | Sort-Object)
    return [Math]::Round($sorted[[int][Math]::Floor(($sorted.Count - 1) * $P)], 3)
}

$allResults = @()
$runIndex = 0
foreach ($route in $Routes) {
    foreach ($profile in $Profiles) {
        $runIndex++
        $runId = ('{0:d2}-{1}-{2}' -f $runIndex, $route, $profile)
        $stdout = Join-Path $EvidenceDir "$runId.stdout.log"
        $stderr = Join-Path $EvidenceDir "$runId.stderr.log"
        $metricsPath = Join-Path $EvidenceDir "$runId.metrics.json"
        # Each trial starts from a separate empty world, including user://mods,
        # without touching the owner's actual user://worlds or installed mods.
        $isolated = Join-Path $EvidenceDir "user-$runId"
        New-Item -ItemType Directory -Force -Path $isolated | Out-Null
        $env:APPDATA = $isolated
        $env:SANDBOX_STREAM_BENCHMARK = '1'
        $env:SANDBOX_STREAM_PROFILE = $profile
        $env:SANDBOX_PERF_TRACE = '1'
        $env:SANDBOX_PERF_TRACE_MIN_MS = '2.0'
        $arguments = "--headless --path " + ('"{0}"' -f $project) +
            " --max-fps 60 -- --stream-benchmark-route=$route --stream-benchmark-frames=$Frames --start-water=ocean"
        if ($WarmupFrames -gt 0) {
            $arguments += " --stream-benchmark-warmup-frames=$WarmupFrames"
        }
        Write-Host "P5 deterministic trial $runId HEAD=$commit Godot=$version warmup_frames=$WarmupFrames"
        $process = Start-Process -FilePath $GodotBin -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $timeoutMs = [int]([Math]::Max(120000, ($Frames + $WarmupFrames) / 60.0 * 9000))
        $cpuSamples = @()
        $cpuLastWall = [DateTime]::UtcNow
        $cpuLastSeconds = 0.0
        $cpuWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $logicalCpus = [Environment]::ProcessorCount
        $timedOut = $false
        # Keep the original blocking semantics when CPU sampling is disabled.
        if (-not $CaptureProcessCpu) {
            $timedOut = -not $process.WaitForExit($timeoutMs)
        } else {
            while (-not $process.WaitForExit(500)) {
                if ($cpuWatch.ElapsedMilliseconds -gt $timeoutMs) { $timedOut = $true; break }
                # Godot's _console.exe is a lightweight Windows parent/launcher.
                # Measure its *engine child process*, not just the ~6 MiB console stub.
                $trackedPids = @([int]$process.Id)
                try {
                    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($process.Id)" -ErrorAction SilentlyContinue)
                    foreach ($child in $children) {
                        if ([string]$child.Name -like 'Godot*') {
                            $trackedPids += [int]$child.ProcessId
                        }
                    }
                    # Detached engine fallback: bind by the EXACT benchmark route
                    # and repository path so other local Godot sessions are excluded.
                    $candidates = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue)
                    foreach ($candidate in $candidates) {
                        if ([string]$candidate.CommandLine -like "*stream-benchmark-route=$route*" -and
                            [string]$candidate.CommandLine -like "*$project*" -and
                            $trackedPids -notcontains [int]$candidate.ProcessId) {
                            $trackedPids += [int]$candidate.ProcessId
                        }
                    }
                } catch { Write-Warning "DM9 CPU engine process lookup failed: $_" }
                $family = @(Get-Process -Id ($trackedPids | Sort-Object -Unique) -ErrorAction SilentlyContinue)
                if ($family.Count -eq 0) { continue }
                $cpuSeconds = 0.0
                $rssBytes = 0.0
                $privateBytes = 0.0
                $threadCount = 0
                foreach ($member in $family) {
                    $cpuSeconds += [double]$member.CPU
                    $rssBytes += [double]$member.WorkingSet64
                    $privateBytes += [double]$member.PrivateMemorySize64
                    $threadCount += $member.Threads.Count
                }
                $wall = [DateTime]::UtcNow
                $elapsedSeconds = ($wall - $cpuLastWall).TotalSeconds
                if ($elapsedSeconds -gt 0.1) {
                    $cpuSamples += [ordered]@{
                        relative_wall_ms = [Math]::Round($cpuWatch.Elapsed.TotalMilliseconds, 1)
                        cpu_pct_total_capacity = [Math]::Round(100.0 * [Math]::Max(0.0, $cpuSeconds - $cpuLastSeconds) / ($elapsedSeconds * $logicalCpus), 2)
                        working_set_mb = [Math]::Round($rssBytes / 1048576.0, 2)
                        private_memory_mb = [Math]::Round($privateBytes / 1048576.0, 2)
                        thread_count = $threadCount
                        tracked_process_ids = @($family | ForEach-Object { $_.Id })
                        tracked_process_names = @($family | ForEach-Object { $_.ProcessName })
                    }
                    $cpuLastWall = $wall
                    $cpuLastSeconds = $cpuSeconds
                }
            }
        }
        if ($timedOut) {
            $process.Kill()
            $process.WaitForExit()
            throw "Benchmark timeout: $runId ($stdout)"
        }
        if ($CaptureProcessCpu) {
            $cpuSamples | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $EvidenceDir "$runId.cpu.json") -Encoding UTF8
            $maxRss = if ($cpuSamples.Count -gt 0) { (@($cpuSamples | ForEach-Object { [double]$_['working_set_mb'] }) | Measure-Object -Maximum).Maximum } else { 0.0 }
            if ($maxRss -lt 40.0) {
                throw "DM9_PROCESS_SAMPLING_INVALID: engine not observed; maximum tracked RSS=$maxRss MiB. See $runId.cpu.json"
            }
        }
        # PowerShell 5.1 on the service runner can expose an empty ExitCode
        # even when WaitForExit returned success. A positive terminal marker,
        # exact route/seed/profile receipt, and error-free console are required.
        $process.Refresh()
        if ($null -ne $process.ExitCode -and [int]$process.ExitCode -ne 0) {
            throw "Godot exit $($process.ExitCode): $runId ($stdout / $stderr)"
        }
        $stderrContents = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
        if ($stderrContents -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)') {
            throw "Godot engine stderr contained an error: $runId ($stderr)"
        }

        $lines = @(Get-Content -LiteralPath $stdout | ForEach-Object { $_ -replace '\x00', '' })
        $completeLine = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
        $profileLine = @($lines | Where-Object { $_.Contains('"event":"terrain_stream_profile"') })
        if ($completeLine.Count -ne 1 -or $profileLine.Count -ne 1) {
            throw "Missing or duplicate benchmark/profile markers: $runId"
        }
        $receipt = ($completeLine[0].Substring($completeLine[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 26) | ConvertFrom-Json)
        $actualProfile = ($profileLine[0].Substring($profileLine[0].IndexOf('PERF_TRACE ') + 11) | ConvertFrom-Json)
        if ($receipt.profile -ne $profile -or $actualProfile.profile -ne $profile -or
            $actualProfile.profile_mismatch -or $receipt.route -ne $route -or
            [int]$receipt.seed -ne 424242 -or [int]$receipt.frames -ne $Frames) {
            throw "Non-matching source/route/profile/seed/frames: $runId"
        }
        $expectedDistance = if ($route -eq 'idle') { 0.0 } elseif ($route -eq 'straight-2') { 2.0 * $Frames / 60.0 } elseif ($route.EndsWith('54')) { 54.0 * $Frames / 60.0 } else { 18.0 * $Frames / 60.0 }
        if ([Math]::Abs([double]$receipt.distance_m - $expectedDistance) -gt 0.005) {
            throw "Route geometry mismatch: $runId, distance=$($receipt.distance_m), expected=$expectedDistance"
        }

        $windows = @()
        $regionLoadMs = @()
        $workerByKind = @{}
        $radialSamples = @()
        $coarseCount = 0
        $coarseReadyMs = @()
        $effectBlockers = 0
        $dm9ByAction = @{}
        $dm9ReadyHits = 0
        $workerQueueMs = @()
        $workerRunMs = @()
        $uploadMs = @()
        $snapshotMs = @()
        $dm10SchedulerSamples = @()
        $dm9VisualWorkerMs = @()
        $dm9VisualQueueMs = @()
        $dm9VisualFieldMs = @()
        $dm9VisualMeshMs = @()
        $dm9VisualPrecomputeMs = @()
        $dm9SessionStartUsec = -1L
        $dm9FullHighUsec = -1L
        $dm9VisualLatticeMs = @()
        $dm9VisualRebuildMs = @()
        $dm9VisualChunkBuildMs = @()
        $dm9VisualChunkCombineMs = @()
        $dm9UniformCells = @()
        $dm9VisualPublishMs = @()
        foreach ($line in $lines) {
            $start = $line.IndexOf('PERF_TRACE ')
            if ($start -lt 0) { continue }
            try { $event = $line.Substring($start + 11) | ConvertFrom-Json } catch { continue }
            switch ($event.event) {
                'terrain_trace_session' { $dm9SessionStartUsec = [long]$event.t_usec }
                'dm8_high_radial_complete' {
                    if ($dm9FullHighUsec -lt 0) { $dm9FullHighUsec = [long]$event.t_usec }
                }
                'terrain_stream_budget_window' { $windows += $event }
                'dm8_radial_gap_sample' { $radialSamples += $event }
                'dm10_visual_qos_sample' { $dm10SchedulerSamples += $event }
                'dm9_visual_shell_complete' {
                    $dm9VisualWorkerMs += ([double]$event.worker_run_usec / 1000.0)
                    $dm9VisualQueueMs += ([double]$event.worker_queue_usec / 1000.0)
                    $dm9VisualFieldMs += ([double]$event.field_generate_usec / 1000.0)
                    $dm9VisualMeshMs += ([double]$event.surface_mesh_usec / 1000.0)
                    $dm9VisualPrecomputeMs += ([double]$event.precompute_usec / 1000.0)
                    $dm9VisualLatticeMs += ([double]$event.lattice_usec / 1000.0)
                    $dm9VisualRebuildMs += ([double]$event.cell_rebuild_usec / 1000.0)
                    $dm9VisualChunkBuildMs += ([double]$event.chunk_build_usec / 1000.0)
                    $dm9VisualChunkCombineMs += ([double]$event.chunk_combine_usec / 1000.0)
                    $dm9UniformCells += [int]$event.uniform_cells_skipped
                    $dm9VisualPublishMs += ([double]$event.main_thread_publish_usec / 1000.0)
                }
                'dm9_prefetch_stage' {
                    $action = [string]$event.action
                    if (-not $dm9ByAction.ContainsKey($action)) { $dm9ByAction[$action] = 0 }
                    $dm9ByAction[$action]++
                    if ($action -eq 'promote' -and [bool]$event.ready) { $dm9ReadyHits++ }
                }
                'terrain_mesh_job_complete' {
                    $workerQueueMs += ([double]$event.worker_queue_usec / 1000.0)
                    $workerRunMs += ([double]$event.worker_run_usec / 1000.0)
                    $uploadMs += ([double]$event.upload_usec / 1000.0)
                }
                'terrain_mesh_snapshot' {
                    $snapshotMs += ([double]$event.duration_usec / 1000.0)
                }
                'terrain_region_load_complete' {
                    if ($event.purpose -eq 'load') { $regionLoadMs += ([double]$event.elapsed_usec / 1000.0) }
                }
                'terrain_region_coarse_visible' {
                    $coarseCount++
                    $coarseReadyMs += ([double]$event.queue_to_coarse_usec / 1000.0)
                }
                'terrain_mesh_job_complete' {
                    $kind = [string]$event.job_kind
                    if (-not $workerByKind.ContainsKey($kind)) { $workerByKind[$kind] = @() }
                    $workerByKind[$kind] += ([double]$event.worker_run_usec / 1000.0)
                }
            }
        }
        if ($windows.Count -eq 0) { throw "No streaming window telemetry: $runId" }
        $numFrames = 0.0
        $numMoving = 0.0
        $missingFocus = 0.0
        $missingPerceivedFocus = 0.0
        $missingRegions = 0.0
        $bad20 = 0.0
        $bad33 = 0.0
        $frameMs = 0.0
        $processMs = 0.0
        $dispatches = 0
        $uploads = 0
        $coarseReported = 0
        $blockers = @{}
        foreach ($w in $windows) {
            $numFrames += [double]$w.frame_count
            $numMoving += [double]$w.f10_movement_frames
            $missingFocus += [double]$w.f10_focus_missing_frames
            $missingPerceivedFocus += [double]$w.f10_perceived_focus_missing_frames
            $missingRegions += [double]$w.f10_missing_regions_in_window_total
            $bad20 += [double]$w.frames_over_20_ms
            $bad33 += [double]$w.frames_over_33_ms
            $frameMs += [double]$w.frame_mean_ms * [double]$w.frame_count
            $processMs += [double]$w.process_mean_ms * [double]$w.frame_count
            $dispatches += [int]$w.mesh_dispatches
            $uploads += [int]$w.mesh_uploads
            $coarseReported += [int]$w.coarse_preview_published
            foreach ($p in $w.mesh_dispatch_blockers.PSObject.Properties) {
                if (-not $blockers.ContainsKey($p.Name)) { $blockers[$p.Name] = 0 }
                $blockers[$p.Name] += [int]$p.Value
            }
        }
        # Fail closed if the stream monitor dropped any final movement frames.
        if ($route -ne 'idle' -and [int]$numMoving -ne $Frames) {
            throw "Incomplete F10 trace ${runId}: movement=$numMoving expected=$Frames"
        }
        if ([int]$numFrames -ne ($Frames + $WarmupFrames + 1)) {
            throw "Incomplete frame trace ${runId}: sampled=$numFrames expected=$($Frames + $WarmupFrames + 1)"
        }
        $workerSummary = [ordered]@{}
        foreach ($kind in @($workerByKind.Keys | Sort-Object)) {
            $workerSummary[$kind] = @{
                count = $workerByKind[$kind].Count
                p50_ms = Get-Percentile $workerByKind[$kind] 0.50
                p95_ms = Get-Percentile $workerByKind[$kind] 0.95
            }
        }
        $metrics = [ordered]@{
            run_id = $runId
            commit = $commit
            godot = $version
            display_backend = 'headless'
            route = $route
            profile = $profile
            requested_frames = $Frames
            warmup_frames = $WarmupFrames
            sampled_frames = [int]$numFrames
            measured_movement_frames = [int]$numMoving
            seed = [int]$receipt.seed
            distance_m = [double]$receipt.distance_m
            final_x_mm = [int]$receipt.final_x_mm
            final_z_mm = [int]$receipt.final_z_mm
            elapsed_wall_ms = [double]$receipt.elapsed_wall_ms
            initial_world_state = 'isolated_empty_APPDATA'
            avg_frame_ms = [Math]::Round($frameMs / [Math]::Max(1.0, $numFrames), 3)
            avg_process_ms = [Math]::Round($processMs / [Math]::Max(1.0, $numFrames), 3)
            frames_over_20_ms_pct = [Math]::Round(100.0 * $bad20 / [Math]::Max(1.0, $numFrames), 3)
            frames_over_33_ms_pct = [Math]::Round(100.0 * $bad33 / [Math]::Max(1.0, $numFrames), 3)
            f10_focus_missing_pct = $(if ($numMoving -gt 0) { [Math]::Round(100.0 * $missingFocus / $numMoving, 3) } else { $null })
            f10_perceived_focus_missing_pct = $(if ($numMoving -gt 0) { [Math]::Round(100.0 * $missingPerceivedFocus / $numMoving, 3) } else { $null })
            f10_missing_regions_per_frame = $(if ($numMoving -gt 0) { [Math]::Round($missingRegions / $numMoving, 3) } else { $null })
            mesh_dispatches = $dispatches
            mesh_uploads = $uploads
            dm9_enabled = ($env:SANDBOX_DM9_PREFETCH -eq '1')
            dm9_lifecycle = $dm9ByAction
            dm9_visual_worker_limit = $(if ($env:SANDBOX_DM9_VISUAL_WORKERS) { [int]$env:SANDBOX_DM9_VISUAL_WORKERS } else { 1 })
            dm10_mode = $env:SANDBOX_DM10_VISUAL_QOS
            dm10_scheduler_samples = $dm10SchedulerSamples.Count
            dm10_scheduler_moving_canonical_pressure_samples = @($dm10SchedulerSamples | Where-Object { $_.state -eq 'directional' -and $_.canonical_loading -gt 0 }).Count
            dm10_scheduler_blocked_samples = @($dm10SchedulerSamples | Where-Object { -not [bool]$_.may_submit }).Count
            dm10_scheduler_last_reason = $(if ($dm10SchedulerSamples.Count -gt 0) { [string]$dm10SchedulerSamples[-1].reason } else { '' })
            dm9_visual_shell_complete_count = $dm9VisualWorkerMs.Count
            dm9_fast_b4 = ($env:SANDBOX_DM9_FAST_B4 -eq '1')
            dm9_full_high_elapsed_ms = $(if ($dm9SessionStartUsec -ge 0 -and $dm9FullHighUsec -ge $dm9SessionStartUsec) { [Math]::Round(($dm9FullHighUsec - $dm9SessionStartUsec) / 1000.0, 3) } else { $null })
            dm9_visual_precompute_p50_ms = Get-Percentile $dm9VisualPrecomputeMs 0.50
            dm9_visual_precompute_p95_ms = Get-Percentile $dm9VisualPrecomputeMs 0.95
            dm9_visual_lattice_p50_ms = Get-Percentile $dm9VisualLatticeMs 0.50
            dm9_visual_lattice_p95_ms = Get-Percentile $dm9VisualLatticeMs 0.95
            dm9_visual_cell_rebuild_p50_ms = Get-Percentile $dm9VisualRebuildMs 0.50
            dm9_visual_cell_rebuild_p95_ms = Get-Percentile $dm9VisualRebuildMs 0.95
            dm9_visual_chunk_build_p50_ms = Get-Percentile $dm9VisualChunkBuildMs 0.50
            dm9_visual_chunk_build_p95_ms = Get-Percentile $dm9VisualChunkBuildMs 0.95
            dm9_visual_chunk_combine_p50_ms = Get-Percentile $dm9VisualChunkCombineMs 0.50
            dm9_visual_chunk_combine_p95_ms = Get-Percentile $dm9VisualChunkCombineMs 0.95
            dm9_uniform_cells_skipped_total = [long]$(if ($dm9UniformCells.Count -gt 0) { ($dm9UniformCells | Measure-Object -Sum).Sum } else { 0 })
            dm9_visual_shell_worker_p50_ms = Get-Percentile $dm9VisualWorkerMs 0.50
            dm9_visual_shell_worker_p95_ms = Get-Percentile $dm9VisualWorkerMs 0.95
            dm9_visual_field_generate_p50_ms = Get-Percentile $dm9VisualFieldMs 0.50
            dm9_visual_field_generate_p95_ms = Get-Percentile $dm9VisualFieldMs 0.95
            dm9_visual_chunk_meshing_p50_ms = Get-Percentile $dm9VisualMeshMs 0.50
            dm9_visual_chunk_meshing_p95_ms = Get-Percentile $dm9VisualMeshMs 0.95
            dm9_visual_shell_queue_p95_ms = Get-Percentile $dm9VisualQueueMs 0.95
            dm9_visual_shell_publish_p95_ms = Get-Percentile $dm9VisualPublishMs 0.95
            dm9_prefetch_ready_hits = $dm9ReadyHits
            dm8_radial_sample_count = $radialSamples.Count
            dm8_visual_gap_front_p95_regions = Get-Percentile @($radialSamples | ForEach-Object { [double]$_.terrain_gap_front_cone }) 0.95
            dm10_velocity_gap_front_p95_regions = Get-Percentile @($radialSamples | ForEach-Object { [double]$_.dm10_velocity_front_gap }) 0.95
            dm10_corridor_coverage_mean_pct = $(if (@($radialSamples | Where-Object { [double]$_.dm10_corridor_coverage_pct -ge 0 }).Count -gt 0) {
                [Math]::Round((@($radialSamples | Where-Object { [double]$_.dm10_corridor_coverage_pct -ge 0 } | ForEach-Object { [double]$_.dm10_corridor_coverage_pct }) | Measure-Object -Average).Average, 3)
            } else { $null })

            dm8_visual_gap_p95_regions = Get-Percentile @($radialSamples | ForEach-Object { [double]$_.terrain_gap_outer }) 0.95
            dm8_visual_gap_age_p95_ms = Get-Percentile @($radialSamples | ForEach-Object { [double]$_.terrain_gap_age_p95_ms }) 0.95
            dm8_visual_gap_final_regions = $(if ($radialSamples.Count -gt 0) { [int]$radialSamples[-1].terrain_gap_outer } else { $null })
            dm8_rock_gap_final_regions = $(if ($radialSamples.Count -gt 0) { [int]$radialSamples[-1].rock_gap_outer } else { $null })
            snapshot_p50_ms = Get-Percentile $snapshotMs 0.50
            snapshot_p95_ms = Get-Percentile $snapshotMs 0.95
            worker_queue_p50_ms = Get-Percentile $workerQueueMs 0.50
            worker_queue_p95_ms = Get-Percentile $workerQueueMs 0.95
            worker_run_p50_ms = Get-Percentile $workerRunMs 0.50
            worker_run_p95_ms = Get-Percentile $workerRunMs 0.95
            upload_p50_ms = Get-Percentile $uploadMs 0.50
            upload_p95_ms = Get-Percentile $uploadMs 0.95
            process_cpu_samples = $cpuSamples.Count
            process_cpu_tracked_names = $(if ($cpuSamples.Count -gt 0) { @($cpuSamples[-1]['tracked_process_names']) } else { @() })
            process_cpu_mean_pct_total_capacity = $(if ($cpuSamples.Count -gt 0) { [Math]::Round((@($cpuSamples | ForEach-Object { [double]$_['cpu_pct_total_capacity'] }) | Measure-Object -Average).Average, 2) } else { $null })
            process_cpu_peak_pct_total_capacity = $(if ($cpuSamples.Count -gt 0) { [Math]::Round((@($cpuSamples | ForEach-Object { [double]$_['cpu_pct_total_capacity'] }) | Measure-Object -Maximum).Maximum, 2) } else { $null })
            process_rss_peak_mb = $(if ($cpuSamples.Count -gt 0) { [Math]::Round((@($cpuSamples | ForEach-Object { [double]$_['working_set_mb'] }) | Measure-Object -Maximum).Maximum, 2) } else { $null })
            coarse_visible_events = $coarseCount
            coarse_reported_windows = $coarseReported
            coarse_ready_p50_ms = Get-Percentile $coarseReadyMs 0.50
            coarse_ready_p95_ms = Get-Percentile $coarseReadyMs 0.95
            region_load_count = $regionLoadMs.Count
            region_load_p50_ms = Get-Percentile $regionLoadMs 0.50
            region_load_p95_ms = Get-Percentile $regionLoadMs 0.95
            mesh_worker_job_kind = $workerSummary
            blockers = $blockers
        }
        $metrics | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metricsPath -Encoding UTF8
        $allResults += $metrics
        Write-Host "P5_STREAM_BENCH_TRIAL_PASS $runId missing_pct=$($metrics.f10_focus_missing_pct) coarse=$coarseCount"
    }
}
$summary = Join-Path $EvidenceDir 'summary.json'
$allResults | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summary -Encoding UTF8
Write-Host "P5_STREAM_DETERMINISTIC_BENCH_PASS: runs=$($allResults.Count) commit=$commit output=$summary"

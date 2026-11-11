param(
    [ValidateSet('idle', 'straight-18', 'straight-54', 'outback-18', 'outback-54')]
    [string[]]$Routes = @('straight-18', 'straight-54'),
    [ValidateSet('baseline', 'adaptive', 'adaptive-skip', 'adaptive-skip-lookahead', 'adaptive-skip-coarse')]
    [string[]]$Profiles = @('adaptive-skip', 'adaptive-skip-coarse', 'adaptive-skip-coarse', 'adaptive-skip'),
    [ValidateRange(120, 5400)]
    [int]$Frames = 720,
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
        Write-Host "P5 deterministic trial $runId HEAD=$commit Godot=$version"
        $process = Start-Process -FilePath $GodotBin -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $timeoutMs = [int]([Math]::Max(120000, $Frames / 60.0 * 9000))
        if (-not $process.WaitForExit($timeoutMs)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Benchmark timeout: $runId ($stdout)"
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
        $expectedDistance = if ($route -eq 'idle') { 0.0 } elseif ($route.EndsWith('54')) { 54.0 * $Frames / 60.0 } else { 18.0 * $Frames / 60.0 }
        if ([Math]::Abs([double]$receipt.distance_m - $expectedDistance) -gt 0.005) {
            throw "Route geometry mismatch: $runId, distance=$($receipt.distance_m), expected=$expectedDistance"
        }

        $windows = @()
        $regionLoadMs = @()
        $workerByKind = @{}
        $coarseCount = 0
        $coarseReadyMs = @()
        $effectBlockers = 0
        foreach ($line in $lines) {
            $start = $line.IndexOf('PERF_TRACE ')
            if ($start -lt 0) { continue }
            try { $event = $line.Substring($start + 11) | ConvertFrom-Json } catch { continue }
            switch ($event.event) {
                'terrain_stream_budget_window' { $windows += $event }
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
        if ([int]$numFrames -ne ($Frames + 1)) {
            throw "Incomplete frame trace ${runId}: sampled=$numFrames expected=$($Frames + 1)"
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

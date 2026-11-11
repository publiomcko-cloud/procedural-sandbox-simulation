param(
    [ValidateSet('baseline', 'adaptive', 'adaptive-skip')]
    [Alias('Profile')]
    [string]$ProfileName = 'baseline',
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = 'C:\Dev\p5-0f-evidence'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Push-Location $repoRoot
try {
    if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
        throw "Godot executable not found: $GodotBin"
    }
    New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
    $head = (& git rev-parse HEAD).Trim()
    $branch = (& git branch --show-current).Trim()
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $log = Join-Path $EvidenceDir "P5-stream-$ProfileName-$stamp.log"
    $env:SANDBOX_PERF_TRACE = '1'
    $env:SANDBOX_PERF_TRACE_MIN_MS = '2.0'
    $env:SANDBOX_STREAM_PROFILE = $ProfileName

    @(
        'P5.0F STREAMING A/B EXPERIMENT'
        "Profile: $ProfileName"
        "Commit: $head"
        "Branch: $branch"
        "Date: $(Get-Date -Format o)"
        "Godot: $(& $GodotBin --version)"
        '========== CONSOLE =========='
    ) | Set-Content -LiteralPath $log -Encoding UTF8

    $ErrorActionPreference = 'Continue'
    & $GodotBin --headless --path .\game --script res://tests/p5_0f_stream_budget_tests.gd 2>&1 |
        Tee-Object -FilePath $log -Append
    $testExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($testExit -ne 0) { throw "Stream policy unit test failed. See $log" }

    Write-Host "Running $ProfileName. Travel the same route for each A/B run, then close Godot."
    $ErrorActionPreference = 'Continue'
    & $GodotBin --path .\game -- --start-water=ocean --p5-water-debug=sources 2>&1 |
        Tee-Object -FilePath $log -Append
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    Add-Content -LiteralPath $log -Value @(
        '========== END =========='
        "Exit code: $exitCode"
        "Finished: $(Get-Date -Format o)"
    )

    # PowerShell 5.1 may write native output as UTF-16LE characters in
    # a UTF-8 Tee-Object file. Strip interleaved NULs before JSON extraction.
    $cleanLines = @(
        Get-Content -LiteralPath $log |
            ForEach-Object { $_ -replace '\x00', '' }
    )
    # Fail closed: header/requested profile is not proof of the Godot
    # runtime's actual selected profile. This caught the R2 false A/B.
    $profileEvent = @(
        $cleanLines |
            Select-String -SimpleMatch '"event":"terrain_stream_profile"' |
            Select-Object -First 1
    )
    if ($profileEvent.Count -ne 1) {
        throw "No terrain_stream_profile event found; invalid A/B trial. See $log"
    }
    $rawProfile = $profileEvent[0].Line
    $index = $rawProfile.IndexOf('PERF_TRACE ')
    if ($index -lt 0) {
        throw "Malformed profile event; invalid A/B trial. See $log"
    }
    $effectiveProfile = ($rawProfile.Substring($index + 11) | ConvertFrom-Json).profile
    if ($effectiveProfile -ne $ProfileName) {
        throw "Profile mismatch requested=$ProfileName effective=$effectiveProfile; invalid A/B trial. See $log"
    }
    $events = "$log.events.txt"
    $cleanLines |
        Select-String -Pattern 'terrain_stream_(budget_window|budget_transition|profile)|terrain_mesh_snapshot|terrain_process_spike|terrain_region_publish|terrain_region_load_complete|environment_surface_cache_job|effect_prefetch_tick|p5_environment_visual_rebuild' |
        Set-Content -LiteralPath $events

    $windowRows = @(
        $cleanLines |
            Select-String -SimpleMatch '"event":"terrain_stream_budget_window"' |
            ForEach-Object {
                $raw = $_.Line
                $start = $raw.IndexOf('PERF_TRACE ')
                if ($start -ge 0) {
                    try { $raw.Substring($start + 11) | ConvertFrom-Json }
                    catch { $null }
                }
            } | Where-Object { $null -ne $_ }
    )
    $regionLoadTimes = @(
        $cleanLines |
            Select-String -SimpleMatch '"event":"terrain_region_load_complete"' |
            ForEach-Object {
                $raw = $_.Line
                $start = $raw.IndexOf('PERF_TRACE ')
                if ($start -ge 0) {
                    try {
                        $record = $raw.Substring($start + 11) | ConvertFrom-Json
                        if ($record.purpose -eq 'load') {
                            [double]$record.elapsed_usec / 1000.0
                        }
                    } catch {}
                }
            } | Sort-Object
    )
    if ($windowRows.Count -gt 0) {
        $totalFrames = [double](($windowRows | Measure-Object -Property frame_count -Sum).Sum)
        $totalDispatches = [double](($windowRows | Measure-Object -Property mesh_dispatches -Sum).Sum)
        $totalUploads = [double](($windowRows | Measure-Object -Property mesh_uploads -Sum).Sum)
        $badFrames = [double](($windowRows | Measure-Object -Property frames_over_20_ms -Sum).Sum)
        $criticalFrames = [double](($windowRows | Measure-Object -Property frames_over_33_ms -Sum).Sum)
        $boosted = [double](($windowRows | Measure-Object -Property boosted_frames -Sum).Sum)
        $frameMean = 0.0
        $workMean = 0.0
        $framePeak = 0.0
        foreach ($w in $windowRows) {
            $frameMean += [double]$w.frame_mean_ms * [double]$w.frame_count
            $workMean += [double]$w.process_mean_ms * [double]$w.frame_count
            $framePeak = [Math]::Max($framePeak, [double]$w.frame_peak_ms)
        }
        $effectWaits = 0
        $headSkips = 0
        $skipRecovered = 0
        $skipBudgetExhausted = 0
        $dispatchBlockers = @{}
        foreach ($w in $windowRows) {
            $headSkips += [int]$w.effect_pending_load_skips
            $skipRecovered += [int]$w.successful_dispatch_after_skip
            $skipBudgetExhausted += [int]$w.skip_time_budget_exhausted
            if ($null -ne $w.mesh_dispatch_blockers) {
                foreach ($property in $w.mesh_dispatch_blockers.PSObject.Properties) {
                    $dispatchBlockers[$property.Name] = [int]$dispatchBlockers[$property.Name] + [int]$property.Value
                }
            }
        }
        $metrics = [ordered]@{
            profile = $ProfileName
            commit = $head
            windows = $windowRows.Count
            frames = [int]$totalFrames
            boosted_frames = [int]$boosted
            effect_pending_load_skips = $headSkips
            successful_dispatch_after_skip = $skipRecovered
            skip_time_budget_exhausted = $skipBudgetExhausted
            mesh_dispatch_blockers = $dispatchBlockers
            mesh_dispatches = [int]$totalDispatches
            mesh_uploads = [int]$totalUploads
            dispatches_per_100_frames = [Math]::Round(100.0 * $totalDispatches / [Math]::Max(1.0, $totalFrames), 2)
            avg_frame_ms = [Math]::Round($frameMean / [Math]::Max(1.0, $totalFrames), 2)
            peak_frame_ms = [Math]::Round($framePeak, 2)
            avg_process_ms = [Math]::Round($workMean / [Math]::Max(1.0, $totalFrames), 2)
            frames_over_20_ms_pct = [Math]::Round(100.0 * $badFrames / [Math]::Max(1.0, $totalFrames), 2)
            frames_over_33_ms_pct = [Math]::Round(100.0 * $criticalFrames / [Math]::Max(1.0, $totalFrames), 2)
            region_load_samples = $regionLoadTimes.Count
            region_load_p50_ms = $(if ($regionLoadTimes.Count -gt 0) {
                [Math]::Round($regionLoadTimes[[int][Math]::Floor(($regionLoadTimes.Count - 1) * 0.50)], 2)
            } else { $null })
            region_load_p95_ms = $(if ($regionLoadTimes.Count -gt 0) {
                [Math]::Round($regionLoadTimes[[int][Math]::Floor(($regionLoadTimes.Count - 1) * 0.95)], 2)
            } else { $null })
        }
        $metricsPath = "$log.metrics.json"
        $metrics | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metricsPath -Encoding UTF8
        Write-Host "Metrics: $metricsPath"
        $metrics | Format-Table -AutoSize | Out-Host
    } else {
        Write-Warning 'No terrain_stream_budget_window events found; check profile/trace initialization.'
    }
    Write-Host "Full console: $log"
    Write-Host "Filtered events: $events"
    if ($exitCode -ne 0) { throw "Godot exited with code $exitCode; see $log" }
}
finally {
    Pop-Location
}

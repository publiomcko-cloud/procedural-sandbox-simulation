param(
    [ValidateRange(120,18000)][int]$MotionFrames = 720,
    [ValidateRange(120,18000)][int]$IdleFrames = 3600,
    [switch]$SkipIdle,
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) {
        Join-Path $env:RUNNER_TEMP 'dm16-trace-factorial'
    } else { Join-Path $env:TEMP 'dm16-trace-factorial' })
)

# Legacy P5 harness forces SANDBOX_PERF_TRACE=1; this one must NOT.
# All modes use the SAME in-engine in-memory receipt, including trace OFF.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Godot missing: $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Unsupported Godot version: $version" }
$head = (& git -C $root rev-parse HEAD).Trim()
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$previousAppData = $env:APPDATA

$cases = @(
    @{name='a-off';mode='off';route='outback-18';frames=$MotionFrames},
    @{name='a-light';mode='light';route='outback-18';frames=$MotionFrames},
    @{name='a-full';mode='full';route='outback-18';frames=$MotionFrames},
    @{name='b-full';mode='full';route='outback-18';frames=$MotionFrames},
    @{name='b-light';mode='light';route='outback-18';frames=$MotionFrames},
    @{name='b-off';mode='off';route='outback-18';frames=$MotionFrames}
)
if (-not $SkipIdle) {
    $cases += @(
        @{name='idle-off';mode='off';route='idle';frames=$IdleFrames},
        @{name='idle-light';mode='light';route='idle';frames=$IdleFrames},
        @{name='idle-full';mode='full';route='idle';frames=$IdleFrames}
    )
}

$summary = @()
foreach ($case in $cases) {
    $name = [string]$case.name
    $mode = [string]$case.mode
    $frames = [int]$case.frames
    $route = [string]$case.route
    $dir = Join-Path $EvidenceDir $name
    $isolated = Join-Path $dir 'APPDATA'
    New-Item -ItemType Directory -Force -Path $isolated | Out-Null
    $env:APPDATA = $isolated
    $env:SANDBOX_STREAM_BENCHMARK = '1'
    $env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
    $env:SANDBOX_DM16_BENCH_METRICS = '1'
    $env:SANDBOX_DM16_LIGHT_STAGES = $(if ($mode -eq 'light') { '1' } else { '0' })
    $env:SANDBOX_PERF_TRACE = $(if ($mode -eq 'full') { '1' } else { '0' })
    $env:SANDBOX_PERF_TRACE_MIN_MS = '2'
    $env:SANDBOX_DM12_FRAME_TRACE = '0'
    $env:SANDBOX_DM14_EFFECT_TRACE = '0'
    $env:SANDBOX_DM15_RELEASE_TRACE = '0'
    $env:SANDBOX_DM15_DORMANT_ROLLUP = '1'

    $stdout = Join-Path $dir 'engine.stdout.log'
    $stderr = Join-Path $dir 'engine.stderr.log'
    $arguments = "--headless --path " + ('"{0}"' -f $project) +
        " --max-fps 60 -- --stream-benchmark-route=$route --stream-benchmark-frames=$frames --start-water=ocean"
    Write-Host "DM16_START name=$name mode=$mode frames=$frames head=$head"
    $proc = Start-Process -FilePath $GodotBin -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $timeoutMs = [int][Math]::Max(180000.0, 1000.0 * $frames / 60.0 * 6.0)
    if (-not $proc.WaitForExit($timeoutMs)) {
        $proc.Kill()
        $proc.WaitForExit()
        throw "DM16 timeout: $name"
    }
    $proc.Refresh()
    if ($null -ne $proc.ExitCode -and [int]$proc.ExitCode -ne 0) {
        throw "DM16 Godot exit $($proc.ExitCode): $name"
    }
    $err = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
    if ($err -match '(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)') {
        throw "DM16 script error $name : $err"
    }
    $lines = @(Get-Content -LiteralPath $stdout | ForEach-Object { $_ -replace '\x00', '' })
    $terminal = @($lines | Where-Object { $_.Contains('DM16_BENCH_SUMMARY: ') })
    $complete = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
    if ($terminal.Count -ne 1 -or $complete.Count -ne 1) {
        throw "DM16 incomplete receipts: $name DM16=$($terminal.Count) P5=$($complete.Count)"
    }
    $m = $terminal[0].Substring($terminal[0].IndexOf('DM16_BENCH_SUMMARY: ') + 20) | ConvertFrom-Json
    $p5 = $complete[0].Substring($complete[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 26) | ConvertFrom-Json
    if (-not [bool]$m.ok -or $m.source -ne 'dm16_benchmark_in_memory' -or
        [int]$m.expected_frames -ne $frames -or [int]$m.measured_frames -ne $frames -or
        [int]$m.seed -ne 424242 -or [int]$p5.seed -ne 424242 -or
        [int]$p5.frames -ne $frames -or $p5.route -ne $route -or
        $m.route -ne $route -or $m.profile -ne 'adaptive-skip-progressive' -or
        [bool]$m.perf_trace -ne ($mode -eq 'full') -or
        [bool]$m.light_stages -ne ($mode -eq 'light')) {
        throw "DM16 mismatched route, seed, profile, frame count or trace state: $name"
    }
    $expectedDist = $(if ($route -eq 'idle') { 0.0 } else { 18.0 * $frames / 60.0 })
    if ([Math]::Abs([double]$p5.distance_m - $expectedDist) -gt 0.005) {
        throw "DM16 deterministic distance mismatch: $name"
    }
    $events = @($lines | Where-Object { $_.Contains('PERF_TRACE ') })
    if ($mode -ne 'full' -and $events.Count -ne 0) {
        throw "DM16 unexpected PERF_TRACE in $mode ($($events.Count) events)"
    }
    if ($mode -eq 'full' -and $events.Count -lt 50) {
        throw "DM16 missing full telemetry: $name"
    }
    $stageFields = @($m.stage_work.PSObject.Properties)
    if (($mode -eq 'light' -and $stageFields.Count -lt 6) -or
        ($mode -ne 'light' -and $stageFields.Count -ne 0)) {
        throw "DM16 stage collector mismatch: $name stages=$($stageFields.Count)"
    }
    $traceBytes = 0L
    foreach ($event in $events) { $traceBytes += [System.Text.Encoding]::UTF8.GetByteCount($event) }
    $receipt = [ordered]@{
        name=$name; mode=$mode; route=$route; frames=$frames; head=$head
        frame_avg_ms=[double]$m.frame_avg_ms
        frame_p95_ms=[double]$m.frame_p95_ms
        frame_p99_ms=[double]$m.frame_p99_ms
        frame_max_ms=[double]$m.frame_max_ms
        frame_over20_pct=[double]$m.frame_over20_pct
        frame_over33_pct=[double]$m.frame_over33_pct
        frame_over50_count=[int]$m.frame_over50_count
        process_avg_ms=[double]$m.process_avg_ms
        process_p99_ms=[double]$m.process_p99_ms
        focus_missing_pct=$m.focus_missing_pct
        visual_high_completed=[int]$m.visual_high_completed
        visual_high_visible=[int]$m.visual_high_visible
        canonical_regions_active=[int]$m.canonical_regions_active
        full_high_elapsed_ms=$m.full_high_elapsed_ms
        spikes_with_prior_process_over14=[int]$m.spikes_with_prior_process_over14
        spike_prior_dominant_stage_counts=$m.spike_prior_dominant_stage_counts
        stages=$m.stage_work
        trace_events=$events.Count
        trace_bytes=$traceBytes
    }
    $receipt | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $dir 'metrics.json') -Encoding UTF8
    $summary += $receipt
    Write-Host ('DM16_TRACE_CASE=' + ($receipt | ConvertTo-Json -Compress -Depth 7))
}
$env:APPDATA = $previousAppData
$summary | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $EvidenceDir 'dm16-trace-factorial-summary.json') -Encoding UTF8
foreach ($mode in @('off','light','full')) {
    $moving = @($summary | Where-Object { $_.mode -eq $mode -and $_.route -eq 'outback-18' })
    if ($moving.Count -ne 2) { throw "DM16 missing matched motion pair: $mode" }
    $receipt = [ordered]@{
        mode=$mode; count=$moving.Count
        frame_over33_pct=[Math]::Round(($moving | Measure-Object -Property frame_over33_pct -Average).Average, 3)
        frame_over20_pct=[Math]::Round(($moving | Measure-Object -Property frame_over20_pct -Average).Average, 3)
        frame_p99_ms=[Math]::Round(($moving | Measure-Object -Property frame_p99_ms -Average).Average, 3)
        frame_avg_ms=[Math]::Round(($moving | Measure-Object -Property frame_avg_ms -Average).Average, 3)
        canonical_focus_missing_pct=[Math]::Round(($moving | Measure-Object -Property focus_missing_pct -Average).Average, 3)
        visual_high_completed=[Math]::Round(($moving | Measure-Object -Property visual_high_completed -Average).Average, 2)
        trace_events=($moving | Measure-Object -Property trace_events -Sum).Sum
        trace_bytes=($moving | Measure-Object -Property trace_bytes -Sum).Sum
    }
    Write-Host ('DM16_TRACE_GROUP=' + ($receipt | ConvertTo-Json -Compress -Depth 6))
}
Write-Host "DM16_TRACE_FACTORIAL_PASS runs=$($summary.Count) head=$head"

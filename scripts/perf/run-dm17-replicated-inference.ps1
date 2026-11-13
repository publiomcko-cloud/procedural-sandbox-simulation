param(
    [ValidateRange(4,32)][int]$Pairs = 16,
    [ValidateRange(2,24)][int]$StressPairs = 8,
    [ValidateRange(2,12)][int]$IdlePairs = 4,
    [ValidateRange(360,18000)][int]$MotionFrames = 720,
    [ValidateRange(1200,18000)][int]$IdleFrames = 2400,
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm17-replication' } else { Join-Path $env:TEMP 'dm17-replication' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "DM17_GODOT_MISSING $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "DM17_GODOT_VERSION $version" }
$head = (& git -C $root rev-parse HEAD).Trim()
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$previousAppData = $env:APPDATA
$records = New-Object System.Collections.Generic.List[object]
$pairRecords = New-Object System.Collections.Generic.List[object]

# Pre-registered within-trial comparison: control vs both (A+B).
# ABBA order across adjacent pairs balances CPU warmup, thermal drift and
# cache effects without ever executing variants concurrently.
$routes = @(
    @{name='straight-18'; count=$Pairs; frames=$MotionFrames},
    @{name='outback-18'; count=$Pairs; frames=$MotionFrames},
    @{name='straight-54'; count=$StressPairs; frames=$MotionFrames},
    @{name='idle'; count=$IdlePairs; frames=$IdleFrames}
)
try {
    foreach ($routeCase in $routes) {
        $route = [string]$routeCase.name
        $frames = [int]$routeCase.frames
        for ($pair = 0; $pair -lt [int]$routeCase.count; $pair++) {
            $pairId = '{0}-{1:d2}' -f $route,$pair
            $arms = $(if ($pair % 2 -eq 0) { @('control','both') } else { @('both','control') })
            $byArm = @{}
            foreach ($arm in $arms) {
                $trial = "$pairId-$arm"
                $dir = Join-Path $EvidenceDir $trial
                $isolated = Join-Path $dir 'APPDATA'
                New-Item -ItemType Directory -Force -Path $isolated | Out-Null
                $env:APPDATA = $isolated
                $env:SANDBOX_STREAM_BENCHMARK = '1'
                $env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
                $env:SANDBOX_DM16_BENCH_METRICS = '1'
                $env:SANDBOX_DM16_LIGHT_STAGES = '0'
                $env:SANDBOX_PERF_TRACE = '0'
                $env:SANDBOX_DM17_WALLCLOCK_ROUTE = '1'
                $env:SANDBOX_DM17_SPARSE_BLOCK = $(if ($arm -eq 'both') { '1' } else { '0' })
                $env:SANDBOX_DM17_SHARED_LATTICE = $(if ($arm -eq 'both') { '1' } else { '0' })
                $env:SANDBOX_DM12_FRAME_TRACE = '0'
                $env:SANDBOX_DM14_EFFECT_TRACE = '0'
                $env:SANDBOX_DM15_RELEASE_TRACE = '0'
                $env:SANDBOX_DM15_DORMANT_ROLLUP = '1'
                $env:SANDBOX_STREAM_BENCH_SCREENSHOT = ''
                $stdout = Join-Path $dir 'stdout.log'
                $stderr = Join-Path $dir 'stderr.log'
                $arguments = '--headless --path "' + $project +
                    '" --max-fps 60 -- --stream-benchmark-route=' + $route +
                    ' --stream-benchmark-frames=' + $frames + ' --start-water=ocean'
                Write-Host "DM17_REPLICATION_START trial=$trial sha=$head"
                $process = Start-Process -FilePath $GodotBin -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
                $timeout = [int][Math]::Max(180000.0, [double]$frames * 1000.0 / 60.0 * 6.0)
                if (-not $process.WaitForExit($timeout)) {
                    $process.Kill(); $process.WaitForExit()
                    throw "DM17_REPLICATION_TIMEOUT $trial"
                }
                $process.Refresh()
                if ($null -ne $process.ExitCode -and [int]$process.ExitCode -ne 0) {
                    throw "DM17_REPLICATION_EXIT $trial code=$($process.ExitCode)"
                }
                $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
                $out = (Get-Content -LiteralPath $stdout -Raw) -replace '\x00',''
                if (($out + $err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)') {
                    throw "DM17_REPLICATION_SCRIPT_ERROR $trial"
                }
                $lines = @($out -split '\r?\n')
                $summaryLines = @($lines | Where-Object { $_.Contains('DM16_BENCH_SUMMARY: ') })
                $terminalLines = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
                if ($summaryLines.Count -ne 1 -or $terminalLines.Count -ne 1) {
                    throw "DM17_REPLICATION_RECEIPT_MISSING $trial"
                }
                $m = $summaryLines[0].Substring($summaryLines[0].IndexOf('DM16_BENCH_SUMMARY: ') + 20) | ConvertFrom-Json
                $p = $terminalLines[0].Substring($terminalLines[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 26) | ConvertFrom-Json
                $speed = $(if ($route -eq 'idle') { 0.0 } elseif ($route.EndsWith('54')) { 54.0 } else { 18.0 })
                $expectedDistance = $speed * [double]$p.wallclock_motion_seconds
                if (-not [bool]$m.ok -or [bool]$m.perf_trace -or [bool]$m.light_stages -or
                    [int]$m.seed -ne 424242 -or [int]$p.seed -ne 424242 -or
                    [int]$m.measured_frames -ne $frames -or [int]$p.frames -ne $frames -or
                    $p.route -ne $route -or $m.route -ne $route -or
                    $m.profile -ne 'adaptive-skip-progressive' -or $p.profile -ne 'adaptive-skip-progressive' -or
                    -not [bool]$p.wallclock_route -or
                    [bool]$p.dm17_sparse_block -ne ($arm -eq 'both') -or
                    [bool]$p.dm17_shared_lattice -ne ($arm -eq 'both') -or
                    [Math]::Abs([double]$p.distance_m - $expectedDistance) -gt 0.01) {
                    throw "DM17_REPLICATION_INVARIANT_MISMATCH $trial"
                }
                if ($speed -gt 0 -and
                    ([double]$p.wallclock_motion_seconds -lt 0.95*[double]$frames/60.0 -or
                     [double]$p.wallclock_motion_seconds -gt 1.10*[double]$frames/60.0)) {
                    throw "DM17_REPLICATION_CLOCK_OUTLIER $trial"
                }
                $traceEvents = @($lines | Where-Object { $_.Contains('PERF_TRACE ') })
                if ($traceEvents.Count -gt 0) { throw "DM17_REPLICATION_TRACE_CONTAMINATION $trial" }
                $receipt = [pscustomobject][ordered]@{
                    trial=$trial; pair=$pair; route=$route; arm=$arm; head=$head
                    frames=$frames; wallclock_s=[double]$p.wallclock_motion_seconds
                    distance_m=[double]$p.distance_m
                    frame_avg_ms=[double]$m.frame_avg_ms
                    frame_p95_ms=[double]$m.frame_p95_ms
                    frame_p99_ms=[double]$m.frame_p99_ms
                    frame_over20_pct=[double]$m.frame_over20_pct
                    frame_over33_pct=[double]$m.frame_over33_pct
                    process_avg_ms=[double]$m.process_avg_ms
                    process_p99_ms=[double]$m.process_p99_ms
                    missing_focus_pct=$(if ($route -eq 'idle') { $null } else { [double]$m.focus_missing_pct })
                    high_completed=[int]$m.visual_high_completed
                    core_regions_active=[int]$m.canonical_regions_active
                    high_fill_ms=$(if ($route -eq 'idle') { [double]$m.full_high_elapsed_ms } else { $null })
                    high_gap=$(if ($route -eq 'idle') { 268 - [int]$m.visual_high_completed } else { $null })
                }
                $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $dir 'receipt.json') -Encoding UTF8
                [void]$records.Add($receipt)
                $byArm[$arm] = $receipt
                Write-Host ('DM17_REPLICATION_CASE=' + ($receipt | ConvertTo-Json -Compress -Depth 5))
            }
            $a = $byArm['control']; $b = $byArm['both']
            $pairReceipt = [pscustomobject][ordered]@{
                pair=$pair; route=$route
                delta_missing_focus_pct=$(if ($route -eq 'idle') { $null } else { $b.missing_focus_pct - $a.missing_focus_pct })
                delta_frame_p99_ms=$b.frame_p99_ms - $a.frame_p99_ms
                delta_frame_over33_pct=$b.frame_over33_pct - $a.frame_over33_pct
                delta_frame_over20_pct=$b.frame_over20_pct - $a.frame_over20_pct
                delta_high_completed=$b.high_completed - $a.high_completed
                delta_high_fill_ms=$(if ($route -eq 'idle') { $b.high_fill_ms - $a.high_fill_ms } else { $null })
                baseline_high_gap=$a.high_gap; both_high_gap=$b.high_gap
            }
            [void]$pairRecords.Add($pairReceipt)
            Write-Host ('DM17_REPLICATION_PAIR=' + ($pairReceipt | ConvertTo-Json -Compress -Depth 5))
            $records | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'trials.json') -Encoding UTF8
            $pairRecords | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'pairs.json') -Encoding UTF8
        }
    }
} finally {
    $env:APPDATA = $previousAppData
}

function Get-CI($data, [string]$column) {
    $values = @($data | Where-Object { $null -ne $_.$column } | ForEach-Object { [double]($_.$column) })
    $n = $values.Count
    if ($n -lt 2) { throw "DM17_INSUFFICIENT_PAIRS $column" }
    $sum = 0.0
    foreach ($value in $values) { $sum += $value }
    $mean = $sum / [double]$n
    $sumSquares = 0.0
    foreach ($value in $values) { $sumSquares += [Math]::Pow($value-$mean,2) }
    $stddev = [Math]::Sqrt($sumSquares / [double]($n - 1))
    # Student critical values df=3, 7, 15, 31, 39, 47 (two-sided 95%).
    # Nearest LOWER degrees of freedom gives a conservative interval.
    $t = $(if ($n -le 4) { 3.18245 }
        elseif ($n -le 8) { 2.36462 }
        elseif ($n -le 16) { 2.13145 }
        elseif ($n -le 32) { 2.03951 }
        else { 2.02269 })
    $radius = $t * $stddev / [Math]::Sqrt([double]$n)
    $negative = @($values | Where-Object { $_ -lt 0 }).Count
    $positive = @($values | Where-Object { $_ -gt 0 }).Count
    return [pscustomobject][ordered]@{
        n=$n; mean=[Math]::Round($mean,5); stddev=[Math]::Round($stddev,5)
        ci95_lower=[Math]::Round($mean-$radius,5)
        ci95_upper=[Math]::Round($mean+$radius,5)
        negative_pairs=$negative; positive_pairs=$positive
    }
}
$analysis = [ordered]@{}
foreach ($routeName in @('straight-18','outback-18','straight-54','idle')) {
    $subset = @($pairRecords | Where-Object { $_.route -eq $routeName })
    $a = [ordered]@{
        delta_p99_ms=Get-CI $subset 'delta_frame_p99_ms'
        delta_over33_pp=Get-CI $subset 'delta_frame_over33_pct'
        delta_high_completed=Get-CI $subset 'delta_high_completed'
    }
    if ($routeName -eq 'idle') {
        $a['delta_high_fill_ms'] = Get-CI $subset 'delta_high_fill_ms'
        $a['all_high_complete'] = @($subset | Where-Object { $_.baseline_high_gap -ne 0 -or $_.both_high_gap -ne 0 }).Count -eq 0
    } else {
        $a['delta_missing_focus_pp'] = Get-CI $subset 'delta_missing_focus_pct'
    }
    $analysis[$routeName] = $a
    Write-Host ('DM17_REPLICATION_GROUP=' + (@{route=$routeName; inference=$a} | ConvertTo-Json -Compress -Depth 8))
}
$normal = @($pairRecords | Where-Object { $_.route -in @('straight-18','outback-18') })
$analysis['normal_18_pooled'] = [ordered]@{
    delta_missing_focus_pp=Get-CI $normal 'delta_missing_focus_pct'
    delta_p99_ms=Get-CI $normal 'delta_frame_p99_ms'
    delta_over33_pp=Get-CI $normal 'delta_frame_over33_pct'
    delta_high_completed=Get-CI $normal 'delta_high_completed'
}
$e = $analysis['normal_18_pooled']
$idle = $analysis['idle']
# Pre-registered decision gate: primary improvement at 18m/s and no
# statistically supported harm to frame tail or stationary HIGH fill.
# A CI spanning zero on the primary metric remains INCONCLUSIVE, not PASS.
$verdict = 'INCONCLUSIVE'
if ($e.delta_missing_focus_pp.ci95_lower -gt -2.0) {
    $verdict = 'NO_PRACTICALLY_MEANINGFUL_18MPS_GAIN'
} elseif ($e.delta_missing_focus_pp.ci95_upper -lt 0.0 -and
    $e.delta_missing_focus_pp.mean -le -5.0 -and
    $e.delta_p99_ms.ci95_upper -le 2.0 -and
    $e.delta_over33_pp.ci95_upper -le 0.35 -and
    $idle.all_high_complete -and
    $idle.delta_high_fill_ms.ci95_upper -le 1000.0) {
    $verdict = 'HEADLESS_CANDIDATE_REPLICATED_GPU_STILL_REQUIRED'
}
$final = [pscustomobject][ordered]@{
    verdict=$verdict; head=$head; seed=424242; frames_motion=$MotionFrames
    frames_idle=$IdleFrames; pairs_normal_per_route=$Pairs
    pairs_stress=$StressPairs; pairs_idle=$IdlePairs
    trace='OFF'; wallclock_route=$true; inferred=$analysis
}
$final | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm17-replication-analysis.json') -Encoding UTF8
Write-Host ('DM17_REPLICATION_ANALYSIS=' + ($final | ConvertTo-Json -Compress -Depth 12))
Write-Host "DM17_REPLICATION_COMPLETE verdict=$verdict trials=$($records.Count) head=$head"

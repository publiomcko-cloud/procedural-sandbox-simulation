param(
    [ValidateRange(2,16)][int]$LongPairs = 8,
    [ValidateRange(2,16)][int]$ShortPairs = 8,
    [ValidateRange(2,16)][int]$StraightPairs = 4,
    [ValidateRange(2,8)][int]$IdlePairs = 2,
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm18-canonical-cache' } else { Join-Path $env:TEMP 'dm18-canonical-cache' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "DM18_GODOT_MISSING $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "DM18_GODOT_VERSION $version" }
$sha = (& git -C $root rev-parse HEAD).Trim()
$previousAppData = $env:APPDATA
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$records = New-Object 'System.Collections.Generic.List[object]'
$pairs = New-Object 'System.Collections.Generic.List[object]'
# Long out-and-back forces revisits beyond the 20s visual retention;
# short out-and-back checks 18mps core revisits, straight is cold control.
$scenarios = @(
    @{key='outback-long'; route='outback-18'; frames=2400; count=$LongPairs},
    @{key='outback-short'; route='outback-18'; frames=720; count=$ShortPairs},
    @{key='straight'; route='straight-18'; frames=720; count=$StraightPairs},
    @{key='idle'; route='idle'; frames=3600; count=$IdlePairs}
)
try {
    foreach ($scenario in $scenarios) {
        $label = [string]$scenario.key
        $frames = [int]$scenario.frames
        $route = [string]$scenario.route
        for ($p = 0; $p -lt [int]$scenario.count; $p++) {
            $pairName = '{0}-{1:d2}' -f $label,$p
            $arms = $(if ($p % 2 -eq 0) { @('control','cache') } else { @('cache','control') })
            $byArm = @{}
            foreach ($arm in $arms) {
                $trialName = "$pairName-$arm"
                $trialDir = Join-Path $EvidenceDir $trialName
                $user = Join-Path $trialDir 'APPDATA'
                New-Item -ItemType Directory -Force -Path $user | Out-Null
                $env:APPDATA = $user
                $env:SANDBOX_STREAM_BENCHMARK = '1'
                $env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
                $env:SANDBOX_DM16_BENCH_METRICS = '1'
                $env:SANDBOX_DM16_LIGHT_STAGES = '0'
                $env:SANDBOX_PERF_TRACE = '0'
                $env:SANDBOX_DM17_WALLCLOCK_ROUTE = '1'
                $env:SANDBOX_DM17_SPARSE_BLOCK = '0'
                $env:SANDBOX_DM17_SHARED_LATTICE = '0'
                $env:SANDBOX_DM18_CANONICAL_CACHE = $(if ($arm -eq 'cache') { '1' } else { '0' })
                $env:SANDBOX_DM18_DIAGNOSTIC = '1'
                $env:SANDBOX_DM12_FRAME_TRACE = '0'
                $env:SANDBOX_DM14_EFFECT_TRACE = '0'
                $env:SANDBOX_DM15_RELEASE_TRACE = '0'
                $env:SANDBOX_DM15_DORMANT_ROLLUP = '1'
                $stdout = Join-Path $trialDir 'stdout.log'
                $stderr = Join-Path $trialDir 'stderr.log'
                $args = '--headless --path "' + $project +
                    '" --max-fps 60 -- --stream-benchmark-route=' + $route +
                    ' --stream-benchmark-frames=' + $frames + ' --start-water=ocean'
                Write-Host "DM18_TRIAL_START trial=$trialName sha=$sha frames=$frames"
                $proc = Start-Process -FilePath $GodotBin -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
                $timeoutMs = [int][Math]::Max(180000.0, [double]$frames/60.0 * 9000.0)
                if (-not $proc.WaitForExit($timeoutMs)) {
                    $proc.Kill(); $proc.WaitForExit()
                    throw "DM18_TIMEOUT $trialName"
                }
                $proc.Refresh()
                if ($null -ne $proc.ExitCode -and [int]$proc.ExitCode -ne 0) { throw "DM18_EXIT_FAIL $trialName $($proc.ExitCode)" }
                $out = (Get-Content -LiteralPath $stdout -Raw) -replace '\x00',''
                $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
                if (($out+$err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)') {
                    throw "DM18_SCRIPT_ERROR $trialName $err"
                }
                $lines = @($out -split '\r?\n')
                $bench = @($lines | Where-Object { $_.Contains('DM16_BENCH_SUMMARY: ') })
                $terminal = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
                if ($bench.Count -ne 1 -or $terminal.Count -ne 1) { throw "DM18_RECEIPTS_MISSING $trialName" }
                $m = $bench[0].Substring($bench[0].IndexOf('DM16_BENCH_SUMMARY: ') + 20) | ConvertFrom-Json
                $s = $terminal[0].Substring($terminal[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 26) | ConvertFrom-Json
                $speed = $(if ($route -eq 'idle') { 0.0 } else { 18.0 })
                if (-not $m.ok -or [int]$m.seed -ne 424242 -or [int]$s.seed -ne 424242 -or
                    [int]$m.measured_frames -ne $frames -or [int]$s.frames -ne $frames -or
                    $m.route -ne $route -or $s.route -ne $route -or
                    [bool]$m.perf_trace -or [bool]$m.light_stages -or
                    -not [bool]$s.wallclock_route -or -not [bool]$s.dm18_diagnostic_enabled -or
                    [bool]$s.dm18_cache_enabled -ne ($arm -eq 'cache') -or
                    [Math]::Abs([double]$s.distance_m - $speed*[double]$s.wallclock_motion_seconds) -gt 0.01 -or
                    @($lines | Where-Object { $_.Contains('PERF_TRACE ') }).Count -ne 0) {
                    throw "DM18_RECEIPT_INVARIANT $trialName"
                }
                $c = $s.dm18_cache
                $d = $s.dm18
                if ($arm -eq 'cache' -and
                    ([int]$c.hits -ne [int]$d.cached_loads -or
                     [int]$c.entries -lt 0 -or [double]$c.estimated_bytes -gt 134217728)) {
                    throw "DM18_CACHE_INVARIANT $trialName"
                }
                $rec = [pscustomobject][ordered]@{
                    trial=$trialName; scenario=$label; route=$route; frames=$frames; pair=$p; arm=$arm; sha=$sha
                    wallclock_s=[double]$s.wallclock_motion_seconds; distance_m=[double]$s.distance_m
                    missing_pct=$(if ($route -eq 'idle') { $null } else { [double]$m.focus_missing_pct })
                    frame_avg_ms=[double]$m.frame_avg_ms; p99_ms=[double]$m.frame_p99_ms
                    over33_pct=[double]$m.frame_over33_pct; over20_pct=[double]$m.frame_over20_pct
                    visual_high=[int]$m.visual_high_completed
                    high_fill_ms=$(if ($route -eq 'idle') { [double]$m.full_high_elapsed_ms } else { $null })
                    cache_hits=[int]$c.hits; cache_stores=[int]$c.stores
                    cache_evictions=[int]$c.evictions; cache_rejected=[int]$c.rejected
                    cache_entries=[int]$c.entries; cache_estimated_mb=[Math]::Round([double]$c.estimated_bytes/1MB,3)
                    focus_visual_high_missing=[int]$d.focus_missing_visual_high
                    focus_missing_total=[int]$d.focus_missing_total
                    cache_restores=[int]$d.cache_restores
                    restore_total_ms=[double]$d.restore_total_ms
                    restore_max_ms=[double]$d.restore_max_ms
                    new_loads=[int]$d.new_loads; cached_loads=[int]$d.cached_loads
                    new_loads_total_ms=[double]$d.new_loads_total_ms
                    cached_loads_total_ms=[double]$d.cached_loads_total_ms
                    worker_jobs=[int]$d.canonical_jobs.jobs
                    worker_queue_total_ms=[Math]::Round([double]$d.canonical_jobs.worker_queue_usec/1000.0,3)
                    worker_run_total_ms=[Math]::Round([double]$d.canonical_jobs.worker_run_usec/1000.0,3)
                    snapshot_total_ms=[Math]::Round([double]$d.canonical_jobs.snapshot_usec/1000.0,3)
                    upload_total_ms=[Math]::Round([double]$d.canonical_jobs.upload_usec/1000.0,3)
                    stale_jobs=[int]$d.canonical_jobs.stale_jobs
                }
                $rec | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $trialDir 'receipt.json') -Encoding UTF8
                [void]$records.Add($rec); $byArm[$arm] = $rec
                Write-Host ('DM18_TRIAL=' + ($rec | ConvertTo-Json -Compress -Depth 6))
            }
            $b=$byArm['control']; $a=$byArm['cache']
            $pairReceipt=[pscustomobject][ordered]@{
                scenario=$label; pair=$p
                diff_missing_pp=$(if ($route -eq 'idle') { $null } else { $a.missing_pct-$b.missing_pct })
                diff_p99_ms=$a.p99_ms-$b.p99_ms
                diff_over33_pp=$a.over33_pct-$b.over33_pct
                diff_high=$a.visual_high-$b.visual_high
                diff_high_fill_ms=$(if ($route -eq 'idle') { $a.high_fill_ms-$b.high_fill_ms } else { $null })
                cache_hits=$a.cache_hits; cache_stores=$a.cache_stores; cache_estimated_mb=$a.cache_estimated_mb
                diff_worker_jobs=$a.worker_jobs-$b.worker_jobs
                diff_worker_run_ms=$a.worker_run_total_ms-$b.worker_run_total_ms
                diff_queue_ms=$a.worker_queue_total_ms-$b.worker_queue_total_ms
                diff_snapshot_ms=$a.snapshot_total_ms-$b.snapshot_total_ms
                diff_upload_ms=$a.upload_total_ms-$b.upload_total_ms
                focus_visual_high_missing_control=$b.focus_visual_high_missing
                focus_visual_high_missing_cache=$a.focus_visual_high_missing
            }
            [void]$pairs.Add($pairReceipt)
            Write-Host ('DM18_PAIR=' + ($pairReceipt | ConvertTo-Json -Compress -Depth 6))
            $records | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'trials.json') -Encoding UTF8
            $pairs | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'pairs.json') -Encoding UTF8
        }
    }
} finally {
    $env:APPDATA = $previousAppData
}
function Get-PairCI($set, [string]$column) {
    $a = @($set | Where-Object { $null -ne $_.$column } | ForEach-Object { [double]($_.$column) })
    if ($a.Count -lt 2) { throw "DM18_TOO_FEW_PAIRS $column" }
    $n=$a.Count; $sum=0.0; foreach($v in $a){$sum+=$v}
    $avg=$sum/$n; $squares=0.0;foreach($v in $a){$squares += [Math]::Pow($v-$avg,2)}
    $sd=[Math]::Sqrt($squares/($n-1))
    $t=$(if($n -le 2){12.7062}elseif($n -le 4){3.18245}elseif($n -le 8){2.36462}elseif($n -le 16){2.13145}else{2.03951})
    $radius=$t*$sd/[Math]::Sqrt([double]$n)
    return [pscustomobject]@{
        n=$n; mean=[Math]::Round($avg,4)
        ci95_low=[Math]::Round($avg-$radius,4); ci95_high=[Math]::Round($avg+$radius,4)
        negative_pairs=@($a | Where-Object { $_ -lt 0 }).Count
        positive_pairs=@($a | Where-Object { $_ -gt 0 }).Count
    }
}
$all=@{}
foreach($label in @('outback-long','outback-short','straight','idle')){
    $group=@($pairs | Where-Object { $_.scenario -eq $label })
    $record=[ordered]@{
        missing_pp=$(if($label -eq 'idle'){$null}else{Get-PairCI $group 'diff_missing_pp'})
        p99_ms=(Get-PairCI $group 'diff_p99_ms')
        over33_pp=(Get-PairCI $group 'diff_over33_pp')
        high=(Get-PairCI $group 'diff_high')
        worker_jobs=(Get-PairCI $group 'diff_worker_jobs')
        worker_run_ms=(Get-PairCI $group 'diff_worker_run_ms')
        cache_hits=(Get-PairCI $group 'cache_hits')
        cache_estimated_mb=(Get-PairCI $group 'cache_estimated_mb')
        high_fill_ms=$(if($label -eq 'idle'){Get-PairCI $group 'diff_high_fill_ms'}else{$null})
    }
    $all[$label]=$record
    Write-Host ('DM18_GROUP=' + (@{scenario=$label; metrics=$record}|ConvertTo-Json -Compress -Depth 8))
}
$long=$all['outback-long']
$short=$all['outback-short']
# Test success requires actual reuse, lower focus misses by >=5pp with
# confidence interval below zero on LONG revisits and no >2ms p99 tail harm.
# Otherwise classify as inconclusive or no useful gain; never silently deploy.
$verdict='INCONCLUSIVE'
if ($long.cache_hits.mean -lt 1.0 -or $short.cache_hits.mean -lt 1.0) {
    $verdict='CACHE_NOT_EXERCISED'
} elseif ($long.missing_pp.ci95_high -lt 0.0 -and
          $long.missing_pp.mean -le -5.0 -and
          $long.p99_ms.ci95_high -le 2.0 -and
          $long.over33_pp.ci95_high -le 0.35) {
    $verdict='HEADLESS_REVISIT_GAIN_CANDIDATE_GPU_AND_SEMANTIC_QA_PENDING'
} elseif ($long.missing_pp.ci95_low -gt -5.0) {
    $verdict='NO_5PP_REVISIT_GAIN'
}
$final=[pscustomobject]@{
    verdict=$verdict; sha=$sha; seed=424242
    pairs_long=$LongPairs; pairs_short=$ShortPairs
    pairs_straight=$StraightPairs; pairs_idle=$IdlePairs
    trials=$records.Count; groups=$all; headless=$true; trace_off=$true
}
$final | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm18-inference.json') -Encoding UTF8
Write-Host ('DM18_FINAL_ANALYSIS=' + ($final | ConvertTo-Json -Compress -Depth 12))
Write-Host "DM18_RUN_COMPLETE verdict=$verdict runs=$($records.Count) sha=$sha"

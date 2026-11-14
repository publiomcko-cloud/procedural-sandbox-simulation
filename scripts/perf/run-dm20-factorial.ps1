param(
    [ValidateRange(2,12)][int]$ColdBlocks = 6,
    [ValidateRange(2,12)][int]$WarmBlocks = 4,
    [ValidateRange(0,12)][int]$LongBlocks = 2,
    [ValidateRange(0,8)][int]$IdleBlocks = 0,
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm20-factorial' } else { Join-Path $env:TEMP 'dm20-factorial' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "DM20_GODOT_MISSING $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "DM20_GODOT_VERSION $version" }
$sha = (& git -C $root rev-parse HEAD).Trim()
$previousAppData = $env:APPDATA
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$records = New-Object 'System.Collections.Generic.List[object]'
$blocks = New-Object 'System.Collections.Generic.List[object]'
# Latin square: four arms, equal ordered exposure in every group of four.
$orders = @(
    @('control','a','ab','b'),
    @('a','b','control','ab'),
    @('b','ab','a','control'),
    @('ab','control','b','a')
)
$scenarios = @(
    @{name='cold-straight';route='straight-18';frames=720;warm=0;count=$ColdBlocks},
    @{name='warm-straight';route='straight-18';frames=720;warm=900;count=$WarmBlocks},
    @{name='warm-outback';route='outback-18';frames=2400;warm=900;count=$LongBlocks},
    @{name='idle';route='idle';frames=2400;warm=0;count=$IdleBlocks}
)
try {
    foreach ($scenario in $scenarios) {
        if ([int]$scenario.count -eq 0) { continue }
        $name = [string]$scenario.name
        $frames = [int]$scenario.frames
        $warm = [int]$scenario.warm
        $route = [string]$scenario.route
        for ($block = 0; $block -lt [int]$scenario.count; $block++) {
            $byArm = @{}
            foreach ($arm in $orders[$block % 4]) {
                $trial = '{0}-{1:d2}-{2}' -f $name,$block,$arm
                $dir = Join-Path $EvidenceDir $trial
                $env:APPDATA = Join-Path $dir 'APPDATA'
                New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
                $env:SANDBOX_STREAM_BENCHMARK = '1'
                $env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
                $env:SANDBOX_TERRAIN_BACKEND = 'b4'
                $env:SANDBOX_DM16_BENCH_METRICS = '1'
                $env:SANDBOX_DM16_LIGHT_STAGES = '0'
                $env:SANDBOX_PERF_TRACE = '0'
                $env:SANDBOX_DM17_WALLCLOCK_ROUTE = '1'
                $env:SANDBOX_DM17_SPARSE_BLOCK = '0'
                $env:SANDBOX_DM17_SHARED_LATTICE = '0'
                $env:SANDBOX_DM18_CANONICAL_CACHE = '1'
                $env:SANDBOX_DM18_DIAGNOSTIC = '1'
                $env:SANDBOX_DM19_COLD_DIAGNOSTIC = '1'
                $env:SANDBOX_DM19_EFFECT_MOTION_PRIORITY = '0'
                $env:SANDBOX_DM20_SNAPSHOT_PRIMER = $(if ($arm -in @('a','ab')) {'1'} else {'0'})
                $env:SANDBOX_DM20_FOCUS_FIRST = $(if ($arm -in @('b','ab')) {'1'} else {'0'})
                $env:SANDBOX_DM12_FRAME_TRACE = '0'
                $env:SANDBOX_DM14_EFFECT_TRACE = '0'
                $env:SANDBOX_DM15_RELEASE_TRACE = '0'
                $env:SANDBOX_DM15_DORMANT_ROLLUP = '1'
                $stdout = Join-Path $dir 'stdout.log'
                $stderr = Join-Path $dir 'stderr.log'
                $args = '--headless --path "' + $project +
                    '" --max-fps 60 -- --stream-benchmark-route=' + $route +
                    ' --stream-benchmark-frames=' + $frames + ' --start-water=ocean' +
                    $(if ($warm -gt 0) { ' --stream-benchmark-warmup-frames=' + $warm } else { '' })
                Write-Host "DM20_TRIAL_START trial=$trial sha=$sha frames=$frames warmup=$warm"
                $proc = Start-Process -FilePath $GodotBin -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
                $timeoutMs = [int][Math]::Max(180000.0, [double]($frames+$warm)/60.0*8000.0)
                if (-not $proc.WaitForExit($timeoutMs)) {
                    $proc.Kill(); $proc.WaitForExit()
                    throw "DM20_TIMEOUT $trial"
                }
                $proc.Refresh()
                if ($null -ne $proc.ExitCode -and [int]$proc.ExitCode -ne 0) { throw "DM20_EXIT_FAIL $trial $($proc.ExitCode)" }
                $out = (Get-Content -LiteralPath $stdout -Raw) -replace '\x00',''
                $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
                if (($out+$err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)') {
                    throw "DM20_SCRIPT_ERROR $trial $err"
                }
                $lines = @($out -split '\r?\n')
                $benches = @($lines | Where-Object { $_.Contains('DM16_BENCH_SUMMARY: ') })
                $terminals = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
                if ($benches.Count -ne 1 -or $terminals.Count -ne 1) { throw "DM20_RECEIPT_MISSING $trial" }
                $m = $benches[0].Substring($benches[0].IndexOf('DM16_BENCH_SUMMARY: ') + 20) | ConvertFrom-Json
                $s = $terminals[0].Substring($terminals[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 26) | ConvertFrom-Json
                $speed = $(if ($route -eq 'idle') { 0.0 } else { 18.0 })
                $aOn = $arm -in @('a','ab')
                $bOn = $arm -in @('b','ab')
                if (-not [bool]$m.ok -or [int]$m.seed -ne 424242 -or [int]$s.seed -ne 424242 -or
                    [int]$m.measured_frames -ne $frames -or [int]$s.frames -ne $frames -or
                    [int]$s.warmup_frames -ne $warm -or
                    $m.route -ne $route -or $s.route -ne $route -or
                    $m.profile -ne 'adaptive-skip-progressive' -or
                    -not [bool]$s.wallclock_route -or -not [bool]$s.dm18_cache_enabled -or
                    -not [bool]$s.dm19_cold_diagnostic_enabled -or
                    [bool]$s.dm20_snapshot_primer_enabled -ne $aOn -or
                    [bool]$s.dm20_focus_first_enabled -ne $bOn -or
                    [bool]$m.perf_trace -or [bool]$m.light_stages -or
                    [Math]::Abs([double]$s.distance_m - $speed*[double]$s.wallclock_motion_seconds) -gt 0.01 -or
                    @($lines | Where-Object { $_.Contains('PERF_TRACE ') }).Count -ne 0) {
                    throw "DM20_RECEIPT_INVARIANT $trial"
                }
                $d = $s.dm19_cold
                $c = $s.dm20
                if (([int]$d.dispatch_frames.budget_one + [int]$d.dispatch_frames.budget_two) -ne $frames) {
                    throw "DM20_FRAME_ACCOUNTING_FAILED $trial"
                }
                if ($aOn -and [int]$c.prime_attempts -lt 1) { throw "DM20_PRIMER_NOT_EXERCISED $trial" }
                if ($bOn -and [int]$c.priority_overrides -lt 1 -and $route -ne 'idle') {
                    throw "DM20_FOCUS_PRIORITY_NOT_EXERCISED $trial"
                }
                if ([int]$s.dm18_cache.estimated_bytes -gt 134217728) { throw "DM20_DM18_CACHE_OVER_BUDGET $trial" }
                $record = [pscustomobject][ordered]@{
                    trial=$trial;scenario=$name;block=$block;arm=$arm;sha=$sha
                    route=$route;frames=$frames;warmup_frames=$warm
                    missing_pct=$(if ($route -eq 'idle') { $null } else { [double]$m.focus_missing_pct })
                    p99_ms=[double]$m.frame_p99_ms
                    frame_over33_pct=[double]$m.frame_over33_pct
                    process_p99_ms=[double]$m.process_p99_ms
                    visual_high=[int]$m.visual_high_completed
                    high_fill_ms=$(if ($route -eq 'idle') {[double]$m.full_high_elapsed_ms} else {$null})
                    worker_jobs=[int]$s.dm18.canonical_jobs.jobs
                    dm18_cache_hits=[int]$s.dm18_cache.hits
                    dm18_cache_estimated_mb=[math]::Round([double]$s.dm18_cache.estimated_bytes/1MB,3)
                    dm20=$c
                    dm19=$d
                    effect_performance=$s.dm19_effect_runtime
                }
                $record | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $dir 'receipt.json') -Encoding UTF8
                [void]$records.Add($record)
                $byArm[$arm] = $record
                Write-Host ('DM20_TRIAL=' + ($record | ConvertTo-Json -Compress -Depth 16))
            }
            $base = $byArm['control']
            foreach($arm in @('a','b','ab')){
                $v = $byArm[$arm]
                $row = [pscustomobject][ordered]@{
                    scenario=$name;block=$block;arm=$arm
                    diff_missing_pp=$(if ($route -eq 'idle') {$null} else {$v.missing_pct-$base.missing_pct})
                    diff_p99_ms=$v.p99_ms-$base.p99_ms
                    diff_over33_pp=$v.frame_over33_pct-$base.frame_over33_pct
                    diff_high=$v.visual_high-$base.visual_high
                    diff_worker_jobs=$v.worker_jobs-$base.worker_jobs
                    diff_first_dispatch_ms=$v.dm19.stage_latency.'first_visit.before_first_submit'.avg_ms-$base.dm19.stage_latency.'first_visit.before_first_submit'.avg_ms
                    diff_effect_pending=[int]$v.dm19.effect.pending-[int]$base.dm19.effect.pending
                    diff_missing_focus_wait_first=[int]$v.dm19.missing_focus_frames_by_state.awaiting_first_dispatch-[int]$base.dm19.missing_focus_frames_by_state.awaiting_first_dispatch
                    prime_attempts=[int]$v.dm20.prime_attempts
                    prime_hits=[int]$v.dm20.prime_hits
                    priority_overrides=[int]$v.dm20.priority_overrides
                    diff_high_fill_ms=$(if($route -eq 'idle'){$v.high_fill_ms-$base.high_fill_ms}else{$null})
                }
                [void]$blocks.Add($row)
                Write-Host ('DM20_BLOCK=' + ($row | ConvertTo-Json -Compress -Depth 9))
            }
            $records | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'trials.json') -Encoding UTF8
            $blocks | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'paired-blocks.json') -Encoding UTF8
        }
    }
} finally {
    $env:APPDATA = $previousAppData
}
function PairCI($group,[string]$field) {
    $v=@($group|Where-Object {$null -ne $_.$field}|ForEach-Object {[double]($_.$field)})
    if($v.Count -lt 2) { return $null }
    $n=$v.Count; $avg=($v|Measure-Object -Average).Average
    $squares=0.0; foreach($x in $v){$squares+=[Math]::Pow($x-$avg,2)}
    $sd=[Math]::Sqrt($squares/($n-1))
    $t=$(if($n -eq 2){12.7062}elseif($n -eq 3){4.3027}elseif($n -eq 4){3.1824}elseif($n -eq 6){2.5706}elseif($n -eq 8){2.3646}else{2.23})
    $radius=$t*$sd/[Math]::Sqrt([double]$n)
    return [pscustomobject]@{
        n=$n;mean=[Math]::Round($avg,4);ci95_low=[Math]::Round($avg-$radius,4)
        ci95_high=[Math]::Round($avg+$radius,4)
        improved_pairs=@($v|Where-Object {$_ -lt 0}).Count
        worse_pairs=@($v|Where-Object {$_ -gt 0}).Count
    }
}
$groups=@{}
foreach($scenario in @('cold-straight','warm-straight','warm-outback','idle')){
    foreach($arm in @('a','b','ab')){
        $g=@($blocks|Where-Object {$_.scenario -eq $scenario -and $_.arm -eq $arm})
        if($g.Count -eq 0){continue}
        $key="$scenario/$arm"
        $groups[$key]=[pscustomobject]@{
            focus_missing_pp=(PairCI $g 'diff_missing_pp')
            p99_ms=(PairCI $g 'diff_p99_ms')
            over33_pp=(PairCI $g 'diff_over33_pp')
            high=(PairCI $g 'diff_high')
            worker_jobs=(PairCI $g 'diff_worker_jobs')
            effect_pending=(PairCI $g 'diff_effect_pending')
            first_focus_wait_frames=(PairCI $g 'diff_missing_focus_wait_first')
            first_dispatch_ms=(PairCI $g 'diff_first_dispatch_ms')
            high_fill_ms=(PairCI $g 'diff_high_fill_ms')
        }
        Write-Host ('DM20_GROUP=' + (@{scenario=$scenario;arm=$arm;stats=$groups[$key]}|ConvertTo-Json -Compress -Depth 10))
    }
}
$complete=[pscustomobject]@{
    verdict='REVIEW_REQUIRED_NO_AUTOMATIC_PROMOTION'
    sha=$sha;trials=$records.Count;paired_rows=$blocks.Count;seed=424242
    metric_groups=$groups;dm18_cache_preserved=$true;trace_off=$true;headless=$true
}
$complete|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm20-analysis.json') -Encoding UTF8
Write-Host ('DM20_FINAL_ANALYSIS=' + ($complete|ConvertTo-Json -Compress -Depth 15))
Write-Host "DM20_FACTORIAL_COMPLETE trials=$($records.Count) sha=$sha"

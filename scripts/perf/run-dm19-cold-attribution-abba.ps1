param(
    [ValidateRange(2,16)][int]$ColdPairs = 4,
    [ValidateRange(1,12)][int]$WarmPairs = 2,
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm19-cold' } else { Join-Path $env:TEMP 'dm19-cold' })
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "DM19_GODOT_MISSING $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "DM19_VERSION_MISMATCH $version" }
$head = (& git -C $root rev-parse HEAD).Trim()
$oldAppData = $env:APPDATA
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$records = New-Object 'System.Collections.Generic.List[object]'
$pairRecords = New-Object 'System.Collections.Generic.List[object]'
$scenarios = @(
    @{scenario='cold-straight';route='straight-18';frames=720;pairs=$ColdPairs},
    @{scenario='revisit-long';route='outback-18';frames=2400;pairs=$WarmPairs}
)
try {
    foreach ($scenario in $scenarios) {
        $name = [string]$scenario.scenario
        $route = [string]$scenario.route
        $frames = [int]$scenario.frames
        for ($p = 0; $p -lt [int]$scenario.pairs; $p++) {
            $pairId = '{0}-{1:d2}' -f $name,$p
            # ABBA adjacent pairs. Both variants keep DM18 cache ENABLED;
            # only the benchmark-only DM19 probe differs.
            $arms = $(if ($p % 2 -eq 0) { @('off','on') } else { @('on','off') })
            $byArm = @{}
            foreach ($arm in $arms) {
                $trial = "$pairId-$arm"
                $dir = Join-Path $EvidenceDir $trial
                $env:APPDATA = Join-Path $dir 'APPDATA'
                New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
                $env:SANDBOX_STREAM_BENCHMARK = '1'
                $env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
                $env:SANDBOX_DM16_BENCH_METRICS = '1'
                $env:SANDBOX_DM16_LIGHT_STAGES = '0'
                $env:SANDBOX_PERF_TRACE = '0'
                $env:SANDBOX_DM17_WALLCLOCK_ROUTE = '1'
                $env:SANDBOX_DM17_SPARSE_BLOCK = '0'
                $env:SANDBOX_DM17_SHARED_LATTICE = '0'
                $env:SANDBOX_DM18_CANONICAL_CACHE = '1'
                $env:SANDBOX_DM18_DIAGNOSTIC = '1'
                $env:SANDBOX_DM19_COLD_DIAGNOSTIC = $(if ($arm -eq 'on') {'1'} else {'0'})
                $env:SANDBOX_DM12_FRAME_TRACE = '0'
                $env:SANDBOX_DM14_EFFECT_TRACE = '0'
                $env:SANDBOX_DM15_RELEASE_TRACE = '0'
                $env:SANDBOX_DM15_DORMANT_ROLLUP = '1'
                $stdout = Join-Path $dir 'stdout.log'
                $stderr = Join-Path $dir 'stderr.log'
                $arguments = '--headless --path "' + $project +
                    '" --max-fps 60 -- --stream-benchmark-route=' + $route +
                    ' --stream-benchmark-frames=' + $frames + ' --start-water=ocean'
                Write-Host "DM19_START trial=$trial sha=$head"
                $proc = Start-Process -FilePath $GodotBin -ArgumentList $arguments -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
                $timeout = [int][Math]::Max(180000.0, [double]$frames * 1000.0 / 60.0 * 8.0)
                if (-not $proc.WaitForExit($timeout)) {
                    $proc.Kill(); $proc.WaitForExit()
                    throw "DM19_TIMEOUT $trial"
                }
                $proc.Refresh()
                if ($null -ne $proc.ExitCode -and [int]$proc.ExitCode -ne 0) { throw "DM19_EXIT $trial exit=$($proc.ExitCode)" }
                $out = (Get-Content -LiteralPath $stdout -Raw) -replace '\x00',''
                $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
                if (($out + $err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)') {
                    throw "DM19_SCRIPT_ERROR $trial $err"
                }
                $lines = @($out -split '\r?\n')
                $mline = @($lines | Where-Object { $_.Contains('DM16_BENCH_SUMMARY: ') })
                $sline = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
                if ($mline.Count -ne 1 -or $sline.Count -ne 1) { throw "DM19_RECEIPTS_MISSING $trial" }
                $m = $mline[0].Substring($mline[0].IndexOf('DM16_BENCH_SUMMARY: ') + 20) | ConvertFrom-Json
                $s = $sline[0].Substring($sline[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 26) | ConvertFrom-Json
                if (-not [bool]$m.ok -or [int]$m.seed -ne 424242 -or [int]$s.seed -ne 424242 -or
                    [int]$m.measured_frames -ne $frames -or [int]$s.frames -ne $frames -or
                    $m.route -ne $route -or $s.route -ne $route -or
                    $m.profile -ne 'adaptive-skip-progressive' -or
                    -not [bool]$s.wallclock_route -or -not [bool]$s.dm18_cache_enabled -or
                    [bool]$s.dm19_cold_diagnostic_enabled -ne ($arm -eq 'on') -or
                    [bool]$m.perf_trace -or [bool]$m.light_stages -or
                    [Math]::Abs([double]$s.distance_m - 18.0*[double]$s.wallclock_motion_seconds) -gt 0.01 -or
                    @($lines | Where-Object { $_.Contains('PERF_TRACE ') }).Count -gt 0) {
                    throw "DM19_INVARIANT $trial"
                }
                $d = $s.dm19_cold
                if ($arm -eq 'on' -and
                    ([int]$d.effect.calls -lt 1 -or
                     [int]$d.dispatch_frames.budget_one + [int]$d.dispatch_frames.budget_two -ne $frames -or
                     $d.stage_groups.first_visit.published -eq $null)) {
                    throw "DM19_DIAGNOSTIC_INCOMPLETE $trial"
                }
                $e = $s.dm19_effect_runtime
                $r = [pscustomobject][ordered]@{
                    trial=$trial;pair=$p;scenario=$name;route=$route;frames=$frames;arm=$arm;sha=$head
                    focus_missing_pct=[double]$m.focus_missing_pct
                    frame_p99_ms=[double]$m.frame_p99_ms
                    frame_over33_pct=[double]$m.frame_over33_pct
                    process_p99_ms=[double]$m.process_p99_ms
                    canonical_worker_jobs=[int]$s.dm18.canonical_jobs.jobs
                    dm18_cache_hits=[int]$s.dm18_cache.hits
                    dm19=$d
                    effect_performance=$e
                }
                $r | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $dir 'receipt.json') -Encoding UTF8
                [void]$records.Add($r)
                $byArm[$arm] = $r
                Write-Host ('DM19_TRIAL=' + ($r | ConvertTo-Json -Compress -Depth 15))
            }
            $base=$byArm['off']; $instrumented=$byArm['on']
            $pairResult=[pscustomobject][ordered]@{
                scenario=$name;pair=$p
                delta_focus_missing_pp=$instrumented.focus_missing_pct-$base.focus_missing_pct
                delta_p99_ms=$instrumented.frame_p99_ms-$base.frame_p99_ms
                delta_over33_pp=$instrumented.frame_over33_pct-$base.frame_over33_pct
                delta_canonical_jobs=$instrumented.canonical_worker_jobs-$base.canonical_worker_jobs
                diag_first_visit=$instrumented.dm19.stage_groups.first_visit
                diag_first_visit_latency=$instrumented.dm19.stage_latency
                diag_gap_state=$instrumented.dm19.missing_focus_frames_by_state
                diag_effect=$instrumented.dm19.effect
                diag_blockers=$instrumented.dm19.dispatch_blockers
                diag_dispatch=$instrumented.dm19.dispatch_frames
                diag_prefetch=$instrumented.effect_performance
            }
            [void]$pairRecords.Add($pairResult)
            Write-Host ('DM19_PAIR=' + ($pairResult | ConvertTo-Json -Compress -Depth 15))
            $records | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'trials.json') -Encoding UTF8
            $pairRecords | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'pairs.json') -Encoding UTF8
        }
    }
} finally {
    $env:APPDATA = $oldAppData
}
$summary = [ordered]@{}
foreach($key in @('cold-straight','revisit-long')){
    $group=@($pairRecords | Where-Object { $_.scenario -eq $key })
    $summary[$key] = [pscustomobject][ordered]@{
        n=$group.Count
        delta_focus_missing_pp=($group | Measure-Object -Property delta_focus_missing_pp -Average).Average
        delta_p99_ms=($group | Measure-Object -Property delta_p99_ms -Average).Average
        delta_over33_pp=($group | Measure-Object -Property delta_over33_pp -Average).Average
    }
}
Write-Host ('DM19_DIAGNOSTIC_SUMMARY=' + ($summary | ConvertTo-Json -Compress -Depth 7))
$summary | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm19-summary.json') -Encoding UTF8
Write-Host "DM19_ATTRIBUTION_COMPLETE trials=$($records.Count) sha=$head"

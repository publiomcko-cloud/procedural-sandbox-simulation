# DM25 observer-only matched A/A: DM18 ON, DM24 policy OFF, equal stage/probe cost.
param(
  [ValidateRange(1,12)][int]$ColdPairs=6,
  [ValidateRange(1,12)][int]$WarmPairs=4,
  [ValidateRange(0,12)][int]$LongPairs=8,
  [ValidateRange(0,12)][int]$IdlePairs=2,
  [string]$GodotBin='C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
  [string]$EvidenceDir=$(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm24-stage' } else { Join-Path $env:TEMP 'dm24-stage' })
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project=Join-Path $root 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)){throw "DM24_GODOT_MISSING $GodotBin"}
$version=(& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)'){throw "DM24_GODOT_VERSION $version"}
$sha=(& git -C $root rev-parse HEAD).Trim()
$oldAppData=$env:APPDATA
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$rows=New-Object 'System.Collections.Generic.List[object]'
$pairs=New-Object 'System.Collections.Generic.List[object]'
$scenarios=@(
  @{name='cold-forward';route='straight-18';frames=720;warm=0;pairs=$ColdPairs},
  @{name='warm-forward';route='straight-18';frames=720;warm=900;pairs=$WarmPairs},
  @{name='warm-long';route='outback-18';frames=2400;warm=900;pairs=$LongPairs},
  @{name='idle';route='idle';frames=2400;warm=0;pairs=$IdlePairs}
)
try {
  foreach ($scenario in $scenarios){
    if ([int]$scenario.pairs -eq 0){continue}
    $name=[string]$scenario.name
    $route=[string]$scenario.route
    $frames=[int]$scenario.frames
    $warm=[int]$scenario.warm
    for($p=0;$p -lt [int]$scenario.pairs;$p++){
      # ABBA order. BOTH arms always have the same, full instrumentation.
      $order=$(if($p % 2 -eq 0){@('control','repeat')}else{@('repeat','control')})
      $byArm=@{}
      foreach($arm in $order){
        $trial='{0}-{1:d2}-{2}' -f $name,$p,$arm
        $dir=Join-Path $EvidenceDir $trial
        $env:APPDATA=Join-Path $dir 'APPDATA'
        New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
        $env:SANDBOX_TERRAIN_BACKEND='b4'
        $env:SANDBOX_STREAM_BENCHMARK='1'
        $env:SANDBOX_STREAM_PROFILE='adaptive-skip-progressive'
        $env:SANDBOX_DM16_BENCH_METRICS='1'
        $env:SANDBOX_DM16_LIGHT_STAGES='0'
        $env:SANDBOX_PERF_TRACE='0'
        $env:SANDBOX_DM17_WALLCLOCK_ROUTE='1'
        $env:SANDBOX_DM17_SPARSE_BLOCK='0'
        $env:SANDBOX_DM17_SHARED_LATTICE='0'
        $env:SANDBOX_DM18_CANONICAL_CACHE='1'
        $env:SANDBOX_DM18_DIAGNOSTIC='1'
        $env:SANDBOX_DM19_COLD_DIAGNOSTIC='1'
        $env:SANDBOX_DM19_EFFECT_MOTION_PRIORITY='0'
        $env:SANDBOX_DM20_SNAPSHOT_PRIMER='0'
        $env:SANDBOX_DM20_FOCUS_FIRST='0'
        $env:SANDBOX_DM21_EFFECT_GATE='0'
        $env:SANDBOX_DM21_RETAIN_PARTIAL_STAGES='0'
        # CRITICAL CONTROL: never disable DM23 probe, even in reference runs.
        $env:SANDBOX_DM22_SCOPE_TRACE='1'
        $env:SANDBOX_DM23_STAGE_TRACE='1'
        $env:SANDBOX_DM23_FAIR_SOURCE_QUEUE='0'
        $env:SANDBOX_DM24_STAGE_TRACE='1'
        $env:SANDBOX_DM24_STAGE_FAIR='0'
        $env:SANDBOX_DM12_FRAME_TRACE='0'
        $env:SANDBOX_DM14_EFFECT_TRACE='0'
        $env:SANDBOX_DM15_RELEASE_TRACE='0'
        $env:SANDBOX_DM15_DORMANT_ROLLUP='1'
        $outFile=Join-Path $dir 'stdout.log'
        $errFile=Join-Path $dir 'stderr.log'
        $arguments='--headless --path "'+$project+'" --max-fps 60 -- --stream-benchmark-route='+$route+
           ' --stream-benchmark-frames='+$frames+' --start-water=ocean'+
           $(if($warm -gt 0){' --stream-benchmark-warmup-frames='+$warm}else{''})
        Write-Host "DM25_START trial=$trial sha=$sha trace_on=1"
        $proc=Start-Process -FilePath $GodotBin -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $timeoutMs=[int][Math]::Max(180000.0, [double]($frames+$warm)*1000.0/60.0*8.0)
        if(-not $proc.WaitForExit($timeoutMs)){$proc.Kill();$proc.WaitForExit();throw "DM24_TIMEOUT $trial"}
        $proc.Refresh()
        if($null -ne $proc.ExitCode -and [int]$proc.ExitCode -ne 0){throw "DM24_EXIT $trial code=$($proc.ExitCode)"}
        $output=(Get-Content -LiteralPath $outFile -Raw) -replace '\x00',''
        $err=(Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
        if(($output+$err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script)'){throw "DM24_GAME_SCRIPT_ERROR $trial $err"}
        $lines=@($output -split '\r?\n')
        $metricLines=@($lines|Where-Object {$_.Contains('DM16_BENCH_SUMMARY: ')})
        $terminalLines=@($lines|Where-Object {$_.Contains('P5_STREAM_BENCH_COMPLETE: ')})
        if($metricLines.Count -ne 1 -or $terminalLines.Count -ne 1){throw "DM24_RECEIPTS_MISSING $trial"}
        $m=$metricLines[0].Substring($metricLines[0].IndexOf('DM16_BENCH_SUMMARY: ')+20)|ConvertFrom-Json
        $s=$terminalLines[0].Substring($terminalLines[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ')+26)|ConvertFrom-Json
        $speed=$(if($route -eq 'idle'){0.0}else{18.0})
        if(-not [bool]$m.ok -or [int]$m.seed -ne 424242 -or [int]$s.seed -ne 424242 -or
            [int]$m.measured_frames -ne $frames -or [int]$s.frames -ne $frames -or
            [int]$s.warmup_frames -ne $warm -or
            $m.route -ne $route -or $s.route -ne $route -or
            $m.profile -ne 'adaptive-skip-progressive' -or -not [bool]$s.wallclock_route -or
            -not [bool]$s.dm18_cache_enabled -or -not [bool]$s.dm19_cold_diagnostic_enabled -or
            -not [bool]$s.dm22_scope_trace_enabled -or
            -not [bool]$s.dm23_stage_trace_enabled -or
            -not [bool]$s.dm23_fair_source_queue.trace_enabled -or
            [bool]$s.dm23_fair_source_queue.fair_enabled -or
            -not [bool]$s.dm24_stage_trace_enabled -or
            [bool]$s.dm24_stage_fair_enabled -or
            [bool]$m.perf_trace -or [bool]$m.light_stages -or
            [Math]::Abs([double]$s.distance_m-$speed*[double]$s.wallclock_motion_seconds) -gt 0.01 -or
            @($lines|Where-Object {$_.Contains('PERF_TRACE ')}).Count -gt 0){
            throw "DM24_INVARIANT_OR_UNEQUAL_TRACE $trial"
        }
        $d=$s.dm22_scope_trace
        $d23=$s.dm23_region_trace
        $fair=$s.dm23_fair_source_queue
        $stage=$s.dm24_stage_funnel
        # Warm-up counters reset during pre-stream motion, before the
        # current frame reaches the canonical dispatcher. Thus the new
        # per-dispatch probe counts one boundary frame in both A/B arms.
        $expectedStageFrames=$frames+$(if($warm -gt 0){1}else{0})
        if ([int]$stage.counts.instrumented_frames -ne $expectedStageFrames){
            throw "DM24_STAGE_FRAME_ACCOUNTING $trial expected=$expectedStageFrames recorded=$($stage.counts.instrumented_frames)"
        }
        if([int]$d23.counts.load_stages_started -lt 1 -or
            [int]$d.counts.scope_publications -lt 1 -or
            [int]$d.latency.scope_total_ms.n -lt 1 -or
            [int]$s.dm18_cache.estimated_bytes -gt 134217728){
            throw "DM24_INCOMPLETE_SCOPE_LIFECYCLE $trial"
        }
        # After stationary prewarm, the first focal region may already be
        # fully resident: zero new first-chunk dispatches is a valid result.
        if($warm -eq 0 -and $route -ne 'idle' -and
            [int]$d.counts.focus_first_chunk_submitted -lt 1){
            throw "DM24_MISSING_COLD_FIRST_FOCUS_CHUNK_LINKAGE $trial"
        }
        # Mutually exclusive DM25 reasons must exactly partition the focal LOAD
        # first-dispatch observations. DM19 additionally includes other stage purposes.
        $focalAttributed=[int]$stage.counts.dm25_focal_missing_awaiting_first
        $reasonSum=0
        foreach($property in $stage.counts.PSObject.Properties){
          if($property.Name -like 'dm25_reason_*'){$reasonSum += [int]$property.Value}
        }
        $dm19Awaiting=[int]$s.dm19_cold.missing_focus_frames_by_state.awaiting_first_dispatch
        if($reasonSum -ne $focalAttributed -or $focalAttributed -gt $dm19Awaiting){
          throw "DM25_FRAME_ATTRIBUTION_MISMATCH trial=$trial accounted=$reasonSum observed=$focalAttributed dm19=$dm19Awaiting"
        }
        $record=[pscustomobject][ordered]@{
            trial=$trial;scenario=$name;pair=$p;arm=$arm;sha=$sha;frames=$frames;warmup=$warm
            trace_enabled=$true
            missing_pct=$(if($route -eq 'idle'){$null}else{[double]$m.focus_missing_pct})
            p99_ms=[double]$m.frame_p99_ms
            over33_pct=[double]$m.frame_over33_pct
            visual_high=[int]$m.visual_high_completed
            high_fill_ms=$(if($route -eq 'idle'){[double]$m.full_high_elapsed_ms}else{$null})
            worker_jobs=[int]$s.dm18.canonical_jobs.jobs
            dm25_attributed_focus_frames=$focalAttributed
            dm25_dm19_first_wait_frames=$dm19Awaiting
            dm18_cache_hits=[int]$s.dm18_cache.hits
            dm22=$d
            dm23=$d23
            fair_queue=$fair
            dm24=$stage
            dm19=$s.dm19_cold
            effect_performance=$s.dm19_effect_runtime
        }
        $record|ConvertTo-Json -Depth 18|Set-Content -LiteralPath (Join-Path $dir 'receipt.json') -Encoding UTF8
        [void]$rows.Add($record)
        $byArm[$arm]=$record
        Write-Host ('DM25_TRIAL='+($record|ConvertTo-Json -Compress -Depth 18))
      }
      $base=$byArm['control']
      $test=$byArm['repeat']
      $paired=[pscustomobject][ordered]@{
        scenario=$name;pair=$p;trace_in_both=$true;kind='MATCHED_DM25_STALL_ATTRIBUTION_AA'
        delta_focus_missing_pp=$(if($route -eq 'idle'){$null}else{$test.missing_pct-$base.missing_pct})
        delta_p99_ms=$test.p99_ms-$base.p99_ms
        delta_over33_pp=$test.over33_pct-$base.over33_pct
        delta_high=$test.visual_high-$base.visual_high
        delta_jobs=$test.worker_jobs-$base.worker_jobs
        delta_scope_total_ms=$test.dm22.latency.scope_total_ms.mean_ms-$base.dm22.latency.scope_total_ms.mean_ms
        delta_focus_first_chunk_wait_ms=$test.dm22.latency.focus_first_chunk_wait_ms.mean_ms-$base.dm22.latency.focus_first_chunk_wait_ms.mean_ms
        delta_stage_wait_ms=[double]$test.dm23.latency.first_attempt_to_dispatch_ms.mean_ms-[double]$base.dm23.latency.first_attempt_to_dispatch_ms.mean_ms
        delta_focus_entry_to_first_ms=[double]$test.dm23.latency.focus_entry_to_first_dispatch_ms.mean_ms-[double]$base.dm23.latency.focus_entry_to_first_dispatch_ms.mean_ms
        delta_neighbor_became_focus=[int]$test.dm23.counts.neighbor_became_focus-[int]$base.dm23.counts.neighbor_became_focus
        delta_focal_pending=[int]$test.dm19.effect.pending-[int]$base.dm19.effect.pending
        shadow_stage_overrides=[int]$test.dm24.counts.shadow_priority_overrides
        applied_stage_overrides=[int]$test.dm24.counts.applied_priority_overrides
        delta_unsubmitted_focal_frames=[int]$test.dm24.counts.unsubmitted_focal_frames-[int]$base.dm24.counts.unsubmitted_focal_frames
        delta_focal_budget_frames=[int]$test.dm24.counts.focal_wait_dispatch_budget-[int]$base.dm24.counts.focal_wait_dispatch_budget
        delta_focal_worker_frames=[int]$test.dm24.counts.focal_wait_worker_capacity-[int]$base.dm24.counts.focal_wait_worker_capacity
        delta_focal_eligible_frames=[int]$test.dm24.counts.focal_eligible_not_yet_submitted-[int]$base.dm24.counts.focal_eligible_not_yet_submitted
        delta_cancelled_never_selected=[int]$test.dm24.counts.ended_never_selected-[int]$base.dm24.counts.ended_never_selected
        delta_dm25_no_selection=[int]$test.dm24.counts.dm25_reason_no_selection_with_global_capacity-[int]$base.dm24.counts.dm25_reason_no_selection_with_global_capacity
        delta_dm25_effect_pending=[int]$test.dm24.counts.dm25_reason_selected_effect_pending-[int]$base.dm24.counts.dm25_reason_selected_effect_pending
        delta_dm25_other_load=[int]$test.dm24.counts.dm25_reason_other_load_selected-[int]$base.dm24.counts.dm25_reason_other_load_selected
        delta_first_select_ms=[double]$test.dm24.latency.creation_to_first_selection_ms.mean_ms-[double]$base.dm24.latency.creation_to_first_selection_ms.mean_ms
        delta_first_dispatch_ms=[double]$test.dm24.latency.creation_to_first_dispatch_ms.mean_ms-[double]$base.dm24.latency.creation_to_first_dispatch_ms.mean_ms
      }
      [void]$pairs.Add($paired)
      Write-Host ('DM25_PAIR='+($paired|ConvertTo-Json -Compress -Depth 10))
      $rows|ConvertTo-Json -Depth 18|Set-Content -LiteralPath (Join-Path $EvidenceDir 'trials.json') -Encoding UTF8
      $pairs|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $EvidenceDir 'pairs.json') -Encoding UTF8
    }
  }
} finally {
  $env:APPDATA=$oldAppData
}
$summary=@{}
foreach($scenario in @('cold-forward','warm-forward','warm-long','idle')){
  $r=@($rows|Where-Object {$_.scenario -eq $scenario})
  $p=@($pairs|Where-Object {$_.scenario -eq $scenario})
  if($r.Count -eq 0){continue}
  $summary[$scenario]=[pscustomobject]@{
    trials=$r.Count
    mean_scope_total_ms=($r|ForEach-Object {$_.dm22.latency.scope_total_ms.mean_ms}|Measure-Object -Average).Average
    mean_focus_wait_ms=($r|ForEach-Object {$_.dm22.latency.focus_first_chunk_wait_ms.mean_ms}|Measure-Object -Average).Average
    mean_pending_effect_calls=($r|ForEach-Object {$_.dm19.effect.pending}|Measure-Object -Average).Average
    mean_dm25_attributed_first_missing=($r|ForEach-Object {$_.dm25_attributed_focus_frames}|Measure-Object -Average).Average
    mean_dm25_selected_effect_pending=($r|ForEach-Object {[int]$_.dm24.counts.dm25_reason_selected_effect_pending}|Measure-Object -Average).Average
    mean_dm25_no_selection_with_global_capacity=($r|ForEach-Object {[int]$_.dm24.counts.dm25_reason_no_selection_with_global_capacity}|Measure-Object -Average).Average
    mean_dm25_other_load_selected=($r|ForEach-Object {[int]$_.dm24.counts.dm25_reason_other_load_selected}|Measure-Object -Average).Average
    mean_dm25_protected_stage_selected=($r|ForEach-Object {[int]$_.dm24.counts.dm25_reason_protected_stage_selected}|Measure-Object -Average).Average
    mean_dm25_budget_gated=($r|ForEach-Object {[int]$_.dm24.counts.dm25_reason_no_budget_at_dispatch_entry}|Measure-Object -Average).Average
    mean_dm25_worker_gated=($r|ForEach-Object {[int]$_.dm24.counts.dm25_reason_no_worker_at_dispatch_entry}|Measure-Object -Average).Average
    mean_creation_to_first_selection_ms=($r|ForEach-Object {$_.dm24.latency.creation_to_first_selection_ms.mean_ms}|Measure-Object -Average).Average
    mean_created_to_first_dispatch_ms=($r|ForEach-Object {$_.dm24.latency.creation_to_first_dispatch_ms.mean_ms}|Measure-Object -Average).Average
    mean_focal_eligible_frames=($r|ForEach-Object {$_.dm24.counts.focal_eligible_not_yet_submitted}|Measure-Object -Average).Average
    mean_focal_budget_frames=($r|ForEach-Object {$_.dm24.counts.focal_wait_dispatch_budget}|Measure-Object -Average).Average
    mean_focal_worker_frames=($r|ForEach-Object {$_.dm24.counts.focal_wait_worker_capacity}|Measure-Object -Average).Average
    mean_queue_to_gen_ms=($r|ForEach-Object {$_.dm22.latency.scope_queue_ms.mean_ms}|Measure-Object -Average).Average
    mean_projection_to_publish_ms=($r|ForEach-Object {$_.dm22.latency.projection_to_publish_ms.mean_ms}|Measure-Object -Average).Average
    null_control_delta_focus_pp=($p|Where-Object {$null -ne $_.delta_focus_missing_pp}|Measure-Object -Property delta_focus_missing_pp -Average).Average
    null_control_delta_p99_ms=($p|Measure-Object -Property delta_p99_ms -Average).Average
  }
}
$analysis=[ordered]@{
  verdict='DM25_FOCAL_FIRST_DISPATCH_STALL_AA_DIAGNOSTIC_REVIEW'
  sha=$sha;trials=$rows.Count;pairs=$pairs.Count
  both_arms_identical_instrumentation=$true
  trace_cost_is_in_both_arms=$true
  perf_trace_off=$true;dm18_unchanged=$true
  summary=$summary
}
$analysis|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm24-analysis.json') -Encoding UTF8
Write-Host ('DM25_FINAL_ANALYSIS='+($analysis|ConvertTo-Json -Compress -Depth 12))
Write-Host "DM25_SCOPE_CAMPAIGN_COMPLETE trials=$($rows.Count) sha=$sha"

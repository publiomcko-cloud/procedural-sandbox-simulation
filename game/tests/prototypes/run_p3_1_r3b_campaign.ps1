param(
    [string]$Godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceRoot = '',
    [string]$ScenarioFilter = '',
    [int]$RepeatCount = 5,
    [int]$ProcessTimeoutSeconds = 900
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$fixture = Join-Path $repo 'game\tests\fixtures\p3_1_r3b\issue131'
$expectedEngineSha = 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643'
$expectedSumsSha = 'ac8a00cee024815dc55551c0ed5011ea2e9034d499b7846f7cf59b9b446d2be1'
if (-not $EvidenceRoot) { $EvidenceRoot = Join-Path $env:TEMP ('p31-r3b-campaign-' + [guid]::NewGuid().ToString('N')) }
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
if (Test-Path -LiteralPath $EvidenceRoot) { throw "Evidence root must be new: $EvidenceRoot" }
New-Item -ItemType Directory -Path $EvidenceRoot | Out-Null
$profileRoot = Join-Path $EvidenceRoot 'godot-profile'
New-Item -ItemType Directory -Path $profileRoot | Out-Null
$env:APPDATA = Join-Path $profileRoot 'roaming'
$env:LOCALAPPDATA = Join-Path $profileRoot 'local'
New-Item -ItemType Directory -Path $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$engineHash = (Get-FileHash -LiteralPath $Godot -Algorithm SHA256).Hash.ToLowerInvariant()
if ($engineHash -ne $expectedEngineSha) { throw "Pinned Godot SHA mismatch: $engineHash" }
$version = (& $Godot --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -ne '4.7.2.stable.official.ed1daf0bf') { throw "Pinned Godot version mismatch: $version" }
$sumsHash = (Get-FileHash -LiteralPath (Join-Path $fixture 'SHA256SUMS.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($sumsHash -ne $expectedSumsSha) { throw "Issue #131 checksum index changed: $sumsHash" }
$sumsLines = Get-Content -LiteralPath (Join-Path $fixture 'SHA256SUMS.txt')
foreach ($artifact in Get-ChildItem -LiteralPath $fixture -File | Where-Object Name -ne 'SHA256SUMS.txt') {
    $line = $sumsLines | Where-Object { $_.TrimEnd().EndsWith($artifact.Name) } | Select-Object -First 1
    if (-not $line) { throw "Fixture artifact missing from SHA256SUMS: $($artifact.Name)" }
    $expectedHash = $line.Substring(0,64).ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) { throw "Issue #131 fixture SHA mismatch for $($artifact.Name): $actualHash" }
}
$sourceSha = (git -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to read source commit' }
$scenarioNames = foreach ($layout in @('CONCENTRATED','DISTRIBUTED')) { foreach ($count in @(256,640,2048,8192)) { "$layout-$count" } }
if ($ScenarioFilter) { $scenarioNames = @($ScenarioFilter) }
$campaign = [Collections.Generic.List[object]]::new()
foreach ($scenario in $scenarioNames) {
    for ($repeat = 1; $repeat -le $RepeatCount; $repeat++) {
        $runId = "$scenario-R$('{0:D2}' -f $repeat)"
        $runRoot = Join-Path $EvidenceRoot "runs\$runId"
        $outputRoot = Join-Path $runRoot 'output'
        $cacheRoot = Join-Path $EvidenceRoot "cache\$scenario"
        New-Item -ItemType Directory -Path $outputRoot,(Join-Path $runRoot 'raw'),$cacheRoot -Force | Out-Null
        $outPath = Join-Path $runRoot 'raw\stdout.txt'
        $errPath = Join-Path $runRoot 'raw\stderr.txt'
        $engineArguments = @('--headless','--path', (Join-Path $repo 'game'),'--script','res://tests/prototypes/p3_1_r3b_benchmark.gd')
        $record = [ordered]@{
            run_id=$runId; source_sha=$sourceSha; scenario=$scenario; repeat=$repeat; godot=$Godot; godot_sha256=$engineHash; godot_version=$version
            command=$engineArguments; started_utc=[DateTime]::UtcNow.ToString('o'); launcher_pid=$PID; engine_pid=$null; exit_code=$null; duration_ms=$null
            sampled_peak_working_set_bytes=0; last_sampled_working_set_bytes=0; sampled_peak_private_bytes=0
            os_peak_working_set_bytes=$null; os_final_private_bytes=$null; working_set_sample_count=0
            appdata=$env:APPDATA; localappdata=$env:LOCALAPPDATA; status='RESERVED'
        }
        $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'process.json') -Encoding utf8
        @{ executable=$Godot; arguments=$engineArguments; environment=@{ P31_R3B_SCENARIO=$scenario; P31_R3B_REPEAT=$repeat; P31_R3B_SOURCE_SHA=$sourceSha; P31_R3B_OUTPUT_DIR=$outputRoot; P31_R3B_CACHE_DIR=$cacheRoot } } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'command.json') -Encoding utf8
        $env:P31_R3B_SCENARIO = $scenario
        $env:P31_R3B_REPEAT = [string]$repeat
        $env:P31_R3B_SOURCE_SHA = $sourceSha
        $env:P31_R3B_OUTPUT_DIR = $outputRoot
        $env:P31_R3B_CACHE_DIR = $cacheRoot
        $started = [Diagnostics.Stopwatch]::StartNew()
        $proc = Start-Process -FilePath $Godot -ArgumentList $engineArguments -PassThru -NoNewWindow -RedirectStandardOutput $outPath -RedirectStandardError $errPath
        $record.engine_pid = $proc.Id
        $record.status = 'STARTED'
        $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'process.json') -Encoding utf8
        $timedOut = $false
        while (-not $proc.HasExited) {
            $proc.Refresh()
            if (-not $proc.HasExited) {
                try {
                    $observedProcess = Get-Process -Id $proc.Id -ErrorAction Stop
                    $workingSetBytes = [long]$observedProcess.WorkingSet64
                    $privateBytes = [long]$observedProcess.PrivateMemorySize64
                    $record.last_sampled_working_set_bytes = $workingSetBytes
                    $record.working_set_sample_count++
                    if ($workingSetBytes -gt $record.sampled_peak_working_set_bytes) { $record.sampled_peak_working_set_bytes = $workingSetBytes }
                    if ($privateBytes -gt $record.sampled_peak_private_bytes) { $record.sampled_peak_private_bytes = $privateBytes }
                } catch {
                    if (-not $proc.HasExited) { throw }
                }
            }
            if ($started.Elapsed.TotalSeconds -gt $ProcessTimeoutSeconds) {
                $timedOut = $true
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
                break
            }
            Start-Sleep -Milliseconds 100
        }
        $proc.Refresh()
        try {
            $record.os_peak_working_set_bytes = [long]$proc.PeakWorkingSet64
            $record.os_final_private_bytes = [long]$proc.PrivateMemorySize64
        } catch { }
        $record.exit_code = if ($timedOut) { $null } else { $proc.ExitCode }
        $record.status = if ($timedOut) { 'TIMEOUT_CENSORED_PROCESS_STOPPED' } elseif ($proc.ExitCode -eq 0) { 'EXIT_ZERO' } else { 'EXIT_NONZERO' }
        $record.ended_utc = [DateTime]::UtcNow.ToString('o')
        $started.Stop()
        $record.duration_ms = [math]::Round($started.Elapsed.TotalMilliseconds,3)
        $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'process.json') -Encoding utf8
        $resultPath = Join-Path $outputRoot 'result.jsonl'
        $parsedResult = $null
        if (Test-Path -LiteralPath $resultPath) {
            $rawResult = Get-Content -LiteralPath $resultPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($rawResult)) { try { $parsedResult = $rawResult | ConvertFrom-Json -ErrorAction Stop } catch { Write-Warning "Result JSON parse failed for $runId`: $_" } }
        }
        $campaign.Add([pscustomobject]@{ process=$record; result=$parsedResult })
        if ($timedOut -or $proc.ExitCode -ne 0 -or -not $parsedResult -or $parsedResult.status -ne 'PASS') {
            $record.status = 'FAIL_RETAINED'
            $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot 'process.json') -Encoding utf8
            # Continue other independent repetitions/scenarios; never retry this launched run.
        }
    }
}
$campaign | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'campaign.json') -Encoding utf8
$campaign | ForEach-Object { if ($_.result) { $_.result | ConvertTo-Json -Compress -Depth 20 } } | Set-Content -LiteralPath (Join-Path $EvidenceRoot 'results.jsonl') -Encoding utf8
$csvRows = foreach ($entry in $campaign) {
    if (-not $entry.result) { continue }
    $r = $entry.result
    [pscustomobject]@{
        run_id=$r.run_id; scenario_id=$r.scenario_id; repeat=$r.repeat; layout=$r.layout; operation_count=$r.operation_count; status=$r.status
        baseline_query_p50_us=$r.baseline_query_us.p50; optimized_query_p50_us=$r.optimized_query_us.p50
        lod0_baseline_p50_us=$r.lod0_baseline_build_us.p50; lod0_optimized_p50_us=$r.lod0_optimized_build_us.p50
        lod1_baseline_p50_us=$r.lod1_baseline_build_us.p50; lod1_optimized_p50_us=$r.lod1_optimized_build_us.p50
        lod0_cache_cold_us=$r.lod0_cache_cold_total_us; lod0_cache_memory_hit_us=$r.lod0_cache_memory_hit_us; lod0_cache_disk_hit_us=$r.lod0_cache_fresh_instance_disk_hit_us
        cache_disk_hit_us=$r.cache_fresh_instance_disk_hit_us; cache_remote_edit_us=$r.cache_remote_edit_lookup_us
        cache_local_rebuild_us=$r.cache_local_edit_rebuild_us; cache_disk_bytes=$r.cache_disk_bytes; cache_memory_bytes=$r.cache_memory_bytes
        memory_delta_bytes=$r.static_memory_delta_bytes; candidate_operations=$r.meshing_candidate_count; replay_operations=$r.replay_stats.replay_operations; failures=($r.failures -join ';')
    }
}
$csvRows | Export-Csv -LiteralPath (Join-Path $EvidenceRoot 'results.csv') -NoTypeInformation -Encoding utf8
Write-Host "R3B campaign evidence: $EvidenceRoot"
Write-Host "runs=$($campaign.Count) source=$sourceSha godot=$version godot_sha=$engineHash"

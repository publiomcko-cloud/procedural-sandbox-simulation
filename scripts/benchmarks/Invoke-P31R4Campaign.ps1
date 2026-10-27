param(
    [Parameter(Mandatory = $true)][string]$ExpectedHead,
    [Parameter(Mandatory = $true)][string]$GodotPath,
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [string]$ManifestPath = (Join-Path $PSScriptRoot '..\..\docs\reports\P3-1-R4\campaign-manifest.json'),
    [int]$TimeoutSeconds = 600,
    [switch]$PreflightOnly
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$game = Join-Path $repo 'game'
if (Test-Path -LiteralPath $EvidenceRoot) { throw "Evidence root already exists: $EvidenceRoot" }
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot executable not found: $GodotPath" }
if ((Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643') {
    throw 'Godot executable SHA-256 differs from the preregistered binary.'
}
$head = (& git -C $repo rev-parse HEAD).Trim()
if ($head -ne $ExpectedHead) { throw "Source HEAD mismatch: expected $ExpectedHead, got $head" }
$trackedStatus = @(& git -C $repo status --porcelain --untracked-files=no)
if ($trackedStatus.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace(($trackedStatus -join "`n"))) { throw 'Tracked source tree is dirty.' }
$manifestBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $ManifestPath).Path)
$manifestSha = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$sidecar = ((Get-Content -LiteralPath ($ManifestPath + '.sha256') -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
if ($manifestSha -ne $sidecar) { throw 'Campaign manifest sidecar mismatch.' }
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'p3-1-r4-campaign-manifest-v1' -or $manifest.production_baseline -ne '92b442d7f5b605c7bc9c48fac2aceea9d71813aa' `
    -or $manifest.repeat_target -ne 5 -or $manifest.rows.Count -ne 90) {
    throw 'Campaign manifest schema or row count is not the preregistered 90 rows.'
}
$scenarioIds = @($manifest.rows | ForEach-Object { [string]$_.scenario_id } | Sort-Object -Unique)
if ($scenarioIds.Count -ne 18) { throw 'Campaign manifest must contain 18 unique frozen scenario IDs.' }
$seenRunKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
for ($rowIndex = 0; $rowIndex -lt $manifest.rows.Count; $rowIndex++) {
    $row = $manifest.rows[$rowIndex]
    if ([int]$row.order_index -ne ($rowIndex + 1)) { throw "Campaign row order index invalid at $rowIndex." }
    $runKey = '{0}|{1}' -f [string]$row.scenario_id, [int]$row.repeat
    if (-not $seenRunKeys.Add($runKey)) { throw "Duplicate scenario/repeat key: $runKey" }
    [double[]]$expectedResolutions = @()
    if ([int]$row.operation_count -le 256) { $expectedResolutions = [double[]]@(0.5, 0.25, 0.125) }
    elseif ([int]$row.operation_count -le 2048) { $expectedResolutions = [double[]]@(0.5, 0.25) }
    else { $expectedResolutions = [double[]]@(0.5) }
    [double[]]$actualResolutions = @($row.resolutions | ForEach-Object { [double]$_ })
    if ($actualResolutions.Length -ne $expectedResolutions.Length) { throw "Resolution schedule length mismatch: $($row.scenario_id)" }
    for ($resolutionIndex = 0; $resolutionIndex -lt $expectedResolutions.Length; $resolutionIndex++) {
        if ([Math]::Abs($actualResolutions[$resolutionIndex] - $expectedResolutions[$resolutionIndex]) -gt 1e-9) { throw "Resolution schedule mismatch: $($row.scenario_id)" }
    }
    if ([int]$row.repeat -lt 1 -or [int]$row.repeat -gt 5 -or [int]$row.operation_count -notin @(0, 256, 640, 2048, 8192)) {
        throw "Campaign row has an unsupported repeat or operation count: $runKey"
    }
}
foreach ($row in $manifest.rows) {
    $inputPath = Join-Path $repo ($row.input_path -replace '/', '\')
    if ((Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $row.input_sha256) {
        throw "Frozen input hash mismatch: $($row.scenario_id)"
    }
    $fixtureDirectory = Split-Path -Parent $inputPath
    $fixtureManifestHash = (Get-FileHash -LiteralPath (Join-Path $fixtureDirectory 'scenario-manifest.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $fixtureInventoryHash = (Get-FileHash -LiteralPath (Join-Path $fixtureDirectory 'SHA256SUMS.txt') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($fixtureManifestHash -ne $row.source_manifest_sha256 -or $fixtureInventoryHash -ne $row.source_inventory_sha256) {
        throw "Frozen fixture manifest or inventory mismatch: $($row.scenario_id)"
    }
    $inputSidecar = $inputPath -replace '\.json$', '.sha256'
    $inputSidecarHash = ((Get-Content -LiteralPath $inputSidecar -Raw).Trim() -split '\s+')[0].ToLowerInvariant()
    if ($inputSidecarHash -ne $row.input_sha256) { throw "Frozen input sidecar mismatch: $($row.scenario_id)" }
}
$godotVersion = (& $GodotPath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $godotVersion -ne '4.7.2.stable.official.ed1daf0bf') { throw "Unexpected Godot version: $godotVersion" }
[System.IO.Directory]::CreateDirectory($EvidenceRoot) | Out-Null
$attemptRoot = Join-Path $EvidenceRoot 'attempts'
[System.IO.Directory]::CreateDirectory($attemptRoot) | Out-Null
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$environment = [ordered]@{
    source_head = $head
    baseline_sha = $manifest.production_baseline
    manifest_sha256 = $manifestSha
    godot_path = (Resolve-Path $GodotPath).Path
    godot_sha256 = (Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant()
    godot_version = $godotVersion
    cpu = $processor.Name
    logical_processors = [int]$computer.NumberOfLogicalProcessors
    physical_memory_bytes = [long]$computer.TotalPhysicalMemory
    os_caption = $os.Caption
    os_version = $os.Version
    timeout_seconds = $TimeoutSeconds
    started_utc = [DateTime]::UtcNow.ToString('o')
}
[System.IO.File]::WriteAllText((Join-Path $EvidenceRoot 'environment.json'), ($environment | ConvertTo-Json -Depth 5) + "`n", [System.Text.UTF8Encoding]::new($false))
if ($PreflightOnly) {
    Write-Output "P31R4_PREFLIGHT_PASS source=$head rows=$($manifest.rows.Count) manifest_sha256=$manifestSha godot=$godotVersion"
    return
}
$jsonlPath = Join-Path $EvidenceRoot 'campaign.jsonl'
$results = [System.Collections.Generic.List[object]]::new()
$metricRows = [System.Collections.Generic.List[object]]::new()
$stoppedScenario = @{}
$globalStopReason = ''
$environmentNames = @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'P31_R4_SCENARIO', 'P31_R4_REPEAT', 'P31_R4_RUN_ID', 'P31_R4_OUTPUT_DIR', 'P31_R4_STORAGE_DIR', 'P31_R4_MESH_CACHE_DIR', 'P31_R4_SOURCE_SHA', 'P31_R4_RESULT_PATH', 'P31_R4_INPUT_SHA256', 'P31_R4_RESULT_SHA256', 'P31_R4_RESTART_OUTPUT_PATH')
$oldEnvironment = @{}
foreach ($name in $environmentNames) { $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    foreach ($row in $manifest.rows) {
        $scenario = [string]$row.scenario_id
        $runId = '{0}.R{1:D2}' -f $scenario, [int]$row.repeat
        $slug = ($runId -replace '[^A-Za-z0-9_.-]', '_')
        if (-not [string]::IsNullOrEmpty($globalStopReason)) {
            $record = [ordered]@{ run_id = $runId; scenario_id = $scenario; repeat = [int]$row.repeat; status = 'NOT_RUN_GLOBAL_STOP'; stop_reason = $globalStopReason }
            $results.Add($record)
            [System.IO.File]::AppendAllText($jsonlPath, (($record | ConvertTo-Json -Depth 12 -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
            continue
        }
        $runRoot = Join-Path $attemptRoot ('{0:D3}-{1}' -f [int]$row.order_index, $slug)
        $recordPath = Join-Path $runRoot 'process-record.json'
        if ($stoppedScenario.ContainsKey($scenario)) {
            $record = [ordered]@{ run_id = $runId; scenario_id = $scenario; repeat = [int]$row.repeat; status = 'NOT_RUN_AFTER_ROW_STOP'; stop_reason = $stoppedScenario[$scenario] }
            $results.Add($record)
            [System.IO.File]::AppendAllText($jsonlPath, (($record | ConvertTo-Json -Depth 12 -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
            continue
        }
        [System.IO.Directory]::CreateDirectory($runRoot) | Out-Null
        foreach ($folder in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'output', 'storage', 'mesh-cache')) {
            [System.IO.Directory]::CreateDirectory((Join-Path $runRoot $folder)) | Out-Null
        }
        $reservation = [ordered]@{ run_id = $runId; scenario_id = $scenario; repeat = [int]$row.repeat; source_head = $head; manifest_sha256 = $manifestSha; reserved_utc = [DateTime]::UtcNow.ToString('o'); status = 'RESERVED' }
        $reservationBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(($reservation | ConvertTo-Json -Depth 8) + "`n")
        $reservationStream = [System.IO.File]::Open($recordPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $reservationStream.Write($reservationBytes, 0, $reservationBytes.Length)
        $reservationStream.Flush($true)
        $reservationStream.Dispose()
        $stdoutPath = Join-Path $runRoot 'stdout.log'
        $stderrPath = Join-Path $runRoot 'stderr.log'
        $timedOut = $false
        $env:P31_R4_SCENARIO = $scenario
        $env:P31_R4_REPEAT = [string]$row.repeat
        $env:P31_R4_RUN_ID = $runId
        $env:P31_R4_OUTPUT_DIR = Join-Path $runRoot 'output'
        $env:P31_R4_STORAGE_DIR = Join-Path $runRoot 'storage'
        $env:P31_R4_MESH_CACHE_DIR = Join-Path $runRoot 'mesh-cache'
        $env:P31_R4_SOURCE_SHA = $head
        $env:APPDATA = Join-Path $runRoot 'APPDATA'
        $env:LOCALAPPDATA = Join-Path $runRoot 'LOCALAPPDATA'
        $env:TEMP = Join-Path $runRoot 'TEMP'
        $env:TMP = Join-Path $runRoot 'TMP'
        $argumentList = @('--headless', '--path', $game, '--script', 'res://tests/prototypes/p3_1_r4_benchmark.gd')
        $commandText = '"' + (Resolve-Path $GodotPath).Path + '" ' + (($argumentList | ForEach-Object { '"' + $_ + '"' }) -join ' ')
        $launchUtc = [DateTime]::UtcNow
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $process = Start-Process -FilePath $GodotPath -ArgumentList $argumentList -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        $processId = [int]$process.Id
        $process.Refresh()
        $peakWorkingSet = [long]$process.WorkingSet64
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
        $waited = $false
        while (-not $waited) {
            $waited = $process.WaitForExit(1000)
            if (-not $waited) { $process.Refresh(); $peakWorkingSet = [Math]::Max($peakWorkingSet, [long]$process.WorkingSet64) }
            if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds -and -not $waited) {
                try { $process.Kill() } catch {}
                $process.WaitForExit()
                $waited = $true
                $timedOut = $true
                break
            }
        }
        if (-not $timedOut) { $timedOut = $false }
        $watch.Stop()
        $exitCode = if ($timedOut) { $null } else { [int]$process.ExitCode }
        $resultPath = Join-Path (Join-Path $runRoot 'output') 'result.json'
        $result = $null
        $status = if ($timedOut) { 'TIMEOUT_RIGHT_CENSORED' } else { 'PROCESS_EXITED_NO_VALID_RESULT' }
        $validationReasons = [System.Collections.Generic.List[string]]::new()
        if (-not $timedOut -and (Test-Path -LiteralPath $resultPath)) {
            try {
                $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                $stdoutText = Get-Content -LiteralPath $stdoutPath -Raw
                $stderrText = Get-Content -LiteralPath $stderrPath -Raw
                $marker = "P31_R4_$($result.status) scenario=$scenario repeat=$($row.repeat)"
                if ($result.status -notin @('PASS', 'FAIL')) { $validationReasons.Add('terminal_status_invalid') }
                if ($result.scenario_id -ne $scenario -or [int]$result.repeat -ne [int]$row.repeat -or $result.run_id -ne $runId) { $validationReasons.Add('result_identity_mismatch') }
                if ([int]$result.operation_count -ne [int]$row.operation_count) { $validationReasons.Add('operation_count_mismatch') }
                if ($result.source_sha -ne $head -or $result.command_sha256 -ne [string]$row.input_sha256) { $validationReasons.Add('source_or_input_identity_mismatch') }
                if ($stdoutText -notmatch [regex]::Escape($marker)) { $validationReasons.Add('terminal_marker_invalid') }
                if (($stdoutText + $stderrText) -match 'SCRIPT ERROR:|Parse Error:|Invalid call|WARNING: `NaN`') { $validationReasons.Add('unexpected_engine_diagnostic') }
                if ($result.status -eq 'PASS') {
                    if (-not [bool]$result.cave_oracle.voxel_valid -or [int]$result.cave_oracle.centerline_samples -ne 9) { $validationReasons.Add('cave_diagnostic_invalid') }
                    if ([int]$result.cave_oracle.projection_mismatches -ne 0) { $validationReasons.Add('cave_projection_mismatch') }
                    foreach ($resolution in $result.picker_resolutions) {
                        if (-not [bool]$resolution.metrics.all_projection_hits_match) { $validationReasons.Add('picker_projection_mismatch') }
                    }
                    foreach ($resolution in $result.voxel_resolutions) {
                        if (-not [bool]$resolution.B.node_error.valid -or -not [bool]$resolution.C.node_error.valid) { $validationReasons.Add('voxel_node_oracle_invalid') }
                    }
                    if ($exitCode -ne 0) { $validationReasons.Add('pass_exit_code_nonzero') }
                    $status = if ($validationReasons.Count -gt 0) { 'INVALID_EVIDENCE' } else { 'PASS' }
                } else {
                    $failureNames = @($result.failures | ForEach-Object { [string]$_ })
                    if ($exitCode -eq 0) { $validationReasons.Add('fail_exit_code_zero') }
                    if ($failureNames.Count -eq 0) { $validationReasons.Add('failure_record_missing') }
                    if ($failureNames -match 'fixture_digest_or_manifest_invalid|canonical_command_hash_mismatch|frozen_input_identity_invalid') { $validationReasons.Add('frozen_input_integrity_failure') }
                    $status = if ($validationReasons.Count -gt 0) { 'INVALID_EVIDENCE' } else { 'FUNCTIONAL_FAIL' }
                }
                if ($validationReasons.Count -gt 0) { $status = 'INVALID_EVIDENCE' }
            } catch {
                $status = 'INVALID_RESULT_JSON'
                $validationReasons.Add($_.Exception.Message)
            }
        }
        $restartRecord = $null
        if ($status -eq 'PASS' -and $null -ne $result) {
            $restartRoot = Join-Path $runRoot 'fresh-process-restart'
            foreach ($folder in @('', 'APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP', 'output')) {
                $directory = if ([string]::IsNullOrEmpty($folder)) { $restartRoot } else { Join-Path $restartRoot $folder }
                [System.IO.Directory]::CreateDirectory($directory) | Out-Null
            }
            $restartStdout = Join-Path $restartRoot 'stdout.log'
            $restartStderr = Join-Path $restartRoot 'stderr.log'
            $restartReportPath = Join-Path $restartRoot 'output\restart-result.json'
            $env:P31_R4_RESULT_PATH = $resultPath
            $env:P31_R4_INPUT_SHA256 = [string]$row.input_sha256
            $env:P31_R4_RESULT_SHA256 = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $env:P31_R4_RESTART_OUTPUT_PATH = $restartReportPath
            $env:APPDATA = Join-Path $restartRoot 'APPDATA'
            $env:LOCALAPPDATA = Join-Path $restartRoot 'LOCALAPPDATA'
            $env:TEMP = Join-Path $restartRoot 'TEMP'
            $env:TMP = Join-Path $restartRoot 'TMP'
            $restartArgs = @('--headless', '--path', $game, '--script', 'res://tests/prototypes/p3_1_r4_restart_verify.gd')
            $restartCommand = '"' + (Resolve-Path $GodotPath).Path + '" ' + (($restartArgs | ForEach-Object { '"' + $_ + '"' }) -join ' ')
            $restartLaunchedUtc = [DateTime]::UtcNow
            $restartWatch = [Diagnostics.Stopwatch]::StartNew()
            $restartProcess = Start-Process -FilePath $GodotPath -ArgumentList $restartArgs -WorkingDirectory $repo -WindowStyle Hidden -PassThru -RedirectStandardOutput $restartStdout -RedirectStandardError $restartStderr
            $restartPid = [int]$restartProcess.Id
            $restartProcess.Refresh()
            $restartPeakWorkingSet = [long]$restartProcess.WorkingSet64
            $restartCim = Get-CimInstance Win32_Process -Filter "ProcessId=$restartPid" -ErrorAction SilentlyContinue
            $restartWaited = $false
            $restartTimedOut = $false
            while (-not $restartWaited) {
                $restartWaited = $restartProcess.WaitForExit(1000)
                if (-not $restartWaited) { $restartProcess.Refresh(); $restartPeakWorkingSet = [Math]::Max($restartPeakWorkingSet, [long]$restartProcess.WorkingSet64) }
                if ($restartWatch.Elapsed.TotalSeconds -ge $TimeoutSeconds -and -not $restartWaited) {
                    try { $restartProcess.Kill() } catch {}
                    $restartProcess.WaitForExit(); $restartWaited = $true; $restartTimedOut = $true
                    break
                }
            }
            $restartWatch.Stop()
            $restartExitCode = if ($restartTimedOut) { $null } else { [int]$restartProcess.ExitCode }
            $restartText = if (Test-Path -LiteralPath $restartStdout) { Get-Content -LiteralPath $restartStdout -Raw } else { '' }
            $restartErrorText = if (Test-Path -LiteralPath $restartStderr) { Get-Content -LiteralPath $restartStderr -Raw } else { '' }
            $restartResult = $null
            $restartFailureKind = ''
            if (Test-Path -LiteralPath $restartReportPath) {
                try { $restartResult = Get-Content -LiteralPath $restartReportPath -Raw | ConvertFrom-Json } catch { $restartFailureKind = 'restart_json_invalid' }
            }
            $restartValid = $null -ne $restartResult -and $restartResult.status -eq 'PASS' -and $restartResult.run_id -eq $runId `
                -and $restartResult.scenario_id -eq $scenario -and $restartResult.source_sha -eq $head `
                -and $restartResult.command_sha256 -eq [string]$row.input_sha256 -and $restartExitCode -eq 0 `
                -and $restartText -match 'P31_R4_RESTART_PASS' -and ($restartText + $restartErrorText) -notmatch 'SCRIPT ERROR:|Parse Error:'
            if (-not $restartValid) {
                if (-not $restartTimedOut -and $restartExitCode -eq 1 -and $null -ne $restartResult -and $restartResult.status -eq 'FAIL') {
                    $status = 'FUNCTIONAL_FAIL'; $stoppedScenario[$scenario] = 'fresh-process artifact reconstruction failed; no automatic repeat'
                } else {
                    $status = 'INVALID_EVIDENCE'; $globalStopReason = 'fresh-process restart verifier produced incomplete or malformed evidence'
                    if (-not $restartFailureKind) { $restartFailureKind = 'restart_process_or_identity_validation_failed' }
                }
            }
            $restartDisposition = if ($restartValid) { 'PASS' } elseif ($null -ne $restartResult -and $restartResult.status -eq 'FAIL') { 'FUNCTIONAL_FAIL' } else { 'INVALID_EVIDENCE' }
            $restartRecord = [ordered]@{
                run_id = $runId; scenario_id = $scenario; status = $restartDisposition
                failure_kind = $restartFailureKind; exit_code = $restartExitCode; timed_out = $restartTimedOut
                process_id = $restartPid; launcher_pid = $PID; cim_parent_process_id = if ($null -ne $restartCim) { [int]$restartCim.ParentProcessId } else { $null }
                cim_command_line = if ($null -ne $restartCim) { [string]$restartCim.CommandLine } else { '' }; command_line = $restartCommand
                launched_utc = $restartLaunchedUtc.ToString('o'); duration_ms = [long]$restartWatch.ElapsedMilliseconds
                peak_working_set_bytes = $restartPeakWorkingSet; stdout_path = $restartStdout
                stdout_sha256 = if (Test-Path $restartStdout) { (Get-FileHash -LiteralPath $restartStdout -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
                stderr_path = $restartStderr; stderr_sha256 = if (Test-Path $restartStderr) { (Get-FileHash -LiteralPath $restartStderr -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
                result_path = if (Test-Path $restartReportPath) { $restartReportPath } else { '' }
                result_sha256 = if (Test-Path $restartReportPath) { (Get-FileHash -LiteralPath $restartReportPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
                loaded_voxel_snapshots = if ($null -ne $restartResult) { [int]$restartResult.loaded_voxel_snapshots } else { $null }
                expected_voxel_snapshots = if ($null -ne $restartResult) { [int]$restartResult.expected_voxel_snapshots } else { $null }
                maximum_node_error = if ($null -ne $restartResult) { [double]$restartResult.maximum_node_error_vs_rebuilt_canonical_chunk_projection } else { $null }
            }
            [System.IO.File]::WriteAllText((Join-Path $restartRoot 'process-record.json'), ($restartRecord | ConvertTo-Json -Depth 10) + "`n", [System.Text.UTF8Encoding]::new($false))
            $restartProcess.Dispose()
        }
        $stdoutHash = if (Test-Path $stdoutPath) { (Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
        $stderrHash = if (Test-Path $stderrPath) { (Get-FileHash -LiteralPath $stderrPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
        $resultHash = if (Test-Path $resultPath) { (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' }
        $processRecord = [ordered]@{
            run_id = $runId; scenario_id = $scenario; repeat = [int]$row.repeat; order_index = [int]$row.order_index
            source_head = $head; manifest_sha256 = $manifestSha; input_sha256 = $row.input_sha256
            status = $status; validation_reasons = @($validationReasons); exit_code = $exitCode
            process_id = $processId; launcher_pid = $PID; cim_parent_process_id = if ($null -ne $cim) { [int]$cim.ParentProcessId } else { $null }
            cim_command_line = if ($null -ne $cim) { [string]$cim.CommandLine } else { '' }
            command_line = $commandText; launched_utc = $launchUtc.ToString('o'); duration_ms = [long]$watch.ElapsedMilliseconds
            peak_working_set_bytes = $peakWorkingSet; stdout_path = $stdoutPath; stdout_sha256 = $stdoutHash
            stderr_path = $stderrPath; stderr_sha256 = $stderrHash; result_path = if (Test-Path $resultPath) { $resultPath } else { '' }
            result_sha256 = $resultHash; output_root = (Join-Path $runRoot 'output'); storage_root = (Join-Path $runRoot 'storage'); mesh_cache_root = (Join-Path $runRoot 'mesh-cache')
            restart = $restartRecord
        }
        [System.IO.File]::WriteAllText($recordPath, ($processRecord | ConvertTo-Json -Depth 15) + "`n", [System.Text.UTF8Encoding]::new($false))
        $results.Add($processRecord)
        [System.IO.File]::AppendAllText($jsonlPath, (($processRecord | ConvertTo-Json -Depth 15 -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
        Write-Output ("P31R4_RUN {0} {1} exit={2} duration_ms={3}" -f $runId, $status, $exitCode, $watch.ElapsedMilliseconds)
        if ($status -eq 'TIMEOUT_RIGHT_CENSORED' -or $status -eq 'FUNCTIONAL_FAIL') {
            $stoppedScenario[$scenario] = "prior run status $status; no automatic repeat"
        }
        if ($status -in @('INVALID_EVIDENCE', 'INVALID_RESULT_JSON', 'PROCESS_EXITED_NO_VALID_RESULT')) {
            $globalStopReason = "run $runId terminated as $status; inspect preserved evidence before any continuation"
        }
        if ($status -eq 'PASS' -and $null -ne $result) {
            $metricRows.Add([pscustomobject]@{
                run_id = $runId; scenario_id = $scenario; repeat = [int]$row.repeat; arm = 'A_CHUNK_SUBLEDGER'; resolution = 0.0
                candidate_operations = [int]$result.candidate_operation_count; build_usec = [double]$result.A_projection_build_usec
                incremental_usec = [double]$result.A_incremental_append_usec; save_usec = [double]$result.A_persist_usec
                load_usec = [double]$result.A_reload_usec; query_p50_usec = [double]$result.A_projected_query_usec.p50_usec
                query_p95_usec = [double]$result.A_projected_query_usec.p95_usec; query_p99_usec = [double]$result.A_projected_query_usec.p99_usec
                picker_sample_count = 0
                lod0_usec = [double]$result.A_lod0_usec; lod1_usec = [double]$result.A_lod1_usec
                node_error_max = 0.0; lod0_surface_p95 = 0.0; lod1_surface_p95 = 0.0; lod0_normal_p95_deg = 0.0; lod1_normal_p95_deg = 0.0
                storage_bytes = [long]$result.storage_bytes; working_set_peak_bytes = [long]$peakWorkingSet
            })
            foreach ($resolution in $result.voxel_resolutions) {
                foreach ($arm in @('B', 'C')) {
                    $metricRows.Add([pscustomobject]@{
                        run_id = $runId; scenario_id = $scenario; repeat = [int]$row.repeat; arm = if ($arm -eq 'B') { 'B_INCREMENTAL_FLOAT32_VOXEL' } else { 'C_SUBLEDGER_VOXEL_MESH_CACHE' }; resolution = [double]$resolution.spacing
                        candidate_operations = [int]$result.candidate_operation_count; build_usec = [double]$resolution[$arm].materialize_usec
                        incremental_usec = [double]$resolution[$arm].incremental_update_usec; save_usec = [double]$resolution[$arm].save_usec
                        load_usec = [double]$resolution[$arm].load_usec; query_p50_usec = [double]$resolution[$arm].query_usec.p50_usec
                        query_p95_usec = [double]$resolution[$arm].query_usec.p95_usec; query_p99_usec = [double]$resolution[$arm].query_usec.p99_usec
                        picker_sample_count = 0
                        lod0_usec = [double]$resolution[$arm].lod0_build_usec; lod1_usec = [double]$resolution[$arm].lod1_build_usec
                        node_error_max = [double]$resolution[$arm].node_error.max_abs_error
                        lod0_surface_p95 = [double]$resolution[$arm].lod0_surface.sampled_symmetric_vertex_to_triangle_distance.p95
                        lod1_surface_p95 = [double]$resolution[$arm].lod1_surface.sampled_symmetric_vertex_to_triangle_distance.p95
                        lod0_normal_p95_deg = [double]$resolution[$arm].lod0_surface.sampled_normal_angle_deg.p95
                        lod1_normal_p95_deg = [double]$resolution[$arm].lod1_surface.sampled_normal_angle_deg.p95
                        storage_bytes = [long]$result.storage_bytes; working_set_peak_bytes = [long]$peakWorkingSet
                    })
                }
            }
            foreach ($pickerResolution in $result.picker_resolutions) {
                foreach ($pickerArm in @('canonical', 'projection', 'B', 'C')) {
                    $pickerSamples = @($pickerResolution.metrics.arms[$pickerArm].samples | Measure-Object -Sum).Sum
                    $metricRows.Add([pscustomobject]@{
                        run_id = $runId; scenario_id = $scenario; repeat = [int]$row.repeat; arm = ('PICKER_' + $pickerArm.ToUpperInvariant()); resolution = [double]$pickerResolution.spacing
                        candidate_operations = [int]$result.candidate_operation_count; build_usec = 0.0; incremental_usec = 0.0; save_usec = 0.0; load_usec = 0.0
                        query_p50_usec = [double]$pickerResolution.metrics.arms[$pickerArm].elapsed_usec.p50_usec
                        query_p95_usec = [double]$pickerResolution.metrics.arms[$pickerArm].elapsed_usec.p95_usec
                        query_p99_usec = [double]$pickerResolution.metrics.arms[$pickerArm].elapsed_usec.p99_usec
                        picker_sample_count = [int]$pickerSamples
                        lod0_usec = 0.0; lod1_usec = 0.0; node_error_max = 0.0; lod0_surface_p95 = 0.0; lod1_surface_p95 = 0.0
                        lod0_normal_p95_deg = 0.0; lod1_normal_p95_deg = 0.0; storage_bytes = [long]$result.storage_bytes; working_set_peak_bytes = [long]$peakWorkingSet
                    })
                }
            }
        }
    }
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name], 'Process') }
}
$csvRows = foreach ($record in $results) {
    [pscustomobject]@{ run_id = $record.run_id; scenario_id = $record.scenario_id; repeat = $record.repeat; order_index = $record.order_index; status = $record.status; exit_code = $record.exit_code; duration_ms = $record.duration_ms; peak_working_set_bytes = $record.peak_working_set_bytes; result_sha256 = $record.result_sha256; stdout_sha256 = $record.stdout_sha256; stderr_sha256 = $record.stderr_sha256 }
}
$csvRows | Export-Csv -LiteralPath (Join-Path $EvidenceRoot 'campaign.csv') -NoTypeInformation -Encoding UTF8
$metricRows | Export-Csv -LiteralPath (Join-Path $EvidenceRoot 'metrics-per-run.csv') -NoTypeInformation -Encoding UTF8
function Get-MedianValue([double[]]$Values) {
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}
$scenarioSummaries = [System.Collections.Generic.List[object]]::new()
$metricGroups = $metricRows | Group-Object { '{0}|{1}|{2}' -f $_.scenario_id, $_.arm, $_.resolution }
foreach ($group in $metricGroups) {
    $items = @($group.Group)
    $row = $items[0]
    $summaryRow = [ordered]@{ scenario_id = $row.scenario_id; arm = $row.arm; resolution = $row.resolution; completed_processes = $items.Count }
    foreach ($metric in @('build_usec', 'incremental_usec', 'save_usec', 'load_usec', 'query_p50_usec', 'query_p95_usec', 'query_p99_usec', 'lod0_usec', 'lod1_usec', 'node_error_max', 'lod0_surface_p95', 'lod1_surface_p95', 'lod0_normal_p95_deg', 'lod1_normal_p95_deg', 'storage_bytes', 'working_set_peak_bytes')) {
        $values = @($items | ForEach-Object { [double]$_.$metric })
        $summaryRow[$metric + '_median_across_processes'] = Get-MedianValue $values
        $summaryRow[$metric + '_min_across_processes'] = ($values | Measure-Object -Minimum).Minimum
        $summaryRow[$metric + '_max_across_processes'] = ($values | Measure-Object -Maximum).Maximum
    }
    $scenarioSummaries.Add([pscustomobject]$summaryRow)
}
$scenarioSummaries | Export-Csv -LiteralPath (Join-Path $EvidenceRoot 'scenario-summary.csv') -NoTypeInformation -Encoding UTF8
[System.IO.File]::WriteAllText((Join-Path $EvidenceRoot 'scenario-summary.json'), ($scenarioSummaries | ConvertTo-Json -Depth 12) + "`n", [System.Text.UTF8Encoding]::new($false))
$countsByStatus = @{}
foreach ($record in $results) { $key = [string]$record.status; if (-not $countsByStatus.ContainsKey($key)) { $countsByStatus[$key] = 0 }; $countsByStatus[$key] = 1 + [int]$countsByStatus[$key] }
$summary = [ordered]@{ source_head = $head; manifest_sha256 = $manifestSha; run_count = $results.Count; status_counts = $countsByStatus; completed_process_metrics = $metricRows.Count; summarized_scenario_arm_groups = $scenarioSummaries.Count; completed_utc = [DateTime]::UtcNow.ToString('o'); campaign_jsonl_sha256 = (Get-FileHash -LiteralPath $jsonlPath -Algorithm SHA256).Hash.ToLowerInvariant(); campaign_csv_sha256 = (Get-FileHash -LiteralPath (Join-Path $EvidenceRoot 'campaign.csv') -Algorithm SHA256).Hash.ToLowerInvariant(); metrics_csv_sha256 = (Get-FileHash -LiteralPath (Join-Path $EvidenceRoot 'metrics-per-run.csv') -Algorithm SHA256).Hash.ToLowerInvariant(); scenario_summary_sha256 = (Get-FileHash -LiteralPath (Join-Path $EvidenceRoot 'scenario-summary.json') -Algorithm SHA256).Hash.ToLowerInvariant() }
[System.IO.File]::WriteAllText((Join-Path $EvidenceRoot 'summary.json'), ($summary | ConvertTo-Json -Depth 10) + "`n", [System.Text.UTF8Encoding]::new($false))
$artifactRows = foreach ($file in Get-ChildItem -LiteralPath $EvidenceRoot -Recurse -File | Where-Object { $_.Name -notin @('artifact-index.csv', 'summary.json') }) {
    [pscustomobject]@{ relative_path = $file.FullName.Substring($EvidenceRoot.TrimEnd('\').Length + 1); bytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$artifactRows | Export-Csv -LiteralPath (Join-Path $EvidenceRoot 'artifact-index.csv') -NoTypeInformation -Encoding UTF8
$summary['artifact_index_sha256'] = (Get-FileHash -LiteralPath (Join-Path $EvidenceRoot 'artifact-index.csv') -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText((Join-Path $EvidenceRoot 'summary.json'), ($summary | ConvertTo-Json -Depth 10) + "`n", [System.Text.UTF8Encoding]::new($false))
$summary | ConvertTo-Json -Depth 10

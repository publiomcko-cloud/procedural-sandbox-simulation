[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [Parameter(Mandatory=$true)][string]$Stage,
    [Parameter(Mandatory=$true)][string]$Worktree,
    [Parameter(Mandatory=$true)][string]$SourceSha,
    [Parameter(Mandatory=$true)][string]$ProfileRoot,
    [Parameter(Mandatory=$true)][string]$GodotPath,
    [Parameter(Mandatory=$true)][string[]]$ArgumentVector,
    [Parameter(Mandatory=$true)][int]$TimeoutSeconds,
    [string]$ArtifactDirectory = '',
    [hashtable]$ExtraEnvironment = @{}
)
$ErrorActionPreference = 'Stop'
$expectedOrigin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$expectedGodotSha = 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643'
$expectedManifestSha = '1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972'
$stagePath = Join-Path $EvidenceDirectory $Stage
if (-not (Test-Path -LiteralPath $stagePath -PathType Container)) { throw 'evidence directory missing' }
if ((git -C $Worktree rev-parse HEAD).Trim() -ne $SourceSha) { throw 'source HEAD mismatch' }
if ((git -C $Worktree remote get-url origin).Trim() -ne $expectedOrigin) { throw 'origin mismatch' }
git -C $Worktree diff --quiet HEAD; if ($LASTEXITCODE -ne 0) { throw 'tracked worktree modified' }
git -C $Worktree diff --cached --quiet HEAD; if ($LASTEXITCODE -ne 0) { throw 'index modified' }
if ((Get-FileHash -LiteralPath $GodotPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedGodotSha) { throw 'Godot executable SHA mismatch' }
$manifestPath = Join-Path $Worktree 'game\tests\prototypes\p3_1_r9_2_e2e_inputs.jsonl'
$sidecarPath = Join-Path $Worktree 'game\tests\prototypes\p3_1_r9_2_e2e_inputs.sha256'
if ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedManifestSha) { throw 'manifest SHA mismatch' }
if ((Get-Content -LiteralPath $sidecarPath -Raw).Trim() -ne ($expectedManifestSha + '  p3_1_r9_2_e2e_inputs.jsonl')) { throw 'manifest sidecar mismatch' }
if (-not (Test-Path -LiteralPath $ProfileRoot)) {
    New-Item -ItemType Directory -Path $ProfileRoot | Out-Null
    foreach ($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')) { New-Item -ItemType Directory -Path (Join-Path $ProfileRoot $name) | Out-Null }
} else { throw 'profile root already exists' }
if (-not [string]::IsNullOrEmpty($ArtifactDirectory) -and (Test-Path -LiteralPath $ArtifactDirectory)) { throw 'artifact directory already exists' }
function Write-NewDurable([string]$path, [string]$text) {
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($text)
    $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Snap([string]$path) {
    $os = Get-CimInstance Win32_OperatingSystem
    $mem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    $cs = Get-CimInstance Win32_ComputerSystem
    $all = Get-Process -ErrorAction SilentlyContinue
    $tempDrive = ([IO.Path]::GetPathRoot([IO.Path]::GetTempPath())).TrimEnd(':/\')
    $godotRunning = @($all | Where-Object { $_.ProcessName -match '^godot' } | Select-Object ProcessName,Id,PrivateMemorySize64,WorkingSet64)
    $data = [ordered]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
        physical_total_kb = [int64]$os.TotalVisibleMemorySize
        physical_available_kb = [int64]$os.FreePhysicalMemory
        committed_bytes = [int64]$mem.CommittedBytes
        commit_limit_bytes = [int64]$mem.CommitLimit
        free_commit_bytes = ([int64]$mem.CommitLimit - [int64]$mem.CommittedBytes)
        commit_percent = [math]::Round(100.0 * [int64]$mem.CommittedBytes / [int64]$mem.CommitLimit,2)
        available_mbytes = [int64]$mem.AvailableMBytes
        automatic_managed_pagefile = $cs.AutomaticManagedPagefile
        pagefile_usage = @(Get-CimInstance Win32_PageFileUsage | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage)
        pagefile_setting = @(Get-CimInstance Win32_PageFileSetting | Select-Object Name,InitialSize,MaximumSize)
        disk_c_free_bytes = (Get-PSDrive C).Free
        temp_drive_free_bytes = (Get-PSDrive -Name $tempDrive -ErrorAction SilentlyContinue).Free
        top_private = @($all | Sort-Object PrivateMemorySize64 -Descending | Select-Object -First 12 ProcessName,Id,PrivateMemorySize64,WorkingSet64)
        selected_processes = @($all | Where-Object { $_.ProcessName -match 'godot|code|chrome|brave|firefox|msedge|powershell|pwsh|vmmem' } | Select-Object ProcessName,Id,PrivateMemorySize64,WorkingSet64)
        running_godot_processes = $godotRunning
        wsl_running = ((wsl.exe --list --running 2>&1 | Out-String) -replace [char]0,'')
    }
    Write-NewDurable $path ($data | ConvertTo-Json -Depth 8)
    return $data
}
$hostBeforePath = Join-Path $stagePath 'host-before.json'
$hostAfterPath = Join-Path $stagePath 'host-after.json'
$reservationPath = Join-Path $stagePath 'reservation.json'
$intentPath = Join-Path $stagePath 'launch-intent.json'
$createdPath = Join-Path $stagePath 'process-created.json'
$processPath = Join-Path $stagePath 'process.json'
$stdoutPath = Join-Path $stagePath 'stdout.txt'
$stderrPath = Join-Path $stagePath 'stderr.txt'
$resourceMonitorPath = Join-Path $stagePath 'resource-monitor.jsonl'
$resourceFloorBytes = 4GB
foreach ($path in @($hostBeforePath,$hostAfterPath,$reservationPath,$intentPath,$createdPath,$processPath,$stdoutPath,$stderrPath,$resourceMonitorPath)) {
    if (Test-Path -LiteralPath $path) { throw "evidence destination already exists: $path" }
}
$before = Snap $hostBeforePath
$ready = ([int64]$before.free_commit_bytes -ge $resourceFloorBytes -and ([int64]$before.physical_available_kb * 1KB) -ge 8GB -and [int64]$before.disk_c_free_bytes -ge 10GB -and [int64]$before.temp_drive_free_bytes -ge 10GB -and @($before.running_godot_processes).Count -eq 0)
$reservation = [ordered]@{stage=$Stage;source_sha=$SourceSha;created_utc=(Get-Date).ToUniversalTime().ToString('o');owner_authorized_override='monitored D3 only';original_gate_bytes=6GB;prelaunch_floor_bytes=$resourceFloorBytes;runtime_abort_floor_bytes=$resourceFloorBytes;status=$(if ($ready) {'RESERVED'} else {'HOST_GATE_BLOCKED_NOT_STARTED'})}
Write-NewDurable $reservationPath ($reservation | ConvertTo-Json -Depth 5)
if (-not $ready) {
    Write-NewDurable $processPath ([ordered]@{stage=$Stage;source_sha=$SourceSha;scenario_started=$false;status='HOST_GATE_BLOCKED_NOT_STARTED';host_before=$hostBeforePath;required_free_commit_bytes=$resourceFloorBytes;original_gate_bytes=6GB;owner_authorized_override='monitored D3 only';required_physical_available_bytes=8GB;required_disk_free_bytes=10GB;required_temp_free_bytes=10GB} | ConvertTo-Json -Depth 5)
    Snap $hostAfterPath | Out-Null
    exit 21
}
$envBlock = [ordered]@{
    APPDATA = Join-Path $ProfileRoot 'APPDATA'
    LOCALAPPDATA = Join-Path $ProfileRoot 'LOCALAPPDATA'
    TEMP = Join-Path $ProfileRoot 'TEMP'
    TMP = Join-Path $ProfileRoot 'TMP'
    R96R1_ARTIFACT_DIR = $ArtifactDirectory
}
$allowedExtraEnvironment = @('R95_CANDIDATE_ID','R95_CANDIDATE_SOURCE_SHA','R95_RUN_ID','R95_ORACLE_SHA','R96R1_ATTEMPT')
foreach ($name in $ExtraEnvironment.Keys) {
    if ($name -notin $allowedExtraEnvironment) { throw "extra environment key is not allowlisted: $name" }
    if ($envBlock.Contains($name)) { throw "extra environment cannot override an isolation variable: $name" }
    $envBlock[$name] = [string]$ExtraEnvironment[$name]
}
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $GodotPath
$psi.WorkingDirectory = $Worktree
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.Arguments = ($ArgumentVector -join ' ')
foreach ($name in $envBlock.Keys) { $psi.EnvironmentVariables[$name] = [string]$envBlock[$name] }
$intent = [ordered]@{stage=$Stage;source_sha=$SourceSha;origin=$expectedOrigin;godot_path=$GodotPath;godot_sha256=$expectedGodotSha;godot_version='4.7.2.stable.official.ed1daf0bf';manifest_sha256=$expectedManifestSha;arguments=$ArgumentVector;working_directory=$Worktree;profile_root=$ProfileRoot;artifact_directory=$ArtifactDirectory;owner_authorized_override='monitored D3 only';original_prelaunch_gate_bytes=6GB;minimum_free_commit_bytes=$resourceFloorBytes;runtime_monitor_poll_ms=100;environment=$envBlock;intent_utc=(Get-Date).ToUniversalTime().ToString('o')}
Write-NewDurable $intentPath ($intent | ConvertTo-Json -Depth 8)
Write-NewDurable $resourceMonitorPath ''
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi
$processStarted = $false; $timedOut = $false; $resourceStopped = $false; $resourceStopReason = ''; $resourceStopFreeCommitBytes = $null; $monitorSamples = 0; $exitCode = $null; $exception = $null; $observed = $null; $startedUtc = (Get-Date).ToUniversalTime().ToString('o')
$watch = [Diagnostics.Stopwatch]::StartNew()
try {
    $processStarted = $process.Start()
    if (-not $processStarted) { throw 'Process.Start returned false' }
    $engineProcessId = $process.Id
    try { $observed = Get-CimInstance Win32_Process -Filter "ProcessId=$engineProcessId" | Select-Object ProcessId,ParentProcessId,CommandLine,ExecutablePath,CreationDate } catch { $observed = $null }
    Write-NewDurable $createdPath ([ordered]@{stage=$Stage;source_sha=$SourceSha;process_id=$engineProcessId;observed_process=$observed;started_utc=$startedUtc;created_utc=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Depth 8)
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    while (-not $process.HasExited) {
        if ($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) { $timedOut = $true; try { $process.Kill() } catch {}; break }
        try {
            $monitorMem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
            if ($null -eq $monitorMem) { throw 'commit monitor returned no memory record' }
            $freeCommitNow = [int64]$monitorMem.CommitLimit - [int64]$monitorMem.CommittedBytes
            $processNow = Get-Process -Id $engineProcessId -ErrorAction SilentlyContinue
            $sample = [ordered]@{timestamp_utc=(Get-Date).ToUniversalTime().ToString('o');elapsed_ms=[math]::Round($watch.Elapsed.TotalMilliseconds,2);free_commit_bytes=$freeCommitNow;floor_bytes=$resourceFloorBytes;godot_pid=$engineProcessId;godot_private_bytes=$(if ($processNow) {[int64]$processNow.PrivateMemorySize64} else {$null});godot_working_set_bytes=$(if ($processNow) {[int64]$processNow.WorkingSet64} else {$null})}
            [IO.File]::AppendAllText($resourceMonitorPath,(($sample | ConvertTo-Json -Compress -Depth 4)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
            $monitorSamples++
            if ($freeCommitNow -le $resourceFloorBytes) {
                $resourceStopped = $true
                $resourceStopReason = 'FREE_COMMIT_AT_OR_BELOW_4_GIB_FLOOR'
                $resourceStopFreeCommitBytes = $freeCommitNow
                try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch { $resourceStopReason += ';KILL_EXCEPTION=' + $_.Exception.Message }
                break
            }
        } catch {
            $resourceStopped = $true
            $resourceStopReason = 'RESOURCE_MONITOR_FAILURE=' + $_.Exception.Message
            try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch { $resourceStopReason += ';KILL_EXCEPTION=' + $_.Exception.Message }
            break
        }
        [void]$process.WaitForExit(100)
    }
    $process.WaitForExit()
    $stdoutText = $outTask.Result
    $stderrText = $errTask.Result
    $exitCode = $process.ExitCode
} catch {
    $exception = $_.Exception.ToString()
    if ($processStarted) { $timedOut = $true; try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } catch {} }
} finally {
    $watch.Stop()
    Write-NewDurable $stdoutPath $(if ($null -ne $stdoutText) { $stdoutText } else { '' })
    Write-NewDurable $stderrPath $(if ($null -ne $stderrText) { $stderrText } else { '' })
    $status = if (-not $processStarted) {'NOT_STARTED'} elseif ($resourceStopped) {'RESOURCE_MONITOR_STOPPED_D3_PROCESS'} elseif ($timedOut) {'STARTED_TIMEOUT_OR_POSTSTART_EXCEPTION'} elseif ($exitCode -eq 0) {'PROCESS_EXIT_0'} else {'PROCESS_NONZERO'}
    $record = [ordered]@{stage=$Stage;source_sha=$SourceSha;status=$status;scenario_started=$processStarted;process_id=$(if ($processStarted) {$process.Id} else {$null});observed_process=$observed;started_utc=$startedUtc;finished_utc=(Get-Date).ToUniversalTime().ToString('o');elapsed_ms=[math]::Round($watch.Elapsed.TotalMilliseconds,2);timeout_seconds=$TimeoutSeconds;timeout=$timedOut;exit_code=$exitCode;exception=$exception;arguments=$ArgumentVector;environment=$envBlock;stdout=$stdoutPath;stdout_sha256=(Get-FileHash $stdoutPath -Algorithm SHA256).Hash.ToLowerInvariant();stderr=$stderrPath;stderr_sha256=(Get-FileHash $stderrPath -Algorithm SHA256).Hash.ToLowerInvariant();host_before=$hostBeforePath;host_after=$hostAfterPath;artifact_directory=$ArtifactDirectory}
    $record['owner_authorized_override']='monitored D3 only'
    $record['original_prelaunch_gate_bytes']=6GB
    $record['runtime_abort_floor_bytes']=$resourceFloorBytes
    $record['resource_stop_triggered']=$resourceStopped
    $record['resource_stop_reason']=$resourceStopReason
    $record['resource_stop_free_commit_bytes']=$resourceStopFreeCommitBytes
    $record['resource_monitor_samples']=$monitorSamples
    $record['resource_monitor_path']=$resourceMonitorPath
    $record['resource_monitor_sha256']=(Get-FileHash $resourceMonitorPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Write-NewDurable $processPath ($record | ConvertTo-Json -Depth 8)
    Snap $hostAfterPath | Out-Null
}
if (-not $processStarted) { exit 22 }
if ($resourceStopped) { exit 125 }
if ($timedOut) { exit 124 }
if ($null -eq $exitCode) { exit 23 }
exit $exitCode

param(
	[Parameter(Mandatory = $true)][ValidateSet('import', 'check-only', 'geometry')][string]$Stage,
	[Parameter(Mandatory = $true)][string]$AttemptId,
	[Parameter(Mandatory = $true)][string]$Hypothesis,
	[Parameter(Mandatory = $true)][string]$EvidenceRoot
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$expectedGodotSha = 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643'
$expectedCandidateSha = '334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a'
$attemptRoot = Join-Path $EvidenceRoot ($AttemptId + '_' + $Stage)
$profileRoot = Join-Path $attemptRoot 'profile'
if (Test-Path -LiteralPath $attemptRoot) { throw "Evidence attempt directory already exists: $attemptRoot" }
New-Item -ItemType Directory -Path $attemptRoot -Force | Out-Null
New-Item -ItemType Directory -Path $profileRoot -Force | Out-Null

$observedGodotSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $godot).Hash.ToLowerInvariant()
if ($observedGodotSha -ne $expectedGodotSha) { throw "Godot executable hash mismatch: $observedGodotSha" }
$sourceSha = (& git -C $repo rev-parse HEAD).Trim()
$candidateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r9_2_candidate_impl.gd')).Hash.ToLowerInvariant()
if ($candidateSha -ne $expectedCandidateSha) { throw "Candidate D byte pin mismatch: $candidateSha" }

$arguments = switch ($Stage) {
	'import' { @('--headless', '--path', './game', '--editor', '--import') }
	'check-only' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r10_a_campaign.gd') }
	'geometry' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_a_campaign.gd') }
}
$commandLine = $arguments -join ' '
$runId = [guid]::NewGuid().ToString('N')
$intent = [ordered]@{
	schema = 'P3.1.R10A.LaunchIntent.v1'; run_id = $runId; stage = $Stage; attempt_id = $AttemptId; hypothesis = $Hypothesis
	repository = $repo; origin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'; source_sha = $sourceSha
	godot_path = $godot; godot_sha256 = $observedGodotSha; candidate_d_sha256 = $candidateSha; arguments = $arguments
	command_line = $commandLine; profile_root = $profileRoot; artifact_root = $attemptRoot; created_utc = [DateTime]::UtcNow.ToString('o')
}
$intentPath = Join-Path $attemptRoot 'launch-intent.json'
$intentJson = $intent | ConvertTo-Json -Depth 8
$intentStream = [IO.File]::Open($intentPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try { $intentBytes = [Text.UTF8Encoding]::new($false).GetBytes($intentJson); $intentStream.Write($intentBytes, 0, $intentBytes.Length); $intentStream.Flush($true) } finally { $intentStream.Dispose() }

$hostBefore = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
$before = [ordered]@{ timestamp_utc = [DateTime]::UtcNow.ToString('o'); committed_bytes = [int64]$hostBefore.CommittedBytes; commit_limit_bytes = [int64]$hostBefore.CommitLimit; free_commit_bytes = ([int64]$hostBefore.CommitLimit - [int64]$hostBefore.CommittedBytes); available_mbytes = [int64]$hostBefore.AvailableMBytes }
[IO.File]::WriteAllText((Join-Path $attemptRoot 'host-before.json'), ($before | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))

$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $godot
$psi.WorkingDirectory = $repo
$psi.Arguments = $commandLine
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['APPDATA'] = $profileRoot
$psi.EnvironmentVariables['R10A_ATTEMPT'] = $AttemptId
$psi.EnvironmentVariables['R10A_HYPOTHESIS'] = $Hypothesis
$psi.EnvironmentVariables['R10A_SOURCE_SHA'] = $sourceSha
$psi.EnvironmentVariables['R10A_ARTIFACT_DIR'] = $attemptRoot

$proc = [Diagnostics.Process]::new()
$proc.StartInfo = $psi
$startUtc = [DateTime]::UtcNow
if (-not $proc.Start()) { throw 'Process.Start returned false; no scenario process was created.' }
$godotProcessId = $proc.Id
$launcherProcessId = $PID
$created = [ordered]@{ schema = 'P3.1.R10A.ProcessCreated.v1'; run_id = $runId; stage = $Stage; pid = $godotProcessId; parent_pid = $launcherProcessId; start_utc = $startUtc.ToString('o'); process_name = $proc.ProcessName; source_sha = $sourceSha; command_line = $commandLine }
[IO.File]::WriteAllText((Join-Path $attemptRoot 'process-created.json'), ($created | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()
$monitorPath = Join-Path $attemptRoot 'resource-monitor.jsonl'
$monitorStream = [IO.File]::Open($monitorPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
$monitorWriter = [IO.StreamWriter]::new($monitorStream, [Text.UTF8Encoding]::new($false))
$resourceAbort = $false
$timeoutAbort = $false
$minFreeCommit = [int64]::MaxValue
$warningCount = 0
$lastSample = [DateTime]::UtcNow
$timeout = [TimeSpan]::FromMinutes(10)
try {
	while (-not $proc.HasExited) {
		$sampleTime = [DateTime]::UtcNow
		$memory = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
		$freeCommit = [int64]$memory.CommitLimit - [int64]$memory.CommittedBytes
		if ($freeCommit -lt $minFreeCommit) { $minFreeCommit = $freeCommit }
		$processInfo = $null
		try { $gp = Get-Process -Id $godotProcessId -ErrorAction Stop; $processInfo = @{ working_set_bytes = [int64]$gp.WorkingSet64; private_bytes = [int64]$gp.PrivateMemorySize64 } } catch { $processInfo = @{ unavailable = $_.Exception.Message } }
		$sample = [ordered]@{ timestamp_utc = $sampleTime.ToString('o'); interval_ms = ($sampleTime - $lastSample).TotalMilliseconds; committed_bytes = [int64]$memory.CommittedBytes; commit_limit_bytes = [int64]$memory.CommitLimit; free_commit_bytes = $freeCommit; available_mbytes = [int64]$memory.AvailableMBytes; godot_pid = $godotProcessId; godot = $processInfo; warning = ($freeCommit -le 3GB); abort_floor = ($freeCommit -le 2GB) }
		$monitorWriter.WriteLine(($sample | ConvertTo-Json -Compress -Depth 5)); $monitorWriter.Flush()
		if ($freeCommit -le 3GB) { $warningCount++ }
		$lastSample = $sampleTime
		if ($freeCommit -le 2GB) {
			$resourceAbort = $true
			try { $proc.Kill() } catch { }
			break
		}
		if (($sampleTime - $startUtc) -ge $timeout) {
			$timeoutAbort = $true
			try { $proc.Kill() } catch { }
			break
		}
		Start-Sleep -Milliseconds 350
	}
	$proc.WaitForExit()
} finally {
	$monitorWriter.Dispose()
}
$elapsedMs = ([DateTime]::UtcNow - $startUtc).TotalMilliseconds
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
[IO.File]::WriteAllText((Join-Path $attemptRoot 'stdout.txt'), $stdout, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $attemptRoot 'stderr.txt'), $stderr, [Text.UTF8Encoding]::new($false))
$exitCode = if ($resourceAbort -or $timeoutAbort) { $null } else { $proc.ExitCode }
$scriptErrorDetected = $stderr -match '(?m)^(SCRIPT ERROR:|ERROR:|Parse Error:|Compile Error:)'
$preflightMarkerCount = [regex]::Matches($stdout, '(?m)^R10A_PREFLIGHT ').Count
$completionMatches = [regex]::Matches($stdout, '(?m)^R10A_ATTEMPT_COMPLETE (.+)$')
$terminalResult = 'NOT_AVAILABLE'
if ($completionMatches.Count -eq 1) {
	try { $terminalResult = [string](($completionMatches[0].Groups[1].Value | ConvertFrom-Json -ErrorAction Stop).result) } catch { $terminalResult = 'INVALID_COMPLETION_JSON' }
}
$validationStatus = if ($resourceAbort) { 'RUNTIME_ABORT_RESOURCE_SAFETY' } elseif ($timeoutAbort) { 'RUNTIME_ABORT_TIMEOUT' } elseif ($scriptErrorDetected) { 'GODOT_SCRIPT_ERROR' } elseif ($exitCode -ne 0) { 'PROCESS_NONZERO_EXIT' } elseif ($Stage -eq 'geometry' -and ($preflightMarkerCount -ne 1 -or $completionMatches.Count -ne 1 -or $terminalResult -notin @('PASS', 'FAILED_TARGET', 'PARTIAL', 'FAILED_WITH_REGRESSION'))) { 'GEOMETRY_TERMINAL_EVIDENCE_INVALID' } elseif ($Stage -eq 'import') { 'IMPORT_PROCESS_PASS' } elseif ($Stage -eq 'check-only') { 'CHECK_ONLY_PROCESS_PASS' } else { 'GEOMETRY_RESULT_RECORDED' }
$afterMemory = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
$after = [ordered]@{ timestamp_utc = [DateTime]::UtcNow.ToString('o'); committed_bytes = [int64]$afterMemory.CommittedBytes; commit_limit_bytes = [int64]$afterMemory.CommitLimit; free_commit_bytes = ([int64]$afterMemory.CommitLimit - [int64]$afterMemory.CommittedBytes); available_mbytes = [int64]$afterMemory.AvailableMBytes }
[IO.File]::WriteAllText((Join-Path $attemptRoot 'host-after.json'), ($after | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$processRecord = [ordered]@{ schema = 'P3.1.R10A.ProcessRecord.v1'; run_id = $runId; stage = $Stage; pid = $godotProcessId; parent_pid = $launcherProcessId; command_line = $commandLine; source_sha = $sourceSha; exit_code = $exitCode; elapsed_ms = $elapsedMs; resource_abort = $resourceAbort; timeout_abort = $timeoutAbort; validation_status = $validationStatus; script_error_detected = $scriptErrorDetected; preflight_marker_count = $preflightMarkerCount; completion_marker_count = $completionMatches.Count; terminal_result = $terminalResult; min_free_commit_bytes = $minFreeCommit; warning_samples = $warningCount; stdout_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $attemptRoot 'stdout.txt')).Hash.ToLowerInvariant(); stderr_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $attemptRoot 'stderr.txt')).Hash.ToLowerInvariant(); monitor_sha256 = (Get-FileHash -Algorithm SHA256 $monitorPath).Hash.ToLowerInvariant() }
[IO.File]::WriteAllText((Join-Path $attemptRoot 'process.json'), ($processRecord | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
$processRecord | ConvertTo-Json -Depth 6
if ($resourceAbort) { exit 75 }
if ($timeoutAbort) { exit 76 }
if ($scriptErrorDetected -or $validationStatus -eq 'GEOMETRY_TERMINAL_EVIDENCE_INVALID') { exit 2 }
if ($exitCode -ne 0) { exit 1 }

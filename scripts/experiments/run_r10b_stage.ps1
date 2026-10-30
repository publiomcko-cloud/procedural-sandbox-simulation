param(
	[Parameter(Mandatory = $true)][ValidateSet('import', 'check-only', 'check-ray', 'ray-causality', 'check-authority', 'graph-contract', 'geometry')][string]$Stage,
	[Parameter(Mandatory = $true)][string]$AttemptId,
	[Parameter(Mandatory = $true)][string]$Hypothesis,
	[Parameter(Mandatory = $true)][string]$EvidenceRoot
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$expectedGodotSha = 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643'
$expectedCandidateSha = '334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a'
$expectedManifestSha = '1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972'
$expectedAuthoritySha = 'feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216'
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
$manifestSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r9_2_e2e_inputs.jsonl')).Hash.ToLowerInvariant()
if ($manifestSha -ne $expectedManifestSha) { throw "Frozen manifest byte pin mismatch: $manifestSha" }
$authoritySha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_a_topology_authority.gd')).Hash.ToLowerInvariant()
if ($authoritySha -ne $expectedAuthoritySha) { throw "R10-A authority byte pin mismatch: $authoritySha" }
$rayScriptSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_b_ray_causality.gd')).Hash.ToLowerInvariant()
$rayFixtureSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'docs\reports\P3-1-R10-B-CAMPAIGN\fixtures\ray_reference_fixture_r2.json')).Hash.ToLowerInvariant()
$campaignSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_b_campaign.gd')).Hash.ToLowerInvariant()
$realizerSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_b_realizer.gd')).Hash.ToLowerInvariant()

$arguments = switch ($Stage) {
	'import' { @('--headless', '--path', './game', '--editor', '--import') }
	'check-only' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r10_b_campaign.gd') }
	'check-ray' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r10_b_ray_causality.gd') }
	'ray-causality' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_b_ray_causality.gd') }
	'check-authority' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r10_a_topology_authority.gd') }
	'graph-contract' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_b_campaign.gd') }
	'geometry' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_b_campaign.gd') }
}
$commandLine = $arguments -join ' '
$runId = [guid]::NewGuid().ToString('N')
$intent = [ordered]@{
	schema = 'P3.1.R10B.LaunchIntent.v1'; run_id = $runId; stage = $Stage; attempt_id = $AttemptId; hypothesis = $Hypothesis
	repository = $repo; origin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'; source_sha = $sourceSha
	godot_path = $godot; godot_sha256 = $observedGodotSha; candidate_d_sha256 = $candidateSha; arguments = $arguments
	command_line = $commandLine; profile_root = $profileRoot; artifact_root = $attemptRoot; runner_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash.ToLowerInvariant(); source_physical_hashes = @{ candidate_d = $candidateSha; manifest = $manifestSha; r10a_authority = $authoritySha; ray_script = $rayScriptSha; ray_fixture = $rayFixtureSha; campaign = $campaignSha; realizer = $realizerSha }; created_utc = [DateTime]::UtcNow.ToString('o')
}
$intentPath = Join-Path $attemptRoot 'launch-intent.json'
$intentJson = $intent | ConvertTo-Json -Depth 8
$intentStream = [IO.File]::Open($intentPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try { $intentBytes = [Text.UTF8Encoding]::new($false).GetBytes($intentJson); $intentStream.Write($intentBytes, 0, $intentBytes.Length); $intentStream.Flush($true) } finally { $intentStream.Dispose() }

$hostBefore = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
$before = [ordered]@{ timestamp_utc = [DateTime]::UtcNow.ToString('o'); committed_bytes = [int64]$hostBefore.CommittedBytes; commit_limit_bytes = [int64]$hostBefore.CommitLimit; free_commit_bytes = ([int64]$hostBefore.CommitLimit - [int64]$hostBefore.CommittedBytes); available_mbytes = [int64]$hostBefore.AvailableMBytes }
[IO.File]::WriteAllText((Join-Path $attemptRoot 'host-before.json'), ($before | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
if ([int64]$before.free_commit_bytes -le 2GB) {
	$blocked = [ordered]@{ schema = 'P3.1.R10B.ProcessRecord.v1'; run_id = $runId; stage = $Stage; source_sha = $sourceSha; launched = $false; exit_code = $null; validation_status = 'PRELAUNCH_ABORT_FREE_COMMIT_AT_OR_BELOW_2GB'; free_commit_bytes = [int64]$before.free_commit_bytes }
	[IO.File]::WriteAllText((Join-Path $attemptRoot 'process.json'), ($blocked | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
	$blocked | ConvertTo-Json -Depth 5
	exit 75
}

$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $godot
$psi.WorkingDirectory = $repo
$psi.Arguments = $commandLine
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$profileData = Join-Path $profileRoot 'APPDATA'
$profileLocal = Join-Path $profileRoot 'LOCALAPPDATA'
$profileTemp = Join-Path $profileRoot 'TEMP'
New-Item -ItemType Directory -Path $profileData, $profileLocal, $profileTemp -Force | Out-Null
$psi.EnvironmentVariables['APPDATA'] = $profileData
$psi.EnvironmentVariables['LOCALAPPDATA'] = $profileLocal
$psi.EnvironmentVariables['TEMP'] = $profileTemp
$psi.EnvironmentVariables['TMP'] = $profileTemp
$psi.EnvironmentVariables['R10B_ATTEMPT'] = $AttemptId
$psi.EnvironmentVariables['R10B_HYPOTHESIS'] = $Hypothesis
$psi.EnvironmentVariables['R10B_SOURCE_SHA'] = $sourceSha
$psi.EnvironmentVariables['R10B_ARTIFACT_DIR'] = $attemptRoot
$psi.EnvironmentVariables['R10B_REPO_ROOT'] = $repo
$psi.EnvironmentVariables['R10B_CAMPAIGN_SOURCE_SHA256'] = $campaignSha
$psi.EnvironmentVariables['R10B_REALIZER_SOURCE_SHA256'] = $realizerSha
if ($Stage -in @('check-only', 'check-ray', 'ray-causality', 'graph-contract', 'geometry')) {
	$psi.EnvironmentVariables['R10B_RAY_SOURCE_SHA256'] = $rayScriptSha
	$psi.EnvironmentVariables['R10B_RAY_FIXTURE_SHA256'] = $rayFixtureSha
}
if ($Stage -eq 'graph-contract') { $psi.EnvironmentVariables['R10B_GRAPH_ONLY'] = '1' }

$proc = [Diagnostics.Process]::new()
$proc.StartInfo = $psi
$startUtc = [DateTime]::UtcNow
if (-not $proc.Start()) { throw 'Process.Start returned false; no scenario process was created.' }
$godotProcessId = $proc.Id
$launcherProcessId = [Diagnostics.Process]::GetCurrentProcess().Id
$created = [ordered]@{ schema = 'P3.1.R10B.ProcessCreated.v1'; run_id = $runId; stage = $Stage; pid = $godotProcessId; parent_pid = $launcherProcessId; start_utc = $startUtc.ToString('o'); process_name = $proc.ProcessName; source_sha = $sourceSha; command_line = $commandLine }
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
$combinedOutput = $stdout + "`n" + $stderr
$scriptErrorDetected = $combinedOutput -match '(?m)^(SCRIPT ERROR:|ERROR:|Parse Error:|Compile Error:)'
$preflightMarkerCount = [regex]::Matches($stdout, '(?m)^R10B_PREFLIGHT ').Count
$completionMatches = [regex]::Matches($stdout, '(?m)^R10B_ATTEMPT_COMPLETE (.+)$')
$graphContractMatches = [regex]::Matches($stdout, '(?m)^R10B_GRAPH_CONTRACT_COMPLETE (.+)$')
$rayCompletionMatches = [regex]::Matches($stdout, '(?m)^R10B_RAY_DIAGNOSTIC_COMPLETE (.+)$')
$rayBlockedMatches = [regex]::Matches($stdout, '(?m)^R10B_RAY_BLOCKED (.+)$')
$terminalResult = 'NOT_AVAILABLE'
if ($completionMatches.Count -eq 1) {
	try { $terminalResult = [string](($completionMatches[0].Groups[1].Value | ConvertFrom-Json -ErrorAction Stop).result) } catch { $terminalResult = 'INVALID_COMPLETION_JSON' }
}
$graphContractStatus = 'NOT_AVAILABLE'
if ($graphContractMatches.Count -eq 1) { try { $graphContractStatus = [string](($graphContractMatches[0].Groups[1].Value | ConvertFrom-Json -ErrorAction Stop).status) } catch { $graphContractStatus = 'INVALID_GRAPH_CONTRACT_JSON' } }
$rayStatus = 'NOT_AVAILABLE'
if ($rayCompletionMatches.Count -eq 1) { try { $rayStatus = [string](($rayCompletionMatches[0].Groups[1].Value | ConvertFrom-Json -ErrorAction Stop).status) } catch { $rayStatus = 'INVALID_RAY_RESULT_JSON' } }
$validationStatus = if ($resourceAbort) { 'RUNTIME_ABORT_RESOURCE_SAFETY' } elseif ($timeoutAbort) { 'RUNTIME_ABORT_TIMEOUT' } elseif ($scriptErrorDetected) { 'GODOT_SCRIPT_ERROR' } elseif ($Stage -eq 'ray-causality' -and ($exitCode -ne 0 -or $rayCompletionMatches.Count -ne 1 -or $rayBlockedMatches.Count -ne 0 -or $rayStatus -notin @('PASS', 'DIAGNOSTIC_MISMATCH'))) { 'RAY_DIAGNOSTIC_EVIDENCE_INVALID' } elseif ($exitCode -ne 0) { 'PROCESS_NONZERO_EXIT' } elseif ($Stage -eq 'geometry' -and ($preflightMarkerCount -ne 1 -or $completionMatches.Count -ne 1 -or $terminalResult -notin @('PASS', 'FAILED_TARGET', 'PARTIAL', 'FAILED_WITH_REGRESSION'))) { 'GEOMETRY_TERMINAL_EVIDENCE_INVALID' } elseif ($Stage -eq 'graph-contract' -and ($preflightMarkerCount -ne 1 -or $graphContractMatches.Count -ne 1 -or $graphContractStatus -ne 'PASS' -or $completionMatches.Count -ne 0)) { 'GRAPH_CONTRACT_EVIDENCE_INVALID' } elseif ($Stage -eq 'graph-contract') { 'GRAPH_CONTRACT_PASS' } elseif ($Stage -eq 'import') { 'IMPORT_PROCESS_PASS' } elseif ($Stage -in @('check-only', 'check-ray', 'check-authority')) { 'CHECK_ONLY_PROCESS_PASS' } elseif ($Stage -eq 'ray-causality') { 'RAY_DIAGNOSTIC_CAPTURED' } else { 'GEOMETRY_RESULT_RECORDED' }
$afterMemory = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
$after = [ordered]@{ timestamp_utc = [DateTime]::UtcNow.ToString('o'); committed_bytes = [int64]$afterMemory.CommittedBytes; commit_limit_bytes = [int64]$afterMemory.CommitLimit; free_commit_bytes = ([int64]$afterMemory.CommitLimit - [int64]$afterMemory.CommittedBytes); available_mbytes = [int64]$afterMemory.AvailableMBytes }
[IO.File]::WriteAllText((Join-Path $attemptRoot 'host-after.json'), ($after | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))
$processRecord = [ordered]@{ schema = 'P3.1.R10B.ProcessRecord.v1'; run_id = $runId; stage = $Stage; pid = $godotProcessId; parent_pid = $launcherProcessId; command_line = $commandLine; source_sha = $sourceSha; source_physical_hashes = @{ candidate_d = $candidateSha; manifest = $manifestSha; r10a_authority = $authoritySha; ray_script = $rayScriptSha; ray_fixture = $rayFixtureSha; campaign = $campaignSha; realizer = $realizerSha }; exit_code = $exitCode; elapsed_ms = $elapsedMs; resource_abort = $resourceAbort; timeout_abort = $timeoutAbort; validation_status = $validationStatus; script_error_detected = $scriptErrorDetected; preflight_marker_count = $preflightMarkerCount; graph_contract_marker_count = $graphContractMatches.Count; graph_contract_status = $graphContractStatus; ray_completion_marker_count = $rayCompletionMatches.Count; ray_blocked_marker_count = $rayBlockedMatches.Count; ray_status = $rayStatus; completion_marker_count = $completionMatches.Count; terminal_result = $terminalResult; min_free_commit_bytes = $minFreeCommit; warning_samples = $warningCount; stdout_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $attemptRoot 'stdout.txt')).Hash.ToLowerInvariant(); stderr_sha256 = (Get-FileHash -Algorithm SHA256 (Join-Path $attemptRoot 'stderr.txt')).Hash.ToLowerInvariant(); monitor_sha256 = (Get-FileHash -Algorithm SHA256 $monitorPath).Hash.ToLowerInvariant() }
[IO.File]::WriteAllText((Join-Path $attemptRoot 'process.json'), ($processRecord | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
$processRecord | ConvertTo-Json -Depth 6
if ($resourceAbort) { exit 75 }
if ($timeoutAbort) { exit 76 }
if ($scriptErrorDetected -or $validationStatus -in @('GEOMETRY_TERMINAL_EVIDENCE_INVALID', 'GRAPH_CONTRACT_EVIDENCE_INVALID', 'RAY_DIAGNOSTIC_EVIDENCE_INVALID')) { exit 2 }
if ($exitCode -ne 0) { exit 1 }

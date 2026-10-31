[CmdletBinding()]
param(
	[switch]$ControlOnly,
	[switch]$RunFrozenTarget,
	[string]$RepoRoot,
	[string]$EvidenceRoot,
	[string]$GodotExe,
	[string]$ExecutionCheckoutHead,
	[string]$SourceSha,
	[string]$AttemptId,
	[string]$CampaignSha256,
	[string]$RealizerSha256,
	[string]$Stage0Path,
	[string]$ResidualPath,
	[string]$C6CampaignSha256,
	[string]$C6RealizerSha256,
	[string]$ResidualSha256
)

$ErrorActionPreference = 'Stop'

function Write-NewDurable([string]$Path, [byte[]]$Bytes) {
	$stream = [IO.FileStream]::new($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, [Math]::Max(4096, $Bytes.Length), [IO.FileOptions]::WriteThrough)
	try {
		if ($Bytes.Length -gt 0) { $stream.Write($Bytes, 0, $Bytes.Length) }
		$stream.Flush($true)
	} finally {
		$stream.Dispose()
	}
}

function Write-NewJson([string]$Path, [object]$Value) {
	$json = ConvertTo-Json -InputObject $Value -Depth 16
	Write-NewDurable $Path ([Text.UTF8Encoding]::new($false).GetBytes($json + [Environment]::NewLine))
}

function Get-Sha256([string]$Path) {
	(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if ($ControlOnly -eq $RunFrozenTarget) { throw 'Choose exactly one dispatcher mode.' }
if ([string]::IsNullOrWhiteSpace($EvidenceRoot) -or -not (Test-Path -LiteralPath $EvidenceRoot -PathType Container)) { throw 'Evidence root must exist before reservation.' }
if (@(Get-ChildItem -LiteralPath $EvidenceRoot -Force).Count -ne 0) { throw 'Evidence root must be empty; overwrite is prohibited.' }

$expectedControlExit = $null
$scenarioId = 'NONE'
$phase = 'NONE'
$freeCommitBytes = $null
$appData = 'NOT_APPLICABLE'
if ($ControlOnly) {
	$AttemptId = 'R3_DISPATCHER_CONTROL_01'
	$program = (Get-Process -Id $PID).Path
	$argVector = @('-NoLogo', '-NoProfile', '-Command', "[Console]::Out.WriteLine('R3_CONTROL_STDOUT');[Console]::Error.WriteLine('R3_CONTROL_STDERR');Start-Sleep -Milliseconds 250;exit 23")
	$expectedControlExit = 23
} else {
	if ($AttemptId -ne 'R3_TARGET_20261031_02') { throw 'Frozen R3 target attempt ID mismatch.' }
	if ($RepoRoot -ne 'C:\r12cxr-convergence-20261031') { throw 'Frozen repository path mismatch.' }
	if ($SourceSha -ne 'fdab3b8f16b615077aa44a7901b9555aebd3d80d') { throw 'Frozen R3 code source SHA mismatch.' }
	if ((git -C $RepoRoot rev-parse HEAD).Trim() -ne $ExecutionCheckoutHead) { throw 'Execution checkout HEAD mismatch.' }
	if ((git -C $RepoRoot remote get-url origin).Trim() -ne 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git') { throw 'Repository origin mismatch.' }
	$campaignPath = Join-Path $RepoRoot 'game\tests\prototypes\p3_1_r12_cxr_campaign.gd'
	$realizerPath = Join-Path $RepoRoot 'game\tests\prototypes\p3_1_r12_cxr_field_support_realizer.gd'
	if ((Get-Sha256 $campaignPath) -ne $CampaignSha256 -or (Get-Sha256 $realizerPath) -ne $RealizerSha256) { throw 'R3 source pin mismatch.' }
	git -C $RepoRoot diff --quiet $SourceSha $ExecutionCheckoutHead -- game/tests/prototypes/p3_1_r12_cxr_campaign.gd game/tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd game/tests/prototypes/p3_1_r12_cxr_contract_tests.gd
	if ($LASTEXITCODE -ne 0) { throw 'Execution checkout changed pinned R3 source files.' }
	if ((Get-Sha256 $Stage0Path) -ne '33e04446d25ec8dc21f6794b9509296e7ebcd575c2a8713edefd152f58e1cd0d') { throw 'Stage-0 fixture pin mismatch.' }
	if ((Get-Sha256 $ResidualPath) -ne $ResidualSha256 -or $ResidualSha256 -ne 'ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23') { throw 'Residual fixture pin mismatch.' }
	if ((Get-Sha256 $GodotExe) -ne 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643') { throw 'Godot executable pin mismatch.' }
	$memory = Get-CimInstance Win32_PerfRawData_PerfOS_Memory | Select-Object -First 1 CommittedBytes, CommitLimit
	if ($null -eq $memory -or [int64]$memory.CommitLimit -le [int64]$memory.CommittedBytes) { throw 'Commit-memory telemetry unavailable.' }
	$freeCommitBytes = [int64]$memory.CommitLimit - [int64]$memory.CommittedBytes
	if ($freeCommitBytes -lt 2GB) { throw 'Prelaunch memory stop-loss: free commit below 2 GiB.' }
	if (Test-Path -LiteralPath (Join-Path $EvidenceRoot ('r12cxr_' + $AttemptId + '.json'))) { throw 'Frozen result path already exists.' }
	$program = $GodotExe
	$argVector = @('--headless', '--path', (Join-Path $RepoRoot 'game'), '--script', 'res://tests/prototypes/p3_1_r12_cxr_campaign.gd')
	$scenarioId = 'R9.2.SEAM.XPLUS_EQUAL.v1'
	$phase = 'r3'
}

$reservation = Join-Path $EvidenceRoot 'reservation.json'
$launchIntent = Join-Path $EvidenceRoot 'launch-intent.json'
Write-NewJson $reservation ([ordered]@{attempt_id=$AttemptId; mode=$(if ($ControlOnly) {'CONTROL_ONLY'} else {'FROZEN_R3_TARGET'}); scenario_id=$scenarioId; phase=$phase; created_utc=[DateTime]::UtcNow.ToString('o'); status='RESERVED_NOT_STARTED'; source_sha=$SourceSha; execution_checkout_head=$ExecutionCheckoutHead})
Write-NewJson $launchIntent ([ordered]@{attempt_id=$AttemptId; scenario_id=$scenarioId; phase=$phase; argv=$argVector; executable=$program; intent_utc=[DateTime]::UtcNow.ToString('o'); process_start_attempted=$false; source_sha=$SourceSha; execution_checkout_head=$ExecutionCheckoutHead})

$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $program
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
if ($RepoRoot) { $psi.WorkingDirectory = $RepoRoot }
foreach ($argument in $argVector) { $psi.ArgumentList.Add([string]$argument) }
if ($RunFrozenTarget) {
	$profileRoot = Join-Path $env:TEMP ('r12cxr_r3_userprofile_' + $AttemptId + '_' + [guid]::NewGuid().ToString('N'))
	$appData = Join-Path $profileRoot 'roaming'
	$localAppData = Join-Path $profileRoot 'local'
	$tempData = Join-Path $profileRoot 'temp'
	New-Item -ItemType Directory -Path $appData, $localAppData, $tempData | Out-Null
	$psi.EnvironmentVariables['APPDATA'] = $appData
	$psi.EnvironmentVariables['LOCALAPPDATA'] = $localAppData
	$psi.EnvironmentVariables['TEMP'] = $tempData
	$psi.EnvironmentVariables['TMP'] = $tempData
	$environment = @{
		R12CXR_MODE='campaign'; R12CXR_PHASE='r3'; R12CXR_ATTEMPT_ID=$AttemptId; R12CXR_SOURCE_SHA=$SourceSha
		R12CXR_ARTIFACT_DIR=$EvidenceRoot; R12CXR_FIXTURE_PATH=$Stage0Path; R12CXR_RESIDUAL_FIXTURE_PATH=$ResidualPath
		R12CXR_EXPECTED_CAMPAIGN_SHA256=$CampaignSha256; R12CXR_EXPECTED_REALIZER_SHA256=$RealizerSha256
		R12CXR_EXPECTED_C6_CAMPAIGN_SHA256=$C6CampaignSha256; R12CXR_EXPECTED_C6_REALIZER_SHA256=$C6RealizerSha256
		R12CXR_EXPECTED_RESIDUAL_FIXTURE_SHA256=$ResidualSha256
	}
	foreach ($key in $environment.Keys) { $psi.EnvironmentVariables[$key] = [string]$environment[$key] }
}

$process = [Diagnostics.Process]::new()
$process.StartInfo = $psi
$startIntentRecord = [ordered]@{
	attempt_id=$AttemptId; executable=$program; argv=$argVector; scenario_id=$scenarioId; phase=$phase
	status='PROCESS_START_CALL_IMMINENT'; created_utc=[DateTime]::UtcNow.ToString('o')
	source_sha=$SourceSha; execution_checkout_head=$ExecutionCheckoutHead
}
Write-NewJson (Join-Path $EvidenceRoot 'process-start-intent.json') $startIntentRecord
$startUtc = [DateTime]::UtcNow.ToString('o')
if (-not $process.Start()) { throw 'Process.Start returned false; no scenario process created.' }
$engineProcessId = $process.Id
$postStartTelemetryError = ''
$osProcess = $null
try { $osProcess = Get-CimInstance Win32_Process -Filter "ProcessId = $engineProcessId" -ErrorAction SilentlyContinue } catch { $postStartTelemetryError = $_.Exception.Message }
$parentPidValue = 'UNKNOWN_NOT_CAPTURED'
$osCommandLineValue = 'UNKNOWN_NOT_CAPTURED'
$creationValue = 'UNKNOWN_NOT_CAPTURED'
if ($osProcess) {
	$parentPidValue = [int]$osProcess.ParentProcessId
	$osCommandLineValue = [string]$osProcess.CommandLine
	$creationValue = [string]$osProcess.CreationDate
}
$startRecord = [ordered]@{
	attempt_id=$AttemptId; executable=$program; argv=$argVector; pid=$engineProcessId
	parent_pid=$parentPidValue; os_command_line=$osCommandLineValue; creation_date=$creationValue
	process_start_utc=$startUtc; source_sha=$SourceSha; execution_checkout_head=$ExecutionCheckoutHead
	scenario_id=$scenarioId; phase=$phase; free_commit_bytes=$freeCommitBytes; appdata=$appData; status='PROCESS_STARTED'
	post_start_telemetry_error=$postStartTelemetryError
}
$startWriteError = ''
try { Write-NewJson (Join-Path $EvidenceRoot 'process-started.json') $startRecord } catch { $startWriteError = $_.Exception.Message }
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$timeoutMs = if ($RunFrozenTarget) { 45000 } else { 10000 }
$hasExited = $process.WaitForExit($timeoutMs)
$timedOut = -not $hasExited
if ($timedOut) {
	try { $process.Kill(); $process.WaitForExit() } catch {}
}
$stdoutText = $stdoutTask.GetAwaiter().GetResult()
$stderrText = $stderrTask.GetAwaiter().GetResult()
$stdoutPath = Join-Path $EvidenceRoot 'stdout.txt'
$stderrPath = Join-Path $EvidenceRoot 'stderr.txt'
$outputWriteFailure = ''
try { Write-NewDurable $stdoutPath ([Text.UTF8Encoding]::new($false).GetBytes($stdoutText)) } catch { $outputWriteFailure = $_.Exception.Message }
try { Write-NewDurable $stderrPath ([Text.UTF8Encoding]::new($false).GetBytes($stderrText)) } catch { if ($outputWriteFailure) { $outputWriteFailure += '; ' }; $outputWriteFailure += $_.Exception.Message }
$exitCode = if ($process.HasExited) { $process.ExitCode } else { 'UNKNOWN_NOT_CAPTURED' }
$stdoutHash = if (Test-Path -LiteralPath $stdoutPath) { Get-Sha256 $stdoutPath } else { 'UNKNOWN_NOT_CAPTURED' }
$stderrHash = if (Test-Path -LiteralPath $stderrPath) { Get-Sha256 $stderrPath } else { 'UNKNOWN_NOT_CAPTURED' }
$completion = [ordered]@{
	attempt_id=$AttemptId; pid=$engineProcessId; end_utc=[DateTime]::UtcNow.ToString('o')
	timeout_seconds=$timeoutMs / 1000; timed_out=$timedOut; exit_code=$exitCode
	status=if ($timedOut) {'BLOCKED_TIMEOUT'} else {'PROCESS_EXITED'}
	stdout_sha256=$stdoutHash; stderr_sha256=$stderrHash
	scenario_started=$stdoutText.Contains('R12CXR_TARGET_INVOCATION_BEGIN')
	process_start_record_error=$startWriteError; raw_output_write_error=$outputWriteFailure; post_start_telemetry_error=$postStartTelemetryError
}
Write-NewJson (Join-Path $EvidenceRoot 'process-completion.json') $completion
if ($ControlOnly) {
	$reservationDenied = $false
	try { $null = [IO.File]::Open($reservation, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) } catch [IO.IOException] { $reservationDenied = $true }
	$overwriteDenied = $false
	try { Write-NewDurable $stdoutPath ([Text.Encoding]::UTF8.GetBytes('overwrite')) } catch [IO.IOException] { $overwriteDenied = $true }
	Write-NewJson (Join-Path $EvidenceRoot 'control-validation.json') ([ordered]@{expected_exit=23; observed_exit=$exitCode; stdout_exact=$stdoutText.Trim() -eq 'R3_CONTROL_STDOUT'; stderr_exact=$stderrText.Trim() -eq 'R3_CONTROL_STDERR'; duplicate_reservation_denied=$reservationDenied; output_overwrite_denied=$overwriteDenied; scenario_started=$completion.scenario_started; process_start_record_written=[string]::IsNullOrEmpty($startWriteError)})
	if ($exitCode -ne 23 -or $stdoutText.Trim() -ne 'R3_CONTROL_STDOUT' -or $stderrText.Trim() -ne 'R3_CONTROL_STDERR' -or -not $reservationDenied -or -not $overwriteDenied -or $startWriteError -or $outputWriteFailure) { exit 2 }
	exit 0
}
if ($timedOut -or $startWriteError -or $outputWriteFailure) { exit 3 }
exit $exitCode

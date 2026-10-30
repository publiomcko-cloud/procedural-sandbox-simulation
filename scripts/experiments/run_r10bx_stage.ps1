param(
	[Parameter(Mandatory = $true)][ValidateSet('import', 'check-campaign', 'check-solver', 'unit', 'reference-check-authority', 'reference-check-b1r', 'reference-ray-causality', 'reference-graph-contract', 'graph', 'search')][string]$Stage,
	[Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_-]{1,80}$')][string]$AttemptId,
	[Parameter(Mandatory = $true)][string]$EvidenceRoot,
	[Parameter(Mandatory = $true)][string]$PinnedDomainPath,
	[Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedDomainSha256,
	[string]$GraphDirectory = '',
	[string]$ExpectedGraphSha256 = ''
)

$ErrorActionPreference = 'Stop'

function Write-NewUtf8Text([string]$Path, [string]$Text) {
	$stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
	try { $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$expectedOrigin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$expectedBranch = 'exp/p3-1-r10-bx-conflict-indexed-feasibility'
$expectedParent = '4e032085da53c43e78fe6b7ca3af1f569ede03d8'
$expectedGodot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$expectedGodotSha = 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643'
$expectedSourceAncestor = '6f28273d0113f93678034b9e482140e73e765721'
$expectedCampaignSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_bx_campaign.gd')).Hash.ToLowerInvariant()
$expectedSolverSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_bx_conflict_solver.gd')).Hash.ToLowerInvariant()
$expectedUnitSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_bx_tests.gd')).Hash.ToLowerInvariant()
$preregPath = Join-Path $repo 'docs\reports\P3-1-R10-BX-CAMPAIGN\BX-PREREGISTRATION.md'
$expectedPreregSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $preregPath).Hash.ToLowerInvariant()
$expectedRayFixtureSha = '9780bea4b1609bbc89db45e21d8671170198ca01d1ad3e252b9f877a64eb62c7'
$rayFixtureRepoRelative = 'docs\reports\P3-1-R10-B-CAMPAIGN\fixtures\ray_reference_fixture_r2.json'
$rayFixtureSourcePath = Join-Path $repo $rayFixtureRepoRelative
$rayFixtureSourceSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $rayFixtureSourcePath).Hash.ToLowerInvariant()
$resolvedEvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)
$referenceShadowRoot = Join-Path $resolvedEvidenceRoot 'r10b-reference-lf-shadow'
$referenceFixturePath = Join-Path $referenceShadowRoot $rayFixtureRepoRelative
$attemptRoot = Join-Path $resolvedEvidenceRoot ($AttemptId + '_' + $Stage)
$profileRoot = Join-Path $attemptRoot 'profile'
$domainFullPath = (Resolve-Path -LiteralPath $PinnedDomainPath).Path
$domainFullHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $domainFullPath).Hash.ToLowerInvariant()

if ($domainFullHash -ne $ExpectedDomainSha256.ToLowerInvariant()) { throw "Frozen domain SHA-256 mismatch: $domainFullHash" }
if (-not $domainFullPath.StartsWith($resolvedEvidenceRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Pinned candidate domain must be inside this isolated evidence root.' }
if (Test-Path -LiteralPath $attemptRoot) { throw "Evidence attempt directory already exists: $attemptRoot" }
New-Item -ItemType Directory -Path $attemptRoot | Out-Null
New-Item -ItemType Directory -Path $profileRoot | Out-Null

$observedOrigin = (& git -C $repo remote get-url origin).Trim()
$branch = (& git -C $repo branch --show-current).Trim()
$sourceSha = (& git -C $repo rev-parse HEAD).Trim().ToLowerInvariant()
$treeSha = (& git -C $repo rev-parse 'HEAD^{tree}').Trim().ToLowerInvariant()
$parentSha = (& git -C $repo rev-parse 'HEAD^').Trim().ToLowerInvariant()
$trackedChanges = @(& git -C $repo diff --name-only HEAD)
$stagedChanges = @(& git -C $repo diff --cached --name-only)
$untrackedPaths = @(& git -C $repo ls-files --others --exclude-standard)
$unexpectedUntracked = @($untrackedPaths | Where-Object { -not $_.EndsWith('.gd.uid', [StringComparison]::OrdinalIgnoreCase) })
if ($observedOrigin -ne $expectedOrigin -or $branch -ne $expectedBranch -or $parentSha -ne $expectedParent -or $trackedChanges.Count -ne 0 -or $stagedChanges.Count -ne 0 -or $unexpectedUntracked.Count -ne 0) { throw "Source identity/worktree gate failed: origin=$observedOrigin branch=$branch parent=$parentSha tracked=$($trackedChanges.Count) staged=$($stagedChanges.Count) unexpected_untracked=$($unexpectedUntracked.Count)" }
$uidInventory = @()
foreach ($uidPath in $untrackedPaths) {
	$uidFullPath = Join-Path $repo $uidPath
	$uidInventory += @{ path=$uidPath; sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $uidFullPath).Hash.ToLowerInvariant(); length=(Get-Item -LiteralPath $uidFullPath).Length }
}
& git -C $repo merge-base --is-ancestor $expectedSourceAncestor HEAD
if ($LASTEXITCODE -ne 0) { throw "Pinned B1R source is not an ancestor: $expectedSourceAncestor" }
$godotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $expectedGodot).Hash.ToLowerInvariant()
if ($godotHash -ne $expectedGodotSha) { throw "Godot executable hash mismatch: $godotHash" }
if ($expectedPreregSha -ne '9ec0de228487722cb74f5ea78b33ebda5d5a0d78782edea1bad55cb4dbd4c460') { throw "Preregistration physical hash mismatch: $expectedPreregSha" }

# R10-B's frozen fixture is LF-pinned. On this Windows worktree Git autocrlf
# yields a known CRLF physical hash. Build a create-new shadow only from either
# exact observed form; never rewrite the tracked fixture or the earlier PR.
$referenceFixtureSha = ''
if ($Stage -like 'reference-*') {
	if ($rayFixtureSourceSha -notin @('8848b9181f826dc69c49fde222171c5ab1a60ea55daaba4beb4672c7b672ca7e', $expectedRayFixtureSha)) { throw "R10-B tracked fixture has an unrecognized physical hash: $rayFixtureSourceSha" }
	[IO.Directory]::CreateDirectory((Split-Path -Parent $referenceFixturePath)) | Out-Null
	if (-not (Test-Path -LiteralPath $referenceFixturePath)) {
		$sourceText = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($rayFixtureSourcePath))
		$lfText = $sourceText.Replace("`r`n", "`n")
		if ($lfText.Contains("`r")) { throw 'R10-B tracked fixture contains an unsupported lone CR.' }
		$lfBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($lfText)
		$lfStream = [IO.File]::Open($referenceFixturePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
		try { $lfStream.Write($lfBytes, 0, $lfBytes.Length); $lfStream.Flush($true) } finally { $lfStream.Dispose() }
	}
	$referenceFixtureSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $referenceFixturePath).Hash.ToLowerInvariant()
	if ($referenceFixtureSha -ne $expectedRayFixtureSha) { throw "R10-B shadow fixture SHA-256 mismatch: $referenceFixtureSha" }
}

$engineArguments = switch ($Stage) {
	'import' { @('--headless', '--path', './game', '--editor', '--import') }
	'check-campaign' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_bx_campaign.gd') }
	'check-solver' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r10_bx_conflict_solver.gd') }
	'unit' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_bx_tests.gd') }
	'reference-check-authority' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r10_a_topology_authority.gd') }
	'reference-check-b1r' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r10_b1r_direct_triangulator.gd') }
	'reference-ray-causality' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_b_ray_causality.gd') }
	'reference-graph-contract' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_b_campaign.gd') }
	'graph' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_bx_campaign.gd') }
	'search' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r10_bx_campaign.gd') }
}
$argumentLine = $engineArguments -join ' '
$runId = [guid]::NewGuid().ToString('N')
$profileData = Join-Path $profileRoot 'APPDATA'
$profileLocal = Join-Path $profileRoot 'LOCALAPPDATA'
$profileTemp = Join-Path $profileRoot 'TEMP'
New-Item -ItemType Directory -Path $profileData, $profileLocal, $profileTemp | Out-Null
$processStartInfo = [Diagnostics.ProcessStartInfo]::new()
$processStartInfo.FileName = $expectedGodot
$processStartInfo.WorkingDirectory = $repo
$processStartInfo.Arguments = $argumentLine
$processStartInfo.UseShellExecute = $false
$processStartInfo.CreateNoWindow = $true
$processStartInfo.RedirectStandardOutput = $true
$processStartInfo.RedirectStandardError = $true
$processStartInfo.EnvironmentVariables['APPDATA'] = $profileData
$processStartInfo.EnvironmentVariables['LOCALAPPDATA'] = $profileLocal
$processStartInfo.EnvironmentVariables['TEMP'] = $profileTemp
$processStartInfo.EnvironmentVariables['TMP'] = $profileTemp
$processStartInfo.EnvironmentVariables['R10BX_REPO_ROOT'] = $repo
$processStartInfo.EnvironmentVariables['R10BX_STAGE'] = if ($Stage -eq 'graph') { 'graph' } elseif ($Stage -eq 'search') { 'search' } else { 'check-only' }
$processStartInfo.EnvironmentVariables['R10BX_ARTIFACT_DIR'] = $attemptRoot
$processStartInfo.EnvironmentVariables['R10BX_GRAPH_DIR'] = if ($Stage -eq 'graph') { Join-Path $attemptRoot 'graph' } elseif ($Stage -eq 'search') { [IO.Path]::GetFullPath($GraphDirectory) } else { Join-Path $attemptRoot 'graph' }
$processStartInfo.EnvironmentVariables['R10BX_DOMAIN_PATH'] = $domainFullPath
$processStartInfo.EnvironmentVariables['R10BX_DOMAIN_SHA256'] = $ExpectedDomainSha256.ToLowerInvariant()
$processStartInfo.EnvironmentVariables['R10BX_SOURCE_SHA'] = $sourceSha
$processStartInfo.EnvironmentVariables['R10BX_CAMPAIGN_SHA256'] = $expectedCampaignSha
$processStartInfo.EnvironmentVariables['R10BX_SOLVER_SHA256'] = $expectedSolverSha
$processStartInfo.EnvironmentVariables['R10BX_PREREGISTRATION_SHA256'] = $expectedPreregSha
$processStartInfo.EnvironmentVariables['R10BX_UNIT_SHA256'] = $expectedUnitSha
$processStartInfo.EnvironmentVariables['R10BX_EXPECTED_GRAPH_SHA256'] = $ExpectedGraphSha256.ToLowerInvariant()
$processStartInfo.EnvironmentVariables['R10B_ATTEMPT'] = $AttemptId
$processStartInfo.EnvironmentVariables['R10B_HYPOTHESIS'] = 'R10BX_CONFLICT_INDEXED_EXACT_ROOT_FEASIBILITY'
$processStartInfo.EnvironmentVariables['R10B_SOURCE_SHA'] = $sourceSha
$processStartInfo.EnvironmentVariables['R10B_ARTIFACT_DIR'] = $attemptRoot
$processStartInfo.EnvironmentVariables['R10B_REPO_ROOT'] = if ($Stage -like 'reference-*') { $referenceShadowRoot } else { $repo }
$processStartInfo.EnvironmentVariables['R10B_CAMPAIGN_SOURCE_SHA256'] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_b_campaign.gd')).Hash.ToLowerInvariant()
$processStartInfo.EnvironmentVariables['R10B_REALIZER_SOURCE_SHA256'] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_b_realizer.gd')).Hash.ToLowerInvariant()
$processStartInfo.EnvironmentVariables['R10B_B1R_REALIZER_SOURCE_SHA256'] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_b1r_direct_triangulator.gd')).Hash.ToLowerInvariant()
$processStartInfo.EnvironmentVariables['R10B_RAY_SOURCE_SHA256'] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_b_ray_causality.gd')).Hash.ToLowerInvariant()
$processStartInfo.EnvironmentVariables['R10B_RAY_FIXTURE_SHA256'] = $expectedRayFixtureSha
if ($Stage -eq 'reference-graph-contract') { $processStartInfo.EnvironmentVariables['R10B_GRAPH_ONLY'] = '1' }
if ($Stage -eq 'graph') { New-Item -ItemType Directory -Path $processStartInfo.EnvironmentVariables['R10BX_GRAPH_DIR'] | Out-Null }
if ($Stage -eq 'search') {
	if ([string]::IsNullOrWhiteSpace($GraphDirectory) -or $ExpectedGraphSha256 -notmatch '^[0-9a-fA-F]{64}$' -or -not (Test-Path -LiteralPath (Join-Path $GraphDirectory 'bx_conflict_index_receipt.json'))) { throw 'Search requires the completed graph-preflight directory and exact graph SHA.' }
	$graphReceipt = Get-Content -Raw -LiteralPath (Join-Path $GraphDirectory 'bx_conflict_index_receipt.json') | ConvertFrom-Json
	if ([string]$graphReceipt.graph_sha256 -ne $ExpectedGraphSha256.ToLowerInvariant()) { throw 'Graph receipt differs from the independently pinned graph SHA.' }
	$priorResourceAborts = 0
	foreach ($priorDirectory in @(Get-ChildItem -LiteralPath $resolvedEvidenceRoot -Directory)) {
		$priorProcessPath = Join-Path $priorDirectory.FullName 'process.json'
		if (-not (Test-Path -LiteralPath $priorProcessPath)) { continue }
		try { $priorRecord = Get-Content -Raw -LiteralPath $priorProcessPath | ConvertFrom-Json } catch { continue }
		if ([string]$priorRecord.stage -eq 'search' -and [string]$priorRecord.source_sha -eq $sourceSha -and [string]$priorRecord.domain_sha256 -eq $ExpectedDomainSha256.ToLowerInvariant() -and [bool]$priorRecord.resource_abort) { $priorResourceAborts++ }
	}
	if ($priorResourceAborts -ge 2) { throw 'The preregistered maximum of two resource-safety retries has already been exhausted.' }
}

if ($Stage -eq 'search') {
	$launchReservation = [ordered]@{ schema='P3.1.R10BX.ExternalSearchLaunchReservation.v1'; run_id=$runId; attempt_id=$AttemptId; source_sha=$sourceSha; parent_sha=$parentSha; tree_sha=$treeSha; domain_sha256=$ExpectedDomainSha256.ToLowerInvariant(); graph_sha256=$ExpectedGraphSha256.ToLowerInvariant(); preregistration_sha256=$expectedPreregSha; argument_vector=$engineArguments; created_utc=[DateTime]::UtcNow.ToString('o') }
	$launchPath = Join-Path $attemptRoot 'search-launch-reservation.json'
	$launchStream = [IO.File]::Open($launchPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
	try { $launchBytes = [Text.UTF8Encoding]::new($false).GetBytes(($launchReservation | ConvertTo-Json -Depth 8)); $launchStream.Write($launchBytes, 0, $launchBytes.Length); $launchStream.Flush($true) } finally { $launchStream.Dispose() }
}

$intent = [ordered]@{
	schema='P3.1.R10BX.LaunchIntent.v1'; run_id=$runId; attempt_id=$AttemptId; stage=$Stage; hypothesis='R10BX_CONFLICT_INDEXED_EXACT_ROOT_FEASIBILITY';
	repository=$repo; origin=$observedOrigin; branch=$branch; source_sha=$sourceSha; parent_sha=$parentSha; tree_sha=$treeSha;
	godot_path=$expectedGodot; godot_sha256=$godotHash; argument_vector=$engineArguments; command_line=$argumentLine;
	domain_path=$domainFullPath; domain_sha256=$domainFullHash; graph_directory=$processStartInfo.EnvironmentVariables['R10BX_GRAPH_DIR']; graph_sha256=$ExpectedGraphSha256.ToLowerInvariant(); preregistration_sha256=$expectedPreregSha;
	profile_root=$profileRoot; artifact_root=$attemptRoot; runner_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash.ToLowerInvariant();
	tracked_changes=$trackedChanges; staged_changes=$stagedChanges; allowed_untracked_uid_inventory=$uidInventory;
	reference_fixture_source_sha256=$rayFixtureSourceSha; reference_fixture_shadow_sha256=$referenceFixtureSha; reference_fixture_shadow_path=$(if ($Stage -like 'reference-*') { $referenceFixturePath } else { $null });
	source_physical_hashes=@{ campaign=$expectedCampaignSha; solver=$expectedSolverSha; unit_tests=$expectedUnitSha; preregistration=$expectedPreregSha }; created_utc=[DateTime]::UtcNow.ToString('o')
}
$intentPath = Join-Path $attemptRoot 'launch-intent.json'
$intentStream = [IO.File]::Open($intentPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
try { $intentBytes = [Text.UTF8Encoding]::new($false).GetBytes(($intent | ConvertTo-Json -Depth 10)); $intentStream.Write($intentBytes, 0, $intentBytes.Length); $intentStream.Flush($true) } finally { $intentStream.Dispose() }

$hostBefore = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
$freeBefore = [int64]$hostBefore.CommitLimit - [int64]$hostBefore.CommittedBytes
	$timeoutSeconds = switch ($Stage) { 'graph' { 1200 } 'search' { 600 } 'import' { 300 } 'unit' { 180 } 'reference-graph-contract' { 1200 } 'reference-ray-causality' { 600 } default { 120 } }
$processRecord = [ordered]@{ schema='P3.1.R10BX.ProcessRecord.v1'; run_id=$runId; stage=$Stage; source_sha=$sourceSha; parent_sha=$parentSha; tree_sha=$treeSha; domain_sha256=$ExpectedDomainSha256.ToLowerInvariant(); graph_sha256=$ExpectedGraphSha256.ToLowerInvariant(); pid=$null; parent_pid=[Diagnostics.Process]::GetCurrentProcess().Id; started=$false; exit_code=$null; elapsed_ms=$null; timeout_seconds=$timeoutSeconds; resource_abort=$false; min_free_commit_bytes=$freeBefore; warning_samples=0; validation_status='NOT_STARTED'; launch_intent_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $intentPath).Hash.ToLowerInvariant() }
if ($freeBefore -le 2GB) {
	$processRecord.validation_status = 'PRELAUNCH_ABORT_FREE_COMMIT_AT_OR_BELOW_2GB'
	Write-NewUtf8Text (Join-Path $attemptRoot 'process.json') ($processRecord | ConvertTo-Json -Depth 10)
	exit 75
}

$childProcess = [Diagnostics.Process]::new()
$childProcess.StartInfo = $processStartInfo
$launcherProcessId = [Diagnostics.Process]::GetCurrentProcess().Id
$startedUtc = [DateTime]::UtcNow
$stdoutTask = $null
$stderrTask = $null
$resourceAbort = $false
$timeoutAbort = $false
$minFreeCommit = [int64]::MaxValue
$warningSamples = 0
try {
	if (-not $childProcess.Start()) { throw 'Process.Start returned false.' }
	$engineProcessId = $childProcess.Id
	$processRecord.pid = $engineProcessId
	$processRecord.parent_pid = $launcherProcessId
	$processRecord.started = $true
	$processRecord.start_utc = $startedUtc.ToString('o')
	$processRecord.process_name = $childProcess.ProcessName
	$processRecord.validation_status = 'RUNNING'
	$createdPath = Join-Path $attemptRoot 'process-created.json'
	$createdRecord = [ordered]@{ schema='P3.1.R10BX.ProcessCreated.v1'; run_id=$runId; stage=$Stage; pid=$engineProcessId; parent_pid=$launcherProcessId; start_utc=$startedUtc.ToString('o'); process_name=$childProcess.ProcessName; source_sha=$sourceSha; argument_vector=$engineArguments; command_line=$argumentLine }
	$createdStream = [IO.File]::Open($createdPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
	try { $createdBytes = [Text.UTF8Encoding]::new($false).GetBytes(($createdRecord | ConvertTo-Json -Depth 8)); $createdStream.Write($createdBytes, 0, $createdBytes.Length); $createdStream.Flush($true) } finally { $createdStream.Dispose() }
	$stdoutTask = $childProcess.StandardOutput.ReadToEndAsync()
	$stderrTask = $childProcess.StandardError.ReadToEndAsync()
	$monitorPath = Join-Path $attemptRoot 'resource-monitor.jsonl'
	$monitorStream = [IO.File]::Open($monitorPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
	$monitorWriter = [IO.StreamWriter]::new($monitorStream, [Text.UTF8Encoding]::new($false))
	$lastSampleUtc = [DateTime]::UtcNow
	try {
		while (-not $childProcess.HasExited) {
			$sampleUtc = [DateTime]::UtcNow
			$memory = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
			$freeCommit = [int64]$memory.CommitLimit - [int64]$memory.CommittedBytes
			if ($freeCommit -lt $minFreeCommit) { $minFreeCommit = $freeCommit }
			if ($freeCommit -le 3GB) { $warningSamples++ }
			$engineInfo = $null
			try { $engineProcess = Get-Process -Id $engineProcessId -ErrorAction Stop; $engineInfo = @{ working_set_bytes=[int64]$engineProcess.WorkingSet64; private_bytes=[int64]$engineProcess.PrivateMemorySize64 } } catch { $engineInfo = @{ unavailable=$true } }
			$monitorRow = [ordered]@{ timestamp_utc=$sampleUtc.ToString('o'); interval_ms=($sampleUtc - $lastSampleUtc).TotalMilliseconds; committed_bytes=[int64]$memory.CommittedBytes; commit_limit_bytes=[int64]$memory.CommitLimit; free_commit_bytes=$freeCommit; available_mbytes=[int64]$memory.AvailableMBytes; engine_pid=$engineProcessId; engine=$engineInfo; warning=($freeCommit -le 3GB); hard_abort=($freeCommit -le 2GB) }
			$monitorWriter.WriteLine(($monitorRow | ConvertTo-Json -Compress -Depth 6)); $monitorWriter.Flush()
			$lastSampleUtc = $sampleUtc
			if ($freeCommit -le 2GB) { $resourceAbort = $true; try { $childProcess.Kill() } catch { }; break }
			if (($sampleUtc - $startedUtc).TotalSeconds -ge $timeoutSeconds) { $timeoutAbort = $true; try { $childProcess.Kill() } catch { }; break }
			Start-Sleep -Milliseconds 350
		}
		$childProcess.WaitForExit()
	} finally { $monitorWriter.Dispose() }
	$stdout = $stdoutTask.GetAwaiter().GetResult()
	$stderr = $stderrTask.GetAwaiter().GetResult()
	$stdoutPath = Join-Path $attemptRoot 'stdout.txt'
	$stderrPath = Join-Path $attemptRoot 'stderr.txt'
	Write-NewUtf8Text $stdoutPath $stdout
	Write-NewUtf8Text $stderrPath $stderr
	$processRecord.exit_code = if ($resourceAbort -or $timeoutAbort) { $null } else { $childProcess.ExitCode }
	$processRecord.elapsed_ms = ([DateTime]::UtcNow - $startedUtc).TotalMilliseconds
	$processRecord.resource_abort = $resourceAbort
	$processRecord.timeout_abort = $timeoutAbort
	$processRecord.min_free_commit_bytes = $minFreeCommit
	$processRecord.warning_samples = $warningSamples
	$processRecord.stdout_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $stdoutPath).Hash.ToLowerInvariant()
	$processRecord.stderr_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $stderrPath).Hash.ToLowerInvariant()
	$processRecord.monitor_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $monitorPath).Hash.ToLowerInvariant()
	$scriptErrorDetected = ($stdout + "`n" + $stderr) -match '(?m)^(SCRIPT ERROR:|ERROR:|Parse Error:|Compile Error:)'
	$processRecord.script_error_detected = $scriptErrorDetected
	$processRecord.marker_summary = @{}
	if ($Stage -eq 'import') { $processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0) { 'PASS' } else { 'IMPORT_FAILED' } }
	elseif ($Stage -eq 'check-campaign') { $processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0 -and ([regex]::Matches($stdout, '(?m)^R10BX_CHECK_COMPLETE ')).Count -eq 1) { 'PASS' } else { 'CHECK_FAILED' } }
	elseif ($Stage -eq 'check-solver') { $processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0) { 'PASS' } else { 'CHECK_FAILED' } }
	elseif ($Stage -in @('reference-check-authority', 'reference-check-b1r')) { $processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0) { 'PASS' } else { 'REFERENCE_CHECK_FAILED' } }
	elseif ($Stage -eq 'reference-ray-causality') {
		$rayMatches = [regex]::Matches($stdout, '(?m)^R10B_RAY_DIAGNOSTIC_COMPLETE (.+)$')
		$blockedMatches = [regex]::Matches($stdout, '(?m)^R10B_RAY_BLOCKED ')
		if ($rayMatches.Count -eq 1) { $processRecord.marker_summary = $rayMatches[0].Groups[1].Value | ConvertFrom-Json }
		$processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0 -and $rayMatches.Count -eq 1 -and $blockedMatches.Count -eq 0 -and $processRecord.marker_summary.status -eq 'PASS' -and [int]$processRecord.marker_summary.D0_roi_scoped -eq 0 -and [int]$processRecord.marker_summary.D3_roi_scoped -eq 0) { 'PASS' } else { 'R10B_RAY_REFERENCE_FAILED' }
	}
	elseif ($Stage -eq 'reference-graph-contract') {
		$graphMatches = [regex]::Matches($stdout, '(?m)^R10B_GRAPH_CONTRACT_COMPLETE (.+)$')
		if ($graphMatches.Count -eq 1) { $processRecord.marker_summary = $graphMatches[0].Groups[1].Value | ConvertFrom-Json }
		$processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0 -and $graphMatches.Count -eq 1 -and $processRecord.marker_summary.status -eq 'PASS' -and [bool]$processRecord.marker_summary.volume_identity_preserved -and [bool]$processRecord.marker_summary.source_topology_graph_proof.valid) { 'PASS' } else { 'R10B_GRAPH_CONTRACT_FAILED' }
	}
	elseif ($Stage -eq 'unit') {
		$unitMatches = [regex]::Matches($stdout, '(?m)^R10BX_UNIT_TESTS_PASS (.+)$')
		if ($unitMatches.Count -eq 1) { $unitObject = $unitMatches[0].Groups[1].Value | ConvertFrom-Json; $processRecord.marker_summary = $unitObject }
		$processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0 -and $unitMatches.Count -eq 1 -and [int]$processRecord.marker_summary.assertions -eq 20 -and [int]$processRecord.marker_summary.failures -eq 0) { 'PASS' } else { 'UNIT_TESTS_FAILED' }
	}
	elseif ($Stage -eq 'graph') {
		$graphMatches = [regex]::Matches($stdout, '(?m)^R10BX_GRAPH_COMPLETE (.+)$')
		if ($graphMatches.Count -eq 1) {
			$graphObject = $graphMatches[0].Groups[1].Value | ConvertFrom-Json
			$summaryPath = [IO.Path]::GetFullPath([string]$graphObject.artifact)
			$summaryRoot = [IO.Path]::GetFullPath($attemptRoot).TrimEnd('\') + '\'
			if ($summaryPath.StartsWith($summaryRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $summaryPath -PathType Leaf)) {
				$summary = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json
				$processRecord.marker_summary = $graphObject
				$processRecord.graph_summary_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $summaryPath).Hash.ToLowerInvariant()
				$processRecord.graph_sha256 = [string]$summary.graph_sha256
				$processRecord.graph_artifact_hashes = @{ index=[string]$summary.graph_files.index_sha256; matrix=[string]$summary.graph_files.matrix_sha256 }
				$processRecord.graph_directory = [IO.Path]::GetFullPath([string]$processStartInfo.EnvironmentVariables['R10BX_GRAPH_DIR'])
				$processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0 -and $graphObject.status -eq 'PASS' -and $summary.status -eq 'PASS' -and $summary.search_started -eq $false -and [int]$summary.first_build.candidate_count -eq 7608 -and [string]$summary.domain_sha256 -eq $ExpectedDomainSha256.ToLowerInvariant()) { 'PASS' } else { 'GRAPH_PREFLIGHT_FAILED' }
			} else { $processRecord.validation_status = 'GRAPH_SUMMARY_OUTSIDE_ATTEMPT' }
		} else { $processRecord.validation_status = 'GRAPH_MARKER_INVALID' }
	}
	elseif ($Stage -eq 'search') {
		$startedMatches = [regex]::Matches($stdout, '(?m)^R10BX_SEARCH_STARTED ')
		$completeMatches = [regex]::Matches($stdout, '(?m)^R10BX_SEARCH_COMPLETE (.+)$')
		$processRecord.search_started_marker_count = $startedMatches.Count
		$processRecord.search_complete_marker_count = $completeMatches.Count
		if ($completeMatches.Count -eq 1) {
			$completion = $completeMatches[0].Groups[1].Value | ConvertFrom-Json
			$processRecord.marker_summary = $completion
			$resultPath = [IO.Path]::GetFullPath([string]$completion.result_artifact)
			$resultRoot = [IO.Path]::GetFullPath($attemptRoot).TrimEnd('\') + '\'
			if ($completion.status -in @('SAT', 'INFEASIBLE_COMPLETE', 'INCONCLUSIVE_LIMIT') -and $resultPath.StartsWith($resultRoot, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
				$resultObject = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
				$processRecord.search_result_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resultPath).Hash.ToLowerInvariant()
				$processRecord.search_result = $resultObject
				$identityOk = ([string]$resultObject.source_sha -eq $sourceSha) -and ([string]$resultObject.domain_sha256 -eq $ExpectedDomainSha256.ToLowerInvariant()) -and ([string]$resultObject.graph_sha256 -eq $ExpectedGraphSha256.ToLowerInvariant()) -and ([string]$resultObject.preregistration_sha256 -eq $expectedPreregSha)
				$statusMatches = [string]$resultObject.status -eq [string]$completion.status
				$processRecord.validation_status = if (-not $scriptErrorDetected -and $processRecord.exit_code -eq 0 -and $startedMatches.Count -eq 1 -and $identityOk -and $statusMatches -and [bool]$resultObject.search_started) { 'SCIENTIFIC_TERMINAL_RECORDED' } else { 'SEARCH_EVIDENCE_INVALID' }
			} else { $processRecord.validation_status = 'SEARCH_RESULT_INVALID_OR_INCONCLUSIVE_INTERNAL' }
		} else { $processRecord.validation_status = 'SEARCH_COMPLETION_MARKER_INVALID' }
	}
} catch {
	$processRecord.validation_status = if ($processRecord.started) { 'POST_START_INDETERMINATE' } else { 'PRESTART_FAILURE' }
	$processRecord.exception = $_.Exception.ToString()
	if ($processRecord.started) {
		$processRecord.pid = $engineProcessId
		try { if (-not $childProcess.HasExited) { $childProcess.Kill(); $childProcess.WaitForExit() }; if ($childProcess.HasExited) { $processRecord.observed_exit_code_after_exception = $childProcess.ExitCode } } catch { $processRecord.termination_confirmation = 'UNCONFIRMED' }
		if ($null -ne $stdoutTask) { try { $capturedStdout = $stdoutTask.GetAwaiter().GetResult(); $stdoutPath = Join-Path $attemptRoot 'stdout.txt'; if (-not (Test-Path -LiteralPath $stdoutPath)) { Write-NewUtf8Text $stdoutPath $capturedStdout } } catch { $processRecord.stdout_capture_after_exception = 'UNAVAILABLE' } }
		if ($null -ne $stderrTask) { try { $capturedStderr = $stderrTask.GetAwaiter().GetResult(); $stderrPath = Join-Path $attemptRoot 'stderr.txt'; if (-not (Test-Path -LiteralPath $stderrPath)) { Write-NewUtf8Text $stderrPath $capturedStderr } } catch { $processRecord.stderr_capture_after_exception = 'UNAVAILABLE' } }
	}
	try { $exceptionPath = Join-Path $attemptRoot 'process-exception.txt'; Write-NewUtf8Text $exceptionPath $_.Exception.ToString() } catch { }
} finally {
	$processPath = Join-Path $attemptRoot 'process.json'
	if (-not (Test-Path -LiteralPath $processPath)) { $recordStream = [IO.File]::Open($processPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read); try { $recordBytes = [Text.UTF8Encoding]::new($false).GetBytes(($processRecord | ConvertTo-Json -Depth 20)); $recordStream.Write($recordBytes, 0, $recordBytes.Length); $recordStream.Flush($true) } finally { $recordStream.Dispose() } }
}

$processRecord | ConvertTo-Json -Depth 20
if ($resourceAbort) { exit 75 }
if ($timeoutAbort) { exit 76 }
if ($processRecord.validation_status -notin @('PASS', 'SCIENTIFIC_TERMINAL_RECORDED')) { exit 2 }
exit 0

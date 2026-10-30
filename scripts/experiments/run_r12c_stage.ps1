param(
	[Parameter(Mandatory = $true)][ValidateSet('import', 'check-stage0', 'stage0')][string]$Stage,
	[Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_-]{1,80}$')][string]$AttemptId,
	[Parameter(Mandatory = $true)][string]$EvidenceRoot,
	[Parameter(Mandatory = $true)][string]$PinnedDomainPath,
	[Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ExpectedDomainSha256,
	[Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedSourceSha,
	[string]$ExpectedParentSha = ''
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$originExpected = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$branchExpected = 'exp/p3-1-r12-c-topology-geometry-realization'
$parentExpected = $ExpectedParentSha.ToLowerInvariant()
$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$godotExpected = 'c8f0a6bc45a19b33541501e57f6f7cd972ab18453743266339d495cbbe846643'
$candidateExpected = '334db9e3e9dfe3aca4a590845ba6b792629d204c0f1d6a3fc8a3898e7cbb020a'
$manifestExpected = '1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972'
$authorityExpected = 'feea8237160c90a049d9f0ab63ad7ff86f46604f9d57112278d25fda20a08216'
$domainFull = (Resolve-Path -LiteralPath $PinnedDomainPath).Path
$rootFull = [IO.Path]::GetFullPath($EvidenceRoot).TrimEnd('\') + '\'
if (-not $domainFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'Domain file must be within this evidence root.' }
$domainSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $domainFull).Hash.ToLowerInvariant()
if ($domainSha -ne $ExpectedDomainSha256.ToLowerInvariant()) { throw "Candidate-domain SHA mismatch: $domainSha" }
$sourceSha = (& git -C $repo rev-parse HEAD).Trim().ToLowerInvariant()
$parentSha = (& git -C $repo rev-parse 'HEAD^').Trim().ToLowerInvariant()
$treeSha = (& git -C $repo rev-parse 'HEAD^{tree}').Trim().ToLowerInvariant()
$branch = (& git -C $repo branch --show-current).Trim()
$origin = (& git -C $repo remote get-url origin).Trim()
$tracked = @(& git -C $repo diff --name-only HEAD)
$staged = @(& git -C $repo diff --cached --name-only)
$untracked = @(& git -C $repo ls-files --others --exclude-standard)
$unexpected = @($untracked | Where-Object { -not $_.EndsWith('.gd.uid', [StringComparison]::OrdinalIgnoreCase) -and -not $_.StartsWith('game\.godot\', [StringComparison]::OrdinalIgnoreCase) })
if ($origin -ne $originExpected -or $branch -ne $branchExpected -or $sourceSha -ne $ExpectedSourceSha.ToLowerInvariant() -or ($parentExpected -and $parentSha -ne $parentExpected) -or $tracked.Count -ne 0 -or $staged.Count -ne 0 -or $unexpected.Count -ne 0) {
	throw "Source gate failed: origin=$origin branch=$branch source=$sourceSha parent=$parentSha tracked=$($tracked.Count) staged=$($staged.Count) unexpected_untracked=$($unexpected.Count)"
}
& git -C $repo merge-base --is-ancestor 6f28273d0113f93678034b9e482140e73e765721 HEAD
if ($LASTEXITCODE -ne 0) { throw 'R10-B1R measured source is not an ancestor.' }
$godotSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $godot).Hash.ToLowerInvariant()
$candidateSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r9_2_candidate_impl.gd')).Hash.ToLowerInvariant()
$manifestSha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r9_2_e2e_inputs.jsonl')).Hash.ToLowerInvariant()
$authoritySha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r10_a_topology_authority.gd')).Hash.ToLowerInvariant()
$stage0Sha = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repo 'game\tests\prototypes\p3_1_r12_c_stage0_fixture.gd')).Hash.ToLowerInvariant()
if ($godotSha -ne $godotExpected -or $candidateSha -ne $candidateExpected -or $manifestSha -ne $manifestExpected -or $authoritySha -ne $authorityExpected) { throw "Pinned input mismatch: godot=$godotSha candidate=$candidateSha manifest=$manifestSha authority=$authoritySha" }
$attemptRoot = Join-Path $EvidenceRoot ($AttemptId + '_' + $Stage)
if (Test-Path -LiteralPath $attemptRoot) { throw "Attempt evidence path already exists: $attemptRoot" }
[IO.Directory]::CreateDirectory($attemptRoot) | Out-Null
$profileRoot = Join-Path $EvidenceRoot 'profile'
$profileAppData = Join-Path $profileRoot 'APPDATA'
$profileLocal = Join-Path $profileRoot 'LOCALAPPDATA'
$profileTemp = Join-Path $profileRoot 'TEMP'
[IO.Directory]::CreateDirectory($profileAppData) | Out-Null
[IO.Directory]::CreateDirectory($profileLocal) | Out-Null
[IO.Directory]::CreateDirectory($profileTemp) | Out-Null
$argv = switch ($Stage) {
	'import' { @('--headless', '--path', './game', '--editor', '--import') }
	'check-stage0' { @('--headless', '--path', './game', '--check-only', '--script', 'res://tests/prototypes/p3_1_r12_c_stage0_fixture.gd') }
	'stage0' { @('--headless', '--path', './game', '--script', 'res://tests/prototypes/p3_1_r12_c_stage0_fixture.gd') }
}
$intent = [ordered]@{
	schema='P3.1.R12C.LaunchIntent.v1'; attempt_id=$AttemptId; stage=$Stage
	origin=$origin; branch=$branch; source_sha=$sourceSha; parent_sha=$parentSha; tree_sha=$treeSha
	godot_path=$godot; godot_sha256=$godotSha; argv=$argv; evidence_root=$attemptRoot
	profile_root=$profileRoot; domain_path=$domainFull; domain_sha256=$domainSha
	source_hashes=@{stage0=$stage0Sha; candidate_d=$candidateSha; manifest=$manifestSha; r10a_authority=$authoritySha}
	created_utc=[DateTime]::UtcNow.ToString('o'); launcher_pid=$PID
}
$intentPath = Join-Path $attemptRoot 'launch-intent.json'
$intentStream = [IO.File]::Open($intentPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try { $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($intent|ConvertTo-Json -Depth 10)); $intentStream.Write($bytes,0,$bytes.Length); $intentStream.Flush($true) } finally { $intentStream.Dispose() }
$hostBefore = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
$freeBefore = [int64]$hostBefore.CommitLimit - [int64]$hostBefore.CommittedBytes
$before = [ordered]@{timestamp_utc=[DateTime]::UtcNow.ToString('o'); commit_limit=[int64]$hostBefore.CommitLimit; committed=[int64]$hostBefore.CommittedBytes; free_commit=$freeBefore}
[IO.File]::WriteAllText((Join-Path $attemptRoot 'host-before.json'),($before|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
if ($freeBefore -le 2GB) { throw "Prelaunch resource stop: free commit $freeBefore <= 2 GiB; no Godot process created." }
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $godot
$psi.WorkingDirectory = $repo
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.Arguments = $argv -join ' '
$psi.EnvironmentVariables['APPDATA']=$profileAppData
$psi.EnvironmentVariables['LOCALAPPDATA']=$profileLocal
$psi.EnvironmentVariables['TEMP']=$profileTemp
$psi.EnvironmentVariables['TMP']=$profileTemp
$psi.EnvironmentVariables['R12C_SOURCE_SHA']=$sourceSha
$psi.EnvironmentVariables['R12C_ATTEMPT_ID']=$AttemptId
$psi.EnvironmentVariables['R12C_ARTIFACT_DIR']=$EvidenceRoot
$psi.EnvironmentVariables['R12C_DOMAIN_PATH']=$domainFull
$proc = [Diagnostics.Process]::new()
$proc.StartInfo = $psi
if (-not $proc.Start()) { throw 'Godot Process.Start returned false.' }
$godotPid = $proc.Id
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()
$records = [Collections.Generic.List[object]]::new()
$warnings = [Collections.Generic.List[string]]::new()
$sw = [Diagnostics.Stopwatch]::StartNew()
$hardAbort = $false
$timedOut = $false
while (-not $proc.HasExited) {
	Start-Sleep -Milliseconds 350
	$memory = Get-CimInstance Win32_PerfRawData_PerfOS_Memory
	$free = [int64]$memory.CommitLimit - [int64]$memory.CommittedBytes
	$sample = [ordered]@{timestamp_utc=[DateTime]::UtcNow.ToString('o'); elapsed_ms=$sw.ElapsedMilliseconds; free_commit=$free; godot_pid=$godotPid; working_set_bytes=$null}
	try { $sample.working_set_bytes=[int64](Get-Process -Id $godotPid -ErrorAction Stop).WorkingSet64 } catch { $sample.process_unavailable=$true }
	$records.Add($sample)
	if ($free -le 3GB -and $warnings.Count -eq 0) { $warnings.Add("free_commit_warning:$free") }
	if ($free -le 2GB) { $hardAbort=$true; Stop-Process -Id $godotPid -Force -ErrorAction SilentlyContinue; break }
	if ($sw.Elapsed.TotalMinutes -ge 10) { $timedOut=$true; Stop-Process -Id $godotPid -Force -ErrorAction SilentlyContinue; break }
}
try { $proc.WaitForExit() } catch {}
$sw.Stop()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
$stdoutPath = Join-Path $attemptRoot 'stdout.txt'
$stderrPath = Join-Path $attemptRoot 'stderr.txt'
[IO.File]::WriteAllText($stdoutPath,$stdout,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($stderrPath,$stderr,[Text.UTF8Encoding]::new($false))
$sampleBytes=[Text.UTF8Encoding]::new($false).GetBytes(($records|ConvertTo-Json -Depth 8))
[IO.File]::WriteAllBytes((Join-Path $attemptRoot 'monitor.json'),$sampleBytes)
$markerLines=@($stdout -split '\r?\n' | Where-Object { $_ -like 'R12C_STAGE0_COMPLETE *' })
$marker=$null
if ($markerLines.Count -eq 1) { try { $marker=$markerLines[0].Substring('R12C_STAGE0_COMPLETE '.Length)|ConvertFrom-Json } catch {} }
$exitCode=$null
if ($proc.HasExited) { $exitCode=$proc.ExitCode }
$status='FAILED'
if ($hardAbort) { $status='RESOURCE_ABORT_FREE_COMMIT_2GB' }
elseif ($timedOut) { $status='TIMEOUT_INCOMPLETE' }
elseif ($Stage -eq 'stage0' -and $exitCode -eq 0 -and $null -ne $marker -and $marker.status -eq 'PASS') { $status='PASS' }
elseif ($Stage -ne 'stage0' -and $exitCode -eq 0) { $status='PASS' }
$record=[ordered]@{
	schema='P3.1.R12C.ProcessRecord.v1'; attempt_id=$AttemptId; stage=$Stage; status=$status
	source_sha=$sourceSha; parent_sha=$parentSha; tree_sha=$treeSha; godot_pid=$godotPid; launcher_pid=$PID
	exit_code=$exitCode; elapsed_ms=$sw.ElapsedMilliseconds; stdout_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $stdoutPath).Hash.ToLowerInvariant()
	stderr_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $stderrPath).Hash.ToLowerInvariant()
	marker=$marker; warnings=@($warnings); resource_abort=$hardAbort; timeout=$timedOut
}
$recordPath=Join-Path $attemptRoot 'process-record.json'
$recordStream=[IO.File]::Open($recordPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try{$recordBytes=[Text.UTF8Encoding]::new($false).GetBytes(($record|ConvertTo-Json -Depth 12));$recordStream.Write($recordBytes,0,$recordBytes.Length);$recordStream.Flush($true)}finally{$recordStream.Dispose()}
$record | ConvertTo-Json -Depth 12
if ($status -ne 'PASS') { exit 2 }

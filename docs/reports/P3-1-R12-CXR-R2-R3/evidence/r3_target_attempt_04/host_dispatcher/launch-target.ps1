$ErrorActionPreference = 'Stop'
function Write-NewJson([string]$Path,[object]$Value) {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-Json -InputObject $Value -Depth 12)+[Environment]::NewLine)
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,4096,[IO.FileOptions]::WriteThrough)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
}
function Write-NewText([string]$Path,[string]$Value) {
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Value)
    $stream=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None,[Math]::Max(4096,$bytes.Length),[IO.FileOptions]::WriteThrough)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
}
$root='C:\r12cxr-convergence-20261031\docs\reports\P3-1-R12-CXR-R2-R3\evidence\r3_target_attempt_04'
$hostDir=Join-Path $root 'host_dispatcher'
$engineDir=Join-Path $root 'engine_evidence'
$dispatcher='C:\r12cxr-convergence-20261031\docs\reports\P3-1-R12-CXR-R2-R3\evidence\r3_pretarget_04\r3_target_dispatcher.ps1'
$dispatcherSha='697f6593bf1fdce4640123248518857d480689803ec188123768feea9b5d86b9'
if((Get-FileHash -LiteralPath $dispatcher -Algorithm SHA256).Hash.ToLowerInvariant() -ne $dispatcherSha){throw 'Committed dispatcher SHA mismatch.'}
$argVector=@(
    '-RunFrozenTarget',
    '-RepoRoot','C:\r12cxr-attempt04-2964bd5',
    '-EvidenceRoot',$engineDir,
    '-GodotExe','C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    '-ExecutionCheckoutHead','2964bd55b5691081bfe4db9c421f3b982fee167b',
    '-SourceSha','2964bd55b5691081bfe4db9c421f3b982fee167b',
    '-ContractTestsSha256','04573c6e8723e328c78276aa43d62a21396d0194581e4ffb14839d39f2d4f6c6',
    '-AttemptId','R3_TARGET_20261031_04',
    '-CampaignSha256','1b3a73845ef5bafec6d16fe2a7928ee3599c5e70ba5310070cb845af3687145b',
    '-RealizerSha256','6200b9e337a39a23bb57ce9b8bcddf09b0e955365673a2b2825389e6322e6271',
    '-Stage0Path','C:\r12cxr-convergence-20261031\docs\reports\P3-1-R12-CXR-R2-R3\evidence\r2_attempt_01\r12c_stage0_topology_fixture.json',
    '-ResidualPath','C:\r12cxr-attempt04-2964bd5\game\tests\prototypes\p3_1_r12_cx_residual_fixture.json',
    '-C6CampaignSha256','9a695705c47ad6473b773bbfaeaf35d88306cee6804113a0b1a71c6faca2f348',
    '-C6RealizerSha256','31947e1944a017442ad14cc4f098e67db800d4f5e196d07e047b93dc0fe9d2ac',
    '-ResidualSha256','ad000594b25a82459da824b7488b2a553392a86e117eb64535b182463847ff23'
)
$pwsh=(Get-Process -Id $PID).Path
$psi=[Diagnostics.ProcessStartInfo]::new()
$psi.FileName=$pwsh
$psi.UseShellExecute=$false
$psi.CreateNoWindow=$true
$psi.RedirectStandardOutput=$true
$psi.RedirectStandardError=$true
$psi.WorkingDirectory='C:\r12cxr-convergence-20261031'
$psi.ArgumentList.Add('-NoLogo');$psi.ArgumentList.Add('-NoProfile');$psi.ArgumentList.Add('-File');$psi.ArgumentList.Add($dispatcher)
foreach($arg in $argVector){$psi.ArgumentList.Add([string]$arg)}
$intent=[ordered]@{attempt_id='R3_TARGET_20261031_04';status='DISPATCHER_START_CALL_IMMINENT';created_utc=[DateTime]::UtcNow.ToString('o');launcher_pid=$PID;executable=$pwsh;dispatcher=$dispatcher;dispatcher_sha256=$dispatcherSha;argv=@('-NoLogo','-NoProfile','-File',$dispatcher)+$argVector;scenario_id='R9.2.SEAM.XPLUS_EQUAL.v1';source_sha='2964bd55b5691081bfe4db9c421f3b982fee167b'}
Write-NewJson (Join-Path $hostDir 'dispatcher-launch-intent.json') $intent
$process=[Diagnostics.Process]::new();$process.StartInfo=$psi
try { if(-not $process.Start()){throw 'Dispatcher Process.Start returned false.'} } catch {
    Write-NewJson (Join-Path $hostDir 'dispatcher-start-failure.json') ([ordered]@{attempt_id='R3_TARGET_20261031_04';error=$_.Exception.Message;utc=[DateTime]::UtcNow.ToString('o');target_process_started=$false})
    throw
}
$dispatcherPid=$process.Id
$parentPid=$PID
$started=[ordered]@{attempt_id='R3_TARGET_20261031_04';dispatcher_pid=$dispatcherPid;parent_pid=$parentPid;executable=$pwsh;process_start_utc=[DateTime]::UtcNow.ToString('o');scenario_id='R9.2.SEAM.XPLUS_EQUAL.v1';source_sha='2964bd55b5691081bfe4db9c421f3b982fee167b';status='DISPATCHER_STARTED'}
Write-NewJson (Join-Path $hostDir 'dispatcher-started.json') $started
$stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$stdout=$stdoutTask.GetAwaiter().GetResult();$stderr=$stderrTask.GetAwaiter().GetResult()
Write-NewText (Join-Path $hostDir 'dispatcher-stdout.txt') $stdout
Write-NewText (Join-Path $hostDir 'dispatcher-stderr.txt') $stderr
$completion=[ordered]@{attempt_id='R3_TARGET_20261031_04';dispatcher_pid=$dispatcherPid;end_utc=[DateTime]::UtcNow.ToString('o');dispatcher_exit_code=$process.ExitCode;status=if($process.ExitCode -eq 0){'DISPATCHER_EXITED_ZERO'}else{'DISPATCHER_EXITED_NONZERO'};stdout_sha256=(Get-FileHash -LiteralPath (Join-Path $hostDir 'dispatcher-stdout.txt') -Algorithm SHA256).Hash.ToLowerInvariant();stderr_sha256=(Get-FileHash -LiteralPath (Join-Path $hostDir 'dispatcher-stderr.txt') -Algorithm SHA256).Hash.ToLowerInvariant()}
Write-NewJson (Join-Path $hostDir 'dispatcher-completion.json') $completion
exit $process.ExitCode
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
$root='C:\r12cxr-convergence-20261031\docs\reports\P3-1-R12-CXR-R2-R3\evidence\r3_target_attempt_05'
$hostDir=Join-Path $root 'host_dispatcher'
$engineDir=Join-Path $root 'engine_evidence'
if(Test-Path -LiteralPath $root){throw 'Attempt evidence path already exists; refusing reuse.'}
[IO.Directory]::CreateDirectory($root)|Out-Null
[IO.Directory]::CreateDirectory($hostDir)|Out-Null
[IO.Directory]::CreateDirectory($engineDir)|Out-Null
$dispatcher='C:\r12cxr-convergence-20261031\docs\reports\P3-1-R12-CXR-R2-R3\evidence\r3_pretarget_05\r3_target_dispatcher.ps1'
$dispatcherSha='b935c0dc34364ca85e2147968341bded9cf254404b6295319713263799243af0'
if((Get-FileHash -LiteralPath $dispatcher -Algorithm SHA256).Hash.ToLowerInvariant() -ne $dispatcherSha){throw 'Committed dispatcher SHA mismatch.'}
$argVector=@(
    '-RunFrozenTarget',
    '-RepoRoot','C:\r12cxr-attempt05-4734e6c',
    '-EvidenceRoot',$engineDir,
    '-GodotExe','C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    '-ExecutionCheckoutHead','4734e6cb0c80cde086ea86e7d8afcda983e3a24b',
    '-SourceSha','4734e6cb0c80cde086ea86e7d8afcda983e3a24b',
    '-ContractTestsSha256','25d86eb5e91a7096ad73244d0710e14379283b757c343673af637e22bcd3e8b7',
    '-AttemptId','R3_TARGET_20261031_05',
    '-CampaignSha256','1b3a73845ef5bafec6d16fe2a7928ee3599c5e70ba5310070cb845af3687145b',
    '-RealizerSha256','a96cc49aeb162381c13f972ef66ad1ece076f1244689362cc8f0a4c7d3d1f7c2',
    '-Stage0Path','C:\r12cxr-convergence-20261031\docs\reports\P3-1-R12-CXR-R2-R3\evidence\r2_attempt_01\r12c_stage0_topology_fixture.json',
    '-ResidualPath','C:\r12cxr-attempt05-4734e6c\game\tests\prototypes\p3_1_r12_cx_residual_fixture.json',
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
$intent=[ordered]@{attempt_id='R3_TARGET_20261031_05';status='DISPATCHER_START_CALL_IMMINENT';created_utc=[DateTime]::UtcNow.ToString('o');launcher_pid=$PID;executable=$pwsh;dispatcher=$dispatcher;dispatcher_sha256=$dispatcherSha;argv=@('-NoLogo','-NoProfile','-File',$dispatcher)+$argVector;scenario_id='R9.2.SEAM.XPLUS_EQUAL.v1';source_sha='4734e6cb0c80cde086ea86e7d8afcda983e3a24b'}
Write-NewJson (Join-Path $hostDir 'dispatcher-launch-intent.json') $intent
$process=[Diagnostics.Process]::new();$process.StartInfo=$psi
try { if(-not $process.Start()){throw 'Dispatcher Process.Start returned false.'} } catch {
    Write-NewJson (Join-Path $hostDir 'dispatcher-start-failure.json') ([ordered]@{attempt_id='R3_TARGET_20261031_05';error=$_.Exception.Message;utc=[DateTime]::UtcNow.ToString('o');target_process_started=$false})
    throw
}
$dispatcherPid=$process.Id
$parentPid=$PID
$started=[ordered]@{attempt_id='R3_TARGET_20261031_05';dispatcher_pid=$dispatcherPid;parent_pid=$parentPid;executable=$pwsh;process_start_utc=[DateTime]::UtcNow.ToString('o');scenario_id='R9.2.SEAM.XPLUS_EQUAL.v1';source_sha='4734e6cb0c80cde086ea86e7d8afcda983e3a24b';status='DISPATCHER_STARTED'}
Write-NewJson (Join-Path $hostDir 'dispatcher-started.json') $started
$stdoutTask=$process.StandardOutput.ReadToEndAsync();$stderrTask=$process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$stdout=$stdoutTask.GetAwaiter().GetResult();$stderr=$stderrTask.GetAwaiter().GetResult()
Write-NewText (Join-Path $hostDir 'dispatcher-stdout.txt') $stdout
Write-NewText (Join-Path $hostDir 'dispatcher-stderr.txt') $stderr
$completion=[ordered]@{attempt_id='R3_TARGET_20261031_05';dispatcher_pid=$dispatcherPid;end_utc=[DateTime]::UtcNow.ToString('o');dispatcher_exit_code=$process.ExitCode;status=if($process.ExitCode -eq 0){'DISPATCHER_EXITED_ZERO'}else{'DISPATCHER_EXITED_NONZERO'};stdout_sha256=(Get-FileHash -LiteralPath (Join-Path $hostDir 'dispatcher-stdout.txt') -Algorithm SHA256).Hash.ToLowerInvariant();stderr_sha256=(Get-FileHash -LiteralPath (Join-Path $hostDir 'dispatcher-stderr.txt') -Algorithm SHA256).Hash.ToLowerInvariant()}
Write-NewJson (Join-Path $hostDir 'dispatcher-completion.json') $completion
exit $process.ExitCode
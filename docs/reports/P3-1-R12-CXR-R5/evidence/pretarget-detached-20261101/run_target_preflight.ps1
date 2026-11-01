$ErrorActionPreference = 'Stop'
$repoRoot = 'C:\r12cxr-r5-target-8e5211e-20261101'
$godot = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe'
$expectedSource = '8e5211e0665b6f57839d5c7eeae51c28c64325f6'
$evidenceRoot = 'C:\Users\PUBLI\AppData\Local\Temp\r12cxr_r5_20261101_a1\exact-target-preflight-a'
$runRoot = Join-Path $evidenceRoot 'run'
$logs = Join-Path $runRoot 'logs'
$profile = Join-Path $runRoot 'profile'
if (Test-Path -LiteralPath $runRoot) { throw 'Postcommit preflight R8 directory already exists; refusing overwrite.' }
New-Item -ItemType Directory -Path $logs,(Join-Path $profile 'Roaming'),(Join-Path $profile 'Local') -Force | Out-Null
$env:APPDATA = Join-Path $profile 'Roaming'
$env:LOCALAPPDATA = Join-Path $profile 'Local'
$source = (git -C $repoRoot rev-parse HEAD).Trim()
if ($source -ne $expectedSource) { throw "Unexpected source SHA $source" }
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $godot).Hash
if ($exeHash -ne 'C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643') { throw "Godot binary hash mismatch: $exeHash" }
$processRecords = @()
function Invoke-GodotStage([string]$name, [string[]]$arguments, [hashtable]$overrides = @{}) {
    foreach ($kv in $overrides.GetEnumerator()) { [Environment]::SetEnvironmentVariable([string]$kv.Key,[string]$kv.Value,'Process') }
    $stdout = Join-Path $logs ($name + '.stdout.log')
    $stderr = Join-Path $logs ($name + '.stderr.log')
    $recordPath = Join-Path $logs ($name + '.process.json')
    foreach ($path in @($stdout,$stderr,$recordPath)) { if (Test-Path -LiteralPath $path) { throw "Refusing overwrite: $path" } }
    $started = [DateTime]::UtcNow
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -WorkingDirectory $repoRoot -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -Wait -WindowStyle Hidden
    $ended = [DateTime]::UtcNow
    $stderrText = [IO.File]::ReadAllText($stderr)
    $record = [ordered]@{stage=$name;source_sha=$source;executable=$godot;executable_sha256=$exeHash;arguments=$arguments;environment_overrides=$overrides;pid=$process.Id;start_utc=$started.ToString('o');end_utc=$ended.ToString('o');duration_ms=[math]::Round(($ended-$started).TotalMilliseconds,3);exit_code=$process.ExitCode;stdout=$stdout;stderr=$stderr;stderr_bytes=(Get-Item $stderr).Length}
    [IO.File]::WriteAllText($recordPath,($record | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    $script:processRecords += $record
    Write-Output ("STAGE {0} EXIT={1} PID={2} DURATION_MS={3} STDERR_BYTES={4}" -f $name,$process.ExitCode,$process.Id,$record.duration_ms,$record.stderr_bytes)
    if ($process.ExitCode -ne 0) { throw "Stage failed exit code: $name" }
    if (-not [string]::IsNullOrEmpty($stderrText)) { throw "Stage produced stderr; review required: $name" }
}
try {
    Invoke-GodotStage 'version' @('--version')
    $version = [IO.File]::ReadAllText((Join-Path $logs 'version.stdout.log')).Trim()
    if ($version -ne '4.7.2.stable.official.ed1daf0bf') { throw "Godot version mismatch: $version" }
    Invoke-GodotStage 'cold-import' @('--headless','--path','./game','--editor','--import')
    Invoke-GodotStage 'realizer-check' @('--headless','--path','./game','--check-only','--script','res://tests/prototypes/p3_1_r12_cxr_field_support_realizer.gd')
    Invoke-GodotStage 'campaign-check' @('--headless','--path','./game','--check-only','--script','res://tests/prototypes/p3_1_r12_cxr_r5_campaign.gd')
    Invoke-GodotStage 'synthesizer-check' @('--headless','--path','./game','--check-only','--script','res://tests/prototypes/p3_1_r12_cxr_r5_support_synthesizer.gd')
    Invoke-GodotStage 'contract-check' @('--headless','--path','./game','--check-only','--script','res://tests/prototypes/p3_1_r12_cxr_r5_contract_tests.gd')
    Invoke-GodotStage 'r5-contract' @('--headless','--path','./game','--script','res://tests/prototypes/p3_1_r12_cxr_r5_contract_tests.gd')
    if ((Get-Content -Raw (Join-Path $logs 'r5-contract.stdout.log')) -notmatch 'R12CXR_R5_CONTRACT_TESTS_PASS assertions=348 failures=0') { throw 'R5 contract marker/count invalid.' }
    Invoke-GodotStage 'r12-contract' @('--headless','--path','./game','--script','res://tests/prototypes/p3_1_r12_cxr_contract_tests.gd')
    if ((Get-Content -Raw (Join-Path $logs 'r12-contract.stdout.log')) -notmatch 'R12CXR_CONTRACT_TESTS_PASS .*"assertions":216,"failures":0') { throw 'R12 contract marker/count invalid.' }
    $cavityOutput = Join-Path $runRoot 'frozen-cavity.json'
    Invoke-GodotStage 'freeze-cavity' @('--headless','--path','./game','--script','res://tests/prototypes/p3_1_r12_cxr_r5_campaign.gd') @{R12CXR_R5_MODE='freeze';R12CXR_R5_OUTPUT=$cavityOutput;R12CXR_SOURCE_SHA=$source}
    $cavityHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $cavityOutput).Hash.ToLowerInvariant()
    $fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot 'game/tests/prototypes/fixtures/r12_cxr_r5/frozen-cavity.json')).Hash.ToLowerInvariant()
    if ([string]::CompareOrdinal($cavityHash,$fixtureHash) -ne 0) { throw "Frozen cavity output differs: output=$cavityHash fixture=$fixtureHash" }
    $manifestHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $repoRoot 'game/tests/prototypes/p3_1_r9_2_e2e_inputs.jsonl')).Hash.ToLowerInvariant()
    $sidecar = [IO.File]::ReadAllText((Join-Path $repoRoot 'game/tests/prototypes/p3_1_r9_2_e2e_inputs.sha256'))
    if ($manifestHash -ne '1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972' -or $sidecar -ne "1610c535f98a11e26ca1890c0d99addf4316fbcaa7ec9cdb7dfaa71cf5bb3972  p3_1_r9_2_e2e_inputs.jsonl`n") { throw 'Manifest physical integrity check failed.' }
    $os=Get-CimInstance Win32_OperatingSystem
    $freeMiB=[math]::Round($os.FreePhysicalMemory/1024,1)
    if ($freeMiB -le 2048) { throw "Hard stop memory threshold reached: $freeMiB MiB" }
    $summary = [ordered]@{status='R5_POSTCOMMIT_PREFLIGHT_PASS';source_sha=$source;parent_sha=(git -C $repoRoot rev-parse HEAD^).Trim();executable_sha256=$exeHash;godot_version=$version;manifest_sha256=$manifestHash;frozen_cavity_sha256=$cavityHash;free_physical_mib_preflight=$freeMiB;process_records=$processRecords}
    [IO.File]::WriteAllText((Join-Path $runRoot 'preflight-summary.json'),($summary | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    Write-Output ('PASS SUMMARY ' + (ConvertTo-Json $summary -Depth 5 -Compress))
} catch {
    $failure = [ordered]@{status='R5_POSTCOMMIT_PREFLIGHT_BLOCKED';error=$_.Exception.Message;source_sha=$source;process_records=$processRecords}
    [IO.File]::WriteAllText((Join-Path $runRoot 'preflight-summary.json'),($failure | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
    Write-Error $_
    exit 3
}
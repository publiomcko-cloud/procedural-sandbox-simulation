param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$ProjectPath = $(Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'game'),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p4-0b-evidence' } else { Join-Path $env:TEMP 'p4-0b-evidence' })
)

$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    Write-Error "Godot executable not found: $GodotBin"
    exit 1
}

$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable(?:\.|$)') {
    Write-Error "Godot 4.7.2 stable required; found '$version'"
    exit 1
}
Write-Output "GODOT_VERSION=$version"

$isolatedRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$isolatedAppData = Join-Path $isolatedRoot ("sandbox-sim-p4-0b-appdata-" + $PID)
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null
$env:APPDATA = $isolatedAppData

$importLog = Join-Path $EvidenceDir 'p4-0b-import.log'
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$importOutput = @(
    & $GodotBin --headless --editor --path $ProjectPath --import 2>&1
)
$importExit = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
$importText = ($importOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
[System.IO.File]::WriteAllText(
    $importLog,
    $importText + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)
foreach ($line in $importOutput) {
    Write-Output $line
}
if ($importExit -ne 0 -or $importText.Contains('SCRIPT ERROR:')) {
    Write-Error "P4.0B import/parser gate failed (exit=$importExit)"
    exit 1
}

$focusedLog = Join-Path $EvidenceDir 'p4-0b-focused.log'
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$focusedOutput = @(
    & $GodotBin --headless --path $ProjectPath --script 'res://tests/p4_0b_simulation_tier_tests.gd' 2>&1
)
$focusedExit = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
$focusedText = ($focusedOutput | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
[System.IO.File]::WriteAllText(
    $focusedLog,
    $focusedText + [Environment]::NewLine,
    [System.Text.UTF8Encoding]::new($false)
)
foreach ($line in $focusedOutput) {
    Write-Output $line
}

if ($focusedExit -ne 0) {
    Write-Error "P4.0B focused qualification exit code $focusedExit"
    exit 1
}
if (-not $focusedText.Contains('P4_0B_TIER_PASS:')) {
    Write-Error 'P4.0B focused PASS marker missing'
    exit 1
}
if ($focusedText.Contains('SCRIPT ERROR:') -or $focusedText.Contains('ERROR: FAIL:')) {
    Write-Error 'P4.0B focused qualification contains unexpected script/test failure'
    exit 1
}

$p4aScript = Join-Path $PSScriptRoot 'run-p4-0a-qualification.ps1'
$p4aEvidence = if ($env:RUNNER_TEMP) {
    Join-Path $env:RUNNER_TEMP 'p4-0a-evidence'
} else {
    Join-Path $env:TEMP 'p4-0a-evidence'
}

& $p4aScript -GodotBin $GodotBin -ProjectPath $ProjectPath -EvidenceDir $p4aEvidence
if ($LASTEXITCODE -ne 0) {
    Write-Error "P4.0A regression envelope failed with exit code $LASTEXITCODE"
    exit 1
}

Write-Output 'SELF_HOSTED_P4_0B_QUALIFICATION_PASS: tier framework + P4.0A regression envelope'
exit 0

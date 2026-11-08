param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$ProjectPath = $(Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'game'),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p4-0g-evidence' } else { Join-Path $env:TEMP 'p4-0g-evidence' })
)
$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Missing pinned Godot: $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Invalid Godot version: $version" }
$isolatedAppData = Join-Path $EvidenceDir 'isolated-appdata'
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null
$env:APPDATA = $isolatedAppData

function Invoke-Qualification([string]$Label, [string[]]$CommandArgs, [string]$ExpectedMarker) {
    $ErrorActionPreference = 'Continue'
    $output = @(& $GodotBin @CommandArgs 2>&1)
    $code = $LASTEXITCODE
    $value = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    [System.IO.File]::WriteAllText((Join-Path $EvidenceDir "$Label.log"), $value + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Output $value
    if ($code -ne 0 -or $value.Contains('SCRIPT ERROR:') -or $value.Contains('ERROR: FAIL:')) {
        throw "P4.0G $Label failed with exit=$code"
    }
    if ($ExpectedMarker -and -not $value.Contains($ExpectedMarker)) {
        throw "P4.0G $Label PASS marker absent: $ExpectedMarker"
    }
}

Invoke-Qualification 'import' @('--headless', '--editor', '--path', $ProjectPath, '--import') ''
Invoke-Qualification 'focused' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/p4_0g_deterministic_replay_persistence_tests.gd') 'P4_0G_REPLAY_PASS:'
& (Join-Path $PSScriptRoot 'run-p4-0f-qualification.ps1') -GodotBin $GodotBin -ProjectPath $ProjectPath
if ($LASTEXITCODE -ne 0) { throw "P4.0F cumulative qualification failed: $LASTEXITCODE" }
Write-Output 'SELF_HOSTED_P4_0G_QUALIFICATION_PASS'
exit 0

param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$ProjectPath = $(Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'game'),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-0e-evidence' } else { Join-Path $env:TEMP 'p5-0e-evidence' })
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
    $log = Join-Path $EvidenceDir "$Label.log"
    [System.IO.File]::WriteAllText($log, $value + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Output $value
    if ($code -ne 0 -or $value.Contains('SCRIPT ERROR:') -or $value.Contains('ERROR: FAIL:')) {
        throw "P5.0E $Label failed with exit=$code"
    }
    if ($ExpectedMarker -and -not $value.Contains($ExpectedMarker)) {
        throw "P5.0E $Label PASS marker absent: $ExpectedMarker"
    }
}

Invoke-Qualification 'import' @('--headless', '--editor', '--path', $ProjectPath, '--import') '' | Out-Null
Invoke-Qualification 'focused' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/p5_0e_cross_region_hydrology_tests.gd') 'P5_0E_CROSS_REGION_HYDROLOGY_PASS:' | Out-Host

& (Join-Path $PSScriptRoot 'run-p5-0d-qualification.ps1') -GodotBin $GodotBin -ProjectPath $ProjectPath
if ($LASTEXITCODE -ne 0) { throw "Inherited P5.0D qualification failed: $LASTEXITCODE" }

Write-Output 'SELF_HOSTED_P5_0E_QUALIFICATION_PASS'
exit 0

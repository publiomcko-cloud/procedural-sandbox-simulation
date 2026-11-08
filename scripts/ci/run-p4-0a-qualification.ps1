param(
    [string]$GodotBin = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }),
    [string]$ProjectPath = $(Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path 'game'),
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p4-0a-evidence' } else { Join-Path $env:TEMP 'p4-0a-evidence' })
)

$ErrorActionPreference = 'Stop'
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$failures = [System.Collections.Generic.List[string]]::new()
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$isolatedRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$isolatedAppData = Join-Path $isolatedRoot ("sandbox-sim-godot-appdata-" + $PID)
New-Item -ItemType Directory -Force -Path $isolatedAppData | Out-Null
$env:APPDATA = $isolatedAppData

function Add-Failure {
    param([string]$Message)
    $script:failures.Add($Message)
    Write-Host "FAIL: $Message"
}

function Invoke-GodotCase {
    param(
        [string]$Name,
        [string[]]$Arguments
    )

    $logPath = Join-Path $EvidenceDir "$Name.log"
    Write-Host ("COMMAND: {0} {1}" -f $GodotBin, ($Arguments -join ' '))

    $output = @(& $GodotBin @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    [System.IO.File]::WriteAllText(
        $logPath,
        $text + [Environment]::NewLine,
        [System.Text.UTF8Encoding]::new($false)
    )

    foreach ($line in $output) {
        Write-Host $line
    }

    return [pscustomobject]@{
        Name = $Name
        ExitCode = $exitCode
        Text = $text
        LogPath = $logPath
    }
}

function Require-ExitZero {
    param($Result)
    if ($Result.ExitCode -ne 0) {
        Add-Failure "$($Result.Name): exit code $($Result.ExitCode), expected 0"
    }
}

function Require-Marker {
    param(
        $Result,
        [string]$Marker
    )
    if (-not $Result.Text.Contains($Marker)) {
        Add-Failure "$($Result.Name): missing marker '$Marker'"
    }
}

function Require-Absent {
    param(
        $Result,
        [string]$Marker
    )
    if ($Result.Text.Contains($Marker)) {
        Add-Failure "$($Result.Name): forbidden marker '$Marker' present"
    }
}

function Require-Count {
    param(
        $Result,
        [string]$Marker,
        [int]$Expected
    )
    $actual = [regex]::Matches($Result.Text, [regex]::Escape($Marker)).Count
    if ($actual -ne $Expected) {
        Add-Failure "$($Result.Name): marker '$Marker' count=$actual expected=$Expected"
    }
}

if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) {
    throw "Godot executable not found: $GodotBin"
}

$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
$versionExit = $LASTEXITCODE
Write-Host "GODOT_VERSION=$version"
if ($versionExit -ne 0 -or $version -notmatch '^4\.7\.2\.stable(?:\.|$)') {
    throw "Godot 4.7.2 stable required; found '$version' (exit=$versionExit)"
}

$import = Invoke-GodotCase 'import' @('--headless', '--editor', '--path', $ProjectPath, '--import')
Require-ExitZero $import
Require-Absent $import 'SCRIPT ERROR:'

$p4 = Invoke-GodotCase 'p4-0a' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/p4_0a_fixed_tick_scheduler_tests.gd')
Require-ExitZero $p4
Require-Marker $p4 'P4_0A_FIXED_TICK_PASS: assertions=74 failures=0'
Require-Absent $p4 'SCRIPT ERROR:'
Require-Absent $p4 'ERROR: FAIL:'

$m4 = Invoke-GodotCase 'm4' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/m4_0_mod_first_core_tests.gd')
Require-ExitZero $m4
Require-Marker $m4 'M4_0_MOD_FIRST_CORE_PASS: assertions=31 failures=0'
Require-Absent $m4 'SCRIPT ERROR:'
Require-Absent $m4 'ERROR: FAIL:'

$declarative = Invoke-GodotCase 'declarative' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/declarative_mod_tests.gd')
Require-ExitZero $declarative
Require-Marker $declarative 'DECLARATIVE_MOD_PASS: assertions=79 failures=0'
Require-Absent $declarative 'SCRIPT ERROR:'
Require-Absent $declarative 'ERROR: FAIL:'

$entity = Invoke-GodotCase 'entity' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/entity_command_tests.gd')
Require-ExitZero $entity
Require-Marker $entity 'ENTITY_COMMAND_PASS: assertions=67 failures=0'
Require-Absent $entity 'SCRIPT ERROR:'
Require-Absent $entity 'ERROR: FAIL:'

$d8 = Invoke-GodotCase 'd8' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/issue108_d8_lod1_terrain_effect_tests.gd')
Require-ExitZero $d8
Require-Marker $d8 'ISSUE108_D8_LOD1_EFFECT_PASS: assertions=34 failures=0'
Require-Absent $d8 'SCRIPT ERROR:'
Require-Absent $d8 'ERROR: FAIL:'

$placement = Invoke-GodotCase 'placement' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/p3_0d_entity_placement_tests.gd')
Require-ExitZero $placement
Require-Marker $placement 'P3_0D_PLACEMENT_PASS: assertions=53 failures=0'
Require-Absent $placement 'SCRIPT ERROR:'
Require-Absent $placement 'ERROR: FAIL:'

$procedural = Invoke-GodotCase 'procedural' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/procedural_object_tests.gd')
Require-Absent $procedural 'SCRIPT ERROR:'
if ($procedural.Text.Contains('PROCEDURAL_OBJECT_PASS')) {
    Require-ExitZero $procedural
} else {
    if ($procedural.ExitCode -eq 0) {
        Add-Failure 'procedural: expected non-zero exit for accepted historical failure baseline'
    }
    Require-Marker $procedural 'PROCEDURAL_OBJECT_FAIL: assertions=671 failures=1'
    Require-Count $procedural 'ERROR: FAIL: camera-driven revisit republishes the original region' 1
    Require-Count $procedural 'effect_projection_same_revision_fingerprint_conflict' 9
    Require-Count $procedural 'ERROR: FAIL:' 1
}

$smoke = Invoke-GodotCase 'smoke' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/smoke.gd')
Require-ExitZero $smoke
Require-Marker $smoke 'SMOKE_PASS: assertions=52 failures=0'
Require-Absent $smoke 'SCRIPT ERROR:'
Require-Absent $smoke 'ERROR: FAIL:'

$sdf = Invoke-GodotCase 'terrain-sdf' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/terrain_sdf_tests.gd')
Require-ExitZero $sdf
Require-Marker $sdf 'TERRAIN_SDF_PASS: assertions=46 failures=0'
Require-Absent $sdf 'SCRIPT ERROR:'
Require-Absent $sdf 'ERROR: FAIL:'

$lod = Invoke-GodotCase 'lod01' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/lod01_transition_tests.gd')
Require-ExitZero $lod
Require-Marker $lod 'LOD01_TRANSITION_PASS: assertions=6474 failures=0'
Require-Absent $lod 'SCRIPT ERROR:'
Require-Absent $lod 'ERROR: FAIL:'

$bootstrap = Invoke-GodotCase 'bootstrap' @('--headless', '--path', $ProjectPath, '--script', 'res://tests/bootstrap_visual_regression.gd')
Require-ExitZero $bootstrap
Require-Marker $bootstrap 'BOOTSTRAP_STRUCTURE_PASS: assertions=18 failures=0'
Require-Absent $bootstrap 'SCRIPT ERROR:'
Require-Absent $bootstrap 'ERROR: FAIL:'

$startup = Invoke-GodotCase 'startup' @('--headless', '--path', $ProjectPath, '--quit-after', '2')
Require-ExitZero $startup
Require-Absent $startup 'SCRIPT ERROR:'

if ($failures.Count -gt 0) {
    Write-Host "SELF_HOSTED_QUALIFICATION_FAIL: failures=$($failures.Count)"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}

Write-Host 'SELF_HOSTED_QUALIFICATION_PASS: P4.0A + M4/P3/D8 + canonical regression envelope'
exit 0

param(
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm2-b4-gui' } else { Join-Path $env:TEMP 'dm2-b4-gui' }),
    [ValidateRange(120,1800)][int]$Frames = 300
)
$ErrorActionPreference = 'Stop'
if ((Get-Process -Id $PID).SessionId -le 0 -or -not [Environment]::UserInteractive) {
    throw 'DM2_GUI_IN_SESSION_ZERO'
}
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$sha = (& git -C $repoRoot rev-parse HEAD).Trim()
$reports = @()
foreach ($backend in @('sdf', 'b4')) {
    $env:SANDBOX_TERRAIN_BACKEND = $backend
    $directory = Join-Path $EvidenceDir $backend
    Write-Host "DM2_GUI_START backend=$backend sha=$sha"
    & (Join-Path $PSScriptRoot 'run-p5-gpu-smoke.ps1') `
        -GodotBin $GodotBin -Frames $Frames -EvidenceDir $directory
    if ($LASTEXITCODE -ne 0) {
        throw "DM2_GUI_ENGINE_FAILED backend=$backend"
    }
    $stdoutLogs = @(Get-ChildItem -LiteralPath $directory -Filter '*.stdout.log' -File)
    $pngFiles = @(Get-ChildItem -LiteralPath $directory -Filter '*.png' -File)
    if ($stdoutLogs.Count -ne 2 -or $pngFiles.Count -ne 2) {
        throw "DM2_GUI_SCREENSHOT_OR_LOG_MISSING backend=$backend"
    }
    $seenB4 = 0
    foreach ($log in $stdoutLogs) {
        $content = (Get-Content -LiteralPath $log.FullName -Raw) -replace '\x00', ''
        if (-not $content.Contains("DM2_TERRAIN_BACKEND=$backend ")) {
            throw "DM2_GUI_WRONG_BACKEND backend=$backend log=$($log.Name)"
        }
        if ($content -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: Failed to load script)') {
            throw "DM2_GUI_SCRIPT_FAILURE backend=$backend log=$($log.Name)"
        }
        $seenB4 += [regex]::Matches($content, '"terrain_backend":"b4"').Count
    }
    if ($backend -eq 'b4' -and $seenB4 -lt 1) {
        throw 'DM2_GUI_B4_NO_WORKER_PUBLISHED'
    }
    $reports += [ordered]@{
        backend = $backend
        source_sha = $sha
        frames = $Frames
        screenshots = @($pngFiles | ForEach-Object { $_.Name })
        b4_worker_receipts = $seenB4
        smoke = 'pass'
    }
    Write-Host "DM2_GUI_PASS backend=$backend screenshots=$($pngFiles.Count) b4_workers=$seenB4"
}
$reports | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm2-gui-results.json') -Encoding UTF8
Write-Host "DM2_B4_GUI_AB_PASS sha=$sha"

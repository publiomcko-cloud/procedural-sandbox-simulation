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
    # Idle baseline profile disables the coarse preview and lets definitive
    # terrain chunks settle before capturing a genuinely comparable surface.
    $idleDir = Join-Path $directory 'settled-idle'
    & (Join-Path $PSScriptRoot 'run-p5-gpu-smoke.ps1') `
        -GodotBin $GodotBin -Frames 900 -EvidenceDir $idleDir `
        -Routes @('idle') -StreamProfile 'baseline'
    $idleLogPath = Join-Path $idleDir 'gpu-idle.stdout.log'
    $idlePngPath = Join-Path $idleDir 'gpu-idle.png'
    if (-not (Test-Path -LiteralPath $idleLogPath) -or
        -not (Test-Path -LiteralPath $idlePngPath)) {
        throw "DM2_GUI_IDLE_OUTPUT_MISSING backend=$backend"
    }
    $idleLines = Get-Content -LiteralPath $idleLogPath
    $completeLine = @($idleLines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
    if ($completeLine.Count -ne 1) {
        throw "DM2_GUI_IDLE_COMPLETE_MISSING backend=$backend"
    }
    $receipt = ($completeLine[0].Substring($completeLine[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 'P5_STREAM_BENCH_COMPLETE: '.Length) | ConvertFrom-Json)
    if ([int]$receipt.active_regions -lt 1 -or [int]$receipt.frames -ne 900) {
        throw "DM2_GUI_IDLE_NOT_PUBLISHED backend=$backend active_regions=$($receipt.active_regions)"
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
        settled_idle_screenshot = 'settled-idle/gpu-idle.png'
        settled_active_regions = [int]$receipt.active_regions
        settled_idle_png_sha256 = (Get-FileHash -LiteralPath $idlePngPath -Algorithm SHA256).Hash
        smoke = 'pass'
    }
    Write-Host "DM2_GUI_PASS backend=$backend screenshots=$($pngFiles.Count)+1 settled_regions=$($receipt.active_regions) b4_workers=$seenB4"
}
$reports | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'dm2-gui-results.json') -Encoding UTF8
if ($reports[0].settled_idle_png_sha256 -eq $reports[1].settled_idle_png_sha256) {
    Write-Warning 'DM2_GUI_IDLE_IMAGES_IDENTICAL: manual image review still required'
} else {
    Write-Host 'DM2_GUI_IDLE_IMAGES_DIFFER: definitive terrain candidate visible in screenshots'
}
Write-Host "DM2_B4_GUI_AB_PASS sha=$sha"

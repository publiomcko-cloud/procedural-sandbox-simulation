param(
    [ValidateRange(120, 1800)] [int]$Frames = 360,
    [ValidateSet('idle','straight-18','straight-54','outback-18','outback-54')]
    [string[]]$Routes = @('straight-18','straight-54'),
    [ValidateSet('baseline','adaptive','adaptive-skip','adaptive-skip-lookahead','adaptive-skip-coarse','adaptive-skip-progressive')]
    [string]$StreamProfile = 'adaptive-skip-coarse',
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-gpu-smoke' } else { Join-Path $env:TEMP 'p5-gpu-smoke' })
)
$ErrorActionPreference = 'Stop'
if ((Get-Process -Id $PID).SessionId -le 0 -or -not [Environment]::UserInteractive) {
    throw 'P5_GUI_IN_SESSION_ZERO: refusing a simulated graphics benchmark.'
}
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $repoRoot 'game'
if (-not (Test-Path -LiteralPath $GodotBin -PathType Leaf)) { throw "Godot executable missing: $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Unexpected Godot version: $version" }
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$commit = (& git -C $repoRoot rev-parse HEAD).Trim()
$receipts = @()
foreach ($route in $Routes) {
    $runName = "gpu-$route"
    $stdout = Join-Path $EvidenceDir "$runName.stdout.log"
    $stderr = Join-Path $EvidenceDir "$runName.stderr.log"
    $png = Join-Path $EvidenceDir "$runName.png"
    $userHome = Join-Path $EvidenceDir "isolated-profile-$route"
    New-Item -ItemType Directory -Path $userHome -Force | Out-Null
    $env:APPDATA = $userHome
    $env:SANDBOX_STREAM_BENCHMARK = '1'
    $env:SANDBOX_STREAM_PROFILE = $StreamProfile
    $env:SANDBOX_PERF_TRACE = '1'
    $env:SANDBOX_PERF_TRACE_MIN_MS = '2.0'
    $env:SANDBOX_STREAM_BENCH_SCREENSHOT = $png
    # This is a separate Windows runner workspace. The service runner's
    # editor import/class_name cache is not shared here. Without import the
    # GUI can keep running with an empty scene after GDScript parse errors.
    $importLog = Join-Path $EvidenceDir "$runName.import.log"
    $importErr = Join-Path $EvidenceDir "$runName.import.stderr.log"
    $importProc = Start-Process -FilePath $GodotBin -ArgumentList ('--headless --editor --path "' + $project + '" --import') -PassThru -NoNewWindow -RedirectStandardOutput $importLog -RedirectStandardError $importErr
    if (-not $importProc.WaitForExit(90000)) {
        $importProc.Kill()
        $importProc.WaitForExit()
        throw "P5_GPU_IMPORT_TIMEOUT: $runName"
    }
    $importProc.Refresh()
    $importErrors = (Get-Content -LiteralPath $importErr -Raw -ErrorAction SilentlyContinue)
    if (($null -ne $importProc.ExitCode -and [int]$importProc.ExitCode -ne 0) -or $importErrors -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: Failed to load script)') {
        throw "P5_GPU_IMPORT_FAILED: $runName; inspect import stdout/stderr"
    }
    $arguments = '--verbose --windowed --resolution 960x540 --rendering-method gl_compatibility --path "' + $project +
        '" -- --stream-benchmark-route=' + $route + ' --stream-benchmark-frames=' + $Frames + ' --start-water=ocean'
    Write-Host "P5_GPU_SMOKE_START: $route sha=$commit"
    $process = Start-Process -FilePath $GodotBin -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(90000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "P5_GPU_SMOKE_TIMEOUT: $runName"
    }
    $process.Refresh()
    if ($null -ne $process.ExitCode -and [int]$process.ExitCode -ne 0) {
        throw "P5_GPU_SMOKE_EXIT: $($process.ExitCode) $runName"
    }
    $output = (Get-Content -LiteralPath $stdout -Raw) -replace '\x00', ''
    $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00', ''
    if (($output + $err) -match '(?m)(SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|ERROR: Failed to load script|P5_STREAM_BENCH_CAPTURE_FAILED|P5_STREAM_BENCH_GUI_NOT_INTERACTIVE)') {
        throw "P5_GPU_SMOKE_ENGINE_ERROR: $runName; inspect stdout/stderr"
    }
    $lines = @($output -split '\r?\n')
    $profileLines = @($lines | Where-Object { $_.Contains('"event":"terrain_stream_profile"') })
    $displayLines = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_DISPLAY: ') })
    $captureLines = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_SCREENSHOT: ') })
    $completeLines = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
    if ($profileLines.Count -ne 1 -or $displayLines.Count -ne 1 -or $captureLines.Count -ne 1 -or $completeLines.Count -ne 1) {
        throw "P5_GPU_SMOKE_RECEIPTS_MISSING: $runName"
    }
    $profile = $profileLines[0].Substring($profileLines[0].IndexOf('PERF_TRACE ') + 'PERF_TRACE '.Length) | ConvertFrom-Json
    $display = $displayLines[0].Substring($displayLines[0].IndexOf('P5_STREAM_BENCH_DISPLAY: ') + 'P5_STREAM_BENCH_DISPLAY: '.Length) | ConvertFrom-Json
    $capture = $captureLines[0].Substring($captureLines[0].IndexOf('P5_STREAM_BENCH_SCREENSHOT: ') + 'P5_STREAM_BENCH_SCREENSHOT: '.Length) | ConvertFrom-Json
    $complete = $completeLines[0].Substring($completeLines[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 'P5_STREAM_BENCH_COMPLETE: '.Length) | ConvertFrom-Json
    if ($profile.profile -ne $StreamProfile -or $profile.profile_mismatch -or
        $complete.route -ne $route -or $complete.profile -ne $StreamProfile -or
        [int]$complete.seed -ne 424242 -or [int]$complete.frames -ne $Frames) {
        throw "P5_GPU_SMOKE_NONDETERMINISTIC_RECEIPT: $runName"
    }
    if ($display.display -ne 'windows' -or [int]$display.drawn_frames -lt 20 -or [int]$display.screens -lt 1) {
        throw "P5_GPU_SMOKE_NOT_RENDERED_ON_WINDOWS: $runName"
    }
    if ([string]::IsNullOrWhiteSpace([string]$display.adapter) -or $display.adapter -match '(?i)llvmpipe|basic render|software rasterizer') {
        throw "P5_GPU_SMOKE_NO_HARDWARE_ADAPTER: $runName adapter=$($display.adapter)"
    }
    $speed = if ($route -eq 'idle') { 0.0 } elseif ($route.EndsWith('54')) { 54.0 } else { 18.0 }
    $expectedMeters = $speed * $Frames / 60.0
    if ([Math]::Abs([double]$complete.distance_m - $expectedMeters) -gt 0.005) {
        throw "P5_GPU_SMOKE_ROUTE_MISMATCH: $runName"
    }
    if (-not (Test-Path -LiteralPath $png -PathType Leaf) -or (Get-Item -LiteralPath $png).Length -lt 4096) {
        throw "P5_GPU_SMOKE_PNG_MISSING_OR_EMPTY: $runName"
    }
    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::FromFile($png)
    try {
        if ($bitmap.Width -lt 320 -or $bitmap.Height -lt 240 -or
            [int]$capture.width -ne $bitmap.Width -or [int]$capture.height -ne $bitmap.Height) {
            throw "P5_GPU_SMOKE_PNG_BAD_DIMENSIONS: $runName"
        }
        $colors = New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($x in 0..11) {
            foreach ($y in 0..7) {
                $cx = [int](($bitmap.Width - 1) * $x / 11)
                $cy = [int](($bitmap.Height - 1) * $y / 7)
                [void]$colors.Add($bitmap.GetPixel($cx, $cy).ToArgb())
            }
        }
        if ($colors.Count -lt 4) {
            throw "P5_GPU_SMOKE_UNIFORM_FRAME: $runName unique_colors=$($colors.Count)"
        }
    } finally {
        $bitmap.Dispose()
    }
    $receipts += [ordered]@{
        route = $route
        sha = $commit
        godot = $version
        profile = $StreamProfile
        seed = [int]$complete.seed
        frames = [int]$complete.frames
        distance_m = [double]$complete.distance_m
        display = [string]$display.display
        adapter = [string]$display.adapter
        drawn_frames = [int]$display.drawn_frames
        image = (Split-Path $png -Leaf)
        screenshot_width = [int]$capture.width
        screenshot_height = [int]$capture.height
    }
    Write-Host "P5_GPU_SMOKE_TRIAL_PASS: $runName adapter=$($display.adapter) frames=$($display.drawn_frames)"
}
$receipts | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'gpu-smoke-summary.json') -Encoding UTF8
Write-Host 'P5_GPU_INTERACTIVE_QUALIFICATION_PASS'

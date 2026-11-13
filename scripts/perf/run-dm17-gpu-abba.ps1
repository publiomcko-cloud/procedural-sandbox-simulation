param(
    [ValidateRange(240, 1800)][int]$Frames = 720,
    [string]$GodotBin = 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'dm17-gpu-abba' } else { Join-Path $env:TEMP 'dm17-gpu-abba' })
)
$ErrorActionPreference = 'Stop'
if ((Get-Process -Id $PID).SessionId -le 0 -or -not [Environment]::UserInteractive) {
    throw 'DM17_GPU_SESSION_REQUIRED'
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'game'
if (-not (Test-Path -LiteralPath $GodotBin)) { throw "Missing Godot: $GodotBin" }
$version = (& $GodotBin --version 2>&1 | Out-String).Trim()
if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') { throw "Wrong Godot version: $version" }
$head = (& git -C $root rev-parse HEAD).Trim()
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$oldAppData = $env:APPDATA
$trials = @(
    @{name='a-control'; both=$false},
    @{name='a-both'; both=$true},
    @{name='b-both'; both=$true},
    @{name='b-control'; both=$false}
)
$records = @()
try {
    foreach ($trial in $trials) {
        $dir = Join-Path $EvidenceDir $trial.name
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $env:APPDATA = Join-Path $dir 'APPDATA'
        New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
        $env:SANDBOX_STREAM_BENCHMARK = '1'
        $env:SANDBOX_STREAM_PROFILE = 'adaptive-skip-progressive'
        $env:SANDBOX_DM16_BENCH_METRICS = '1'
        $env:SANDBOX_DM16_LIGHT_STAGES = '0'
        $env:SANDBOX_PERF_TRACE = '0'
        $env:SANDBOX_DM17_WALLCLOCK_ROUTE = '1'
        $env:SANDBOX_DM17_SPARSE_BLOCK = $(if ($trial.both) { '1' } else { '0' })
        $env:SANDBOX_DM17_SHARED_LATTICE = $(if ($trial.both) { '1' } else { '0' })
        $env:SANDBOX_DM12_FRAME_TRACE = '0'
        $env:SANDBOX_DM14_EFFECT_TRACE = '0'
        $env:SANDBOX_DM15_RELEASE_TRACE = '0'
        $env:SANDBOX_STREAM_BENCH_SCREENSHOT = Join-Path $dir 'final.png'
        $stdout = Join-Path $dir 'stdout.log'
        $stderr = Join-Path $dir 'stderr.log'
        $args = '--windowed --resolution 960x540 --rendering-method gl_compatibility --max-fps 60 --path "' + $project +
            '" -- --stream-benchmark-route=straight-18 --stream-benchmark-frames=' + $Frames + ' --start-water=ocean'
        Write-Host "DM17_GPU_START $($trial.name) sha=$head"
        $proc = Start-Process -FilePath $GodotBin -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $proc.WaitForExit(180000)) {
            $proc.Kill(); $proc.WaitForExit()
            throw "DM17_GPU_TIMEOUT $($trial.name)"
        }
        $proc.Refresh()
        if ($null -ne $proc.ExitCode -and $proc.ExitCode -ne 0) { throw "DM17_GPU_EXIT $($trial.name) $($proc.ExitCode)" }
        $out = (Get-Content -LiteralPath $stdout -Raw) -replace '\x00',''
        $err = (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue) -replace '\x00',''
        if (($out + $err) -match 'SCRIPT ERROR:|Parse Error:|ERROR: FAIL:|P5_STREAM_BENCH_GUI_NOT_INTERACTIVE') {
            throw "DM17_GPU_SCRIPT_ERROR $($trial.name)"
        }
        $lines = @($out -split '\r?\n')
        $summaryLine = @($lines | Where-Object { $_.Contains('DM16_BENCH_SUMMARY: ') })
        $completeLine = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_COMPLETE: ') })
        $displayLine = @($lines | Where-Object { $_.Contains('P5_STREAM_BENCH_DISPLAY: ') })
        if ($summaryLine.Count -ne 1 -or $completeLine.Count -ne 1 -or $displayLine.Count -ne 1) {
            throw "DM17_GPU_RECEIPTS_MISSING $($trial.name)"
        }
        $m = $summaryLine[0].Substring($summaryLine[0].IndexOf('DM16_BENCH_SUMMARY: ') + 20) | ConvertFrom-Json
        $p = $completeLine[0].Substring($completeLine[0].IndexOf('P5_STREAM_BENCH_COMPLETE: ') + 26) | ConvertFrom-Json
        $d = $displayLine[0].Substring($displayLine[0].IndexOf('P5_STREAM_BENCH_DISPLAY: ') + 25) | ConvertFrom-Json
        if (-not $m.ok -or $m.perf_trace -or [int]$m.measured_frames -ne $Frames -or
            $p.route -ne 'straight-18' -or -not $p.wallclock_route -or
            [bool]$p.dm17_sparse_block -ne [bool]$trial.both -or
            [bool]$p.dm17_shared_lattice -ne [bool]$trial.both -or
            [Math]::Abs([double]$p.distance_m - 18.0*[double]$p.wallclock_motion_seconds) -gt 0.008) {
            throw "DM17_GPU_INVARIANTS_FAILED $($trial.name)"
        }
        if ($d.display -ne 'windows' -or [int]$d.drawn_frames -lt 20 -or
            [string]::IsNullOrWhiteSpace([string]$d.adapter) -or
            $d.adapter -match '(?i)llvmpipe|basic render|software rasterizer') {
            throw "DM17_GPU_NOT_HARDWARE_RENDERING $($trial.name)"
        }
        if (-not (Test-Path -LiteralPath $env:SANDBOX_STREAM_BENCH_SCREENSHOT) -or
            (Get-Item -LiteralPath $env:SANDBOX_STREAM_BENCH_SCREENSHOT).Length -lt 4096) {
            throw "DM17_GPU_SCREENSHOT_MISSING $($trial.name)"
        }
        $record = [pscustomobject]@{
            name=$trial.name; both=[bool]$trial.both; sha=$head
            adapter=[string]$d.adapter; drawn_frames=[int]$d.drawn_frames
            distance_m=[double]$p.distance_m
            frame_p99_ms=[double]$m.frame_p99_ms
            frame_over33_pct=[double]$m.frame_over33_pct
            focus_missing_pct=[double]$m.focus_missing_pct
            high_completed=[int]$m.visual_high_completed
        }
        $records += $record
        Write-Host ('DM17_GPU_CASE=' + ($record | ConvertTo-Json -Compress))
    }
} finally {
    $env:APPDATA = $oldAppData
}
$records | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $EvidenceDir 'dm17-gpu-abba.json') -Encoding UTF8
foreach ($both in @($false,$true)) {
    $set = @($records | Where-Object { $_.both -eq $both })
    if ($set.Count -ne 2) { throw 'DM17_GPU_ABBA_PAIR_MISSING' }
    Write-Host ('DM17_GPU_GROUP=' + ([pscustomobject]@{
        both=$both
        p99_ms=[Math]::Round(($set | Measure-Object frame_p99_ms -Average).Average,3)
        frame_over33_pct=[Math]::Round(($set | Measure-Object frame_over33_pct -Average).Average,3)
        focus_missing_pct=[Math]::Round(($set | Measure-Object focus_missing_pct -Average).Average,3)
        high_completed=[Math]::Round(($set | Measure-Object high_completed -Average).Average,2)
    } | ConvertTo-Json -Compress))
}
Write-Host "DM17_GPU_ABBA_PASS sha=$head"

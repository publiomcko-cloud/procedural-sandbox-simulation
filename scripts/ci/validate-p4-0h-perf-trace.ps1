param(
    [Parameter(Mandatory=$true)][string]$LogPath
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { throw "Trace log missing: $LogPath" }

$events = @{}
Get-Content -LiteralPath $LogPath | ForEach-Object {
    if (-not $_.StartsWith('PERF_TRACE ')) { return }
    try { $record = ($_.Substring(11) | ConvertFrom-Json) } catch { return }
    $name = [string]$record.event
    if (-not $events.ContainsKey($name)) { $events[$name] = @() }
    if ($null -ne $record.duration_usec) {
        $events[$name] += [int64]$record.duration_usec
    } else {
        $events[$name] += [int64]0
    }
}

function Percentile([Int64[]]$values, [double]$fraction) {
    if ($values.Count -eq 0) { return 0 }
    $sorted = @($values | Sort-Object)
    $index = [Math]::Ceiling($sorted.Count * $fraction) - 1
    if ($index -lt 0) { $index = 0 }
    if ($index -ge $sorted.Count) { $index = $sorted.Count - 1 }
    return [int64]$sorted[$index]
}

$requirements = @(
    @{ Name='simulation_scheduler_frame'; Min=10; MaxUsec=2000 },
    @{ Name='simulation_world_scope_frame'; Min=5; MaxUsec=15000 },
    @{ Name='material_environment_batch'; Min=1; MaxUsec=15000 },
    @{ Name='terrain_window_reconcile'; Min=3; MaxUsec=30000 },
    @{ Name='effect_snapshot_prepare'; Min=1; MaxUsec=25000 }
)

$summary = [ordered]@{}
$failures = @()
foreach ($gate in $requirements) {
    $name = [string]$gate.Name
    $values = @()
    if ($events.ContainsKey($name)) { $values = @($events[$name]) }
    $nonzero = @($values | Where-Object { $_ -gt 0 })
    $entry = [ordered]@{
        count = $values.Count
        p50_usec = (Percentile $nonzero 0.50)
        p95_usec = (Percentile $nonzero 0.95)
        p99_usec = (Percentile $nonzero 0.99)
        max_usec = $(if ($nonzero.Count -gt 0) { [int64](($nonzero | Measure-Object -Maximum).Maximum) } else { 0 })
        max_gate_usec = [int64]$gate.MaxUsec
    }
    $summary[$name] = $entry
    if ($values.Count -lt [int]$gate.Min) {
        $failures += "$name count $($values.Count) < $($gate.Min)"
    }
    if ($entry.max_usec -gt [int64]$gate.MaxUsec) {
        $failures += "$name max $($entry.max_usec) > $($gate.MaxUsec)"
    }
}

$spikeCount = 0
if ($events.ContainsKey('terrain_process_spike')) { $spikeCount = $events['terrain_process_spike'].Count }
$summary['terrain_process_spike_count'] = $spikeCount
Write-Output ('P4_0H_TRACE_SUMMARY=' + ($summary | ConvertTo-Json -Depth 8 -Compress))
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error "P4.0H PERF GATE: $_" }
    exit 1
}
Write-Output 'P4_0H_TRACE_PASS'
exit 0

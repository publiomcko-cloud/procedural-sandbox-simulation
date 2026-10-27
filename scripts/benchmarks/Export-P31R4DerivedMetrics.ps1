[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][string]$ExpectedSourceSha,
    [Parameter(Mandatory = $true)][string]$ExpectedManifestSha,
    [string]$DerivedDirectoryName = 'derived-report-r4'
)
$ErrorActionPreference = 'Stop'
$EvidenceRoot = [System.IO.Path]::GetFullPath($EvidenceRoot)
$jsonlPath = Join-Path $EvidenceRoot 'campaign.jsonl'
if (-not (Test-Path -LiteralPath $jsonlPath -PathType Leaf)) { throw 'campaign_jsonl_missing' }

function Get-PropertyValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}
function Get-NearestRank([object[]]$Values, [double]$Quantile) {
    $sorted = @($Values | ForEach-Object { [long]$_ } | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $index = [Math]::Max(0, [Math]::Min($sorted.Count - 1, [int][Math]::Ceiling($sorted.Count * $Quantile) - 1))
    return [long]$sorted[$index]
}
function Get-RecursiveBytes([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "storage_root_missing:$Path" }
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force)
    $total = [long]0
    foreach ($file in $files) { $total += [long]$file.Length }
    return $total
}
function Assert-Artifact($Artifact, [string]$PathProperty, [string]$HashProperty, [System.Collections.Generic.List[object]]$Rows, [string]$RunId) {
    $path = [string](Get-PropertyValue $Artifact $PathProperty '')
    $expected = [string](Get-PropertyValue $Artifact $HashProperty '')
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "artifact_missing:${RunId}:$PathProperty"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected.ToLowerInvariant()) { throw "artifact_hash_mismatch:${RunId}:$PathProperty" }
    $Rows.Add([pscustomobject]@{ run_id = $RunId; artifact_path = $path; sha256 = $actual; bytes = (Get-Item -LiteralPath $path).Length })
}

$records = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($line in [System.IO.File]::ReadAllLines($jsonlPath)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $record = $line | ConvertFrom-Json
    if ($record.source_head -ne $ExpectedSourceSha -or $record.manifest_sha256 -ne $ExpectedManifestSha) { throw 'campaign_source_or_manifest_mismatch' }
    if (-not $seen.Add([string]$record.run_id)) { throw "duplicate_run_id:$($record.run_id)" }
    if ($record.status -ne 'PASS' -or [int]$record.exit_code -ne 0) { throw "campaign_row_not_pass:$($record.run_id)" }
    $resultPath = [string]$record.result_path
    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "result_missing:$($record.run_id)" }
    $resultHash = (Get-FileHash -LiteralPath $resultPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($resultHash -ne ([string]$record.result_sha256).ToLowerInvariant()) { throw "result_hash_mismatch:$($record.run_id)" }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($result.status -ne 'PASS' -or $result.source_sha -ne $ExpectedSourceSha -or $result.run_id -ne $record.run_id) {
        throw "result_identity_or_status_mismatch:$($record.run_id)"
    }
    $record | Add-Member -NotePropertyName _result -NotePropertyValue $result
    $record | Add-Member -NotePropertyName _storage_bytes -NotePropertyValue (Get-RecursiveBytes ([string]$record.storage_root))
    $records.Add($record)
}
if ($records.Count -ne 90) { throw "expected_90_campaign_rows_got_$($records.Count)" }

$artifactRows = [System.Collections.Generic.List[object]]::new()
$metricRows = [System.Collections.Generic.List[object]]::new()
foreach ($record in $records) {
    $result = $record._result
    Assert-Artifact $result.subledger_artifact 'path' 'sha256' $artifactRows $record.run_id
    foreach ($artifact in @($result.voxel_artifacts)) {
        Assert-Artifact $artifact 'B_path' 'B_sha256' $artifactRows $record.run_id
        Assert-Artifact $artifact 'C_path' 'C_sha256' $artifactRows $record.run_id
    }
    $meshStats = Get-PropertyValue $result.mesh_cache_stats 'stats'
    $meshRoot = [string]$record.mesh_cache_root
    $meshFiles = @(Get-ChildItem -LiteralPath $meshRoot -Recurse -File -Force)
    $meshBytes = [long]0
    foreach ($meshFile in $meshFiles) {
        $meshBytes += [long]$meshFile.Length
        $artifactRows.Add([pscustomobject]@{ run_id = $record.run_id; artifact_path = $meshFile.FullName
            sha256 = (Get-FileHash -LiteralPath $meshFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); bytes = [long]$meshFile.Length })
    }
    if ($meshBytes -ne [long](Get-PropertyValue $meshStats 'disk_bytes' 0)) { throw "mesh_cache_disk_inventory_mismatch:$($record.run_id)" }
    $cacheResult = Get-PropertyValue $result 'mesh_cache_stats'
    $launcherPeak = Get-PropertyValue $record 'launcher_peak_working_set_bytes' (Get-PropertyValue $record 'peak_working_set_bytes' 0)
    $base = [ordered]@{ run_id = $record.run_id; scenario_id = $record.scenario_id; repeat = [int]$record.repeat; source_sha = $ExpectedSourceSha
        candidate_operations = [int]$result.candidate_operation_count; storage_bytes = [long]$record._storage_bytes
        canonical_query_p95_usec = [double]$result.A_full_query_usec.p95_usec
        canonical_lod0_usec = [long]$result.canonical_lod0_usec; canonical_lod1_usec = [long]$result.canonical_lod1_usec
        mesh_cache_disk_bytes = [long](Get-PropertyValue $meshStats 'disk_bytes' 0); godot_static_memory_delta_bytes = [long](Get-PropertyValue $result 'static_memory_delta_bytes' 0)
        mesh_cache_cold_lookup_usec = [long](Get-PropertyValue $cacheResult 'cold_lookup_usec' 0)
        mesh_cache_warm_memory_usec = [long](Get-PropertyValue $cacheResult 'warm_memory_usec' 0)
        mesh_cache_fresh_instance_disk_usec = [long](Get-PropertyValue $cacheResult 'fresh_instance_disk_usec' 0)
        mesh_cache_hits = [long](Get-PropertyValue $meshStats 'hits' 0); mesh_cache_misses = [long](Get-PropertyValue $meshStats 'misses' 0)
        mesh_cache_disk_entries = [long](Get-PropertyValue $meshStats 'disk_entries' 0); mesh_cache_memory_bytes = [long](Get-PropertyValue $meshStats 'memory_bytes' 0)
        launcher_peak_working_set_bytes = [long]$launcherPeak; engine_os_rss_bytes = $null }
    $a = [ordered]@{} + $base
    $a.arm = 'A_CHUNK_SUBLEDGER'; $a.resolution = 0.0
    $a.build_usec = [double]$result.A_projection_build_usec; $a.incremental_usec = [double]$result.A_incremental_append_usec
    $a.save_usec = [double]$result.A_persist_usec; $a.load_usec = [double]$result.A_reload_usec
    $a.query_p50_usec = [double]$result.A_projected_query_usec.p50_usec; $a.query_p95_usec = [double]$result.A_projected_query_usec.p95_usec
    $a.query_p99_usec = [double]$result.A_projected_query_usec.p99_usec; $a.lod0_usec = [double]$result.A_lod0_usec; $a.lod1_usec = [double]$result.A_lod1_usec
    $a.node_error_max = $null; $a.lod0_surface_p95 = $null; $a.lod1_surface_p95 = $null; $a.lod0_normal_p95_deg = $null; $a.lod1_normal_p95_deg = $null
    $a.picker_sample_count = 0
    $metricRows.Add([pscustomobject]$a)

    foreach ($resolution in @($result.voxel_resolutions)) {
        foreach ($armName in @('B', 'C')) {
            $armResult = Get-PropertyValue $resolution $armName
            if ($null -eq $armResult) { throw "voxel_arm_missing:$($record.run_id):$armName" }
            $row = [ordered]@{} + $base
            $row.arm = if ($armName -eq 'B') { 'B_INCREMENTAL_FLOAT32_VOXEL' } else { 'C_SUBLEDGER_VOXEL_MESH_CACHE' }
            $row.resolution = [double]$resolution.spacing
            $row.build_usec = [double]$armResult.materialize_usec; $row.incremental_usec = [double]$armResult.incremental_update_usec
            $row.save_usec = [double]$armResult.save_usec; $row.load_usec = [double]$armResult.load_usec
            $row.query_p50_usec = [double]$armResult.query_usec.p50_usec; $row.query_p95_usec = [double]$armResult.query_usec.p95_usec
            $row.query_p99_usec = [double]$armResult.query_usec.p99_usec; $row.lod0_usec = [double]$armResult.lod0_build_usec; $row.lod1_usec = [double]$armResult.lod1_build_usec
            $row.node_error_max = [double]$armResult.node_error.max_abs_error
            $row.lod0_surface_p95 = [double]$armResult.lod0_surface.sampled_symmetric_vertex_to_triangle_distance.p95
            $row.lod1_surface_p95 = [double]$armResult.lod1_surface.sampled_symmetric_vertex_to_triangle_distance.p95
            $row.lod0_normal_p95_deg = [double]$armResult.lod0_surface.sampled_normal_angle_deg.p95
            $row.lod1_normal_p95_deg = [double]$armResult.lod1_surface.sampled_normal_angle_deg.p95; $row.picker_sample_count = 0
            $metricRows.Add([pscustomobject]$row)
        }
    }
    foreach ($picker in @($result.picker_resolutions)) {
        foreach ($armName in @('canonical', 'projection', 'B', 'C')) {
            $times = @($picker.metrics.rays | ForEach-Object { (Get-PropertyValue (Get-PropertyValue $_ $armName) 'elapsed_usec') })
            $armResult = Get-PropertyValue $picker.metrics.arms $armName
            $sampleCount = 0
            foreach ($count in @($armResult.samples)) { $sampleCount += [int]$count }
            $row = [ordered]@{} + $base
            $row.arm = 'PICKER_' + $armName.ToUpperInvariant(); $row.resolution = [double]$picker.spacing
            $row.build_usec = $null; $row.incremental_usec = $null; $row.save_usec = $null; $row.load_usec = $null
            $row.query_p50_usec = Get-NearestRank $times 0.50; $row.query_p95_usec = Get-NearestRank $times 0.95; $row.query_p99_usec = Get-NearestRank $times 0.99
            $row.lod0_usec = $null; $row.lod1_usec = $null; $row.node_error_max = $null; $row.lod0_surface_p95 = $null
            $row.lod1_surface_p95 = $null; $row.lod0_normal_p95_deg = $null; $row.lod1_normal_p95_deg = $null; $row.picker_sample_count = $sampleCount
            $metricRows.Add([pscustomobject]$row)
        }
    }
}

$derived = Join-Path $EvidenceRoot $DerivedDirectoryName
if (Test-Path -LiteralPath $derived) { throw 'derived_report_already_exists_refusing_overwrite' }
[void](New-Item -ItemType Directory -Path $derived)
$metricPath = Join-Path $derived 'metrics-per-run.corrected.csv'
$metricRows | Export-Csv -LiteralPath $metricPath -NoTypeInformation -Encoding UTF8
$artifactPath = Join-Path $derived 'artifact-integrity.csv'
$artifactRows | Export-Csv -LiteralPath $artifactPath -NoTypeInformation -Encoding UTF8

function Get-Median([double[]]$Values) {
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) { return $null }
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$middle] }
    return ([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0
}
$summaryRows = [System.Collections.Generic.List[object]]::new()
foreach ($group in ($metricRows | Group-Object { '{0}|{1}|{2}' -f $_.scenario_id, $_.arm, $_.resolution })) {
    $items = @($group.Group); $first = $items[0]
    $out = [ordered]@{ scenario_id = $first.scenario_id; arm = $first.arm; resolution = $first.resolution; process_count = $items.Count }
    foreach ($metric in @('build_usec','incremental_usec','save_usec','load_usec','query_p50_usec','query_p95_usec','query_p99_usec','canonical_query_p95_usec','canonical_lod0_usec','canonical_lod1_usec','lod0_usec','lod1_usec','node_error_max','lod0_surface_p95','lod1_surface_p95','lod0_normal_p95_deg','lod1_normal_p95_deg','storage_bytes','mesh_cache_disk_bytes','mesh_cache_cold_lookup_usec','mesh_cache_warm_memory_usec','mesh_cache_fresh_instance_disk_usec','mesh_cache_hits','mesh_cache_misses','mesh_cache_disk_entries','mesh_cache_memory_bytes','godot_static_memory_delta_bytes','launcher_peak_working_set_bytes')) {
        $values = @($items | ForEach-Object { $_.$metric } | Where-Object { $null -ne $_ -and $_ -ne '' } | ForEach-Object { [double]$_ })
        $out[$metric + '_median_across_processes'] = Get-Median $values
        $out[$metric + '_min_across_processes'] = if ($values.Count) { ($values | Measure-Object -Minimum).Minimum } else { $null }
        $out[$metric + '_max_across_processes'] = if ($values.Count) { ($values | Measure-Object -Maximum).Maximum } else { $null }
    }
    $summaryRows.Add([pscustomobject]$out)
}
$summaryPath = Join-Path $derived 'scenario-summary.corrected.csv'
$summaryRows | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
$integrity = [ordered]@{ source_head = $ExpectedSourceSha; manifest_sha256 = $ExpectedManifestSha; campaign_rows = $records.Count
    all_campaign_rows_pass = $true; verified_result_files = $records.Count; verified_artifacts = $artifactRows.Count
    metric_rows = $metricRows.Count; summary_groups = $summaryRows.Count; engine_os_rss = 'NOT_MEASURED'
    storage_measurement = 'recursive physical file byte sum of each run storage root'; picker_percentiles = 'nearest-rank over three raw rays per process and spacing; headless only'
    files = @() }
$integrity.files = @($metricPath, $artifactPath, $summaryPath | ForEach-Object { [pscustomobject]@{ path = $_; sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant(); bytes = (Get-Item -LiteralPath $_).Length } })
$integrityPath = Join-Path $derived 'integrity.json'
[System.IO.File]::WriteAllText($integrityPath, ($integrity | ConvertTo-Json -Depth 8) + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "DERIVED_METRICS_PASS campaign_rows=$($records.Count) metric_rows=$($metricRows.Count) groups=$($summaryRows.Count) verified_artifacts=$($artifactRows.Count)"
Write-Output $integrityPath

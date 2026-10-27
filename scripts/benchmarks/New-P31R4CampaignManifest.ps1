param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\docs\reports\P3-1-R4\campaign-manifest.json')
)
$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path $RepositoryRoot 'game\tests\fixtures\p3_1_r4'
$periodicRoot = Join-Path $fixtureRoot 'issue131'
$nonperiodicRoot = Join-Path $fixtureRoot 'nonperiodic'
function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$scenarioSpecs = [System.Collections.Generic.List[object]]::new()
$counts = @(0, 256, 640, 2048, 8192)
foreach ($layout in @('concentrated', 'distributed')) {
    foreach ($count in $counts) {
        $token = 'N{0:D4}' -f $count
        $stem = "P31.EDIT.$($layout.ToUpperInvariant()).$token.v1.R01.commands"
        $input = Join-Path $periodicRoot ($stem + '.json')
        [double[]]$resolutionSet = @()
        if ($count -le 256) { $resolutionSet = [double[]]@(0.5, 0.25, 0.125) }
        elseif ($count -le 2048) { $resolutionSet = [double[]]@(0.5, 0.25) }
        else { $resolutionSet = [double[]]@(0.5) }
        $scenarioSpecs.Add([ordered]@{
            scenario_id = "P31.R4.EDIT.$($layout.ToUpperInvariant()).$token.v1"
            source_kind = 'ISSUE131_R3B_FROZEN'
            layout = $layout
            operation_count = $count
            input_path = 'game/tests/fixtures/p3_1_r4/issue131/' + (Split-Path $input -Leaf)
            input_sha256 = Get-Sha256 $input
            source_manifest_sha256 = Get-Sha256 (Join-Path $periodicRoot 'scenario-manifest.json')
            source_inventory_sha256 = Get-Sha256 (Join-Path $periodicRoot 'SHA256SUMS.txt')
            region = if ($layout -eq 'concentrated') { @(0, 0) } else { @(-31, -64) }
            chunk = if ($layout -eq 'concentrated') { @(0, 0) } else { @(2, 2) }
            resolutions = [object[]]$resolutionSet
        })
    }
}
foreach ($layout in @('concentrated', 'distributed')) {
    foreach ($count in @(256, 640, 2048, 8192)) {
        $token = 'N{0:D4}' -f $count
        $filename = "P31.R3C.NONPERIODIC.$($layout.ToUpperInvariant()).$token.v1.commands.json"
        $input = Join-Path $nonperiodicRoot $filename
        [double[]]$resolutionSet = @()
        if ($count -le 256) { $resolutionSet = [double[]]@(0.5, 0.25, 0.125) }
        elseif ($count -le 2048) { $resolutionSet = [double[]]@(0.5, 0.25) }
        else { $resolutionSet = [double[]]@(0.5) }
        $scenarioSpecs.Add([ordered]@{
            scenario_id = "P31.R4.NONPERIODIC.$($layout.ToUpperInvariant()).$token.v1"
            source_kind = 'R3C_DISTINCT_NONPERIODIC_FROZEN'
            layout = $layout
            operation_count = $count
            input_path = 'game/tests/fixtures/p3_1_r4/nonperiodic/' + $filename
            input_sha256 = Get-Sha256 $input
            source_manifest_sha256 = Get-Sha256 (Join-Path $nonperiodicRoot 'scenario-manifest.json')
            source_inventory_sha256 = Get-Sha256 (Join-Path $nonperiodicRoot 'SHA256SUMS.txt')
            region = if ($layout -eq 'concentrated') { @(0, 0) } else { @(-31, -64) }
            chunk = if ($layout -eq 'concentrated') { @(0, 0) } else { @(2, 2) }
            resolutions = [object[]]$resolutionSet
        })
    }
}
$runs = [System.Collections.Generic.List[object]]::new()
$orderIndex = 0
for ($repeat = 1; $repeat -le 5; $repeat++) {
    $ordered = @($scenarioSpecs)
    if (($repeat % 2) -eq 0) { [array]::Reverse($ordered) }
    foreach ($spec in $ordered) {
        $orderIndex++
        $runs.Add([ordered]@{
            order_index = $orderIndex
            scenario_id = $spec.scenario_id
            repeat = $repeat
            source_kind = $spec.source_kind
            layout = $spec.layout
            operation_count = $spec.operation_count
            input_path = $spec.input_path
            input_sha256 = $spec.input_sha256
            source_manifest_sha256 = $spec.source_manifest_sha256
            source_inventory_sha256 = $spec.source_inventory_sha256
            region = $spec.region
            chunk = $spec.chunk
            resolutions = $spec.resolutions
            expected_sequence_start = if ($spec.operation_count -gt 0) { 0 } else { -1 }
            expected_sequence_end = $spec.operation_count - 1
        })
    }
}
$manifest = [ordered]@{
    schema = 'p3-1-r4-campaign-manifest-v1'
    campaign_id = 'P3.1-R4-PREREGISTERED-EXPERIMENT-v1'
    production_baseline = '92b442d7f5b605c7bc9c48fac2aceea9d71813aa'
    seed = 131102026
    generator_version = 1
    radius_mm = 580
    architecture_arms = @('A_CHUNK_SUBLEDGER', 'B_INCREMENTAL_FLOAT32_VOXEL', 'C_SUBLEDGER_VOXEL_MESH_CACHE')
    repeat_target = 5
    maximum_row_duration_seconds = 600
    rows = @($runs)
}
$json = ($manifest | ConvertTo-Json -Depth 20) + "`n"
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($json)
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $OutputPath)) | Out-Null
[System.IO.File]::WriteAllBytes($OutputPath, $bytes)
$sha = Get-Sha256 $OutputPath
[System.IO.File]::WriteAllText($OutputPath + '.sha256', "$sha  $(Split-Path $OutputPath -Leaf)`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "MANIFEST=$OutputPath"
Write-Output "ROWS=$($runs.Count)"
Write-Output "SHA256=$sha"

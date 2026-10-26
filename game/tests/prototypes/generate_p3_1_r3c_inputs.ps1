param([string]$OutputRoot = (Join-Path $PSScriptRoot '..\fixtures\p3_1_r3c\nonperiodic'))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $root) {
    if ((Get-ChildItem -LiteralPath $root -Force | Measure-Object).Count -ne 0) {
        throw "Output root already contains content; refusing to overwrite: $root"
    }
} else {
    [void][IO.Directory]::CreateDirectory($root)
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$seed = 135031
$allRows = New-Object System.Collections.Generic.List[object]
$allSums = New-Object System.Collections.Generic.List[string]

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Read-U16([byte[]]$Bytes, [int]$Offset) {
    return [int]$Bytes[$Offset] + 256 * [int]$Bytes[$Offset + 1]
}

foreach ($layout in @('CONCENTRATED', 'DISTRIBUTED')) {
    foreach ($count in @(256, 640, 2048, 8192)) {
        $commands = New-Object System.Collections.Generic.List[object]
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        for ($i = 0; $i -lt $count; $i++) {
            $token = "P31-R3C-NONPERIODIC-v1|$seed|$layout|$i"
            $tokenSha = [Security.Cryptography.SHA256]::Create()
            try { $digest = $tokenSha.ComputeHash($utf8.GetBytes($token)) }
            finally { $tokenSha.Dispose() }
            $y = -1500 + (Read-U16 $digest 0) % 8501
            $radius = 450 + (Read-U16 $digest 2) % 751
            $rx = 0; $rz = 0
            if ($layout -eq 'CONCENTRATED') {
                $x = 3000 + ($i % 1000)
                $band = [Math]::Floor($i / 1000)
                $z = 1500 + ($band * 1200) + (Read-U16 $digest 4) % 200
            } else {
                $rx = ((Read-U16 $digest 4) % 9) - 4 - 31
                $rz = ((Read-U16 $digest 6) % 9) - 4 - 64
                switch ($i % 32) {
                    0 { $x = 50; $z = 50 }
                    1 { $x = 50; $z = 11950 }
                    2 { $x = 15950; $z = 50 }
                    3 { $x = 15950; $z = 11950 }
                    4 { $x = 50; $z = 400 + (Read-U16 $digest 8) % 11200 }
                    5 { $x = 15950; $z = 400 + (Read-U16 $digest 8) % 11200 }
                    6 { $x = 300 + (Read-U16 $digest 8) % 15400; $z = 50 }
                    7 { $x = 300 + (Read-U16 $digest 8) % 15400; $z = 11950 }
                    default {
                        $x = 250 + (($i * 7919) % 15500)
                        $z = 200 + (Read-U16 $digest 8) % 11600
                    }
                }
            }
            $centerKey = "$rx,$rz,$x,$y,$z"
            while (-not $seen.Add($centerKey)) {
                $x = 50 + (($x - 50 + 1) % 15900)
                $centerKey = "$rx,$rz,$x,$y,$z"
            }
            $worldX = $rx * 16000 + $x
            $worldZ = $rz * 12000 + $z
            $commands.Add([ordered]@{
                sequence = $i
                revision = $i + 1
                mode = if (($i % 2) -eq 0) { 'CARVE' } else { 'FILL' }
                center_mm = @($worldX, $y, $worldZ)
                radius_mm = $radius
            })
        }
        $stem = "P31.R3C.NONPERIODIC.$layout.N{0:D4}.v1" -f $count
        $commandArray = $commands.ToArray()
        $json = ConvertTo-Json -InputObject $commandArray -Depth 8 -Compress
        $bytes = $utf8.GetBytes($json + "`n")
        $path = Join-Path $root ($stem + '.commands.json')
        [IO.File]::WriteAllBytes($path, $bytes)
        $hash = Get-BytesSha256 $bytes
        [IO.File]::WriteAllText((Join-Path $root ($stem + '.commands.sha256')), "$hash`n", $utf8)
        $allSums.Add("$hash  $([IO.Path]::GetFileName($path))")
        $allRows.Add([ordered]@{
            scenario_id = "$stem"
            layout = $layout
            count = $count
            seed = $seed
            command_file = [IO.Path]::GetFileName($path)
            command_sha256 = $hash
            unique_center_count = $seen.Count
            selected_region = if ($layout -eq 'CONCENTRATED') { @(0,0) } else { @(-31,-64) }
            selected_chunk = if ($layout -eq 'CONCENTRATED') { @(0,0) } else { @(2,2) }
            geometry = if ($layout -eq 'CONCENTRATED') { 'single-region strip spanning chunk boundaries, varied height/radius, cave and surface samples' } else { '9x9 negative-region neighborhood with face/edge/corner seam centers and varied geometry' }
        })
    }
}
$manifest = [ordered]@{ schema = 1; generator = 'P31-R3C-NONPERIODIC-v1'; seed = $seed; hash_input = 'UTF8(P31-R3C-NONPERIODIC-v1|seed|layout|zero_based_sequence), SHA-256'; center_uniqueness = 'ordinal world-mm tuple; collision resolves by incrementing local X mm with wrap in [50,15949]'; scenarios = $allRows.ToArray() }
$manifestJson = (ConvertTo-Json -InputObject $manifest -Depth 10).Replace("`r`n", "`n")
$manifestBytes = $utf8.GetBytes($manifestJson + "`n")
[IO.File]::WriteAllBytes((Join-Path $root 'scenario-manifest.json'), $manifestBytes)
$manifestSha = Get-BytesSha256 $manifestBytes
[IO.File]::WriteAllText((Join-Path $root 'scenario-manifest.sha256'), "$manifestSha`n", $utf8)
$allSums.Add("$manifestSha  scenario-manifest.json")
$sumsBytes = $utf8.GetBytes(($allSums -join "`n") + "`n")
[IO.File]::WriteAllBytes((Join-Path $root 'SHA256SUMS.txt'), $sumsBytes)
Write-Output "FixtureRoot=$root"
Write-Output "ManifestSha256=$manifestSha"
Write-Output "ScenarioCount=$($allRows.Count)"
$allRows | ForEach-Object { Write-Output "$($_.scenario_id) unique=$($_.unique_center_count) sha256=$($_.command_sha256)" }

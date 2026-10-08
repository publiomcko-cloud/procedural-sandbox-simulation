[CmdletBinding()]
param(
    [string] $FixturePath = (Join-Path $PSScriptRoot 'fixtures/analytic_sdf_v1.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json
$assertions = 0

function Assert-Equal([object] $Actual, [object] $Expected, [string] $Message) {
    $script:assertions++
    if ($Actual -ne $Expected) {
        throw "$Message; expected '$Expected', got '$Actual'."
    }
}

function Get-FixtureDensity([double[]] $Point, [object] $Field) {
    $x = $Point[0]
    $y = $Point[1]
    $z = $Point[2]

    $center = $Field.sphere_center
    $sphereDistance = [Math]::Sqrt(
        [Math]::Pow($x - [double]$center[0], 2) +
        [Math]::Pow($y - [double]$center[1], 2) +
        [Math]::Pow($z - [double]$center[2], 2))
    $plane = -$y
    $hill = [double]$Field.sphere_radius - $sphereDistance
    $base = [Math]::Max($plane, $hill)

    $start = $Field.tunnel_segment_start
    $end = $Field.tunnel_segment_end
    $dx = [double]$end[0] - [double]$start[0]
    $dy = [double]$end[1] - [double]$start[1]
    $dz = [double]$end[2] - [double]$start[2]
    $lengthSquared = $dx * $dx + $dy * $dy + $dz * $dz
    $projection = (($x - [double]$start[0]) * $dx +
        ($y - [double]$start[1]) * $dy +
        ($z - [double]$start[2]) * $dz) / $lengthSquared
    $projection = [Math]::Max(0.0, [Math]::Min(1.0, $projection))
    $closestX = [double]$start[0] + $projection * $dx
    $closestY = [double]$start[1] + $projection * $dy
    $closestZ = [double]$start[2] + $projection * $dz
    $segmentDistance = [Math]::Sqrt(
        [Math]::Pow($x - $closestX, 2) +
        [Math]::Pow($y - $closestY, 2) +
        [Math]::Pow($z - $closestZ, 2))
    $tunnel = [double]$Field.tunnel_radius - $segmentDistance

    return [Math]::Min($base, -$tunnel)
}

Assert-Equal $fixture.fixture_id 'p0.1.f0.analytic_sdf.v1' 'Fixture identity'
Assert-Equal $fixture.canonicalization.tick_scale 4096 'Canonical tick scale'
Assert-Equal $fixture.sign_probes.Count 7 'Sign-probe count'
Assert-Equal $fixture.field.plane '-p.y' 'Plane formula'
Assert-Equal $fixture.field.hill '5 - length(p - (0,-1,0))' 'Hill formula'
Assert-Equal $fixture.field.base 'max(plane, hill)' 'Base formula'
Assert-Equal $fixture.field.density 'min(base, -tunnel)' 'Density formula'

foreach ($probe in $fixture.sign_probes) {
    $density = Get-FixtureDensity -Point ([double[]]$probe.point) -Field $fixture.field
    $ticks = [long][Math]::Round(
        $density * [double]$fixture.canonicalization.tick_scale,
        [MidpointRounding]::ToEven)

    $assertions++
    if ([Math]::Abs($density - [double]$probe.expected_density) -gt 1e-12) {
        throw "Density mismatch at ($($probe.point -join ', ')): expected $($probe.expected_density), got $density."
    }
    $pointText = (($probe.point | ForEach-Object {
        ([double]$_).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    }) -join ', ')
    Assert-Equal $ticks ([long]$probe.expected_ticks) "Canonical ticks at ($pointText)"
    $densityText = $density.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    Write-Output "PASS: ($pointText) density=$densityText ticks=$ticks — $($probe.expectation)"
}

Write-Output "Assertions: $assertions"
Write-Output 'Fixture validation PASS (source-only; no Godot or vendor code executed).'

param(
    [Parameter(Mandatory=$true)][string]$ProjectPath
)
$ErrorActionPreference = 'Stop'

$relativeFiles = @(
    'scripts/simulation/fixed_tick_scheduler.gd',
    'scripts/simulation/simulation_tier_state.gd',
    'scripts/simulation/simulation_tier_router.gd',
    'scripts/simulation/material_environment_domain.gd',
    'scripts/simulation/material_environment_work_queue.gd',
    'scripts/simulation/material_environment_runtime_bridge.gd',
    'scripts/simulation/simulation_world_scope_lifecycle.gd',
    'scripts/simulation/simulation_runtime_store.gd',
    'scripts/simulation/simulation_runtime.gd',
    'scripts/terrain/terrain_demo.gd'
)
$classNames = @(
    'FixedTickScheduler',
    'SimulationTierState',
    'SimulationTierRouter',
    'MaterialEnvironmentDomain',
    'MaterialEnvironmentWorkQueue',
    'MaterialEnvironmentRuntimeBridge',
    'SimulationWorldScopeLifecycle',
    'SimulationRuntimeStore',
    'SimulationRuntime'
)

$violations = @()
foreach ($relative in $relativeFiles) {
    $path = Join-Path $ProjectPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "P4 cache-independence source missing: $relative"
    }
    $lineNumber = 0
    Get-Content -LiteralPath $path | ForEach-Object {
        $lineNumber += 1
        $line = $_
        if ($line -match '^\s*class_name\s+') { return }
        foreach ($name in $classNames) {
            $escaped = [regex]::Escape($name)
            if (
                $line -match (':\s*' + $escaped + '\b') -or
                $line -match ('->\s*' + $escaped + '\b') -or
                $line -match ('\b' + $escaped + '\s*\.')
            ) {
                $violations += "$relative:$lineNumber: $line"
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Error "P4 class-cache dependency: $_" }
    exit 1
}
Write-Output 'P4_0H_CLASS_CACHE_INDEPENDENCE_PASS'
exit 0

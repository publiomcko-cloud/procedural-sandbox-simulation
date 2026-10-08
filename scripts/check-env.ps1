$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Write-Host "Repository directory: $root"
foreach ($command in @('git','code','pwsh')) {
    $cmd = Get-Command $command -ErrorAction SilentlyContinue
    if ($cmd) { Write-Host "Found $command -> $($cmd.Source)" }
    else { Write-Warning "$command not in PATH" }
}
$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'godot' }
try { & $godot --version; if ($LASTEXITCODE -ne 0) { throw 'Godot exited non-zero' } }
catch { Write-Error "Godot unavailable. Set GODOT_BIN or PATH. $($_.Exception.Message)"; exit 1 }
Write-Host 'ENV_CHECK_PASS (availability only; full tests require validate.ps1)'

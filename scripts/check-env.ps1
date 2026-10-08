$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = [System.Collections.Generic.List[string]]::new()
Write-Host "Repository directory: $root"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    $failures.Add("PowerShell 7 required; found $($PSVersionTable.PSVersion)")
} else {
    Write-Host "PowerShell PASS: $($PSVersionTable.PSVersion)"
}

$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
if ($null -eq $os) {
    $failures.Add('Could not determine Windows version')
} elseif ([int]$os.BuildNumber -lt 22000) {
    $failures.Add("Windows 11 required (build 22000+); found $($os.Caption), build $($os.BuildNumber)")
} else {
    Write-Host "Windows PASS: $($os.Caption), build $($os.BuildNumber), $env:PROCESSOR_ARCHITECTURE"
}

foreach ($command in @('git', 'pwsh')) {
    $found = Get-Command $command -ErrorAction SilentlyContinue
    if ($null -eq $found) {
        $failures.Add("Required command not found: $command")
    } else {
        $version = if ($command -eq 'git') { (& git --version 2>&1 | Out-String).Trim() } else { "PowerShell $($PSVersionTable.PSVersion)" }
        Write-Host "$command PASS: $version ($($found.Source))"
    }
}

$python = Get-Command py -ErrorAction SilentlyContinue
if ($null -eq $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
if ($null -eq $python) {
    Write-Host 'Python OPTIONAL: not installed; no P0.0 validation script requires Python'
} else {
    $pythonVersion = (& $python.Source --version 2>&1 | Out-String).Trim()
    Write-Host "Python OPTIONAL: $pythonVersion ($($python.Source))"
}

$godot = if ($env:GODOT_BIN) { $env:GODOT_BIN } else { 'godot' }
try {
    $version = (& $godot --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Godot version command exited $LASTEXITCODE" }
    Write-Host "Godot found: $version"
    if ($version -notmatch '^4\.7\.2\.stable(?:\.|$)') {
        $failures.Add("Godot 4.7.2 stable required; found '$version'")
    } else {
        Write-Host 'Godot PASS: pinned version 4.7.2 stable'
    }
} catch {
    $failures.Add("Godot unavailable or failed: $($_.Exception.Message). Set GODOT_BIN or add Godot to PATH.")
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "ENV_CHECK_FAIL: failures=$($failures.Count)"
    exit 1
}
Write-Host 'ENV_CHECK_PASS: Windows 11, PowerShell 7, Git and Godot 4.7.2 verified'
exit 0

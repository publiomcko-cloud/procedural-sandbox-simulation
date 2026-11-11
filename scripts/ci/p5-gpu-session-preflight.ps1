param(
    [ValidateSet('Service', 'Interactive')]
    [string]$Role = 'Service',
    [string]$EvidenceDir = $(if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'p5-gpu-session' } else { Join-Path $env:TEMP 'p5-gpu-session' })
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$session = (Get-Process -Id $PID).SessionId
$explorerInSession = @(
    Get-Process -Name explorer -ErrorAction SilentlyContinue |
        Where-Object { $_.SessionId -eq $session }
).Count -gt 0
$adapters = @()
try {
    $adapters = @(
        Get-CimInstance Win32_VideoController -ErrorAction Stop |
            Select-Object -Property Name, DriverVersion
    )
} catch {
    Write-Warning 'Video adapter inventory unavailable; graphic runtime validation remains mandatory.'
}
$record = [ordered]@{
    role = $Role
    session_id = [int]$session
    environment_user_interactive = [Environment]::UserInteractive
    explorer_in_same_session = [bool]$explorerInSession
    video_adapters = $adapters
    windows_version = [Environment]::OSVersion.VersionString
    runner_is_self_hosted = ($env:RUNNER_OS -eq 'Windows')
    status = 'DIAGNOSTIC_ONLY'
}
$path = Join-Path $EvidenceDir "session-$($Role.ToLowerInvariant()).json"
$record | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
Write-Host ('P5_GPU_SESSION_DIAGNOSTIC: ' + ($record | ConvertTo-Json -Compress -Depth 5))
if ($Role -eq 'Interactive') {
    if ($session -le 0 -or -not [Environment]::UserInteractive -or -not $explorerInSession) {
        throw 'P5_GPU_INTERACTIVE_SESSION_MISSING: run the GPU runner from a logged-in, unlocked Windows desktop; never as a service.'
    }
    Write-Host 'P5_GPU_INTERACTIVE_SESSION_PASS'
} else {
    Write-Host 'P5_GPU_SERVICE_PROBE_PASS'
}

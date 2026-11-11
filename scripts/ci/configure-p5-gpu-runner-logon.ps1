param(
    [string]$RunnerDir = 'C:\actions-runner-gpu',
    [string]$TaskName = 'Sandbox-P5-GPU-Interactive-Runner',
    [switch]$Install,
    [switch]$Remove,
    [switch]$Start
)
$ErrorActionPreference = 'Stop'
if (@($Install, $Remove, $Start | Where-Object { $_ }).Count -ne 1) {
    throw 'Choose exactly one action: -Install, -Start or -Remove.'
}
if ((Get-Process -Id $PID).SessionId -le 0 -or -not [Environment]::UserInteractive) {
    throw 'Run this script from a PowerShell session in your logged-in Windows desktop, not GitHub Actions service.'
}
if ($Remove) {
    $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        Write-Host "No task registered: $TaskName"
        exit 0
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "P5_GPU_LOGON_TASK_REMOVED: $TaskName"
    exit 0
}
$runnerCmd = Join-Path $RunnerDir 'run.cmd'
if (-not (Test-Path -LiteralPath $runnerCmd -PathType Leaf)) { throw "Runner binary missing: $runnerCmd" }
if (-not (Test-Path -LiteralPath (Join-Path $RunnerDir '.runner') -PathType Leaf)) {
    throw 'The GPU runner has not been registered. Configure it via GitHub Settings > Actions > Runners before installing the logon task.'
}
$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
if ($Install) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        throw "Task already exists: $TaskName. Review it before changing it."
    }
    $arguments = '/d /c ""' + $runnerCmd + '""'
    $action = New-ScheduledTaskAction -Execute "$env:WINDIR\System32\cmd.exe" -Argument $arguments -WorkingDirectory $RunnerDir
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'GitHub Actions P5 GPU runner; interactive Windows session only; no auto-logon.' | Out-Null
    Write-Host "P5_GPU_LOGON_TASK_INSTALLED: $TaskName"
    Write-Host 'Starts only after this Windows user signs in. No password or auto-logon is configured.'
}
if ($Start) {
    if (-not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) { throw "Task not found: $TaskName" }
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "P5_GPU_LOGON_TASK_STARTED: $TaskName"
}

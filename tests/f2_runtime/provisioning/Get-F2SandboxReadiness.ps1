[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Add-Check {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('PASS', 'FAIL', 'UNKNOWN')] [string] $Status,
        [Parameter(Mandatory)] [string] $Detail
    )
    [pscustomobject]@{ name = $Name; status = $Status; detail = $Detail }
}

$checks = [System.Collections.Generic.List[object]]::new()
$machine = Get-CimInstance -ClassName Win32_ComputerSystem
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$checks.Add((Add-Check -Name 'guest_identity' -Status PASS -Detail ("{0}\\{1}; OS={2}; build={3}; current_user_admin={4}" -f $machine.Domain, $identity.Name, $os.Caption, $os.BuildNumber, $isAdmin)))

$whoami = & "$env:WINDIR\System32\whoami.exe" /all 2>&1 | Out-String
$checks.Add((Add-Check -Name 'token_groups' -Status $(if ($isAdmin) { 'FAIL' } else { 'PASS' }) -Detail $whoami.Trim()))

try {
    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) -or -not (Get-Command Get-NetRoute -ErrorAction SilentlyContinue)) {
        throw 'Get-NetAdapter/Get-NetRoute commands are unavailable.'
    }
    $adapters = @(Get-NetAdapter -ErrorAction Stop | Select-Object Name, InterfaceDescription, Status, MacAddress, LinkSpeed)
    $upAdapters = @($adapters | Where-Object { $_.Status -eq 'Up' })
    $routes = @(
        Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop
        Get-NetRoute -AddressFamily IPv6 -ErrorAction Stop
    ) | Select-Object InterfaceAlias, AddressFamily, DestinationPrefix, NextHop, RouteMetric
    $defaultRoutes = @($routes | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0', '::/0') })
    $networkStatus = if ($upAdapters.Count -eq 0 -and $defaultRoutes.Count -eq 0) { 'PASS' } else { 'FAIL' }
    $networkDetails = @{
        adapters = $adapters
        active_adapters = $upAdapters
        default_routes = $defaultRoutes
        note = 'PASS means no adapter reported Up and no IPv4 or IPv6 default route was observed; this does not independently prove every possible network path is disabled.'
    }
} catch {
    $networkStatus = 'UNKNOWN'
    $networkDetails = @{ error = $_.Exception.Message; note = 'Network state could not be queried; UNKNOWN is not a pass.' }
}
$checks.Add((Add-Check -Name 'effective_network_observation' -Status $networkStatus -Detail ($networkDetails | ConvertTo-Json -Depth 6 -Compress)))

$inputRoot = 'C:\F2Input'
if (-not (Test-Path -LiteralPath $inputRoot -PathType Container)) {
    $checks.Add((Add-Check -Name 'read_only_mapping' -Status UNKNOWN -Detail 'C:\F2Input is absent; the expected input mapping was not observed.'))
} else {
    $probePath = Join-Path $inputRoot ('.__f2_readonly_probe_{0}.tmp' -f [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($probePath, 'F2 read-only mapping probe')
        $removed = $false
        try {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction Stop
            $removed = -not (Test-Path -LiteralPath $probePath)
        } catch { }
        $checks.Add((Add-Check -Name 'read_only_mapping' -Status FAIL -Detail ("A write succeeded inside C:\F2Input; temporary probe removed={0}. Do not continue." -f $removed)))
    } catch [System.UnauthorizedAccessException] {
        $checks.Add((Add-Check -Name 'read_only_mapping' -Status PASS -Detail 'Write attempt was denied by access control.'))
    } catch [System.IO.IOException] {
        if ($_.Exception.HResult -eq -2147024891) {
            $checks.Add((Add-Check -Name 'read_only_mapping' -Status PASS -Detail 'Write attempt was denied by access control.'))
        } else {
            $checks.Add((Add-Check -Name 'read_only_mapping' -Status UNKNOWN -Detail $_.Exception.Message))
        }
    } catch {
        $checks.Add((Add-Check -Name 'read_only_mapping' -Status UNKNOWN -Detail $_.Exception.Message))
    } finally {
        if (Test-Path -LiteralPath $probePath -PathType Leaf) {
            Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        }
    }
}

$checks.Add((Add-Check -Name 'guest_mapping_inventory' -Status $(if (Test-Path -LiteralPath $inputRoot -PathType Container) { 'PASS' } else { 'UNKNOWN' }) -Detail $(if (Test-Path -LiteralPath $inputRoot -PathType Container) { (Get-ChildItem -LiteralPath $inputRoot -Force | Select-Object Name, Length, Attributes | ConvertTo-Json -Depth 4 -Compress) } else { 'Expected mapped directory is not present.' })))

$graphics = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue | Select-Object Name, AdapterCompatibility, DriverVersion, VideoModeDescription, Status)
$checks.Add((Add-Check -Name 'graphics_inventory' -Status $(if ($graphics.Count) { 'PASS' } else { 'UNKNOWN' }) -Detail ((@{ adapters = $graphics; godot_gl_compatibility = 'UNKNOWN: no Godot executable was started by this diagnostic.' } | ConvertTo-Json -Depth 5 -Compress))))

$memory = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$systemDrive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction SilentlyContinue
$checks.Add((Add-Check -Name 'resource_and_supervision_limits' -Status UNKNOWN -Detail ("Guest-visible RAM={0} GiB; {1} free on system volume. These observations do not prove configured caps, disk quotas, CPU limits, or per-probe/session supervision." -f $memory, $(if ($systemDrive) { [math]::Round($systemDrive.FreeSpace / 1GB, 2).ToString() + ' GiB' } else { 'unknown free space' }))))
$checks.Add((Add-Check -Name 'godot_standard_user_launch_context' -Status UNKNOWN -Detail 'No Godot executable or native extension was launched. Current-token membership alone does not prove a future launch token.'))
$checks.Add((Add-Check -Name 'evidence_export_and_discard' -Status UNKNOWN -Detail 'Manual owner confirmation required for screen capture, sanitized evidence handling, and guest discard/cleanup.'))

$result = [pscustomobject]@{
    diagnostic = 'F2 Windows Sandbox readiness; diagnostics only'
    timestamp_utc = [DateTime]::UtcNow.ToString('o')
    computer = $machine.Name
    checks = @($checks)
    overall = if (@($checks | Where-Object { $_.status -eq 'FAIL' }).Count) { 'FAIL' } else { 'INCOMPLETE' }
    native_code_executed = $false
}
$result | ConvertTo-Json -Depth 8

if ($result.overall -eq 'FAIL') { exit 2 }
exit 0

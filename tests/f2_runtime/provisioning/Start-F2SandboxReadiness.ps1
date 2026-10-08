[CmdletBinding()]
param(
    [switch] $ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$approvedHostFolder = 'C:\F2-Approved-Inputs'
$diagnosticName = 'Get-F2SandboxReadiness.ps1'
$bootstrapName = 'Start-F2SandboxDiagnostics.ps1'
$expectedDiagnosticSha256 = '78fa1dd2d0bc691cecdb5089ee409c71080d30fe0f0e928b2225c7d3bc745d9f'
$expectedBootstrapSha256 = 'ac8f5952b4138c774a5193f1b5eba0abef6abca961a9573e208296812933ab0e'
$expectedWsbSha256 = '0edaa9ab7363c902ea1a39badd5dc8f5b9e6870811cbb32421c7562e133de941'
$sandboxExe = Join-Path $env:WINDIR 'System32\WindowsSandbox.exe'
$templatePath = Join-Path $PSScriptRoot 'F2-Isolated-Sandbox-automation.wsb.example'
$preparerPath = Join-Path $PSScriptRoot 'Prepare-F2SandboxInputs.ps1'
$powershellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-NormalizedScriptHash {
    param([Parameter(Mandatory)] [string] $LiteralPath)
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    $text = $strictUtf8.GetString([IO.File]::ReadAllBytes($LiteralPath))
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-NoReparsePath {
    param([Parameter(Mandatory)] [string] $LiteralPath)
    $resolved = [IO.Path]::GetFullPath($LiteralPath)
    $root = [IO.Path]::GetPathRoot($resolved)
    if ($resolved -eq $root) { throw "Refusing drive root: $resolved" }
    $cursor = $root
    foreach ($part in $resolved.Substring($root.Length).Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $part
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Refusing reparse path: $cursor" }
        }
    }
}

function Assert-LauncherTemplateHash {
    param([Parameter(Mandatory)] [string] $LiteralPath, [Parameter(Mandatory)] [string] $ExpectedSha256)
    if ((Get-NormalizedScriptHash $LiteralPath) -ne $ExpectedSha256) { throw 'Automation .wsb template hash does not match the reviewed file.' }
    return $true
}

function Assert-LauncherAutomationConfiguration {
    param(
        [Parameter(Mandatory)] [xml] $Configuration,
        [Parameter(Mandatory)] [string] $ExpectedCommand,
        [Parameter(Mandatory)] [string] $ApprovedHostFolder
    )
    $settings = @($Configuration.Configuration.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    $mappedFolders = @($Configuration.Configuration.MappedFolders.MappedFolder)
    $logonChildren = @($Configuration.Configuration.LogonCommand.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    if ($Configuration.Configuration.Networking -ne 'Disable' -or
        $Configuration.Configuration.ClipboardRedirection -ne 'Disable' -or
        $Configuration.Configuration.VGpu -ne 'Disable' -or
        $Configuration.Configuration.ProtectedClient -ne 'Enable' -or
        $Configuration.Configuration.AudioInput -ne 'Disable' -or
        $Configuration.Configuration.VideoInput -ne 'Disable' -or
        $Configuration.Configuration.PrinterRedirection -ne 'Disable' -or
        $Configuration.Configuration.MemoryInMB -ne '8192' -or
        $mappedFolders.Count -ne 1 -or
        $mappedFolders[0].HostFolder -ne $ApprovedHostFolder -or
        $mappedFolders[0].SandboxFolder -ne 'C:\F2Input' -or
        $mappedFolders[0].ReadOnly -ne 'true' -or
        $logonChildren.Count -ne 1 -or $logonChildren[0] -ne 'Command' -or
        $Configuration.Configuration.LogonCommand.Command -ne $ExpectedCommand -or
        $settings.Count -ne 10 -or
        @($settings | Select-Object -Unique).Count -ne 10 -or
        @($settings | Where-Object { $_ -notin @('VGpu', 'Networking', 'MappedFolders', 'AudioInput', 'VideoInput', 'ProtectedClient', 'PrinterRedirection', 'ClipboardRedirection', 'MemoryInMB', 'LogonCommand') }).Count -gt 0) {
        throw 'The automation .wsb does not match the exact reviewed offline/read-only configuration and single diagnostic command.'
    }
    return $true
}

try {
    if (-not (Test-Path -LiteralPath $sandboxExe -PathType Leaf)) { throw 'WindowsSandbox.exe is unavailable; host settings were not changed.' }
    if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)) { throw '64-bit Windows PowerShell is unavailable.' }
    $activeSandbox = @(Get-Process -Name WindowsSandbox -ErrorAction SilentlyContinue)
    if ($activeSandbox.Count -gt 0) { throw 'A WindowsSandbox process is already active. Close/discard that guest before staging new inputs or starting another session.' }
    Assert-NoReparsePath -LiteralPath $approvedHostFolder
    Assert-NoReparsePath -LiteralPath $templatePath
    Assert-NoReparsePath -LiteralPath $preparerPath
    Assert-LauncherTemplateHash -LiteralPath $templatePath -ExpectedSha256 $expectedWsbSha256 | Out-Null

    $preparerOutput = & $powershellPath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $preparerPath -Automation -PrepareInputs 2>&1
    $preparerExit = $LASTEXITCODE
    if ($preparerExit -ne 0) { throw "Pinned host checks/input staging failed with exit code $preparerExit. $($preparerOutput -join ' ')" }

    $folderEntries = @(Get-ChildItem -LiteralPath $approvedHostFolder -Force)
    $expectedNames = @($diagnosticName, $bootstrapName)
    if ($folderEntries.Count -ne $expectedNames.Count -or @($folderEntries | Where-Object { $_.Name -notin $expectedNames -or $_.PSIsContainer -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }).Count -gt 0) {
        throw 'The approved input folder does not contain exactly the two reviewed regular script files.'
    }
    $diagnosticPath = Join-Path $approvedHostFolder $diagnosticName
    $bootstrapPath = Join-Path $approvedHostFolder $bootstrapName
    if ((Get-NormalizedScriptHash $diagnosticPath) -ne $expectedDiagnosticSha256) { throw 'Staged diagnostic digest changed after the host checker.' }
    if ((Get-NormalizedScriptHash $bootstrapPath) -ne $expectedBootstrapSha256) { throw 'Staged bootstrap digest changed after the host checker.' }

    [xml] $wsb = Get-Content -LiteralPath $templatePath -Raw
    $expectedCommand = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -Command "Write-Host ''F2 DIAGNOSTIC STARTING - visible startup wrapper''; & ''C:\F2Input\Start-F2SandboxDiagnostics.ps1''"'
    Assert-LauncherAutomationConfiguration -Configuration $wsb -ExpectedCommand $expectedCommand -ApprovedHostFolder $approvedHostFolder | Out-Null

    $runId = [guid]::NewGuid().ToString('N')
    $configPath = Join-Path $env:TEMP ("F2-Sandbox-Readiness-$runId.wsb")
    if (Test-Path -LiteralPath $configPath) { throw 'Generated .wsb path already exists; refusing overwrite.' }
    Copy-Item -LiteralPath $templatePath -Destination $configPath -ErrorAction Stop
    Assert-NoReparsePath -LiteralPath $configPath
    Assert-LauncherTemplateHash -LiteralPath $configPath -ExpectedSha256 $expectedWsbSha256 | Out-Null

    $featureStatus = 'UNKNOWN (read-only optional-feature query was not run by this launcher; Sandbox launch will report availability)'
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -ErrorAction Stop
        $featureStatus = [string]$feature.State
    } catch {
        $featureStatus = 'UNKNOWN (feature query requires elevation; this launcher will not elevate)'
    }
    if ($ValidateOnly) {
        Write-Output 'HOST VALIDATION PASS; no Sandbox process was launched.'
        Write-Output ('Configuration prepared at: {0}' -f $configPath)
        Write-Output ('Input scripts are pinned: diagnostic={0}; bootstrap={1}' -f $expectedDiagnosticSha256, $expectedBootstrapSha256)
        Write-Output 'Network, clipboard, and vGPU remain disabled in the generated configuration.'
        exit 0
    }
    $scopeText = @"
One disposable Windows Sandbox will start using:
$configPath

Host input mapping: $approvedHostFolder -> C:\F2Input (ReadOnly=true)
Guest inputs: two hash-pinned PowerShell diagnostic scripts only
Diagnostic SHA-256: $($expectedDiagnosticSha256.Substring(0, 16))…; bootstrap SHA-256: $($expectedBootstrapSha256.Substring(0, 16))…
Automatic guest action: create one random-password guest-local standard user, run the pinned diagnostic as that user, print a concise report
Networking: disabled    Clipboard: disabled    vGPU: disabled
ProtectedClient: enabled    Memory allocation: 8192 MiB
No downloads, Godot/Voxel Tools execution, host feature changes, host elevation, or writable host mapping.
Host feature query: $featureStatus

The guest will remain disposable. Canceling here leaves only the narrow approved input folder and this temporary .wsb file.
"@
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [System.Windows.Forms.MessageBox]::Show($scopeText, 'Review F2 Sandbox diagnostic launch', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    $approved = $answer -eq [System.Windows.Forms.DialogResult]::Yes
    if (-not $approved) {
        Write-Output "Launch canceled. Reviewed .wsb remains at: $configPath"
        exit 0
    }

    Assert-NoReparsePath -LiteralPath $configPath
    if (-not (Assert-LauncherTemplateHash -LiteralPath $configPath -ExpectedSha256 $expectedWsbSha256) -or
        (Get-NormalizedScriptHash $diagnosticPath) -ne $expectedDiagnosticSha256 -or
        (Get-NormalizedScriptHash $bootstrapPath) -ne $expectedBootstrapSha256) {
        throw 'A reviewed .wsb or staged script changed after owner confirmation; refusing launch.'
    }
    $sandboxProcess = Start-Process -FilePath $sandboxExe -ArgumentList ('"{0}"' -f $configPath) -PassThru -ErrorAction Stop
    Write-Output 'Windows Sandbox launch was requested with the reviewed diagnostic-only configuration.'
    Write-Output ('WindowsSandbox process id: {0}' -f $sandboxProcess.Id)
    Write-Output ('Configuration retained for review: {0}' -f $configPath)
    Write-Output 'The guest report is visible in the Sandbox window. A process launch is not proof that the guest or standard-user diagnostic succeeded.'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}

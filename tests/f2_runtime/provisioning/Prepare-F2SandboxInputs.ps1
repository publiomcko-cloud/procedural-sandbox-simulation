[CmdletBinding()]
param(
    [switch] $PrepareInputs,
    [switch] $Automation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$approvedHostFolder = 'C:\F2-Approved-Inputs'
$sandboxInputFolder = 'C:\F2Input'
$diagnosticName = 'Get-F2SandboxReadiness.ps1'
$bootstrapName = 'Start-F2SandboxDiagnostics.ps1'
$expectedDiagnosticSha256 = '78fa1dd2d0bc691cecdb5089ee409c71080d30fe0f0e928b2225c7d3bc745d9f'
$expectedBootstrapSha256 = '88cad4600e8417ab524728a27cd638b27b5f46fcf0c0495f7ff21e9cda80288e'
$previousReviewedBootstrapSha256 = @(
    '2bbb945e86274b98eda6b2c08eae156c0d2851f114c895f77505576991600093'
    '4a28b6d8a6b56239da131204316f441ab3a486d9bcb9a7bb7e3b4c77e36800f3'
)
$previousReviewedDiagnosticSha256 = @(
    'd3c6883d7b70d218968caa74ec2e0916406a6eb31d2075b45ab40cf15c07df65'
    '0664b0adfb511bda16bec900e92aad568eb50cc1cdba2cd9bdd35729cb1c164b'
    '5677f096eb78c2db08f5630e53a74c932719130ca0f7842ee8dca2ac2c0ff300'
)
$inputNames = if ($Automation) { @($diagnosticName, $bootstrapName) } else { @($diagnosticName) }
$diagnosticSource = Join-Path $PSScriptRoot $diagnosticName
$bootstrapSource = Join-Path $PSScriptRoot $bootstrapName
$wsbTemplateName = if ($Automation) { 'F2-Isolated-Sandbox-automation.wsb.example' } else { 'F2-Isolated-Sandbox.wsb.example' }
$wsbTemplate = Join-Path $PSScriptRoot $wsbTemplateName
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result {
    param([string] $Check, [ValidateSet('PASS', 'FAIL', 'UNKNOWN', 'NOT RUN')] [string] $Status, [string] $Detail)
    $results.Add([pscustomobject]@{ check = $Check; status = $Status; detail = $Detail })
}

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

function Assert-NoReparseComponent {
    param([Parameter(Mandatory)] [string] $LiteralPath)
    $resolved = [System.IO.Path]::GetFullPath($LiteralPath)
    $root = [System.IO.Path]::GetPathRoot($resolved)
    if ($resolved -eq $root) { throw "Refusing drive root: $resolved" }
    $cursor = $root
    foreach ($part in $resolved.Substring($root.Length).Split([System.IO.Path]::DirectorySeparatorChar, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $part
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing reparse point in approved path: $cursor"
            }
        }
    }
}

try {
    if ([System.IO.Path]::GetFullPath($approvedHostFolder) -ne $approvedHostFolder) {
        throw "Approved folder is not the fixed canonical path: $approvedHostFolder"
    }
    if ($approvedHostFolder -eq [System.IO.Path]::GetPathRoot($approvedHostFolder) -or
        $approvedHostFolder.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase) -or
        $approvedHostFolder -match '^[A-Za-z]:\\Dev\\sandbox-sim(?:-|\\|$)') {
        throw "The approved mapping path is a drive root, profile path, or project worktree: $approvedHostFolder"
    }
    Assert-NoReparseComponent -LiteralPath $approvedHostFolder
    Add-Result 'fixed_host_mapping_path' PASS $approvedHostFolder

    $sourceItem = Get-Item -LiteralPath $diagnosticSource -Force
    if ($sourceItem.PSIsContainer -or ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The diagnostic source must be a regular non-reparse file.'
    }
    $sourceBytes = [IO.File]::ReadAllBytes($diagnosticSource)
    if ($sourceBytes.Length -gt 65536 -or $sourceBytes -contains 0) { throw 'Diagnostic exceeds 64 KiB or contains NUL bytes.' }
    $sourceText = [Text.UTF8Encoding]::new($false, $true).GetString($sourceBytes)
    if ($sourceText -match '(?im)\b(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|DownloadFile|WebClient|HttpClient|Add-MpPreference|Set-MpPreference|Enable-WindowsOptionalFeature|Disable-WindowsOptionalFeature|Start-Process)\b') {
        throw 'Diagnostic contains a prohibited network, security-setting, feature-change, or child-process command.'
    }
    $sourceHash = Get-NormalizedScriptHash -LiteralPath $diagnosticSource
    if ($expectedDiagnosticSha256 -eq 'TO_BE_PINNED' -or $sourceHash -ne $expectedDiagnosticSha256) {
        throw "Diagnostic SHA-256 is not the reviewed pinned value. Observed: $sourceHash"
    }
    Add-Result 'diagnostic_source_identity' PASS ("$diagnosticSource SHA256=$sourceHash; UTF-8 plain text, $($sourceBytes.Length) bytes")

    if ($Automation) {
        $bootstrapItem = Get-Item -LiteralPath $bootstrapSource -Force
        if ($bootstrapItem.PSIsContainer -or ($bootstrapItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'The startup bootstrap must be a regular non-reparse file.'
        }
        $bootstrapBytes = [IO.File]::ReadAllBytes($bootstrapSource)
        if ($bootstrapBytes.Length -gt 65536 -or $bootstrapBytes -contains 0) { throw 'Startup bootstrap exceeds 64 KiB or contains NUL bytes.' }
        $bootstrapText = [Text.UTF8Encoding]::new($false, $true).GetString($bootstrapBytes)
        if ($bootstrapText -match '(?im)\b(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|DownloadFile|WebClient|HttpClient|Enable-WindowsOptionalFeature|Disable-WindowsOptionalFeature|Set-ExecutionPolicy)\b') {
            throw 'Startup bootstrap contains a prohibited network, feature-change, or persistent execution-policy command.'
        }
        $bootstrapHash = Get-NormalizedScriptHash -LiteralPath $bootstrapSource
        if ($bootstrapHash -eq 'TO_BE_PINNED' -or $bootstrapHash -ne $expectedBootstrapSha256) {
            throw "Startup bootstrap SHA-256 is not the reviewed pinned value. Observed: $bootstrapHash"
        }
        Add-Result 'bootstrap_source_identity' PASS ("$bootstrapSource SHA256=$bootstrapHash; UTF-8 plain text, $($bootstrapBytes.Length) bytes")
    }

    [xml] $config = Get-Content -LiteralPath $wsbTemplate -Raw
    $mapped = @($config.Configuration.MappedFolders.MappedFolder)
    $mappingElements = @($mapped[0].ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    $expectedMappingElements = @('HostFolder', 'SandboxFolder', 'ReadOnly')
    $logonCommand = 'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File C:\F2Input\Start-F2SandboxDiagnostics.ps1'
    $logonElements = @($config.Configuration.LogonCommand.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    $logonSafe = if ($Automation) {
        $logonElements.Count -eq 1 -and $logonElements[0] -eq 'Command' -and $config.Configuration.LogonCommand.Command -eq $logonCommand
    } else {
        $null -eq $config.Configuration.LogonCommand
    }
    $safeConfig = $config.Configuration.Networking -eq 'Disable' -and
        $config.Configuration.VGpu -eq 'Disable' -and
        $config.Configuration.ClipboardRedirection -eq 'Disable' -and
        $config.Configuration.ProtectedClient -eq 'Enable' -and
        $config.Configuration.AudioInput -eq 'Disable' -and
        $config.Configuration.VideoInput -eq 'Disable' -and
        $config.Configuration.PrinterRedirection -eq 'Disable' -and
        $config.Configuration.MemoryInMB -eq '8192' -and
        $logonSafe -and
        $mapped.Count -eq 1 -and
        (@($mappingElements | Where-Object { $_ -notin $expectedMappingElements }).Count -eq 0) -and
        $mappingElements.Count -eq $expectedMappingElements.Count -and
        $mapped[0].HostFolder -eq $approvedHostFolder -and
        $mapped[0].SandboxFolder -eq $sandboxInputFolder -and
        $mapped[0].ReadOnly -eq 'true'
    if (-not $safeConfig) { throw 'The .wsb template does not match the required network, clipboard, vGPU, ProtectedClient, and single read-only mapping settings.' }
    $allowedElements = @('VGpu', 'Networking', 'MappedFolders', 'AudioInput', 'VideoInput', 'ProtectedClient', 'PrinterRedirection', 'ClipboardRedirection', 'MemoryInMB')
    if ($Automation) { $allowedElements += 'LogonCommand' }
    $actualElements = @($config.Configuration.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    if ($actualElements.Count -ne $allowedElements.Count -or
        @($actualElements | Where-Object { $_ -notin $allowedElements }).Count -gt 0 -or
        @($actualElements | Select-Object -Unique).Count -ne $allowedElements.Count) {
        throw 'The .wsb contains an unreviewed, missing, or duplicated setting.'
    }
    if ($Automation) {
        $configDescription = 'Offline; clipboard/audio/video/printer/vGPU off; ProtectedClient on; one exact pinned diagnostic-only LogonCommand; one read-only mapping.'
    } else {
        $configDescription = 'Offline; clipboard/audio/video/printer/vGPU off; ProtectedClient on; no LogonCommand; one read-only mapping.'
    }
    Add-Result 'wsb_security_configuration' PASS $configDescription
    Add-Result 'resource_configuration' UNKNOWN 'MemoryInMB is a guest memory allocation only; this file does not enforce CPU, disk, or per-probe/session time limits.'

    $sandboxExe = Join-Path $env:WINDIR 'System32\WindowsSandbox.exe'
    if ((Test-Path -LiteralPath $sandboxExe -PathType Leaf) -and (Get-Command WindowsSandbox.exe -ErrorAction SilentlyContinue)) {
        Add-Result 'windows_sandbox_executable' PASS $sandboxExe
    } else {
        Add-Result 'windows_sandbox_executable' FAIL 'WindowsSandbox.exe was not found; do not alter Windows features from this script.'
    }

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -ErrorAction Stop
        Add-Result 'sandbox_optional_feature' $(if ($feature.State -eq 'Enabled') { 'PASS' } else { 'FAIL' }) ("Containers-DisposableClientVM state=$($feature.State); no feature change was requested.")
    } catch {
        Add-Result 'sandbox_optional_feature' UNKNOWN ("Could not read optional-feature state without elevation: $($_.Exception.Message)")
    }

    Add-Result 'wsb_opened' 'NOT RUN' 'This script never launches Windows Sandbox. Owner must use the printed manual command and observe the guest window.'

    if ($PrepareInputs) {
        if (@(Get-Process -Name WindowsSandbox -ErrorAction SilentlyContinue).Count -gt 0) {
            throw 'A WindowsSandbox process is active; refusing to change its mapped input folder.'
        }
        if (-not (Test-Path -LiteralPath $approvedHostFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $approvedHostFolder -ErrorAction Stop | Out-Null
        }
        Assert-NoReparseComponent -LiteralPath $approvedHostFolder
        $items = @(Get-ChildItem -LiteralPath $approvedHostFolder -Force)
        $unexpected = @($items | Where-Object { $_.Name -notin $inputNames })
        if ($unexpected.Count) { throw "Approved input folder contains unexpected entries; nothing was removed: $($unexpected.Name -join ', ')" }
        foreach ($name in $inputNames) {
            $source = Join-Path $PSScriptRoot $name
            $destination = Join-Path $approvedHostFolder $name
            $expectedHash = if ($name -eq $diagnosticName) { $expectedDiagnosticSha256 } else { $expectedBootstrapSha256 }
            if (Test-Path -LiteralPath $destination) {
                $existingItem = Get-Item -LiteralPath $destination -Force
                if ($existingItem.PSIsContainer -or ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Existing mapped input is not a regular file; refusing to follow or overwrite it: $name"
                }
                $existingHash = Get-NormalizedScriptHash -LiteralPath $destination
                $knownPrevious = if ($name -eq $diagnosticName) { $existingHash -in $previousReviewedDiagnosticSha256 } else { $existingHash -in $previousReviewedBootstrapSha256 }
                if ($existingHash -ne $expectedHash -and -not $knownPrevious) {
                    throw "Existing mapped input differs from reviewed content; refusing overwrite: $name SHA256=$existingHash"
                }
                if ($knownPrevious) {
                    Copy-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop
                }
            } else {
                Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
            }
            Assert-NoReparseComponent -LiteralPath $destination
            $copiedHash = Get-NormalizedScriptHash -LiteralPath $destination
            if ($copiedHash -ne $expectedHash) { throw "Copied input hash mismatch: $name SHA256=$copiedHash" }
        }
        $finalItems = @(Get-ChildItem -LiteralPath $approvedHostFolder -Force)
        if ($finalItems.Count -ne $inputNames.Count -or @($finalItems | Where-Object { $_.Name -notin $inputNames }).Count -gt 0) {
            throw 'Staged input folder does not contain exactly the reviewed script allowlist.'
        }
        Add-Result 'approved_input_staging' PASS ("Only reviewed inputs are present: $($inputNames -join ', ')")
    } else {
        Add-Result 'approved_input_staging' 'NOT RUN' 'Pass -PrepareInputs to create the fixed narrow folder and stage the pinned diagnostic script.'
    }
} catch {
    Add-Result 'preparation' FAIL $_.Exception.Message
}

$overall = if (@($results | Where-Object { $_.status -eq 'FAIL' }).Count) { 'FAIL' } else { 'OWNER_CHECK_REQUIRED' }
[pscustomobject]@{
    diagnostic = 'F2 host-side Sandbox input preparation; does not launch Sandbox or native code'
    timestamp_utc = [DateTime]::UtcNow.ToString('o')
    overall = $overall
    results = @($results)
    owner_follow_up = @(
        'Review the exact .wsb content and enablement state from Administrator PowerShell if not already confirmed.',
        'Open the .wsb manually and capture the visible guest; this script has not claimed the file opened.',
        $(if ($Automation) { 'The single reviewed LogonCommand runs the bootstrap; no guest typing is required.' } else { 'Inside the guest, run: & ''C:\F2Input\Get-F2SandboxReadiness.ps1''' }),
        'Keep guest Networking disabled and do not stage or run Godot/Voxel Tools as part of this readiness task.'
    )
} | ConvertTo-Json -Depth 8

if ($overall -eq 'FAIL') { exit 2 }
exit 0

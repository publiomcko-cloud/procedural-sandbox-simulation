[CmdletBinding()]
param(
    [switch] $PrepareInputs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$approvedHostFolder = 'C:\F2-Approved-Inputs'
$sandboxInputFolder = 'C:\F2Input'
$diagnosticName = 'Get-F2SandboxReadiness.ps1'
$expectedDiagnosticSha256 = '5677f096eb78c2db08f5630e53a74c932719130ca0f7842ee8dca2ac2c0ff300'
$previousReviewedDiagnosticSha256 = @(
    'd3c6883d7b70d218968caa74ec2e0916406a6eb31d2075b45ab40cf15c07df65'
    '0664b0adfb511bda16bec900e92aad568eb50cc1cdba2cd9bdd35729cb1c164b'
)
$diagnosticSource = Join-Path $PSScriptRoot $diagnosticName
$wsbTemplate = Join-Path $PSScriptRoot 'F2-Isolated-Sandbox.wsb.example'
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

    [xml] $config = Get-Content -LiteralPath $wsbTemplate -Raw
    $mapped = @($config.Configuration.MappedFolders.MappedFolder)
    $mappingElements = @($mapped[0].ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    $expectedMappingElements = @('HostFolder', 'SandboxFolder', 'ReadOnly')
    $safeConfig = $config.Configuration.Networking -eq 'Disable' -and
        $config.Configuration.VGpu -eq 'Disable' -and
        $config.Configuration.ClipboardRedirection -eq 'Disable' -and
        $config.Configuration.ProtectedClient -eq 'Enable' -and
        $config.Configuration.AudioInput -eq 'Disable' -and
        $config.Configuration.VideoInput -eq 'Disable' -and
        $config.Configuration.PrinterRedirection -eq 'Disable' -and
        $config.Configuration.MemoryInMB -eq '8192' -and
        @($config.Configuration.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element -and $_.Name -eq 'LogonCommand' }).Count -eq 0 -and
        $mapped.Count -eq 1 -and
        (@($mappingElements | Where-Object { $_ -notin $expectedMappingElements }).Count -eq 0) -and
        $mappingElements.Count -eq $expectedMappingElements.Count -and
        $mapped[0].HostFolder -eq $approvedHostFolder -and
        $mapped[0].SandboxFolder -eq $sandboxInputFolder -and
        $mapped[0].ReadOnly -eq 'true'
    if (-not $safeConfig) { throw 'The .wsb template does not match the required network, clipboard, vGPU, ProtectedClient, and single read-only mapping settings.' }
    $allowedElements = @('VGpu', 'Networking', 'MappedFolders', 'AudioInput', 'VideoInput', 'ProtectedClient', 'PrinterRedirection', 'ClipboardRedirection', 'MemoryInMB')
    $actualElements = @($config.Configuration.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    if ($actualElements.Count -ne $allowedElements.Count -or
        @($actualElements | Where-Object { $_ -notin $allowedElements }).Count -gt 0 -or
        @($actualElements | Select-Object -Unique).Count -ne $allowedElements.Count) {
        throw 'The .wsb contains an unreviewed, missing, or duplicated setting.'
    }
    Add-Result 'wsb_security_configuration' PASS 'Offline; clipboard/audio/video/printer/vGPU off; ProtectedClient on; no LogonCommand; one read-only C:\F2-Approved-Inputs to C:\F2Input mapping.'
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
        if (-not (Test-Path -LiteralPath $approvedHostFolder -PathType Container)) {
            New-Item -ItemType Directory -Path $approvedHostFolder -ErrorAction Stop | Out-Null
        }
        Assert-NoReparseComponent -LiteralPath $approvedHostFolder
        $items = @(Get-ChildItem -LiteralPath $approvedHostFolder -Force)
        $unexpected = @($items | Where-Object { $_.Name -ne $diagnosticName })
        if ($unexpected.Count) { throw "Approved input folder contains unexpected entries; nothing was removed: $($unexpected.Name -join ', ')" }
        $destination = Join-Path $approvedHostFolder $diagnosticName
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $existingItem = Get-Item -LiteralPath $destination -Force
            if ($existingItem.PSIsContainer -or ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Existing mapped diagnostic is not a regular file; refusing to follow or overwrite it.'
            }
            $existingHash = Get-NormalizedScriptHash -LiteralPath $destination
            if ($existingHash -ne $expectedDiagnosticSha256 -and $existingHash -notin $previousReviewedDiagnosticSha256) {
                throw "Existing mapped diagnostic differs from all reviewed versions; refusing overwrite. SHA256=$existingHash"
            }
            if ($existingHash -in $previousReviewedDiagnosticSha256) {
                Copy-Item -LiteralPath $diagnosticSource -Destination $destination -Force -ErrorAction Stop
            }
        } else {
            Copy-Item -LiteralPath $diagnosticSource -Destination $destination -ErrorAction Stop
        }
        Assert-NoReparseComponent -LiteralPath $destination
        $copiedHash = Get-NormalizedScriptHash -LiteralPath $destination
        if ($copiedHash -ne $expectedDiagnosticSha256) { throw "Copied diagnostic hash mismatch: $copiedHash" }
        Add-Result 'approved_input_staging' PASS ("Only $diagnosticName is present; SHA256=$copiedHash")
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
        'Inside the guest, run: & ''C:\F2Input\Get-F2SandboxReadiness.ps1''',
        'Keep guest Networking disabled and do not stage or run Godot/Voxel Tools as part of this readiness task.'
    )
} | ConvertTo-Json -Depth 8

if ($overall -eq 'FAIL') { exit 2 }
exit 0

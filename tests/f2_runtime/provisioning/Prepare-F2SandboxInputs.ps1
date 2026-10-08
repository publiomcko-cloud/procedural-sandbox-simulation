[CmdletBinding()]
param(
    [switch] $PrepareInputs,
    [switch] $Automation,
    [switch] $SourceOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$approvedHostFolder = 'C:\F2-Approved-Inputs'
$sandboxInputFolder = 'C:\F2Input'
$diagnosticName = 'Get-F2SandboxReadiness.ps1'
$bootstrapName = 'Start-F2SandboxDiagnostics.ps1'
$wrapperName = 'F2-Guest-Diagnostic.cmd'
$expectedDiagnosticSha256 = '78fa1dd2d0bc691cecdb5089ee409c71080d30fe0f0e928b2225c7d3bc745d9f'
$expectedBootstrapSha256 = 'ac8f5952b4138c774a5193f1b5eba0abef6abca961a9573e208296812933ab0e'
$expectedWsbSha256 = '368d5bed7093504e7cbfbae3fc830b536b5f8f42e12f363537b2ac8697ece652'
$expectedWrapperSha256 = 'a53cbc9a0c5565bbf182c794f31d4ba24a8a94bd181e11e0bdf15e55aa75ca89'
$previousReviewedBootstrapSha256 = @(
    '2bbb945e86274b98eda6b2c08eae156c0d2851f114c895f77505576991600093'
    '4a28b6d8a6b56239da131204316f441ab3a486d9bcb9a7bb7e3b4c77e36800f3'
    '88cad4600e8417ab524728a27cd638b27b5f46fcf0c0495f7ff21e9cda80288e'
)
$previousReviewedDiagnosticSha256 = @(
    'd3c6883d7b70d218968caa74ec2e0916406a6eb31d2075b45ab40cf15c07df65'
    '0664b0adfb511bda16bec900e92aad568eb50cc1cdba2cd9bdd35729cb1c164b'
    '5677f096eb78c2db08f5630e53a74c932719130ca0f7842ee8dca2ac2c0ff300'
)
$inputNames = if ($Automation) { @($diagnosticName, $bootstrapName, $wrapperName) } else { @($diagnosticName) }
$diagnosticSource = Join-Path $PSScriptRoot $diagnosticName
$bootstrapSource = Join-Path $PSScriptRoot $bootstrapName
$wrapperSource = Join-Path $PSScriptRoot $wrapperName
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

function Assert-PreparerTemplateHash {
    param([Parameter(Mandatory)] [string] $LiteralPath, [Parameter(Mandatory)] [string] $ExpectedSha256)
    if ((Get-NormalizedScriptHash -LiteralPath $LiteralPath) -ne $ExpectedSha256) {
        throw 'Automation .wsb SHA-256 is not the reviewed pinned value.'
    }
    return $true
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

function Assert-PreparerSandboxConfiguration {
    param(
        [Parameter(Mandatory)] [xml] $Configuration,
        [Parameter(Mandatory)] [bool] $Automation,
        [Parameter(Mandatory)] [string] $ApprovedHostFolder,
        [Parameter(Mandatory)] [string] $SandboxInputFolder,
        [Parameter(Mandatory)] [string] $ExpectedCommand
    )
    $mappedFolders = @($Configuration.Configuration.MappedFolders.MappedFolder)
    $mappingElements = @($mappedFolders[0].ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    $expectedMappingElements = @('HostFolder', 'SandboxFolder', 'ReadOnly')
    $logonElements = @($Configuration.Configuration.LogonCommand.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    $logonSafe = if ($Automation) {
        $logonElements.Count -eq 1 -and $logonElements[0] -eq 'Command' -and $Configuration.Configuration.LogonCommand.Command -eq $ExpectedCommand
    } else {
        $null -eq $Configuration.Configuration.LogonCommand
    }
    $safeConfig = $Configuration.Configuration.Networking -eq 'Disable' -and
        $Configuration.Configuration.VGpu -eq 'Disable' -and
        $Configuration.Configuration.ClipboardRedirection -eq 'Disable' -and
        $Configuration.Configuration.ProtectedClient -eq 'Enable' -and
        $Configuration.Configuration.AudioInput -eq 'Disable' -and
        $Configuration.Configuration.VideoInput -eq 'Disable' -and
        $Configuration.Configuration.PrinterRedirection -eq 'Disable' -and
        $Configuration.Configuration.MemoryInMB -eq '8192' -and
        $logonSafe -and
        $mappedFolders.Count -eq 1 -and
        (@($mappingElements | Where-Object { $_ -notin $expectedMappingElements }).Count -eq 0) -and
        $mappingElements.Count -eq $expectedMappingElements.Count -and
        $mappedFolders[0].HostFolder -eq $ApprovedHostFolder -and
        $mappedFolders[0].SandboxFolder -eq $SandboxInputFolder -and
        $mappedFolders[0].ReadOnly -eq 'true'
    if (-not $safeConfig) { throw 'The .wsb template does not match the required network, clipboard, vGPU, ProtectedClient, and single read-only mapping settings.' }
    $allowedElements = @('VGpu', 'Networking', 'MappedFolders', 'AudioInput', 'VideoInput', 'ProtectedClient', 'PrinterRedirection', 'ClipboardRedirection', 'MemoryInMB')
    if ($Automation) { $allowedElements += 'LogonCommand' }
    $actualElements = @($Configuration.Configuration.ChildNodes | Where-Object { $_.NodeType -eq [Xml.XmlNodeType]::Element } | ForEach-Object { $_.Name })
    if ($actualElements.Count -ne $allowedElements.Count -or
        @($actualElements | Where-Object { $_ -notin $allowedElements }).Count -gt 0 -or
        @($actualElements | Select-Object -Unique).Count -ne $allowedElements.Count) {
        throw 'The .wsb contains an unreviewed, missing, or duplicated setting.'
    }
    if ($Automation) {
        return 'Offline; clipboard/audio/video/printer/vGPU off; ProtectedClient on; one exact pinned diagnostic-only LogonCommand; one read-only mapping.'
    }
    return 'Offline; clipboard/audio/video/printer/vGPU off; ProtectedClient on; no LogonCommand; one read-only mapping.'
}

try {
    if ($SourceOnly -and (-not $Automation -or $PrepareInputs)) { throw 'SourceOnly is restricted to diagnostic-only automation source validation without staging.' }
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
        $wrapperItem = Get-Item -LiteralPath $wrapperSource -Force
        if ($wrapperItem.PSIsContainer -or ($wrapperItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Guest CMD startup wrapper must be a regular non-reparse file.'
        }
        $wrapperBytes = [IO.File]::ReadAllBytes($wrapperSource)
        if ($wrapperBytes.Length -gt 16384 -or $wrapperBytes -contains 0 -or @($wrapperBytes | Where-Object { $_ -gt 127 }).Count -gt 0) {
            throw 'Guest CMD startup wrapper must be ASCII plain text under 16 KiB without NUL.'
        }
        $wrapperHash = Get-NormalizedScriptHash -LiteralPath $wrapperSource
        if ($wrapperHash -ne $expectedWrapperSha256) { throw "Guest CMD wrapper SHA-256 mismatch: $wrapperHash" }
        Add-Result 'wrapper_source_identity' PASS ("$wrapperSource SHA256=$wrapperHash")
    }

    [xml] $config = Get-Content -LiteralPath $wsbTemplate -Raw

    $logonCommand = 'C:\F2Input\F2-Guest-Diagnostic.cmd'
    $configDescription = Assert-PreparerSandboxConfiguration -Configuration $config -Automation ([bool]$Automation) -ApprovedHostFolder $approvedHostFolder -SandboxInputFolder $sandboxInputFolder -ExpectedCommand $logonCommand
    if ($Automation) {
        $wsbHash = Get-NormalizedScriptHash -LiteralPath $wsbTemplate
        Assert-PreparerTemplateHash -LiteralPath $wsbTemplate -ExpectedSha256 $expectedWsbSha256 | Out-Null
        Add-Result 'automation_configuration_identity' PASS ("$wsbTemplate SHA256=$wsbHash")
    } else {
        # Non-automation mappings intentionally have no LogonCommand.
    }
    Add-Result 'wsb_security_configuration' PASS $configDescription
    Add-Result 'resource_configuration' UNKNOWN 'MemoryInMB is a guest memory allocation only; this file does not enforce CPU, disk, or per-probe/session time limits.'

    if ($SourceOnly) {
        Add-Result 'windows_sandbox_executable' UNKNOWN 'SourceOnly fixture: OS Sandbox executable deliberately NOT CHECKED.'
        Add-Result 'sandbox_optional_feature' UNKNOWN 'SourceOnly fixture: optional feature deliberately NOT CHECKED.'
    } else {
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
            $expectedHash = if ($name -eq $diagnosticName) { $expectedDiagnosticSha256 } elseif ($name -eq $bootstrapName) { $expectedBootstrapSha256 } else { $expectedWrapperSha256 }
            if (Test-Path -LiteralPath $destination) {
                $existingItem = Get-Item -LiteralPath $destination -Force
                if ($existingItem.PSIsContainer -or ($existingItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Existing mapped input is not a regular file; refusing to follow or overwrite it: $name"
                }
                $existingHash = Get-NormalizedScriptHash -LiteralPath $destination
                $knownPrevious = if ($name -eq $diagnosticName) { $existingHash -in $previousReviewedDiagnosticSha256 } elseif ($name -eq $bootstrapName) { $existingHash -in $previousReviewedBootstrapSha256 } else { $false }
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

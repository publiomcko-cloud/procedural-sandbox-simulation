[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRoot = $PSScriptRoot
$tempRoot = [IO.Path]::GetFullPath($env:TEMP)
$fixtureRoot = Join-Path $tempRoot ("F2-Sandbox-Automation-Test-{0}" -f [guid]::NewGuid().ToString('N'))
$fixtureProvisioning = Join-Path $fixtureRoot 'provisioning'
$assertions = 0
$failures = 0

function Assert-True {
    param([bool] $Condition, [string] $Message)
    $script:assertions++
    if (-not $Condition) {
        $script:failures++
        Write-Error "FAIL: $Message"
    } else { Write-Output "PASS: $Message" }
}

function Invoke-HostFixture {
    param([string] $Description, [int] $ExpectedExitCode)
    $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureProvisioning 'Prepare-F2SandboxInputs.ps1') -Automation 2>&1 | Out-String
    $actualExitCode = $LASTEXITCODE
    if ($actualExitCode -eq $ExpectedExitCode) {
        Assert-True $true ("{0}: exit {1}" -f $Description, $actualExitCode)
    } else {
        Write-Output $output
        Assert-True $false ("{0}: exit {1} (expected {2})" -f $Description, $actualExitCode, $ExpectedExitCode)
    }
}

try {
    New-Item -ItemType Directory -Path $fixtureProvisioning -ErrorAction Stop | Out-Null
    foreach ($name in @(
        'Prepare-F2SandboxInputs.ps1',
        'Get-F2SandboxReadiness.ps1',
        'Start-F2SandboxDiagnostics.ps1',
        'F2-Isolated-Sandbox-automation.wsb.example'
    )) {
        Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $fixtureProvisioning $name) -ErrorAction Stop
    }

    foreach ($name in @('Prepare-F2SandboxInputs.ps1', 'Get-F2SandboxReadiness.ps1', 'Start-F2SandboxDiagnostics.ps1', 'Start-F2SandboxReadiness.ps1', 'Test-F2SandboxAutomation.ps1')) {
        $path = Join-Path $sourceRoot $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $tokens = $null
            $parseErrors = $null
            [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
            Assert-True ($parseErrors.Count -eq 0) ("PowerShell AST parse: {0}" -f $name)
        }
    }

    $bootstrapPath = Join-Path $sourceRoot 'Start-F2SandboxDiagnostics.ps1'
    $bootstrapText = Get-Content -LiteralPath $bootstrapPath -Raw
    Assert-True ($bootstrapText -match '(?m)^\s*\$randomBytes\s*=\s*New-Object byte\[\]\s+6\s*$') 'Username suffix uses six cryptographic random bytes (12 hexadecimal characters)'
    Assert-True ($bootstrapText -match '(?m)^\s*Assert-GuestDiagnosticUsername\s+-Name\s+\$username\s*$') 'Generated username is explicitly length-validated before account creation'
    $bootstrapTokens = $null
    $bootstrapParseErrors = $null
    $bootstrapAst = [Management.Automation.Language.Parser]::ParseFile($bootstrapPath, [ref]$bootstrapTokens, [ref]$bootstrapParseErrors)
    $usernameValidator = @($bootstrapAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-GuestDiagnosticUsername' }, $false))
    Assert-True ($usernameValidator.Count -eq 1) 'Username validator is uniquely defined in the source'
    if ($usernameValidator.Count -eq 1) {
        Invoke-Expression $usernameValidator[0].Extent.Text
        $validUsernameAccepted = $false
        try { Assert-GuestDiagnosticUsername -Name 'F2Diag_012345ABCDEF'; $validUsernameAccepted = $true } catch {}
        Assert-True $validUsernameAccepted 'Accept bounded 19-character diagnostic username'
        $oversizedUsernameRejected = $false
        try { Assert-GuestDiagnosticUsername -Name 'F2Diag_0123456789ABCDEF' } catch { $oversizedUsernameRejected = $true }
        Assert-True $oversizedUsernameRejected 'Reject 23-character diagnostic username'
        $malformedUsernameRejected = $false
        try { Assert-GuestDiagnosticUsername -Name 'F2Diag_not-hex' } catch { $malformedUsernameRejected = $true }
        Assert-True $malformedUsernameRejected 'Reject malformed diagnostic username'
    }

    Invoke-HostFixture -Description 'Reviewed offline automation template and pinned scripts' -ExpectedExitCode 0

    $diagnostic = Join-Path $fixtureProvisioning 'Get-F2SandboxReadiness.ps1'
    Add-Content -LiteralPath $diagnostic -Value "`n# tampered input fixture" -Encoding utf8
    Invoke-HostFixture -Description 'Reject altered diagnostic digest' -ExpectedExitCode 2
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'Get-F2SandboxReadiness.ps1') -Destination $diagnostic -Force

    $configPath = Join-Path $fixtureProvisioning 'F2-Isolated-Sandbox-automation.wsb.example'
    $configText = Get-Content -LiteralPath $configPath -Raw
    Set-Content -LiteralPath $configPath -Value $configText.Replace('<ReadOnly>true</ReadOnly>', '<ReadOnly>false</ReadOnly>') -Encoding utf8
    Invoke-HostFixture -Description 'Reject writable host mapping' -ExpectedExitCode 2
    Set-Content -LiteralPath $configPath -Value $configText -Encoding utf8

    Set-Content -LiteralPath $configPath -Value $configText.Replace(' -File C:\F2Input\Start-F2SandboxDiagnostics.ps1', ' -File C:\F2Input\Unreviewed.ps1') -Encoding utf8
    Invoke-HostFixture -Description 'Reject unreviewed LogonCommand' -ExpectedExitCode 2

    Write-Output ("SUMMARY: {0} assertions, {1} failures" -f $assertions, $failures)
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolvedFixture.StartsWith($tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedFixture).StartsWith('F2-Sandbox-Automation-Test-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures -gt 0) { exit 1 }
exit 0

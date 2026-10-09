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
    $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureProvisioning 'Prepare-F2SandboxInputs.ps1') -Automation -SourceOnly 2>&1 | Out-String
    $actualExitCode = $LASTEXITCODE
    if ($actualExitCode -eq $ExpectedExitCode) {
        Assert-True $true ("{0}: exit {1}" -f $Description, $actualExitCode)
    } else {
        Write-Output $output
        Assert-True $false ("{0}: exit {1} (expected {2})" -f $Description, $actualExitCode, $ExpectedExitCode)
    }
}

function Get-NormalizedSourceHash {
    param([Parameter(Mandatory)] [string] $LiteralPath)
    $text = [Text.UTF8Encoding]::new($false, $true).GetString([IO.File]::ReadAllBytes($LiteralPath))
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash([Text.UTF8Encoding]::new($false).GetBytes($text))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Set-FixtureWsbPin {
    $fixtureWsb = Join-Path $fixtureProvisioning 'F2-Isolated-Sandbox-automation.wsb.example'
    $fixturePreparer = Join-Path $fixtureProvisioning 'Prepare-F2SandboxInputs.ps1'
    $hash = Get-NormalizedSourceHash -LiteralPath $fixtureWsb
    $preparerText = [IO.File]::ReadAllText($fixturePreparer)
    $pattern = '(?m)^[ \t]*\$expectedWsbSha256[ \t]*=[ \t]*''[0-9a-f]{64}''[ \t]*\r?$'
    $match = [regex]::Match($preparerText, $pattern)
    if (-not $match.Success) { throw 'Fixture preparer SHA pin was not found.' }
    $replacement = '$expectedWsbSha256 = ''{0}''' -f $hash
    $preparerText = $preparerText.Substring(0, $match.Index) + $replacement + $preparerText.Substring($match.Index + $match.Length)
    [IO.File]::WriteAllText($fixturePreparer, $preparerText, [Text.UTF8Encoding]::new($false))
}

try {
    New-Item -ItemType Directory -Path $fixtureProvisioning -ErrorAction Stop | Out-Null
    foreach ($name in @(
        'Prepare-F2SandboxInputs.ps1',
        'Get-F2SandboxReadiness.ps1',
        'Start-F2SandboxDiagnostics.ps1',
        'F2-Guest-Diagnostic.cmd',
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

    $reportFunctions = @('Write-Report', 'Test-VerifiedStandardUserToken')
    foreach ($functionName in $reportFunctions) {
        $functionAst = @($bootstrapAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $false))
        Assert-True ($functionAst.Count -eq 1) ("Source-only report helper exists exactly once: {0}" -f $functionName)
        if ($functionAst.Count -eq 1) { Invoke-Expression $functionAst[0].Extent.Text }
    }

    $validToken = [pscustomobject]@{ identity = 'Sandbox\F2Diag_012345ABCDEF'; is_administrator = $false; token_status = 'PASS' }
    $deniedToken = [pscustomobject]@{ identity = 'Sandbox\F2Diag_012345ABCDEF'; is_administrator = $true; token_status = 'FAIL' }
    Assert-True (Test-VerifiedStandardUserToken -Result $validToken -ExpectedIdentity 'Sandbox\F2Diag_012345ABCDEF') 'Accept only exact verified standard-user token'
    Assert-True (-not (Test-VerifiedStandardUserToken -Result $deniedToken -ExpectedIdentity 'Sandbox\F2Diag_012345ABCDEF')) 'Reject denied or administrator child token without fallback'
    Assert-True ($bootstrapText -match '(?s)\$stage\s*=\s*''validate read-only mapped diagnostic''.*?Test-Path -LiteralPath \$diagnosticPath') 'Missing mapped diagnostic fails at a visible preflight stage'
    Assert-True ($bootstrapText -notmatch '(?im)^\s*Start-Sleep\b') 'Bootstrap does not depend on a timed sleep to keep the report visible'
    Assert-True ($bootstrapText -match '(?im)Start-Process\s+-FilePath\s+\$powershellPath\s+-Credential\s+\$credential') 'Only credential-bound standard-user child launch is present'
    Assert-True ($bootstrapText -notmatch '(?i)Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|DownloadFile|Godot|Voxel.?Tools|GDExtension|GDNative') 'Bootstrap has no network or vendor-runtime path'

    $reportCases = @(
        @{ Name = 'early bootstrap failure'; Stage = 'validate read-only mapped diagnostic'; Status = 'BLOCKED_ENVIRONMENT'; Category = 'ObjectNotFound/ItemNotFoundException'; ExitCode = $null }
        @{ Name = 'denied standard-user child'; Stage = 'launch readiness diagnostic under standard-user credential'; Status = 'BLOCKED_STANDARD_USER'; Category = 'SecurityError/StartProcessDenied'; ExitCode = $null }
        @{ Name = 'standard-user child timeout'; Stage = 'wait for standard-user diagnostic (60-second timeout)'; Status = 'BLOCKED_STANDARD_USER'; Category = 'OperationTimeout'; ExitCode = $null }
        @{ Name = 'malformed child JSON'; Stage = 'parse standard-user diagnostic result'; Status = 'BLOCKED_STANDARD_USER'; Category = 'InvalidData/ConvertFromJson'; ExitCode = 1 }
        @{ Name = 'missing mapped input'; Stage = 'validate read-only mapped diagnostic'; Status = 'BLOCKED_ENVIRONMENT'; Category = 'ObjectNotFound/ItemNotFoundException'; ExitCode = $null }
    )
    foreach ($case in $reportCases) {
        $stage = $case.Stage
        $failureCategory = $case.Category
        $diagnosticExitCode = $case.ExitCode
        $summary = $null
        $report = Write-Report -Status $case.Status -Message 'Startup or diagnostic stage failed.' | Out-String
        Assert-True ($report.Contains($case.Status) -and $report.Contains($case.Stage) -and $report.Contains($case.Category)) ("Failure remains visible with stage/category: {0}" -f $case.Name)
        Assert-True ($report.Contains('F2 native runtime: NOT RUN') -and $report.Contains('window remains open')) ("Failure report stays open and diagnostic-only: {0}" -f $case.Name)
        if ($null -ne $case.ExitCode) { Assert-True ($report.Contains('exit code: 1')) 'Malformed/nonzero child failure reports exit code' }
    }

    $configPath = Join-Path $fixtureProvisioning 'F2-Isolated-Sandbox-automation.wsb.example'
    [xml]$startupConfig = Get-Content -LiteralPath $configPath -Raw
    $startupCommand = [string]$startupConfig.Configuration.LogonCommand.Command
    Assert-True ($startupCommand -eq 'C:\F2Input\F2-Guest-Diagnostic.cmd') 'WSB invokes only the pinned mapped CMD entrypoint without nested console quotation'
    $wrapperPath = Join-Path $sourceRoot 'F2-Guest-Diagnostic.cmd'
    $wrapperText = Get-Content -LiteralPath $wrapperPath -Raw
    Assert-True ($wrapperText.Contains('F2 GUEST WRAPPER STARTED') -and $wrapperText.Contains('F2 STAGE: CMD_ENTRY')) 'Immediate pre-PowerShell wrapper banner exists'
    Assert-True ($wrapperText.Contains('if /i "%~1"=="--f2-visible" goto :visible_diagnostic')) 'Wrapper accepts only the explicitly designated visible child path'
    Assert-True ($wrapperText.Contains('if not "%~1"=="" exit /b 2')) 'Wrapper refuses unexpected startup parameters'
    Assert-True ($wrapperText.Contains('start "F2 Sandbox Diagnostic" "%SystemRoot%\System32\cmd.exe" /k C:\F2Input\F2-Guest-Diagnostic.cmd --f2-visible')) 'Original LogonCommand explicitly starts a distinct persistent visible console'
    Assert-True ($wrapperText.Contains('exit /b %ERRORLEVEL%') -and $wrapperText.Contains(':visible_diagnostic')) 'Hidden LogonCommand returns without executing guest account bootstrap in the hidden parent'
    Assert-True ($wrapperText.IndexOf(':visible_diagnostic') -lt $wrapperText.IndexOf('F2 GUEST WRAPPER STARTED')) 'Stage-zero banner executes only in separate visible child'
    Assert-True ($wrapperText -notmatch '(?im)^\s*start\s+(/b|/min|/wait)\b') 'Startup does not suppress foreground window or wait for it to exit'
    Assert-True ($wrapperText.IndexOf('F2 GUEST WRAPPER STARTED') -lt $wrapperText.IndexOf(' -ExecutionPolicy Bypass -File')) 'CMD banner executes before PowerShell call'
    Assert-True ($wrapperText.Contains('if not exist "C:\F2Input\Start-F2SandboxDiagnostics.ps1" goto :missing_bootstrap')) 'Missing mapped bootstrap has visible fail-closed path'
    Assert-True ($wrapperText.Contains('F2 PowerShell process exit code: %F2_PS_EXIT%')) 'Guest wrapper exposes PowerShell exit code without reporting readiness PASS'
    Assert-True ($wrapperText -notmatch '(?i)Invoke-WebRequest|curl|wget|Godot|Voxel.?Tools|GDExtension|GDNative|net user') 'CMD wrapper contains no native/network/user mutation commands'


    $launcherPath = Join-Path $sourceRoot 'Start-F2SandboxReadiness.ps1'
    $launcherText = Get-Content $launcherPath -Raw
    $sourcePreparerText = Get-Content (Join-Path $sourceRoot 'Prepare-F2SandboxInputs.ps1') -Raw
    $bootstrapPinMatch = [regex]::Match($sourcePreparerText, '(?m)^[ \t]*\$expectedBootstrapSha256[ \t]*=[ \t]*''([0-9a-f]{64})''[ \t]*\r?$')
    $wsbPinMatch = [regex]::Match($sourcePreparerText, '(?m)^[ \t]*\$expectedWsbSha256[ \t]*=[ \t]*''([0-9a-f]{64})''[ \t]*\r?$')
    Assert-True ($bootstrapPinMatch.Success -and $wsbPinMatch.Success) 'Bootstrap and WSB SHA256 pins are declared and anchored in the production preparer'
    $expectedBootstrapHash = $bootstrapPinMatch.Groups[1].Value
    $expectedWsbHash = $wsbPinMatch.Groups[1].Value
    $launcherCommandMatch = [regex]::Match($launcherText, '(?m)^[ \t]*\$expectedCommand[ \t]*=[ \t]*''(.*)''[ \t]*\r?$')
    $preparerCommandMatch = [regex]::Match($sourcePreparerText, '(?m)^[ \t]*\$logonCommand[ \t]*=[ \t]*''(.*)''[ \t]*\r?$')
    Assert-True ($launcherCommandMatch.Success -and $preparerCommandMatch.Success) 'Both production validators declare an exact LogonCommand'
    if ($launcherCommandMatch.Success -and $preparerCommandMatch.Success) {
        $launcherExpectedCommand = $launcherCommandMatch.Groups[1].Value.Replace("''", "'")
        $preparerExpectedCommand = $preparerCommandMatch.Groups[1].Value.Replace("''", "'")
        Assert-True ($launcherExpectedCommand -eq $startupCommand -and $preparerExpectedCommand -eq $startupCommand -and $launcherExpectedCommand -eq $preparerExpectedCommand) 'Host launcher and preparer allow exactly the parsed approved .wsb command'
    }

    $launcherAstTokens = $null
    $launcherAstErrors = $null
    $launcherAst = [Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$launcherAstTokens, [ref]$launcherAstErrors)
    $launcherValidatorAst = @($launcherAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-LauncherAutomationConfiguration' }, $false))
    $launcherHashAst = @($launcherAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-LauncherTemplateHash' }, $false))
    $launcherNormalizerAst = @($launcherAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-NormalizedScriptHash' }, $false))
    $preparerAstTokens = $null
    $preparerAstErrors = $null
    $preparerAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $sourceRoot 'Prepare-F2SandboxInputs.ps1'), [ref]$preparerAstTokens, [ref]$preparerAstErrors)
    $preparerValidatorAst = @($preparerAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-PreparerSandboxConfiguration' }, $false))
    $preparerHashAst = @($preparerAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Assert-PreparerTemplateHash' }, $false))
    Assert-True ($launcherValidatorAst.Count -eq 1 -and $preparerValidatorAst.Count -eq 1 -and $launcherHashAst.Count -eq 1 -and $preparerHashAst.Count -eq 1 -and $launcherNormalizerAst.Count -eq 1) 'Production launcher and preparer config/hash validators are source-addressable for fixture checks'
    if ($launcherValidatorAst.Count -eq 1 -and $preparerValidatorAst.Count -eq 1 -and $launcherHashAst.Count -eq 1 -and $preparerHashAst.Count -eq 1 -and $launcherNormalizerAst.Count -eq 1 -and $launcherCommandMatch.Success -and $preparerCommandMatch.Success) {
        Invoke-Expression $launcherNormalizerAst[0].Extent.Text
        Invoke-Expression $launcherHashAst[0].Extent.Text
        Invoke-Expression $preparerHashAst[0].Extent.Text
        Invoke-Expression $launcherValidatorAst[0].Extent.Text
        Invoke-Expression $preparerValidatorAst[0].Extent.Text
        $validAcceptedByLauncher = $false
        $validAcceptedByPreparer = $false
        try { $validAcceptedByLauncher = Assert-LauncherAutomationConfiguration -Configuration $startupConfig -ExpectedCommand $launcherExpectedCommand -ApprovedHostFolder 'C:\F2-Approved-Inputs' } catch {}
        try { $validAcceptedByPreparer = [bool](Assert-PreparerSandboxConfiguration -Configuration $startupConfig -Automation $true -ApprovedHostFolder 'C:\F2-Approved-Inputs' -SandboxInputFolder 'C:\F2Input' -ExpectedCommand $preparerExpectedCommand) } catch {}
        Assert-True ($validAcceptedByLauncher -and $validAcceptedByPreparer) 'Actual host launcher and host preparer validators both accept the approved configuration'
        $launcherHashAccepted = Assert-LauncherTemplateHash -LiteralPath $configPath -ExpectedSha256 $expectedWsbHash
        $preparerHashAccepted = Assert-PreparerTemplateHash -LiteralPath $configPath -ExpectedSha256 $expectedWsbHash
        Assert-True ($launcherHashAccepted -and $preparerHashAccepted) 'Actual host launcher and host preparer hash validators accept the approved configuration'

        $modifiedConfigs = @(
            @{ Name = 'writable mapping'; Xml = [xml]($startupConfig.OuterXml.Replace('<ReadOnly>true</ReadOnly>', '<ReadOnly>false</ReadOnly>')) }
            @{ Name = 'unreviewed command'; Xml = [xml]($startupConfig.OuterXml.Replace('F2-Guest-Diagnostic.cmd', 'Unreviewed.cmd')) }
            @{ Name = 'unexpected direct PowerShell startup'; Xml = [xml]($startupConfig.OuterXml.Replace('C:\F2Input\F2-Guest-Diagnostic.cmd', 'powershell.exe')) }
            @{ Name = 'modified CMD wrapper path'; Xml = [xml]($startupConfig.OuterXml.Replace('F2-Guest-Diagnostic.cmd', 'Unreviewed-Guest.cmd')) }
            @{ Name = 'additional LogonCommand'; Xml = [xml]($startupConfig.OuterXml.Replace('</LogonCommand>', '<Command>unreviewed.exe</Command></LogonCommand>')) }
        )
        foreach ($modified in $modifiedConfigs) {
            Assert-True ($modified.Xml.OuterXml -ne $startupConfig.OuterXml) ("Negative fixture actually modifies approved XML: {0}" -f $modified.Name)
            $launcherRejected = $false
            $preparerRejected = $false
            try { Assert-LauncherAutomationConfiguration -Configuration $modified.Xml -ExpectedCommand $launcherExpectedCommand -ApprovedHostFolder 'C:\F2-Approved-Inputs' | Out-Null } catch { $launcherRejected = $true }
            try { Assert-PreparerSandboxConfiguration -Configuration $modified.Xml -Automation $true -ApprovedHostFolder 'C:\F2-Approved-Inputs' -SandboxInputFolder 'C:\F2Input' -ExpectedCommand $preparerExpectedCommand | Out-Null } catch { $preparerRejected = $true }
            Assert-True ($launcherRejected -and $preparerRejected) ("Both production validators reject {0}" -f $modified.Name)
        }

        $approvedConfigText = [IO.File]::ReadAllText($configPath)
        [IO.File]::AppendAllText($configPath, "`n<!-- source-only hash tamper -->")
        $launcherHashRejected = $false
        $preparerHashRejected = $false
        try { Assert-LauncherTemplateHash -LiteralPath $configPath -ExpectedSha256 $expectedWsbHash | Out-Null } catch { $launcherHashRejected = $true }
        try { Assert-PreparerTemplateHash -LiteralPath $configPath -ExpectedSha256 $expectedWsbHash | Out-Null } catch { $preparerHashRejected = $true }
        Assert-True ($launcherHashRejected -and $preparerHashRejected) 'Both production hash validators reject a modified configuration hash'
        [IO.File]::WriteAllText($configPath, $approvedConfigText, [Text.UTF8Encoding]::new($false))
    }

    $wrapperPinMatch = [regex]::Match($sourcePreparerText, '(?m)^[ \t]*\$expectedWrapperSha256[ \t]*=[ \t]*''([0-9a-f]{64})''[ \t]*\r?$')
    Assert-True $wrapperPinMatch.Success 'CMD wrapper SHA256 pin is declared and anchored in the production preparer'
    $expectedWrapperHash = $wrapperPinMatch.Groups[1].Value
    Assert-True ($expectedWrapperHash -eq (Get-NormalizedSourceHash $wrapperPath)) 'Preparer pin matches approved guest CMD wrapper'
    Assert-True ($launcherText.Contains($expectedWrapperHash)) 'Launcher pins same approved guest CMD SHA256'

    $previousWrapperReviewMatch = [regex]::Match($sourcePreparerText, '(?s)\$previousReviewedWrapperSha256\s*=\s*@\(\s*''([0-9a-f]{64})''\s*\)')
    Assert-True ($previousWrapperReviewMatch.Success -and $previousWrapperReviewMatch.Groups[1].Value -eq 'f93c0890d595093d25891b1a6dcaca105f46c2aec418c3f11bed3187e4c5b822') 'Only the exact previously source-reviewed CMD wrapper hash is authorized for migration'
    $previousVersionValidatorAst = @($preparerAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-PreviouslyReviewedStagedInput' }, $false))
    Assert-True ($previousVersionValidatorAst.Count -eq 1) 'Production prior-version migration validator is source-addressable exactly once'
    Assert-True ($sourcePreparerText.Contains('$knownPrevious = Test-PreviouslyReviewedStagedInput -Name $name -Sha256 $existingHash')) 'Production staging path actually calls reviewed prior-version validator'
    Assert-True ($sourcePreparerText.IndexOf('Get-Process -Name WindowsSandbox') -lt $sourcePreparerText.IndexOf('$knownPrevious = Test-PreviouslyReviewedStagedInput')) 'Active Sandbox process guard executes before migration eligibility or staged writes'
    if ($previousVersionValidatorAst.Count -eq 1 -and $previousWrapperReviewMatch.Success) {
        Invoke-Expression $previousVersionValidatorAst[0].Extent.Text
        $wrapperName = 'F2-Guest-Diagnostic.cmd'
        $diagnosticName = 'Get-F2SandboxReadiness.ps1'
        $bootstrapName = 'Start-F2SandboxDiagnostics.ps1'
        $previousReviewedWrapperSha256 = @($previousWrapperReviewMatch.Groups[1].Value)
        $previousReviewedBootstrapSha256 = @()
        $previousReviewedDiagnosticSha256 = @()
        Assert-True (Test-PreviouslyReviewedStagedInput -Name $wrapperName -Sha256 $previousReviewedWrapperSha256[0]) 'Production migration accepts the one approved older CMD wrapper'
        Assert-True (-not (Test-PreviouslyReviewedStagedInput -Name $wrapperName -Sha256 $expectedWrapperHash)) 'Current wrapper hash is not misclassified as an older version'
        Assert-True (-not (Test-PreviouslyReviewedStagedInput -Name $wrapperName -Sha256 ('0' * 64))) 'Production migration rejects unknown/tampered wrapper digest'
        Assert-True (-not (Test-PreviouslyReviewedStagedInput -Name 'Unreviewed.cmd' -Sha256 $previousReviewedWrapperSha256[0])) 'Production migration rejects an unreviewed input filename'
        Assert-True (-not (Test-PreviouslyReviewedStagedInput -Name $diagnosticName -Sha256 $previousReviewedWrapperSha256[0])) 'Old CMD wrapper digest cannot authorize overwriting the diagnostic'
    }
    Assert-True ($sourcePreparerText.Contains('@($diagnosticName, $bootstrapName, $wrapperName)') -and $launcherText.Contains('@($diagnosticName, $bootstrapName, $wrapperName)')) 'Both host validators require exactly three staged input names'
    Assert-True ($expectedBootstrapHash -eq (Get-NormalizedSourceHash $bootstrapPath)) 'Preparer pin matches updated bootstrap source'
    Assert-True ($expectedWsbHash -eq (Get-NormalizedSourceHash $configPath)) 'Preparer pin matches updated startup configuration'
    Assert-True ($launcherText.Contains($expectedBootstrapHash) -and $launcherText.Contains($expectedWsbHash)) 'Launcher pins updated bootstrap and startup configuration'

    $sourceOnlyGuardOutput = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fixtureProvisioning 'Prepare-F2SandboxInputs.ps1') -Automation -SourceOnly -PrepareInputs 2>&1 | Out-String
    Assert-True ($LASTEXITCODE -eq 2 -and $sourceOnlyGuardOutput.Contains('SourceOnly is restricted')) 'SourceOnly fixture cannot stage mapped host inputs'
    Invoke-HostFixture -Description 'Reviewed offline automation template and pinned scripts' -ExpectedExitCode 0

    $diagnostic = Join-Path $fixtureProvisioning 'Get-F2SandboxReadiness.ps1'
    Add-Content -LiteralPath $diagnostic -Value "`n# tampered input fixture" -Encoding utf8
    Invoke-HostFixture -Description 'Reject altered diagnostic digest' -ExpectedExitCode 2
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'Get-F2SandboxReadiness.ps1') -Destination $diagnostic -Force

    $bootstrapFixture = Join-Path $fixtureProvisioning 'Start-F2SandboxDiagnostics.ps1'
    Add-Content -LiteralPath $bootstrapFixture -Value "`n# tampered bootstrap fixture" -Encoding utf8
    Invoke-HostFixture -Description 'Reject altered bootstrap digest' -ExpectedExitCode 2
    Copy-Item -LiteralPath $bootstrapPath -Destination $bootstrapFixture -Force

    $wrapperFixture = Join-Path $fixtureProvisioning 'F2-Guest-Diagnostic.cmd'
    Add-Content -LiteralPath $wrapperFixture -Value 'REM altered wrapper fixture' -Encoding ascii
    Invoke-HostFixture -Description 'Reject altered CMD startup wrapper digest' -ExpectedExitCode 2
    Copy-Item -LiteralPath $wrapperPath -Destination $wrapperFixture -Force

    $configText = Get-Content -LiteralPath $configPath -Raw
    Set-Content -LiteralPath $configPath -Value $configText.Replace('<ReadOnly>true</ReadOnly>', '<ReadOnly>false</ReadOnly>') -Encoding utf8
    Set-FixtureWsbPin
    Invoke-HostFixture -Description 'Reject writable host mapping' -ExpectedExitCode 2
    Set-Content -LiteralPath $configPath -Value $configText -Encoding utf8
    Set-FixtureWsbPin

    Set-Content -LiteralPath $configPath -Value $configText.Replace('F2-Guest-Diagnostic.cmd', 'Unreviewed.cmd') -Encoding utf8
    Set-FixtureWsbPin
    Invoke-HostFixture -Description 'Reject unreviewed LogonCommand' -ExpectedExitCode 2
    Set-Content -LiteralPath $configPath -Value $configText -Encoding utf8
    Set-FixtureWsbPin

    Set-Content -LiteralPath $configPath -Value $configText.Replace('C:\F2Input\F2-Guest-Diagnostic.cmd', 'powershell.exe') -Encoding utf8
    Set-FixtureWsbPin
    Invoke-HostFixture -Description 'Reject direct PowerShell startup instead of reviewed CMD entrypoint' -ExpectedExitCode 2
    Set-Content -LiteralPath $configPath -Value $configText -Encoding utf8
    Set-FixtureWsbPin

    Set-Content -LiteralPath $configPath -Value ($configText + "`n<!-- tampered hash fixture -->") -Encoding utf8
    Invoke-HostFixture -Description 'Reject startup configuration hash mismatch' -ExpectedExitCode 2

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

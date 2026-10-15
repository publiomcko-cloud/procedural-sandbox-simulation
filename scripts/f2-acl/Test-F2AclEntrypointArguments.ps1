[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$script:Failures = [Collections.Generic.List[string]]::new()

function Assert-Entrypoint {
    param([bool]$Condition, [string]$Name)
    $script:Assertions++
    if (-not $Condition) {
        $script:Failures.Add($Name)
        Write-Host ('FAIL: ' + $Name)
    } else {
        Write-Host ('PASS: ' + $Name)
    }
}

function Invoke-SyntheticPowerShellFile {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string]$Arguments = '',
        [string]$ExpectedPathOverride
    )

    $argumentLine = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $ScriptPath + '"'
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $argumentLine += ' ' + $Arguments }

    $hadOverride = Test-Path Env:F2_SYNTHETIC_EXPECTED_PATH
    $oldOverride = $env:F2_SYNTHETIC_EXPECTED_PATH
    $process = $null
    try {
        if ($PSBoundParameters.ContainsKey('ExpectedPathOverride')) { $env:F2_SYNTHETIC_EXPECTED_PATH = $ExpectedPathOverride }
        else { Remove-Item Env:F2_SYNTHETIC_EXPECTED_PATH -ErrorAction SilentlyContinue }
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $script:PowerShell51
        $startInfo.Arguments = $argumentLine
        $startInfo.WorkingDirectory = $script:FixtureRoot
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        if (-not $process.Start()) { throw 'SyntheticPowerShellStartFailed.' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $exited = $process.WaitForExit(10000)
        if (-not $exited) {
            try { $process.Kill() } catch { }
            [void]$process.WaitForExit(1000)
            return [pscustomobject]@{ ExitCode = $null; TimedOut = $true; Stdout = ''; Stderr = 'SyntheticProcessTimeout.' }
        }
        if (-not $stdoutTask.Wait(1000) -or -not $stderrTask.Wait(1000)) { return [pscustomobject]@{ ExitCode = [int]$process.ExitCode; TimedOut = $true; Stdout = ''; Stderr = 'SyntheticStreamDrainTimedOut.' } }
        return [pscustomobject]@{
            ExitCode = [int]$process.ExitCode
            TimedOut = $false
            Stdout = [string]$stdoutTask.Result
            Stderr = [string]$stderrTask.Result
        }
    } finally {
        if ($null -ne $process) { $process.Dispose() }
        if ($hadOverride) { $env:F2_SYNTHETIC_EXPECTED_PATH = $oldOverride }
        else { Remove-Item Env:F2_SYNTHETIC_EXPECTED_PATH -ErrorAction SilentlyContinue }
    }
}

function Write-SyntheticResult {
    param([string]$Name, [object]$Result)
    $compactStdout = ([string]$Result.Stdout).Replace("`r", ' ').Replace("`n", ' ').Trim()
    $compactStderr = ([string]$Result.Stderr).Replace("`r", ' ').Replace("`n", ' ').Trim()
    Write-Host ("CASE={0};ExitCode={1};TimedOut={2};Stdout={3};Stderr={4}" -f $Name, $Result.ExitCode, $Result.TimedOut, $compactStdout, $compactStderr)
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$productionLauncher = Get-Content -LiteralPath (Join-Path $scriptRoot 'Invoke-F2IcaclsCapture.ps1') -Raw
$productionCoordinator = Get-Content -LiteralPath (Join-Path $scriptRoot 'Invoke-F2IcaclsProtectedCoordinator.ps1') -Raw
$launcherTokens = $null; $launcherParseErrors = $null
$launcherAst = [Management.Automation.Language.Parser]::ParseInput($productionLauncher, [ref]$launcherTokens, [ref]$launcherParseErrors)
$coordinatorTokens = $null; $coordinatorParseErrors = $null
$coordinatorAst = [Management.Automation.Language.Parser]::ParseInput($productionCoordinator, [ref]$coordinatorTokens, [ref]$coordinatorParseErrors)

Assert-Entrypoint ($launcherParseErrors.Count -eq 0 -and $coordinatorParseErrors.Count -eq 0) 'both production entrypoints parse under Windows PowerShell 5.1'
Assert-Entrypoint ($productionLauncher -match 'Set-StrictMode -Version Latest' -and $productionCoordinator -match 'Set-StrictMode -Version Latest') 'both production entrypoints retain StrictMode Latest'
Assert-Entrypoint ($productionLauncher -notmatch '\[CmdletBinding\(\)\]' -and $productionCoordinator -notmatch '\[CmdletBinding\(\)\]') 'entrypoints avoid pre-body advanced-parameter binding so rejected arguments receive explicit failure status'
Assert-Entrypoint ($productionLauncher -match '\$MyInvocation\.UnboundArguments' -and $productionLauncher -notmatch '\$args\.Count') 'production launcher uses a PS5.1-safe unbound-argument check'
Assert-Entrypoint ($productionCoordinator -match '\$MyInvocation\.UnboundArguments' -and $productionCoordinator -notmatch '\$args\.Count') 'production coordinator uses a PS5.1-safe unbound-argument check'
Assert-Entrypoint ($productionLauncher.IndexOf('try {', [StringComparison]::Ordinal) -lt $productionLauncher.IndexOf('$MyInvocation.UnboundArguments', [StringComparison]::Ordinal)) 'launcher argument validation is inside its protected error handler'
Assert-Entrypoint ($productionCoordinator.IndexOf('try {', [StringComparison]::Ordinal) -lt $productionCoordinator.IndexOf('$MyInvocation.UnboundArguments', [StringComparison]::Ordinal)) 'coordinator path and argument checks are inside its protected error handler'
Assert-Entrypoint ($productionCoordinator -match 'F2-G1-Icacls\\scripts\\f2-acl' -and $productionCoordinator -match 'Invoke-F2IcaclsProtectedCoordinator\.ps1') 'coordinator retains its exact installed-path enforcement'
Assert-Entrypoint ($coordinatorAst.ParamBlock.Parameters.Count -eq 1 -and $coordinatorAst.ParamBlock.Parameters[0].Name.VariablePath.UserPath -eq 'CaptureId' -and $productionCoordinator -match '\$CaptureId -notmatch ''\^\[0-9a-f\]\{32\}\$''') 'coordinator retains exactly one required validated CaptureId input'

$script:PowerShell51 = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
$script:FixtureRoot = Join-Path $env:TEMP ('F2 PS51 Entrypoint Synthetic ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:FixtureRoot)
$launcherFixturePath = Join-Path $script:FixtureRoot 'Synthetic Launcher.ps1'
$coordinatorFixturePath = Join-Path $script:FixtureRoot 'Synthetic Coordinator.ps1'

$launcherFixture = @'
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failureStage = 'LauncherFailure'
$failureExitCode = 1
try {
    $unboundArguments = @($MyInvocation.UnboundArguments)
    if ($unboundArguments.Count -ne 0) { $failureStage = 'RuntimeArgumentsRejected'; $failureExitCode = 2; throw 'RuntimeArgumentsRejected.' }
    [Console]::Out.WriteLine('SYNTHETIC_BODY_REACHED')
    exit 0
} catch {
    [Console]::Error.WriteLine(('SYNTHETIC_STAGE:' + $failureStage))
    exit $failureExitCode
}
'@

$coordinatorFixture = @'
param([string]$CaptureId)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$failureStage = 'CoordinatorFailure'
$failureExitCode = 1
try {
    $expectedPath = if ([string]::IsNullOrWhiteSpace($env:F2_SYNTHETIC_EXPECTED_PATH)) { [IO.Path]::GetFullPath($PSCommandPath) } else { [IO.Path]::GetFullPath($env:F2_SYNTHETIC_EXPECTED_PATH) }
    if (-not [string]::Equals([IO.Path]::GetFullPath($PSCommandPath), $expectedPath, [StringComparison]::OrdinalIgnoreCase)) { $failureStage = 'CoordinatorPathRejected'; $failureExitCode = 2; throw 'CoordinatorPathRejected.' }
    $unboundArguments = @($MyInvocation.UnboundArguments)
    if ($unboundArguments.Count -ne 0) { $failureStage = 'CoordinatorArgumentsRejected'; $failureExitCode = 2; throw 'CoordinatorArgumentsRejected.' }
    if ([string]$CaptureId -notmatch '^[0-9a-f]{32}$') { $failureStage = 'CoordinatorCaptureIdRejected'; $failureExitCode = 2; throw 'CoordinatorCaptureIdRejected.' }
    [Console]::Out.WriteLine(('SYNTHETIC_BODY_REACHED:' + $CaptureId))
    exit 0
} catch {
    [Console]::Error.WriteLine(('SYNTHETIC_STAGE:' + $failureStage))
    exit $failureExitCode
}
'@

[IO.File]::WriteAllText($launcherFixturePath, $launcherFixture, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($coordinatorFixturePath, $coordinatorFixture, [Text.UTF8Encoding]::new($false))
$validCaptureId = '0123456789abcdef0123456789abcdef'
try {
    $zeroLauncher = Invoke-SyntheticPowerShellFile -ScriptPath $launcherFixturePath
    Write-SyntheticResult -Name 'launcher-zero' -Result $zeroLauncher
    Assert-Entrypoint ($zeroLauncher.ExitCode -eq 0 -and -not $zeroLauncher.TimedOut -and $zeroLauncher.Stdout -match 'SYNTHETIC_BODY_REACHED') 'synthetic launcher zero-argument -File invocation passes StrictMode'

    $extraLauncher = Invoke-SyntheticPowerShellFile -ScriptPath $launcherFixturePath -Arguments 'unexpected'
    Write-SyntheticResult -Name 'launcher-extra' -Result $extraLauncher
    Assert-Entrypoint ($null -ne $extraLauncher.ExitCode -and $extraLauncher.ExitCode -ne 0 -and -not $extraLauncher.TimedOut -and $extraLauncher.Stdout -notmatch 'SYNTHETIC_BODY_REACHED') 'synthetic launcher rejects unexpected arguments before its body'

    $namedExtraLauncher = Invoke-SyntheticPowerShellFile -ScriptPath $launcherFixturePath -Arguments '-Unexpected value'
    Write-SyntheticResult -Name 'launcher-named-extra' -Result $namedExtraLauncher
    Assert-Entrypoint ($namedExtraLauncher.ExitCode -eq 2 -and -not $namedExtraLauncher.TimedOut -and $namedExtraLauncher.Stderr -match 'RuntimeArgumentsRejected' -and $namedExtraLauncher.Stdout -notmatch 'SYNTHETIC_BODY_REACHED') 'synthetic launcher rejects unexpected named arguments with a controlled exit code'

    $validCoordinator = Invoke-SyntheticPowerShellFile -ScriptPath $coordinatorFixturePath -Arguments ('-CaptureId ' + $validCaptureId)
    Write-SyntheticResult -Name 'coordinator-valid' -Result $validCoordinator
    Assert-Entrypoint ($validCoordinator.ExitCode -eq 0 -and -not $validCoordinator.TimedOut -and $validCoordinator.Stdout -match ('SYNTHETIC_BODY_REACHED:' + $validCaptureId)) 'synthetic coordinator accepts named CaptureId with zero extra arguments under StrictMode'

    $extraCoordinator = Invoke-SyntheticPowerShellFile -ScriptPath $coordinatorFixturePath -Arguments ('-CaptureId ' + $validCaptureId + ' unexpected')
    Write-SyntheticResult -Name 'coordinator-extra' -Result $extraCoordinator
    Assert-Entrypoint ($null -ne $extraCoordinator.ExitCode -and $extraCoordinator.ExitCode -ne 0 -and -not $extraCoordinator.TimedOut -and $extraCoordinator.Stdout -notmatch 'SYNTHETIC_BODY_REACHED') 'synthetic coordinator rejects unexpected extra arguments before its body'

    $namedExtraCoordinator = Invoke-SyntheticPowerShellFile -ScriptPath $coordinatorFixturePath -Arguments ('-CaptureId ' + $validCaptureId + ' -Unexpected value')
    Write-SyntheticResult -Name 'coordinator-named-extra' -Result $namedExtraCoordinator
    Assert-Entrypoint ($namedExtraCoordinator.ExitCode -eq 2 -and -not $namedExtraCoordinator.TimedOut -and $namedExtraCoordinator.Stderr -match 'CoordinatorArgumentsRejected' -and $namedExtraCoordinator.Stdout -notmatch 'SYNTHETIC_BODY_REACHED') 'synthetic coordinator rejects unexpected named arguments with a controlled exit code'

    $badCoordinatorId = Invoke-SyntheticPowerShellFile -ScriptPath $coordinatorFixturePath -Arguments '-CaptureId invalid'
    Write-SyntheticResult -Name 'coordinator-invalid' -Result $badCoordinatorId
    Assert-Entrypoint ($null -ne $badCoordinatorId.ExitCode -and $badCoordinatorId.ExitCode -ne 0 -and -not $badCoordinatorId.TimedOut -and $badCoordinatorId.Stdout -notmatch 'SYNTHETIC_BODY_REACHED') 'synthetic coordinator rejects an invalid CaptureId before its body'

    $missingCoordinatorId = Invoke-SyntheticPowerShellFile -ScriptPath $coordinatorFixturePath
    Write-SyntheticResult -Name 'coordinator-missing' -Result $missingCoordinatorId
    Assert-Entrypoint ($null -ne $missingCoordinatorId.ExitCode -and $missingCoordinatorId.ExitCode -ne 0 -and -not $missingCoordinatorId.TimedOut -and $missingCoordinatorId.Stdout -notmatch 'SYNTHETIC_BODY_REACHED') 'synthetic coordinator rejects a missing required CaptureId before its body'

    $wrongCoordinatorPath = Invoke-SyntheticPowerShellFile -ScriptPath $coordinatorFixturePath -Arguments ('-CaptureId ' + $validCaptureId) -ExpectedPathOverride (Join-Path $script:FixtureRoot 'not-the-coordinator.ps1')
    Write-SyntheticResult -Name 'coordinator-wrong-path' -Result $wrongCoordinatorPath
    Assert-Entrypoint ($wrongCoordinatorPath.ExitCode -eq 2 -and -not $wrongCoordinatorPath.TimedOut -and $wrongCoordinatorPath.Stderr -match 'CoordinatorPathRejected' -and $wrongCoordinatorPath.Stdout -notmatch 'SYNTHETIC_BODY_REACHED') 'synthetic coordinator rejects a path mismatch before its body'
} finally {
    $fullFixtureRoot = [IO.Path]::GetFullPath($script:FixtureRoot)
    $tempRoot = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    if (-not $fullFixtureRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($fullFixtureRoot) -notlike 'F2 PS51 Entrypoint Synthetic *') { throw 'Refusing to remove an unexpected synthetic fixture path.' }
    $fixtureInfo = Get-Item -LiteralPath $fullFixtureRoot -Force
    if (($fixtureInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Refusing to remove a reparse-point fixture directory.' }
    [IO.Directory]::Delete($fullFixtureRoot, $true)
}

Write-Host ("Assertions={0};Failures={1}" -f $script:Assertions, $script:Failures.Count)
if ($script:Failures.Count -gt 0) { $script:Failures | ForEach-Object { Write-Error $_ }; exit 1 }

#requires -Version 5.1
[CmdletBinding()]
param()

if ($MyInvocation.InvocationName -eq '.') {
    Write-Output '{"Schema":"f2-g1-manual-wmi-observation-v1","Outcome":"FAIL","Stage":"STARTUP","ErrorCode":"DOT_SOURCE_REJECTED"}'
    return
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Result = [ordered]@{
    Schema = 'f2-g1-manual-wmi-observation-v1'
    Outcome = 'FAIL'
    Stage = 'STARTUP'
    ErrorCode = 'NOT_STARTED'
    ReviewCommit = '56a34d7899ba31b0d3fe6d3185435bc182ac453f'
    RuntimeCommit = '8c14cf97c9446e11b8afbd64196c3f4558d4c3c9'
    RuntimeModuleSha256 = '06f117c6be29e3e150149087cb19323e83df20601b8d134f0bb02ec7335867d2'
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    RequesterPid = [int]$PID
    RequesterTokenClass = 'UNKNOWN'
    ChildPid = $null
    ChildImagePath = $null
    ChildOwnerMatchesRequester = $false
    GeneratedCommandLineLength = 0
    ObservedCommandLineLength = 0
    ObservedCommandLineSha256 = $null
    ObservedCommandLineRedacted = $null
    ObservedEncodedPayloadSha256 = $null
    ExactCommandLineMatch = $false
    EncodedPayloadMatch = $false
    ProductionValidatorPass = $false
    ChildExitCode = $null
    TimedOut = $false
    TemporaryRootId = $null
    CleanupOutcome = 'NOT_STARTED'
}

$script:ErrorRecordCode = 'NONE'
$script:TempRoot = $null
$script:FixturePath = $null
$script:FixtureSha256 = $null
$script:ChildProcess = $null
$script:ChildStarted = $false
$script:ChildExited = $false
$script:ChildStartTimestamp = $null
$script:TempRootCreated = $false
$script:ModuleInfo = $null
$script:OldTimeoutDefaultPresent = $false
$script:OldTimeoutDefault = $null
$script:TimeoutDefaultSet = $false
$script:OverallWatch = [Diagnostics.Stopwatch]::StartNew()
$script:MaximumRunMilliseconds = 120000

function Stop-F2ManualWmiObservation {
    param([Parameter(Mandatory)][string]$Code)
    $script:ErrorRecordCode = $Code
    throw 'F2_MANUAL_WMI_OBSERVATION_STOP'
}

function Assert-F2ManualNoReparseChain {
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if (-not ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current))) {
            Stop-F2ManualWmiObservation -Code 'PATH_UNAVAILABLE'
        }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Stop-F2ManualWmiObservation -Code 'REPARSE_PATH_REJECTED'
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $current) { break }
        $current = $parent
    }
}

function Read-F2ManualPinnedModuleBytes {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256
    )
    Assert-F2ManualNoReparseChain -Path $Path
    $stream = $null
    try {
        $stream = New-Object IO.FileStream($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        if ($stream.Length -lt 1 -or $stream.Length -gt 1048576) {
            Stop-F2ManualWmiObservation -Code 'MODULE_SIZE_INVALID'
        }
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes,$offset,$bytes.Length - $offset)
            if ($read -le 0) { Stop-F2ManualWmiObservation -Code 'MODULE_READ_INCOMPLETE' }
            $offset += $read
        }
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $actualSha256 = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($actualSha256 -cne $ExpectedSha256) {
        Stop-F2ManualWmiObservation -Code 'MODULE_HASH_MISMATCH'
    }
    return ,$bytes
}

function Get-F2ManualChildCommandLineHash {
    param([Parameter(Mandatory)][string]$CommandLine)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::Unicode.GetBytes($CommandLine)
        return [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-F2ManualRemainingMilliseconds {
    $remaining = $script:MaximumRunMilliseconds - [int]$script:OverallWatch.ElapsedMilliseconds
    if ($remaining -lt 0) { return 0 }
    return $remaining
}

try {
    $script:Result.Stage = 'ARGUMENT_AND_HOST_PREFLIGHT'
    if (@($MyInvocation.UnboundArguments).Count -ne 0) {
        Stop-F2ManualWmiObservation -Code 'UNEXPECTED_ARGUMENTS'
    }
    $expectedScriptPath = 'C:\Dev\f2-g1-manual-wmi-observation\docs\reviews\f2-g1-manual-wmi-observation\Observe-F2LaunchWmiCommandLine.ps1'
    $actualScriptPath = [IO.Path]::GetFullPath([string]$MyInvocation.MyCommand.Path)
    if ($actualScriptPath -cne [IO.Path]::GetFullPath($expectedScriptPath)) {
        Stop-F2ManualWmiObservation -Code 'SCRIPT_PATH_MISMATCH'
    }
    Assert-F2ManualNoReparseChain -Path $actualScriptPath
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
        Stop-F2ManualWmiObservation -Code 'POWERSHELL_VERSION_UNSUPPORTED'
    }

    $reviewRoot = 'C:\Dev\f2-g1-diagnostic-elevation-plan-review'
    $runtimeRoot = 'C:\Dev\f2-g1-diagnostic-launch-runtime'
    $modulePath = Join-Path $runtimeRoot 'scripts\f2-acl\F2HistoricalManifestLaunch.psm1'
    $expectedModulePath = 'C:\Dev\f2-g1-diagnostic-launch-runtime\scripts\f2-acl\F2HistoricalManifestLaunch.psm1'
    if ([IO.Path]::GetFullPath($modulePath) -cne [IO.Path]::GetFullPath($expectedModulePath)) {
        Stop-F2ManualWmiObservation -Code 'MODULE_PATH_MISMATCH'
    }

    $script:Result.Stage = 'PINNED_MODULE_LOAD'
    $moduleBytes = Read-F2ManualPinnedModuleBytes -Path $modulePath -ExpectedSha256 $script:Result.RuntimeModuleSha256
    $moduleText = (New-Object Text.UTF8Encoding($false,$true)).GetString($moduleBytes)
    $moduleBlock = [ScriptBlock]::Create($moduleText)
    $script:ModuleInfo = New-Module -Name 'F2ManualWmiPinnedLaunchModule' -ScriptBlock $moduleBlock
    if ($null -eq $script:ModuleInfo) { Stop-F2ManualWmiObservation -Code 'MODULE_LOAD_FAILED' }
    Import-Module -ModuleInfo $script:ModuleInfo -Force -ErrorAction Stop | Out-Null

    $script:Result.Stage = 'CHECKOUT_IDENTITY'
    $gitPath = 'C:\Program Files\Git\mingw64\bin\git.exe'
    $gitSha256 = '1a0043555d254618f2d56c936c3d9a1fbfb878bc878416a133c346bc7835eda9'
    $reviewFacts = Get-F2LaunchRepositoryFacts -GitPath $gitPath -ExpectedGitSha256 $gitSha256 -Repository $reviewRoot -ExpectedRoot $reviewRoot -ExpectedHead $script:Result.ReviewCommit
    $runtimeFacts = Get-F2LaunchRepositoryFacts -GitPath $gitPath -ExpectedGitSha256 $gitSha256 -Repository $runtimeRoot -ExpectedRoot $runtimeRoot -ExpectedHead $script:Result.RuntimeCommit
    if (-not $reviewFacts.Pass -or -not $runtimeFacts.Pass) {
        Stop-F2ManualWmiObservation -Code 'CHECKOUT_IDENTITY_MISMATCH'
    }

    $script:Result.Stage = 'REQUESTER_TOKEN'
    $requesterFacts = Get-F2LaunchTokenFacts
    if ($requesterFacts.IsElevated -or $requesterFacts.IsAdministrator) {
        Stop-F2ManualWmiObservation -Code 'ELEVATED_OR_ADMINISTRATOR_TOKEN_REJECTED'
    }
    $script:Result.RequesterTokenClass = 'STANDARD'
    $requesterIdentity = Get-F2LaunchProcessIdentity -ProcessId $PID
    $expectedPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if ([IO.Path]::GetFullPath($requesterIdentity.ImagePath) -ine [IO.Path]::GetFullPath($expectedPowerShell)) {
        Stop-F2ManualWmiObservation -Code 'REQUESTER_IMAGE_MISMATCH'
    }

    $script:Result.Stage = 'TEMP_FIXTURE_CREATE'
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($tempBase.StartsWith('\\',[StringComparison]::Ordinal) -or $tempBase -notmatch '^[A-Za-z]:\\') {
        Stop-F2ManualWmiObservation -Code 'TEMP_VOLUME_NOT_LOCAL'
    }
    Assert-F2ManualNoReparseChain -Path $tempBase
    $driveRoot = [IO.Path]::GetPathRoot($tempBase)
    $drive = [IO.DriveInfo]::new($driveRoot)
    if ($drive.DriveType -ne [IO.DriveType]::Fixed) {
        Stop-F2ManualWmiObservation -Code 'TEMP_VOLUME_NOT_FIXED'
    }
    $tempId = [Guid]::NewGuid().ToString('N')
    $script:Result.TemporaryRootId = $tempId
    $script:TempRoot = Join-Path $tempBase ('F2G1-WmiObservation-' + $tempId)
    if ([IO.Directory]::Exists($script:TempRoot) -or [IO.File]::Exists($script:TempRoot)) {
        Stop-F2ManualWmiObservation -Code 'TEMP_NAME_COLLISION'
    }
    [void][IO.Directory]::CreateDirectory($script:TempRoot)
    $script:TempRootCreated = $true
    if ([IO.Path]::GetFullPath($script:TempRoot) -cne [IO.Path]::GetFullPath((Join-Path $tempBase ('F2G1-WmiObservation-' + $tempId)))) {
        Stop-F2ManualWmiObservation -Code 'TEMP_PATH_MISMATCH'
    }
    Assert-F2ManualNoReparseChain -Path $script:TempRoot
    if (@(Get-ChildItem -LiteralPath $script:TempRoot -Force -ErrorAction Stop).Count -ne 0) {
        Stop-F2ManualWmiObservation -Code 'TEMP_DIRECTORY_NOT_EMPTY'
    }

    $script:FixturePath = Join-Path $script:TempRoot 'sleep-fixture.ps1'
    $fixtureText = @'
param([string]$PipeName,[int]$ExpectedParentPid,[long]$ExpectedParentStartUtcTicks,[string]$ExpectedLaunchCommitSha)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PipeName -notmatch '^F2D_[0-9a-f]{32}$' -or $ExpectedParentPid -le 0 -or $ExpectedParentStartUtcTicks -le 0 -or $ExpectedLaunchCommitSha -notmatch '^[0-9a-f]{40}$') { exit 82 }
Start-Sleep -Seconds 25
exit 0
'@
    $fixtureBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($fixtureText)
    $fixtureStream = New-Object IO.FileStream($script:FixturePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $fixtureStream.Write($fixtureBytes,0,$fixtureBytes.Length); $fixtureStream.Flush($true) }
    finally { $fixtureStream.Dispose() }
    $fixtureSha = [Security.Cryptography.SHA256]::Create()
    try { $script:FixtureSha256 = [BitConverter]::ToString($fixtureSha.ComputeHash($fixtureBytes)).Replace('-','').ToLowerInvariant() }
    finally { $fixtureSha.Dispose() }
    Assert-F2ManualNoReparseChain -Path $script:FixturePath

    $script:Result.Stage = 'COMMAND_BUILD'
    $pipeName = 'F2D_' + [Guid]::NewGuid().ToString('N')
    $childInvocation = New-F2LaunchChildInvocation -ChildPath $script:FixturePath -ChildSha256 $script:FixtureSha256 -PipeName $pipeName -RequesterPid $requesterIdentity.ProcessId -RequesterStartUtcTicks $requesterIdentity.StartUtcTicks -LaunchCommitSha $script:Result.RuntimeCommit -MaximumCommandLineLength 3600
    $script:Result.GeneratedCommandLineLength = [int]$childInvocation.CommandLineLength
    if ($childInvocation.CommandLineLength -gt 3600) { Stop-F2ManualWmiObservation -Code 'GENERATED_COMMAND_TOO_LONG' }
    if ([IO.Path]::GetFullPath($childInvocation.ExecutablePath) -ine [IO.Path]::GetFullPath($expectedPowerShell)) {
        Stop-F2ManualWmiObservation -Code 'CHILD_IMAGE_PATH_MISMATCH'
    }

    $script:Result.Stage = 'SAME_TOKEN_SHELLEXECUTE'
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $childInvocation.ExecutablePath
    $startInfo.Arguments = $childInvocation.Arguments
    $startInfo.WorkingDirectory = $script:TempRoot
    $startInfo.UseShellExecute = $true
    $startInfo.Verb = [string]::Empty
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    if (-not $startInfo.UseShellExecute -or $startInfo.Verb.Length -ne 0) {
        Stop-F2ManualWmiObservation -Code 'SHELLEXECUTE_POLICY_MISMATCH'
    }
    $script:ChildProcess = New-Object Diagnostics.Process
    $script:ChildProcess.StartInfo = $startInfo
    $script:ChildStartTimestamp = [Diagnostics.Stopwatch]::StartNew()
    try { $started = $script:ChildProcess.Start() }
    catch { Stop-F2ManualWmiObservation -Code 'CHILD_START_FAILED' }
    if (-not $started) { Stop-F2ManualWmiObservation -Code 'CHILD_START_FAILED' }
    $script:ChildStarted = $true
    $script:Result.ChildPid = [int]$script:ChildProcess.Id

    $script:Result.Stage = 'ACTUAL_WMI_OBSERVATION'
    $observed = $null
    $wmiAttempts = 0
    while ($null -eq $observed -and $wmiAttempts -lt 5 -and $script:ChildStartTimestamp.ElapsedMilliseconds -lt 14000) {
        $wmiAttempts++
        try {
            $instances = @(Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId = {0}' -f $script:ChildProcess.Id) -Property ProcessId,Name,ExecutablePath,CommandLine -OperationTimeoutSec 2 -ErrorAction Stop)
            if ($instances.Count -gt 1) { Stop-F2ManualWmiObservation -Code 'WMI_DUPLICATE_PROCESS_RECORD' }
            if ($instances.Count -eq 1) { $observed = $instances[0] }
        }
        catch {
            if ($script:ErrorRecordCode -ne 'NONE') { throw }
            if ($wmiAttempts -ge 5) { Stop-F2ManualWmiObservation -Code 'WMI_QUERY_FAILED' }
        }
        if ($null -eq $observed -and $wmiAttempts -lt 5) { Start-Sleep -Milliseconds 150 }
    }
    if ($null -eq $observed) { Stop-F2ManualWmiObservation -Code 'WMI_RECORD_MISSING' }

    $observedPid = [int]$observed.ProcessId
    $observedImage = [string]$observed.ExecutablePath
    $observedCommandLine = [string]$observed.CommandLine
    if ($observedPid -ne $script:ChildProcess.Id -or [string]$observed.Name -cne 'powershell.exe' -or [string]::IsNullOrWhiteSpace($observedImage) -or [string]::IsNullOrWhiteSpace($observedCommandLine)) {
        Stop-F2ManualWmiObservation -Code 'OBSERVED_PROCESS_IDENTITY_MISMATCH'
    }
    if ([IO.Path]::GetFullPath($observedImage) -ine [IO.Path]::GetFullPath($childInvocation.ExecutablePath)) {
        Stop-F2ManualWmiObservation -Code 'OBSERVED_PROCESS_IMAGE_MISMATCH'
    }
    $script:Result.ChildImagePath = [IO.Path]::GetFullPath($observedImage)
    $script:Result.ObservedCommandLineLength = $observedCommandLine.Length
    $script:Result.ObservedCommandLineSha256 = Get-F2ManualChildCommandLineHash -CommandLine $observedCommandLine
    $expectedCommandLine = '"' + $childInvocation.ExecutablePath + '" ' + $childInvocation.Arguments
    $script:Result.ExactCommandLineMatch = ($observedCommandLine -ceq $expectedCommandLine)
    $payloadMatch = [regex]::Match($observedCommandLine,'^\s*"[^"]+"\s+-NoLogo\s+-NoProfile\s+-NonInteractive\s+-ExecutionPolicy\s+Bypass\s+-EncodedCommand\s+(?<payload>[A-Za-z0-9+/=]+)\s*$')
    $script:Result.EncodedPayloadMatch = ($payloadMatch.Success -and $payloadMatch.Groups['payload'].Value -ceq $childInvocation.EncodedCommand)
    if ($payloadMatch.Success) {
        $observedPayload = $payloadMatch.Groups['payload'].Value
        $payloadBytes = [Convert]::FromBase64String($observedPayload)
        $payloadHasher = [Security.Cryptography.SHA256]::Create()
        try { $script:Result.ObservedEncodedPayloadSha256 = [BitConverter]::ToString($payloadHasher.ComputeHash($payloadBytes)).Replace('-','').ToLowerInvariant() }
        finally { $payloadHasher.Dispose() }
        $script:Result.ObservedCommandLineRedacted = '"' + [IO.Path]::GetFullPath($observedImage) + '" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand <redacted;chars=' + $observedPayload.Length + ';sha256=' + $script:Result.ObservedEncodedPayloadSha256 + '>'
    }
    else {
        $script:Result.ObservedCommandLineRedacted = '<unrecognized command-line shape; raw withheld>'
    }
    if (-not $script:Result.ExactCommandLineMatch -or -not $script:Result.EncodedPayloadMatch) {
        Stop-F2ManualWmiObservation -Code 'OBSERVED_COMMANDLINE_MISMATCH'
    }

    $script:Result.Stage = 'PRODUCTION_VALIDATOR'
    if ($null -eq $global:PSDefaultParameterValues) {
        $global:PSDefaultParameterValues = @{}
    }
    if (-not $global:PSDefaultParameterValues.ContainsKey('Get-CimInstance:OperationTimeoutSec')) {
        $script:OldTimeoutDefaultPresent = $false
    }
    else {
        $script:OldTimeoutDefaultPresent = $true
        $script:OldTimeoutDefault = $global:PSDefaultParameterValues['Get-CimInstance:OperationTimeoutSec']
    }
    $global:PSDefaultParameterValues['Get-CimInstance:OperationTimeoutSec'] = 2
    $script:TimeoutDefaultSet = $true
    if (-not (Get-Command Get-CimInstance -ErrorAction Stop).Parameters.ContainsKey('OperationTimeoutSec')) {
        Stop-F2ManualWmiObservation -Code 'WMI_TIMEOUT_UNAVAILABLE'
    }
    $script:Result.ProductionValidatorPass = [bool](Test-F2LaunchProcessCommandLine -ProcessId $script:ChildProcess.Id -ExpectedImagePath $childInvocation.ExecutablePath -ExpectedEncodedCommand $childInvocation.EncodedCommand)
    if (-not $script:Result.ProductionValidatorPass) {
        Stop-F2ManualWmiObservation -Code 'PRODUCTION_VALIDATOR_REJECTED'
    }

    $script:Result.Stage = 'SAME_REQUESTER_ACCOUNT_CHECK'
    $observedSid = [F2HistoricalLaunchNative]::ProcessSid([uint32]$script:ChildProcess.Id)
    $script:Result.ChildOwnerMatchesRequester = ([string]$observedSid -ceq [string]$requesterFacts.UserSid)
    if (-not $script:Result.ChildOwnerMatchesRequester) {
        Stop-F2ManualWmiObservation -Code 'CHILD_OWNER_MISMATCH'
    }

    $script:Result.Stage = 'BOUNDED_NATURAL_EXIT'
    $remaining = [Math]::Min(35000,(Get-F2ManualRemainingMilliseconds))
    if ($remaining -le 0 -or -not $script:ChildProcess.WaitForExit($remaining)) {
        $script:Result.TimedOut = $true
        Stop-F2ManualWmiObservation -Code 'CHILD_TIMEOUT'
    }
    $script:ChildExited = $true
    $script:Result.ChildExitCode = [int]$script:ChildProcess.ExitCode
    if ($script:Result.ChildExitCode -ne 0) { Stop-F2ManualWmiObservation -Code 'CHILD_EXIT_NONZERO' }
    $script:Result.Outcome = 'PASS'
    $script:Result.ErrorCode = 'NONE'
    $script:Result.Stage = 'CLEANUP'
}
catch {
    $script:Result.Outcome = 'FAIL'
    if ($script:ErrorRecordCode -ne 'NONE') {
        $script:Result.ErrorCode = $script:ErrorRecordCode
    }
    else {
        $script:Result.ErrorCode = switch ([string]$script:Result.Stage) {
            'PINNED_MODULE_LOAD' { 'MODULE_LOAD_FAILED' }
            'CHECKOUT_IDENTITY' { 'CHECKOUT_QUERY_FAILED' }
            'REQUESTER_TOKEN' { 'TOKEN_QUERY_FAILED' }
            'TEMP_FIXTURE_CREATE' { 'TEMP_SETUP_FAILED' }
            'COMMAND_BUILD' { 'COMMAND_BUILD_FAILED' }
            'SAME_TOKEN_SHELLEXECUTE' { 'CHILD_START_FAILED' }
            'ACTUAL_WMI_OBSERVATION' { 'WMI_QUERY_FAILED' }
            'PRODUCTION_VALIDATOR' { 'PRODUCTION_VALIDATOR_FAILED' }
            'SAME_REQUESTER_ACCOUNT_CHECK' { 'CHILD_IDENTITY_QUERY_FAILED' }
            'BOUNDED_NATURAL_EXIT' { 'CHILD_WAIT_FAILED' }
            default { 'UNCLASSIFIED_SCRIPT_FAILURE' }
        }
    }
}
finally {
    if ($script:TimeoutDefaultSet) {
        if ($script:OldTimeoutDefaultPresent) {
            $global:PSDefaultParameterValues['Get-CimInstance:OperationTimeoutSec'] = $script:OldTimeoutDefault
        }
        else {
            [void]$global:PSDefaultParameterValues.Remove('Get-CimInstance:OperationTimeoutSec')
        }
    }

    if ($script:ChildStarted -and $null -ne $script:ChildProcess) {
        try {
            if (-not $script:ChildProcess.HasExited) {
                $remaining = [Math]::Min(35000,(Get-F2ManualRemainingMilliseconds))
                if ($remaining -gt 0 -and $script:ChildProcess.WaitForExit($remaining)) {
                    $script:ChildExited = $true
                }
            }
            if ($script:ChildProcess.HasExited) {
                $script:ChildExited = $true
                $script:Result.ChildExitCode = [int]$script:ChildProcess.ExitCode
            }
        }
        catch {
            $script:ChildExited = $false
        }
    }

    if (-not $script:ChildStarted -or $script:ChildExited) {
        try {
            if ($script:TempRootCreated -and $null -ne $script:TempRoot) {
                $expectedTempRoot = Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) ('F2G1-WmiObservation-' + [string]$script:Result.TemporaryRootId)
                $expectedFixture = Join-Path $expectedTempRoot 'sleep-fixture.ps1'
                if ([IO.Path]::GetFullPath($script:TempRoot) -cne [IO.Path]::GetFullPath($expectedTempRoot)) {
                    throw 'cleanup-scope'
                }
                Assert-F2ManualNoReparseChain -Path $expectedTempRoot
                $children = @(Get-ChildItem -LiteralPath $expectedTempRoot -Force -ErrorAction Stop)
                if ($children.Count -eq 0) {
                    [IO.Directory]::Delete($expectedTempRoot,$false)
                    if ([IO.Directory]::Exists($expectedTempRoot)) { throw 'cleanup-empty-root-residual' }
                    $script:Result.CleanupOutcome = 'COMPLETE'
                }
                elseif ($children.Count -eq 1 -and [IO.Path]::GetFullPath($children[0].FullName) -ceq [IO.Path]::GetFullPath($expectedFixture) -and $null -ne $script:FixtureSha256) {
                    if ([IO.Path]::GetFullPath($script:FixturePath) -cne [IO.Path]::GetFullPath($expectedFixture)) { throw 'cleanup-fixture-scope' }
                    Assert-F2ManualNoReparseChain -Path $expectedFixture
                    $currentBytes = Read-F2LaunchPinnedFile -Path $expectedFixture -ExpectedSha256 $script:FixtureSha256 -MaximumBytes 65536
                    if ($currentBytes.Length -gt 65536) { throw 'cleanup-size' }
                    [IO.File]::Delete($expectedFixture)
                    [IO.Directory]::Delete($expectedTempRoot,$false)
                    if ([IO.Directory]::Exists($expectedTempRoot) -or [IO.File]::Exists($expectedFixture)) { throw 'cleanup-residual' }
                    $script:Result.CleanupOutcome = 'COMPLETE'
                }
                else {
                    throw 'cleanup-contents'
                }
            }
            else {
                $script:Result.CleanupOutcome = 'NO_TEMP_OBJECTS_CREATED'
            }
        }
        catch {
            $script:Result.CleanupOutcome = 'FAILED_OR_UNEXPECTED_TEMP_CONTENT'
            $script:Result.Outcome = 'FAIL'
            $script:Result.ErrorCode = 'CLEANUP_INCOMPLETE'
            $script:Result.Stage = 'CLEANUP'
        }
    }
    else {
        $script:Result.TimedOut = $true
        $script:Result.CleanupOutcome = 'PRESERVED_CHILD_MAY_REMAIN'
        $script:Result.Outcome = 'FAIL'
        $script:Result.ErrorCode = 'CHILD_MAY_REMAIN'
        $script:Result.Stage = 'CLEANUP'
    }

    if ($null -ne $script:ChildProcess) {
        try { $script:ChildProcess.Dispose() } catch {
            $script:Result.Outcome = 'FAIL'
            $script:Result.ErrorCode = 'PROCESS_HANDLE_CLEANUP_FAILED'
            $script:Result.Stage = 'CLEANUP'
        }
    }
    if ($script:Result.Outcome -eq 'PASS' -and $script:Result.CleanupOutcome -eq 'COMPLETE') {
        $script:Result.Stage = 'COMPLETE'
        $script:Result.ErrorCode = 'NONE'
    }
    elseif ($script:Result.Outcome -eq 'PASS') {
        $script:Result.Outcome = 'FAIL'
        $script:Result.ErrorCode = 'CLEANUP_INCOMPLETE'
        $script:Result.Stage = 'CLEANUP'
    }
}

$json = $script:Result | ConvertTo-Json -Depth 4 -Compress
if ($json.Length -gt 4096) {
    $json = '{"Schema":"f2-g1-manual-wmi-observation-v1","Outcome":"FAIL","Stage":"REPORTING","ErrorCode":"RESULT_TOO_LARGE"}'
    $script:Result.Outcome = 'FAIL'
    $script:Result.ErrorCode = 'RESULT_TOO_LARGE'
    $script:Result.Stage = 'REPORTING'
}
Write-Output $json
if ($script:Result.Outcome -eq 'PASS') { exit 0 }
exit 1

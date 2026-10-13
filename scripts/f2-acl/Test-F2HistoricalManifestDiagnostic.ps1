[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$assertions = 0
$failures = New-Object 'System.Collections.Generic.List[string]'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$modulePath = Join-Path $PSScriptRoot 'F2HistoricalManifestDiagnostic.psm1'
$probePath = Join-Path $PSScriptRoot 'Invoke-F2HistoricalManifestDiagnostic.ps1'
$expected = @{
    Updater = 'd9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2'
    Launcher = '9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
    Protocol = '66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'
    Candidate = 'b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
    SourceCommit = '396c44965c90c08292ad2835f8317e81b6b9daaf'
    CandidateCommit = '7f99bc10f3e2258d2340cea4e7ba1352022cbb6d'
    ReviewCommit = 'd9a0ffa18e54716dbc8dac577ce2c2979e961a9a'
}
$updaterPath = 'scripts/f2-acl/Invoke-F2ProtectedReleaseUpdate.ps1'
$launcherPath = 'scripts/f2-acl/Start-F2ProtectedReleaseUpdate.ps1'
$protocolPath = 'scripts/f2-acl/F2ProtectedRelease.Diagnostics.ps1'
$candidatePath = 'docs/reviews/f2-g1-protected-release-updater/f2-runtime-release-v3.candidate.json'

function Assert-F2Probe {
    param([Parameter(Mandatory)][bool]$Condition,[Parameter(Mandatory)][string]$Name)
    $script:assertions++
    if (-not $Condition) { $script:failures.Add($Name) }
}

function Get-F2ProbeFilteredGitBlob {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$Commit,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$MaximumBytes
    )
    $git = Get-Command 'git.exe' -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $git.Source
    $start.Arguments = '-C "' + $Repository + '" -c core.autocrlf=true cat-file --filters --path="' + $Path + '" ' + $Commit + ':' + $Path
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    $memory = New-Object IO.MemoryStream
    try {
        if (-not $process.Start()) { throw 'TEST_GIT_OBJECT_PROCESS_START_FAILED' }
        $buffer = New-Object byte[] 8192
        while ($true) {
            $read = $process.StandardOutput.BaseStream.Read($buffer,0,$buffer.Length)
            if ($read -le 0) { break }
            if (($memory.Length + $read) -gt $MaximumBytes) {
                try { $process.Kill() } catch {}
                throw 'TEST_GIT_OBJECT_OUTPUT_LIMIT'
            }
            $memory.Write($buffer,0,$read)
        }
        if (-not $process.WaitForExit(15000)) {
            try { $process.Kill() } catch {}
            throw 'TEST_GIT_OBJECT_TIMEOUT'
        }
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) { throw 'TEST_GIT_OBJECT_READ_FAILED' }
        return ,$memory.ToArray()
    } finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

function Get-F2ProbeHash {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2ProbeAstForFile {
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    Assert-F2Probe -Condition ($null -ne $ast -and $parseErrors.Count -eq 0) -Name ('Parser:' + [IO.Path]::GetFileName($Path))
    return $ast
}

try {
    $version = $PSVersionTable.PSVersion
    Assert-F2Probe -Condition ($version.Major -eq 5 -and $version.Minor -eq 1) -Name 'WindowsPowerShell51'

    foreach ($commit in @($expected.SourceCommit,$expected.CandidateCommit,$expected.ReviewCommit)) {
        & git -C $repoRoot cat-file -e ($commit + '^{commit}')
        Assert-F2Probe -Condition ($LASTEXITCODE -eq 0) -Name ('CommitObject:' + $commit.Substring(0,7))
    }
    & git -C $repoRoot merge-base --is-ancestor $expected.SourceCommit $expected.ReviewCommit
    Assert-F2Probe -Condition ($LASTEXITCODE -eq 0) -Name 'HistoricalSourceIsAncestorOfReview'
    & git -C $repoRoot merge-base --is-ancestor $expected.SourceCommit $expected.CandidateCommit
    Assert-F2Probe -Condition ($LASTEXITCODE -eq 0) -Name 'HistoricalSourceIsAncestorOfCandidateCheckout'
    & git -C $repoRoot merge-base --is-ancestor $expected.CandidateCommit $expected.ReviewCommit
    Assert-F2Probe -Condition ($LASTEXITCODE -eq 0) -Name 'CandidateCheckoutIsAncestorOfReviewHead'
    $sourceParent = [string](& git -C $repoRoot show -s --format=%P $expected.SourceCommit)
    Assert-F2Probe -Condition ($LASTEXITCODE -eq 0 -and $sourceParent.Trim() -ceq 'f58b7fdfaf71e212213d559480e1913ae6c210f8') -Name 'HistoricalSourceParent'

    $updater = Get-F2ProbeFilteredGitBlob -Repository $repoRoot -Commit $expected.SourceCommit -Path $updaterPath -MaximumBytes 4194304
    $launcher = Get-F2ProbeFilteredGitBlob -Repository $repoRoot -Commit $expected.SourceCommit -Path $launcherPath -MaximumBytes 4194304
    $protocol = Get-F2ProbeFilteredGitBlob -Repository $repoRoot -Commit $expected.SourceCommit -Path $protocolPath -MaximumBytes 4194304
    $candidate = Get-F2ProbeFilteredGitBlob -Repository $repoRoot -Commit $expected.CandidateCommit -Path $candidatePath -MaximumBytes 65536
    Assert-F2Probe -Condition ((Get-F2ProbeHash -Bytes $updater) -ceq $expected.Updater) -Name 'HistoricalUpdaterWindowsBytesSha256'
    Assert-F2Probe -Condition ((Get-F2ProbeHash -Bytes $launcher) -ceq $expected.Launcher) -Name 'HistoricalLauncherWindowsBytesSha256'
    Assert-F2Probe -Condition ((Get-F2ProbeHash -Bytes $protocol) -ceq $expected.Protocol) -Name 'HistoricalDiagnosticProtocolWindowsBytesSha256'
    Assert-F2Probe -Condition ((Get-F2ProbeHash -Bytes $candidate) -ceq $expected.Candidate) -Name 'HistoricalCandidateWindowsBytesSha256'

    $candidateText = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($candidate)
    $candidateObject = $candidateText | ConvertFrom-Json -ErrorAction Stop
    Assert-F2Probe -Condition ($candidateObject.ReviewedCommitSha -ceq $expected.SourceCommit) -Name 'CandidateReviewedCommitBinding'
    Assert-F2Probe -Condition ($candidateObject.Schema -ceq 'f2-icacls-runtime-release-v3' -and @($candidateObject.Files).Count -eq 7) -Name 'CandidateSchemaAndPackageShape'

    $moduleBytes = [IO.File]::ReadAllBytes($modulePath)
    $moduleHash = Get-F2ProbeHash -Bytes $moduleBytes
    Assert-F2Probe -Condition ($moduleHash -ceq '41156247154c95df8bcf7beb1c42db4a0fab7404c78e7e97d546c2a2a642405f') -Name 'DiagnosticModuleExactBytesPin'
    $moduleText = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($moduleBytes)
    $moduleInfo = New-Module -Name 'F2HistoricalManifestDiagnosticTest' -ScriptBlock ([scriptblock]::Create($moduleText)) -Force
    Import-Module -ModuleInfo $moduleInfo -Force -ErrorAction Stop | Out-Null
    $baseline = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $launcher -ProtocolBytes $protocol -CandidateBytes $candidate -ExpectedCandidateSha256 $expected.Candidate -TokenClass STANDARD
    Assert-F2Probe -Condition ($baseline.Status -ceq 'PASS' -and $baseline.Stage -ceq 'CandidateManifestValidation' -and $baseline.ErrorCode -ceq 'NONE') -Name 'ExactHistoricalBootstrapParserAndCommitComparison'
    Assert-F2Probe -Condition (-not $baseline.UpdaterEntrypointInvoked -and -not $baseline.RecoveryEntrypointInvoked -and -not $baseline.ProtectedWritePerformed) -Name 'SuccessPathHasNoUpdateOrWrite'

    $simulatedElevated = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $launcher -ProtocolBytes $protocol -CandidateBytes $candidate -ExpectedCandidateSha256 $expected.Candidate -TokenClass ELEVATED
    Assert-F2Probe -Condition ($simulatedElevated.Status -ceq 'PASS' -and $simulatedElevated.TokenClass -ceq 'ELEVATED') -Name 'SyntheticElevatedLabelOnly'
    Assert-F2Probe -Condition (-not $simulatedElevated.ProtectedWritePerformed -and -not $simulatedElevated.UpdaterEntrypointInvoked -and -not $simulatedElevated.RecoveryEntrypointInvoked) -Name 'ElevatedLabelDoesNotElevateOrMutate'

    $badUpdater = [byte[]]$updater.Clone()
    $badUpdater[0] = [byte]($badUpdater[0] -bxor 1)
    $badUpdaterResult = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $badUpdater -LauncherBytes $launcher -ProtocolBytes $protocol -CandidateBytes $candidate -ExpectedCandidateSha256 $expected.Candidate -TokenClass STANDARD
    Assert-F2Probe -Condition ($badUpdaterResult.Status -ceq 'FAIL' -and $badUpdaterResult.ErrorCode -ceq 'PROBE_UPDATER_HASH_MISMATCH') -Name 'UpdaterSourceTamperRejected'

    $badLauncher = [byte[]]$launcher.Clone()
    $badLauncher[0] = [byte]($badLauncher[0] -bxor 1)
    $badLauncherResult = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $badLauncher -ProtocolBytes $protocol -CandidateBytes $candidate -ExpectedCandidateSha256 $expected.Candidate -TokenClass STANDARD
    Assert-F2Probe -Condition ($badLauncherResult.Status -ceq 'FAIL' -and $badLauncherResult.ErrorCode -ceq 'PROBE_LAUNCHER_HASH_MISMATCH') -Name 'LauncherSourceTamperRejected'

    $badProtocol = [byte[]]$protocol.Clone()
    $badProtocol[0] = [byte]($badProtocol[0] -bxor 1)
    $badProtocolResult = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $launcher -ProtocolBytes $badProtocol -CandidateBytes $candidate -ExpectedCandidateSha256 $expected.Candidate -TokenClass STANDARD
    Assert-F2Probe -Condition ($badProtocolResult.Status -ceq 'FAIL' -and $badProtocolResult.ErrorCode -ceq 'PROBE_PROTOCOL_HASH_MISMATCH') -Name 'ProtocolSourceTamperRejected'

    $badCandidate = [byte[]]$candidate.Clone()
    $badCandidate[0] = [byte]($badCandidate[0] -bxor 1)
    $badCandidateResult = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $launcher -ProtocolBytes $protocol -CandidateBytes $badCandidate -ExpectedCandidateSha256 $expected.Candidate -TokenClass STANDARD
    Assert-F2Probe -Condition ($badCandidateResult.Status -ceq 'FAIL' -and $badCandidateResult.ErrorCode -ceq 'PROBE_CANDIDATE_HASH_MISMATCH') -Name 'CandidatePinTamperRejected'

    $badCommitObject = $candidateText | ConvertFrom-Json -ErrorAction Stop
    $badCommitObject.ReviewedCommitSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    $badCommitBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $badCommitObject -Depth 8 -Compress))
    $badCommitHash = Get-F2ProbeHash -Bytes $badCommitBytes
    $badCommitResult = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $launcher -ProtocolBytes $protocol -CandidateBytes $badCommitBytes -ExpectedCandidateSha256 $badCommitHash -TokenClass STANDARD
    Assert-F2Probe -Condition ($badCommitResult.Status -ceq 'FAIL' -and $badCommitResult.OperationClassification -ceq 'ReviewedCommitShaComparison' -and $badCommitResult.ErrorCode -ceq 'UPDATE_CANDIDATE_COMMIT_MISMATCH') -Name 'ReviewedCommitMismatchClassified'

    $missingIdentity = $candidateText | ConvertFrom-Json -ErrorAction Stop
    $missingIdentity.PSObject.Properties.Remove('BaselineMailboxId')
    $missingIdentityBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes((ConvertTo-Json -InputObject $missingIdentity -Depth 8 -Compress))
    $missingIdentityHash = Get-F2ProbeHash -Bytes $missingIdentityBytes
    $missingIdentityResult = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $launcher -ProtocolBytes $protocol -CandidateBytes $missingIdentityBytes -ExpectedCandidateSha256 $missingIdentityHash -TokenClass STANDARD
    Assert-F2Probe -Condition ($missingIdentityResult.Status -ceq 'FAIL' -and $missingIdentityResult.OperationClassification -ceq 'HistoricalManifestParserCall' -and $missingIdentityResult.ExceptionCategory -ceq 'STRICTMODE_MISSING_PROPERTY') -Name 'HistoricalStrictModeMissingIdentityReproduced'
    Assert-F2Probe -Condition ($missingIdentityResult.FullyQualifiedErrorId -ceq 'PropertyNotFoundStrict') -Name 'StrictModeFullyQualifiedErrorIdSanitizedAndClassified'
    $missingJson = ConvertTo-Json -InputObject $missingIdentityResult -Compress
    Assert-F2Probe -Condition (-not $missingJson.Contains('C:\Dev') -and -not $missingJson.Contains('S-1-') -and -not $missingJson.Contains('BaselineMailboxId')) -Name 'FailureRecordContainsNoPathSidOrManifestField'

    $malformedBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes('{not-json')
    $malformedHash = Get-F2ProbeHash -Bytes $malformedBytes
    $malformedResult = Invoke-F2HistoricalManifestDiagnosticCore -UpdaterBytes $updater -LauncherBytes $launcher -ProtocolBytes $protocol -CandidateBytes $malformedBytes -ExpectedCandidateSha256 $malformedHash -TokenClass STANDARD
    Assert-F2Probe -Condition ($malformedResult.Status -ceq 'FAIL' -and $malformedResult.ErrorCode -ceq 'UPDATE_MANIFEST_JSON_INVALID' -and $malformedResult.FullyQualifiedErrorId -ceq 'UPDATE_MANIFEST_JSON_INVALID') -Name 'MalformedJsonSanitized'

    $powershell51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $childStart = New-Object System.Diagnostics.ProcessStartInfo
    $childStart.FileName = $powershell51
    $childStart.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $probePath + '" unexpected-argument'
    $childStart.UseShellExecute = $false
    $childStart.CreateNoWindow = $true
    $childStart.RedirectStandardOutput = $true
    $childStart.RedirectStandardError = $true
    $child = New-Object System.Diagnostics.Process
    $child.StartInfo = $childStart
    try {
        if (-not $child.Start()) { throw 'TEST_PROBE_ARGUMENT_CHILD_START_FAILED' }
        $childStdout = $child.StandardOutput.ReadToEnd()
        $childStderr = $child.StandardError.ReadToEnd()
        if (-not $child.WaitForExit(15000)) { try { $child.Kill() } catch {}; throw 'TEST_PROBE_ARGUMENT_CHILD_TIMEOUT' }
        $childResult = $childStdout.Trim() | ConvertFrom-Json -ErrorAction Stop
        Assert-F2Probe -Condition ($child.ExitCode -eq 1 -and $childResult.ErrorCode -ceq 'PROBE_UNEXPECTED_ARGUMENTS') -Name 'ActualEntrypointRejectsUnexpectedArgument'
        Assert-F2Probe -Condition (-not $childStdout.Contains('C:\Dev') -and -not $childStdout.Contains('S-1-')) -Name 'ArgumentFailureOutputSanitized'
    } finally { $child.Dispose() }
    $files = @($modulePath,$probePath)
    $forbiddenCommands = @(
        'Start-Process','Set-Acl','icacls','New-Item','Remove-Item','Move-Item','Copy-Item',
        'Invoke-F2ProtectedReleaseUpdate','Invoke-F2ProtectedReleaseRecovery','Invoke-F2UpdateTransaction',
        'Resolve-F2UpdateTransaction','Get-VM','Get-VMNetworkAdapter','New-VM','Start-VM','Stop-VM',
        'Get-Disk','Get-Volume','Add-Content','Out-File','Set-Content','Export-Csv','Clear-Content'
    )
    foreach ($file in $files) {
        $ast = Get-F2ProbeAstForFile -Path $file
        $commands = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] },$true) |
            ForEach-Object { [string]$_.GetCommandName() } | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $matches = @($commands | Where-Object { $forbiddenCommands -icontains $_ })
        Assert-F2Probe -Condition ($matches.Count -eq 0) -Name ('NoForbiddenCommand:' + [IO.Path]::GetFileName($file))
        $invokes = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] },$true))
        $methodNames = @($invokes | ForEach-Object { [string]$_.Member.Extent.Text })
        $writeMethods = @($invokes | Where-Object { [string]$_.Member.Extent.Text -match '^(?i:Write|Append|Delete|Move|CreateDirectory|SetAccessControl|SetSecurityDescriptor|SetOwner)' })
        Assert-F2Probe -Condition ($writeMethods.Count -eq 0) -Name ('NoForbiddenWriteMethod:' + [IO.Path]::GetFileName($file))
    }

    $sourceText = [IO.File]::ReadAllText($modulePath) + [IO.File]::ReadAllText($probePath)
    Assert-F2Probe -Condition ($sourceText -notmatch '(?i)C:\\Program Files\\F2-G1-Icacls|C:\\ProgramData\\F2-G1-Icacls|G:\\|F2-G1-Isolated-Disposable') -Name 'NoProtectedPathReferences'
    $drivePathLiterals = @([regex]::Matches($sourceText,'(?i)\b[A-Z]:\\[^'']*') | ForEach-Object { $_.Value })
    $unsafeDrivePaths = @($drivePathLiterals | Where-Object { $_ -notmatch '^(?i)C:\\Dev(?:\\|$)' })
    Assert-F2Probe -Condition ($unsafeDrivePaths.Count -eq 0) -Name 'AllProductionPathLiteralsStayUnderDev'
    Assert-F2Probe -Condition ($sourceText -notmatch '(?i)-Verb\s+RunAs|Start-Process') -Name 'NoUacLaunchCommand'

    Write-Output ('Assertions=' + $assertions + ';Failures=' + $failures.Count)
    foreach ($failure in $failures) { Write-Output ('ASSERTION_FAILED:' + $failure) }
    if ($failures.Count -gt 0) { exit 1 }
    exit 0
} catch {
    Write-Output ('F2_HISTORICAL_MANIFEST_DIAGNOSTIC_TEST_FAILED:' + ([string]$_.FullyQualifiedErrorId).Split(',')[0])
    exit 1
}
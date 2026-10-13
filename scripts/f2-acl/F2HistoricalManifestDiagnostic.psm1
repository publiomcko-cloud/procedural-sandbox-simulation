Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:F2HistoricalUpdaterSha256 = 'd9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2'
$script:F2HistoricalLauncherSha256 = '9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
$script:F2HistoricalProtocolSha256 = '66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7'
$script:F2HistoricalCandidateSha256 = 'b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
$script:F2HistoricalSourceCommit = '396c44965c90c08292ad2835f8317e81b6b9daaf'
$script:F2UpdateDiagnosticProtocolSha256 = $script:F2HistoricalProtocolSha256
$script:F2UpdateBaselineMailboxId = 'ecb6deeb424e40feb5354d18908986df'
$script:F2UpdateBaselineCaptureId = '489e7fec-0300-467c-bfbd-a46fb8cf7211'
$script:F2UpdateBaselinePayloadSha256 = '1b5eee9aae928a909d4c251a4dd6d2c0898c400e2807e0acc3268d61d5149014'
$script:F2UpdateBaselineIntegritySha256 = '02d6f07f5b3bb6f47a84e58d7c207c9935481e8a898a3b1f5e1ed273d4d61b34'
$script:F2UpdateOldPins = [ordered]@{
    'F2AclCapture.Protocol.psm1' = '42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'
    'F2AclIcacls.Corroboration.psm1' = 'a52ed86218a0ba0c0801ee6e84a4a5e47c73eda43db78f818b0b12670ad5110b'
    'F2AclIcacls.Runtime.psm1' = '950b8232be2f22412e837d63f7b2fb678fc83871862b6bafc714d303599a71a5'
    'Invoke-F2IcaclsCapture.ps1' = 'fb55240a16f0858980bb38851414b28ce5f403ba26697ff78f227ca22ff804b0'
    'Invoke-F2IcaclsProtectedCoordinator.ps1' = '3badc19c8ac6ac450f9691258c6ecd2a3754cd665fd5989325c90b64290ae9e2'
    'F2_ICACLS_SOURCE_PINS.json' = 'bd0a66a5e81494acaa14facb48b58e4c485acda1c17ead4fdfff220bcef97cd7'
    'Invoke-F2AclReadOnlyCapture.ps1' = 'bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b'
}

function Get-F2ProbeSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-F2ProbeFunctionAst {
    param(
        [Parameter(Mandatory)][Management.Automation.Language.ScriptBlockAst]$Ast,
        [Parameter(Mandatory)][string]$Name
    )
    $matches = @($Ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name
    }, $true))
    if ($matches.Count -ne 1) { throw 'PROBE_SOURCE_FUNCTION_SHAPE_INVALID' }
    return $matches[0]
}

function Assert-F2ProbeFunctionSafe {
    param(
        [Parameter(Mandatory)][Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AllowedCommands,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$AllowedMethods
    )
    $commands = @($FunctionAst.Body.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst]
    }, $true) | ForEach-Object { [string]$_.GetCommandName() } | Where-Object { -not [string]::IsNullOrEmpty($_) })
    $unexpectedCommands = @($commands | Where-Object { $AllowedCommands -notcontains $_ })
    $methods = @($FunctionAst.Body.FindAll({
        param($node)
        $node -is [Management.Automation.Language.InvokeMemberExpressionAst]
    }, $true) | ForEach-Object { [string]$_.Member.Extent.Text })
    $unexpectedMethods = @($methods | Where-Object { $AllowedMethods -notcontains $_ })
    if ($unexpectedCommands.Count -gt 0 -or $unexpectedMethods.Count -gt 0) { throw 'PROBE_SOURCE_FUNCTION_SHAPE_INVALID' }
}
function Get-F2ProbeScriptAst {
    param([Parameter(Mandatory)][string]$Text)
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if ($null -eq $ast -or $errors.Count -ne 0) { throw 'PROBE_SOURCE_PARSE_FAILED' }
    return $ast
}

function Get-F2ProbeSafeFailure {
    param(
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$Record,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][ValidateSet('STANDARD','ELEVATED')][string]$TokenClass,
        [Parameter(Mandatory)][string]$CandidateSha256
    )
    $rawId = [string]$Record.FullyQualifiedErrorId
    $safeId = 'UNLISTED'
    $headId = if ($rawId.Contains(',')) { $rawId.Substring(0, $rawId.IndexOf(',')) } else { $rawId }
    $safeIds = @(
        'PropertyNotFoundStrict','UPDATE_MANIFEST_SIZE_INVALID','UPDATE_MANIFEST_HASH_MISMATCH',
        'UPDATE_MANIFEST_JSON_INVALID','UPDATE_MANIFEST_SCHEMA_INVALID',
        'UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID','UPDATE_SOURCE_PINS_HASH_INVALID',
        'UPDATE_MANIFEST_FILE_SET_INVALID','UPDATE_MANIFEST_FILE_PIN_INVALID',
        'UPDATE_MANIFEST_PACKAGE_ROOT_INVALID','UPDATE_CANDIDATE_COMMIT_MISMATCH',
        'PROBE_UPDATER_HASH_MISMATCH','PROBE_LAUNCHER_HASH_MISMATCH',
        'PROBE_PROTOCOL_HASH_MISMATCH','PROBE_CANDIDATE_HASH_MISMATCH',
        'PROBE_BOOTSTRAP_STATEMENT_MISMATCH','PROBE_SOURCE_FUNCTION_SHAPE_INVALID',
        'PROBE_SOURCE_PARSE_FAILED','PROBE_SOURCE_INPUT_INVALID','PROBE_UNCLASSIFIED_FAILURE',
        'PROBE_BOOTSTRAP_CALL_SHAPE_INVALID','PROBE_BOOTSTRAP_COMPARISON_SHAPE_INVALID','PROBE_BOOTSTRAP_STATEMENT_TEXT_INVALID'
    )
    if ($headId -cin $safeIds) { $safeId = $headId }

    $category = 'UNEXPECTED_POWERSHELL_EXCEPTION'
    if ($safeId -ceq 'PropertyNotFoundStrict') { $category = 'STRICTMODE_MISSING_PROPERTY' }
    elseif ($safeId -like 'UPDATE_MANIFEST_*' -or $safeId -like 'UPDATE_SOURCE_PINS_*') { $category = 'HISTORICAL_MANIFEST_REJECTION' }
    elseif ($safeId -ceq 'UPDATE_CANDIDATE_COMMIT_MISMATCH') { $category = 'REVIEWED_COMMIT_MISMATCH' }
    elseif ($safeId -like 'PROBE_*') { $category = 'PROBE_VALIDATION_FAILURE' }

    return [pscustomobject][ordered]@{
        Schema = 'f2-g1-historical-manifest-diagnostic-v1'
        Authority = 'NON_AUTHORITATIVE_DIAGNOSTIC_ONLY'
        Status = 'FAIL'
        Stage = $Stage
        OperationClassification = $Operation
        ExceptionCategory = $category
        FullyQualifiedErrorId = $safeId
        ErrorCode = $safeId
        TokenClass = $TokenClass
        HistoricalSourceCommit = $script:F2HistoricalSourceCommit
        HistoricalUpdaterSha256 = $script:F2HistoricalUpdaterSha256
        HistoricalLauncherSha256 = $script:F2HistoricalLauncherSha256
        HistoricalCandidateSha256 = $CandidateSha256
        UpdaterEntrypointInvoked = $false
        RecoveryEntrypointInvoked = $false
        ProtectedWritePerformed = $false
    }
}

function Invoke-F2HistoricalManifestDiagnosticCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$UpdaterBytes,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$LauncherBytes,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$ProtocolBytes,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$CandidateBytes,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExpectedCandidateSha256 = $script:F2HistoricalCandidateSha256,
        [Parameter(Mandatory)][ValidateSet('STANDARD','ELEVATED')][string]$TokenClass
    )
    $stage = 'InputIntegrityValidation'
    $operation = 'HistoricalInputHashValidation'
    $expectedCandidate = $ExpectedCandidateSha256
    $expectedSourceCommit = $script:F2HistoricalSourceCommit
    $candidateHash = $expectedCandidate
    try {
        if ($UpdaterBytes.Length -lt 1 -or $UpdaterBytes.Length -gt 4194304 -or (Get-F2ProbeSha256 -Bytes $UpdaterBytes) -cne $script:F2HistoricalUpdaterSha256) { throw 'PROBE_UPDATER_HASH_MISMATCH' }
        if ($LauncherBytes.Length -lt 1 -or $LauncherBytes.Length -gt 4194304 -or (Get-F2ProbeSha256 -Bytes $LauncherBytes) -cne $script:F2HistoricalLauncherSha256) { throw 'PROBE_LAUNCHER_HASH_MISMATCH' }
        if ($ProtocolBytes.Length -lt 1 -or $ProtocolBytes.Length -gt 4194304 -or (Get-F2ProbeSha256 -Bytes $ProtocolBytes) -cne $script:F2HistoricalProtocolSha256) { throw 'PROBE_PROTOCOL_HASH_MISMATCH' }
        if ($CandidateBytes.Length -lt 1 -or $CandidateBytes.Length -gt 65536 -or (Get-F2ProbeSha256 -Bytes $CandidateBytes) -cne $ExpectedCandidateSha256) { throw 'PROBE_CANDIDATE_HASH_MISMATCH' }

        $stage = 'HistoricalBootstrapShapeValidation'
        $operation = 'PinnedSourceParsing'
        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $updaterText = $utf8.GetString($UpdaterBytes)
        $launcherText = $utf8.GetString($LauncherBytes)
        $updaterAst = Get-F2ProbeScriptAst -Text $updaterText
        $launcherAst = Get-F2ProbeScriptAst -Text $launcherText

        $updaterHashAst = Get-F2ProbeFunctionAst -Ast $updaterAst -Name 'Get-F2UpdateSha256'
        $manifestAst = Get-F2ProbeFunctionAst -Ast $updaterAst -Name 'Get-F2UpdateManifestObject'
        $launcherHashAst = Get-F2ProbeFunctionAst -Ast $launcherAst -Name 'Get-F2UpdateLauncherSha256'
        $childBuilderAst = Get-F2ProbeFunctionAst -Ast $launcherAst -Name 'New-F2UpdateElevatedChildScript'
        $safeCryptoMethods = @('Create','ComputeHash','ToString','Replace','ToLowerInvariant','Dispose')
        Assert-F2ProbeFunctionSafe -FunctionAst $updaterHashAst -AllowedCommands @() -AllowedMethods $safeCryptoMethods
        Assert-F2ProbeFunctionSafe -FunctionAst $manifestAst -AllowedCommands @('Get-F2UpdateSha256','ConvertFrom-Json','Sort-Object','Compare-Object') -AllowedMethods @('IsNullOrWhiteSpace','ToLowerInvariant','GetString')
        Assert-F2ProbeFunctionSafe -FunctionAst $launcherHashAst -AllowedCommands @() -AllowedMethods $safeCryptoMethods
        Assert-F2ProbeFunctionSafe -FunctionAst $childBuilderAst -AllowedCommands @('ConvertTo-Json','Get-F2UpdateLauncherSha256') -AllowedMethods @('GetBytes','ToBase64String','Replace')

        . ([scriptblock]::Create($updaterHashAst.Extent.Text))
        . ([scriptblock]::Create($manifestAst.Extent.Text))
        . ([scriptblock]::Create($launcherHashAst.Extent.Text))
        . ([scriptblock]::Create($childBuilderAst.Extent.Text))

        $syntheticSid = -join [char[]]@(83,45,49,45,53,45,50,49,45,49,49,49,45,50,50,50,45,51,51,51,45,49,48,48,49)
        $request = [pscustomobject]@{
            Schema = 'f2-protected-release-update-request-v1'
            RequestId = '00000000000000000000000000000000'
            Nonce = '0000000000000000000000000000000000000000000000000000000000000000'
            PipeName = '\\.\pipe\F2SyntheticDiagnosticOnly'
            SourceCommit = $expectedSourceCommit
            LauncherSha256 = $script:F2HistoricalLauncherSha256
            UpdaterSha256 = $script:F2HistoricalUpdaterSha256
            CandidateManifestSha256 = $expectedCandidate
            RequesterPid = 12345
            RequesterCreationUtcTicks = 638000000000000000
            RequesterSidSha256 = ('0' * 64)
        }
        $builderArgs = @{
            UpdaterPath = 'C:\Dev\F2-DIAGNOSTIC-FIXTURE\updater.ps1'
            CandidatePath = 'C:\Dev\F2-DIAGNOSTIC-FIXTURE\candidate.json'
            SourceRoot = 'C:\Dev\F2-DIAGNOSTIC-FIXTURE\source'
            ExpectedSourceCommit = $expectedSourceCommit
            ExpectedLauncherSha256 = $script:F2HistoricalLauncherSha256
            ExpectedUpdaterSha256 = $script:F2HistoricalUpdaterSha256
            ExpectedCandidateManifestSha256 = $expectedCandidate
            ExpectedRequesterSid = $syntheticSid
            RequesterLauncherProcessId = 12345
            RequesterLauncherCreationUtcTicks = 638000000000000000
            DiagnosticRequest = $request
            DiagnosticProtocolPath = 'C:\Dev\F2-DIAGNOSTIC-FIXTURE\protocol.ps1'
            DiagnosticProtocolBytes = $ProtocolBytes
        }
        $childScript = New-F2UpdateElevatedChildScript @builderArgs
        if (-not ($childScript -is [string]) -or $childScript.Length -gt 262144) { throw 'PROBE_BOOTSTRAP_STATEMENT_MISMATCH' }
        $childTokens = $null
        $childErrors = $null
        $childAst = [Management.Automation.Language.Parser]::ParseInput($childScript, [ref]$childTokens, [ref]$childErrors)
        if ($null -eq $childAst -or $childErrors.Count -ne 0) { throw 'PROBE_SOURCE_PARSE_FAILED' }

        $callNodes = @($childAst.FindAll({
            param($node)
            if ($node -is [Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -ceq 'parsedCandidate') {
                return $node.Right.Extent.Text -match '(^|[^A-Za-z0-9_])Get-F2UpdateManifestObject([^A-Za-z0-9_]|$)'
            }
            return $false
        }, $true))
        $comparisonNodes = @($childAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.IfStatementAst] -and
                $node.Extent.Text -match 'UPDATE_CANDIDATE_COMMIT_MISMATCH'
        }, $true))
        if ($callNodes.Count -ne 1) { throw 'PROBE_BOOTSTRAP_CALL_SHAPE_INVALID' }
        if ($comparisonNodes.Count -ne 1) { throw 'PROBE_BOOTSTRAP_COMPARISON_SHAPE_INVALID' }
        $callText = $callNodes[0].Extent.Text.Trim()
        $comparisonText = $comparisonNodes[0].Extent.Text.Trim()
        $expectedComparison = 'if($parsedCandidate.ReviewedCommitSha -cne $expectedSourceCommit){throw ''UPDATE_CANDIDATE_COMMIT_MISMATCH''}'
        if ($callText -cne '$parsedCandidate=Get-F2UpdateManifestObject -Bytes $candidateBytes -ExpectedSchema v3 -ExpectedHash $expectedCandidate' -or
            $comparisonText -cne $expectedComparison) {
            throw 'PROBE_BOOTSTRAP_STATEMENT_TEXT_INVALID'
        }
        $candidateBytes = [byte[]]$CandidateBytes
        $operation = 'HistoricalManifestParserCall'
        $stage = 'CandidateManifestValidation'
        Set-StrictMode -Version Latest
        . ([scriptblock]::Create($callText))
        $operation = 'ReviewedCommitShaComparison'
        . ([scriptblock]::Create($comparisonText))

        return [pscustomobject][ordered]@{
            Schema = 'f2-g1-historical-manifest-diagnostic-v1'
            Authority = 'NON_AUTHORITATIVE_DIAGNOSTIC_ONLY'
            Status = 'PASS'
            Stage = $stage
            OperationClassification = 'ManifestParseAndReviewedCommitComparison'
            ExceptionCategory = 'NONE'
            FullyQualifiedErrorId = 'NONE'
            ErrorCode = 'NONE'
            TokenClass = $TokenClass
            HistoricalSourceCommit = $script:F2HistoricalSourceCommit
            HistoricalUpdaterSha256 = $script:F2HistoricalUpdaterSha256
            HistoricalLauncherSha256 = $script:F2HistoricalLauncherSha256
            HistoricalCandidateSha256 = $candidateHash
            ParsedReviewedCommitSha = $expectedSourceCommit
            UpdaterEntrypointInvoked = $false
            RecoveryEntrypointInvoked = $false
            ProtectedWritePerformed = $false
        }
    } catch {
        $safeStage = if ($stage -in @('InputIntegrityValidation','HistoricalBootstrapShapeValidation','CandidateManifestValidation')) { $stage } else { 'CandidateManifestValidation' }
        $safeOperation = if ($operation -in @('HistoricalInputHashValidation','PinnedSourceParsing','HistoricalManifestParserCall','ReviewedCommitShaComparison')) { $operation } else { 'HistoricalManifestParserCall' }
        return Get-F2ProbeSafeFailure -Record $_ -Stage $safeStage -Operation $safeOperation -TokenClass $TokenClass -CandidateSha256 $candidateHash
    }
}

Export-ModuleMember -Function Invoke-F2HistoricalManifestDiagnosticCore

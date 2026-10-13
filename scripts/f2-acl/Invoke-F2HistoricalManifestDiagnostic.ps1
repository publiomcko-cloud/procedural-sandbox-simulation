Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$stage = 'ProbeInitialization'
$tokenClass = 'STANDARD'
$exitCode = 1

function New-F2ProbeWrapperFailure {
    param([string]$SafeCode,[string]$SafeStage,[string]$TokenMode)
    return [pscustomobject][ordered]@{
        Schema = 'f2-g1-historical-manifest-diagnostic-v1'
        Authority = 'NON_AUTHORITATIVE_DIAGNOSTIC_ONLY'
        Status = 'FAIL'
        Stage = $SafeStage
        OperationClassification = 'ProbeInitialization'
        ExceptionCategory = 'PROBE_VALIDATION_FAILURE'
        FullyQualifiedErrorId = 'UNLISTED'
        ErrorCode = $SafeCode
        TokenClass = $TokenMode
        HistoricalSourceCommit = '396c44965c90c08292ad2835f8317e81b6b9daaf'
        HistoricalUpdaterSha256 = 'd9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2'
        HistoricalLauncherSha256 = '9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9'
        HistoricalCandidateSha256 = 'b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
        UpdaterEntrypointInvoked = $false
        RecoveryEntrypointInvoked = $false
        ProtectedWritePerformed = $false
    }
}

function Get-F2ProbeBytesSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Test-F2ProbeNoReparsePath {
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current)) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'PROBE_REPARSE_INPUT_REJECTED' }
        } else {
            throw 'PROBE_INPUT_UNAVAILABLE'
        }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $current) { break }
        $current = $parent
    }
}

try {
    if (@($MyInvocation.UnboundArguments).Count -ne 0) {
        throw 'PROBE_UNEXPECTED_ARGUMENTS'
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { $tokenClass = 'ELEVATED' }
    } finally {
        if ($null -ne $identity) { $identity.Dispose() }
    }

    $historicalRoot = 'C:\Dev\f2-g1-protected-updater-source'
    $candidateRoot = 'C:\Dev\f2-g1-protected-updater'
    $updaterPath = Join-Path $historicalRoot 'scripts\f2-acl\Invoke-F2ProtectedReleaseUpdate.ps1'
    $launcherPath = Join-Path $historicalRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'
    $protocolPath = Join-Path $historicalRoot 'scripts\f2-acl\F2ProtectedRelease.Diagnostics.ps1'
    $candidatePath = Join-Path $candidateRoot 'docs\reviews\f2-g1-protected-release-updater\f2-runtime-release-v3.candidate.json'
    $modulePath = Join-Path $PSScriptRoot 'F2HistoricalManifestDiagnostic.psm1'
    foreach ($inputPath in @($updaterPath,$launcherPath,$protocolPath,$candidatePath)) {
        Test-F2ProbeNoReparsePath -Path $inputPath
    }

    $stage = 'ModuleIntegrityValidation'
    $inMemoryModule = Get-Variable -Name 'F2HistoricalVerifiedModuleBytes' -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $inMemoryModule) {
        if ($inMemoryModule.Value -isnot [byte[]] -or $inMemoryModule.Value.Length -gt 131072) { throw 'PROBE_MODULE_INPUT_INVALID' }
        $moduleBytes = [byte[]]$inMemoryModule.Value
    } else {
        Test-F2ProbeNoReparsePath -Path $modulePath
        $moduleItem = Get-Item -LiteralPath $modulePath -Force -ErrorAction Stop
        if ($moduleItem.PSIsContainer -or $moduleItem.Length -gt 131072) { throw 'PROBE_MODULE_INPUT_INVALID' }
        $moduleBytes = [IO.File]::ReadAllBytes($modulePath)
        if ($moduleBytes.Length -ne $moduleItem.Length) { throw 'PROBE_MODULE_INPUT_INVALID' }
    }
    $moduleSha256 = Get-F2ProbeBytesSha256 -Bytes $moduleBytes
    if ($moduleSha256 -cne '4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee') { throw 'PROBE_MODULE_HASH_MISMATCH' }
    $moduleText = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($moduleBytes)
    $moduleScript = [scriptblock]::Create($moduleText)
    $moduleInfo = New-Module -Name 'F2HistoricalManifestDiagnostic' -ScriptBlock $moduleScript -Force
    Import-Module -ModuleInfo $moduleInfo -Force -ErrorAction Stop | Out-Null

    $stage = 'HistoricalInputRead'
    $inputs = @(
        @{ Path = $updaterPath; MaxBytes = 4194304 },
        @{ Path = $launcherPath; MaxBytes = 4194304 },
        @{ Path = $protocolPath; MaxBytes = 4194304 },
        @{ Path = $candidatePath; MaxBytes = 65536 }
    )
    $bytes = New-Object 'System.Collections.Generic.List[byte[]]'
    foreach ($input in $inputs) {
        $item = Get-Item -LiteralPath $input.Path -Force -ErrorAction Stop
        if ($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt $input.MaxBytes) { throw 'PROBE_INPUT_TYPE_OR_SIZE_INVALID' }
        $bytes.Add([IO.File]::ReadAllBytes($input.Path))
    }

    $stage = 'CandidateManifestValidation'
    $coreArgs = @{
        UpdaterBytes = [byte[]]$bytes[0]
        LauncherBytes = [byte[]]$bytes[1]
        ProtocolBytes = [byte[]]$bytes[2]
        CandidateBytes = [byte[]]$bytes[3]
        ExpectedCandidateSha256 = 'b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022'
        TokenClass = $tokenClass
    }
    $result = Invoke-F2HistoricalManifestDiagnosticCore @coreArgs
    if ($result.Status -ceq 'PASS') { $exitCode = 0 }
} catch {
    $safeCode = 'PROBE_UNCLASSIFIED_FAILURE'
    $safeStage = if ($stage -in @('ProbeInitialization','ModuleIntegrityValidation','HistoricalInputRead','CandidateManifestValidation')) { $stage } else { 'ProbeInitialization' }
    if ($_.FullyQualifiedErrorId -match 'PROBE_UNEXPECTED_ARGUMENTS') { $safeCode = 'PROBE_UNEXPECTED_ARGUMENTS' }
    elseif ($_.FullyQualifiedErrorId -match 'PROBE_REPARSE_INPUT_REJECTED') { $safeCode = 'PROBE_REPARSE_INPUT_REJECTED' }
    elseif ($_.FullyQualifiedErrorId -match 'PROBE_MODULE_HASH_MISMATCH') { $safeCode = 'PROBE_MODULE_HASH_MISMATCH' }
    elseif ($_.FullyQualifiedErrorId -match 'PROBE_MODULE_INPUT_INVALID') { $safeCode = 'PROBE_MODULE_INPUT_INVALID' }
    elseif ($_.FullyQualifiedErrorId -match 'PROBE_INPUT_UNAVAILABLE') { $safeCode = 'PROBE_INPUT_UNAVAILABLE' }
    elseif ($_.FullyQualifiedErrorId -match 'PROBE_INPUT_TYPE_OR_SIZE_INVALID') { $safeCode = 'PROBE_INPUT_TYPE_OR_SIZE_INVALID' }
    $result = New-F2ProbeWrapperFailure -SafeCode $safeCode -SafeStage $safeStage -TokenMode $tokenClass
}
$json = ConvertTo-Json -InputObject $result -Depth 5 -Compress
if ($json.Length -gt 4096) {
    $result = New-F2ProbeWrapperFailure -SafeCode 'PROBE_OUTPUT_BOUND_EXCEEDED' -SafeStage 'ProbeSerialization' -TokenMode $tokenClass
    $json = ConvertTo-Json -InputObject $result -Depth 5 -Compress
    $exitCode = 1
}
Write-Output $json
exit $exitCode

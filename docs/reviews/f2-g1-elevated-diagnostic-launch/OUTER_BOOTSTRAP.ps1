# Review source for the inert -EncodedCommand bootstrap documented beside this file.
# This file is not executed directly. The owner would copy the exact encoded command
# from the review handoff after independent review and separate authorization.
$env:PSModulePath = $PSHOME + '\Modules'
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$stage = 'BootstrapInitialization'
$uacAttempted = $false
$failureCode = 'OUTER_BOOTSTRAP_FAILED'
$launchRoot = 'C:\Dev\f2-g1-diagnostic-elevation-plan-source'
$expectedLaunchCommitSha = '8c2bddd90c6ac5214eeed08b5648d0ef30b58bf4'
$expectedRemote = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$expectedGitPath = 'C:\Program Files\Git\cmd\git.exe'
$expectedGitSha256 = '7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364'
$expectedLaunchModuleSha256 = 'ec40adb78eb54c1e6df92ca6ce142b85fe71e98340c30f185fc506e37a744432'
$expectedLauncherSha256 = 'a314696562b3b3fd4fbb0785d06bb6c243450c69282a48c9a73ff008d05ff258'

try {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'LAUNCH_PS_VERSION_INVALID' }
    if (-not [Environment]::Is64BitProcess) { throw 'LAUNCH_PS_ARCH_INVALID' }

    $modulePath = Join-Path $launchRoot 'scripts\f2-acl\F2HistoricalManifestLaunch.psm1'
    $current = [IO.Path]::GetFullPath($modulePath)
    while (-not [string]::IsNullOrEmpty($current)) {
        if (-not ([IO.File]::Exists($current) -or [IO.Directory]::Exists($current))) { throw 'LAUNCH_PATH_UNAVAILABLE' }
        $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'LAUNCH_REPARSE_PATH_REJECTED' }
        $parent = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $current) { break }
        $current = $parent
    }

    $stage = 'LaunchModuleIntegrity'
    $moduleItem = Get-Item -LiteralPath $modulePath -Force -ErrorAction Stop
    if ($moduleItem.PSIsContainer -or $moduleItem.Length -lt 1 -or $moduleItem.Length -gt 262144) { throw 'LAUNCH_FILE_TYPE_OR_SIZE_INVALID' }
    $stream = New-Object IO.FileStream($modulePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if ($stream.Length -ne $moduleItem.Length) { throw 'LAUNCH_FILE_CHANGED_DURING_READ' }
        $moduleBytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $moduleBytes.Length) {
            $read = $stream.Read($moduleBytes,$offset,$moduleBytes.Length-$offset)
            if ($read -le 0) { throw 'LAUNCH_FILE_TRUNCATED' }
            $offset += $read
        }
    } finally { $stream.Dispose() }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $moduleSha = ([BitConverter]::ToString($sha.ComputeHash($moduleBytes))).Replace('-','').ToLowerInvariant() } finally { $sha.Dispose() }
    if ($moduleSha -cne $expectedLaunchModuleSha256) { throw 'LAUNCH_MODULE_HASH_MISMATCH' }
    $moduleText = (New-Object System.Text.UTF8Encoding($false,$true)).GetString($moduleBytes)
    $moduleBlock = [scriptblock]::Create($moduleText)
    $moduleInfo = New-Module -Name 'F2HistoricalManifestLaunchOuterBootstrap' -ScriptBlock $moduleBlock -Force
    Import-Module -ModuleInfo $moduleInfo -Force -ErrorAction Stop | Out-Null

    $stage = 'RequesterTokenValidation'
    $token = Get-F2LaunchTokenFacts
    if ($token.IsAdministrator -or $token.IsElevated -or $token.IntegrityRid -ge 0x3000) { throw 'LAUNCH_REQUESTER_TOKEN_REQUIRED' }

    $stage = 'LaunchCheckoutValidation'
    $launchFacts = Get-F2LaunchRepositoryFacts -GitPath $expectedGitPath -ExpectedGitSha256 $expectedGitSha256 -Repository $launchRoot -ExpectedRoot $launchRoot -ExpectedHead $expectedLaunchCommitSha
    if (-not $launchFacts.Pass -or $launchFacts.Origin -cne $expectedRemote) { throw 'LAUNCH_CHECKOUT_MISMATCH' }

    $stage = 'LauncherIntegrity'
    $launcherPath = Join-Path $launchRoot 'scripts\f2-acl\Start-F2HistoricalManifestDiagnostic.ps1'
    $launcherBytes = Read-F2LaunchPinnedFile -Path $launcherPath -ExpectedSha256 $expectedLauncherSha256 -MaximumBytes 262144
    $launcherBlock = ConvertTo-F2LaunchVerifiedScriptBlock -Bytes $launcherBytes -ExpectedSha256 $expectedLauncherSha256 -MaximumBytes 262144

    # Start-F2HistoricalManifestDiagnostic performs fresh requester/source/input
    # checks, creates the one-shot pipe, and contains the sole RunAs call site.
    $stage = 'VerifiedLauncherInvocation'
    & $launcherBlock -ExpectedLaunchCommitSha $expectedLaunchCommitSha -ExpectedLauncherSha256 $expectedLauncherSha256 -ExpectedLaunchModuleSha256 $expectedLaunchModuleSha256 -ExecuteApprovedProbe
    exit $LASTEXITCODE
} catch {
    $head = ([string]$_.FullyQualifiedErrorId).Split(',')[0]
    $safe = @('LAUNCH_PS_VERSION_INVALID','LAUNCH_PS_ARCH_INVALID','LAUNCH_PATH_UNAVAILABLE','LAUNCH_REPARSE_PATH_REJECTED','LAUNCH_FILE_TYPE_OR_SIZE_INVALID','LAUNCH_FILE_CHANGED_DURING_READ','LAUNCH_FILE_TRUNCATED','LAUNCH_MODULE_HASH_MISMATCH','LAUNCH_REQUESTER_TOKEN_REQUIRED','LAUNCH_CHECKOUT_MISMATCH','LAUNCH_GIT_PATH_REJECTED','LAUNCH_GIT_TIMEOUT','LAUNCH_GIT_OUTPUT_LIMIT','LAUNCH_GIT_DRAIN_INCOMPLETE','LAUNCH_GIT_QUERY_FAILED','LAUNCH_CHECKOUT_METADATA_REJECTED','LAUNCH_FILE_HASH_MISMATCH','LAUNCH_SCRIPT_PARSE_REJECTED')
    if ($head -in $safe) { $failureCode = $head }
    $record = [pscustomobject][ordered]@{
        Schema = 'f2-g1-diagnostic-outer-bootstrap-result-v1'
        Authority = 'NON_AUTHORITATIVE_DIAGNOSTIC_ONLY'
        Status = 'FAIL'
        Stage = $stage
        ErrorCode = $failureCode
        UacAttempted = $uacAttempted
        ProtectedOperationInvoked = $false
        RawErrorIncluded = $false
    }
    Write-Output (ConvertTo-Json -InputObject $record -Depth 3 -Compress)
    exit 1
}

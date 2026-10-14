Set-StrictMode -Version Latest

# F2 G1 V4: source-only Git checkout inspection, NEVER protected dispatch.
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseIntegration.V4.SourceOnly.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'F2ReleaseContract.V4.SourceOnly.psm1') -Force -ErrorAction Stop

function Assert-F2V4LocalFixedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[switch]$RequireFile)
    # Fail before I/O for UNC, rooted-relative, G:, device or drive-relative paths.
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]' -or $Path -match '^[Gg]:'){
        throw 'F2_V4_LOCAL_PATH_REQUIRED'
    }
    $full=[IO.Path]::GetFullPath($Path)
    if($full -notmatch '^[A-Za-z]:\\' -or $full -match '^[Gg]:' -or $full.StartsWith('\\')){
        throw 'F2_V4_CANONICAL_PATH_REJECTED'
    }
    $volume=[IO.DriveInfo]::new($full.Substring(0,3))
    if($volume.DriveType -ne [IO.DriveType]::Fixed){throw 'F2_V4_NONFIXED_DRIVE'}
    $item=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if($RequireFile){
        if($item.PSIsContainer -or $item.Length -lt 1 -or $item.Length -gt 134217728){
            throw 'F2_V4_TOOL_FILE_INVALID'
        }
    } elseif(-not $item.PSIsContainer){throw 'F2_V4_SOURCE_NOT_DIRECTORY'}
    $cursor=$full
    while(-not [string]::IsNullOrWhiteSpace($cursor)){
        $node=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if(($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
            throw 'F2_V4_REPARSE_ANCESTRY_REJECTED'
        }
        $parent=[IO.Directory]::GetParent($cursor)
        if($null -eq $parent){break}
        $cursor=$parent.FullName
    }
    return $full
}

function Invoke-F2V4BoundedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExecutablePath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$ArgumentsText,
        [ValidateRange(50,10000)][int]$TimeoutMilliseconds=4000,
        [ValidateRange(128,32768)][int]$MaxOutputBytes=16384
    )
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$ExecutablePath
    $psi.Arguments=$ArgumentsText
    $psi.WorkingDirectory=$WorkingDirectory
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    foreach($key in @($psi.EnvironmentVariables.Keys)){
        if(([string]$key).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase)){
            [void]$psi.EnvironmentVariables.Remove([string]$key)
        }
    }
    $psi.EnvironmentVariables['GIT_CONFIG_NOSYSTEM']='1'
    $psi.EnvironmentVariables['GIT_CONFIG_GLOBAL']='NUL'
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0'
    $psi.EnvironmentVariables['GIT_OPTIONAL_LOCKS']='0'
    $psi.EnvironmentVariables['GIT_CONFIG_COUNT']='0'
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$psi
    $stdout=[IO.MemoryStream]::new()
    $stderr=[IO.MemoryStream]::new()
    $bufferOut=New-Object byte[] 2048
    $bufferErr=New-Object byte[] 2048
    $clock=[Diagnostics.Stopwatch]::StartNew()
    try {
        if(-not $process.Start()){throw 'F2_V4_PROCESS_START_FAILED'}
        $readOut=$process.StandardOutput.BaseStream.ReadAsync($bufferOut,0,$bufferOut.Length)
        $readErr=$process.StandardError.BaseStream.ReadAsync($bufferErr,0,$bufferErr.Length)
        while($true){
            if($clock.ElapsedMilliseconds -gt $TimeoutMilliseconds){throw 'F2_V4_PROCESS_TIMEOUT'}
            if($null -ne $readOut -and $readOut.IsCompleted){
                $n=[int]$readOut.GetAwaiter().GetResult()
                $readOut=$null
                if($n -gt 0){
                    if(($stdout.Length+$stderr.Length+$n) -gt $MaxOutputBytes){throw 'F2_V4_OUTPUT_LIMIT'}
                    $stdout.Write($bufferOut,0,$n)
                    $readOut=$process.StandardOutput.BaseStream.ReadAsync($bufferOut,0,$bufferOut.Length)
                }
            }
            if($null -ne $readErr -and $readErr.IsCompleted){
                $n=[int]$readErr.GetAwaiter().GetResult()
                $readErr=$null
                if($n -gt 0){
                    if(($stdout.Length+$stderr.Length+$n) -gt $MaxOutputBytes){throw 'F2_V4_OUTPUT_LIMIT'}
                    $stderr.Write($bufferErr,0,$n)
                    $readErr=$process.StandardError.BaseStream.ReadAsync($bufferErr,0,$bufferErr.Length)
                }
            }
            if($null -eq $readOut -and $null -eq $readErr -and $process.HasExited){break}
            [Threading.Thread]::Sleep(5)
        }
        if($process.ExitCode -ne 0 -or $stderr.Length -ne 0){throw 'F2_V4_NONZERO_OR_STDERR'}
        $utf8=[Text.UTF8Encoding]::new($false,$true)
        return $utf8.GetString($stdout.ToArray()).TrimEnd([char[]]@([char]13,[char]10))
    } finally {
        $clock.Stop()
        try {
            if($process.Id -gt 0 -and -not $process.HasExited){
                $process.Kill()
                [void]$process.WaitForExit(1500)
            }
        } catch {}
        $stdout.Dispose()
        $stderr.Dispose()
        $process.Dispose()
    }
}

function Invoke-F2V4GitRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GitExecutable,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][ValidateSet('TopLevel','Worktree','Head','Status','Version')][string]$Query
    )
    $command=switch($Query){
        'TopLevel' {'rev-parse --show-toplevel'}
        'Worktree' {'rev-parse --is-inside-work-tree'}
        'Head' {'rev-parse --verify HEAD'}
        'Status' {'status --porcelain=v1 --untracked-files=normal --ignore-submodules=all'}
        'Version' {'--version'}
    }
    # No dynamic CLI arguments; ensure modern Git before "status".
    $flags='--no-optional-locks --no-pager -c core.fsmonitor=false -c core.untrackedCache=false -c core.hooksPath=NUL -c gc.auto=0 '
    return Invoke-F2V4BoundedProcess -ExecutablePath $GitExecutable -WorkingDirectory $RepositoryRoot -ArgumentsText ($flags+$command)
}

function Test-F2V4ReadOnlyPreDispatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Collector','Runtime','Coordinator','Launcher','Updater','Recovery')][string]$Role,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$ManifestBytes,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExternallyReviewedCommitSha,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExternallyApprovedManifestSha256,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExternallyApprovedActivePinsSha256,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedPackageHome,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$TrustedGitExecutablePath,
        [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExternallyPinnedGitExecutableSha256
    )
    $stage='ROOT'
    $passed=$false
    $actualHead=$null
    try {
        $root=Assert-F2V4LocalFixedPath -Path $SourceRoot
        $stage='GIT_EXECUTABLE'
        $gitPath=Assert-F2V4LocalFixedPath -Path $TrustedGitExecutablePath -RequireFile
        if([IO.Path]::GetFileName($gitPath) -cne 'git.exe'){throw 'F2_V4_GIT_EXE_REQUIRED'}
        $observedGitSha=(Get-FileHash -LiteralPath $gitPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        if($observedGitSha -cne $ExternallyPinnedGitExecutableSha256){throw 'F2_V4_GIT_BINARY_HASH_MISMATCH'}
        $stage='GIT_VERSION'
        $version=[string](Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Query Version)
        if($version -notmatch '^git version (\d+)\.(\d+)\.(\d+)'){throw 'F2_V4_GIT_VERSION_INVALID'}
        $major=[int]$Matches[1];$minor=[int]$Matches[2]
        if($major -lt 2 -or ($major -eq 2 -and $minor -lt 36)){throw 'F2_V4_GIT_TOO_OLD'}
        $stage='GIT_IDENTITY'
        $verifiedRoot=[string](Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Query TopLevel)
        $isWorktree=[string](Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Query Worktree)
        $actualHead=[string](Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Query Head)
        if($isWorktree -cne 'true' -or $actualHead -notmatch '^[0-9a-f]{40}$'){throw 'F2_V4_GIT_IDENTITY_INVALID'}
        $actualRoot=[IO.Path]::GetFullPath($verifiedRoot.Replace('/','\'))
        if(-not [string]::Equals($actualRoot,$root,[StringComparison]::OrdinalIgnoreCase)){throw 'F2_V4_WRONG_REPOSITORY_ROOT'}
        if($actualHead -cne $ExternallyReviewedCommitSha){throw 'F2_V4_COMMIT_MISMATCH'}
        $stage='GIT_DIRTY_STATE'
        $dirty=[string](Invoke-F2V4GitRead -GitExecutable $gitPath -RepositoryRoot $root -Query Status)
        if(-not [string]::IsNullOrEmpty($dirty)){throw 'F2_V4_DIRTY_SOURCE'}
        $stage='V4_SOURCE_PACKAGE'
        # Receipt authority remains external; the function never approves a release.
        $result=Test-F2V4IntegrationBoundary -Role $Role -Action Inspect -ManifestBytes $ManifestBytes -ExpectedManifestSha256 $ExternallyApprovedManifestSha256 -ExpectedActivePinsSha256 $ExternallyApprovedActivePinsSha256 -ExpectedCommitSha $ExternallyReviewedCommitSha -ActualCommitSha $actualHead -ExpectedPackageHome $ExpectedPackageHome -SourceRoot $root -VerifySourceBytes
        if(-not $result.Pass -or -not $result.SourceBytesVerified -or $result.HasSideEffects -or $result.CanInstall -or $result.CanActivate -or $result.CanRollback -or $result.CanResumeForward){
            throw 'F2_V4_READ_ONLY_CONTRACT_REJECTED'
        }
        $stage='SOURCE_ONLY_PRE_DISPATCH_ACCEPTED'
        $passed=$true
    } catch {
        $passed=$false
    }
    return [pscustomobject]@{
        Pass=$passed;Role=$Role
        Disposition=if($passed){'SOURCE_ONLY_INSPECTION_ACCEPTED'}else{'REJECTED'}
        Stage=$stage
        ErrorCode=if($passed){$null}else{'F2_V4_PRE_DISPATCH_REJECTED'}
        VerifiedCheckoutHead=if($passed){$actualHead}else{$null}
        GitHeadMatchesExpected=$passed
        CheckoutClean=$passed
        ExactTenSourceBytesVerified=$passed
        ExternalGitBinaryHashMatched=$passed
        GitToolchainIndependentlyAttested=$false
        ExternalReceiptIndependentlyAuthenticated=$false
        ReleaseApproved=$false
        CanDispatch=$false;CanCapture=$false;CanLaunch=$false;CanInstall=$false
        CanActivate=$false;CanRollback=$false;CanResumeForward=$false
        HasSideEffects=$false
        ExternalProcessSideEffectsUnprovable=$true
    }
}
Export-ModuleMember -Function Test-F2V4ReadOnlyPreDispatch

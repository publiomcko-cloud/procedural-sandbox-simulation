[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Count=0
$script:Failures=New-Object 'System.Collections.Generic.List[string]'
$script:SafeCleanup=$true
function Check([bool]$condition,[string]$label) {
    $script:Count++
    if($condition) { Write-Host ('PASS: '+$label) }
    else { $script:Failures.Add($label);Write-Host ('FAIL: '+$label) }
}
function Case {
    param(
        [string]$Wrapper,
        [string[]]$CaseArgs,
        [int]$ExpectedExit,
        [string]$ExpectedText,
        [int]$TimeoutMs=30000,
        [switch]$RedirectTemp
    )
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $psi.Arguments=(@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File','"'+$Wrapper+'"')+$CaseArgs) -join ' '
    if($RedirectTemp) {
        $psi.EnvironmentVariables['TEMP']='C:\Windows'
        $psi.EnvironmentVariables['TMP']='C:\Windows'
    }
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$psi
    $stdoutTask=$null;$stderrTask=$null
    $exited=$false;$timedOut=$false
    try {
        if (-not $p.Start()) { throw 'TEST_CHILD_START_FAILED' }
        $script:SafeCleanup=$false
        # Both streams are drained concurrently while the child runs; no
        # WaitForExit-before-ReadToEnd deadlock.
        $stdoutTask=$p.StandardOutput.ReadToEndAsync()
        $stderrTask=$p.StandardError.ReadToEndAsync()
        if(-not $p.WaitForExit($TimeoutMs)) {
            $timedOut=$true
            $p.Kill()
            if(-not $p.WaitForExit(5000)) { throw 'TEST_CHILD_KILL_UNCONFIRMED' }
        }
        $exited=$true
        if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutTask,$stderrTask),5000)) {throw 'TEST_CHILD_STREAM_DRAIN_UNCONFIRMED'}
        $script:SafeCleanup=$true
        $out=[string]$stdoutTask.Result
        $err=[string]$stderrTask.Result
        if($out.Length -gt 4096 -or $err.Length -gt 4096) {throw 'TEST_CHILD_OUTPUT_NOT_BOUNDED'}
        if($timedOut) { return [pscustomobject]@{Ok=$false;TimedOut=$true;Exited=$exited;Exit=-1;Stdout=$out;Stderr=$err} }
        $exit=$p.ExitCode
        return [pscustomobject]@{Ok=($exit -eq $ExpectedExit -and ($out+$err).Contains($ExpectedText));TimedOut=$false;Exited=$exited;Exit=$exit;Stdout=$out;Stderr=$err}
    } finally {
        if($p.HasExited) { $script:SafeCleanup=$true }
        $p.Dispose()
    }
}
function Remove-Fixture([string]$Path,[string]$TrustedParent) {
    $name=[IO.Path]::GetFileName($Path)
    if(-not [string]::Equals([IO.Path]::GetDirectoryName($Path),$TrustedParent,[StringComparison]::OrdinalIgnoreCase) -or
      $name -notmatch '^F2G1-R3Handle-[0-9a-fA-F-]{36}$') { throw 'UNSAFE_FIXTURE_CLEANUP' }
    if([IO.Directory]::Exists($Path)) { [IO.Directory]::Delete($Path,$true) }
}
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$bootstrap=Join-Path $root 'Invoke-F2G1R3.SourceOnly.ps1'
$native=Join-Path $root 'F2G1R3.TempHandleProbe.cs'
$scope=Join-Path $root 'F2G1R3.FixedScope.json'
$tokens=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($bootstrap,[ref]$tokens,[ref]$parseErrors)
Check ($parseErrors.Count -eq 0) 'R3.1 bootstrap parses under Windows PowerShell 5.1'
$source=[IO.File]::ReadAllText($bootstrap)
$nativeSource=[IO.File]::ReadAllText($native)
Check (-not $source.Contains('[switch]$Live') -and -not $source.Contains('OwnerAuthorizationReference') -and
    $source.Contains('Add-Type -TypeDefinition $code') -and -not $source.Contains('Add-Type -Path')) 'live is unavailable and compiler consumes verified held bytes'
Check ($nativeSource.Contains('OpenRelativeDirectory(volume,"Users")') -and
    $nativeSource.Contains('OpenRelativeDirectory(users,"Public")') -and
    $nativeSource.Contains('OpenRelativeDirectory(publicRoot,leaf)') -and
    -not $nativeSource.Contains('GetTempPath')) 'trusted fixture ancestors use no-follow relative handles, not TEMP/TMP'
Check ($source.Contains('9dcf97a9ad2636a28616278bc33d390443aca12ce3f930cbbcbcf8926fc800a1')) 'full canonical scope SHA-256 is pinned in prototype bootstrap'
try { Add-Type -Path $native -ErrorAction Stop;Check $true 'native C# compiles in PS5.1' }
catch { Check $false 'native C# compiles in PS5.1';throw }
$parent='C:\Users\Public'
if(-not [IO.Directory]::Exists($parent)) {throw 'MISSING_PINNED_TEST_PARENT'}
$fixture=Join-Path $parent ('F2G1-R3Handle-'+[guid]::NewGuid().ToString())
$junction=$null
$tamper=$null
[void][IO.Directory]::CreateDirectory($fixture)
try {
    [IO.File]::WriteAllBytes((Join-Path $fixture 'payload.bin'),[Text.Encoding]::UTF8.GetBytes('TEMP-fixture-only R3.1'))
    Write-Host ('SAFE_TEST_LEAF_LENGTH='+([IO.Path]::GetFileName($fixture)).Length+';PREFIX='+([IO.Path]::GetFileName($fixture)).StartsWith('F2G1-R3Handle-'))
    $h1=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToLowerInvariant()
    $h2=(Get-FileHash -LiteralPath $scope -Algorithm SHA256).Hash.ToLowerInvariant()
    $common=@('-SyntheticFixtureRoot',$fixture,'-ExpectedNativeSha256',$h1,'-ExpectedScopeSha256',$h2)
    $good=Case -Wrapper $bootstrap -CaseArgs $common -ExpectedExit 0 -ExpectedText 'TEMP_HANDLE_FIXTURE_PASS'
    if(-not $good.Ok) {Write-Host ('TEST_ONLY_DIAGNOSTIC:POSITIVE_EXIT='+$good.Exit+';STDERR='+$good.Stderr.Trim())}
    Check $good.Ok 'fixed parent and held relative file handles permit synthetic capture'
    $redirect=Case -Wrapper $bootstrap -CaseArgs $common -ExpectedExit 0 -ExpectedText 'TEMP_HANDLE_FIXTURE_PASS' -RedirectTemp
    Check $redirect.Ok 'redirected TEMP/TMP do not change trusted fixture parent'
    $rename=Case -Wrapper $bootstrap -CaseArgs ($common+@('-AttemptReplacement')) -ExpectedExit 0 -ExpectedText 'TEMP_HANDLE_FIXTURE_PASS'
    Check ($rename.Ok -and [IO.File]::Exists((Join-Path $fixture 'payload.bin'))) 'held file denies adversarial rename while open'
    $drift=Case -Wrapper $bootstrap -CaseArgs ($common+@('-InjectIdentityDrift')) -ExpectedExit 2 -ExpectedText 'BLOCKED_WITH_EVIDENCE'
    Check $drift.Ok 'injected identity drift blocks, no real race-free claim'
    $admin=Case -Wrapper $bootstrap -CaseArgs ($common+@('-SimulatePrivilegedToken')) -ExpectedExit 2 -ExpectedText 'SIMULATED_PRIVILEGED_TOKEN_REJECTED'
    Check $admin.Ok 'simulated token denial only, not actual admin enforcement'
    $hash=Case -Wrapper $bootstrap -CaseArgs @('-SyntheticFixtureRoot',$fixture,'-ExpectedNativeSha256',('0'*64),'-ExpectedScopeSha256',$h2) -ExpectedExit 2 -ExpectedText 'BLOCKED_WITH_EVIDENCE'
    Check $hash.Ok 'wrong native source digest fails closed'
    $scopeHash=Case -Wrapper $bootstrap -CaseArgs @('-SyntheticFixtureRoot',$fixture,'-ExpectedNativeSha256',$h1,'-ExpectedScopeSha256',('0'*64)) -ExpectedExit 2 -ExpectedText 'BLOCKED_WITH_EVIDENCE'
    Check $scopeHash.Ok 'wrong scope digest fails closed'
    $pathAlias=Case -Wrapper $bootstrap -CaseArgs @('-SyntheticFixtureRoot','C:\Windows\Temp\F2G1-R3Handle-11111111-1111-4111-8111-111111111111','-ExpectedNativeSha256',$h1,'-ExpectedScopeSha256',$h2) -ExpectedExit 2 -ExpectedText 'FIXED_FIXTURE_PARENT_ONLY'
    Check $pathAlias.Ok 'untrusted absolute fixture path is rejected before open'
    $untrusted=Case -Wrapper $bootstrap -CaseArgs @('-SyntheticFixtureRoot',($fixture+'\..\'+[IO.Path]::GetFileName($fixture)),'-ExpectedNativeSha256',$h1,'-ExpectedScopeSha256',$h2) -ExpectedExit 2 -ExpectedText 'FIXED_FIXTURE_PARENT_ONLY'
    Check $untrusted.Ok 'parent alias in requested fixture is rejected'
    $exclusive=[IO.FileStream]::new((Join-Path $fixture 'payload.bin'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $denied=Case -Wrapper $bootstrap -CaseArgs $common -ExpectedExit 2 -ExpectedText 'BLOCKED_WITH_EVIDENCE'
        Check $denied.Ok 'pre-existing exclusive file handle fails closed'
    } finally {$exclusive.Dispose()}
    [IO.File]::WriteAllText((Join-Path $fixture 'unexpected.bin'),'fixture-only')
    $extra=Case -Wrapper $bootstrap -CaseArgs $common -ExpectedExit 2 -ExpectedText 'BLOCKED_WITH_EVIDENCE'
    Check $extra.Ok 'unexpected child fails closed'
    [IO.File]::Delete((Join-Path $fixture 'unexpected.bin'))
    $junction=Join-Path $parent ('F2G1-R3Handle-'+[guid]::NewGuid().ToString())
    [void](New-Item -ItemType Junction -Path $junction -Target $fixture -ErrorAction Stop)
    $rp=Case -Wrapper $bootstrap -CaseArgs (@('-SyntheticFixtureRoot',$junction,'-ExpectedNativeSha256',$h1,'-ExpectedScopeSha256',$h2)) -ExpectedExit 2 -ExpectedText 'REPARSE_POINT_DENIED'
    Check $rp.Ok 'reparse in ancestor of payload is rejected via held no-follow directory handle'
    # Tamper a disposable COPY of native source/scope while giving the child
    # matching, attacker-picked hashes; the source is test code, never trusted.
    $tamper=Join-Path $parent ('F2G1-R3Handle-'+[guid]::NewGuid().ToString())
    [void][IO.Directory]::CreateDirectory($tamper)
    foreach($name in @('Invoke-F2G1R3.SourceOnly.ps1','F2G1R3.TempHandleProbe.cs','F2G1R3.FixedScope.json')) {
        [IO.File]::Copy((Join-Path $root $name),(Join-Path $tamper $name),$false)
    }
    $tBootstrap=Join-Path $tamper 'Invoke-F2G1R3.SourceOnly.ps1'
    $tNative=Join-Path $tamper 'F2G1R3.TempHandleProbe.cs'
    $tScope=Join-Path $tamper 'F2G1R3.FixedScope.json'
    $tNativeHash=(Get-FileHash $tNative -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::AppendAllText($tScope,'{"Mutated":true}')
    $tScopeHash=(Get-FileHash $tScope -Algorithm SHA256).Hash.ToLowerInvariant()
    $altered=Case -Wrapper $tBootstrap -CaseArgs @('-SyntheticFixtureRoot',$fixture,'-ExpectedNativeSha256',$tNativeHash,'-ExpectedScopeSha256',$tScopeHash) -ExpectedExit 2 -ExpectedText 'NONCANONICAL_FIXED_SCOPE'
    Check $altered.Ok 'altered-but-rehashed scope cannot bypass canonical byte pin'
    [IO.File]::Copy($scope,$tScope,$true)
    [IO.File]::AppendAllText($tNative,[Environment]::NewLine+'not valid c sharp !!!')
    $alteredNativeHash=(Get-FileHash $tNative -Algorithm SHA256).Hash.ToLowerInvariant()
    $badSource=Case -Wrapper $tBootstrap -CaseArgs @('-SyntheticFixtureRoot',$fixture,'-ExpectedNativeSha256',$alteredNativeHash,'-ExpectedScopeSha256',$h2) -ExpectedExit 2 -ExpectedText 'BLOCKED_WITH_EVIDENCE'
    Check $badSource.Ok 'malformed-but-rehashed native source never produces PASS'
    $timeout=Case -Wrapper $bootstrap -CaseArgs ($common+@('-SimulateDelaySeconds','10')) -ExpectedExit 2 -ExpectedText '' -TimeoutMs 350
    Check ($timeout.TimedOut -and $timeout.Exited) 'timed-out child is killed and confirmed exited before cleanup'
    [IO.File]::Delete((Join-Path $fixture 'payload.bin'))
    $missing=Case -Wrapper $bootstrap -CaseArgs $common -ExpectedExit 2 -ExpectedText 'BLOCKED_WITH_EVIDENCE'
    Check $missing.Ok 'missing fixture child is rejected'
} finally {
    if(-not $script:SafeCleanup) { throw 'TEST_CHILD_EXIT_UNCONFIRMED_FIXTURE_RETAINED' }
    if($null -ne $junction -and [IO.Directory]::Exists($junction)) {
        if(([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint) -eq 0) {throw 'UNSAFE_JUNCTION_CLEANUP'}
        [IO.Directory]::Delete($junction,$false)
    }
    if($null -ne $tamper) {Remove-Fixture -Path $tamper -TrustedParent $parent}
    Remove-Fixture -Path $fixture -TrustedParent $parent
}
Write-Host ('ASSERTIONS='+$script:Count+' FAILURES='+$script:Failures.Count)
if($script:Failures.Count -gt 0) {$script:Failures|ForEach-Object {Write-Host ('FAILED='+$_)};exit 1}
exit 0

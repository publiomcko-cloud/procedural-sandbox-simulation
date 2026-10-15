[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Count=0;$script:Failed=New-Object 'System.Collections.Generic.List[string]'
function Check([bool]$condition,[string]$label){
    $script:Count++
    if($condition){Write-Host ('PASS: '+$label)}else{$script:Failed.Add($label);Write-Host ('FAIL: '+$label)}
}
function Case([string]$wrapper,[string[]]$caseArgs,[int]$expectedExit,[string]$expectedText){
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    # Windows PowerShell 5.1/.NET Framework lacks ProcessStartInfo.ArgumentList.
    # Fixed source-only test arguments; never passed through untrusted input.
    $psi.Arguments=(@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File','"'+$wrapper+'"')+$caseArgs) -join ' '
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$psi
    $completed=$false;$stdout='';$stderr='';$exit=-1
    try{
        if(-not $p.Start()){throw 'CHILD_NOT_STARTED'}
        if(-not $p.WaitForExit(30000)){$p.Kill();throw 'SYNTHETIC_TEST_TIMEOUT'}
        $stdout=$p.StandardOutput.ReadToEnd();$stderr=$p.StandardError.ReadToEnd()
        $exit=$p.ExitCode;$completed=$true
    } finally {$p.Dispose()}
    return [pscustomobject]@{Ok=($completed -and $exit -eq $expectedExit -and ($stdout+$stderr).Contains($expectedText));Exit=$exit;Stdout=$stdout;Stderr=$stderr}
}
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$bootstrap=Join-Path $root 'Invoke-F2G1R3.SourceOnly.ps1'
$native=Join-Path $root 'F2G1R3.TempHandleProbe.cs'
$scope=Join-Path $root 'F2G1R3.FixedScope.json'
$tok=$null;$parse=$null
[void][Management.Automation.Language.Parser]::ParseFile($bootstrap,[ref]$tok,[ref]$parse)
Check ($parse.Count -eq 0) 'bootstrap parses on actual Windows PowerShell 5.1'
$source=[IO.File]::ReadAllText($bootstrap)
Check (-not $source.Contains('[switch]$Live') -and -not $source.Contains('OwnerAuthorizationReference') -and -not $source.Contains('Get-Acl')) 'R3 entrypoint provides no live or protected-host access mode'
$nativeSource=[IO.File]::ReadAllText($native)
Check ($nativeSource.Contains('NtCreateFile') -and $nativeSource.Contains('NtQueryDirectoryFile') -and $nativeSource.Contains('GetSecurityInfo')) 'experimental native code binds relative handle, inventory and ACL'
Check ($nativeSource.Contains('OUTSIDE_TEMP_FIXTURE') -and $nativeSource.Contains('F2G1-R3Handle-') -and -not $nativeSource.Contains('C:\\Program Files\\F2-G1-Icacls')) 'native probe has explicit TEMP-only fixture guard and no protected path constants'
# Source hash comparison is a fixture correctness check, NOT owner authorization.
$h1=(Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToLowerInvariant()
$h2=(Get-FileHash -LiteralPath $scope -Algorithm SHA256).Hash.ToLowerInvariant()
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$fixture=Join-Path $temp ('F2G1-R3Handle-'+[guid]::NewGuid().ToString())
[void][IO.Directory]::CreateDirectory($fixture)
try {
    [IO.File]::WriteAllBytes((Join-Path $fixture 'payload.bin'),[Text.Encoding]::UTF8.GetBytes('TEMP-only R3 handle probe'))
    $common=@('-SyntheticFixtureRoot','"'+$fixture+'"','-ExpectedNativeSha256',$h1,'-ExpectedScopeSha256',$h2)
    $good=Case $bootstrap $common 0 'TEMP_HANDLE_FIXTURE_PASS'
    if(-not $good.Ok) { Write-Host ('TEMP_ONLY_DIAGNOSTIC:POSITIVE_EXIT='+$good.Exit+';STDERR='+$good.Stderr.Trim()+';STDOUT='+$good.Stdout.Trim()) }
    Check $good.Ok 'held relative file and directory handles support TEMP-only positive capture'
    $changed=Case $bootstrap ($common+@('-AttemptReplacement')) 0 'TEMP_HANDLE_FIXTURE_PASS'
    Check $changed.Ok 'rename/replacement denied while held read-only handles remain open'
    Check ([IO.File]::Exists((Join-Path $fixture 'payload.bin'))) 'inert replacement attempt does not rename held TEMP file'
    $drift=Case $bootstrap ($common+@('-InjectIdentityDrift')) 2 'BLOCKED_WITH_EVIDENCE'
    Check $drift.Ok 'injected identity drift rejects with sanitized failure'
    $admin=Case $bootstrap ($common+@('-SimulatePrivilegedToken')) 2 'SIMULATED_PRIVILEGED_TOKEN_REJECTED'
    Check $admin.Ok 'simulated privileged token denied in TEMP-only bootstrap'

    $badHash=Case $bootstrap @('-SyntheticFixtureRoot','"'+$fixture+'"','-ExpectedNativeSha256',('0'*64),'-ExpectedScopeSha256',$h2) 2 'BLOCKED_WITH_EVIDENCE'
    if(-not $badHash.Ok) { Write-Host ('TEMP_ONLY_DIAGNOSTIC:NEGATIVE_EXIT='+$badHash.Exit+';STDERR='+$badHash.Stderr.Trim()+';STDOUT='+$badHash.Stdout.Trim()) }
    Check $badHash.Ok 'incorrect native source bytes reject before compile'
    $badScope=Case $bootstrap @('-SyntheticFixtureRoot','"'+$fixture+'"','-ExpectedNativeSha256',$h1,'-ExpectedScopeSha256',('0'*64)) 2 'BLOCKED_WITH_EVIDENCE'
    Check $badScope.Ok 'incorrect canonical scope digest rejects'
    [IO.File]::WriteAllText((Join-Path $fixture 'unexpected.txt'),'TEMP unexpected child')
    $unexpected=Case $bootstrap $common 2 'BLOCKED_WITH_EVIDENCE'
    Check $unexpected.Ok 'unexpected immediate TEMP child rejects'
    [IO.File]::Delete((Join-Path $fixture 'unexpected.txt'))
    [IO.File]::Delete((Join-Path $fixture 'payload.bin'))
    $missing=Case $bootstrap $common 2 'BLOCKED_WITH_EVIDENCE'
    Check $missing.Ok 'missing TEMP child rejects'
} finally {
    $full=[IO.Path]::GetFullPath($fixture).TrimEnd('\')
    if([IO.Path]::GetDirectoryName($full) -cne $temp -or [IO.Path]::GetFileName($full) -notmatch '^F2G1-R3Handle-[0-9a-fA-F-]{36}$'){throw 'UNSAFE_TEST_CLEANUP_PATH'}
    if([IO.Directory]::Exists($full)){[IO.Directory]::Delete($full,$true)}
}
Write-Host ('ASSERTIONS='+$script:Count+' FAILURES='+$script:Failed.Count)
if($script:Failed.Count -gt 0){$script:Failed|ForEach-Object{Write-Host ('FAILED='+$_)};exit 1}
exit 0

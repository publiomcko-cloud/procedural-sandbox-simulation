[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$powershell51=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$evidenceRoot=Join-Path $repoRoot 'docs\reviews\f2-g1-elevated-child-diagnostics\evidence'
$logPath=Join-Path $evidenceRoot 'WINDOWS_PS51_REGRESSION.log'
if(-not [IO.File]::Exists($powershell51)){throw 'WINDOWS_POWERSHELL_51_UNAVAILABLE'}
[void][IO.Directory]::CreateDirectory($evidenceRoot)
$encoding=New-Object Text.UTF8Encoding($false)
$writer=New-Object IO.StreamWriter($logPath,$false,$encoding)
$tests=@(
    'Test-F2AclCapture.Protocol.ps1',
    'Test-F2AclIcacls.Corroboration.ps1',
    'Test-F2AclIcacls.Runtime.ps1',
    'Test-F2AclEntrypointArguments.ps1',
    'Test-F2AclProtectedReleaseUpdater.ps1',
    'Test-F2AclProtectedReleaseNativeHelper.ps1',
    'Test-F2ProtectedReleaseDiagnostics.ps1'
)
$failed=0
try{
    $versionOutput=@(& $powershell51 -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.ToString()' 2>&1)
    $versionExit=$LASTEXITCODE
    $versionText=[string]::Join(' ',[string[]]$versionOutput).Trim()
    $version=$null
    if(-not [version]::TryParse($versionText,[ref]$version)){throw 'WINDOWS_POWERSHELL_51_VERSION_UNREADABLE'}
    $writer.WriteLine('Runner=Test-F2ProtectedReleaseDiagnosticSuites.ps1')
    $writer.WriteLine('PowerShell51Path='+$powershell51)
    $writer.WriteLine('PowerShellVersionOutput='+$versionText)
    $writer.WriteLine('PowerShellVersionExit='+$versionExit)
    if($versionExit -ne 0 -or $version.Major -ne 5 -or $version.Minor -ne 1){throw 'WINDOWS_POWERSHELL_51_VERSION_MISMATCH'}
    foreach($name in $tests){
        $testPath=Join-Path $PSScriptRoot $name
        $writer.WriteLine('=== '+$name+' ===')
        $writer.WriteLine('Command="'+$powershell51+'" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$testPath+'"')
        $lines=@(& $powershell51 -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $testPath 2>&1 | ForEach-Object { [string]$_ })
        $testExit=$LASTEXITCODE
        foreach($line in $lines){$writer.WriteLine($line);Write-Output $line}
        $writer.WriteLine('EXIT='+$testExit)
        Write-Output ('EXIT '+$name+'='+$testExit)
        if($testExit -ne 0){$failed++}
    }
    $writer.WriteLine('SUITES='+$tests.Count+';FAILED='+$failed)
    $writer.Flush()
}finally{$writer.Dispose()}
Write-Output ('SUITES='+$tests.Count+';FAILED='+$failed)
if($failed -ne 0){exit 1}
exit 0

[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourceRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($SourceRoot)
$files = @(& git -C $root ls-files 'scripts/f2-acl/*.ps1' 'scripts/f2-acl/*.psm1')
if ($LASTEXITCODE -ne 0 -or $files.Count -eq 0) { throw 'TrackedPowerShellFileEnumerationFailed.' }
$failures = New-Object 'System.Collections.Generic.List[string]'
foreach ($relative in $files) {
    $tokens = $null
    $parseErrors = $null
    $path = Join-Path $root $relative
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in $parseErrors) {
        $failures.Add(('{0}:{1}:{2}:{3}' -f $relative, $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message))
    }
}
Write-Output ('PowerShellVersion=' + $PSVersionTable.PSVersion.ToString())
Write-Output ('ParserFiles=' + $files.Count)
Write-Output ('ParserErrors=' + $failures.Count)
foreach ($failure in $failures) { Write-Output $failure }
if ($failures.Count -gt 0) { exit 1 }
exit 0

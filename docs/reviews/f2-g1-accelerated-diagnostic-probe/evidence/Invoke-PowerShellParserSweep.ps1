$ErrorActionPreference = 'Stop'
$repositoryRoot = [string](& git rev-parse --show-toplevel)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) { throw 'GIT_ROOT_UNAVAILABLE' }
$files = @(& git -C $repositoryRoot ls-files 'scripts/f2-acl/*.ps1' 'scripts/f2-acl/*.psm1')
if ($LASTEXITCODE -ne 0) { throw 'GIT_TRACKED_POWERSHELL_LIST_FAILED' }
$failures = New-Object 'System.Collections.Generic.List[string]'
foreach ($relativePath in $files) {
    $path = Join-Path $repositoryRoot $relativePath
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in $parseErrors) {
        $failures.Add("${relativePath}:$($parseError.Extent.StartLineNumber):$($parseError.Message)")
    }
}
Write-Output ("ParserRuntime=WindowsPowerShell $($PSVersionTable.PSVersion);Files=$($files.Count);Errors=$($failures.Count)")
$failures | ForEach-Object { Write-Output $_ }
if ($failures.Count -gt 0) { exit 1 }

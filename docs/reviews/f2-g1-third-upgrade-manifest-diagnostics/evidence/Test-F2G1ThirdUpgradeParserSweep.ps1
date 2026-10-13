[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = [IO.Path]::GetFullPath($RepoRoot)
$paths = New-Object 'System.Collections.Generic.List[string]'
$productionScriptRoot = Join-Path $root 'scripts\f2-acl'
foreach ($file in @(Get-ChildItem -LiteralPath $productionScriptRoot -File | Where-Object { $_.Extension -in @('.ps1','.psm1') } | Sort-Object FullName)) {
    $paths.Add([IO.Path]::GetFullPath($file.FullName))
}
foreach ($relative in @(
    'docs/reviews/f2-g1-third-upgrade-manifest-diagnostics/evidence/Test-F2G1CandidateManifestSourceChain.ps1',
    'docs/reviews/f2-g1-third-upgrade-manifest-diagnostics/evidence/Test-F2G1ThirdUpgradeParserSweep.ps1'
)) {
    $path = [IO.Path]::GetFullPath((Join-Path $root ($relative -replace '/', '\')))
    if (-not $paths.Contains($path)) { $paths.Add($path) }
}

$errors = New-Object 'System.Collections.Generic.List[string]'
foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add('MISSING:' + [IO.Path]::GetFileName($path))
        continue
    }
    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in $parseErrors) {
        $errors.Add(([IO.Path]::GetFileName($path) + ':' + $parseError.Extent.StartLineNumber + ':' + $parseError.ErrorId))
    }
}

Write-Output ('PowerShellVersion=' + $PSVersionTable.PSVersion.ToString())
Write-Output ('Scope=scripts/f2-acl plus two new review scripts')
Write-Output ('ParserFiles=' + $paths.Count + ';ParserErrors=' + $errors.Count)
foreach ($errorRecord in $errors) { Write-Output ('PARSE_ERROR=' + $errorRecord) }
if ($errors.Count -ne 0) { exit 1 }
exit 0

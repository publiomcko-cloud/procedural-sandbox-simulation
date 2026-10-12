[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptsRoot = [IO.Path]::GetFullPath((Join-Path $SourceRoot 'scripts\f2-acl'))
if (-not [IO.Directory]::Exists($scriptsRoot)) { throw 'PARSER_SOURCE_DIRECTORY_MISSING' }
$files = @(Get-ChildItem -LiteralPath $scriptsRoot -File -ErrorAction Stop | Where-Object { $_.Extension -in @('.ps1', '.psm1') })
if ($files.Count -ne 14) { throw 'PARSER_SOURCE_FILE_SET_UNEXPECTED' }

$failed = 0
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failed++
        Write-Output ('FAIL ' + $file.Name + ' parse-errors=' + $errors.Count)
    }
}

Write-Output ('ProductionPowerShellParserFiles=' + $files.Count + ';Failures=' + $failed)
if ($failed -gt 0) { exit 1 }

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$files=@(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'scripts\f2-acl') -File | Where-Object { $_.Extension -in @('.ps1','.psm1') } | Sort-Object FullName)
$errors=New-Object 'System.Collections.Generic.List[string]'
foreach($file in $files){
    $tokens=$null;$parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    foreach($parseError in $parseErrors){$errors.Add(($file.Name+':'+$parseError.Extent.StartLineNumber+':'+$parseError.Message))}
}
Write-Output ('PowerShellFiles='+$files.Count+';ParserErrors='+$errors.Count)
foreach($errorText in $errors){Write-Output ('PARSE_ERROR='+$errorText)}
if($errors.Count -ne 0){exit 1}
exit 0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$launcherPath = Join-Path $repoRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'
$source = [IO.File]::ReadAllText($launcherPath)
$start = $source.IndexOf('$childScript = @''', [StringComparison]::Ordinal)
if ($start -lt 0) { throw 'CHILD_TEMPLATE_START_MISSING' }
$bodyStart = $source.IndexOf("`n", $start, [StringComparison]::Ordinal) + 1
$end = $source.IndexOf("`n'@", $bodyStart, [StringComparison]::Ordinal)
if ($bodyStart -le 0 -or $end -le $bodyStart) { throw 'CHILD_TEMPLATE_END_MISSING' }
$child = $source.Substring($bodyStart, $end - $bodyStart)

$replacements = @{
    '__UPDATER_PATH__' = 'C:\Synthetic\updater.ps1'
    '__CANDIDATE_PATH__' = 'C:\Synthetic\candidate.json'
    '__UPDATER_SHA__' = ('a' * 64)
    '__LAUNCHER_SHA__' = ('b' * 64)
    '__CANDIDATE_SHA__' = ('c' * 64)
    '__REQUESTER_SID__' = 'S-1-5-21-111-222-333-1001' # Synthetic fixture identity only.
    '__REQUESTER_LAUNCHER_PID__' = '1234'
    '__REQUESTER_LAUNCHER_CREATION_TICKS__' = '638000000000000000'
    '__RECOVERY_TRANSACTION_ID__' = ''
    '__RESUME_FORWARD__' = '$false'
    '__SOURCE_ROOT__' = 'C:\Synthetic\SourceRoot'
}
foreach ($key in $replacements.Keys) { $child = $child.Replace($key, [string]$replacements[$key]) }

$tokens = $null
$errors = $null
[void][Management.Automation.Language.Parser]::ParseInput($child, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    $ids = @($errors | ForEach-Object { $_.ErrorId }) -join ','
    throw ('CHILD_TEMPLATE_PARSE_FAILED:' + $ids)
}
[void][scriptblock]::Create($child)
Write-Output ('EncodedChildTemplateParse=PASS;PSVersion=' + $PSVersionTable.PSVersion.ToString() + ';Characters=' + $child.Length)

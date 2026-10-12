[CmdletBinding()]
param(
    [string]$OutputPath = 'docs/reviews/f2-g1-elevated-child-diagnostics/evidence/ARTIFACT_MANIFEST.json',
    [string]$ExpectedReviewBase = '9e9915e6eb15bcb20cc2f5a1c990791e2a822b90',
    [string]$ProductionSourceCommit = '03882eedf3104fc33aa0cf503ddef9c9a6bec702'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256ForFile([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-StagedBlobSha256([string]$RelativePath) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = 'git'
    $start.Arguments = 'cat-file blob :' + '"' + $RelativePath + '"'
    $start.WorkingDirectory = (Get-Location).Path
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'GIT_BLOB_HASH_START_FAILED' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha.ComputeHash($process.StandardOutput.BaseStream)
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ('GIT_BLOB_HASH_FAILED:' + $RelativePath) }
        return ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose(); $process.Dispose() }
}

if ((git rev-parse HEAD).Trim() -cne $ExpectedReviewBase) { throw 'REVIEW_BASE_HEAD_MISMATCH' }
$stagedPaths = @(& git diff --cached --name-only)
if ($LASTEXITCODE -ne 0 -or $stagedPaths.Count -eq 0) { throw 'STAGED_PATH_INVENTORY_FAILED' }
$manifestRelative = $OutputPath.Replace('\', '/')
$files = New-Object 'System.Collections.Generic.List[object]'
foreach ($path in $stagedPaths) {
    $relative = ([string]$path).Replace('\', '/')
    if ($relative -ceq $manifestRelative) { continue }
    if ([IO.Path]::IsPathRooted($relative) -or $relative.Split('/') -contains '..') { throw 'STAGED_PATH_SCOPE_INVALID' }
    $diff = @(& git diff --quiet -- $relative 2>&1)
    if ($LASTEXITCODE -ne 0) { throw ('UNSTAGED_CONTENT_DIFF:' + $relative) }
    $physicalPath = Join-Path (Get-Location).Path $relative
    if (-not (Test-Path -LiteralPath $physicalPath -PathType Leaf)) { throw ('STAGED_FILE_MISSING:' + $relative) }
    $files.Add([ordered]@{
        Path = $relative
        CheckoutSha256 = Get-Sha256ForFile $physicalPath
        GitBlobSha256 = Get-StagedBlobSha256 $relative
    })
}
$manifest = [ordered]@{
    Schema = 'f2-g1-elevated-child-diagnostics-artifact-manifest-v1'
    ReviewBaseCommit = $ExpectedReviewBase
    ProductionSourceCommit = $ProductionSourceCommit
    ProductionSourceParent = '12575f4802f471210c0516b68b5d0d37d2eb8642'
    Files = @($files.ToArray())
    ManifestSelfHash = 'EXCLUDED_TO_AVOID_RECURSIVE_HASHING; report the committed manifest hash separately'
}
$json = ConvertTo-Json -InputObject $manifest -Depth 6
[IO.File]::WriteAllText((Join-Path (Get-Location).Path $OutputPath), ($json + "`n"), (New-Object Text.UTF8Encoding($false)))
Write-Output ('ManifestFiles=' + $files.Count)
Write-Output ('ManifestPath=' + $OutputPath)

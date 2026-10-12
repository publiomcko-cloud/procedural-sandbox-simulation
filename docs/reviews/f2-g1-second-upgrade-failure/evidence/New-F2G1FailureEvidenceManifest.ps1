[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
$scope = 'docs/reviews/f2-g1-second-upgrade-failure'
$git = (Get-Command git.exe -ErrorAction Stop).Source

function Get-StagedBlobBytes {
    param([Parameter(Mandatory)][string]$ObjectId)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $git
    $start.Arguments = 'cat-file blob ' + $ObjectId
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.CreateNoWindow = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'GIT_BLOB_READ_START_FAILED' }
    $memory = New-Object IO.MemoryStream
    try {
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw 'GIT_BLOB_READ_FAILED' }
        return ,$memory.ToArray()
    } finally {
        $memory.Dispose()
        $process.Dispose()
    }
}

$head = (& $git -C $repoRoot rev-parse HEAD 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'GIT_HEAD_READ_FAILED' }
$branch = (& $git -C $repoRoot branch --show-current 2>$null | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'GIT_BRANCH_READ_FAILED' }
$indexLines = @(& $git -C $repoRoot ls-files -s -- $scope)
if ($LASTEXITCODE -ne 0 -or $indexLines.Count -lt 1) { throw 'GIT_INDEX_SCOPE_EMPTY' }

$sha = [Security.Cryptography.SHA256]::Create()
$files = New-Object 'System.Collections.Generic.List[object]'
try {
    foreach ($line in $indexLines) {
        if ($line -notmatch '^100644 ([0-9a-f]{40}) 0\s+(.+)$') { throw 'GIT_INDEX_ENTRY_UNEXPECTED' }
        $objectId = $Matches[1]
        $path = $Matches[2].Replace('\','/')
        if ($path -ceq ($scope + '/evidence/EVIDENCE_MANIFEST.json')) { continue }
        $bytes = Get-StagedBlobBytes -ObjectId $objectId
        $digest = ([BitConverter]::ToString($sha.ComputeHash([byte[]]$bytes))).Replace('-','').ToLowerInvariant()
        $files.Add([pscustomobject]@{ Path=$path; GitBlob=$objectId; ByteCount=$bytes.Length; Sha256=$digest })
    }
} finally { $sha.Dispose() }

$manifest = [ordered]@{
    Schema = 'f2-g1-second-upgrade-failure-review-evidence-v1'
    ReviewBranch = $branch
    BaseCommit = $head
    EvidenceCommit = 'SELF_REFERENTIAL_COMMIT_SHA_OMITTED; report the final commit separately'
    RepositoryOrigin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
    ProductionCommitReviewed = '03882eedf3104fc33aa0cf503ddef9c9a6bec702'
    Pr62Head = '923c7d39d7fbfe106dea404c386efd4b5844654e'
    Pr63Head = '3dc05f98831924160474bfb5b554b2963d9a137b'
    ManifestSelfHash = 'EXCLUDED; publish receipt will report this file SHA-256'
    Files = @($files | Sort-Object Path)
}
$json = $manifest | ConvertTo-Json -Depth 8
$manifestPath = Join-Path $PSScriptRoot 'EVIDENCE_MANIFEST.json'
[IO.File]::WriteAllText($manifestPath,$json + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[Console]::Out.WriteLine('ManifestPath=evidence/EVIDENCE_MANIFEST.json')
[Console]::Out.WriteLine('Hashes=STAGED_GIT_BLOB_BYTES')
[Console]::Out.WriteLine('ManifestSelfHash=EXCLUDED')

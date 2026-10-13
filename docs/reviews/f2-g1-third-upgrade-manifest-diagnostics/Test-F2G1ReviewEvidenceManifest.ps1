[CmdletBinding()]
param(
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExpectedInventoryCommit = '12d97902d79b362ca406ef6f45422ef9ad54d5ef'
$script:MaximumEvidenceBytes = 2MB
$script:MaximumGitOutputBytes = 4MB

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-ByteEolKind {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    if ($Bytes -contains 0) { return 'BINARY' }
    $hasCrLf = $false
    $hasLf = $false
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 10) {
            if (($i -gt 0) -and ($Bytes[$i - 1] -eq 13)) { $hasCrLf = $true }
            else { $hasLf = $true }
        }
    }
    if ($hasCrLf -and $hasLf) { return 'MIXED' }
    if ($hasCrLf) { return 'CRLF' }
    if ($hasLf) { return 'LF' }
    return 'NONE'
}

function ConvertTo-WindowsArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if (($Value.Length -gt 0) -and ($Value -notmatch '[\s"]')) { return $Value }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * ((2 * $slashes) + 1)))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * (2 * $slashes))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Invoke-GitRaw {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$OutputLimit = $script:MaximumGitOutputBytes
    )

    $gitCommand = Get-Command git.exe -ErrorAction Stop
    $allArguments = @('-C', $RepositoryRoot) + $Arguments
    $quotedArguments = @($allArguments | ForEach-Object { ConvertTo-WindowsArgument -Value $_ })
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $gitCommand.Source
    $startInfo.Arguments = $quotedArguments -join ' '
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $output = New-Object System.IO.MemoryStream
    try {
        if (-not $process.Start()) { throw 'MANIFEST_GIT_START_FAILED' }
        $copyTask = $process.StandardOutput.BaseStream.CopyToAsync($output)
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            try { $process.Kill() } catch { }
            throw 'MANIFEST_GIT_TIMEOUT'
        }
        if (-not $copyTask.Wait(5000)) { throw 'MANIFEST_GIT_OUTPUT_DRAIN_TIMEOUT' }
        [void]$errorTask.Wait(5000)
        if ($output.Length -gt $OutputLimit) { throw 'MANIFEST_GIT_OUTPUT_LIMIT' }
        if ($process.ExitCode -ne 0) { throw ('MANIFEST_GIT_EXIT_' + $process.ExitCode) }
        return ,$output.ToArray()
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function Invoke-GitUtf8 {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [int]$OutputLimit = 4096
    )

    $bytes = Invoke-GitRaw -RepositoryRoot $RepositoryRoot -Arguments $Arguments -OutputLimit $OutputLimit
    return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes).TrimEnd("`r", "`n")
}

function Get-ManifestEntry {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$CommitSha,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $blobId = Invoke-GitUtf8 -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', '--verify', ($CommitSha + ':' + $RelativePath))
    if ($blobId -notmatch '^[0-9a-f]{40}$') { throw 'MANIFEST_GIT_BLOB_ID_INVALID' }
    $blobSizeText = Invoke-GitUtf8 -RepositoryRoot $RepositoryRoot -Arguments @('cat-file', '-s', $blobId)
    if ($blobSizeText -notmatch '^\d+$' -or [int64]$blobSizeText -gt $script:MaximumEvidenceBytes) { throw 'MANIFEST_GIT_BLOB_SIZE_INVALID' }
    $rawGitBytes = Invoke-GitRaw -RepositoryRoot $RepositoryRoot -Arguments @('cat-file', 'blob', $blobId) -OutputLimit $script:MaximumEvidenceBytes
    $checkoutBytes = Invoke-GitRaw -RepositoryRoot $RepositoryRoot -Arguments @('-c', 'core.autocrlf=true', 'cat-file', '--filters', ('--path=' + $RelativePath), $blobId) -OutputLimit $script:MaximumGitOutputBytes
    return [pscustomobject]@{
        Path = $RelativePath
        GitBlob = $blobId
        GitBytes = $rawGitBytes.Length
        GitSha256 = Get-Sha256Hex -Bytes $rawGitBytes
        WindowsCheckoutBytes = $checkoutBytes.Length
        WindowsCheckoutSha256 = Get-Sha256Hex -Bytes $checkoutBytes
        WindowsCheckoutEol = Get-ByteEolKind -Bytes $checkoutBytes
    }
}

function Assert-ManifestRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or $RelativePath.Contains('\') -or $RelativePath.StartsWith('/') -or $RelativePath.Contains(':')) {
        throw 'MANIFEST_PATH_INVALID'
    }
    foreach ($segment in $RelativePath.Split('/')) {
        if (($segment.Length -eq 0) -or ($segment -eq '.') -or ($segment -eq '..')) { throw 'MANIFEST_PATH_INVALID' }
    }
    $rootFull = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\') + '\'
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($RelativePath -replace '/', '\')))
    if (-not $candidate.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw 'MANIFEST_PATH_ESCAPE' }

    $current = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $segments = $RelativePath.Split('/')
    for ($i = 0; $i -lt $segments.Length; $i++) {
        $current = Join-Path $current $segments[$i]
        if (-not (Test-Path -LiteralPath $current)) { throw 'MANIFEST_PATH_MISSING' }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'MANIFEST_REPARSE_PATH' }
        if (($i -lt ($segments.Length - 1)) -and -not $item.PSIsContainer) { throw 'MANIFEST_PATH_NOT_DIRECTORY' }
        if (($i -eq ($segments.Length - 1)) -and $item.PSIsContainer) { throw 'MANIFEST_PATH_NOT_FILE' }
    }
}

function Test-ManifestContent {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ManifestText,
        [Parameter(Mandatory = $true)][string]$ExpectedCommitSha,
        [Parameter(Mandatory = $true)][int]$ExpectedEntryCount,
        [switch]$VerifyPhysicalCheckout
    )

    $lines = $ManifestText -split "`n"
    $headers = @{}
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($untrimmed in $lines) {
        $line = $untrimmed.TrimEnd("`r")
        if (($line.Length -eq 0) -or $line.StartsWith('#') -or $line.StartsWith('Path' + "`t")) {
            if ($line -match '^# ([A-Za-z][A-Za-z0-9]+)=([^\r\n]+)$') { $headers[$Matches[1]] = $Matches[2] }
            continue
        }
        $fields = $line.Split([char]9)
        if ($fields.Count -ne 7) { throw 'MANIFEST_ROW_FORMAT_INVALID' }
        $rows.Add([pscustomobject]@{
            Path = $fields[0]
            GitBlob = $fields[1]
            GitBytes = $fields[2]
            GitSha256 = $fields[3]
            WindowsCheckoutBytes = $fields[4]
            WindowsCheckoutSha256 = $fields[5]
            WindowsCheckoutEol = $fields[6]
        })
    }

    if ($headers['Schema'] -ne 'f2-review-evidence-manifest-v2') { throw 'MANIFEST_SCHEMA_INVALID' }
    if ($headers['InventoryCommit'] -ne $ExpectedCommitSha) { throw 'MANIFEST_INVENTORY_COMMIT_MISMATCH' }
    if ($headers['EntryCount'] -notmatch '^\d+$' -or [int]$headers['EntryCount'] -ne $ExpectedEntryCount -or $rows.Count -ne $ExpectedEntryCount) {
        throw 'MANIFEST_ENTRY_COUNT_MISMATCH'
    }

    $seen = @{}
    foreach ($row in $rows) {
        if ($seen.ContainsKey($row.Path)) { throw 'MANIFEST_DUPLICATE_PATH' }
        $seen[$row.Path] = $true
        Assert-ManifestRelativePath -RepositoryRoot $RepositoryRoot -RelativePath $row.Path
        if ($row.GitBlob -notmatch '^[0-9a-f]{40}$') { throw 'MANIFEST_GIT_BLOB_ID_INVALID' }
        if ($row.GitSha256 -notmatch '^[0-9a-f]{64}$' -or $row.WindowsCheckoutSha256 -notmatch '^[0-9a-f]{64}$') { throw 'MANIFEST_SHA256_INVALID' }
        if ($row.GitBytes -notmatch '^\d+$' -or $row.WindowsCheckoutBytes -notmatch '^\d+$') { throw 'MANIFEST_BYTE_COUNT_INVALID' }
        if ([int64]$row.GitBytes -gt $script:MaximumEvidenceBytes -or [int64]$row.WindowsCheckoutBytes -gt $script:MaximumGitOutputBytes) { throw 'MANIFEST_BYTE_LIMIT_EXCEEDED' }
        if ($row.WindowsCheckoutEol -notin @('BINARY', 'CRLF', 'LF', 'MIXED', 'NONE')) { throw 'MANIFEST_EOL_KIND_INVALID' }

        $inventoryBlob = Invoke-GitUtf8 -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', '--verify', ($ExpectedCommitSha + ':' + $row.Path))
        $head = Invoke-GitUtf8 -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', '--verify', 'HEAD')
        $headBlob = Invoke-GitUtf8 -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', '--verify', ($head + ':' + $row.Path))
        if (($inventoryBlob -ne $row.GitBlob) -or ($headBlob -ne $row.GitBlob)) { throw 'MANIFEST_BLOB_ID_MISMATCH' }

        $actual = Get-ManifestEntry -RepositoryRoot $RepositoryRoot -CommitSha $ExpectedCommitSha -RelativePath $row.Path
        if (($actual.GitBytes -ne [int64]$row.GitBytes) -or ($actual.GitSha256 -ne $row.GitSha256)) { throw 'MANIFEST_GIT_BYTES_MISMATCH' }
        if (($actual.WindowsCheckoutBytes -ne [int64]$row.WindowsCheckoutBytes) -or ($actual.WindowsCheckoutSha256 -ne $row.WindowsCheckoutSha256) -or ($actual.WindowsCheckoutEol -ne $row.WindowsCheckoutEol)) {
            throw 'MANIFEST_WINDOWS_CHECKOUT_BYTES_MISMATCH'
        }
        if ($VerifyPhysicalCheckout) {
            $physicalPath = Join-Path $RepositoryRoot ($row.Path -replace '/', '\')
            $physicalBytes = [System.IO.File]::ReadAllBytes($physicalPath)
            if (($physicalBytes.Length -ne [int64]$row.WindowsCheckoutBytes) -or ((Get-Sha256Hex -Bytes $physicalBytes) -ne $row.WindowsCheckoutSha256)) {
                throw 'MANIFEST_PHYSICAL_CHECKOUT_MISMATCH'
            }
        }
    }
    return $rows.Count
}

function New-TestManifestText {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$CommitSha,
        [Parameter(Mandatory = $true)][string[]]$Paths
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# F2 G1 synthetic evidence manifest')
    $lines.Add('# Schema=f2-review-evidence-manifest-v2')
    $lines.Add('# InventoryCommit=' + $CommitSha)
    $lines.Add('# EntryCount=' + $Paths.Count)
    $lines.Add('# GitSha256=SHA-256 of raw bytes returned by git cat-file blob; GitBytes is that raw length.')
    $lines.Add('# WindowsCheckoutSha256=SHA-256 of git cat-file --filters output with core.autocrlf=true and the path attributes applied.')
    $lines.Add('# WindowsCheckoutBytes and WindowsCheckoutEol describe that filtered Windows checkout representation.')
    $lines.Add('')
    $lines.Add('Path' + "`t" + 'GitBlob' + "`t" + 'GitBytes' + "`t" + 'GitSha256' + "`t" + 'WindowsCheckoutBytes' + "`t" + 'WindowsCheckoutSha256' + "`t" + 'WindowsCheckoutEol')
    foreach ($path in $Paths) {
        $entry = Get-ManifestEntry -RepositoryRoot $RepositoryRoot -CommitSha $CommitSha -RelativePath $path
        $lines.Add(($entry.Path, $entry.GitBlob, $entry.GitBytes, $entry.GitSha256, $entry.WindowsCheckoutBytes, $entry.WindowsCheckoutSha256, $entry.WindowsCheckoutEol) -join "`t")
    }
    return ($lines -join "`n") + "`n"
}

function Invoke-ExpectedManifestFailure {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ManifestText,
        [Parameter(Mandatory = $true)][string]$ExpectedCommitSha,
        [Parameter(Mandatory = $true)][int]$ExpectedEntryCount,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage
    )

    try {
        [void](Test-ManifestContent -RepositoryRoot $RepositoryRoot -ManifestText $ManifestText -ExpectedCommitSha $ExpectedCommitSha -ExpectedEntryCount $ExpectedEntryCount -VerifyPhysicalCheckout)
        throw 'SELFTEST_EXPECTED_FAILURE_NOT_RAISED'
    }
    catch {
        if ($_.Exception.Message -eq 'SELFTEST_EXPECTED_FAILURE_NOT_RAISED') { throw }
        if ($_.Exception.Message -ne $ExpectedMessage) { throw ('SELFTEST_WRONG_FAILURE expected=' + $ExpectedMessage + ' actual=' + $_.Exception.Message) }
    }
}

function Invoke-SelfTest {
    $tempRoot = Join-Path $env:TEMP ('f2-review-evidence-manifest-' + [Guid]::NewGuid().ToString('N'))
    $assertions = 0
    try {
        [void][System.IO.Directory]::CreateDirectory($tempRoot)
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('init', '--quiet'))
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('config', 'user.name', 'F2 Manifest Test'))
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('config', 'user.email', 'f2-manifest-test@example.invalid'))
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('config', 'core.autocrlf', 'true'))
        [System.IO.File]::WriteAllText((Join-Path $tempRoot '.gitattributes'), "*.txt text=auto`n", (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'alpha.txt'), [System.Text.Encoding]::UTF8.GetBytes("alpha`nbeta`n"))
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'payload.bin'), [byte[]]@(0, 1, 2, 255))
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('add', '.'))
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('commit', '--quiet', '-m', 'synthetic manifest fixture'))
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('-c', 'core.autocrlf=true', 'checkout-index', '--force', '--', 'alpha.txt', 'payload.bin', '.gitattributes'))
        foreach ($path in @('alpha.txt', 'payload.bin', '.gitattributes')) { [System.IO.File]::Delete((Join-Path $tempRoot $path)) }
        [void](Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('-c', 'core.autocrlf=true', 'checkout-index', '--all', '--force'))
        $commit = Invoke-GitUtf8 -RepositoryRoot $tempRoot -Arguments @('rev-parse', '--verify', 'HEAD')
        $valid = New-TestManifestText -RepositoryRoot $tempRoot -CommitSha $commit -Paths @('alpha.txt', 'payload.bin')
        if ((Test-ManifestContent -RepositoryRoot $tempRoot -ManifestText $valid -ExpectedCommitSha $commit -ExpectedEntryCount 2 -VerifyPhysicalCheckout) -ne 2) { throw 'SELFTEST_VALID_COUNT_FAILED' }
        $assertions++

        $validLines = $valid -split "`n"
        $rowIndexes = @(); for ($i = 0; $i -lt $validLines.Length; $i++) { if ($validLines[$i] -match '^(alpha\.txt|payload\.bin)\t') { $rowIndexes += $i } }
        $badGit = @($validLines); $fields = $badGit[$rowIndexes[0]].Split([char]9); $fields[3] = ('0' * 64); $badGit[$rowIndexes[0]] = $fields -join "`t"
        Invoke-ExpectedManifestFailure -RepositoryRoot $tempRoot -ManifestText (($badGit -join "`n")) -ExpectedCommitSha $commit -ExpectedEntryCount 2 -ExpectedMessage 'MANIFEST_GIT_BYTES_MISMATCH'; $assertions++

        $badCheckout = @($validLines); $fields = $badCheckout[$rowIndexes[0]].Split([char]9); $fields[5] = ('f' * 64); $badCheckout[$rowIndexes[0]] = $fields -join "`t"
        Invoke-ExpectedManifestFailure -RepositoryRoot $tempRoot -ManifestText (($badCheckout -join "`n")) -ExpectedCommitSha $commit -ExpectedEntryCount 2 -ExpectedMessage 'MANIFEST_WINDOWS_CHECKOUT_BYTES_MISMATCH'; $assertions++

        $missing = ($validLines | Where-Object { $_ -notmatch '^payload\.bin\t' }) -join "`n"
        Invoke-ExpectedManifestFailure -RepositoryRoot $tempRoot -ManifestText $missing -ExpectedCommitSha $commit -ExpectedEntryCount 2 -ExpectedMessage 'MANIFEST_ENTRY_COUNT_MISMATCH'; $assertions++

        $duplicate = @($validLines); $duplicate[$rowIndexes[1]] = $duplicate[$rowIndexes[0]]
        Invoke-ExpectedManifestFailure -RepositoryRoot $tempRoot -ManifestText (($duplicate -join "`n")) -ExpectedCommitSha $commit -ExpectedEntryCount 2 -ExpectedMessage 'MANIFEST_DUPLICATE_PATH'; $assertions++

        $original = [System.IO.File]::ReadAllBytes((Join-Path $tempRoot 'alpha.txt'))
        [System.IO.File]::WriteAllText((Join-Path $tempRoot 'alpha.txt'), 'tampered', (New-Object System.Text.UTF8Encoding($false)))
        Invoke-ExpectedManifestFailure -RepositoryRoot $tempRoot -ManifestText $valid -ExpectedCommitSha $commit -ExpectedEntryCount 2 -ExpectedMessage 'MANIFEST_PHYSICAL_CHECKOUT_MISMATCH'; $assertions++
        [System.IO.File]::WriteAllBytes((Join-Path $tempRoot 'alpha.txt'), $original)

        return $assertions
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}

try {
    if ($SelfTest) {
        $count = Invoke-SelfTest
        Write-Output ('SelfTestAssertions=' + $count + ';Failures=0')
        exit 0
    }

    $repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
    $manifestPath = Join-Path $PSScriptRoot 'FILE_SHA256_MANIFEST.txt'
    $actualRoot = Invoke-GitUtf8 -RepositoryRoot $repositoryRoot -Arguments @('rev-parse', '--show-toplevel')
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($actualRoot), $repositoryRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'MANIFEST_REPOSITORY_ROOT_MISMATCH' }
    $origin = Invoke-GitUtf8 -RepositoryRoot $repositoryRoot -Arguments @('remote', 'get-url', 'origin')
    if ($origin -ne 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git') { throw 'MANIFEST_ORIGIN_MISMATCH' }
    $head = Invoke-GitUtf8 -RepositoryRoot $repositoryRoot -Arguments @('rev-parse', '--verify', 'HEAD')
    $isAncestor = & (Get-Command git.exe -ErrorAction Stop).Source -C $repositoryRoot merge-base --is-ancestor $script:ExpectedInventoryCommit $head
    if ($LASTEXITCODE -ne 0) { throw 'MANIFEST_INVENTORY_NOT_ANCESTOR' }
    $status = Invoke-GitUtf8 -RepositoryRoot $repositoryRoot -Arguments @('status', '--porcelain', '--untracked-files=all')
    if (-not [string]::IsNullOrEmpty($status)) { throw 'MANIFEST_WORKTREE_NOT_CLEAN' }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'MANIFEST_FILE_MISSING' }
    $manifestItem = Get-Item -LiteralPath $manifestPath -Force
    if (($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'MANIFEST_FILE_REPARSE' }
    $manifestText = [System.IO.File]::ReadAllText($manifestPath, (New-Object System.Text.UTF8Encoding($false, $true)))
    $count = Test-ManifestContent -RepositoryRoot $repositoryRoot -ManifestText $manifestText -ExpectedCommitSha $script:ExpectedInventoryCommit -ExpectedEntryCount 29
    Write-Output ('ManifestEntries=' + $count + ';GitBlobAndWindowsCheckoutRepresentations=PASS;Failures=0')
    exit 0
}
catch {
    Write-Error ('EvidenceManifestVerification=FAIL;Code=' + $_.Exception.Message)
    exit 1
}

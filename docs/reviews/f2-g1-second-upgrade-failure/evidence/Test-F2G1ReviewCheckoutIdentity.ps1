[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedOrigin = 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
$checkouts = @(
    [pscustomobject]@{ Name='ProductionSource'; Root='C:\Dev\f2-g1-protected-updater-source'; Commit='03882eedf3104fc33aa0cf503ddef9c9a6bec702' },
    [pscustomobject]@{ Name='PR62Candidate'; Root='C:\Dev\f2-g1-protected-updater'; Commit='923c7d39d7fbfe106dea404c386efd4b5844654e' },
    [pscustomobject]@{ Name='PR63ExecutionReview'; Root='C:\Dev\f2-g1-final-execution-preflight-review'; Commit='3dc05f98831924160474bfb5b554b2963d9a137b' }
)

foreach ($checkout in $checkouts) {
    $item = Get-Item -LiteralPath $checkout.Root -Force -ErrorAction Stop
    if (-not $item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw ($checkout.Name + '_ROOT_TYPE_OR_REPARSE_INVALID')
    }
    $git = Get-Command git.exe -ErrorAction Stop
    $head = (& $git.Source -C $checkout.Root rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $head -cne $checkout.Commit) { throw ($checkout.Name + '_HEAD_MISMATCH') }
    $origin = (& $git.Source -C $checkout.Root remote get-url origin 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $origin -cne $expectedOrigin) { throw ($checkout.Name + '_ORIGIN_MISMATCH') }
    $status = @(& $git.Source -C $checkout.Root status --porcelain --untracked-files=all 2>$null)
    if ($LASTEXITCODE -ne 0 -or $status.Count -ne 0) { throw ($checkout.Name + '_WORKTREE_NOT_CLEAN') }
    [Console]::Out.WriteLine(('PASS:{0};HEAD={1};ORIGIN=EXPECTED;WORKTREE=CLEAN' -f $checkout.Name,$head))
}

[Console]::Out.WriteLine('Result=REVIEW_CHECKOUT_IDENTITIES_VALID')

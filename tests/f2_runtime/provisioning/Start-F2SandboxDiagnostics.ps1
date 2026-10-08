[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$diagnosticPath = 'C:\F2Input\Get-F2SandboxReadiness.ps1'
$powershellPath = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$runId = [guid]::NewGuid().ToString('N')
$stdoutPath = Join-Path $env:TEMP ("F2-readiness-$runId.stdout.json")
$stderrPath = Join-Path $env:TEMP ("F2-readiness-$runId.stderr.txt")
$username = $null
$securePassword = $null
$passwordChars = $null
$randomBytes = $null
$credential = $null
$summary = $null
$finalStatus = 'BLOCKED_ENVIRONMENT'

function Write-Report {
    param([string] $Status, [string] $Message)
    Write-Output ''
    Write-Output 'F2 WINDOWS SANDBOX — DIAGNOSTIC ONLY'
    Write-Output ('Standard-user setup: {0}' -f $Status)
    if ($Message) { Write-Output $Message }
    if ($summary) {
        foreach ($line in $summary.summary) { Write-Output $line }
        Write-Output ('Diagnostic overall: {0}' -f $summary.overall)
    } else {
        Write-Output 'Network, mapping, graphics, limits, and evidence: UNKNOWN (diagnostic did not complete)'
    }
    Write-Output 'F2 native runtime: NOT RUN'
    Write-Output 'This report remains visible for 180 seconds; close the Sandbox at any time to discard guest-local state.'
}

function Assert-GuestDiagnosticUsername {
    param([Parameter(Mandatory)] [string] $Name)
    if ($Name.Length -gt 20) { throw 'The guest diagnostic username exceeds New-LocalUser -Name maximum length 20.' }
    if ($Name -notmatch '^F2Diag_[0-9A-F]{12}$') { throw 'The guest diagnostic username does not match the bounded F2Diag_ plus 12 hexadecimal characters format.' }
}

try {
    if (-not (Test-Path -LiteralPath $diagnosticPath -PathType Leaf)) { throw 'Pinned guest diagnostic is missing from C:\F2Input.' }
    if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)) { throw 'Windows PowerShell executable is unavailable in the guest.' }
    foreach ($commandName in @('Get-LocalUser', 'New-LocalUser', 'Get-LocalGroup', 'Get-LocalGroupMember', 'Add-LocalGroupMember', 'Remove-LocalUser')) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) { throw "Required local-account command is unavailable: $commandName" }
    }

    $finalStatus = 'BLOCKED_STANDARD_USER'
    $randomBytes = New-Object byte[] 6
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($randomBytes) } finally { $rng.Dispose() }
    $suffix = [BitConverter]::ToString($randomBytes).Replace('-', '')
    $username = "F2Diag_$suffix"
    Assert-GuestDiagnosticUsername -Name $username

    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#$%+-_'
    $passwordChars = New-Object char[] 32
    $securePassword = New-Object System.Security.SecureString
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $index = 0
        while ($index -lt $passwordChars.Length) {
            $oneByte = New-Object byte[] 1
            $rng.GetBytes($oneByte)
            $limit = 256 - (256 % $alphabet.Length)
            if ($oneByte[0] -lt $limit) {
                $char = $alphabet[[int]($oneByte[0] % $alphabet.Length)]
                $passwordChars[$index] = $char
                $securePassword.AppendChar($char)
                $index++
            }
            [Array]::Clear($oneByte, 0, $oneByte.Length)
        }
    } finally { $rng.Dispose() }
    $securePassword.MakeReadOnly()

    $newUser = New-LocalUser -Name $username -Password $securePassword -Description 'Disposable F2 readiness diagnostic account' -AccountNeverExpires -PasswordNeverExpires -ErrorAction Stop
    $usersGroup = Get-LocalGroup -SID ([Security.Principal.SecurityIdentifier]'S-1-5-32-545') -ErrorAction Stop
    $adminsGroup = Get-LocalGroup -SID ([Security.Principal.SecurityIdentifier]'S-1-5-32-544') -ErrorAction Stop
    $userSid = $newUser.SID.Value
    $usersMembers = @(Get-LocalGroupMember -Group $usersGroup.Name -ErrorAction Stop)
    if (@($usersMembers | Where-Object { $_.SID.Value -eq $userSid }).Count -eq 0) {
        Add-LocalGroupMember -Group $usersGroup.Name -Member $newUser -ErrorAction Stop
    }
    $adminMembers = @(Get-LocalGroupMember -Group $adminsGroup.Name -ErrorAction Stop)
    if (@($adminMembers | Where-Object { $_.SID.Value -eq $userSid }).Count -gt 0) {
        throw 'The new diagnostic identity unexpectedly belongs to Administrators.'
    }

    $credential = [pscredential]::new(("{0}\{1}" -f $env:COMPUTERNAME, $username), $securePassword)
    $argumentLine = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\F2Input\Get-F2SandboxReadiness.ps1 -Summary'
    $process = Start-Process -FilePath $powershellPath -Credential $credential -LoadUserProfile -ArgumentList $argumentLine -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ErrorAction Stop
    if (-not $process.WaitForExit(60000)) {
        $process.Kill()
        $process.WaitForExit()
        throw 'Standard-user diagnostic exceeded its 60-second limit and was terminated.'
    }

    $json = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction Stop
    $summary = $json | ConvertFrom-Json -ErrorAction Stop
    $expectedIdentity = "{0}\{1}" -f $env:COMPUTERNAME, $username
    if ($summary.identity -ne $expectedIdentity -or $summary.is_administrator -ne $false -or $summary.token_status -ne 'PASS') {
        $finalStatus = 'BLOCKED_STANDARD_USER'
        Write-Report -Status $finalStatus -Message 'The child process did not prove the expected nonadministrator token; no fallback diagnostic ran as WDAGUtilityAccount.'
    } elseif ($process.ExitCode -ne 0 -or $summary.overall -eq 'FAIL' -or $summary.network_status -eq 'FAIL' -or $summary.mapping_status -eq 'FAIL') {
        $finalStatus = 'BLOCKED_ENVIRONMENT'
        Write-Report -Status $finalStatus -Message 'A network or read-only mapping gate failed. Stop; do not stage or run native code.'
    } else {
        $finalStatus = 'INCOMPLETE'
        Write-Report -Status $finalStatus -Message 'Standard-user diagnostic ran. Unknown renderer, resource-supervision, and evidence gates remain open.'
    }
} catch {
    $safeMessage = $_.Exception.Message
    Write-Report -Status $finalStatus -Message ("{0}: {1}" -f $finalStatus, $safeMessage)
} finally {
    if ($stdoutPath -and (Test-Path -LiteralPath $stdoutPath -PathType Leaf)) { Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue }
    if ($stderrPath -and (Test-Path -LiteralPath $stderrPath -PathType Leaf)) { Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue }
    if ($username -and (Get-Command Remove-LocalUser -ErrorAction SilentlyContinue)) {
        Remove-LocalUser -Name $username -ErrorAction SilentlyContinue
    }
    if ($credential) { $credential = $null }
    if ($securePassword) { $securePassword.Dispose() }
    if ($passwordChars) { [Array]::Clear($passwordChars, 0, $passwordChars.Length) }
    if ($randomBytes) { [Array]::Clear($randomBytes, 0, $randomBytes.Length) }
}

Start-Sleep -Seconds 180

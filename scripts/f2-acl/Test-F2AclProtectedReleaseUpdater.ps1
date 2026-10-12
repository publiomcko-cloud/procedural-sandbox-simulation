[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:assertions=0;$script:failures=New-Object 'System.Collections.Generic.List[string]'
function Assert-Update([bool]$Condition,[string]$Message){$script:assertions++;if(-not $Condition){$script:failures.Add($Message);Write-Host ('FAIL: '+$Message)}else{Write-Host ('PASS: '+$Message)}}

$sourceScript=Join-Path $PSScriptRoot 'Invoke-F2ProtectedReleaseUpdate.ps1'
$startScript=Join-Path $PSScriptRoot 'Start-F2ProtectedReleaseUpdate.ps1'
$tokens=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($sourceScript,[ref]$tokens,[ref]$parseErrors)
Assert-Update ($parseErrors.Count -eq 0) 'updater parses in Windows PowerShell 5.1'
$startTokens=$null;$startErrors=$null
[void][Management.Automation.Language.Parser]::ParseFile($startScript,[ref]$startTokens,[ref]$startErrors)
Assert-Update ($startErrors.Count -eq 0) 'single-UAC launcher parses in Windows PowerShell 5.1'
. $sourceScript
. $startScript
$approvedUpdaterBytes=[IO.File]::ReadAllBytes($sourceScript)
$approvedUpdaterHash=Get-F2UpdateLauncherSha256 -Bytes $approvedUpdaterBytes
$modifiedUpdaterBytes=[byte[]]$approvedUpdaterBytes.Clone();$modifiedUpdaterBytes[0]=($modifiedUpdaterBytes[0] -bxor 1)
Assert-Update ((Get-F2UpdateLauncherSha256 -Bytes $approvedUpdaterBytes) -ceq $approvedUpdaterHash -and (Get-F2UpdateLauncherSha256 -Bytes $modifiedUpdaterBytes) -cne $approvedUpdaterHash) 'exact approved updater bytes pass the SHA-256 pin while modified bytes fail the same pin'

$script:root=Join-Path $env:TEMP ('F2 Protected Updater Tests '+[guid]::NewGuid().ToString('N'))
$script:oldSource=Join-Path $script:root 'old-source\scripts\f2-acl'
$script:newSource=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:names=@($script:F2UpdateOldPins.Keys)
$script:allPins=@{}
$script:sourceRoot=Join-Path $script:root 'clean-source'
$script:sourceAcl=Join-Path $script:sourceRoot 'scripts\f2-acl'
[void][IO.Directory]::CreateDirectory($script:sourceAcl)
foreach($name in $script:names){Copy-Item -LiteralPath (Join-Path $script:newSource ('scripts\f2-acl\'+$name)) -Destination (Join-Path $script:sourceAcl $name)}
$script:pinObj=[ordered]@{
    Schema='f2-icacls-corroboration-pins-v1'
    ReviewedCollectorBaseSha='a62773f0553dff4a05055b18fa10834f7488ae55'
    CorroborationModuleSha256=(Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $script:sourceAcl 'F2AclIcacls.Corroboration.psm1'))))
    CollectorScriptSha256=(Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $script:sourceAcl 'Invoke-F2AclReadOnlyCapture.ps1'))))
    ProtocolModuleSha256=(Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $script:sourceAcl 'F2AclCapture.Protocol.psm1'))))
    RuntimeModuleSha256=(Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $script:sourceAcl 'F2AclIcacls.Runtime.psm1'))))
    LauncherScriptSha256=(Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $script:sourceAcl 'Invoke-F2IcaclsCapture.ps1'))))
    CoordinatorScriptSha256=(Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $script:sourceAcl 'Invoke-F2IcaclsProtectedCoordinator.ps1'))))
}
$script:pinPath=Join-Path $script:sourceAcl 'F2_ICACLS_SOURCE_PINS.json'
[IO.File]::WriteAllText($script:pinPath,($script:pinObj|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
foreach($name in $script:names){$script:allPins[$name]=Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $script:sourceAcl $name)))}

$git=Get-Command git.exe -ErrorAction Stop
& $git.Source -C $script:sourceRoot init --quiet
& $git.Source -C $script:sourceRoot config core.autocrlf false
& $git.Source -C $script:sourceRoot config user.name 'F2 Synthetic Test'
& $git.Source -C $script:sourceRoot config user.email 'f2-synthetic@example.invalid'
& $git.Source -C $script:sourceRoot remote add origin 'https://github.com/publiomcko-cloud/procedural-sandbox-simulation.git'
& $git.Source -C $script:sourceRoot add -- scripts/f2-acl
if($LASTEXITCODE -ne 0){throw 'Synthetic Git stage failed.'}
& $git.Source -C $script:sourceRoot commit --quiet -m 'synthetic updater source fixture'
if($LASTEXITCODE -ne 0){throw 'Synthetic Git commit failed.'}
$script:fixtureCommit=(& $git.Source -C $script:sourceRoot rev-parse HEAD | Out-String).Trim()
if($LASTEXITCODE -ne 0 -or $script:fixtureCommit -notmatch '^[0-9a-f]{40}$'){throw 'Synthetic Git commit identity failed.'}

$oldManifest=[ordered]@{
    Schema='f2-icacls-runtime-release-v2'
    ReviewedCommitSha=$script:F2UpdateOldCommit
    BaselineMailboxId=$script:F2UpdateBaselineMailboxId
    BaselinePayloadCaptureId=$script:F2UpdateBaselineCaptureId
    BaselinePayloadSha256=$script:F2UpdateBaselinePayloadSha256
    BaselineIntegritySha256=$script:F2UpdateBaselineIntegritySha256
    SourcePinsManifestSha256=$script:F2UpdateOldPins['F2_ICACLS_SOURCE_PINS.json']
    Files=@(foreach($name in $script:names){[pscustomobject]@{Name=$name;Sha256=$script:F2UpdateOldPins[$name]}})
}
$script:oldManifestBytes=[Text.UTF8Encoding]::new($false).GetBytes(($oldManifest|ConvertTo-Json -Compress -Depth 6))
Assert-Update ((Get-F2UpdateSha256 -Bytes $script:oldManifestBytes) -ceq $script:F2UpdateOldManifestSha256) 'synthetic old v2 manifest exactly reproduces the approved retained old-manifest SHA-256'

function New-UpdateFixture {
    param([string]$FaultAt,[bool]$ProcessActive=$false,[string]$AclRejectPath,[switch]$CorruptOldFile,[switch]$CandidateHashMismatch)
    $caseRoot=Join-Path $script:root ('case-'+[guid]::NewGuid().ToString('N'))
    $fakeC=Join-Path $caseRoot 'C'
    $programFiles=Join-Path $fakeC 'Program Files'
    $programData=Join-Path $fakeC 'ProgramData'
    $packageHome=Join-Path $programFiles 'F2-G1-Icacls'
    $programDataRoot=Join-Path $programData 'F2-G1-Icacls'
    $oldAcl=Join-Path $packageHome 'scripts\f2-acl'
    [void][IO.Directory]::CreateDirectory((Join-Path $oldAcl '..'))
    [void][IO.Directory]::CreateDirectory($oldAcl)
    [void][IO.Directory]::CreateDirectory($programDataRoot)
    foreach($name in $script:names){Copy-Item -LiteralPath (Join-Path $script:oldSource $name) -Destination (Join-Path $oldAcl $name)}
    if($CorruptOldFile){[IO.File]::WriteAllText((Join-Path $oldAcl $script:names[0]),'synthetic corruption')}
    $active=Join-Path $programDataRoot 'approved-release.json'
    [IO.File]::WriteAllBytes($active,$script:oldManifestBytes)
    $candidate=[ordered]@{
        Schema='f2-icacls-runtime-release-v3'
        ReviewedCommitSha=$script:fixtureCommit
        PackageRoot=(Join-Path (Join-Path $packageHome 'releases') $script:fixtureCommit)
        BaselineMailboxId=$script:F2UpdateBaselineMailboxId
        BaselinePayloadCaptureId=$script:F2UpdateBaselineCaptureId
        BaselinePayloadSha256=$script:F2UpdateBaselinePayloadSha256
        BaselineIntegritySha256=$script:F2UpdateBaselineIntegritySha256
        SourcePinsManifestSha256=$script:allPins['F2_ICACLS_SOURCE_PINS.json']
        Files=@(foreach($name in $script:names){[pscustomobject]@{Name=$name;Sha256=$script:allPins[$name]}})
    }
    $candidateBytes=[Text.UTF8Encoding]::new($false).GetBytes(($candidate|ConvertTo-Json -Compress -Depth 6))
    $candidateSha=Get-F2UpdateSha256 -Bytes $candidateBytes
    if($CandidateHashMismatch){$candidateSha=('0'*64)}
    $state=[pscustomobject]@{Handles=(New-Object 'System.Collections.Generic.List[System.IDisposable]');Operations=(New-Object 'System.Collections.Generic.List[string]');Events=(New-Object 'System.Collections.Generic.List[string]');ProcessActive=$ProcessActive;LateProcess=$false;LateReaderBlocked=$false;InventoryCalls=0;InventoryFailureCall=0;AclRejectPath=$AclRejectPath;FaultAt=$FaultAt;Context=$null}
    $hooks=[pscustomobject]@{
        AclCheck={param($path,$kind) if($state.AclRejectPath -and [string]::Equals($path,$state.AclRejectPath,[StringComparison]::OrdinalIgnoreCase)){return $false};return $true}.GetNewClosure()
        ParentChainCheck={param($ctx)return $true}.GetNewClosure()
        ProcessInventory={param($ctx)
            $state.InventoryCalls++;$state.Events.Add(('Inventory'+$state.InventoryCalls))
            if($state.InventoryFailureCall -eq $state.InventoryCalls){throw 'SYNTHETIC_PROCESS_INVENTORY_FAILURE'}
            $requesterPath=Join-Path $ctx.SourceRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'
            $requesterLine='powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& { $path="__PATH__"; $expected="__LAUNCHER_SHA__"; . ([scriptblock]::Create($text)); Invoke-F2ProtectedReleaseUpdateLauncher -ExpectedSourceCommit "__SOURCE_SHA__" -ExpectedUpdaterSha256 "__UPDATER_SHA__" -ExpectedLauncherSha256 "__LAUNCHER_SHA__" -ExpectedCandidateManifestSha256 "__CANDIDATE_SHA__" }"'
            $requesterLine=$requesterLine.Replace('__PATH__',$requesterPath).Replace('__LAUNCHER_SHA__',$ctx.ExpectedLauncherSha256).Replace('__SOURCE_SHA__',$ctx.ExpectedSourceCommit).Replace('__UPDATER_SHA__',$ctx.UpdaterSha256).Replace('__CANDIDATE_SHA__',$ctx.CandidateManifestSha256)
            $rows=New-Object 'System.Collections.Generic.List[object]'
            $rows.Add([pscustomobject]@{ProcessId=$ctx.CurrentProcessId;Name='powershell.exe';CommandLine='powershell.exe -NoProfile -EncodedCommand synthetic-current';CreationUtcTicks=0L;OwnerSid=''})
            $rows.Add([pscustomobject]@{ProcessId=$ctx.RequesterLauncherProcessId;Name='powershell.exe';CommandLine=$requesterLine;CreationUtcTicks=$ctx.RequesterLauncherCreationUtcTicks;OwnerSid=$ctx.ExpectedRequesterSid})
            if($state.ProcessActive -or ($state.LateProcess -and $state.InventoryCalls -ge 2)){
                $rows.Add([pscustomobject]@{ProcessId=3000+$state.InventoryCalls;Name='powershell.exe';CommandLine=('powershell.exe -File "'+(Join-Path $ctx.OldRuntimeSourceRoot 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1')+'"');CreationUtcTicks=638000000000000000L;OwnerSid='S-1-5-21-100'})
            }
            return $rows.ToArray()
        }.GetNewClosure()
        Identity={return [pscustomobject]@{UserSid='S-1-5-21-100';IsAdministrator=$true}}.GetNewClosure()
        CreateDirectory={param($path)if([IO.File]::Exists($path)-or[IO.Directory]::Exists($path)){throw 'CREATE_NEW_COLLISION'};[void][IO.Directory]::CreateDirectory($path)}.GetNewClosure()
        WriteFile={param($path,$bytes,$kind)$stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}}.GetNewClosure()
        AcquireLocks={param($lockPath,$manifestPath)
            if(-not [IO.File]::Exists($lockPath)){[IO.File]::WriteAllBytes($lockPath,[byte[]]@())}
            $lock=[IO.File]::Open($lockPath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
            $barrier=[IO.File]::Open($manifestPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Delete)
            $state.Events.Add('ManifestBarrierAcquired')
            $state.Handles.Add($lock);$state.Handles.Add($barrier);return [pscustomobject]@{Lease=$lock;ManifestBarrier=$barrier}
        }.GetNewClosure()
        ReplaceManifest={param($candidatePath,$activePath,$backupPath)
            $state.Events.Add('ManifestActivation')
            $state.LateReaderBlocked=$false;$lateReader=$null
            try{$lateReader=[IO.File]::Open($activePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)}catch{$state.LateReaderBlocked=$true}finally{if($null -ne $lateReader){$lateReader.Dispose()}}
            [IO.File]::Replace($candidatePath,$activePath,$backupPath,$false)
        }.GetNewClosure()
        AfterOperation={param($name)$state.Operations.Add($name);if($state.FaultAt -ceq $name){throw 'INJECTED_FAULT'}}.GetNewClosure()
    }
    $context=[pscustomobject]@{
        SourceRoot=$script:sourceRoot;ExpectedSourceCommit=$script:fixtureCommit;CandidateManifestBytes=$candidateBytes;CandidateManifestSha256=$candidateSha
        PackageHome=$packageHome;ProgramDataRoot=$programDataRoot;ActiveManifestPath=$active;Hooks=$hooks;Manifest=$null;TransactionState=$null
        OldRuntimeSourceRoot=(Split-Path (Split-Path $script:oldSource -Parent) -Parent)
        UpdaterSha256=('9'*64);ExpectedLauncherSha256=('8'*64);ExpectedRequesterSid='S-1-5-21-100'
        CurrentProcessId=1000;RequesterLauncherProcessId=1001;RequesterLauncherCreationUtcTicks=638000000000000000L
    }
    $state.Context=$context
    return $state
}

function Close-UpdateFixture($State){foreach($handle in @($State.Handles)){try{$handle.Dispose()}catch{}}}
function Get-UpdateActiveSha($State){return Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes($State.Context.ActiveManifestPath))}
function Get-ProcessInventoryError($Context,[object[]]$Processes){try{[void](Test-F2UpdateProcessInventory -Processes $Processes -CurrentProcessId $Context.CurrentProcessId -Context $Context);return ''}catch{return $_.Exception.Message}}
function Get-QuiescenceError($Context){try{[void](Assert-F2UpdateProcessQuiescence -Context $Context);return ''}catch{return $_.Exception.Message}}

try {

    # Build the previous-release fixture from the immutable old source commit
    # in this repository. Never depend on another developer's C:\Dev checkout.
    $oldArchive=Join-Path $script:root 'old-source.zip'
    & $git.Source -C $script:newSource archive --format=zip "--output=$oldArchive" $script:F2UpdateOldCommit 'scripts/f2-acl'
    if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($oldArchive)){throw 'UPDATE_TEST_OLD_SOURCE_ARCHIVE_FAILED'}
    if((Get-Item -LiteralPath $oldArchive).Length -gt 33554432){throw 'UPDATE_TEST_OLD_SOURCE_ARCHIVE_OVERSIZED'}
    [void][IO.Directory]::CreateDirectory($script:oldSource)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $oldZip=[IO.Compression.ZipFile]::OpenRead($oldArchive)
    try {
        $oldFixturesMatch=$true
        foreach($name in $script:names){
            $entry=$oldZip.GetEntry(('scripts/f2-acl/'+$name))
            if($null -eq $entry -or $entry.Length -gt 4194304){throw 'UPDATE_TEST_OLD_SOURCE_ENTRY_INVALID'}
            $entryStream=$entry.Open();$memory=New-Object IO.MemoryStream
            try {
                $buffer=New-Object byte[] 8192;$total=0
                while(($read=$entryStream.Read($buffer,0,$buffer.Length)) -gt 0){
                    $total+=$read
                    if($total -gt 4194304){throw 'UPDATE_TEST_OLD_SOURCE_ENTRY_OVERSIZED'}
                    $memory.Write($buffer,0,$read)
                }
                $oldBytes=$memory.ToArray()
            } finally {$entryStream.Dispose();$memory.Dispose()}
            $oldHash=Get-F2UpdateSha256 -Bytes $oldBytes
            if($oldHash -cne $script:F2UpdateOldPins[$name] -and $name -ceq 'F2AclCapture.Protocol.psm1'){
                # That one source path is explicitly CRLF in the old commit's
                # .gitattributes; git archive contains normalized LF blob bytes.
                $oldText=[Text.UTF8Encoding]::new($false,$true).GetString($oldBytes)
                $oldBytes=[Text.UTF8Encoding]::new($false).GetBytes(($oldText -replace "`r?`n","`r`n"))
                $oldHash=Get-F2UpdateSha256 -Bytes $oldBytes
            }
            if($oldHash -cne $script:F2UpdateOldPins[$name]){$oldFixturesMatch=$false;throw ('UPDATE_TEST_OLD_SOURCE_PIN_MISMATCH:'+ $name)}
            [IO.File]::WriteAllBytes((Join-Path $script:oldSource $name),$oldBytes)
        }
    } finally {$oldZip.Dispose()}
    Assert-Update $oldFixturesMatch 'old-release fixtures are extracted from the pinned Git commit and match all seven installed-byte hashes'

    # The approved v2/v3 runtime surfaces include fixed installed paths and
    # both immutable source checkouts. Tests use temporary roots so no real
    # host process or filesystem inventory is queried.
    $pathFixture=New-UpdateFixture
    $runtimePathInventory=@(Get-F2UpdateRuntimePathInventory -Context $pathFixture.Context)
    $expectedRuntimePaths=@(
        (Join-Path $pathFixture.Context.PackageHome 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1'),
        (Join-Path $pathFixture.Context.PackageHome 'scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1'),
        (Join-Path $pathFixture.Context.PackageHome 'scripts\f2-acl\F2AclIcacls.Runtime.psm1'),
        (Join-Path $pathFixture.Context.OldRuntimeSourceRoot 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1'),
        (Join-Path $pathFixture.Context.OldRuntimeSourceRoot 'scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1'),
        (Join-Path $pathFixture.Context.OldRuntimeSourceRoot 'scripts\f2-acl\F2AclIcacls.Runtime.psm1'),
        (Join-Path $pathFixture.Context.SourceRoot 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1'),
        (Join-Path $pathFixture.Context.SourceRoot 'scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1'),
        (Join-Path $pathFixture.Context.SourceRoot 'scripts\f2-acl\F2AclIcacls.Runtime.psm1'),
        (Join-Path (Join-Path (Join-Path $pathFixture.Context.PackageHome 'releases') $pathFixture.Context.ExpectedSourceCommit) 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1'),
        (Join-Path (Join-Path (Join-Path $pathFixture.Context.PackageHome 'releases') $pathFixture.Context.ExpectedSourceCommit) 'scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1'),
        (Join-Path (Join-Path (Join-Path $pathFixture.Context.PackageHome 'releases') $pathFixture.Context.ExpectedSourceCommit) 'scripts\f2-acl\F2AclIcacls.Runtime.psm1')
    )
    $runtimePathsCovered=$true
    $canonicalExpectedRuntimePaths=@($expectedRuntimePaths | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
    $canonicalRuntimePathInventory=@($runtimePathInventory | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\') })
    foreach($path in $canonicalExpectedRuntimePaths){if($path -notin $canonicalRuntimePathInventory){$runtimePathsCovered=$false}}
    $missingRuntimePaths=@($canonicalExpectedRuntimePaths | Where-Object { $_ -notin $canonicalRuntimePathInventory })
    Assert-Update ($runtimePathsCovered -and $runtimePathInventory.Count -eq 12) ('runtime inventory includes old/new source checkout and fixed/versioned installed launchers, coordinators and direct runtime modules; actualCount='+$runtimePathInventory.Count+'; missing='+($missingRuntimePaths -join '|'))
    $baseInventory=@(& $pathFixture.Context.Hooks.ProcessInventory $pathFixture.Context)
    $baseInventoryError=Get-ProcessInventoryError $pathFixture.Context $baseInventory
    $requesterRecord=$baseInventory | Where-Object { $_.ProcessId -eq $pathFixture.Context.RequesterLauncherProcessId } | Select-Object -First 1
    $expectedRequesterPath=[IO.Path]::GetFullPath((Join-Path $pathFixture.Context.SourceRoot 'scripts\f2-acl\Start-F2ProtectedReleaseUpdate.ps1'))
    $requesterDiagnostics=[ordered]@{
        CommandPresent=([string]$requesterRecord.CommandLine -match '(?i)(?:^|\s)-(?:command|c)(?:\s|:|$)')
        EncodedAbsent=([string]$requesterRecord.CommandLine -notmatch '(?i)(?:^|\s)-(?:encodedcommand|enc)(?:\s|:|$)')
        SourceLauncherPath=([string]$requesterRecord.CommandLine).IndexOf($expectedRequesterPath,[StringComparison]::OrdinalIgnoreCase) -ge 0
        DotSourceBootstrap=([string]$requesterRecord.CommandLine).IndexOf('. ([scriptblock]::Create($text))',[StringComparison]::OrdinalIgnoreCase) -ge 0
        LauncherFunction=([string]$requesterRecord.CommandLine).IndexOf('Invoke-F2ProtectedReleaseUpdateLauncher',[StringComparison]::OrdinalIgnoreCase) -ge 0
        CommitPin=([string]$requesterRecord.CommandLine).IndexOf([string]$pathFixture.Context.ExpectedSourceCommit,[StringComparison]::OrdinalIgnoreCase) -ge 0
        UpdaterPin=([string]$requesterRecord.CommandLine).IndexOf([string]$pathFixture.Context.UpdaterSha256,[StringComparison]::OrdinalIgnoreCase) -ge 0
        LauncherPin=([string]$requesterRecord.CommandLine).IndexOf([string]$pathFixture.Context.ExpectedLauncherSha256,[StringComparison]::OrdinalIgnoreCase) -ge 0
        CandidatePin=([string]$requesterRecord.CommandLine).IndexOf([string]$pathFixture.Context.CandidateManifestSha256,[StringComparison]::OrdinalIgnoreCase) -ge 0
        ProcessIdentity=([long]$requesterRecord.CreationUtcTicks -eq [long]$pathFixture.Context.RequesterLauncherCreationUtcTicks -and [string]$requesterRecord.OwnerSid -ceq [string]$pathFixture.Context.ExpectedRequesterSid)
    }
    $requesterDiagnosticText=($requesterDiagnostics.GetEnumerator() | ForEach-Object { '{0}:{1}' -f $_.Key,$_.Value }) -join ','
    Assert-Update ($baseInventoryError -ceq '') ('only the current updater and exact PID/creation-time/pin-bound requester launcher are allowed; actualError='+$baseInventoryError+'; requesterChecks='+$requesterDiagnosticText)
    $foreignCases=@(
        [pscustomobject]@{Label='active old source-checkout launcher';CommandLine=('powershell.exe -File "'+(Join-Path $pathFixture.Context.OldRuntimeSourceRoot 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1')+'"')},
        [pscustomobject]@{Label='active new source-checkout launcher';CommandLine=('powershell.exe -File "'+(Join-Path $pathFixture.Context.SourceRoot 'scripts\f2-acl\Invoke-F2IcaclsCapture.ps1')+'"')},
        [pscustomobject]@{Label='active installed coordinator';CommandLine=('powershell.exe -File "'+(Join-Path $pathFixture.Context.PackageHome 'scripts\f2-acl\Invoke-F2IcaclsProtectedCoordinator.ps1')+'" -CaptureId '+('a'*32))},
        [pscustomobject]@{Label='direct runtime-module invocation';CommandLine=('powershell.exe -NoProfile -Command "Import-Module '+(Join-Path $pathFixture.Context.OldRuntimeSourceRoot 'scripts\f2-acl\F2AclIcacls.Runtime.psm1')+'; Invoke-F2IcaclsCaptureLauncher"')},
        [pscustomobject]@{Label='encoded PowerShell invocation';CommandLine='powershell.exe -NoProfile -EncodedCommand SQBFAFgA'},
        [pscustomobject]@{Label='legacy process with cached v2 manifest';CommandLine=('powershell.exe -NoProfile -Command "$cachedManifestSha256='''+$script:F2UpdateOldManifestSha256+'''"');CachedManifestSha256=$script:F2UpdateOldManifestSha256},
        [pscustomobject]@{Label='active PowerShell ISE process';Name='powershell_ise.exe';CommandLine='powershell_ise.exe -NoProfile'}
    )
    $caseIndex=0
    foreach($case in $foreignCases){
        $caseIndex++
        $processName=if($case.PSObject.Properties['Name']){[string]$case.Name}else{'powershell.exe'}
        $rows=@($baseInventory)+@([pscustomobject]@{ProcessId=2000+$caseIndex;Name=$processName;CommandLine=$case.CommandLine;CreationUtcTicks=638000000000000000L;OwnerSid='S-1-5-21-200'})
        $caseInventoryError=Get-ProcessInventoryError $pathFixture.Context $rows
        Assert-Update ($caseInventoryError -ceq 'UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN') ($case.Label+' blocks independent of path-only matching; actualError='+$caseInventoryError)
    }
    $missingLine=@($baseInventory)+@([pscustomobject]@{ProcessId=2010;Name='powershell.exe';CommandLine=$null;CreationUtcTicks=638000000000000000L;OwnerSid='S-1-5-21-200'})
    Assert-Update ((Get-ProcessInventoryError $pathFixture.Context $missingLine) -ceq 'UPDATE_PROCESS_COMMAND_LINE_UNKNOWN') 'missing or inaccessible foreign PowerShell command line fails closed'
    $badRequester=@($baseInventory | Where-Object { $_.ProcessId -ne $pathFixture.Context.RequesterLauncherProcessId })+@([pscustomobject]@{ProcessId=$pathFixture.Context.RequesterLauncherProcessId;Name='powershell.exe';CommandLine=$baseInventory[1].CommandLine;CreationUtcTicks=1L;OwnerSid=$pathFixture.Context.ExpectedRequesterSid})
    Assert-Update ((Get-ProcessInventoryError $pathFixture.Context $badRequester) -ceq 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN') 'requester PID reuse or unexpected process creation time is rejected'
    $badPinRequester=@($baseInventory | Where-Object { $_.ProcessId -ne $pathFixture.Context.RequesterLauncherProcessId })+@([pscustomobject]@{ProcessId=$pathFixture.Context.RequesterLauncherProcessId;Name='powershell.exe';CommandLine=$baseInventory[1].CommandLine.Replace($pathFixture.Context.CandidateManifestSha256,('0'*64));CreationUtcTicks=$pathFixture.Context.RequesterLauncherCreationUtcTicks;OwnerSid=$pathFixture.Context.ExpectedRequesterSid})
    Assert-Update ((Get-ProcessInventoryError $pathFixture.Context $badPinRequester) -ceq 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN') 'requester launch command with a changed source pin is rejected'
    $encodedRequester=@($baseInventory | Where-Object { $_.ProcessId -ne $pathFixture.Context.RequesterLauncherProcessId })+@([pscustomobject]@{ProcessId=$pathFixture.Context.RequesterLauncherProcessId;Name='powershell.exe';CommandLine=$baseInventory[1].CommandLine.Replace('-Command','-EncodedCommand');CreationUtcTicks=$pathFixture.Context.RequesterLauncherCreationUtcTicks;OwnerSid=$pathFixture.Context.ExpectedRequesterSid})
    Assert-Update ((Get-ProcessInventoryError $pathFixture.Context $encodedRequester) -ceq 'UPDATE_REQUESTER_LAUNCHER_IDENTITY_UNKNOWN') 'encoded requester launch is rejected even when it repeats approved path text and pins'
    $inventoryError=New-UpdateFixture
    $inventoryError.Context.Hooks.ProcessInventory={param($ctx)throw 'SYNTHETIC_INVENTORY_FAILURE'}
    Assert-Update ((Get-QuiescenceError $inventoryError.Context) -ceq 'UPDATE_PROCESS_INVENTORY_UNKNOWN') 'process inventory command failure fails closed with a stable diagnostic'
    Close-UpdateFixture $inventoryError
    Close-UpdateFixture $pathFixture

    $goodDir='O:BAG:BAD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200A9;;;AU)'
    $goodFile='O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200A9;;;AU)'
    Assert-Update (Test-F2UpdateExactDacl -Sddl $goodDir -Kind Directory) 'exact protected Administrator-owned directory DACL is accepted'
    Assert-Update (Test-F2UpdateExactDacl -Sddl $goodFile -Kind File) 'exact protected Administrator-owned file DACL is accepted'
    Assert-Update (-not (Test-F2UpdateExactDacl -Sddl 'O:SYD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200A9;;;AU)' -Kind File)) 'unexpected owner is rejected'
    Assert-Update (-not (Test-F2UpdateExactDacl -Sddl 'O:BAG:BAD:(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200A9;;;AU)' -Kind File)) 'unprotected DACL is rejected'
    Assert-Update (-not (Test-F2UpdateExactDacl -Sddl 'O:BAG:BAD:P(A;;FA;;;SY)(A;;FA;;;BA)(A;;0x1200A9;;;AU)(A;;FA;;;BU)' -Kind File)) 'extra writable principal is rejected'
    $programDataParent='O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;CI;0x116;;;BU)'
    Assert-Update (Test-F2UpdateSafeParentSddl -Sddl $programDataParent -AllowProgramDataCreateMask) 'reviewed ProgramData child-creation mask is distinguished from protected-child control'
    Assert-Update (-not (Test-F2UpdateSafeParentSddl -Sddl 'O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;CI;0x156;;;BU)' -AllowProgramDataCreateMask)) 'ProgramData delete-child/write-control expansion is rejected'
    Assert-Update (-not (Test-F2UpdateSafeParentSddl -Sddl 'O:SYG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;CI;0x10000000;;;BU)' -AllowProgramDataCreateMask)) 'ProgramData generic full-control grant is rejected'
    Assert-Update (Test-F2UpdateElevationIdentity -ExpectedRequesterSid 'S-1-5-21-100' -Context ([pscustomobject]@{Hooks=[pscustomobject]@{Identity={return [pscustomobject]@{UserSid='S-1-5-21-100';IsAdministrator=$true}}}})) 'same-requester Administrator identity satisfies the future elevated boundary'
    $alternateIdentityRejected=$false;try{[void](Test-F2UpdateElevationIdentity -ExpectedRequesterSid 'S-1-5-21-100' -Context ([pscustomobject]@{Hooks=[pscustomobject]@{Identity={return [pscustomobject]@{UserSid='S-1-5-21-200';IsAdministrator=$true}}}}))}catch{$alternateIdentityRejected=$_.Exception.Message -ceq 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH'}
    Assert-Update $alternateIdentityRejected 'different-account Administrator UAC credentials are rejected'
    $nonAdminIdentityRejected=$false;try{[void](Test-F2UpdateElevationIdentity -ExpectedRequesterSid 'S-1-5-21-100' -Context ([pscustomobject]@{Hooks=[pscustomobject]@{Identity={return [pscustomobject]@{UserSid='S-1-5-21-100';IsAdministrator=$false}}}}))}catch{$nonAdminIdentityRejected=$_.Exception.Message -ceq 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH'}
    Assert-Update $nonAdminIdentityRejected 'same-account non-Administrator token is rejected by elevated coordinator'
    $badManifest=$script:oldManifestBytes;try{[void](Get-F2UpdateManifestObject -Bytes $badManifest -ExpectedSchema v3 -ExpectedHash (Get-F2UpdateSha256 -Bytes $badManifest));$badSchemaRejected=$false}catch{$badSchemaRejected=$true}
    Assert-Update $badSchemaRejected 'candidate parser rejects the installed legacy v2 schema'
    $linkRoot=Join-Path $script:root 'link-target';$linkPath=Join-Path $script:root 'reparse-fixture'
    [void][IO.Directory]::CreateDirectory($linkRoot)
    $junctionCreated=$false
    try { New-Item -ItemType Junction -Path $linkPath -Target $linkRoot -ErrorAction Stop | Out-Null;$junctionCreated=$true } catch {}
    Assert-Update ($junctionCreated -and ((Get-Item -LiteralPath $linkPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'synthetic junction fixture is a reparse point on the Windows test host'
    $linkRejected=$false;try{[void](Test-F2UpdateNoReparsePath -Path (Join-Path $linkPath 'child'))}catch{$linkRejected=$_.Exception.Message -ceq 'UPDATE_REPARSE_POINT_REJECTED'}
    Assert-Update $linkRejected 'reparse point in a candidate path is rejected before traversal'

    # Shared reader leases exclude an update's exclusive lease and the update
    # manifest barrier excludes fresh readers while still permitting atomic replace.
    $shareRoot=Join-Path $script:root 'share-fixture';[void][IO.Directory]::CreateDirectory($shareRoot)
    $leasePath=Join-Path $shareRoot 'release.lock';$manifestPath=Join-Path $shareRoot 'approved-release.json';$candidatePath=Join-Path $shareRoot 'candidate.json';$backupPath=Join-Path $shareRoot 'backup.json'
    [IO.File]::WriteAllBytes($leasePath,[byte[]]@());[IO.File]::WriteAllText($manifestPath,'old');[IO.File]::WriteAllText($candidatePath,'new')
    $exclusive=[IO.File]::Open($leasePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{$blocked=$false;try{$reader=[IO.File]::Open($leasePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$reader.Dispose()}catch{$blocked=$true};Assert-Update $blocked 'exclusive updater lease blocks a new shared runtime lease'}finally{$exclusive.Dispose()}
    $shared=[IO.File]::Open($leasePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{$blocked=$false;try{$writer=[IO.File]::Open($leasePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$writer.Dispose()}catch{$blocked=$true};Assert-Update $blocked 'active runtime shared lease blocks updater exclusive acquisition'}finally{$shared.Dispose()}
    $barrier=[IO.File]::Open($manifestPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Delete)
    try{$blocked=$false;try{$reader=[IO.File]::Open($manifestPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$reader.Dispose()}catch{$blocked=$true};Assert-Update $blocked 'manifest barrier blocks a fresh v2 launcher read';[IO.File]::Replace($candidatePath,$manifestPath,$backupPath,$false);Assert-Update ([IO.File]::ReadAllText($manifestPath)-ceq 'new') 'same-volume manifest replacement exposes only the new active release'}finally{$barrier.Dispose()}
    Assert-Update ([IO.File]::ReadAllText($backupPath)-ceq 'old') 'same-volume manifest replacement preserves the prior release backup after the barrier closes'

    $happy=New-UpdateFixture
    $result=Invoke-F2UpdateTransaction -Context $happy.Context
    Close-UpdateFixture $happy
    $resultErrorCode=if($null -ne $result.PSObject.Properties['ErrorCode']){[string]$result.ErrorCode}else{''}
    $resultStage=if($null -ne $result.PSObject.Properties['Stage']){[string]$result.Stage}else{''}
    Assert-Update ($result.Success -and $result.Outcome -ceq 'UPDATE_COMPLETE' -and $result.InstalledFiles -eq 7 -and $result.OldReleaseRetained) ('successful transaction stages and activates exactly seven new files while retaining old package and manifest; success='+$result.Success+'; outcome='+$result.Outcome+'; error='+$resultErrorCode+'; stage='+$resultStage)
    $events=@($happy.Events)
    $barrierEvent=[array]::IndexOf($events,'ManifestBarrierAcquired');$firstInventoryEvent=[array]::IndexOf($events,'Inventory1');$secondInventoryEvent=[array]::IndexOf($events,'Inventory2');$activationEvent=[array]::IndexOf($events,'ManifestActivation')
    Assert-Update ($barrierEvent -ge 0 -and $barrierEvent -lt $firstInventoryEvent -and $firstInventoryEvent -lt $secondInventoryEvent -and $secondInventoryEvent -lt $activationEvent -and $happy.LateReaderBlocked) 'manifest barrier precedes both process inventories; a later reader is blocked and the final scan directly precedes activation'
    Assert-Update ((Get-UpdateActiveSha $happy) -ceq $happy.Context.CandidateManifestSha256) 'active manifest points only to the complete new versioned package'
    Assert-Update ((Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes($result.OldManifestBackup))) -ceq $script:F2UpdateOldManifestSha256) 'old external v2 manifest backup retains exact original digest'
    $newDir=Join-Path $result.PackageRoot 'scripts\f2-acl'
    Assert-Update (@(Get-ChildItem -LiteralPath $newDir -File).Count -eq 7) 'new immutable version directory contains exactly seven package files'
    foreach($file in @($happy.Context.Manifest.Files)){Assert-Update ((Get-F2UpdateSha256 -Bytes ([IO.File]::ReadAllBytes((Join-Path $newDir $file.Name))))-ceq$file.Sha256) ('activated package hash matches '+$file.Name)}
    $postRecovery=Resolve-F2UpdateTransaction -Context $happy.Context -TransactionId $result.TransactionId
    Assert-Update ($postRecovery.State -ceq 'NEW_RELEASE_ACTIVE' -and $postRecovery.Action -ceq 'VERIFY_ONLY') 'recovery classifies an already active, fully verified release without changing it'

    $candidateBad=New-UpdateFixture -CandidateHashMismatch
    $badResult=Invoke-F2UpdateTransaction -Context $candidateBad.Context
    Assert-Update (-not $badResult.Success -and $badResult.ErrorCode -ceq 'UPDATE_MANIFEST_HASH_MISMATCH' -and -not(Test-Path -LiteralPath (Join-Path $candidateBad.Context.PackageHome 'releases'))) 'candidate tampering fails before any protected release directory is created'
    $candidateIdentityBad=New-UpdateFixture
    $identityObject=[Text.Encoding]::UTF8.GetString($candidateIdentityBad.Context.CandidateManifestBytes)|ConvertFrom-Json
    $identityObject.BaselineMailboxId='ffffffffffffffffffffffffffffffff'
    $candidateIdentityBad.Context.CandidateManifestBytes=[Text.UTF8Encoding]::new($false).GetBytes(($identityObject|ConvertTo-Json -Compress -Depth 6))
    $candidateIdentityBad.Context.CandidateManifestSha256=Get-F2UpdateSha256 -Bytes $candidateIdentityBad.Context.CandidateManifestBytes
    $identityBadResult=Invoke-F2UpdateTransaction -Context $candidateIdentityBad.Context
    Assert-Update (-not $identityBadResult.Success -and $identityBadResult.ErrorCode -ceq 'UPDATE_MANIFEST_IDENTITY_OR_BASELINE_INVALID' -and -not(Test-Path -LiteralPath (Join-Path $candidateIdentityBad.Context.PackageHome 'releases'))) 'candidate with a rehashed but incorrect retained-baseline identity fails before staging'
    $candidatePathBad=New-UpdateFixture
    $pathObject=[Text.Encoding]::UTF8.GetString($candidatePathBad.Context.CandidateManifestBytes)|ConvertFrom-Json
    $pathObject.PackageRoot=Join-Path $script:root 'outside-release-root'
    $candidatePathBad.Context.CandidateManifestBytes=[Text.UTF8Encoding]::new($false).GetBytes(($pathObject|ConvertTo-Json -Compress -Depth 6))
    $candidatePathBad.Context.CandidateManifestSha256=Get-F2UpdateSha256 -Bytes $candidatePathBad.Context.CandidateManifestBytes
    $pathBadResult=Invoke-F2UpdateTransaction -Context $candidatePathBad.Context
    Assert-Update (-not $pathBadResult.Success -and $pathBadResult.ErrorCode -ceq 'UPDATE_CANDIDATE_PACKAGE_ROOT_MISMATCH' -and -not(Test-Path -LiteralPath (Join-Path $candidatePathBad.Context.PackageHome 'releases'))) 'candidate package path outside the versioned release root fails before staging'
    $parentBad=New-UpdateFixture
    $parentBad.Context.Hooks.ParentChainCheck={param($ctx)return $false}
    $parentResult=Invoke-F2UpdateTransaction -Context $parentBad.Context
    Assert-Update (-not $parentResult.Success -and $parentResult.ErrorCode -ceq 'UPDATE_PARENT_CHAIN_UNSAFE' -and -not(Test-Path -LiteralPath (Join-Path $parentBad.Context.PackageHome 'releases'))) 'unsafe current parent ACL profile fails before writes'
    $oldBad=New-UpdateFixture -CorruptOldFile
    $oldResult=Invoke-F2UpdateTransaction -Context $oldBad.Context
    Assert-Update (-not $oldResult.Success -and $oldResult.ErrorCode -ceq 'UPDATE_FILE_HASH_MISMATCH' -and -not(Test-Path -LiteralPath (Join-Path $oldBad.Context.PackageHome 'releases'))) 'modified installed release fails preflight without overwrite or staging'
    $aclBad=New-UpdateFixture
    $aclBadPath=Join-Path (Join-Path $aclBad.Context.PackageHome 'scripts\f2-acl') $script:names[0]
    $aclBadState=$aclBad
    $aclBad.Context.Hooks.AclCheck={param($path,$kind)if([string]::Equals($path,$aclBadPath,[StringComparison]::OrdinalIgnoreCase)){return $false};return $true}.GetNewClosure()
    $aclResult=Invoke-F2UpdateTransaction -Context $aclBad.Context
    Assert-Update (-not $aclResult.Success -and $aclResult.ErrorCode -ceq 'UPDATE_ACL_PROFILE_INVALID') 'unexpected existing owner or DACL fails closed before staging'
    $stagedAclBad=New-UpdateFixture
    $stagedAclBad.Context.Hooks.AclCheck={param($path,$kind)if($path -match '\\.f2-update-[0-9a-f]{32}\.new\\'){return $false};return $true}.GetNewClosure()
    $stagedAclResult=Invoke-F2UpdateTransaction -Context $stagedAclBad.Context
    Close-UpdateFixture $stagedAclBad
    Assert-Update (-not $stagedAclResult.Success -and $stagedAclResult.ErrorCode -ceq 'UPDATE_ACL_PROFILE_INVALID' -and (Get-UpdateActiveSha $stagedAclBad) -ceq $script:F2UpdateOldManifestSha256 -and $stagedAclResult.PartialObjectsPreserved -and -not $stagedAclResult.CleanupPerformed) 'staged directory ACL mismatch preserves the old active release and all partial objects'
    $lockAclBad=New-UpdateFixture
    $lockAclBad.Context.Hooks.AcquireLocks=$null
    $lockAclBad.Context.Hooks.AclCheck={param($path,$kind)if([string]::Equals($path,(Join-Path $lockAclBad.Context.ProgramDataRoot 'release.lock'),[StringComparison]::OrdinalIgnoreCase)){return $false};return $true}.GetNewClosure()
    $lockAclResult=Invoke-F2UpdateTransaction -Context $lockAclBad.Context
    Assert-Update (-not $lockAclResult.Success -and $lockAclResult.ErrorCode -ceq 'UPDATE_ACL_PROFILE_INVALID' -and -not(Test-Path -LiteralPath (Join-Path $lockAclBad.Context.PackageHome 'releases'))) ('new lease file ACL is verified immediately and blocks before release staging ['+$lockAclResult.ErrorCode+']')
    $manifestAclBad=New-UpdateFixture
    $manifestAclState=[pscustomobject]@{ActiveChecks=0;ActivePath=$manifestAclBad.Context.ActiveManifestPath}
    $manifestAclBad.Context.Hooks.AclCheck={param($path,$kind)if($kind -ceq 'File' -and [string]::Equals($path,$manifestAclState.ActivePath,[StringComparison]::OrdinalIgnoreCase)){$manifestAclState.ActiveChecks++;if($manifestAclState.ActiveChecks -ge 3){return $false}};return $true}.GetNewClosure()
    $manifestAclResult=Invoke-F2UpdateTransaction -Context $manifestAclBad.Context
    Close-UpdateFixture $manifestAclBad
    Assert-Update (-not $manifestAclResult.Success -and $manifestAclResult.ErrorCode -ceq 'UPDATE_ACL_PROFILE_INVALID' -and (Get-UpdateActiveSha $manifestAclBad) -ceq $manifestAclBad.Context.CandidateManifestSha256 -and $manifestAclResult.PartialObjectsPreserved -and -not $manifestAclResult.CleanupPerformed) 'active manifest ACL postcheck failure blocks success without unsafe rollback or deleting the retained release'
    $busy=New-UpdateFixture -ProcessActive $true
    $busyResult=Invoke-F2UpdateTransaction -Context $busy.Context
    Close-UpdateFixture $busy
    Assert-Update (-not $busyResult.Success -and $busyResult.ErrorCode -ceq 'UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN' -and -not(Test-Path -LiteralPath (Join-Path $busy.Context.PackageHome 'releases'))) 'detected active legacy launcher blocks before package staging'
    $late=New-UpdateFixture
    $late.LateProcess=$true
    $lateResult=Invoke-F2UpdateTransaction -Context $late.Context
    Close-UpdateFixture $late
    Assert-Update (-not $lateResult.Success -and $lateResult.ErrorCode -ceq 'UPDATE_RUNTIME_PROCESS_ACTIVE_OR_UNKNOWN' -and $late.InventoryCalls -eq 2 -and (Get-UpdateActiveSha $late) -ceq $script:F2UpdateOldManifestSha256 -and -not($late.Events -contains 'ManifestActivation')) 'process spawned after the first inventory is detected by the activation-edge rescan while old manifest remains active'
    $dirty=New-UpdateFixture
    [IO.File]::WriteAllText((Join-Path $dirty.Context.SourceRoot 'untracked-test-only.txt'),'dirty')
    $dirtyResult=Invoke-F2UpdateTransaction -Context $dirty.Context
    Assert-Update (-not $dirtyResult.Success -and $dirtyResult.ErrorCode -ceq 'UPDATE_SOURCE_WORKTREE_NOT_CLEAN' -and -not(Test-Path -LiteralPath (Join-Path $dirty.Context.PackageHome 'releases'))) 'dirty source checkout fails before any protected staging write'
    Remove-Item -LiteralPath (Join-Path $dirty.Context.SourceRoot 'untracked-test-only.txt') -Force
    $wrongCommit=New-UpdateFixture
    $wrongCommit.Context.ExpectedSourceCommit='f'*40
    $wrongCommitResult=Invoke-F2UpdateTransaction -Context $wrongCommit.Context
    Assert-Update (-not $wrongCommitResult.Success -and $wrongCommitResult.ErrorCode -ceq 'UPDATE_CANDIDATE_COMMIT_MISMATCH' -and -not(Test-Path -LiteralPath (Join-Path $wrongCommit.Context.PackageHome 'releases'))) 'source commit mismatch fails before any protected staging write'
    $extraOldObject=New-UpdateFixture
    [IO.File]::WriteAllText((Join-Path (Join-Path $extraOldObject.Context.PackageHome 'scripts\f2-acl') 'unexpected.txt'),'unknown')
    $extraOldResult=Invoke-F2UpdateTransaction -Context $extraOldObject.Context
    Assert-Update (-not $extraOldResult.Success -and $extraOldResult.ErrorCode -ceq 'UPDATE_EXISTING_OBJECT_SET_INVALID' -and -not(Test-Path -LiteralPath (Join-Path $extraOldObject.Context.PackageHome 'releases'))) ('unexpected existing package objects fail before staging and are never overwritten ['+$extraOldResult.ErrorCode+']')
    $preexistingRelease=New-UpdateFixture
    $preexistingReleasesRoot=Join-Path $preexistingRelease.Context.PackageHome 'releases'
    [void][IO.Directory]::CreateDirectory($preexistingReleasesRoot)
    [void][IO.Directory]::CreateDirectory((Join-Path $preexistingReleasesRoot 'unowned-entry'))
    $preexistingReleaseResult=Invoke-F2UpdateTransaction -Context $preexistingRelease.Context
    Assert-Update (-not $preexistingReleaseResult.Success -and $preexistingReleaseResult.ErrorCode -ceq 'UPDATE_EXISTING_TRANSACTION_OBJECTS_PRESENT') ('unowned release/staging entries are preserved and block the updater ['+$preexistingReleaseResult.ErrorCode+']')

    # Fault at each observed material-operation checkpoint. Earlier states keep
    # the old release active. Once a complete final package and candidate exist,
    # bounded recovery may only finish forward using those exact transaction
    # objects; after manifest replacement it verifies the new release only.
    $operationNames=@($happy.Operations|Sort-Object -Unique)
    Assert-Update ($operationNames.Count -ge 15) 'success path exposes fault checkpoints for each material transaction operation'
    $recoveryTests=0
    foreach($operation in $operationNames){
        $fault=New-UpdateFixture -FaultAt $operation
        $faultResult=Invoke-F2UpdateTransaction -Context $fault.Context
        Close-UpdateFixture $fault
        Assert-Update (-not $faultResult.Success -and $faultResult.PartialObjectsPreserved -and -not $faultResult.CleanupPerformed) ('injected interruption fails closed and preserves objects at '+$operation)
        if($faultResult.TransactionId){
            $activeSha=Get-UpdateActiveSha $fault
            $txJournal=Join-Path (Join-Path (Join-Path $fault.Context.ProgramDataRoot 'updates') $faultResult.TransactionId) 'transaction.ndjson'
            if(-not (Test-Path -LiteralPath $txJournal)){
                Assert-Update ($activeSha -ceq $script:F2UpdateOldManifestSha256) ('failure before journal leaves the original release active after '+$operation)
                continue
            }
            if($activeSha -ceq $script:F2UpdateOldManifestSha256){
                if($operation -in @('PackageActivatedSideBySide','JournalPackageReady')){
                    $recovery=Resolve-F2UpdateTransaction -Context $fault.Context -TransactionId $faultResult.TransactionId -ResumeForward
                    Close-UpdateFixture $fault
                    Assert-Update ($recovery.State -ceq 'NEW_RELEASE_ACTIVATED_BY_RECOVERY' -and $recovery.OldBackupRetained) ('recovery completes only the exact fully staged transaction after '+$operation+' ['+$recovery.State+']')
                    $recoveryTests++
                } else {
                    $recovery=Resolve-F2UpdateTransaction -Context $fault.Context -TransactionId $faultResult.TransactionId
                    Assert-Update ($recovery.State -ceq 'OLD_RELEASE_ACTIVE' -and $recovery.Action -ceq 'PRESERVE_ALL_OBJECTS') ('incomplete transaction preserves old active release after '+$operation)
                }
            } else {
                $recovery=Resolve-F2UpdateTransaction -Context $fault.Context -TransactionId $faultResult.TransactionId
                Assert-Update ($recovery.State -ceq 'NEW_RELEASE_ACTIVE') ('post-switch recovery validates new active package after '+$operation)
            }
        }
    }
    Assert-Update ($recoveryTests -ge 2) ('bounded forward recovery was exercised at both package-ready crash checkpoints [count='+$recoveryTests+']')

    $journalBad=New-UpdateFixture -FaultAt 'PackageActivatedSideBySide'
    $journalResult=Invoke-F2UpdateTransaction -Context $journalBad.Context
    Close-UpdateFixture $journalBad
    $journalPath=Join-Path (Join-Path (Join-Path $journalBad.Context.ProgramDataRoot 'updates') $journalResult.TransactionId) 'transaction.ndjson'
    [IO.File]::AppendAllText($journalPath,'{broken')
    $journalRejected=$false;try{[void](Resolve-F2UpdateTransaction -Context $journalBad.Context -TransactionId $journalResult.TransactionId -ResumeForward)}catch{$journalRejected=$true}
    Assert-Update $journalRejected 'malformed or partial transaction journal fails closed and is never repaired by guessing'
    $stateBad=New-UpdateFixture -FaultAt 'PackageActivatedSideBySide'
    $stateBadResult=Invoke-F2UpdateTransaction -Context $stateBad.Context
    Close-UpdateFixture $stateBad
    $stateJournal=Join-Path (Join-Path (Join-Path $stateBad.Context.ProgramDataRoot 'updates') $stateBadResult.TransactionId) 'transaction.ndjson'
    [IO.File]::WriteAllText($stateJournal,(ConvertTo-Json -Compress ([ordered]@{TxId=$stateBadResult.TransactionId;State='PREPARED';PreviousHash='';Utc=[DateTime]::UtcNow.ToString('o')})))
    $stateRejected=$false;try{[void](Resolve-F2UpdateTransaction -Context $stateBad.Context -TransactionId $stateBadResult.TransactionId -ResumeForward)}catch{$stateRejected=$_.Exception.Message -ceq 'UPDATE_RECOVERY_JOURNAL_STATE_INVALID'}
    Assert-Update $stateRejected 'syntactically valid but incomplete transaction journal cannot authorize forward recovery'
    $unknownActive=$false
    [IO.File]::WriteAllText($journalBad.Context.ActiveManifestPath,'unknown-manifest')
    try{[void](Resolve-F2UpdateTransaction -Context $journalBad.Context -TransactionId $journalResult.TransactionId)}catch{$unknownActive=$true}
    Assert-Update $unknownActive 'unknown active-manifest bytes block recovery without rewriting or rolling back'

    # The public elevated launcher is hash-bound, path-closed, single-use, and
    # labels child exit zero as requiring independent post-install attestation.
    $launcherText=Get-Content -LiteralPath $startScript -Raw
    $updaterText=Get-Content -LiteralPath $sourceScript -Raw
    Assert-Update ($launcherText -match '\$uacLaunchAttempted\s*=\s*\$true' -and $launcherText -match 'Start-Process.+-Verb RunAs.+-PassThru' -and $launcherText -notmatch 'Start-Process.+-RedirectStandard') 'launcher uses one human-consented UAC process and does not assume UAC stdout redirection'
    Assert-Update ($launcherText -match 'UPDATE_CHILD_EXIT_ZERO_REQUIRES_POST_ATTESTATION' -and $launcherText -match 'ActualChildExitCode' -and $launcherText -match 'UPDATE_CHILD_STATUS_UNKNOWN') 'launcher retains actual child exit or reports bounded unknown without claiming installation success'
    Assert-Update ($launcherText -match 'ExpectedSourceCommit' -and $launcherText -match 'ExpectedLauncherSha256' -and $launcherText -match 'ExpectedUpdaterSha256' -and $launcherText -match 'ExpectedCandidateManifestSha256' -and $launcherText -match 'C:\\Dev\\f2-g1-protected-updater-source') 'launcher has fixed destinations and requires externally reviewed launcher, updater, candidate and source pins'
    Assert-Update ($launcherText -match 'RequesterLauncherProcessId' -and $launcherText -match 'RequesterLauncherCreationUtcTicks' -and $launcherText -match 'requesterLauncherPid' -and $launcherText -match 'requesterLauncherCreationUtcTicks') 'launcher binds its single requester process across UAC by PID and creation timestamp without relying on ancestry alone'
    Assert-Update ($launcherText -match 'requesterSid' -and $launcherText -match '__REQUESTER_SID__' -and $launcherText -match 'Test-F2UpdateElevationIdentity' -and $updaterText -match 'function Test-F2UpdateElevationIdentity') 'standard requester SID is carried into the child and rechecked against the elevated Administrator token'
    Assert-Update ($launcherText -match 'RecoveryTransactionId' -and $launcherText -match 'ResumeForward' -and $updaterText -match 'function Invoke-F2ProtectedReleaseRecovery' -and $updaterText -match 'function Resolve-F2UpdateTransaction') 'same pinned updater exposes a bounded transaction-specific recovery entrypoint'
    Assert-Update ($launcherText -match 'Test-ChildNoReparse' -and $launcherText -match '4194304' -and $launcherText -match '65536' -and $launcherText -match 'Test-F2UpdateElevationIdentity' -and $updaterText -match 'UPDATE_ELEVATED_REQUESTER_IDENTITY_MISMATCH') 'parent and elevated child recheck bounded input paths and requester-token identity'
    Assert-Update ($launcherText -match 'UAC_CANCELLED' -and $launcherText -match 'UPDATE_NON_ELEVATED_PREFLIGHT_FAILURE' -and $launcherText -match 'UPDATE_CHILD_STATUS_UNKNOWN') 'launcher distinguishes preflight failure, consent cancellation and bounded child-status uncertainty'
    Assert-Update ($updaterText -notmatch 'Remove-Item|Set-Acl|icacls\.exe|Start-Process') 'updater contains no cleanup, ACL-relaxation, icacls or nested process-launch path'
    $childStart=$launcherText.IndexOf('$childScript = @''',[StringComparison]::Ordinal)
    $childEnd=$launcherText.IndexOf("'@",$childStart+18,[StringComparison]::Ordinal)
    $childTemplate=$launcherText.Substring($childStart,$childEnd-$childStart)
    $uacIndex=$launcherText.IndexOf('$uacLaunchAttempted = $true',[StringComparison]::Ordinal)
    $parentHashIndex=$launcherText.IndexOf('UPDATE_UPDATER_HASH_MISMATCH',[StringComparison]::Ordinal)
    $childHashIndex=$childTemplate.IndexOf('UPDATE_UPDATER_HASH_MISMATCH',[StringComparison]::Ordinal)
    Assert-Update ($uacIndex -gt $parentHashIndex -and ([regex]::Matches($childTemplate,'ReadAllBytes\(\$updaterPath\)')).Count -eq 1 -and $childHashIndex -lt $childTemplate.IndexOf('[scriptblock]::Create($text)',[StringComparison]::Ordinal) -and $childTemplate.IndexOf('[scriptblock]::Create($text)',[StringComparison]::Ordinal) -lt $childTemplate.IndexOf('Invoke-F2ProtectedReleaseUpdate -CandidateManifestBytes',[StringComparison]::Ordinal)) 'bootstrap verifies the one-read elevated updater bytes before executing those identical bytes and before staging'
}
finally {
    if(Test-Path -LiteralPath $script:root){Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue}
}

Write-Host ("Assertions={0};Failures={1}" -f $script:assertions,$script:failures.Count)
if($script:failures.Count -gt 0){$script:failures|ForEach-Object{Write-Error $_};exit 1}

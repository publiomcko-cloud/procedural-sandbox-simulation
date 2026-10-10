[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$testCount=0;$failures=New-Object 'System.Collections.Generic.List[string]'
function Assert-Icacl([bool]$Condition,[string]$Message){$script:testCount++;if(-not $Condition){$script:failures.Add($Message);Write-Host ('FAIL: '+$Message)}else{Write-Host ('PASS: '+$Message)}}
function Assert-IcaclReject([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Assert-Icacl $rejected $Message}
function New-CommandResult([string]$Path,[int]$Code=0,[string]$Stdout='',[string]$Stderr='',[bool]$Timeout=$false,[bool]$Complete=$true,[bool]$Cleanup=$true,[bool]$Truncated=$false){[pscustomobject]@{Path=$Path;ProcessId=1234;ExitCode=$Code;TimedOut=$Timeout;CleanupComplete=$Cleanup;OutputComplete=$Complete;Truncated=$Truncated;Stdout=$Stdout;Stderr=$Stderr;ReaderError=$null;ElapsedMilliseconds=15;StdoutBytes=[Text.Encoding]::UTF8.GetByteCount($Stdout);StderrBytes=[Text.Encoding]::UTF8.GetByteCount($Stderr);StdoutSha256='a';StderrSha256='b'}}

$scriptDir=Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptDir 'F2AclIcacls.Corroboration.psm1') -Force
Import-Module (Join-Path $scriptDir 'F2AclCapture.Protocol.psm1') -Force
$script:corroborationModule=Get-Module F2AclIcacls.Corroboration
$script:privateProcessInvocation=[scriptblock]::Create('param($file,$arguments,$timeout,$cleanup,$maxBytes) Invoke-F2IcaclsProcessCore -FilePath $file -Arguments $arguments -TimeoutSeconds $timeout -CleanupGraceMilliseconds $cleanup -MaxBytesPerStream $maxBytes')
function Invoke-TestIcaclsProcess([string]$FilePath,[string]$Arguments,[int]$TimeoutSeconds=15,[int]$CleanupGraceMilliseconds=1000,[int]$MaxBytesPerStream=262144){return $script:corroborationModule.Invoke($script:privateProcessInvocation,@($FilePath,$Arguments,$TimeoutSeconds,$CleanupGraceMilliseconds,$MaxBytesPerStream))}
$repoRoot=[IO.Path]::GetFullPath((Join-Path $scriptDir '..\..'))
$pinPath=Join-Path $scriptDir 'F2_ICACLS_SOURCE_PINS.json'
$pinHash=Get-F2IcaclsFileSha256 -Path $pinPath
$sourceCommit=(& git -C $repoRoot rev-parse HEAD).Trim()
$baselinePinIntegrity=[pscustomobject]@{CollectorScriptSha256='bea7cc93710c83d48a8ef9e54af306401694f17f611e696caa856938ca71a19b';ProtocolModuleSha256='42ba4dd5e31d1db64198bb1cee16d519f087a40364dfb4d2696b4a5bd844d728'}
$actualPins=Test-F2IcaclsSourcePins -RepositoryRoot $repoRoot -Integrity $baselinePinIntegrity -ExpectedPinManifestSha256 $pinHash -ExpectedCommitSha $sourceCommit -ActualCommitSha $sourceCommit
Assert-Icacl $actualPins.Pass 'actual repository helper pins match source files and retained collector provenance'

$projectRoot='C:\F2Synthetic\F2-G1-Isolated-Disposable'
$paths=@(Get-F2IcaclsExpectedPaths -ProjectRoot $projectRoot)
$projectVolume='\\?\Volume{11111111-1111-1111-1111-111111111111}\'
$evidenceVolume='\\?\Volume{22222222-2222-2222-2222-222222222222}\'
$sha='a' * 64;$sourceSha='b' * 64;$moduleSha='c' * 64
$records=@();foreach($path in $paths){$records+=@([pscustomobject]@{Path=$path;Status='PASS';Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type='Allow';AccessMask='0x001F01FF';InheritanceFlags='None';PropagationFlags='None';Inherited=$false})})}
$baseline=[pscustomobject]@{Complete=$true;VmId='6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1';VmName='F2-G1-Isolated-Disposable';VmState='Off';CaptureId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';Manifest=[pscustomobject]@{ExpectedCount=11;ExpectedPaths=$paths;RecordCount=11;UniquePathCount=11;ProjectVolumeGuid=$evidenceVolume};Records=$records}
$integrity=[pscustomobject]@{PayloadSha256=$sha;ProjectVolumeGuid=$projectVolume;EvidenceVolumeGuid=$evidenceVolume;SeparateFromProjectVolume=$true}
$storage=[pscustomobject]@{Win32MatchCount=1;DiskMatchCount=1;PhysicalMatchCount=1;Win32Serial='152D20337A0C';DiskSerial='152D20337A0C';PhysicalSerial='152D20337A0C';Win32Model='KINGSTON  SA400S37240G USB Device';DiskFriendlyName='KINGSTON SA400S37240G';DiskModel=' SA400S37240G   ';BusType='USB';DiskHealth='Healthy';PhysicalHealth='Healthy';DiskOperationalStatus='Online';PartitionDiskNumber=2;DiskNumber=2;Win32Index=2;GDriveLetter='G:';VolumeFileSystem='NTFS';GVolumeGuid=$projectVolume}
$observation=[pscustomobject]@{VmId=$baseline.VmId;VmName=$baseline.VmName;VmState='Off';NicCount=0;Storage=$storage;GVolumeGuid=$projectVolume;EvidenceVolumeGuid=$evidenceVolume;PathChecks=@($paths|%{[pscustomobject]@{Path=$_;Exists=$true;ReparsePoint=$false;ParentChainClear=$true}});EvidenceDirectory=[pscustomobject]@{Protected=$true;OwnerSid='S-1-5-32-544';NoUnexpectedPrincipals=$true;SeparateFromG=$true}}
$preflightArgs=@{Baseline=$baseline;Integrity=$integrity;Observation=$observation;BaselineSha256=$sha;ExpectedBaselineSha256=$sha;ExpectedScriptSha256=$sourceSha;ActualScriptSha256=$sourceSha;ExpectedModuleSha256=$moduleSha;ActualModuleSha256=$moduleSha;ProjectRoot=$projectRoot}
$preflight=Test-F2IcaclsPreflight @preflightArgs -Verbose
if(-not $preflight.Pass){$preflight.Gates|ForEach-Object{Write-Host ("PreflightGate={0};Pass={1};Detail={2}" -f $_.Name,$_.Pass,$_.Detail)}}
Assert-Icacl $preflight.Pass 'all pre-elevation synthetic identity, manifest, volume, path, pin and evidence gates pass'
Assert-Icacl ($preflight.ExpectedPaths.Count -eq 11 -and @($preflight.ExpectedPaths|Sort-Object -Unique).Count -eq 11) 'expected allowlist contains exactly 11 unique objects'
function Invoke-PreflightOverride([string]$Key,$Value){$copy=@{};foreach($k in $preflightArgs.Keys){$copy[$k]=$preflightArgs[$k]};$copy[$Key]=$Value;return Test-F2IcaclsPreflight @copy}
$bad=$observation.PSObject.Copy();$bad.NicCount=1
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $bad).Pass) 'unexpected NIC fails before any coordinator can launch'
$badStorage=$storage.PSObject.Copy();$badStorage.Win32Model='OTHER USB DEVICE';$badObs=$observation.PSObject.Copy();$badObs.Storage=$badStorage
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'incorrect Kingston model fails closed'
$badStorage=$storage.PSObject.Copy();$badStorage.PhysicalMatchCount=2;$badObs=$observation.PSObject.Copy();$badObs.Storage=$badStorage
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'ambiguous disk identity fails closed'
$badIntegrity=$integrity.PSObject.Copy();$badIntegrity.ProjectVolumeGuid=$evidenceVolume
Assert-Icacl (-not (Invoke-PreflightOverride 'Integrity' $badIntegrity).Pass) 'evidence volume GUID cannot be substituted for ProjectVolumeGuid'
$badIntegrity=$integrity.PSObject.Copy();$badIntegrity.ProjectVolumeGuid='\\?\Volume{33333333-3333-3333-3333-333333333333}\'
Assert-Icacl (-not (Invoke-PreflightOverride 'Integrity' $badIntegrity).Pass) 'wrong G: volume identity fails closed'
$badIntegrity=$integrity.PSObject.Copy();$badIntegrity.PayloadSha256='0'*64
Assert-Icacl (-not (Invoke-PreflightOverride 'Integrity' $badIntegrity).Pass) 'baseline integrity digest mismatch fails closed'
$badObs=$observation.PSObject.Copy();$badObs.PathChecks=@($observation.PathChecks);$badObs.PathChecks[5].ReparsePoint=$true
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'reparse path fails before UAC'
$badObs=$observation.PSObject.Copy();$badObs.PathChecks=@($observation.PathChecks);$badObs.PathChecks[7].ParentChainClear=$false
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'reparse or alias in an ancestor chain fails before UAC'
$badObs=$observation.PSObject.Copy();$badObs.PathChecks=@($observation.PathChecks|Select-Object -First 10)
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'missing path check fails before UAC'
$badObs=$observation.PSObject.Copy();$badEvidence=$observation.EvidenceDirectory.PSObject.Copy();$badEvidence.SeparateFromG=$false;$badObs.EvidenceDirectory=$badEvidence
Assert-Icacl (-not (Invoke-PreflightOverride 'Observation' $badObs).Pass) 'evidence storage on G: is rejected'
Assert-Icacl (-not (Invoke-PreflightOverride 'ActualScriptSha256' ('0'*64)).Pass) 'source pin mismatch fails before UAC'
$badBaseline=$baseline.PSObject.Copy();$badBaseline.PSObject.Properties.Remove('Manifest')
Assert-Icacl (-not (Invoke-PreflightOverride 'Baseline' $badBaseline).Pass) 'missing baseline fields return a closed preflight failure rather than throwing'
$badBaseline=$baseline.PSObject.Copy();$badRecords=@($baseline.Records);$badRecord=$badRecords[0].PSObject.Copy();$badRecord.Path=Join-Path (Split-Path -Parent $badRecord.Path) ('.\'+(Split-Path -Leaf $badRecord.Path));$badRecords[0]=$badRecord;$badBaseline.Records=$badRecords
Assert-Icacl (-not (Invoke-PreflightOverride 'Baseline' $badBaseline).Pass) 'non-canonical path spelling is rejected as an alias even when it resolves to an approved object'

$pinRoot=Join-Path $env:TEMP ('F2 Icacls Pin Fixture '+[guid]::NewGuid().ToString('N'));$pinAcl=Join-Path $pinRoot 'scripts\f2-acl';[void][IO.Directory]::CreateDirectory($pinAcl)
try{
    $moduleFixture=Join-Path $pinAcl 'F2AclIcacls.Corroboration.psm1';$captureFixture=Join-Path $pinAcl 'Invoke-F2AclReadOnlyCapture.ps1';$protocolFixture=Join-Path $pinAcl 'F2AclCapture.Protocol.psm1'
    [IO.File]::WriteAllText($moduleFixture,'module fixture');[IO.File]::WriteAllText($captureFixture,'capture fixture');[IO.File]::WriteAllText($protocolFixture,'protocol fixture')
    $fixturePins=[pscustomobject]@{Schema='f2-icacls-corroboration-pins-v1';ReviewedCollectorBaseSha='a62773f0553dff4a05055b18fa10834f7488ae55';CorroborationModuleSha256=(Get-F2IcaclsFileSha256 $moduleFixture);CollectorScriptSha256=(Get-F2IcaclsFileSha256 $captureFixture);ProtocolModuleSha256=(Get-F2IcaclsFileSha256 $protocolFixture)}
    $pinBytes=[Text.UTF8Encoding]::new($false).GetBytes(($fixturePins|ConvertTo-Json -Depth 4));[IO.File]::WriteAllBytes((Join-Path $pinAcl 'F2_ICACLS_SOURCE_PINS.json'),$pinBytes)
    $fixtureIntegrity=[pscustomobject]@{CollectorScriptSha256=$fixturePins.CollectorScriptSha256;ProtocolModuleSha256=$fixturePins.ProtocolModuleSha256}
    $pinDigest=Get-F2IcaclsSha256 -Bytes $pinBytes
    $pinCheck=Test-F2IcaclsSourcePins -RepositoryRoot $pinRoot -Integrity $fixtureIntegrity -ExpectedPinManifestSha256 $pinDigest -ExpectedCommitSha ('d'*40) -ActualCommitSha ('d'*40)
    Assert-Icacl $pinCheck.Pass 'source pin verifier reads the pin manifest and hashes spaced file paths with correct PowerShell 5.1 parameter binding'
    [IO.File]::WriteAllText($moduleFixture,'modified module fixture')
    Assert-Icacl (-not (Test-F2IcaclsSourcePins -RepositoryRoot $pinRoot -Integrity $fixtureIntegrity -ExpectedPinManifestSha256 $pinDigest -ExpectedCommitSha ('d'*40) -ActualCommitSha ('d'*40)).Pass) 'source pin verifier rejects modified helper source'
    Assert-Icacl (-not (Test-F2IcaclsSourcePins -RepositoryRoot $pinRoot -Integrity $fixtureIntegrity -ExpectedPinManifestSha256 $pinDigest -ExpectedCommitSha ('d'*40) -ActualCommitSha ('e'*40)).Pass) 'source pin verifier rejects a commit mismatch'
}finally{if(Test-Path $pinRoot){Remove-Item -LiteralPath $pinRoot -Recurse -Force}}

$goodText=@($paths[0],'S-1-5-32-544:(F)') -join "`r`n"
$spec=Get-F2IcaclsCommandSpec -Target $paths[0] -ProjectRoot $projectRoot
Assert-Icacl ($spec.FilePath -eq (Join-Path $env:SystemRoot 'System32\icacls.exe') -and $spec.Arguments -ceq ('"'+$paths[0]+'"') -and $spec.Switches.Count -eq 0) 'production command spec pins system icacls and uses one quoted allowlisted path without switches'
$specRejected=$false;try{Get-F2IcaclsCommandSpec -Target 'C:\F2Synthetic\outside.txt' -ProjectRoot $projectRoot|Out-Null}catch{$specRejected=$true}
Assert-Icacl $specRejected 'command spec rejects non-allowlisted paths before process creation'
$nativeText=($paths[0]+' *S-1-5-32-544:(F)'+"`r`n"+'  *S-1-5-18:(I)(OI)(CI)(F)'+"`r`n"+'Successfully processed 1 files; Failed processing 0 files')
$parsed=ConvertFrom-F2IcaclsText -Text $nativeText -ExpectedPath $paths[0]
Assert-Icacl ($parsed.PathMatched -and $parsed.Aces.Count -eq 2 -and $parsed.Aces[0].Mask -eq [uint32]0x001F01FF -and $parsed.Aces[1].Flags -contains 'Inherited' -and $parsed.Aces[1].Flags -contains 'ObjectInherit' -and $parsed.Aces[1].Flags -contains 'ContainerInherit') 'native-shaped output parses first header-line ACE and inherited ACE flags'
$namedPrincipalText=$paths[0]+' BUILTIN\Administrators:(F)'+"`r`n"+'  NT AUTHORITY\SYSTEM:(I)(OI)(CI)(F)'
$namedPrincipalParsed=ConvertFrom-F2IcaclsText -Text $namedPrincipalText -ExpectedPath $paths[0]
Assert-Icacl ($namedPrincipalParsed.PathMatched -and $namedPrincipalParsed.Aces.Count -eq 2 -and $namedPrincipalParsed.Aces[0].Sid -eq 'S-1-5-32-544' -and $namedPrincipalParsed.Aces[1].Sid -eq 'S-1-5-18') 'native friendly principal spellings resolve to their well-known SIDs'
$trailerParsed=ConvertFrom-F2IcaclsText -Text ($paths[0]+' *S-1-5-32-544:(F)'+"`r`n"+'unexpected output') -ExpectedPath $paths[0]
Assert-Icacl ($trailerParsed.Unsupported -contains 'UnparsedAclLine') 'unexpected trailer text prevents a complete parse'
$goodText=($paths[0]+' *S-1-5-32-544:(F)')
$goodComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 0 $goodText)
Assert-Icacl ($goodComparison.Classification -eq 'PASS') 'matching synthetic object is classified PASS'
$wrongText=@($paths[0],'S-1-5-32-544:(R)') -join "`r`n"
$wrongComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 0 $wrongText)
Assert-Icacl ($wrongComparison.Classification -eq 'MISMATCH') 'fully parsed different rights classify MISMATCH'
$unknownText=@($paths[0],'S-1-5-32-544:(QZ)') -join "`r`n"
$unknownComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 0 $unknownText)
Assert-Icacl ($unknownComparison.Classification -eq 'INDETERMINATE') 'unsupported icacls rights are INDETERMINATE'
$failedComparison=Get-F2IcaclsComparison -BaselineRecord $records[0] -CommandResult (New-CommandResult $paths[0] 5 '' 'Access is denied.')
Assert-Icacl ($failedComparison.Classification -eq 'INDETERMINATE') 'failed native invocation cannot classify an ACL'
$wrongPathParsed=ConvertFrom-F2IcaclsText -Text ('C:\F2Synthetic\other-target *S-1-5-32-544:(F)') -ExpectedPath $paths[0]
Assert-Icacl (-not $wrongPathParsed.PathMatched -and $wrongPathParsed.Unsupported -contains 'TargetPathMismatch') 'wrong target path is rejected before ACE attribution'
$prefixPathParsed=ConvertFrom-F2IcaclsText -Text ($paths[0]+'suffix *S-1-5-32-544:(F)') -ExpectedPath $paths[0]
Assert-Icacl (-not $prefixPathParsed.PathMatched) 'path-prefix collision is rejected as a non-exact target'
$commaCodes=@('RD','WD','AD','REA','WEA','X','DC','RA','WA','RC','WDAC','WO','S')
$commaParsed=ConvertFrom-F2IcaclsText -Text ($paths[0]+' *S-1-5-32-544:('+($commaCodes -join ',')+')') -ExpectedPath $paths[0]
$commaExpected=Get-F2IcaclsRightMask -Rights $commaCodes
Assert-Icacl ($commaExpected.Supported -and $commaExpected.Mask -eq [uint32]0x001E01FF -and $commaParsed.Aces.Count -eq 1 -and $commaParsed.Aces[0].Mask -eq $commaExpected.Mask) 'comma-separated detailed rights map to exact combined unsigned mask'
$rightCases=@([pscustomobject]@{Code='N';Mask=[uint32]0},[pscustomobject]@{Code='F';Mask=[uint32]0x001F01FF},[pscustomobject]@{Code='M';Mask=[uint32]0x001301BF},[pscustomobject]@{Code='RX';Mask=[uint32]0x001200A9},[pscustomobject]@{Code='R';Mask=[uint32]0x00120089},[pscustomobject]@{Code='W';Mask=[uint32]0x00120116},[pscustomobject]@{Code='D';Mask=[uint32]0x10000},[pscustomobject]@{Code='DE';Mask=[uint32]0x10000},[pscustomobject]@{Code='RD';Mask=[uint32]0x01},[pscustomobject]@{Code='WD';Mask=[uint32]0x02},[pscustomobject]@{Code='AD';Mask=[uint32]0x04},[pscustomobject]@{Code='REA';Mask=[uint32]0x08},[pscustomobject]@{Code='WEA';Mask=[uint32]0x10},[pscustomobject]@{Code='X';Mask=[uint32]0x20},[pscustomobject]@{Code='DC';Mask=[uint32]0x40},[pscustomobject]@{Code='RA';Mask=[uint32]0x80},[pscustomobject]@{Code='WA';Mask=[uint32]0x100},[pscustomobject]@{Code='RC';Mask=[uint32]0x20000},[pscustomobject]@{Code='WDAC';Mask=[uint32]0x40000},[pscustomobject]@{Code='WO';Mask=[uint32]0x80000},[pscustomobject]@{Code='S';Mask=[uint32]0x00100000},[pscustomobject]@{Code='AS';Mask=[uint32]0x01000000},[pscustomobject]@{Code='MA';Mask=[uint32]0x02000000},[pscustomobject]@{Code='GR';Mask=[Convert]::ToUInt32('80000000',16)},[pscustomobject]@{Code='GW';Mask=[Convert]::ToUInt32('40000000',16)},[pscustomobject]@{Code='GE';Mask=[Convert]::ToUInt32('20000000',16)},[pscustomobject]@{Code='GA';Mask=[uint32]0x10000000})
foreach($rightCase in $rightCases){$mapped=Get-F2IcaclsRightMask -Rights @($rightCase.Code);Assert-Icacl ($mapped.Supported -and $mapped.Mask -eq $rightCase.Mask) ('right code '+$rightCase.Code+' maps to its Windows file access mask')}
$genericCases=@([pscustomobject]@{Baseline='0x10000000';Displayed='F'},[pscustomobject]@{Baseline='0x80000006';Displayed='R,WD,AD'},[pscustomobject]@{Baseline='0x40000002';Displayed='W,WD'})
foreach($genericCase in $genericCases){$base=[pscustomobject]@{Path=$paths[0];Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type='Allow';AccessMask=$genericCase.Baseline;InheritanceFlags='None';PropagationFlags='None';Inherited=$false})};$genText=$paths[0]+' *S-1-5-32-544:('+ $genericCase.Displayed +')';$cmp=Get-F2IcaclsComparison -BaselineRecord $base -CommandResult (New-CommandResult $paths[0] 0 $genText);Assert-Icacl ($cmp.Classification -eq 'PASS') ('generic raw mask normalizes without false mismatch: '+$genericCase.Baseline)}
$unknownGenericBase=[pscustomobject]@{Path=$paths[0];Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type='Allow';AccessMask='0xF2000000';InheritanceFlags='None';PropagationFlags='None';Inherited=$false})}
$unknownGenericComparison=Get-F2IcaclsComparison -BaselineRecord $unknownGenericBase -CommandResult (New-CommandResult $paths[0] 0 ($paths[0]+' *S-1-5-32-544:(GA)'))
Assert-Icacl ($unknownGenericComparison.Classification -eq 'INDETERMINATE') 'generic mask with unresolved residual semantics remains INDETERMINATE'
$unknownSpecificBase=[pscustomobject]@{Path=$paths[0];Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type='Allow';AccessMask='0x00001000';InheritanceFlags='None';PropagationFlags='None';Inherited=$false})}
$unknownSpecificComparison=Get-F2IcaclsComparison -BaselineRecord $unknownSpecificBase -CommandResult (New-CommandResult $paths[0] 0 ($paths[0]+' *S-1-5-32-544:(RD)'))
Assert-Icacl ($unknownSpecificComparison.Classification -eq 'INDETERMINATE') 'unknown baseline access-mask bits do not become a false MISMATCH'
$maximumAllowedBase=[pscustomobject]@{Path=$paths[0];Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type='Allow';AccessMask='0x02000000';InheritanceFlags='None';PropagationFlags='None';Inherited=$false})}
$maximumAllowedEquivalent=Get-F2IcaclsComparison -BaselineRecord $maximumAllowedBase -CommandResult (New-CommandResult $paths[0] 0 ($paths[0]+' *S-1-5-32-544:(MA)'))
$maximumAllowedAmbiguous=Get-F2IcaclsComparison -BaselineRecord $maximumAllowedBase -CommandResult (New-CommandResult $paths[0] 0 ($paths[0]+' *S-1-5-32-544:(F)'))
Assert-Icacl ($maximumAllowedEquivalent.Classification -eq 'PASS' -and $maximumAllowedAmbiguous.Classification -eq 'INDETERMINATE') 'MAXIMUM_ALLOWED requires exact raw equality or remains semantically indeterminate'
$denyParsed=ConvertFrom-F2IcaclsText -Text ($paths[0]+' *S-1-5-32-544:(DENY)(WD,DC)(I)(CI)(IO)(NP)') -ExpectedPath $paths[0]
Assert-Icacl ($denyParsed.Aces.Count -eq 1 -and $denyParsed.Aces[0].Type -eq 'Deny' -and $denyParsed.Aces[0].Mask -eq [uint32]0x42 -and $denyParsed.Aces[0].Flags -contains 'Inherited' -and $denyParsed.Aces[0].Flags -contains 'ContainerInherit' -and $denyParsed.Aces[0].Flags -contains 'InheritOnly' -and $denyParsed.Aces[0].Flags -contains 'NoPropagateInherit') 'deny ACE detailed rights and inheritance flags parse faithfully'
$aceProfiles=@(
    [pscustomobject]@{Name='Full';Mask='0x001F01FF';Display='F';Flags=''},[pscustomobject]@{Name='Modify';Mask='0x001301BF';Display='M';Flags=''},
    [pscustomobject]@{Name='Read';Mask='0x00120089';Display='R';Flags=''},[pscustomobject]@{Name='ReadExecute';Mask='0x001200A9';Display='RX';Flags=''},
    [pscustomobject]@{Name='Write';Mask='0x00120116';Display='W';Flags=''},[pscustomobject]@{Name='ReadData';Mask='0x00000001';Display='RD';Flags=''},
    [pscustomobject]@{Name='ReadAttributes';Mask='0x00000080';Display='RA';Flags=''},[pscustomobject]@{Name='ReadExtendedAttributes';Mask='0x00000008';Display='REA';Flags=''},
    [pscustomobject]@{Name='GenericAll';Mask='0x10000000';Display='F';Flags=''},[pscustomobject]@{Name='GenericReadPlusSpecific';Mask='0x80000006';Display='R,WD,AD';Flags=''},
    [pscustomobject]@{Name='InheritedDeny';Mask='0x00010000';Display='(DENY)(D)(I)(OI)(CI)';Flags='Inherited,ObjectInherit,ContainerInherit'}
)
foreach($profile in $aceProfiles){$actualDisplay=$profile.Display;if($profile.Name -eq 'InheritedDeny'){$aceText='*S-1-5-32-544:'+ $profile.Display}else{$aceText='*S-1-5-32-544:('+ $actualDisplay +')'};$profileText=$paths[0]+' '+$aceText;$profileFlags=@();if($profile.Flags){$profileFlags=$profile.Flags.Split(',')};$profileRecord=[pscustomobject]@{Path=$paths[0];Aces=@([pscustomobject]@{Sid='S-1-5-32-544';Type=if($profile.Name -eq 'InheritedDeny'){'Deny'}else{'Allow'};AccessMask=$profile.Mask;InheritanceFlags=if($profileFlags -contains 'ObjectInherit'){'ObjectInherit'}else{'None'};PropagationFlags='None';Inherited=($profileFlags -contains 'Inherited')})};if($profileFlags -contains 'ContainerInherit'){$profileRecord.Aces[0].InheritanceFlags='ObjectInherit,ContainerInherit'};$profileResult=Get-F2IcaclsComparison -BaselineRecord $profileRecord -CommandResult (New-CommandResult $paths[0] 0 $profileText);Assert-Icacl ($profileResult.Classification -eq 'PASS') ('synthetic captured ACE profile compares without protected evidence: '+$profile.Name)}
$duplicateRecord=[pscustomobject]@{Path=$paths[0];Aces=@($records[0].Aces[0],$records[0].Aces[0])}
$duplicateText=$paths[0]+' *S-1-5-32-544:(F)'+"`r`n"+'  *S-1-5-32-544:(F)'
Assert-Icacl ((Get-F2IcaclsComparison -BaselineRecord $duplicateRecord -CommandResult (New-CommandResult $paths[0] 0 $duplicateText)).Classification -eq 'PASS') 'duplicate ACE multiplicity is retained and compared'
$inheritedBaseline=[pscustomobject]@{Path=$paths[0];Aces=@([pscustomobject]@{Sid='S-1-5-18';Type='Allow';AccessMask='0x001F01FF';InheritanceFlags='ObjectInherit,ContainerInherit';PropagationFlags='None';Inherited=$true})}
$inheritedOutput=$paths[0]+' *S-1-5-18:(I)(OI)(CI)(F)'
Assert-Icacl ((Get-F2IcaclsComparison -BaselineRecord $inheritedBaseline -CommandResult (New-CommandResult $paths[0] 0 $inheritedOutput)).Classification -eq 'PASS') 'inherited templates compare with preserved inheritance flags'

$calls=0;$elevationCalls=0
$runner={param($target)$script:calls++;New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}
$coordinator={param($failedPaths)$script:elevationCalls++;[pscustomobject]@{Complete=$true;Runs=@()}}
$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl ($plan.Complete -and $plan.Runs.Count -eq 11 -and $plan.ElevationLaunches -eq 0 -and $script:calls -eq 11) 'end-to-end all-11 standard success makes zero coordinator launches'
$beforeCalls=$script:calls;$scopeTargets=@($paths[0..9]);$scopeTargets+=@('C:\F2Synthetic\outside.txt');$scopePlan=Invoke-F2IcaclsPlan -Targets $scopeTargets -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $scopePlan.Complete -and $scopePlan.ElevationLaunches -eq 0 -and $script:calls -eq $beforeCalls) 'out-of-scope target set fails before standard child or coordinator launch'

$accessDeniedTarget=$paths[3];$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$coordinator={param($failedPaths)$script:elevationCalls++;$runs=@();foreach($target in $failedPaths){$runs+=@([pscustomobject]@{Path=$target;Result=(New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n"))})};[pscustomobject]@{Complete=$true;Runs=$runs}}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl ($plan.Complete -and $plan.ElevationLaunches -eq 1 -and $script:elevationCalls -eq ($before+1)) 'access-denied-only set triggers exactly one coordinator launch'
$elevatedRuns=@($plan.Runs|Where-Object{$_.Mode -eq 'Elevated'})
Assert-Icacl ($elevatedRuns.Count -eq 1 -and $elevatedRuns[0].Path -ceq $accessDeniedTarget) 'coordinator retries only the denied target'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 1 '' 'synthetic generic failure'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 0 -and $script:elevationCalls -eq $before) 'non-access-denied failure never launches UAC'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.' -Timeout $true -Complete $false -Cleanup $false}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 0 -and $script:elevationCalls -eq $before) 'timeout or incomplete stream prevents UAC retry and completion'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$coordinator={param($failedPaths)$script:elevationCalls++;[pscustomobject]@{Complete=$false;Runs=@()}}
$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 1 -and $plan.Outcome -eq 'INDETERMINATE') 'missing elevated evidence fails closed'
$runner={param($target)if($target -eq $accessDeniedTarget){New-CommandResult $target 5 '' 'Access is denied.'}else{New-CommandResult $target 0 (@($target,'S-1-5-32-544:(F)') -join "`r`n")}}
$coordinator={param($failedPaths)$script:elevationCalls++;throw 'synthetic coordinator startup failure'}
$before=$script:elevationCalls;$plan=Invoke-F2IcaclsPlan -Targets $paths -StandardRunner $runner -CoordinatorLauncher $coordinator -ProjectRoot $projectRoot -PermitOneCoordinatorLaunch
Assert-Icacl (-not $plan.Complete -and $plan.ElevationLaunches -eq 1 -and $plan.Outcome -eq 'INDETERMINATE' -and $script:elevationCalls -eq ($before+1)) 'coordinator exception is bounded, reported and never retried'

$psExe=Join-Path $PSHOME 'powershell.exe'
$okArgs='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''fixture-stdout'');[Console]::Error.WriteLine(''fixture-stderr'');exit 0"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $okArgs -TimeoutSeconds 5
Assert-Icacl ($proc.Started -and $proc.ExitCode -eq 0 -and $proc.OutputComplete -and $proc.CleanupComplete -and $proc.Stdout -match 'fixture-stdout' -and $proc.Stderr -match 'fixture-stderr' -and $proc.StdoutSha256 -match '^[0-9a-f]{64}$' -and $proc.StderrSha256 -match '^[0-9a-f]{64}$') 'bounded process runner captures stdout, stderr, PID, exit and hashes'
$quietArgs='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''quiet-stdout'');exit 0"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $quietArgs -TimeoutSeconds 5
Assert-Icacl ($proc.ExitCode -eq 0 -and $proc.OutputComplete -and $proc.StderrBytes -eq 0 -and $proc.StderrSha256 -match '^[0-9a-f]{64}$') 'successful command with empty stderr receives the SHA-256 of the empty byte stream'
$failArgs='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''fixture-fail-out'');[Console]::Error.WriteLine(''fixture-fail-err'');exit 23"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $failArgs -TimeoutSeconds 5
Assert-Icacl ($proc.ExitCode -eq 23 -and $proc.OutputComplete -and $proc.Stdout -match 'fixture-fail-out' -and $proc.Stderr -match 'fixture-fail-err') 'nonzero child exit retains complete separate streams'
$hangArgs='-NoProfile -NonInteractive -Command "while($true){[Console]::Out.WriteLine(''tick'');Start-Sleep -Milliseconds 25}"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $hangArgs -TimeoutSeconds 1 -CleanupGraceMilliseconds 500
Assert-Icacl ($proc.TimedOut -and -not $proc.OutputComplete -and $proc.ElapsedMilliseconds -lt 5000) 'hanging child returns bounded timeout with incomplete status'
$largeArgs='-NoProfile -NonInteractive -Command "[Console]::Out.Write(''x'' * 20000);exit 0"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $largeArgs -TimeoutSeconds 5 -MaxBytesPerStream 1024
Assert-Icacl ($proc.Truncated -and -not $proc.OutputComplete -and $proc.Stdout.Length -le 1024 -and $proc.StdoutBytes -gt 1024 -and $proc.ExitCode -eq 0) 'oversized single-line output is drained with bounded retention and cannot be complete'
Assert-Icacl ($proc.StdoutBytes -gt $proc.Stdout.Length -and $proc.Truncated -and $proc.Stdout.Length -le 1024) 'fixed-chunk stream pump does not depend on line events or allocate a giant line'
$largeErrorArgs='-NoProfile -NonInteractive -Command "[Console]::Error.Write(''y'' * 20000);exit 0"'
$proc=Invoke-TestIcaclsProcess -FilePath $psExe -Arguments $largeErrorArgs -TimeoutSeconds 5 -MaxBytesPerStream 1024
Assert-Icacl ($proc.Truncated -and -not $proc.OutputComplete -and $proc.Stderr.Length -le 1024 -and $proc.StderrBytes -gt 1024) 'oversized stderr is independently bounded and incomplete'
$missingExecutable=Join-Path $env:TEMP ('F2-Icacl-Missing-'+[guid]::NewGuid().ToString('N')+'.exe')
$proc=Invoke-TestIcaclsProcess -FilePath $missingExecutable -Arguments '' -TimeoutSeconds 1
Assert-Icacl (-not $proc.Started -and $null -eq $proc.ExitCode -and -not $proc.CleanupComplete -and -not $proc.OutputComplete) 'child startup failure is reported without inventing an exit code or completion'

$tempRoot=Join-Path $env:TEMP ('F2Icacls-Synthetic-'+[guid]::NewGuid().ToString('N'));$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
try{
    $testDir=Join-Path $tempRoot 'evidence';[void][IO.Directory]::CreateDirectory($tempRoot)
    $testEvidenceGuid=[F2Acl.NativeDirectory]::GetVolumeGuidForPath($tempRoot)
    $testProjectPath=$null
    foreach($driveInfo in [IO.DriveInfo]::GetDrives()){if(-not $driveInfo.IsReady){continue};try{$candidate=[F2Acl.NativeDirectory]::GetVolumeGuidForPath($driveInfo.RootDirectory.FullName);if($candidate -cne $testEvidenceGuid){$testProjectPath=$driveInfo.RootDirectory.FullName;break}}catch{}}
    if([string]::IsNullOrWhiteSpace($testProjectPath)){throw 'Synthetic evidence publication requires a second local volume; no project data is read or written.'}
    $testProjectGuid=[F2Acl.NativeDirectory]::GetVolumeGuidForPath($testProjectPath)
    $module=Get-Module F2AclIcacls.Corroboration
    $resolver={param($path)if([string]::Equals([IO.Path]::GetPathRoot($path),[IO.Path]::GetPathRoot($testProjectPath),[StringComparison]::OrdinalIgnoreCase)){$testProjectGuid}else{$testEvidenceGuid}}
    $module.SessionState.PSVariable.Set('F2IcaclsVolumeResolver',$resolver)
    $safeDir=New-F2AclRestrictedDirectory -Path $testDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $acl=Test-F2AclRestrictedDirectory -Path $safeDir -OwnerSid $owner
    $inputDir=Join-Path $tempRoot 'baseline-input';$inputSafe=New-F2AclRestrictedDirectory -Path $inputDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $payloadBytes=[Text.UTF8Encoding]::new($false).GetBytes(($baseline|ConvertTo-Json -Depth 14))
    [IO.File]::WriteAllBytes((Join-Path $inputSafe 'acl-baseline.json'),$payloadBytes)
    $inputIntegrity=[pscustomobject]@{Schema='f2-acl-integrity-v1';PayloadFile='acl-baseline.json';PayloadBytes=$payloadBytes.Length;PayloadSha256=(Get-F2IcaclsSha256 -Bytes $payloadBytes);ProjectVolumeGuid=$projectVolume;EvidenceVolumeGuid=$evidenceVolume;SeparateFromProjectVolume=$true}
    [IO.File]::WriteAllText((Join-Path $inputSafe 'integrity.json'),($inputIntegrity|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
    $mailboxSddl=Get-F2AclCoordinatorMailboxSddl -RequesterSid $owner
    $module.SessionState.PSVariable.Set('F2IcaclsMailboxPathResolver',{param($captureId) if($captureId -ceq $baseline.CaptureId){$inputSafe}else{Join-Path $tempRoot 'wrong-mailbox'}})
    $module.SessionState.PSVariable.Set('F2IcaclsMailboxDescriptorResolver',{param($path,$captureId) if([string]::Equals([IO.Path]::GetFullPath($path),[IO.Path]::GetFullPath($inputSafe),[StringComparison]::OrdinalIgnoreCase) -and $captureId -ceq $baseline.CaptureId){$mailboxSddl}else{throw 'Synthetic mailbox path mismatch.'}})
    $loaded=Read-F2IcaclsBaselineEvidence -EvidenceDirectory $inputSafe -ExpectedCaptureId $baseline.CaptureId -ExpectedRequesterSid $owner
    Assert-Icacl ($loaded.Pass -and $loaded.Integrity.ProjectVolumeGuid -eq $projectVolume -and $loaded.Integrity.ProjectVolumeGuid -ne $loaded.Baseline.Manifest.ProjectVolumeGuid -and $loaded.Integrity.EvidenceVolumeGuid -eq $evidenceVolume) 'baseline loader sources ProjectVolumeGuid from integrity.json and keeps EvidenceVolumeGuid separate'
    $mailboxCheck=Test-F2AclCoordinatorMailboxSddl -Sddl $mailboxSddl -RequesterSid $owner
    Assert-Icacl ($mailboxCheck.Protected -and $mailboxCheck.OwnerSid -eq 'S-1-5-32-544' -and $mailboxCheck.AceCount -eq 4 -and $mailboxCheck.RequesterSid -eq $owner) 'faithful four-ACE Administrators-owned coordinator mailbox fixture passes'
    Assert-Icacl (-not (Read-F2IcaclsBaselineEvidence -EvidenceDirectory (Join-Path $tempRoot 'wrong-mailbox') -ExpectedCaptureId $baseline.CaptureId -ExpectedRequesterSid $owner).Pass) 'mailbox path must be the exact capture-id-derived location'
    Assert-Icacl (-not (Read-F2IcaclsBaselineEvidence -EvidenceDirectory $inputSafe -ExpectedCaptureId $baseline.CaptureId -ExpectedRequesterSid 'S-1-5-21-111111111-222222222-333333333-4444').Pass) 'wrong requester SID invalidates four-ACE mailbox evidence'
    $wrongMailboxOwner=$mailboxSddl.Replace('O:BA','O:'+ $owner)
    Assert-IcaclReject { Test-F2AclCoordinatorMailboxSddl -Sddl $wrongMailboxOwner -RequesterSid $owner } 'requester-owned mailbox is rejected'
    $missingOwnerRights=$mailboxSddl.Replace('(A;OICI;0x1200a9;;;OW)','')
    Assert-IcaclReject { Test-F2AclCoordinatorMailboxSddl -Sddl $missingOwnerRights -RequesterSid $owner } 'mailbox without OWNER RIGHTS protection is rejected'
    $unprotectedMailbox=$mailboxSddl.Replace('D:P','D:')
    Assert-IcaclReject { Test-F2AclCoordinatorMailboxSddl -Sddl $unprotectedMailbox -RequesterSid $owner } 'inheriting mailbox DACL is rejected'
    $writableMailbox=$mailboxSddl.Replace('0x1200a9','FA')
    Assert-IcaclReject { Test-F2AclCoordinatorMailboxSddl -Sddl $writableMailbox -RequesterSid $owner } 'writable requester ACE in mailbox is rejected'
    $extraMailboxAce=$mailboxSddl+'(A;OICI;0x1200a9;;;S-1-5-21-111111111-222222222-333333333-5555)'
    Assert-IcaclReject { Test-F2AclCoordinatorMailboxSddl -Sddl $extraMailboxAce -RequesterSid $owner } 'unexpected fifth mailbox ACE is rejected'
    $junctionPath=Join-Path $tempRoot 'mailbox-junction';$junctionMade=$false
    try{New-Item -ItemType Junction -Path $junctionPath -Target $inputSafe -ErrorAction Stop|Out-Null;$junctionMade=$true;$module.SessionState.PSVariable.Set('F2IcaclsMailboxPathResolver',{param($captureId)$junctionPath});Assert-Icacl (-not (Read-F2IcaclsBaselineEvidence -EvidenceDirectory $junctionPath -ExpectedCaptureId $baseline.CaptureId -ExpectedRequesterSid $owner).Pass) 'mailbox reparse/junction path is rejected before ACL acceptance'}catch{Assert-Icacl $false ('mailbox junction adversarial fixture could not be created: '+$_.Exception.GetType().Name)}finally{if($junctionMade){try{[IO.Directory]::Delete($junctionPath)}catch{}};$module.SessionState.PSVariable.Set('F2IcaclsMailboxPathResolver',{param($captureId) if($captureId -ceq $baseline.CaptureId){$inputSafe}else{Join-Path $tempRoot 'wrong-mailbox'}})}
    [IO.File]::WriteAllText((Join-Path $inputSafe 'acl-baseline.json'),'tampered payload',[Text.UTF8Encoding]::new($false))
    Assert-Icacl (-not (Read-F2IcaclsBaselineEvidence -EvidenceDirectory $inputSafe -ExpectedCaptureId $baseline.CaptureId -ExpectedRequesterSid $owner).Pass) 'baseline payload tampering fails its integrity.json digest'
    $runs=@();$comparisons=@();foreach($path in $paths){$txt=@($path,'S-1-5-32-544:(F)') -join "`r`n";$r=New-CommandResult $path 0 $txt;$runs+=@([pscustomobject]@{Path=$path;Result=$r;Mode='Synthetic'});$comparisons+=@([pscustomobject]@{Path=$path;Classification='PASS';Reason='SyntheticFixture'})}
    $package=Write-F2IcaclsEvidencePackage -Directory $safeDir -OwnerSid $owner -Targets $paths -Runs $runs -Comparisons $comparisons -ProjectVolumePath $testProjectPath -ProjectVolumeGuid $testProjectGuid -EvidenceVolumeGuid $testEvidenceGuid
    Assert-Icacl ($package.Complete -and $package.TargetCount -eq 11 -and $package.RunCount -eq 11 -and (Test-Path (Join-Path $safeDir 'integrity.json'))) '11-object synthetic evidence package is atomically create-new in protected directory'
    $integrityDoc=Get-Content -Raw (Join-Path $safeDir 'integrity.json')|ConvertFrom-Json
    $verified=$true;foreach($row in $integrityDoc.Results){$file=Join-Path $safeDir $row.Name;$verified=$verified -and (Get-Item $file).Length -eq $row.Bytes -and (Get-F2IcaclsSha256 -Bytes ([IO.File]::ReadAllBytes($file))) -eq $row.Sha256}
    Assert-Icacl $verified 'synthetic evidence file hashes and byte counts verify'
    Assert-Icacl (Test-F2AclRestrictedDirectory -Path $safeDir -OwnerSid $owner).Protected 'evidence DACL remains protected after publication'
    $retryRuns=@($runs);$retryRuns+=@([pscustomobject]@{Path=$paths[0];Result=(New-CommandResult $paths[0] 5 '' 'Access is denied.');Mode='Standard'})
    $retryDir=Join-Path $tempRoot 'retry-evidence';$retrySafe=New-F2AclRestrictedDirectory -Path $retryDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $retryPackage=Write-F2IcaclsEvidencePackage -Directory $retrySafe -OwnerSid $owner -Targets $paths -Runs $retryRuns -Comparisons $comparisons -ProjectVolumePath $testProjectPath -ProjectVolumeGuid $testProjectGuid -EvidenceVolumeGuid $testEvidenceGuid
    $retryManifest=Get-Content -Raw (Join-Path $retrySafe 'integrity.json')|ConvertFrom-Json
    Assert-Icacl ($retryPackage.Complete -and $retryManifest.RunCount -eq 12 -and -not $retryManifest.AllCommandsSuccessful -and $retryManifest.AllComparisonsPass) 'evidence completeness allows a standard denial plus one elevated retry without hiding the failed attempt'
    $badRuns=@($runs);$badRuns[0]=$badRuns[0].PSObject.Copy();$badRuns[0].Result=New-CommandResult $paths[0] 5 '' 'Access is denied.'
    $badComparisons=@($comparisons);$badComparisons[0]=[pscustomobject]@{Path=$paths[0];Classification='INDETERMINATE';Reason='AccessDenied'}
    $failedDir=Join-Path $tempRoot 'failed-evidence';$failedSafe=New-F2AclRestrictedDirectory -Path $failedDir -OwnerSid $owner -ProjectVolumePath $testProjectPath
    $failedPackage=Write-F2IcaclsEvidencePackage -Directory $failedSafe -OwnerSid $owner -Targets $paths -Runs $badRuns -Comparisons $badComparisons -ProjectVolumePath $testProjectPath -ProjectVolumeGuid $testProjectGuid -EvidenceVolumeGuid $testEvidenceGuid
    $failedRecord=Get-Content -Raw (Join-Path $failedSafe 'icacls-01.json')|ConvertFrom-Json
    $failedManifest=Get-Content -Raw (Join-Path $failedSafe 'integrity.json')|ConvertFrom-Json
    Assert-Icacl ($failedPackage.Complete -and -not $failedManifest.AllCommandsSuccessful -and -not $failedManifest.AllComparisonsPass -and $failedRecord.Result.ExitCode -eq 5 -and $failedRecord.Result.Stderr -eq 'Access is denied.') 'failing icacls output and exit status are published as complete diagnostic evidence, never a pass'
}finally{if(Test-Path $tempRoot){Remove-Item -LiteralPath $tempRoot -Recurse -Force}}

Write-Host ("Assertions={0}; Failures={1}" -f $testCount,$failures.Count)
if($failures.Count -gt 0){$failures|ForEach-Object{Write-Error $_};exit 1}
exit 0

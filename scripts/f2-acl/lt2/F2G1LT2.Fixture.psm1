# LT-2: Disposable Windows CI fixture reader ONLY. No protected C:/G: access.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot '..\lt1\F2G1LT1.Synthetic.psm1') -ErrorAction Stop

# Deliberately small native interop: observe the CURRENT Windows token.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
public static class F2G1LT2TokenNative {
 [DllImport("advapi32.dll", SetLastError=true)]
 static extern bool GetTokenInformation(IntPtr token,int kind,out int data,int length,out int returned);
 [DllImport("advapi32.dll", SetLastError=true)]
 static extern bool GetTokenInformation(IntPtr token,int kind,IntPtr data,int length,out int returned);
 public static int IntValue(IntPtr token,int kind) {
   int value,got;
   if (!GetTokenInformation(token,kind,out value,4,out got) || got!=4)
     throw new InvalidOperationException("TOKEN_INFORMATION_UNAVAILABLE");
   return value;
 }
 public static int IntegrityRid(IntPtr token) {
   int length=0;
   GetTokenInformation(token,25,IntPtr.Zero,0,out length);
   if(length<16 || length>4096) throw new InvalidOperationException("INTEGRITY_UNAVAILABLE");
   IntPtr buffer=Marshal.AllocHGlobal(length);
   try {
     int got;
     if(!GetTokenInformation(token,25,buffer,length,out got) || got>length || got<16)
       throw new InvalidOperationException("INTEGRITY_UNAVAILABLE");
     IntPtr sid=Marshal.ReadIntPtr(buffer);
     if(sid==IntPtr.Zero) throw new InvalidOperationException("INTEGRITY_UNAVAILABLE");
     string value=new SecurityIdentifier(sid).Value;
     return Int32.Parse(value.Substring(value.LastIndexOf('-')+1));
   } finally { Marshal.FreeHGlobal(buffer); }
 }
}
'@ -ErrorAction Stop

function Assert-F2G1LT2CiEnvironment {
    if($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
      $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
      $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
      $env:GITHUB_REPOSITORY -cne 'publiomcko-cloud/procedural-sandbox-simulation') {
        throw 'CI_WINDOWS_FIXTURE_ONLY'
    }
}
function Get-F2G1LT2RealToken {
    Assert-F2G1LT2CiEnvironment
    try {
        $impersonating=[Security.Principal.WindowsIdentity]::GetCurrent($true)
        if($null -ne $impersonating) { return [pscustomobject]@{Kind='BLOCKED';Allowed=$false} }
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $principal=New-Object Security.Principal.WindowsPrincipal($identity)
            $elevation=[F2G1LT2TokenNative]::IntValue($identity.Token,20)
            $type=[F2G1LT2TokenNative]::IntValue($identity.Token,18)
            $rid=[F2G1LT2TokenNative]::IntegrityRid($identity.Token)
            $admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            $system=$identity.IsSystem -or $identity.IsAnonymous -or $identity.IsGuest
            # Windows: Default=1, Full=2, Limited=3. Medium integrity=[8192,12288).
            # A filtered UAC admin is acceptable only with an actual LIMITED token,
            # elevation=0, admin role inactive, and medium integrity.
            $allow=(-not $system -and -not $admin -and $elevation -eq 0 -and
               $type -in @(1,3) -and $rid -ge 8192 -and $rid -lt 12288)
            $label=if(-not $allow){'BLOCKED'}elseif($type -eq 3){'FILTERED_LIMITED'}else{'STANDARD'}
            return [pscustomobject]@{Kind=$label;Allowed=[bool]$allow}
        } finally {$identity.Dispose()}
    } catch {
        return [pscustomobject]@{Kind='BLOCKED';Allowed=$false}
    }
}
function Assert-F2G1LT2FixtureRoot([string]$Root) {
    Assert-F2G1LT2CiEnvironment
    if([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {throw 'FIXTURE_ROOT_REJECTED'}
    $temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $leaf=[IO.Path]::GetFileName($full)
    if([IO.Path]::GetDirectoryName($full) -cne $temp -or $leaf -cnotmatch '^F2G1-LT2-[0-9a-fA-F-]{36}$'){throw 'FIXTURE_ROOT_REJECTED'}
    if(-not [IO.Directory]::Exists($full)){throw 'FIXTURE_ROOT_REJECTED'}
    $tempItem=Get-Item -LiteralPath $temp -Force -ErrorAction Stop
    $rootItem=Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if((($tempItem.Attributes -bor $rootItem.Attributes) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'FIXTURE_REPARSE_REJECTED'}
    return $full
}
function Convert-F2G1LT2LabelToPath([string]$Root,[string]$Label) {
    if($Label -ceq 'C:\'){return (Join-Path $Root 'C')}
    if(-not $Label.StartsWith('C:\',[StringComparison]::Ordinal) -or $Label.Length -le 3){throw 'NONFIXED_LABEL'}
    return (Join-Path (Join-Path $Root 'C') $Label.Substring(3))
}
function Get-F2G1LT2Sha([byte[]]$Bytes) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()}
    finally {$hash.Dispose()}
}
function Test-F2G1LT2Physical {
    param([string]$FixtureRoot,[switch]$RequireStandardToken)
    $report=[ordered]@{
        Schema='f2-g1-lt2-disposable-fixture-v1';Mode='DISPOSABLE_WINDOWS_CI_FIXTURE_ONLY'
        Verdict='BLOCKED_WITH_EVIDENCE';Code='INCOMPLETE_OBSERVATION';TokenClass='BLOCKED'
        FixtureObjects=0;FixtureFiles=0;Inventories=0;ProtectedReads=0
        HistoricalV2='NOT_ATTESTED_SYNTHETIC_BYTES';LinkAndAds='LINK_ADS_NOT_ATTESTED'
        TokenEnforced=[bool]$RequireStandardToken
    }
    try {
        $root=Assert-F2G1LT2FixtureRoot $FixtureRoot
        $token=Get-F2G1LT2RealToken
        $report.TokenClass=$token.Kind
        if($RequireStandardToken -and -not $token.Allowed){throw 'REAL_TOKEN_NOT_STANDARD'}
        # CI-only observational mode may run as an elevated GitHub runner.
        # It does NOT qualify elevated tokens for any future protected-host read.
        $scope=Get-F2G1LT1Scope
        $contents=@{}
        $before=@{}
        $after=@{}
        $directories=@($scope.Directories)
        foreach($label in $directories) {
            $path=Convert-F2G1LT2LabelToPath $root $label
            $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'DIRECTORY_TYPE_REPARSE'}
            $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
            if([string]::IsNullOrEmpty($acl.Owner) -or [string]::IsNullOrEmpty($acl.Sddl)){throw 'ACL_UNREADABLE'}
            $before[$label]=@{Created=$item.CreationTimeUtc.Ticks;Acl=$acl.Sddl}
        }
        foreach($file in $scope.Files){
            $label=$file.Path
            $path=Convert-F2G1LT2LabelToPath $root $label
            $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'FILE_TYPE_REPARSE'}
            $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
            if([string]::IsNullOrEmpty($acl.Owner) -or [string]::IsNullOrEmpty($acl.Sddl)){throw 'ACL_UNREADABLE'}
            $size=[int64]$item.Length
            if($size -le 0 -or $size -gt [math]::Min([int64]$file.Max,1048576)){throw 'FILE_SIZE_REJECTED'}
            $handle=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
            try {
                if($handle.Length -ne $size){throw 'FILE_DRIFT'}
                $bytes=New-Object byte[] ([int]$size)
                $offset=0
                while($offset -lt $bytes.Length){
                    $got=$handle.Read($bytes,$offset,$bytes.Length-$offset)
                    if($got -le 0){throw 'TRUNCATED_READ'}
                    $offset+=$got
                }
                if($handle.ReadByte() -ne -1){throw 'TRAILING_BYTES'}
                $next=Get-Item -LiteralPath $path -Force -ErrorAction Stop
                $acl2=Get-Acl -LiteralPath $path -ErrorAction Stop
                if($next.Length -ne $size -or $next.CreationTimeUtc.Ticks -ne $item.CreationTimeUtc.Ticks -or
                   $next.LastWriteTimeUtc.Ticks -ne $item.LastWriteTimeUtc.Ticks -or $acl.Sddl -cne $acl2.Sddl){
                    throw 'FILE_DRIFT'
                }
            } finally {$handle.Dispose()}
            $contents[$label]=[pscustomobject]@{Hash=(Get-F2G1LT2Sha $bytes);Bytes=$bytes}
        }
        $seen=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
        foreach($inv in $scope.Inventories){
            $path=Convert-F2G1LT2LabelToPath $root $inv.Path
            $names=@(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop | ForEach-Object {$_.Name})
            if($names.Count -ne @($inv.Names).Count){throw 'INVENTORY_MISMATCH'}
            foreach($name in $names){
                if($inv.Names -cnotcontains $name -or $scope.TransactionNames -ccontains $name){throw 'INVENTORY_MISMATCH'}
            }
        }
        foreach($label in $directories){
            $path=Convert-F2G1LT2LabelToPath $root $label
            $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
            $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
            if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
               $item.CreationTimeUtc.Ticks -ne $before[$label].Created -or $acl.Sddl -cne $before[$label].Acl){throw 'DIRECTORY_DRIFT'}
        }
        # Schema/cross-file integrity checks against real read bytes, not mocked GetPath/ReadBytes.
        $utf8=[Text.UTF8Encoding]::new($false,$true)
        $manifestLabel='C:\ProgramData\F2-G1-Icacls\approved-release.json'
        $mailbox='C:\ProgramData\F2-G1-ACL-Evidence-ecb6deeb424e40feb5354d18908986df\'
        $m=$utf8.GetString($contents[$manifestLabel].Bytes)|ConvertFrom-Json -ErrorAction Stop
        if($m.Schema -cne 'f2-icacls-runtime-release-v2' -or
           $m.ReviewedCommitSha -cne '5741ffe90a3abd02a08563e6431e8a0b9b63eeb1' -or
           $m.BaselineMailboxId -cne 'ecb6deeb424e40feb5354d18908986df' -or
           $m.BaselinePayloadCaptureId -cne '489e7fec-0300-467c-bfbd-a46fb8cf7211'){throw 'MANIFEST_IDENTITY_INVALID'}
        if(@($m.Files).Count -ne 7){throw 'PACKAGE_MANIFEST_INCOMPLETE'}
        $packageRoot='C:\Program Files\F2-G1-Icacls\scripts\f2-acl\'
        $pkgs=@($scope.Files|Where-Object {$_.Path.StartsWith($packageRoot,[StringComparison]::Ordinal)})
        foreach($pin in @($m.Files)){
            $label=$packageRoot+[string]$pin.Name
            if(@($pkgs.Path) -cnotcontains $label -or $contents[$label].Hash -cne [string]$pin.Sha256){throw 'PACKAGE_HASH_INVALID'}
        }
        $payload=$contents[$mailbox+'acl-baseline.json']
        $integrity=$contents[$mailbox+'integrity.json']
        if($m.BaselinePayloadSha256 -cne $payload.Hash -or $m.BaselineIntegritySha256 -cne $integrity.Hash){throw 'BASELINE_HASH_INVALID'}
        $base=$utf8.GetString($payload.Bytes)|ConvertFrom-Json -ErrorAction Stop
        $integ=$utf8.GetString($integrity.Bytes)|ConvertFrom-Json -ErrorAction Stop
        if($base.CaptureId -cne $m.BaselinePayloadCaptureId -or $base.Complete -ne $true -or
           @($base.Records).Count -ne 11 -or @($base.Records.Path|Sort-Object -Unique).Count -ne 11 -or
           @($base.Manifest.ExpectedPaths).Count -ne 11 -or $integ.Schema -cne 'f2-acl-integrity-v1' -or
           $integ.PayloadFile -cne 'acl-baseline.json' -or [int64]$integ.PayloadBytes -ne $payload.Bytes.Length -or
           $integ.PayloadSha256 -cne $payload.Hash){throw 'EVIDENCE_INTEGRITY_INVALID'}
        $frame=$contents[$mailbox+'acl-baseline.frame'].Bytes
        if($frame.Length -ne $payload.Bytes.Length+44 -or
           [BitConverter]::ToString($frame[0..7]) -cne '46-32-41-43-4C-01-0D-0A' -or
           [BitConverter]::ToInt32($frame,8) -ne $payload.Bytes.Length){throw 'FRAME_INVALID'}
        $fb=New-Object byte[] $payload.Bytes.Length
        [Buffer]::BlockCopy($frame,12,$fb,0,$fb.Length)
        $fh=[byte[]]$frame[($frame.Length-32)..($frame.Length-1)]
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$digest=$sha.ComputeHash($fb)}finally{$sha.Dispose()}
        if((Get-F2G1LT2Sha $fb) -cne $payload.Hash -or [BitConverter]::ToString($fh) -cne [BitConverter]::ToString($digest)){throw 'FRAME_INVALID'}
        $stream=$contents[$mailbox+'powershell-streams.json']
        if($integ.PowerShellStreamsSha256 -cne $stream.Hash -or
           [int64]$integ.PowerShellStreamsBytes -ne $stream.Bytes.Length){throw 'STREAM_INTEGRITY_INVALID'}
        $streamJson=$utf8.GetString($stream.Bytes)|ConvertFrom-Json -ErrorAction Stop
        if($streamJson.Schema -cne 'f2-acl-powershell-streams-v1' -or $streamJson.Complete -ne $true){throw 'STREAM_INTEGRITY_INVALID'}
        $report.Verdict='SYNTHETIC_FIXTURE_PASS'
        $report.Code='PHYSICAL_FIXTURE_EVIDENCE_MATCHED'
        $report.FixtureObjects=23;$report.FixtureFiles=15;$report.Inventories=5
    } catch {
        # Only finite sanitized codes, never paths, Windows SIDs, SDDL or contents.
        $allowed=@('CI_WINDOWS_FIXTURE_ONLY','FIXTURE_ROOT_REJECTED','FIXTURE_REPARSE_REJECTED','REAL_TOKEN_NOT_STANDARD','DIRECTORY_TYPE_REPARSE','ACL_UNREADABLE','FILE_TYPE_REPARSE','FILE_SIZE_REJECTED','FILE_DRIFT','TRUNCATED_READ','TRAILING_BYTES','INVENTORY_MISMATCH','DIRECTORY_DRIFT','MANIFEST_IDENTITY_INVALID','PACKAGE_MANIFEST_INCOMPLETE','PACKAGE_HASH_INVALID','BASELINE_HASH_INVALID','EVIDENCE_INTEGRITY_INVALID','FRAME_INVALID','STREAM_INTEGRITY_INVALID')
        $code='UNCLASSIFIED_BLOCKED'
        foreach($allowedCode in $allowed){if($_.Exception.Message -ceq $allowedCode){$code=$allowedCode;break}}
        $report.Code=$code
    }
    return [pscustomobject]$report
}
Export-ModuleMember -Function Get-F2G1LT2RealToken,Test-F2G1LT2Physical,Assert-F2G1LT2FixtureRoot

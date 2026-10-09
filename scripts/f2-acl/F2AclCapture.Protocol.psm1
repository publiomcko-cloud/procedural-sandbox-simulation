Set-StrictMode -Version Latest

$script:F2AclSchema = 'f2-acl-baseline-v1'
$script:F2AclMaxPayloadBytes = 262144

if ($null -eq ('F2Acl.NativeDirectory' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace F2Acl {
    public static class NativeDirectory {
        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES {
            public int nLength;
            public IntPtr lpSecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)] public bool bInheritHandle;
        }
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint revision, out IntPtr descriptor, out uint size);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="GetNamedSecurityInfoW")]
        private static extern uint GetNamedSecurityInfoNative(string path, int objectType, uint securityInfo, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr descriptor);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr descriptor, uint revision, uint securityInfo, out IntPtr sddl, out uint size);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, EntryPoint="CreateDirectoryW")]
        private static extern bool CreateDirectoryNative(string path, ref SECURITY_ATTRIBUTES attributes);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool GetVolumePathNameW(string fileName, System.Text.StringBuilder volumePathName, uint bufferLength);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        private static extern bool GetVolumeNameForVolumeMountPointW(string volumeMountPoint, System.Text.StringBuilder volumeName, uint bufferLength);
        [DllImport("kernel32.dll")] private static extern IntPtr LocalFree(IntPtr memory);

        public static void CreateWithSddl(string path, string sddl) {
            IntPtr descriptor;
            uint size;
            if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out descriptor, out size))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not build restricted directory security descriptor.");
            try {
                SECURITY_ATTRIBUTES attributes = new SECURITY_ATTRIBUTES();
                attributes.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
                attributes.lpSecurityDescriptor = descriptor;
                attributes.bInheritHandle = false;
                if (!CreateDirectoryNative(path, ref attributes))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not create restricted evidence directory atomically.");
            }
            finally { LocalFree(descriptor); }
        }

        public static string GetSddl(string path) {
            IntPtr owner, group, dacl, sacl, descriptor;
            uint status = GetNamedSecurityInfoNative(path, 1, 0x7, out owner, out group, out dacl, out sacl, out descriptor);
            if (status != 0) throw new Win32Exception((int)status, "Could not read owner/group/DACL security descriptor.");
            try {
                IntPtr text;
                uint chars;
                if (!ConvertSecurityDescriptorToStringSecurityDescriptorW(descriptor, 1, 0x7, out text, out chars))
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not serialize security descriptor to SDDL.");
                try { return Marshal.PtrToStringUni(text); }
                finally { LocalFree(text); }
            }
            finally { LocalFree(descriptor); }
        }

        public static string GetVolumeGuidForPath(string path) {
            var volumePath = new System.Text.StringBuilder(32768);
            if (!GetVolumePathNameW(path, volumePath, (uint)volumePath.Capacity))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not resolve path to a volume mount point.");
            var volumeName = new System.Text.StringBuilder(32768);
            if (!GetVolumeNameForVolumeMountPointW(volumePath.ToString(), volumeName, (uint)volumeName.Capacity))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not resolve volume GUID.");
            return volumeName.ToString().TrimEnd('\\');
        }
    }
}
'@ -ErrorAction Stop
}

function Get-F2AclSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function ConvertFrom-F2AclHex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidatePattern('^(?:[0-9a-fA-F]{2})+$')][string]$Hex)

    $bytes = [byte[]]::new($Hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return ,$bytes
}

function Test-F2AclFixedTimeEqual {
    param([Parameter(Mandatory)][byte[]]$A, [Parameter(Mandatory)][byte[]]$B)

    if ($A.Length -ne $B.Length) { return $false }
    $difference = 0
    for ($i = 0; $i -lt $A.Length; $i++) { $difference = $difference -bor ($A[$i] -bxor $B[$i]) }
    return ($difference -eq 0)
}

function Test-F2AclHasProperties {
    param([Parameter(Mandatory)]$Object, [Parameter(Mandatory)][string[]]$Names)
    if ($null -eq $Object) { return $false }
    foreach ($name in $Names) { if ($null -eq $Object.PSObject.Properties[$name]) { return $false } }
    return $true
}

function Assert-F2AclSupportedAce {
    [CmdletBinding()]
    param([Parameter(Mandatory)][Security.AccessControl.GenericAce]$Ace)
    if ($Ace.GetType() -ne [Security.AccessControl.CommonAce]) { throw ('UnsupportedDaclAceClass:' + $Ace.GetType().FullName) }
    if ($Ace.AceType -notin @([Security.AccessControl.AceType]::AccessAllowed, [Security.AccessControl.AceType]::AccessDenied)) { throw ('UnsupportedDaclAceType:' + $Ace.AceType) }
    if (([int]$Ace.AceFlags -band (-bnot 0x1F)) -ne 0) { throw ('UnsupportedDaclAceFlags:' + [int]$Ace.AceFlags) }
    return $true
}

function ConvertTo-F2AclUtf8Bytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($Text)
    return ,$bytes
}

function ConvertTo-F2AclWindowsArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $slashes = 0
    for ($i = 0; $i -lt $Value.Length; $i++) {
        $character = $Value[$i]
        if ($character -eq '\') { $slashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($slashes * 2) + 1)))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-F2AclCanonicalPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $canonical = [IO.Path]::GetFullPath($Path)
    if ($canonical.Length -gt [IO.Path]::GetPathRoot($canonical).Length) {
        $canonical = $canonical.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $canonical
}

function ConvertTo-F2AclRecordContent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Record)

    return [ordered]@{
        Path = [string]$Record.Path
        Owner = [string]$Record.Owner
        OwnerSid = [string]$Record.OwnerSid
        Sddl = [string]$Record.Sddl
        DaclProtected = [bool]$Record.DaclProtected
        Status = [string]$Record.Status
        Error = [string]$Record.Error
        AceCount = [int]$Record.AceCount
        Aces = @($Record.Aces)
    }
}

function Get-F2AclJsonBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Value)

    $json = ConvertTo-Json -InputObject $Value -Depth 20 -Compress -ErrorAction Stop
    return ConvertTo-F2AclUtf8Bytes -Text $json
}

function Add-F2AclBoundedStreamRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][Collections.Generic.List[object]]$Records,
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Stream,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [int]$MaxBytes = 65536
    )

    $record = [ordered]@{Stream=$Stream;Message=$Message}
    $recordBytes = (Get-F2AclJsonBytes $record).Length
    if ($recordBytes -gt $MaxBytes -or [int64]$State.Bytes + $recordBytes -gt $MaxBytes) { throw 'PowerShell stream output exceeded the 64 KiB collection cap.' }
    $State.Bytes = [int]$State.Bytes + $recordBytes
    $Records.Add($record)
}

function New-F2AclEvidenceDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VmId,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [Parameter()][object]$Metadata = [ordered]@{},
        [Parameter()][string[]]$Errors = @(),
        [Parameter()][string]$CaptureId = ([guid]::NewGuid().ToString('D'))
    )

    $recordRows = @()
    foreach ($record in $Records) {
        $content = ConvertTo-F2AclRecordContent -Record $record
        $content.Path = ConvertTo-F2AclCanonicalPath -Path $content.Path
        $recordHash = Get-F2AclSha256 -Bytes (Get-F2AclJsonBytes -Value $content)
        $row = [ordered]@{}
        foreach ($key in $content.Keys) { $row[$key] = $content[$key] }
        $row.RecordSha256 = $recordHash
        $recordRows += ,$row
    }

    $canonicalExpected = @($ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
    $canonicalActual = @($recordRows | ForEach-Object { $_.Path })
    $distinct = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $canonicalActual) { [void]$distinct.Add($path) }
    $aceCount = 0
    foreach ($row in $recordRows) { $aceCount += [int]$row.AceCount }
    $orderedHashes = @($recordRows | Sort-Object { $_.Path.ToLowerInvariant() } | ForEach-Object { $_.RecordSha256 })
    $pathManifest = @($canonicalExpected | Sort-Object { $_.ToLowerInvariant() }) -join "`n"
    $recordsManifest = $orderedHashes -join "`n"
    $manifest = [ordered]@{
        ExpectedCount = $canonicalExpected.Count
        ExpectedPaths = @($canonicalExpected | Sort-Object { $_.ToLowerInvariant() })
        RecordCount = $recordRows.Count
        UniquePathCount = $distinct.Count
        AceCount = $aceCount
        ErrorCount = @($Errors).Count
        ExpectedPathsSha256 = Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $pathManifest)
        RecordsSha256 = Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $recordsManifest)
        Errors = @($Errors)
    }
    return [ordered]@{
        Schema = $script:F2AclSchema
        CaptureId = $CaptureId
        CreatedUtc = [DateTime]::UtcNow.ToString('o')
        VmId = $VmId.ToLowerInvariant()
        VmName = $VmName
        VmState = 'Off'
        Complete = (@($Errors).Count -eq 0 -and $canonicalExpected.Count -eq 11 -and $recordRows.Count -eq 11 -and $distinct.Count -eq 11)
        Manifest = $manifest
        Metadata = $Metadata
        Records = $recordRows
    }
}

function Write-F2AclFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][byte[]]$Payload,
        [int]$MaxPayloadBytes = $script:F2AclMaxPayloadBytes
    )

    if ($Payload.Length -lt 1 -or $Payload.Length -gt $MaxPayloadBytes) { throw "Payload length $($Payload.Length) is outside the allowed range." }
    $writer = [IO.BinaryWriter]::new($Stream, [Text.Encoding]::UTF8, $true)
    try {
        $writer.Write([byte[]](0x46, 0x32, 0x41, 0x43, 0x4C, 0x01, 0x0D, 0x0A))
        $writer.Write([int]$Payload.Length)
        $writer.Write($Payload)
        $writer.Write((ConvertFrom-F2AclHex (Get-F2AclSha256 $Payload)))
        $writer.Flush()
    }
    finally { $writer.Dispose() }
}

function Read-F2AclExactBytes {
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [Parameter(Mandatory)][int]$Count,
        [Parameter(Mandatory)][DateTime]$DeadlineUtc
    )
    $bytes = [byte[]]::new($Count)
    $offset = 0
    while ($offset -lt $Count) {
        $remainingMs = [int][Math]::Floor(($DeadlineUtc - [DateTime]::UtcNow).TotalMilliseconds)
        if ($remainingMs -le 0) { throw 'FrameReadTimeout.' }
        $async = $Stream.BeginRead($bytes, $offset, $Count - $offset, $null, $null)
        try {
            if (-not $async.AsyncWaitHandle.WaitOne($remainingMs)) {
                try { $Stream.Dispose() } catch { }
                throw 'FrameReadTimeout.'
            }
            $read = $Stream.EndRead($async)
        }
        finally { $async.AsyncWaitHandle.Dispose() }
        if ($read -le 0) { throw 'Frame ended before the declared length.' }
        $offset += $read
    }
    return ,$bytes
}

function Read-F2AclFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [int]$MaxPayloadBytes = $script:F2AclMaxPayloadBytes,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 300
    )

    $reader = [IO.BinaryReader]::new($Stream, [Text.Encoding]::UTF8, $true)
    $deadlineUtc = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    try {
        $magic = Read-F2AclExactBytes $Stream 8 $deadlineUtc
        if ([BitConverter]::ToString($magic) -ne '46-32-41-43-4C-01-0D-0A') { throw 'Frame magic/version is invalid.' }
        $lengthBytes = Read-F2AclExactBytes $Stream 4 $deadlineUtc
        $length = [BitConverter]::ToInt32($lengthBytes, 0)
        if ($length -lt 1 -or $length -gt $MaxPayloadBytes) { throw "Frame payload length $length is outside the allowed range." }
        $payload = Read-F2AclExactBytes $Stream $length $deadlineUtc
        $digest = Read-F2AclExactBytes $Stream 32 $deadlineUtc
        $eofBuffer = [byte[]]::new(1)
        $remainingMs = [int][Math]::Floor(($deadlineUtc - [DateTime]::UtcNow).TotalMilliseconds)
        if ($remainingMs -le 0) { throw 'FrameReadTimeout.' }
        $eofRead = $Stream.BeginRead($eofBuffer, 0, 1, $null, $null)
        try {
            if (-not $eofRead.AsyncWaitHandle.WaitOne($remainingMs)) { try { $Stream.Dispose() } catch { }; throw 'FrameReadTimeout.' }
            $trailingCount = $Stream.EndRead($eofRead)
        }
        finally { $eofRead.AsyncWaitHandle.Dispose() }
        if ($trailingCount -ne 0) { throw 'Frame has trailing bytes.' }
        $actual = ConvertFrom-F2AclHex (Get-F2AclSha256 $payload)
        if (-not (Test-F2AclFixedTimeEqual $actual $digest)) { throw 'Frame SHA-256 does not match.' }
        return [pscustomobject]@{ Payload = $payload; PayloadSha256 = Get-F2AclSha256 $payload; PayloadLength = $length }
    }
    finally { $reader.Dispose() }
}

function Wait-F2AclProcessExit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Diagnostics.Process]$Process,
        [Parameter(Mandatory)][ValidateRange(1, 3600)][int]$TimeoutSeconds,
        [ValidateRange(10, 5000)][int]$PollMilliseconds = 100
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    while (-not $Process.HasExited -and $timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    $timedOut = -not $Process.HasExited
    if ($timedOut) {
        $Process.Kill()
        $Process.WaitForExit()
    }
    return [pscustomobject]@{Completed=(-not $timedOut);TimedOut=$timedOut;ExitCode=[int]$Process.ExitCode;ElapsedMilliseconds=[long]$timer.ElapsedMilliseconds}
}

function Test-F2AclNoReparseAncestors {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($current)
    while ($true) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "EvidencePathReparseAncestor:$current" }
        }
        if ([string]::Equals($current.TrimEnd('\'), $root.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent) { throw 'EvidencePathParentWalkFailed.' }
        $current = $parent.FullName
    }
}

function Test-F2AclEvidenceVolumeSeparateFromG {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    Test-F2AclNoReparseAncestors -Path $Path
    $evidenceVolume = [F2Acl.NativeDirectory]::GetVolumeGuidForPath($Path)
    $projectVolume = [F2Acl.NativeDirectory]::GetVolumeGuidForPath('G:\')
    if ([string]::IsNullOrWhiteSpace($evidenceVolume) -or [string]::IsNullOrWhiteSpace($projectVolume)) { throw 'EvidenceVolumeIdentityUnknown.' }
    if ([string]::Equals($evidenceVolume, $projectVolume, [StringComparison]::OrdinalIgnoreCase)) { throw 'EvidenceMustBeStoredOnVolumeSeparateFromG.' }
    return [pscustomobject]@{EvidenceVolumeGuid=$evidenceVolume;ProjectVolumeGuid=$projectVolume;Separate=$true}
}

function New-F2AclRestrictedDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OwnerSid)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $fullPath) { throw 'Restricted directory already exists; refusing overwrite.' }
    $parentPath = [IO.Directory]::GetParent($fullPath).FullName
    Test-F2AclEvidenceVolumeSeparateFromG -Path $parentPath | Out-Null
    $parentSddl = [F2Acl.NativeDirectory]::GetSddl($parentPath)
    $parentRaw = [Security.AccessControl.RawSecurityDescriptor]::new($parentSddl)
    if ($null -eq $parentRaw.DiscretionaryAcl -or ($parentRaw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclPresent) -eq 0) { throw 'Restricted evidence parent has a missing or null DACL.' }
    $parentRules = @($parentRaw.DiscretionaryAcl | ForEach-Object {
        [pscustomobject]@{IdentityReference=$_.SecurityIdentifier;AccessControlType=if ($_.AceQualifier -eq [Security.AccessControl.AceQualifier]::AccessAllowed) { 'Allow' } else { 'Deny' };FileSystemRights=[Security.AccessControl.FileSystemRights]$_.AccessMask}
    })
    $unexpectedWriters = @(Get-F2AclUnexpectedWritableSids -Rules $parentRules -OwnerSid $OwnerSid)
    if ($unexpectedWriters.Count -gt 0) { throw ('Restricted evidence parent grants write-capable access to an unexpected SID: ' + ($unexpectedWriters -join ',')) }
    $sddl = 'O:' + $OwnerSid + 'D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;' + $OwnerSid + ')'
    try {
        [F2Acl.NativeDirectory]::CreateWithSddl($fullPath, $sddl)
        [void](Test-F2AclRestrictedDirectory -Path $fullPath -OwnerSid $OwnerSid)
        return $fullPath
    }
    catch {
        try {
            $children = @(Get-ChildItem -LiteralPath $fullPath -Force -ErrorAction Stop)
            $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            if ($children.Count -eq 0 -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { Remove-Item -LiteralPath $fullPath -Force -ErrorAction Stop }
        }
        catch { }
        throw
    }
}

function Test-F2AclRestrictedDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$OwnerSid)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Evidence directory is a reparse point.' }
    $raw = [Security.AccessControl.RawSecurityDescriptor]::new([F2Acl.NativeDirectory]::GetSddl($Path))
    if (($raw.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or $raw.Owner.Value -ne $OwnerSid) { throw 'Evidence directory owner or protected-DACL check failed.' }
    $allowed = @('S-1-5-18', 'S-1-5-32-544', $OwnerSid)
    $rules = @($raw.DiscretionaryAcl)
    if ($rules.Count -ne 3) { throw 'Evidence directory ACL has an unexpected ACE count.' }
    $actualSids = @()
    foreach ($rule in $rules) {
        $sid = $rule.SecurityIdentifier.Value
        $actualSids += $sid
        $expectedFlags = [int][Security.AccessControl.AceFlags]::ObjectInherit -bor [int][Security.AccessControl.AceFlags]::ContainerInherit
        if ($sid -notin $allowed -or $rule.AceQualifier -ne [Security.AccessControl.AceQualifier]::AccessAllowed -or $rule.AccessMask -ne [int][Security.AccessControl.FileSystemRights]::FullControl -or [int]$rule.AceFlags -ne $expectedFlags) { throw 'Evidence directory ACL contains an unexpected ACE.' }
    }
    $uniqueSids = @($actualSids | Sort-Object -Unique)
    $missingSids = @($allowed | Where-Object { $_ -notin $uniqueSids })
    if ($uniqueSids.Count -ne 3 -or $missingSids.Count -ne 0) { throw 'Evidence directory ACL is missing an expected unique principal.' }
    return [pscustomobject]@{Path=$item.FullName;OwnerSid=$OwnerSid;Protected=$true;AceCount=$rules.Count;AllowedSids=$allowed;Sddl=$raw.GetSddlForm([Security.AccessControl.AccessControlSections]::All)}
}

function Get-F2AclUnexpectedWritableSids {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Rules, [Parameter(Mandatory)][string]$OwnerSid)

    # Specific write/delete/ownership bits, including WRITE_ATTRIBUTES,
    # plus GENERIC_WRITE and GENERIC_ALL. ReadAndExecute does not overlap these.
    $writeBits = [long]0x000D0156 -bor [long]0x10000000 -bor [long]0x40000000
    $trustedWriteSids = @('S-1-5-18', 'S-1-5-32-544', $OwnerSid)
    $unexpected = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rule in $Rules) {
        if ($rule.AccessControlType -ne 'Allow') { continue }
        try { $sidText = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { throw ('Restricted evidence parent has an unresolvable ACE: ' + [string]$rule.IdentityReference) }
        $mask = [long]([int64]$rule.FileSystemRights -band 0xFFFFFFFFL)
        if (($mask -band $writeBits) -ne 0 -and $sidText -notin $trustedWriteSids) { [void]$unexpected.Add($sidText) }
    }
    return @($unexpected)
}

function Test-F2AclEvidenceDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Payload,
        [Parameter(Mandatory)][string]$PayloadSha256,
        [Parameter(Mandatory)][int]$ChildExitCode,
        [Parameter(Mandatory)][string]$ExpectedVmId,
        [Parameter(Mandatory)][string]$ExpectedVmName,
        [Parameter(Mandatory)][string]$ExpectedDiskSerial,
        [Parameter(Mandatory)][string]$ExpectedDiskModel,
        [Parameter(Mandatory)][string[]]$ExpectedPaths,
        [int]$MaxPayloadBytes = $script:F2AclMaxPayloadBytes
    )

    $errors = [Collections.Generic.List[string]]::new()
    if ($Payload.Length -lt 1 -or $Payload.Length -gt $MaxPayloadBytes) { $errors.Add('PayloadLengthInvalid') }
    if ((Get-F2AclSha256 $Payload) -cne $PayloadSha256) { $errors.Add('PayloadSha256Mismatch') }
    if ($errors.Count) { return [pscustomobject]@{ Pass = $false; Errors = @($errors); Document = $null } }

    try { $doc = [Text.Encoding]::UTF8.GetString($Payload) | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ Pass = $false; Errors = @('MalformedJson: ' + $_.Exception.Message); Document = $null } }

    if ($ChildExitCode -ne 0) { $errors.Add("ChildExitCode=$ChildExitCode") }
    $requiredTop = @('Schema','CaptureId','CreatedUtc','VmId','VmName','VmState','Complete','Manifest','Metadata','Records')
    if (-not (Test-F2AclHasProperties $doc $requiredTop)) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('RequiredTopLevelFieldMissing'); Document=$doc } }
    $requiredManifest = @('ExpectedCount','ExpectedPaths','RecordCount','UniquePathCount','AceCount','ErrorCount','ExpectedPathsSha256','RecordsSha256','Errors')
    if (-not (Test-F2AclHasProperties $doc.Manifest $requiredManifest)) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('RequiredManifestFieldMissing'); Document=$doc } }
    if (-not (Test-F2AclHasProperties $doc.Metadata @('Gates','Disk'))) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('RequiredMetadataFieldMissing'); Document=$doc } }
    if (-not (Test-F2AclHasProperties $doc.Metadata.Disk @('SerialMatched','Serial','Model','DriveLetter','FileSystem','BusType','Health','PhysicalHealth','VolumeHealth','DiskNumber','Win32Index','PartitionDisk'))) { return [pscustomobject]@{ Pass=$false; Errors=@($errors)+@('StorageIdentityFieldsMissing'); Document=$doc } }
    if ($doc.Schema -ne $script:F2AclSchema) { $errors.Add('SchemaMismatch') }
    if ($doc.VmId -ne $ExpectedVmId.ToLowerInvariant() -or $doc.VmName -ne $ExpectedVmName -or $doc.VmState -ne 'Off') { $errors.Add('VmIdentityOrStateMismatch') }
    if ($doc.Complete -ne $true) { $errors.Add('DocumentIncomplete') }
    if (@($doc.Manifest.Errors).Count -ne 0 -or $doc.Manifest.ErrorCount -ne 0) { $errors.Add('CollectionErrorsPresent') }
    if ($null -eq $doc.Metadata -or @($doc.Metadata.Gates).Count -eq 0) { $errors.Add('PreflightGatesMissing') }
    else {
        foreach ($gate in @($doc.Metadata.Gates)) {
            if (-not (Test-F2AclHasProperties $gate @('Name','Pass','Detail'))) { $errors.Add('PreflightGateRecordIncomplete') }
            elseif ($gate.Pass -ne $true) { $errors.Add('PreflightGateFailed: ' + [string]$gate.Name) }
        }
    }
    if ($doc.Metadata.Disk.SerialMatched -ne $true -or $doc.Metadata.Disk.Serial -ne $ExpectedDiskSerial -or $doc.Metadata.Disk.Model -ne $ExpectedDiskModel -or $doc.Metadata.Disk.DriveLetter -ne 'G:' -or $doc.Metadata.Disk.FileSystem -ne 'NTFS' -or $doc.Metadata.Disk.BusType -ne 'USB' -or $doc.Metadata.Disk.Health -ne 'Healthy' -or $doc.Metadata.Disk.PhysicalHealth -ne 'Healthy' -or $doc.Metadata.Disk.VolumeHealth -ne 'Healthy' -or $doc.Metadata.Disk.DiskNumber -ne $doc.Metadata.Disk.Win32Index -or $doc.Metadata.Disk.PartitionDisk -ne $doc.Metadata.Disk.DiskNumber) { $errors.Add('StorageIdentityIncomplete') }

    $expected = @($ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath $_ })
    $actualRows = @($doc.Records)
    $actual = @($actualRows | ForEach-Object { ConvertTo-F2AclCanonicalPath ([string]$_.Path) })
    $expectedSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $actualSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $expected) { [void]$expectedSet.Add($path) }
    foreach ($path in $actual) { [void]$actualSet.Add($path) }
    if ($expected.Count -ne 11 -or $expectedSet.Count -ne 11) { $errors.Add('ExpectedPathSetInvalid') }
    $manifestPaths = @($doc.Manifest.ExpectedPaths | ForEach-Object { ConvertTo-F2AclCanonicalPath ([string]$_) })
    $manifestSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $manifestPaths) { [void]$manifestSet.Add($path) }
    if ($manifestPaths.Count -ne 11 -or $manifestSet.Count -ne 11 -or $manifestSet.Count -ne $expectedSet.Count) { $errors.Add('ManifestPathSetInvalid') }
    foreach ($path in $expectedSet) { if (-not $manifestSet.Contains($path)) { $errors.Add('ManifestPathMissing: ' + $path) } }
    if ($actualRows.Count -ne 11 -or $actualSet.Count -ne 11) { $errors.Add('RecordCountOrDuplicatePath') }
    if ($expectedSet.Count -ne $actualSet.Count) { $errors.Add('PathSetCountMismatch') }
    foreach ($path in $expectedSet) { if (-not $actualSet.Contains($path)) { $errors.Add('MissingPath: ' + $path) } }
    foreach ($path in $actualSet) { if (-not $expectedSet.Contains($path)) { $errors.Add('UnexpectedPath: ' + $path) } }
    if ($doc.Manifest.ExpectedCount -ne 11 -or $doc.Manifest.RecordCount -ne 11 -or $doc.Manifest.UniquePathCount -ne 11) { $errors.Add('ManifestCountMismatch') }

    $aceCount = 0
    foreach ($row in $actualRows) {
        if (-not (Test-F2AclHasProperties $row @('Path','Owner','OwnerSid','Sddl','DaclProtected','Status','Error','AceCount','Aces','RecordSha256'))) {
            $errors.Add('RequiredRecordFieldMissing')
            continue
        }
        if ($row.Status -ne 'PASS' -or [string]::IsNullOrWhiteSpace([string]$row.Owner) -or [string]::IsNullOrWhiteSpace([string]$row.OwnerSid) -or [string]::IsNullOrWhiteSpace([string]$row.Sddl) -or $null -eq $row.DaclProtected -or $row.Error) {
            $errors.Add('RecordIncomplete: ' + [string]$row.Path)
        }
        $aces = @($row.Aces)
        if ([int]$row.AceCount -ne $aces.Count) { $errors.Add('AceCountMismatch: ' + [string]$row.Path) }
        $aceCount += $aces.Count
        foreach ($ace in $aces) {
            if (-not (Test-F2AclHasProperties $ace @('Principal','Sid','Type','Rights','AccessMask','InheritanceFlags','PropagationFlags','Inherited'))) {
                $errors.Add('RequiredAceFieldMissing: ' + [string]$row.Path)
                continue
            }
            if ([string]::IsNullOrWhiteSpace([string]$ace.Sid) -or [string]::IsNullOrWhiteSpace([string]$ace.Type) -or [string]::IsNullOrWhiteSpace([string]$ace.Rights) -or $null -eq $ace.AccessMask -or $null -eq $ace.InheritanceFlags -or $null -eq $ace.PropagationFlags -or $null -eq $ace.Inherited) {
                $errors.Add('AceIncomplete: ' + [string]$row.Path)
            }
        }
        try {
            $content = [ordered]@{
                Path = [string]$row.Path; Owner = [string]$row.Owner; OwnerSid = [string]$row.OwnerSid; Sddl = [string]$row.Sddl
                DaclProtected = [bool]$row.DaclProtected; Status = [string]$row.Status; Error = [string]$row.Error
                AceCount = [int]$row.AceCount; Aces = @($row.Aces)
            }
            $recordHash = Get-F2AclSha256 (Get-F2AclJsonBytes $content)
            if ($recordHash -cne [string]$row.RecordSha256) { $errors.Add('RecordSha256Mismatch: ' + [string]$row.Path) }
        }
        catch { $errors.Add('RecordHashError: ' + [string]$row.Path) }
    }
    if ($doc.Manifest.AceCount -ne $aceCount) { $errors.Add('ManifestAceCountMismatch') }
    if (@($doc.Manifest.ExpectedPathsSha256).Count -ne 1 -or @($doc.Manifest.RecordsSha256).Count -ne 1) { $errors.Add('ManifestDigestMissing') }
    else {
        $pathManifest = @($expected | Sort-Object { $_.ToLowerInvariant() }) -join "`n"
        $recordsManifest = @($actualRows | Sort-Object { ([string]$_.Path).ToLowerInvariant() } | ForEach-Object { [string]$_.RecordSha256 }) -join "`n"
        if ((Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $pathManifest)) -cne [string]$doc.Manifest.ExpectedPathsSha256) { $errors.Add('ExpectedPathsSha256Mismatch') }
        if ((Get-F2AclSha256 (ConvertTo-F2AclUtf8Bytes $recordsManifest)) -cne [string]$doc.Manifest.RecordsSha256) { $errors.Add('RecordsSha256Mismatch') }
    }
    return [pscustomobject]@{ Pass = ($errors.Count -eq 0); Errors = @($errors); Document = $doc }
}

Export-ModuleMember -Function Get-F2AclSha256, ConvertTo-F2AclUtf8Bytes, ConvertTo-F2AclWindowsArgument, ConvertTo-F2AclCanonicalPath, Assert-F2AclSupportedAce, New-F2AclEvidenceDocument, Write-F2AclFrame, Read-F2AclFrame, Wait-F2AclProcessExit, New-F2AclRestrictedDirectory, Test-F2AclRestrictedDirectory, Test-F2AclNoReparseAncestors, Test-F2AclEvidenceVolumeSeparateFromG, Get-F2AclUnexpectedWritableSids, Add-F2AclBoundedStreamRecord, Test-F2AclEvidenceDocument

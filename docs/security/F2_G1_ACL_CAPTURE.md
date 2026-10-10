# F2 G1 ACL evidence capture

## Scope

This tool captures a read-only ACL baseline for VM `F2-G1-Isolated-Disposable` (`6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1`) and the 11 previously identified objects under `G:\F2-G1-Isolated-Disposable`. It does not change ACLs, VM settings, files on G:, registry values, switches, or disks. It never starts a VM.

The elevated child requires the exact VM ID, name, and `Off` state; identifies the Kingston device by serial `152D20337A0C` uniquely across `Win32_DiskDrive`, `Get-Disk`, and `Get-PhysicalDisk`; validates model, USB bus, health, G: partition mapping, and NTFS; verifies configured VM paths; and rejects missing paths, aliases, and reparse points. Model validation uses all three raw model fields: the anchored Win32 form accepts only the exact Kingston model with an optional terminal `USB Device` suffix after whitespace collapse; `Get-Disk.FriendlyName` must canonicalize to `KINGSTON SA400S37240G`; and `Get-Disk.Model` must canonicalize to `SA400S37240G`. Raw and normalized forms are retained in the evidence. Any failed gate prevents ACL reads. For each of the exact 11 canonical paths, it rechecks the no-reparse path chain immediately before reading the owner/group/DACL SDDL through Windows security APIs. SACLs are not requested. The SDDL parser records each supported allow/deny ACE, mask and inheritance flags; an unsupported ACE type fails that object closed.

After the 11 ACL reads, the collector re-queries the same VM ID and verifies its name and `Off` state, rechecks the exact configuration/checkpoint/smart-paging/VHDX paths and zero NIC count, repeats the serial/model/USB/health/G: mapping checks, and rechecks all 11 paths for reparse points. `Complete` is false unless the final observed VM state is `Off` and every post-collection gate passes. The document records the final observed state rather than assigning `Off` unconditionally.

## Captured evidence

Each object record contains canonical path, owner and owner SID, raw SDDL, DACL protection, PASS/FAIL and error, ACE count, and every ACE's principal, SID, allow/deny type, rights, access mask, inheritance and propagation flags, and inherited status. The document includes the exact expected path list, record/ACE/error counts, preflight gates, disk identity summary, per-record SHA-256 values, a records manifest digest, and a SHA-256 digest over the exact UTF-8 payload bytes.

The pipe protocol is bounded to 256 KiB and uses a versioned magic header, a little-endian length, exact payload bytes, and a 32-byte SHA-256 digest. A single deadline bounds the entire frame read, including the final EOF check; a child that keeps the pipe open after a complete frame is rejected on timeout. Timeout closes the dedicated pipe stream to cancel the pending asynchronous read. The parent rejects short, oversized, trailing, corrupted, malformed, duplicate, incomplete, mismatched, or nonzero-exit results. The host process exit code is read from the process handle and checked separately from the structured payload status. A timeout terminates only the capture child process launched by this tool; it never terminates Hyper-V or another host process.

Only a complete validated payload is saved. Before elevation, the parent requires a clean worktree at the caller-supplied reviewed commit and verifies launcher/module hashes against the committed `F2_ACL_SOURCE_PINS.json`. It opens all three files with read-only, write-denying handles and retains them until the child exits. The elevated child verifies both executable source hashes before importing the protocol module or collecting host data. The evidence path is checked from its existing ancestors through the volume root for reparse points; Win32 volume GUIDs must prove the evidence volume differs from G:. Evidence is written into a new LocalAppData directory created atomically with a protected DACL granting Full Control only to SYSTEM, BUILTIN\Administrators, and the current user. It verifies the exact three distinct ACEs and owner. Payload and integrity files are written to new temporary names, hash-checked, then atomically renamed, with the integrity document published last as the completion marker. Existing paths are never overwritten.

The ACL reader intentionally supports only ordinary `CommonAce` allow/deny entries with inheritance flags. It fails the object closed if it encounters object ACEs, callback/conditional ACEs, audit ACEs, unknown ACE classes, or unsupported flag bits, because omitting object GUID or callback semantics would make the evidence incomplete.

## Synthetic validation

Run from Windows PowerShell 5.1:

```powershell
.\scripts\f2-acl\Test-F2AclCapture.Protocol.ps1
```

The Windows PowerShell 5.1 source-only harness covers the observed USB bridge model values, wrong serial/model, ambiguous matches, unavailable fields, non-USB transport, wrong G: mapping, post-collection VM identity/state/path/NIC changes, complete records, argument quoting, framing, oversize rejection, corrupted and partial frames, a stalled live pipe after a partial header or a complete frame, missing/duplicate paths, malformed JSON, missing envelope and ACL fields, nonzero child status, hash mismatch, partial ACL records, child stdout/stderr/exit-code capture, timeout behavior, standard ACE acceptance, callback/object/unsupported-flag ACE rejection, ancestor-junction rejection, atomic restricted-directory creation and exact DACL principals. It uses synthetic ACL fixtures and harmless local PowerShell child processes. It does not query the live VM.

## Approved live capture procedure

After the owner explicitly authorizes one bounded read-only capture phase for the exact independently reviewed commit, run with that full 40-character SHA:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\f2-acl\Invoke-F2AclReadOnlyCapture.ps1 -ExpectedCommitSha <reviewed-commit-sha>
```

The command requests UAC for the read-only child. Keep the VM OFF. The child performs the target-specific preflight and ACL reads, plus one read-only lookup of the exact capability SID in Microsoft's `AllCachedCapabilities` registry value. It stores only whether the exact SID was present, not unrelated registry value contents. No registry value is modified. If a source hash, VM identity/state, disk mapping, path, or evidence integrity check fails, no complete baseline is produced.

The parent must be allowed to finish and return its structured summary and actual child exit code. If the command runner reports a session ID, retain it and poll until the final result; an empty intermediate output is not completion. A timeout, missing pipe frame, unexpected process exit, any failed gate, incomplete record set, or integrity error yields `INCOMPLETE` and no successful baseline.

## Security analysis limits

Microsoft documents that the per-VM SID can require access to the VM's configuration and virtual disks, and identifies `S-1-5-83-0` as the Hyper-V Virtual Machines group whose membership VMMS maintains. Microsoft also documents capability SIDs as legitimate Windows security identifiers and warns against deleting capability SIDs from filesystem permissions. The exact necessity of this project's two root-level ACEs for the reported Hyper-V capability is not documented by those generic references. The live ACL can establish their scope and inheritance, but a read-only capture alone cannot prove whether Hyper-V will function without them; the VM remains OFF and no permission change or start test is in scope.

The provisioning transcript shows that the directory was initially created with protected SYSTEM and Administrators ACEs. `New-VHD`, `New-VM`, and adapter removal then ran before the later `Get-Acl`/`Set-Acl` that intentionally added the VM-specific SID. That `Set-Acl` code did not explicitly construct the capability ACEs; it read and preserved the then-current DACL. No intermediate DACL snapshots were recorded, so the command or Hyper-V component that first introduced the capability ACEs remains UNKNOWN.

## Primary references

- [Microsoft: Hyper-V VM start access denied and VM-specific SID permissions](https://learn.microsoft.com/en-us/troubleshoot/windows-server/virtualization/hyper-v-virtual-machine-not-start-0x80070005)
- [Microsoft Open Specifications: Hyper-V Virtual Machines group and VM-specific SID](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-dtyp/81d92bba-d22b-4a8c-908a-554ab29148ab)
- [Microsoft: Capability SID lookup and cautions about removing capability SIDs](https://learn.microsoft.com/en-us/troubleshoot/windows-server/windows-security/sids-not-resolve-into-friendly-names)
- [Microsoft: Capability SID constants](https://learn.microsoft.com/en-us/windows/win32/secauthz/capability-sid-constants)
- [Microsoft: AppContainer capability SID security model](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)

No ACL remediation is authorized by this tool or document. A change requires a complete live baseline, independent review, and a separate explicit owner authorization.

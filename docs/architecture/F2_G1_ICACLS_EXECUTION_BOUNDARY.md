# F2 G1 `icacls` corroboration execution boundary

**Disposition: DESIGN ONLY — READY_FOR_OWNER_ARCHITECTURE_DECISION**

**Inputs:** PR #50 exact-SHA source review `5480732393` at `b04b01fb4a276f16811ec87dab1e1110835272f3`; Issue #48 status `6101951217`; PR #49 reviewed baseline source `a62773f0553dff4a05055b18fa10834f7488ae55`.

This design adds a production execution boundary around the reviewed, non-executable corroboration library. It does not establish the live ACL state or accept the ACLs. PRs #49 and #50 remain draft and unmerged. No `icacls`, UAC, live host ACL/token query, VM operation, or G: write was performed for this design.

## Decision summary

Use the existing PR #49 protected-mailbox UAC pattern and PR #50's exact-target parser/comparator, but place a small fixed-scope launcher around them. The launcher performs all ordinary work under the signed-in standard token. It starts no elevated coordinator unless every standard run is complete and at least one exact, fully captured `icacls` invocation reports verified Access Denied. The one UAC coordinator runs only the denied subset, writes its result into an Administrator-owned mailbox, and never accepts caller-selected commands or paths.

Two conditions must be resolved before this can be implemented for live use:

1. **Reviewed-source trust anchor:** a source hash checked by code loaded from a user-writable checkout does not protect the first elevated instructions from replacement between check and execution. Install the small elevated coordinator and its fixed reviewed package in a protected, administrator-owned host location, with a separately approved release manifest pinning the final commit and component hashes. The standard launcher may remain in the checkout; it cannot supply executable elevated code.
2. **Standard-token Hyper-V visibility:** the existing record says standard-token `Get-VM` access was denied. Fresh OFF/zero-NIC preflight therefore may fail before the `icacls` runs. This architecture deliberately does not use UAC to work around that failure. If the standard token still cannot establish VM state, stop and request a separate architecture/authorization decision for that prerequisite; do not label the run ready or broaden the UAC trigger.

## Scope and immutable inputs

The production entrypoint has no public target, VM, disk, baseline, executable, or output-directory override. Test seams are available only to the test harness and are not bound by the production entrypoint. The external administrator-owned release manifest anchors the final reviewed Git commit and SHA-256 of every executable script/module. A separate protected baseline record pins the capture ID, `acl-baseline.json` digest, `integrity.json` digest, project volume GUID, and evidence volume GUID. The project and evidence volume identities remain distinct.

The fixed target is VM `F2-G1-Isolated-Disposable`, ID `6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1`, project root `G:\F2-G1-Isolated-Disposable`, Kingston serial `152D20337A0C`, exact reviewed model identity, USB transport, and G: volume. Expected object paths are generated from constants and the immutable VM ID, then compared as a canonical set of exactly 11 unique paths:

1. Project root; 2. VM configuration directory; 3. its `Virtual Machines` directory; 4. VM-ID directory; 5–7. `.vmcx`, `.vmgs`, and `.VMRS`; 8–9. OS and scratch VHDX; 10. project-root `Virtual Machines`; 11. its VM-ID directory.

Any extra, missing, duplicate, aliased, reparse-point, or out-of-root path fails before process launch. No caller-provided path is interpolated into an elevated command.

## Proposed sequence

```mermaid
sequenceDiagram
    actor Owner
    participant L as Standard-token launcher
    participant H as Read-only host observations
    participant I as 11 fixed icacls.exe calls
    participant U as One approved UAC coordinator
    participant M as Protected create-new mailbox
    participant R as Standard-token result validator

    Owner->>L: Start fixed entrypoint (no target parameters)
    L->>L: Verify protected release pins, exact commit/components, baseline hashes
    L->>H: Read VM, disk, volume, paths and reparse state
    H-->>L: Exact identity/state snapshot or fail closed
    loop each of the 11 exact paths, one process per path
        L->>I: icacls.exe <one canonical path> (read-only, no /T)
        I-->>L: bounded stdout/stderr, exit, PID, timing, drain/cleanup
    end
    alt Any result is incomplete, malformed, timeout, or non-Access-Denied failure
        L->>L: Preserve diagnostic; no UAC; INCOMPLETE
    else All complete; some exact Access Denied
        L->>Owner: Show denied object count and fixed scope; require consent
        Owner->>U: Approve the single Windows UAC prompt
        U->>U: Verify admin identity, protected source pin, request and preflight
        loop denied subset only
            U->>I: icacls.exe <one already-authorized path>
            I-->>U: bounded output, exit and cleanup status
        end
        U->>M: Create-new status/evidence and integrity manifest
        R->>M: Read bounded files; validate owner/DACL, identity and hashes
        M-->>R: Authenticated coordinator results
    else All standard calls complete without Access Denied
        L->>L: Do not launch UAC
    end
    L->>H: Repeat VM/disk/path preflight and compare snapshots
    H-->>L: Postflight or fail closed
    L->>L: Publish sanitized summary; retain raw evidence locally
```

The chart omits failure branches for readability: every failed gate stops later stages, records a bounded stage/error, and prevents a complete corroboration result.

## Workflow and trust boundaries

### 1. Standard-token entrypoint and source/baseline pins

The entrypoint accepts no target-affecting parameters. It locates a separately installed, administrator-owned release manifest by a fixed path; verifies its owner, protected DACL, non-reparse ancestry and SHA-256; and checks the exact reviewed commit plus every component digest. The manifest is provisioned only after source review gives the final SHA. This avoids a self-referential in-repository commit pin and prevents a mutable checkout from choosing the code that receives elevation. The baseline reader verifies both JSON files against fixed digests before trusting any embedded path or identity.

Test-only dependency injection is internal to test files and absent from the production command surface. The elevated coordinator independently verifies the same release/baseline pins; it does not trust an `ExpectedCommitSha`, hash, observation, command, path, or baseline digest supplied by the standard process.

### 2. Fresh preflight and race handling

Use read-only observations for (a) the exact VM GUID/name and `Off` state, (b) zero guest NICs and expected G: configuration/VHD paths, (c) unique Kingston serial across Win32/Disk/PhysicalDisk interfaces, appropriate model fields, USB bus, Healthy/Online and the G: partition/NTFS volume mapping, (d) volume GUID identities, and (e) canonical paths with no reparse points. Compare all storage observations to the same physical disk and the protected baseline. Do not infer identity from disk number.

Run this gate under the standard token before `icacls`, then immediately before/after each target process where practical, and once after the phase. A coordinator repeats it under its own token. Any changed observation makes the full result `INDETERMINATE`. This is detection, not an atomic lock: the design assumes no concurrent owner/administrator starts or reconfigures the VM during the short read-only window. A state transition that begins and ends between observations cannot be ruled out without a separate VM-management lock/change, which is outside this authorization.

**Known readiness issue:** if standard-token Hyper-V cmdlets or equivalent read-only VM metadata are denied, stop here. The single UAC coordinator is reserved for verified `icacls` Access Denied and cannot be invoked merely to obtain preflight data. Do not use cached/offline VM state as a fresh substitute.

### 3. Standard `icacls` pass

Invoke the pinned Windows `System32\icacls.exe` once per exact path. Command construction is from the fixed allowlist; it contains no `/T`, save/restore, grant, deny, reset, inheritance, or other ACL-changing switch. Preserve each target's complete bounded stdout/stderr, actual exit code, PID and creation time, monotonic elapsed/deadline status, output digest, truncation flag, drain completion, and cleanup result. Each call gets a fixed per-process output cap and deadline; the 11-call phase also has one absolute wall-clock deadline and aggregate output cap. No line-oriented asynchronous reader is used.

Only an invocation that exited normally, drained both streams completely, passed exact-path parsing, and produced the expected Windows Access Denied diagnostic and error exit is eligible for elevated retry. A timeout, missing process status, oversized output, malformed/wrong-path output, missing evidence, non-Access-Denied error, or cleanup failure ends the run with no UAC. Successful standard results are never repeated elevated.

### 4. One UAC coordinator, only after denied evidence

Once the complete standard phase is retained, present a concise consent description naming the exact fixed 11-object scope and the denied subset. If the owner declines/cancels, do not retry. At most one `Start-Process -Verb RunAs` coordinator launch is permitted. The coordinator binary/script comes from the protected installed package, not the writable checkout. It independently checks exact requester/coordinator SIDs and administrator membership using the reviewed PR #49 identity-pair policy. A distinct credentialed Administrator is accepted only if that same policy explicitly validates the identity pair; otherwise fail before worker launch.

The standard launcher writes the denied-subset request to a separate create-new directory directly under the already validated CommonApplicationData parent, outside G:. The directory has a protected DACL owned by the actual standard-token SID, granting that requester write access and SYSTEM/Administrators read access, with no inherited grants. The path is derived from the unpredictable capture ID; it is not caller-selected. The elevated coordinator opens it read-only, rejects reparse points, and checks owner, DACL, exact schema, bounded length, capture ID, hashes, source/baseline pins and canonical target membership. The requester owns this request and can change it, so it is treated as hostile input: it can never supply executable text or select a path outside the coordinator's independently derived 11-object set. The coordinator derives the requester SID from the request directory owner, validates the identity pair against its own token, and checks that each requested target has a complete standard-token Access Denied record before deriving the retry list. It reads each request file through a bounded `FileShare.None` handle, hashes the bytes it actually parses, and rechecks object identity/metadata before acting; an existing conflicting handle, replacement or change aborts.

The UAC command line carries only the capture ID and the fixed installed coordinator path. It contains no denied path, shell fragment, source-checkout path or caller-supplied hash. It independently checks exact requester/coordinator SIDs and administrator membership using the reviewed PR #49 identity-pair policy. A distinct credentialed Administrator is accepted only if that same policy explicitly validates the identity pair; otherwise fail before worker launch.

### 5. Authenticated cross-integrity return

Reuse PR #49's protected, create-new CommonApplicationData mailbox contract: unpredictable per-capture path; administrator-owned protected DACL; the existing exact four-ACE policy (SYSTEM/Admin full, OWNER RIGHTS read/execute, requester read/execute); parent-chain/no-reparse validation; no replacement/overwrite; bounded framed status/evidence; hashes and actual exit fields. Do not reuse a user-writable named pipe or relax `CurrentUserOnly`.

The low-integrity requester can read but cannot write the elevated result mailbox. It independently validates mailbox path, owner, DACL, non-reparse status, request/capture identity, coordinator SID, source/baseline pins, exact path set, command count, all per-command exits/stream digests, manifest counts and hashes. Any missing, duplicate, extra, truncated, reordered, mismatched or unverifiable record is incomplete. The mailbox and standard evidence directory are outside G: and are create-new; previous baseline and failed evidence remain unchanged. Raw SDDL/ACE records stay local and are never uploaded to GitHub. GitHub receives only source/tests, sanitized gate outcomes and hashes that do not expose raw security evidence.

### 6. Bounded process lifecycle and publication

Reuse PR #50's fixed-size stdout/stderr reads, output caps, exact invocation records, monotonic deadline and parser. Add a phase-level deadline and a Windows Job Object supervisor with kill-on-close for each `icacls.exe` child; create suspended, assign to the job, then resume so there is no unsupervised startup window. Reject job assignment failure, breakaway, lingering readers, failed stream disposal or incomplete drain. The coordinator and worker each have bounded waits; cleanup uses bounded cancellation/termination and never an unbounded `WaitForExit` or reader wait. Retain PID plus creation time to detect PID reuse. If UAC broker visibility or process-tree cleanup cannot be established, report `UNKNOWN/INCOMPLETE`, never success.

Create the final package atomically under a fresh restrictive directory outside G:. Include a completeness manifest for exactly 11 distinct objects; expected and observed command count; per-object stdout/stderr byte and digest fields; process PID/start/exit/deadline/cleanup records; standard/elevated token SIDs (sanitized in summary); pre/post snapshot digest; source/baseline pins; and a top-level integrity file. Reopen and rehash every file after publication. Any publication or postflight failure prevents `COMPLETE_ICACLS_CORROBORATION`. Completion means only that the two `icacls` views were captured and compared; it is not ACL security acceptance.

## Reuse versus new work

| Existing component | Disposition | Boundary |
|---|---|---|
| PR #49 `F2AclCapture.Protocol.psm1`: mailbox SDDL/directory/parent-chain checks, identity-pair validation, atomic create-new files, bounded file/frame handling, SHA-256, process status/diagnostics | Reuse unchanged where signatures fit | Preserve the exact reviewed four-ACE mailbox contract; do not broaden module API just for tests. Re-run its tests on the implementation SHA. |
| PR #49 collector's live Kingston/VM/path helpers | Reuse logic after refactor into a pinned read-only host adapter | They are private to an executable script today. Do not dot-source that script as a library because its entrypoint can run modes. Extract/test the observation adapter or implement an equivalent fixed-scope module and pin it. |
| PR #50 `F2AclIcacls.Corroboration.psm1`: baseline reader, expected-path builder, source-pin validator, exact command builder, native output parser, comparison, access-denied classifier, evidence writer | Reuse parser/comparator and fixed-size single-process capture unchanged if integration contracts remain satisfied | Production must not expose the module's `ProjectRoot`, `VmId`, resolver, observation or coordinator injection seams. A closed launcher supplies fixed constants only. |
| PR #49 `Invoke-F2AclReadOnlyCapture.ps1` UAC and mailbox flow | Reuse mailbox and identity protocol; do not invoke it as the new elevated worker | It captures ACLs and has its own public modes. New protected coordinator must be dedicated to `icacls`, independently pinned, and execute only the denied allowlist subset. |
| PR #50 injected coordinator callback tests | Reuse policy expectation only | Callback tests are not IPC/UAC evidence. Replace with real PS 5.1 process-boundary tests against a synthetic protected mailbox and separately label them simulation. |

**New minimum components:** (1) protected release-pin manifest provisioned after final review; (2) closed production entrypoint with no target overrides; (3) read-only host-observation adapter plus before/after gates; (4) administrator-owned dedicated `icacls` coordinator executable/package; (5) bounded request/result schema and standard-to-admin request validation; (6) Job Object process supervisor and phase deadline; (7) integration test harness using fake `icacls` executables and synthetic mailbox/identity records. No new external dependency or vendor binary is needed.

## Threat analysis and trust assumptions

| Threat | Control | Residual / fail-closed result |
|---|---|---|
| Modified source or baseline | Protected external release pin; exact commit, per-file SHA and baseline payload/integrity SHA; coordinator re-verifies independently | Pin-store provisioning and trust root require owner/admin approval; any mismatch stops. |
| Caller changes VM, path, command or scope | No production override; constants and exactly 11 path set independently rederived on both sides | Test-only injection remains excluded from production package and pinned release. |
| Low-to-high request spoof/replay | Capture GUID, strict bounded schema, requester/coordinator identity checks, create-new mailbox, hashes and one-use state | Same-account standard user can fabricate its own request; elevated side treats it as untrusted data and ignores requested commands/paths. |
| Mailbox substitution or symlink/junction race | Admin owner/protected four ACE DACL, no-reparse ancestry, create-new, canonical path and post-read checks | Parent storage integrity is assumed per PR #49 validator; any drift fails closed. |
| Hang, inherited writer, noisy output, PID reuse | Fixed chunk readers, caps, absolute deadlines, process start identity, Job Object kill-on-close, bounded cleanup | If job APIs/cleanup cannot be verified, result is incomplete and no retry. |
| VM/storage changes during read | Strict preflight, checks around each invocation, coordinator recheck and postflight | No atomic VM lock; requires no concurrent VM administrator activity. Any observed drift is indeterminate. |
| Credentialed UAC selects another account | Verify both SIDs and admin role using PR #49 identity-pair rule; reject unexpected account | UAC UI cannot prove the person approved the command contents; protected, closed coordinator is the trust anchor. |
| Parser or OS output variation | Bind first-line target, preserve raw streams, known mappings only, exact counts; unknown ACE semantics remain INDETERMINATE | `icacls` is not a complete SDDL/owner/effective-access oracle. It cannot prove owner, DACL protection, effective token rights or capability necessity. |
| Evidence disclosure/tampering | Local protected storage outside G:, hashes, create-new publication; sanitize GitHub | Hashes prove internal consistency, not non-repudiation. Local administrator remains trusted. |

The threat model excludes a malicious local Administrator, compromised Windows kernel/VMMS, or a hostile owner with authority to approve arbitrary elevation. It assumes the approved release-pin store and Windows system `icacls.exe` are authentic, and that the project/evidence volumes are not concurrently swapped. These assumptions must be visible in the final report.

## Acceptance matrix for a future implementation

| Gate | Required evidence | Failure outcome |
|---|---|---|
| Reviewed package | Exact reviewed commit, every component SHA and baseline/integrity digest match protected pins | STOP: `SOURCE_OR_BASELINE_PIN_MISMATCH` |
| Fixed scope | Exactly 11 unique canonical authorized paths; exact VM GUID/name, serial/model, G: volume GUID and expected mapping | STOP: `SCOPE_OR_IDENTITY_MISMATCH` |
| Fresh preflight | VM OFF, zero NICs, expected paths, Kingston healthy/online USB mapping, no reparse points, all observations refer to same storage | STOP: `PREFLIGHT_FAILED`; no UAC fallback |
| Standard pass | Eleven distinct complete native calls with exact path binding, actual exit and drained bounded streams | UAC gate only if exact Access Denied; otherwise stop or standard-complete |
| UAC policy | One human-consented launch, protected approved coordinator, expected identity pair, denied subset only | STOP: `UAC_CANCELLED`, `IDENTITY_MISMATCH`, `SECOND_LAUNCH_BLOCKED` |
| Result transfer | Four-ACE mailbox verified, bounded frame/files, exact capture/identity/source/path/count/hash match | STOP: `MAILBOX_OR_INTEGRITY_FAILURE` |
| Process lifecycle | Overall/per-call monotonic deadlines; no live child/readers; actual exits; cleanup success | STOP: `PROCESS_INCOMPLETE` |
| Postflight/publication | Pre/post identities agree; exactly 11 complete records; local package rehashes; sanitized summary | STOP: `POSTFLIGHT_OR_PUBLICATION_FAILURE` |
| Comparison | Per-object `PASS`, `MISMATCH`, or `INDETERMINATE`; generic rights conservative | Report result only; never infer `PASS_RESTRICTIVE_ACL` |

## Synthetic validation plan

Before any live execution, use Windows PowerShell 5.1 CI and source-only local tests. Use a fake executable named `icacls.exe` in an isolated test directory, selected only by an internal test seam, with no production path to that seam. Cover 11-object happy path; standard success; exact Access Denied followed by exactly one elevated coordinator simulation; UAC cancel; separate Administrator identity accepted/rejected; wrong source/baseline hash; wrong target and prefix collision; malformed/duplicate/missing/extra records; empty/large/one-line output; stdout/stderr pipe held open after child exit; hung noisy child; process/job assignment/reader/disposal failure; PID reuse; mailbox ACL/owner/reparse/collision/tampering; source replacement race; VM ON/NIC/storage/reparse drift before, during and after; output truncation; duplicate coordinator result; and create-new/publication/hash failure. Test child exit values and stage records across actual `.ps1`/`.psm1` boundaries. Report these as simulated identity/process tests, not actual UAC, live host permissions, or effective token verification.

## Implementation phases and owner gates

1. **Owner architecture decision (now):** approve or reject the protected release-pin trust anchor and dedicated coordinator package; decide how to proceed if standard-token Hyper-V preflight remains denied. No host action.
2. **Source-only implementation:** add the closed launcher, read-only adapter, coordinator, request/result schema and supervisor; add PS 5.1 hostile integration tests. No UAC or live target calls.
3. **Independent exact-SHA review and Windows CI:** review the trust root, command allowlist, mailbox, deadlines and all fail-closed branches. Any source edit resets this gate.
4. **Separate infrastructure authorization:** owner approves installing the protected coordinator/release manifest on C: (specific path/ACL/write scope) if needed. No G: writes. This is distinct from collection authorization.
5. **Fresh live collection authorization:** owner approves one bounded read-only phase and at most one UAC launch under the reviewed exact SHA. Standard-token preflight must already pass; if it cannot, stop for a new owner decision rather than using elevated fallback for preflight.
6. **Independent evidence review:** inspect raw protected evidence locally, sanitized comparison, and missing `icacls` corroboration. ACL remediation, if recommended, requires a new design/review and separate explicit authorization.

## Recommended minimal implementation

Keep PR #50's parser, comparison and bounded capture core. Add a closed entrypoint and a dedicated, administrator-owned coordinator package whose release pin is outside the mutable checkout. Extract only the existing PR #49 observation/mailbox logic needed for the fixed G1 identity; do not broaden the protocol module API unnecessarily. First prove the complete launcher/coordinator path with synthetic Windows PowerShell 5.1 processes and mailbox fixtures in CI. Keep a live run blocked until both the protected bootstrap trust anchor and a standard-token fresh VM preflight are demonstrably available.

**Current outcome:** source-library review is PASS at the stated SHA; production `icacls` execution remains NOT_READY. This document is a design proposal for owner and independent review, not implementation approval or live collection authorization.

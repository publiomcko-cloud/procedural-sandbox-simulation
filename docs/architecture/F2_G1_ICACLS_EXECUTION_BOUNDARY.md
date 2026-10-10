# F2 G1 `icacls` corroboration execution boundary

**Disposition: SOURCE-ONLY IMPLEMENTATION — READY_FOR_INDEPENDENT_REVIEW**

**Inputs:** PR #50 review `5480732393` at `b04b01fb4a276f16811ec87dab1e1110835272f3`; Issue #48 status `6101951217`; owner approval `6102054991`; PR #49 reviewed baseline source `a62773f0553dff4a05055b18fa10834f7488ae55`.

This document describes a source-only workflow. It does not establish live ACL state or accept ACLs. PR #50 remains draft and unmerged. No UAC, actual `icacls`, live host ACL/token query, VM operation, G: write, or native workload was run for this implementation.

## Approved minimum workflow

Standard-token launcher pins its source and baseline, creates one bounded request, and starts the fixed installed coordinator through one human-consented UAC prompt. The protected coordinator performs the required read-only Hyper-V/storage preflight before its first ACL read, then runs exactly eleven individually bounded `icacls` invocations. It does not retry with a second token or accept caller-selected target paths. This follows owner approval to avoid an unnecessary standard-token pass when Hyper-V metadata is denied.

```mermaid
sequenceDiagram
    actor Owner
    participant L as Closed standard-token launcher
    participant U as One protected UAC coordinator
    participant H as Fixed read-only host preflight
    participant I as System32 icacls.exe
    participant M as Protected mailbox outside G:
    participant R as Standard-token result validator
    Owner->>L: Start fixed launcher, no arguments
    L->>L: Verify external pins and baseline; create one-use request
    L->>Owner: Windows UAC consent
    Owner->>U: Approve once or cancel
    U->>U: Verify installed package, token and request identity
    U->>H: Check VM OFF/zero NICs, Kingston/G:, paths and reparse state
    H-->>U: Exact scope or fail closed
    loop Exactly 11 fixed targets
        U->>I: One bounded, read-only command; no /T
        I-->>U: Exit, bounded streams, hashes and cleanup state
    end
    U->>H: Repeat preflight after reads
    U->>M: Create-new evidence, status and integrity manifest
    R->>M: Verify identity, exact paths/counts, hashes and exits
    M-->>R: Sanitized object comparisons; raw evidence stays local
```

Any cancellation, identity/scope ambiguity, preflight failure, source-pin mismatch, incomplete process output, timeout, cleanup failure, publication failure, or postflight drift prevents a complete result. Completion means only that the read-only views were captured and compared; it is not ACL security acceptance.

## Fixed scope and trust boundaries

The launcher takes no target-affecting arguments. The protected package is installed under `Program Files\F2-G1-Icacls`; its separately stored release manifest is under `ProgramData\F2-G1-Icacls\approved-release.json`. Both roots and the manifest DACL are checked against exact administrator-owned, protected ACL profiles. The release manifest pins the final reviewed commit, the baseline payload/integrity digests, the source-pin manifest, and each executable package file. The installed coordinator rechecks the package before using the request.

The fixed identity is VM `F2-G1-Isolated-Disposable`, ID `6f8d61ce-7c08-4c48-82d9-5fa7fe40a7b1`, on Kingston serial `152D20337A0C`, model `KINGSTON SA400S37240G`, USB transport and G:. The coordinator requires the VM OFF, zero virtual NICs, the pinned G: NTFS volume and exact storage mapping, and exactly the eleven reviewed canonical paths with expected file/directory types and no reparse ancestry. It derives the paths internally and rejects aliases or duplicates.

The one-use request is bounded, create-new, and treated as hostile input. PR #49's requester/coordinator identity checks and administrator-owned four-ACE result mailbox are reused. The request cannot select commands or paths. Raw ACL text stays in protected evidence outside G:; only sanitized per-object comparisons and digests leave the host.

The coordinator invokes the system `icacls.exe` once per target, without recursive or ACL-changing switches. Each process has a fixed stream cap and timeout; the coordinator has an absolute deadline. Output must be completely drained, hashes and actual exit values retained, and cleanup confirmed. The standard launcher validates the returned mailbox, identity pair, source/baseline pins, exact 11-object set, per-file hashes and final integrity hash. A mismatch is reported as `MISMATCH`; unresolved output semantics remain `INDETERMINATE`.

## Component reuse and new pieces

- Reuse PR #49's protected mailbox, identity-pair, source/baseline, bounded-file, no-reparse and create-new protocols.
- Reuse PR #50's exact path builder, pin validator, `icacls` command builder, bounded stream reader, parser, comparator, and evidence writer.
- Add the closed host launcher, protected coordinator entrypoint, runtime module, external release-manifest contract, and PS 5.1 synthetic runtime integration suite.
- Test hooks exist only as private module state; no production CLI or environment override exposes them.

## Acceptance gates and failures

| Gate | Required evidence | Failure result |
|---|---|---|
| Package trust | Protected installed package and manifest, exact source/baseline digests | `SOURCE_OR_BASELINE_PIN_MISMATCH` |
| One human approval | At most one UAC start, expected requester/admin identity pair | `UAC_CANCELLED` or `IDENTITY_MISMATCH`; no retry |
| Fresh preflight | Exact VM OFF/zero-NIC, Kingston serial/model/USB/health, G: mapping, eleven path/type checks | `PREFLIGHT_FAILED`; zero `icacls` reads |
| Command set | Exactly eleven system `icacls` calls with canonical targets and no mutation switches | `SCOPE_OR_COMMAND_FAILURE` |
| Process lifecycle | Actual exits, complete bounded streams, per-call and overall deadlines, cleanup | `PROCESS_INCOMPLETE` |
| Evidence | Protected off-G mailbox, create-new files, exact record count and hashes, postflight match | `MAILBOX_OR_INTEGRITY_FAILURE` |
| Comparison | Per-object `PASS`, `MISMATCH`, or `INDETERMINATE` | Never infer `PASS_RESTRICTIVE_ACL` |

## Synthetic validation and limits

Windows PowerShell 5.1 tests cover the successful eleven-object flow; source tampering; protected ACL-profile acceptance/rejection; VM/storage mismatch before reads; non-administrator rejection; UAC cancellation; incomplete output; timeout; cleanup failure; wrapper argument rejection; and mailbox/result hash and count checks. Existing suites separately exercise parser adversaries, stream-pipe hangs, bounded process capture, and protocol mailbox failures. These fixtures simulate the UAC boundary; they do not prove a real elevated launch, live token visibility, live VM/SSD identity, actual `icacls` output, or effective ACL permissions.

## Separate owner gates

1. Independent review and Windows CI of the final exact source SHA.
2. Fresh explicit authorization to install the protected package and release manifest on C: with the exact paths and ACLs in this document. No G: writes are involved.
3. After installation review, fresh explicit authorization for one bounded live read-only collection and one UAC consent. The live result still requires independent ACL review. Any ACL remediation needs separate design/review and authorization.

The threat model trusts the local administrator, Windows kernel/VMMS, system `icacls.exe`, and the approved protected package location. It cannot rule out a trusted administrator changing the VM between observations; observed drift fails closed, while an unobserved start-and-stop between checks remains a residual race.
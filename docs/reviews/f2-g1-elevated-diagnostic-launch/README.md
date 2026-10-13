# F2 G1 historical manifest diagnostic launch plan

## Decision requested

Review this source-only launch boundary for a possible single, owner-consented, elevated execution of the historical manifest diagnostic. The command is published in `EXACT_UAC_COMMAND.txt`; it was not run. This package does not authorize UAC or claim that the historical elevated failure has been reproduced or explained.

The historical diagnostic wrapper/module and all historical input pins remain fixed. The launch package verifies the wrapper and launch modules by exact Windows checkout-byte SHA-256, reads each executable input through a bounded read-only stream, and creates the PowerShell script blocks from the same verified in-memory bytes. The original diagnostic module at `F2HistoricalManifestDiagnostic.psm1` is unchanged.

## Immutable source lineage

- Review base: PR #68 HEAD `c3d1280f9905730eda8cff40865e8afbbb642367`.
- Source implementation commit: `8c2bddd90c6ac5214eeed08b5648d0ef30b58bf4` (parent is `606cddfe8d8c0912093810c22b3cd9692`; that implementation commit's parent is the review base).
- The final review package adds documentation and the encoded command after that code commit. At execution time, the fixed launch checkout must be clean at the source implementation commit above; a later documentation-only commit is not accepted by the launch gate.
- Fixed launch checkout path: `C:\Dev\f2-g1-diagnostic-elevation-plan-source`.
- Fixed historical source checkout: `C:\Dev\f2-g1-protected-updater-source`, commit `396c44965c90c08292ad2835f8317e81b6b9daaf`.
- Fixed historical candidate checkout: `C:\Dev\f2-g1-protected-updater`, commit `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d`.
- All three repositories must have the exact repository origin, clean status, canonical fixed path, and no reparse point in the path chain.

## Execution overview

```mermaid
sequenceDiagram
    participant O as Owner in standard cmd.exe
    participant B as Encoded outer bootstrap
    participant R as Verified requester launcher
    participant P as One-shot local named pipe
    participant E as UAC elevated child
    participant G as Pinned Git read-only queries
    participant H as Historical parser-only diagnostic
    O->>B: Run exact reviewed -EncodedCommand
    B->>B: Set system-only PSModulePath; validate PS 5.1, token, checkout, module bytes
    B->>R: Invoke ScriptBlock built from verified launcher bytes
    R->>R: Recheck repos, fixed inputs, hashes, token and reparse paths
    R->>P: Create random first-instance local pipe with protected DACL
    R->>E: One Start-Process -Verb RunAs after all gates pass
    E->>P: Connect; bind server PID/time/SID and elevated token
    E->>G: Read-only origin, HEAD, top-level and clean-status checks
    E->>H: Run exact manifest parse and ReviewedCommitSha comparison
    H-->>E: Bounded sanitized diagnostic JSON
    E-->>P: Nonce-bound framed response and child exit status
    P-->>R: Validate exact schema, child identity, hashes and exit agreement
    R-->>O: Sanitized result; never an installation-success claim
```

The native helper is limited to creating/authenticating the local pipe, reading token/process identity, and running the four fixed Git queries with bounded output and deadlines. It does not contain a file, registry, ACL, VM, disk, or process-launch write API. The only child process created by the helper is the hash-pinned Git executable; the one elevation site is the single `Start-Process -Verb RunAs` in the requester launcher.

## Review files

- `OUTER_BOOTSTRAP.ps1` is the exact UTF-16LE `-EncodedCommand` source.
- `EXACT_UAC_COMMAND.txt` is the complete copyable Windows PowerShell 5.1 invocation. It is proposed only and was not executed.
- `SECURITY_BOUNDARIES.md` documents trust assumptions, output/timeout behavior and unverified real-UAC conditions.
- `VALIDATION_RESULTS.md` records the non-elevated Windows PowerShell 5.1 suites and source-only host input checks.
- `DEVELOPER_HANDOFF.md` follows the repository handoff template.
- `FILE_SHA256_MANIFEST.txt` hashes every review-package file except itself using actual Windows checkout bytes.

## Historical pins preserved

| Input | Pin |
|---|---|
| Historical source commit | `396c44965c90c08292ad2835f8317e81b6b9daaf` |
| Historical candidate commit | `7f99bc10f3e2258d2340cea4e7ba1352022cbb6d` |
| Candidate manifest | `b8596905f42ee429ae2fd3352f9133de8bd4f00da654f856012c02390661f022` |
| Historical updater source | `d9572f7ea113ab01eaa4c6ab98d0852ce9549642b083719f68c01f02b2a81bb2` |
| Historical launcher source | `9fc4d574eda4a03ee05bca5ce789bdb10ee0b05f5f6de273839ba0060445bdc9` |
| Historical diagnostic protocol | `66466fd15ce161fe2b522c77cfd6500845012480fc64890aa8435f54197eedc7` |
| Reviewed diagnostic module | `4541338491269ac2bf409c5ba0c63d93d6a5e3fd9896c9d378c79dbea43ee7ee` |

The exact executable byte chain (SHA-256 over Windows checkout bytes) is:

| File | SHA-256 |
|---|---|
| `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnostic.ps1` | `99505626679c75511e16d524c39dfd0ff0cbd27b3a0bd36d631cbadf2c1c9536` |
| `scripts/f2-acl/F2HistoricalManifestLaunch.psm1` | `ec40adb78eb54c1e6df92ca6ce142b85fe71e98340c30f185fc506e37a744432` |
| `scripts/f2-acl/Invoke-F2HistoricalManifestDiagnosticChild.ps1` | `1c7706d65267c578d5d2a76e93cb9dd99f3d4d3b6681a5e83341b991512d3baa` |
| `scripts/f2-acl/Start-F2HistoricalManifestDiagnostic.ps1` | `a314696562b3b3fd4fbb0785d06bb6c243450c69282a48c9a73ff008d05ff258` |
| `docs/reviews/f2-g1-elevated-diagnostic-launch/OUTER_BOOTSTRAP.ps1` | `f3531c7ecca4b2b9ac331803feef954597ac125adf07508f63b58b80ac800fc5` |
| Pinned Git executable | `7b7971dd13f0c3a284e538601f2f9770b3a87dfaccb5fb52d68141c67ed22364` |

The expected original baseline mailbox ID, payload `CaptureId`, payload digest and integrity digest remain the distinct values already pinned in the reviewed diagnostic module; no retained baseline is read or changed by these source-only tests.

## Outcome semantics

`Status=PASS` means only that the fixed candidate bytes parsed and the reviewed source commit comparison completed under this diagnostic context. It does not prove that the previous elevated updater failure is explained, that ACLs are acceptable, or that any installation/update succeeded. A missing or invalid pipe record, nonzero or conflicting child exit, timeout, source mismatch, alternate UAC identity, or output-bound failure is a failure. No retries are automatic.

## Independent review focus

Review the in-memory byte-to-ScriptBlock chain, fixed path/hash checks, command and API allowlists, process/PID/time/token bindings, pipe ACL and framing, failure classification, and the explicit real-UAC unknowns. Keep all PRs draft and unmerged.
